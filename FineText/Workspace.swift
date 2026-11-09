import AppKit
import Foundation
import SwiftData

enum Route: Hashable {
  case rewrite(UUID), translation(UUID), image(UUID), history
}

enum WorkTab: String, CaseIterable, Identifiable {
  case rewrite = "Rewrite", translate = "Translate", image = "Image"
  var id: String { rawValue }
  var title: String {
    switch self {
    case .rewrite: LocalizableKey.rewrite.string
    case .translate: LocalizableKey.translate.string
    case .image: LocalizableKey.image.string
    }
  }
}

/// Owns the current session and runs the AI jobs. Runtime status lives here; results live in SwiftData.
@MainActor @Observable final class Workspace {
  let context: ModelContext
  let providers: ProviderStore
  let preferences: Preferences

  private(set) var session: RefinementSession
  var tab: WorkTab = .rewrite
  var route: Route?
  var toast: Toast?
  private(set) var statuses: [UUID: JobStatus] = [:]
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var taskTokens: [UUID: UUID] = [:]
  private var toastTask: Task<Void, Never>?

  init(container: ModelContainer, providers: ProviderStore, preferences: Preferences) {
    context = container.mainContext
    self.providers = providers
    self.preferences = preferences
    var descriptor = FetchDescriptor<RefinementSession>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    descriptor.fetchLimit = 1
    if let latest = try? context.fetch(descriptor).first {
      session = latest
    } else {
      let fresh = RefinementSession()
      context.insert(fresh)
      session = fresh
    }
  }

  // MARK: Session

  var originalText: String {
    get { session.originalText }
    set {
      session.originalText = newValue
      touch()
    }
  }

  private func touch() {
    session.updatedAt = .now
  }

  func save() {
    try? context.save()
  }

  /// Starts a new empty session. The previous one stays in History unless it was empty.
  func clear() {
    cancelAll()
    if session.isEmpty { context.delete(session) }
    let fresh = RefinementSession()
    context.insert(fresh)
    session = fresh
    route = nil
    save()
    flash(LocalizableKey.cleared.string, symbol: "sparkles")
  }

  func open(_ other: RefinementSession) {
    guard other.id != session.id else { route = nil; return }
    cancelAll()
    if session.isEmpty { context.delete(session) }
    session = other
    touch()
    route = nil
    save()
  }

  func deleteSession(_ other: RefinementSession) {
    if other.id == session.id {
      cancelAll()
      let fresh = RefinementSession()
      context.insert(fresh)
      session = fresh
    }
    context.delete(other)
    save()
    flash(LocalizableKey.sessionDeleted.string, symbol: "trash")
  }

  private func cancelAll() {
    taskTokens.removeAll()
    tasks.values.forEach { $0.cancel() }
    tasks.removeAll()
    statuses.removeAll()
  }

  func status(_ id: UUID) -> JobStatus { statuses[id] ?? .idle }

  // MARK: Toast

