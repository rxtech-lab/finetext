import Foundation

/// Settings for one humanization run. The UI reads them from Settings; MCP clients may override each one.
struct HumanizationOptions {
  var mode: HumanizationMode
  var rounds: Int
  var target: Double
  var engine: HumanizationEngine
  var detector: AIDetectorEngine
  /// Extra rules and reference material from an MCP client.
  var extraGuidance: String?
  var context: String?
  /// Rejects a round's candidate (the round then counts as unchanged), e.g. when template placeholders were lost.
  var accepts: (@MainActor (String) -> Bool)?

  @MainActor static func fromDefaults(_ defaults: UserDefaults = .standard) -> Self {
    let target = defaults.double(forKey: DefaultsKey.targetAIScore)
    return Self(
      mode: HumanizationMode.selected(in: defaults),
      rounds: max(1, defaults.integer(forKey: DefaultsKey.humanizeRounds)),
      target: target.isFinite ? min(100, max(0, target)) : 20,
      engine: HumanizationEngine(rawValue: defaults.string(forKey: DefaultsKey.humanizationEngine) ?? "") ?? .translateGemma,
      detector: AIDetectorEngine.selected
    )
  }
}

/// An MCP rewrite request, resolved against the preset catalog and the configured models.
struct ExternalRewrite {
  var text: String
  var preset: PresetEntry?
  var customPlatform: CustomPlatform?
  var tone: Tone?
  var model: ModelRef
  /// false only humanizes `text` (the `humanize` tool); true writes a fresh draft with the agent first.
  var rewriteFirst: Bool
  var options: HumanizationOptions
}

/// Go-template style `{{ … }}` actions. Rewriting a template must keep every one of them.
enum TemplatePlaceholders {
  static func all(in text: String) -> [String] {
    var result: [String] = []
    var rest = text[...]
    while let open = rest.range(of: "{{"), let close = rest.range(of: "}}", range: open.upperBound..<rest.endIndex) {
      result.append(rest[open.lowerBound..<close.upperBound].replacingOccurrences(of: " ", with: ""))
      rest = rest[close.upperBound...]
    }
    return result.sorted()
  }

  static func missing(from candidate: String, original: String) -> [String] {
    var remaining = all(in: candidate)
    var missing: [String] = []
    for placeholder in all(in: original) {
      if let index = remaining.firstIndex(of: placeholder) { remaining.remove(at: index) } else { missing.append(placeholder) }
    }
    return missing
  }
}
