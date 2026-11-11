import Foundation

/// The tools FineText exposes over MCP. Every rewrite goes through the same humanization loop and
/// AI detector as the menu bar app, so clients get the scored, humanized result.
@MainActor final class MCPTools {
  struct Outcome {
    var payload: [String: Any]
    var text: String
    var isError: Bool
    var logText: String { isError ? text : MCPServer.pretty(payload["structuredContent"] ?? payload) }
  }

  struct Failure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
  }

  private let workspace: Workspace
  private var presets: PresetStore { workspace.presets }
  private var preferences: Preferences { workspace.preferences }
  private var providers: ProviderStore { workspace.providers }

  init(workspace: Workspace) {
    self.workspace = workspace
  }

  static let instructions = """
  FineText rewrites text with a preset (template) and then humanizes it over several rounds, scoring each round \
  with a local AI-text detector until the target score is reached. Call list_templates to find a template id \
  (for example emailSend for an email with subject and body fields) and list_models to pick a model. \
  Use rewrite to write a fresh draft from your text, or humanize to only humanize text you already have. \
  Results include the AI score (0–100, the detector's confidence that the text is AI-written; lower is more human).
  """

  // MARK: Definitions

  private static let humanizationSchema: [String: Any] = [
    "type": "object",
    "description": "Overrides FineText's humanizer settings for this call. Omit to use the app's settings.",
    "properties": [
      "mode": ["type": "string", "enum": ["off", "manual", "automatic"],
               "description": "off: no humanization rounds. manual: a fixed number of rounds. automatic: humanize until the AI score reaches target_score (needs a downloaded detector)."],
      "rounds": ["type": "integer", "minimum": 1, "maximum": 10, "description": "Rounds for manual mode."],
      "target_score": ["type": "number", "minimum": 0, "maximum": 100, "description": "Target AI score for automatic mode."],
      "engine": ["type": "string", "enum": ["translation", "rewrite_model"],
                 "description": "translation: local round-trip translation. rewrite_model: the selected model edits each round (uses provider credits)."],
    ],
  ]

  private static let textProperties: [String: Any] = [
    "text": ["type": "string", "description": "The text to work on. For templates with fields you may pass `fields` instead."],
    "fields": ["type": "object", "additionalProperties": ["type": "string"],
               "description": "Field values for templates with fields, e.g. {\"subject\": \"…\", \"body\": \"…\"} for emailSend."],
    "template_id": ["type": "string", "description": "A template id from list_templates. Omit for general writing."],
    "tone": ["type": "string", "enum": Tone.allCases.map(\.rawValue), "description": "Defaults to the template's tone."],
    "model": ["type": "string", "description": "A model id from list_models. Defaults to the model last used for rewriting."],
    "instructions": ["type": "string", "description": "Extra rules applied after the template's guidelines."],
    "context": ["type": "string", "description": "Reference facts the writer may use (e.g. about the recipient). Never copied verbatim."],
    "preserve_placeholders": ["type": "boolean",
                              "description": "Keep every {{ … }} template placeholder exactly. Humanization rounds that lose one are discarded. Use when rewriting a reusable template."],
    "humanization": humanizationSchema,
  ]

  private static let resultSchema: [String: Any] = [
    "type": "object",
    "properties": [
      "text": ["type": "string"],
      "plain_text": ["type": "string"],
      "fields": ["type": "object", "additionalProperties": ["type": "string"]],
      "initial_ai_score": ["type": ["number", "null"]],
      "final_ai_score": ["type": ["number", "null"]],
      "target_ai_score": ["type": ["number", "null"]],
      "detector": ["type": ["string", "null"]],
      "rounds": ["type": "integer"],
      "model": ["type": "string"],
      "template_id": ["type": ["string", "null"]],
      "note": ["type": ["string", "null"]],
      "missing_placeholders": ["type": "array", "items": ["type": "string"]],
      "cost_usd": ["type": ["number", "null"]],
    ],
    "required": ["text", "plain_text", "rounds", "model"],
  ]

  static let definitions: [[String: Any]] = [
    [
      "name": "list_templates",
      "title": "List templates",
      "description": "Lists FineText's rewrite templates: cloud presets (nested menus flattened into paths) and the user's custom presets.",
      "inputSchema": ["type": "object", "properties": [
        "include_guidelines": ["type": "boolean", "description": "Include each template's rendered guidelines."],
      ]],
      "annotations": ["readOnlyHint": true],
    ],
    [
      "name": "list_models",
      "title": "List models",
      "description": "Lists the text models FineText can rewrite with (providers, Codex, Claude Code and local MLX models).",
      "inputSchema": ["type": "object", "properties": [:]],
      "annotations": ["readOnlyHint": true],
    ],
    [
      "name": "rewrite",
      "title": "Rewrite and humanize",
      "description": "Writes a fresh draft from the text with the agent and the template's guidelines, then humanizes it over several rounds and returns the result with its AI scores.",
      "inputSchema": ["type": "object", "properties": textProperties],
      "outputSchema": resultSchema,
    ],
    [
      "name": "humanize",
      "title": "Humanize",
      "description": "Humanizes existing text over several rounds (no fresh draft) and returns the result with its AI scores.",
      "inputSchema": ["type": "object", "properties": textProperties],
      "outputSchema": resultSchema,
    ],
    [
      "name": "score_text",
      "title": "AI score",
      "description": "Scores text with FineText's local AI detector (0–100; lower reads as more human). English prose of at least 50 words.",
      "inputSchema": ["type": "object", "properties": ["text": ["type": "string"]], "required": ["text"]],
      "annotations": ["readOnlyHint": true],
    ],
  ]

  // MARK: Calls

  func call(_ name: String, arguments: [String: Any], progress: @escaping @MainActor (String) -> Void) async -> Outcome {
    do {
      let structured: [String: Any]
      switch name {
      case "list_templates": structured = listTemplates(includeGuidelines: arguments["include_guidelines"] as? Bool ?? false)
      case "list_models": structured = listModels()
      case "rewrite": structured = try await rewrite(arguments, rewriteFirst: true, progress: progress)
      case "humanize": structured = try await rewrite(arguments, rewriteFirst: false, progress: progress)
      case "score_text": structured = try await score(arguments, progress: progress)
      default: throw Failure(message: "Unknown tool: \(name)")
      }
      let json = MCPServer.pretty(structured)
      return Outcome(payload: ["content": [["type": "text", "text": json]], "structuredContent": structured, "isError": false],
                     text: json, isError: false)
    } catch is CancellationError {
      return Self.failure("Cancelled")
    } catch let error as URLError where error.code == .cancelled {
      return Self.failure("Cancelled")
    } catch {
      return Self.failure(error.localizedDescription)
    }
  }

  private static func failure(_ message: String) -> Outcome {
    Outcome(payload: ["content": [["type": "text", "text": message]], "isError": true], text: message, isError: true)
  }

  private func listTemplates(includeGuidelines: Bool) -> [String: Any] {
    var templates: [[String: Any]] = presets.entries.map { entry in
      var item: [String: Any] = [
        "id": entry.id,
        "kind": "preset",
        "title": entry.path.map(\.english).joined(separator: " · "),
        "path": entry.path.map(\.english),
        "prompt_title": entry.preset.promptTitle,
        "default_tone": preferences.tone(for: entry.preset).rawValue,
      ]
      if let limit = entry.preset.characterLimit { item["character_limit"] = limit }
      if let fields = entry.preset.fields {
        item["fields"] = fields.map { ["id": $0.id, "label": $0.label.english, "multiline": $0.multiline] }
      }
      if includeGuidelines {
        item["guidelines"] = PresetSnapshot(entry).guidelines(tone: preferences.tone(for: entry.preset), appLanguage: "en")
      }
      return item
    }
    templates += preferences.customPlatforms.map { platform in
      var item: [String: Any] = [
        "id": platform.id.uuidString,
        "kind": "custom",
        "title": (platform.folderPath + [platform.name]).joined(separator: " · "),
        "path": platform.folderPath + [platform.name],
        "prompt_title": platform.name,
        "default_tone": Tone.natural.rawValue,
      ]
      if includeGuidelines { item["guidelines"] = platform.instruction }
      return item
    }
    return ["templates": templates, "catalog_version": presets.catalog.version]
  }

  private func availableTextModels() -> [ModelRef] {
    var ids = providers.providers.map(\.id)
    if providers.codex != nil { ids.append(ProviderStore.codexProvider.id) }
    if providers.claudeCode != nil { ids.append(ProviderStore.claudeCodeProvider.id) }
    if providers.flowcy.isSignedIn { ids.append(ProviderStore.flowcyProvider.id) }
    ids.append(Provider.localID)
    return ids.flatMap { id in providers.models(for: id, kind: .text).map { ModelRef(providerID: id, modelID: $0.id) } }
  }

  private func listModels() -> [String: Any] {
    let fallback = defaultModel()
    let models: [[String: Any]] = availableTextModels().map { ref in
      [
        "id": Self.encode(ref),
        "name": providers.displayName(ref),
        "provider": ref.isLocal ? Provider.localName : (providers.provider(ref.providerID)?.name ?? ""),
        "model": ref.modelID,
        "default": ref == fallback,
      ]
    }
    var result: [String: Any] = ["models": models]
    if let fallback { result["default_model"] = Self.encode(fallback) }
    return result
  }

  private func defaultModel() -> ModelRef? {
    if let last = preferences.lastModel(.rewrite), providers.isAvailable(last) { return last }
    return availableTextModels().first
  }

  static func encode(_ ref: ModelRef) -> String { ref.providerID.uuidString + ":" + ref.modelID }

  private static func decode(_ value: String) -> ModelRef? {
    guard let colon = value.firstIndex(of: ":"), let provider = UUID(uuidString: String(value[..<colon])) else { return nil }
    let model = String(value[value.index(after: colon)...])
    return model.isEmpty ? nil : ModelRef(providerID: provider, modelID: model)
  }

  private func rewrite(_ arguments: [String: Any], rewriteFirst: Bool, progress: @escaping @MainActor (String) -> Void) async throws -> [String: Any] {
    var preset: PresetEntry?
    var custom: CustomPlatform?
    if let templateID = (arguments["template_id"] as? String)?.trimmed, !templateID.isEmpty {
      if let entry = presets.entry(id: templateID) {
        preset = entry
      } else if let platform = preferences.customPlatforms.first(where: { $0.id.uuidString.caseInsensitiveCompare(templateID) == .orderedSame }) {
        custom = platform
      } else {
        throw Failure(message: "Unknown template_id \"\(templateID)\". Call list_templates for the available ids.")
      }
    }
    let fields = preset?.preset.fields
    var text = (arguments["text"] as? String) ?? ""
    if let values = arguments["fields"] as? [String: Any] {
      guard let fields else { throw Failure(message: "`fields` needs a template with fields, such as emailSend.") }
      text = StructuredOutput.compose(values.compactMapValues { $0 as? String }, fields: fields)
    }
    guard !text.trimmed.isEmpty else { throw Failure(message: "Pass `text` (or `fields`) to rewrite.") }

    let model: ModelRef
    if let requested = arguments["model"] as? String, !requested.trimmed.isEmpty {
      guard let ref = Self.decode(requested.trimmed), providers.isAvailable(ref) else {
        throw Failure(message: "Model \"\(requested)\" is not available. Call list_models for the available ids.")
      }
      model = ref
    } else {
      guard let fallback = defaultModel() else { throw Failure(message: "No text model is set up in FineText. Add a provider in Settings → Providers.") }
      model = fallback
    }

    var tone: Tone?
    if let raw = arguments["tone"] as? String, !raw.isEmpty {
      guard let value = Tone(rawValue: raw) else { throw Failure(message: "Unknown tone \"\(raw)\".") }
      tone = value
    }

    var options = HumanizationOptions.fromDefaults()
    if let overrides = arguments["humanization"] as? [String: Any] {
      if let raw = overrides["mode"] as? String {
        guard let mode = HumanizationMode(rawValue: raw) else { throw Failure(message: "Unknown humanization mode \"\(raw)\".") }
        options.mode = mode
      }
      if let rounds = overrides["rounds"] as? Int { options.rounds = min(10, max(1, rounds)) }
      if let target = overrides["target_score"] as? Double { options.target = min(100, max(0, target)) }
      switch overrides["engine"] as? String {
      case "translation": options.engine = .translateGemma
      case "rewrite_model": options.engine = .rewriteModel
      default: break
      }
    }
    options.extraGuidance = arguments["instructions"] as? String
    options.context = arguments["context"] as? String
    let preserve = arguments["preserve_placeholders"] as? Bool ?? false
    if preserve {
      let source = text
      options.extraGuidance = [options.extraGuidance, """
      The text is a reusable template. Keep every {{ … }} placeholder and template action exactly as written, \
      character for character, and never replace one with a concrete value.
      """].compactMap { $0?.trimmed }.filter { !$0.isEmpty }.joined(separator: "\n")
      options.accepts = { TemplatePlaceholders.missing(from: $0, original: source).isEmpty }
    }

    let id = UUID()
    progress(rewriteFirst ? "Rewriting with \(providers.displayName(model))" : "Humanizing")
    let watcher = Task { [weak workspace] in
      var last = ""
      while !Task.isCancelled {
        if case .running(let status) = workspace?.status(id), status != last {
          last = status
          progress(status)
        }
        try? await Task.sleep(for: .milliseconds(250))
      }
    }
    defer { watcher.cancel() }
    let item = try await workspace.runExternal(
      ExternalRewrite(text: text, preset: preset, customPlatform: custom, tone: tone, model: model, rewriteFirst: rewriteFirst, options: options),
      id: id
    )
    try Task.checkCancellation()

    var result: [String: Any] = [
      "text": item.output,
      "plain_text": item.plainOutput,
      "rounds": item.humanizationRounds,
      "model": Self.encode(model),
      "model_name": providers.displayName(model),
      "tone": item.tone.rawValue,
      "initial_ai_score": item.initialAIScore ?? NSNull(),
      "final_ai_score": item.finalAIScore ?? NSNull(),
      "target_ai_score": item.targetAIScore ?? NSNull(),
      "detector": item.detectorEngineRaw.flatMap(AIDetectorEngine.init(rawValue:))?.name ?? NSNull(),
      "template_id": preset?.id ?? custom?.id.uuidString ?? NSNull(),
      "note": item.note ?? NSNull(),
      "cost_usd": workspace.cost(for: id).knownTotal ?? NSNull(),
    ]
    if let fields, let values = StructuredOutput.parse(item.output, fields: fields) { result["fields"] = values }
    if item.isGrammar {
      result["corrections"] = GrammarMarkup.fixes(in: item.output).map { fix in
        ["original": fix.original, "replacement": fix.replacement, "reason": fix.reason, "alternatives": fix.alternatives] as [String: Any]
      }
    }
    if preserve { result["missing_placeholders"] = TemplatePlaceholders.missing(from: item.output, original: text) }
    return result
  }

  private func score(_ arguments: [String: Any], progress: @MainActor (String) -> Void) async throws -> [String: Any] {
    let text = (arguments["text"] as? String) ?? ""
    let detector = AIDetectorEngine.selected
    guard detector != .disabled else { throw Failure(message: "No AI detector is selected. Choose one in FineText → Settings → Humanizer.") }
    progress("Checking AI score with \(detector.name)")
    let value = try await AIDetector.shared.score(text, engine: detector)
    return ["score": value, "detector": detector.name]
  }
}