  func flash(_ message: String, symbol: String, isError: Bool = false) {
    isError ? Haptics.failure() : Haptics.success()
    toast = Toast(message: message, symbol: symbol, isError: isError)
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(for: .seconds(1.6))
      if !Task.isCancelled { toast = nil }
    }
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    flash(LocalizableKey.copiedToClipboard.string, symbol: "doc.on.doc")
  }

  // MARK: Add

  @discardableResult
  func addRewrite(platform: Platform, model: ModelRef) -> RewriteItem {
    preferences.remember(platform: platform)
    preferences.remember(model, for: .rewrite)
    let item = RewriteItem(platform: platform, tone: preferences.tone(for: platform), model: model)
    session.rewrites.append(item)
    touch()
    Haptics.tap()
    return item
  }

  @discardableResult
  func addRewrite(customPlatform: CustomPlatform, model: ModelRef) -> RewriteItem {
    preferences.remember(customPlatform: customPlatform)
    preferences.remember(model, for: .rewrite)
    let item = RewriteItem(platform: .message, tone: .natural, model: model)
    item.customPlatformID = customPlatform.id
    item.customPlatformName = customPlatform.name
    item.customPlatformInstruction = customPlatform.instruction
    item.tone = preferences.tone(for: item)
    session.rewrites.append(item)
    touch()
    save()
    Haptics.tap()
    return item
  }

  @discardableResult
  func addTranslation(language: Language, model: ModelRef, source: UUID?) -> TranslationItem {
    preferences.remember(language: language)
    preferences.remember(model, for: .translate)
    let item = TranslationItem(language: language, model: model, sourceRewriteID: source)
    session.translations.append(item)
    touch()
    Haptics.tap()
    return item
  }

  @discardableResult
  func addImage(model: ModelRef) -> ImageItem {
    preferences.remember(model, for: .image)
    let item = ImageItem(model: model)
    session.images.append(item)
    touch()
    Haptics.tap()
    return item
  }

  func remove(_ item: any PersistentModel, id: UUID) {
    tasks[id]?.cancel()
    tasks[id] = nil
    taskTokens[id] = nil
    statuses[id] = nil
    if route != nil { route = nil }
    context.delete(item)
    touch()
    save()
    flash(LocalizableKey.removed.string, symbol: "trash")
  }

  func stop(_ id: UUID) {
    tasks[id]?.cancel()
    tasks[id] = nil
    taskTokens[id] = nil
    statuses[id] = .idle
    save()
  }

  // MARK: Run

  func runAll() {
    switch tab {
    case .rewrite: session.sortedRewrites.forEach(run)
    case .translate: session.sortedTranslations.forEach(run)
    case .image: session.sortedImages.forEach(run)
    }
  }

  var canRunAll: Bool {
    guard !originalText.trimmed.isEmpty else { return false }
    switch tab {
    case .rewrite: return !session.rewrites.isEmpty
    case .translate: return !session.translations.isEmpty
    case .image: return !session.images.isEmpty
    }
  }

  var isRunningAny: Bool { statuses.values.contains { $0.isRunning } }

  private func start(_ id: UUID, _ work: @escaping @MainActor () async throws -> Void) {
    tasks[id]?.cancel()
    let token = UUID()
    taskTokens[id] = token
    statuses[id] = .running(LocalizableKey.starting.string)
    tasks[id] = Task {
      do {
        try await work()
        try Task.checkCancellation()
        guard taskTokens[id] == token else { return }
        statuses[id] = .done
        save()
      } catch is CancellationError {
        if taskTokens[id] == token { statuses[id] = .idle }
      } catch let error as URLError where error.code == .cancelled {
        if taskTokens[id] == token { statuses[id] = .idle }
      } catch {
        if taskTokens[id] == token { statuses[id] = .failed(error.localizedDescription) }
      }
      if taskTokens[id] == token { tasks[id] = nil; taskTokens[id] = nil; save() }
    }
  }

  func run(_ item: RewriteItem) {
    let text = originalText.trimmed
    guard !text.isEmpty else { return flash(LocalizableKey.addYourOriginalPostFirst.string, symbol: "exclamationmark.triangle", isError: true) }
    let id = item.id
    let messages = Prompts.rewrite(text, platform: item.platform, tone: item.tone, customName: item.customPlatformName, customInstruction: item.customPlatformInstruction)
    preferences.setTone(item.tone, for: item)
    let model = item.model
    start(id) {
      item.refinementSource = text
      item.output = ""
      item.note = nil
      item.initialAIScore = nil
      item.finalAIScore = nil
      item.targetAIScore = nil
      item.detectorEngineRaw = nil
      item.aiScoredText = nil
      item.humanizationRounds = 0
      let raw = try await self.chat(model, messages: messages, id: id, status: LocalizableKey.rewriting.string) { delta in item.output += delta }
      try Task.checkCancellation()
      item.output = Prompts.clean(raw)
      try await self.humanize(item, id: id)
    }
  }

  /// Streams a chat completion from a remote provider, from Codex, or from a downloaded MLX model on this Mac.
  private func chat(
    _ model: ModelRef, messages: [ChatMessage], id: UUID, status: String, onDelta: @MainActor @Sendable @escaping (String) -> Void
  ) async throws -> String {
    if providers.isCodex(model) || providers.isClaudeCode(model) {
      let client = try providers.agentClient(for: model)
      return try await AgentTextSession.chat(
        client: client, messages: messages, model: CLIModels.explicitModel(model.modelID), status: status,
        onStatus: { [weak self] in self?.statuses[id] = .running($0) }, onDelta: onDelta
      )
    }
    guard model.isLocal else {
      let client = try providers.client(for: model)
      statuses[id] = .running(status)
      return try await client.streamChat(model: model.modelID, messages: messages, onDelta: onDelta)
    }
    guard providers.local.isInstalled(model.modelID) else {
      throw APIError.http(0, LocalizableKey.modelNotDownloaded.format(providers.displayName(model)))
    }
    statuses[id] = .running(status)
    return try await LocalLLM.shared.streamChat(
      model: model.modelID, messages: messages,
      onLoading: { [weak self] in self?.statuses[id] = .running(LocalizableKey.loadingModel.string) },
      onDelta: { [weak self] delta in
        if self?.statuses[id] != .running(status) { self?.statuses[id] = .running(status) }
        onDelta(delta)
      }
    )
  }

  private func humanize(_ item: RewriteItem, id: UUID) async throws {
    let defaults = UserDefaults.standard
    let mode = HumanizationMode.selected(in: defaults)
    let rounds = defaults.integer(forKey: DefaultsKey.humanizeRounds)
    let engine = HumanizationEngine(rawValue: defaults.string(forKey: DefaultsKey.humanizationEngine) ?? "") ?? .translateGemma
    let detector = AIDetectorEngine.selected
    let configuredTarget = defaults.double(forKey: DefaultsKey.targetAIScore)
    let target = configuredTarget.isFinite ? min(100, max(0, configuredTarget)) : 20
    let pivot = Language.named(code: defaults.string(forKey: DefaultsKey.pivotLanguage) ?? Language.japanese.code)
    let translationModel = TranslationModel.fromDefaults()
    let rewriteModel = item.model
    var scoring: (@MainActor (String) async throws -> Double)?
    do {
      if detector != .disabled {
        do {
          try AIDetector.validate(item.output)
          guard await AIDetector.shared.isInstalled(detector) else { throw AIDetectorError.notReady }
          scoring = { [weak self] text in
            try Task.checkCancellation()
            self?.statuses[id] = .running(LocalizableKey.checkingAIScore.string)
            return try await AIDetector.shared.score(text, engine: detector)
          }
        } catch {
          if mode == .automatic { throw error }
          item.note = LocalizableKey.detectorUnavailable.format(error.localizedDescription)
        }
      }
      if mode == .automatic, scoring == nil { throw AIDetectorError.notReady }
      item.targetAIScore = mode == .automatic ? target : nil
      item.detectorEngineRaw = scoring == nil ? nil : detector.rawValue
      _ = try await HumanizationLoop.run(
        text: item.output, mode: mode, rounds: max(1, rounds), target: target, score: scoring,
        refine: { [weak self] text, round in
          guard let self else { throw CancellationError() }
          try Task.checkCancellation()
          let status = LocalizableKey.humanizingRound.format(round)
          self.statuses[id] = .running(status)
          if engine == .translateGemma {
            guard await TranslationEngine.shared.isInstalled(translationModel) else {
              throw MLXHubError.notDownloaded
            }
            return try await TranslationEngine.shared.humanize(text, rounds: 1, pivot: pivot, model: translationModel) { _ in }
          }
          let messages = Prompts.humanize(text, source: item.refinementSource ?? self.originalText, item: item)
          let raw = try await self.chat(rewriteModel, messages: messages, id: id, status: status) { _ in }
          return Prompts.clean(raw)
        },
        update: { [weak self] result in
          if result.rounds == 0 { item.initialAIScore = result.score }
          item.output = result.text
          item.finalAIScore = result.score
          item.aiScoredText = result.score == nil ? nil : result.text
          item.humanizationRounds = result.rounds
          self?.save()
        }
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch let error as URLError where error.code == .cancelled {
      throw CancellationError()
    } catch {
      try Task.checkCancellation()
      item.note = LocalizableKey.humanizationStopped.format(error.localizedDescription)
    }
  }

  func sourceText(for item: TranslationItem) -> String {
    if let rewriteID = item.sourceRewriteID, let rewrite = session.rewrites.first(where: { $0.id == rewriteID }) {
      return rewrite.output
    }
    return originalText
  }

  func sourceTitle(for item: TranslationItem) -> String {
    if let rewriteID = item.sourceRewriteID, let rewrite = session.rewrites.first(where: { $0.id == rewriteID }) {
      return LocalizableKey.sourceRewrite.format(rewrite.platformTitle)
    }
    return LocalizableKey.original.string
  }

  func run(_ item: TranslationItem) {
    let text = sourceText(for: item).trimmed
    guard !text.isEmpty else { return flash(LocalizableKey.nothingToTranslateYet.string, symbol: "exclamationmark.triangle", isError: true) }
    let id = item.id
    let messages = Prompts.translate(text, to: item.language)
    let model = item.model
    let status = LocalizableKey.translatingTo.format(item.language.localizedName)
    start(id) {
      item.output = ""
      let raw = try await self.chat(model, messages: messages, id: id, status: status) { delta in item.output += delta }
      item.output = Prompts.clean(raw)
    }
  }

  /// How a transparent background is achieved for this item's model.
  func backgroundMode(for item: ImageItem) -> BackgroundMode {
    guard item.transparentBackground else { return .opaque }
    let native = providers.isCodex(item.model) || BackgroundMode.supportsNativeTransparency(modelID: item.modelID)
    return native ? .native : .greenScreen
  }

  func run(_ item: ImageItem) {
    let text = originalText.trimmed
    guard !text.isEmpty || !item.instruction.trimmed.isEmpty else {
      return flash(LocalizableKey.addAPostOrAnInstructionFirst.string, symbol: "exclamationmark.triangle", isError: true)
    }
    let mode = backgroundMode(for: item)
    let prompt = Prompts.image(post: text, instruction: item.instruction, background: mode)
    start(item.id) {
      let (image, raw) = try await self.renderImage(item, prompt: prompt, mode: mode, input: nil, fallbackPrompt: nil)
      item.imageData = image
      item.rawImageData = raw
      item.previousImageData = nil
      item.previousRawImageData = nil
    }
  }

  /// Edits the current image with a follow-up instruction. Models without an edit endpoint regenerate from
  /// the original prompt plus the refinement.
  func refine(_ item: ImageItem, instruction: String) {
    let change = instruction.trimmed
    guard !change.isEmpty, let current = item.imageData else { return }
    let mode = backgroundMode(for: item)
    // Green-screen models edit the unkeyed render (or the cut-out put back on green).
    let input: Data = switch mode {
    case .greenScreen: item.rawImageData ?? BackgroundRemover.compositeOnGreen(current)
    case .native, .opaque: current
    }
    let prompt = Prompts.refine(change, background: mode)
    let combinedDirection = [item.instruction.trimmed, change].filter { !$0.isEmpty }.joined(separator: "\n")
    let fallback = Prompts.image(post: originalText.trimmed, instruction: combinedDirection, background: mode)
    Haptics.tap()
    start(item.id) {
      let (image, raw) = try await self.renderImage(item, prompt: prompt, mode: mode, input: input, fallbackPrompt: fallback)
      item.previousImageData = item.imageData
      item.previousRawImageData = item.rawImageData
      item.imageData = image
      item.rawImageData = raw
      self.flash(LocalizableKey.imageRefined.string, symbol: "wand.and.stars")
    }
  }

  func undoRefinement(_ item: ImageItem) {
    guard let previous = item.previousImageData else { return }
    item.imageData = previous
    item.rawImageData = item.previousRawImageData
    item.previousImageData = nil
    item.previousRawImageData = nil
    touch()
    save()
    flash(LocalizableKey.refinementUndone.string, symbol: "arrow.uturn.backward")
  }

  /// Generates (or edits, when `input` is set) and post-processes the background. Returns the final image
  /// and, for green-screen renders, the unkeyed original.
  private func renderImage(_ item: ImageItem, prompt: String, mode: BackgroundMode, input: Data?,
                           fallbackPrompt: String?) async throws -> (Data, Data?) {
    let id = item.id
    let size = item.size
    var output: Data
    if providers.isCodex(item.model) {
      guard let install = providers.codex else { throw CodexError.notInstalled }
      output = try await CodexSession.generateImage(install: install, prompt: prompt + "\n\n" + Prompts.aspect(size), inputImage: input) { status in
        self.statuses[id] = .running(status)
      }
    } else {
      let client = try providers.client(for: item.model)
      let model = item.modelID
      let sizeValue = size.value(for: model)
      let transparent = mode == .native
      if let input {
        statuses[id] = .running(LocalizableKey.refiningImage.string)
        do {
          output = try await client.editImage(model: model, image: input, prompt: prompt, size: sizeValue, transparent: transparent)
        } catch where OpenAIClient.isEditUnsupported(error) && fallbackPrompt != nil {
          statuses[id] = .running(LocalizableKey.regeneratingWithChanges.string)
          output = try await client.generateImage(model: model, prompt: fallbackPrompt!, size: sizeValue, transparent: transparent)
        }
      } else {
        statuses[id] = .running(LocalizableKey.generatingImage.string)
        output = try await client.generateImage(model: model, prompt: prompt, size: sizeValue, transparent: transparent)
      }
    }
    try Task.checkCancellation()

    switch mode {
    case .opaque:
      return (output, nil)
    case .native:
      statuses[id] = .running(LocalizableKey.checkingTransparency.string)
      let raw = output
      output = try await Task.detached { try BackgroundRemover.ensureTransparent(raw) }.value
      return (output, nil)
    case .greenScreen:
      statuses[id] = .running(LocalizableKey.removingGreenScreen.string)
      let raw = output
      output = try await Task.detached { try BackgroundRemover.removeGreenScreen(raw) }.value
      return (output, raw)
    }
  }

  // MARK: Images

  func copyImage(_ item: ImageItem) {
    guard let data = item.imageData, let image = NSImage(data: data) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
    flash(LocalizableKey.imageCopied.string, symbol: "photo.on.rectangle")
  }

  static var picturesFolder: URL {
    // Real ~/Pictures (allowed by the pictures entitlement), not the sandbox container.
    let home = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir)) } ?? URL.homeDirectory
    return home.appending(path: "Pictures/FineText", directoryHint: .isDirectory)
  }

  func saveImageToPictures(_ item: ImageItem) {
    guard let data = item.imageData else { return }
    do {
      let folder = Self.picturesFolder
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let name = "FineText \(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))).png"
      let url = folder.appending(path: name)
      try Self.png(data).write(to: url)
      flash(LocalizableKey.savedToPicturesFinetext.string, symbol: "square.and.arrow.down")
    } catch {
      flash(LocalizableKey.saveFailed.format(error.localizedDescription), symbol: "xmark.octagon", isError: true)
    }
  }

  func saveImageAs(_ item: ImageItem) {
    guard let data = item.imageData else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "FineText Image.png"
    panel.canCreateDirectories = true
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try Self.png(data).write(to: url)
      flash(LocalizableKey.imageSaved.string, symbol: "square.and.arrow.down")
    } catch {
      flash(LocalizableKey.saveFailed.format(error.localizedDescription), symbol: "xmark.octagon", isError: true)
    }
  }

  private static func png(_ data: Data) -> Data {
    guard let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return data }
    return png
  }
}

// MARK: - Prompts

enum Prompts {
  static func humanize(_ text: String, source: String, item: RewriteItem) -> [ChatMessage] {
    [
      ChatMessage(role: "system", content: """
      Edit the draft into natural writing for \(item.customPlatformName ?? item.platform.promptTitle).
      Tone: \(item.tone.guidance).
      \(item.customPlatformInstruction ?? item.platform.guidelines)
      \(humanStyle)
      Preserve all facts, meaning, links and the original language. The original is the source of truth.
      Do not invent experiences or add errors. Return only the finished text.
      """),
      ChatMessage(role: "user", content: "Original:\n\(source)\n\nDraft to improve:\n\(text)"),
    ]
  }
  static let humanStyle = """
  Write like a real person, not an AI: vary sentence length, use plain words, keep the author's voice. \
  Avoid clichés such as "delve", "game-changer", "unlock", "elevate", "in today's fast-paced world", \
  "let's dive in", avoid overusing em dashes, and do not add emojis unless they suit the platform and tone.
  """

  static func rewrite(_ text: String, platform: Platform, tone: Tone, customName: String? = nil, customInstruction: String? = nil) -> [ChatMessage] {
    [
      ChatMessage(role: "system", content: """
      You are an expert editor who adapts posts for \(customName ?? platform.promptTitle).
      Tone: \(tone.rawValue.capitalized) — \(tone.guidance).
      Platform guidelines:
      \(customInstruction ?? platform.guidelines)
      Keep the original meaning and facts; never invent claims, numbers or links. \
      Write in the same language as the original post.
      \(humanStyle)
      Reply with the finished post only — no preamble, no explanations, no surrounding quotes.
      """),
      ChatMessage(role: "user", content: text),
    ]
  }

  static func translate(_ text: String, to language: Language) -> [ChatMessage] {
    [
      ChatMessage(role: "system", content: """
      Translate the user's text into \(language.name) (\(language.code)) as a native speaker would write it for social media. \
      Preserve meaning, tone, line breaks, Markdown, hashtags, @mentions and URLs. \
      Reply with the translation only.
      """),
      ChatMessage(role: "user", content: text),
    ]
  }

  static func aspect(_ size: ImageSize) -> String {
    switch size {
    case .square: "Use a square 1:1 aspect ratio."
    case .landscape: "Use a landscape 3:2 aspect ratio."
    case .portrait: "Use a portrait 2:3 aspect ratio."
    }
  }

  static func image(post: String, instruction: String, background: BackgroundMode = .opaque) -> String {
    var prompt = "Create an eye-catching illustration to accompany this social media post. Do not render any text in the image."
    if let directive = background.directive { prompt += "\n\n" + directive }
    if !post.isEmpty { prompt += "\n\nPost:\n\(post.prefix(2500))" }
    if !instruction.trimmed.isEmpty { prompt += "\n\nArt direction: \(instruction.trimmed)" }
    return prompt
  }

  static func refine(_ change: String, background: BackgroundMode) -> String {
    var prompt = """
    Edit the provided image: \(change)
    Keep everything else the same: subject, composition, style, colors and framing. Do not render any text.
    """
    if let directive = background.directive { prompt += "\n" + directive }
    return prompt
  }

  /// Strips reasoning blocks and wrapping quotes some models add.
  static func clean(_ text: String) -> String {
    var result = text
    while let start = result.range(of: "<think>"), let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
      result.removeSubrange(start.lowerBound..<end.upperBound)
    }
    result = result.trimmed
    if result.count > 2, result.hasPrefix("\""), result.hasSuffix("\""), !result.dropFirst().dropLast().contains("\"") {
      result = String(result.dropFirst().dropLast())
    }
    return result
  }
}

extension BackgroundMode {
  /// Background instructions appended to image prompts.
  var directive: String? {
    switch self {
    case .opaque: nil
    case .native:
      "Render the subject as an isolated cut-out on a fully transparent background (PNG with alpha). " +
        "No background scenery, floor, frame or drop shadow."
    case .greenScreen:
      "Render the subject isolated on a perfectly flat, uniform, pure chroma-key green (#00FF00) background that fills " +
        "the whole canvas edge to edge. No gradients, texture, scenery, floor, shadows or reflections on the background. " +
        "Do not use green anywhere on the subject, and keep a clear margin between the subject and the image edges."
    }
  }
}
