import Foundation

// MARK: - Presets & tones

// Built-in rewrite presets come from the cloud catalog (see Services/Presets.swift).

/// Reusable rewrite rules. IDs remain stable when the user renames a preset.
struct CustomPlatform: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var instruction: String
  /// Submenu path such as "Work/Clients"; nil keeps the preset at the top level.
  var folder: String? = nil

  /// Folder names from the outermost submenu inwards.
  var folderPath: [String] { Self.path(folder ?? "") }

  static func path(_ folder: String) -> [String] {
    folder.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  /// Canonical "A/B" form, or nil for the top level.
  static func normalizedFolder(_ folder: String?) -> String? {
    let path = path(folder ?? "")
    return path.isEmpty ? nil : path.joined(separator: "/")
  }

  /// Every folder path in use, including parents, e.g. ["Work", "Work/Clients"].
  static func folders(in platforms: [CustomPlatform]) -> [String] {
    Set(platforms.flatMap { platform in
      platform.folderPath.indices.map { platform.folderPath[...$0].joined(separator: "/") }
    }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }
}

/// Custom presets arranged as nested submenus: folders (sorted) first, then presets in saved order.
enum CustomPlatformNode: Identifiable, Hashable, Sendable {
  case folder(name: String, path: String, children: [CustomPlatformNode])
  case platform(CustomPlatform)

  var id: String {
    switch self {
    case .folder(_, let path, _): "folder:" + path
    case .platform(let platform): platform.id.uuidString
    }
  }

  func contains(_ id: UUID?) -> Bool {
    switch self {
    case .folder(_, _, let children): children.contains { $0.contains(id) }
    case .platform(let platform): platform.id == id
    }
  }

  static func tree(_ platforms: [CustomPlatform], depth: Int = 0, parent: [String] = []) -> [CustomPlatformNode] {
    var names: [String] = []
    var grouped: [String: [CustomPlatform]] = [:]
    var leaves: [CustomPlatformNode] = []
    for platform in platforms {
      let path = platform.folderPath
      guard path.count > depth else { leaves.append(.platform(platform)); continue }
      if grouped[path[depth]] == nil { names.append(path[depth]) }
      grouped[path[depth], default: []].append(platform)
    }
    let folders = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
      CustomPlatformNode.folder(name: name, path: (parent + [name]).joined(separator: "/"),
                                children: tree(grouped[name]!, depth: depth + 1, parent: parent + [name]))
    }
    return folders + leaves
  }
}

enum Tone: String, CaseIterable, Codable, Identifiable, Sendable {
  case natural, professional, casual, witty, friendly, enthusiastic, informative, storytelling, bold, concise, empathetic

  var id: String { rawValue }
  var title: String {
    switch self {
    case .natural: LocalizableKey.natural.string
    case .professional: LocalizableKey.professional.string
    case .casual: LocalizableKey.casual.string
    case .witty: LocalizableKey.witty.string
    case .friendly: LocalizableKey.friendly.string
    case .enthusiastic: LocalizableKey.enthusiastic.string
    case .informative: LocalizableKey.informative.string
    case .storytelling: LocalizableKey.storytelling.string
    case .bold: LocalizableKey.bold.string
    case .concise: LocalizableKey.concise.string
    case .empathetic: LocalizableKey.empathetic.string
    }
  }

  var guidance: String {
    switch self {
    case .natural: "how the author would actually say it in person: plain words, relaxed rhythm, nothing performative"
    case .professional: "polished, credible and confident without jargon"
    case .casual: "relaxed and conversational, like talking to a friend"
    case .witty: "clever and playful with light humor, never cringe"
    case .friendly: "warm, approachable and positive"
    case .enthusiastic: "energetic and excited, but still sincere"
    case .informative: "clear, factual and helpful, focused on the key information"
    case .storytelling: "narrative, with a personal arc that pulls the reader in"
    case .bold: "direct, opinionated and a little provocative"
    case .concise: "as short and crisp as possible, every word earns its place"
    case .empathetic: "understanding, human and supportive"
    }
  }
}

// MARK: - Languages

struct Language: Hashable, Codable, Identifiable, Sendable {
  let code: String
  let name: String
  var id: String { code }

  /// Localized display name; `name` stays stable for Codable and model prompts.
  var localizedName: String {
    Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
      .localizedString(forIdentifier: code) ?? name
  }

  static let english = Language(code: "en", name: "English")
  static let japanese = Language(code: "ja", name: "Japanese")

  static let all: [Language] = [
    .english, .japanese,
    Language(code: "zh-Hans", name: "Chinese (Simplified)"),
    Language(code: "zh-Hant", name: "Chinese (Traditional)"),
    Language(code: "ko", name: "Korean"),
    Language(code: "es", name: "Spanish"),
    Language(code: "fr", name: "French"),
    Language(code: "de", name: "German"),
    Language(code: "it", name: "Italian"),
    Language(code: "pt", name: "Portuguese"),
    Language(code: "nl", name: "Dutch"),
    Language(code: "ru", name: "Russian"),
    Language(code: "uk", name: "Ukrainian"),
    Language(code: "pl", name: "Polish"),
    Language(code: "sv", name: "Swedish"),
    Language(code: "tr", name: "Turkish"),
    Language(code: "ar", name: "Arabic"),
    Language(code: "hi", name: "Hindi"),
    Language(code: "id", name: "Indonesian"),
    Language(code: "vi", name: "Vietnamese"),
    Language(code: "th", name: "Thai"),
  ]

  static func named(code: String) -> Language {
    if let known = all.first(where: { $0.code == code }) { return known }
    let name = Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
    return Language(code: code, name: name)
  }
}

// MARK: - Providers & models

struct Provider: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var baseURL: String

  /// Pseudo provider id for MLX models downloaded from Hugging Face and run on this Mac.
  static let localID = UUID(uuidString: "00000000-0000-0000-0000-00000000F17E")!
  static var localName: String { LocalizableKey.onThisMac.string }
}

struct ModelRef: Codable, Hashable, Sendable {
  let providerID: UUID
  let modelID: String

  var isLocal: Bool { providerID == Provider.localID }
}

enum ModelKind: String, Sendable {
  case text, image
}

struct RemoteModel: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let generatesImages: Bool
  let generatesText: Bool
  var pricing: ModelPricing? = nil
}

// MARK: - Jobs

enum JobStatus: Equatable, Sendable {
  case idle
  case running(String)
  case done
  case failed(String)

  var isRunning: Bool { if case .running = self { true } else { false } }
}

enum ImageSize: String, CaseIterable, Identifiable, Sendable {
  case square, landscape, portrait
  var id: String { rawValue }
  var title: String {
    switch self {
    case .square: LocalizableKey.square.string
    case .landscape: LocalizableKey.landscape.string
    case .portrait: LocalizableKey.portrait.string
    }
  }

  func value(for modelID: String) -> String {
    let dalle3 = modelID.lowercased().contains("dall-e-3")
    switch self {
    case .square: return "1024x1024"
    case .landscape: return dalle3 ? "1792x1024" : "1536x1024"
    case .portrait: return dalle3 ? "1024x1792" : "1024x1536"
    }
  }
}

// MARK: - Defaults

enum DefaultsKey {
  static let humanizationMode = "humanizationMode"
  static let humanizationEngine = "humanizationEngine"
  static let detectorEngine = "aiDetectorEngine"
  static let targetAIScore = "targetAIScore"
  static let humanizeRounds = "humanizeRounds"
  static let pivotLanguage = "pivotLanguage"
  static let gemmaModel = "translateGemmaMLXModel"
  static let draft = "draftText"
  static let providers = "providers"
  static let modelCache = "modelCache"
  static let preferences = "preferences"
  static let localModels = "localModels"
  static let settingsTab = "settingsTab"
  static let analyticsEnabled = "analyticsEnabled"

  static func register() {
    UserDefaults.standard.register(defaults: [
      humanizeRounds: 3,
      pivotLanguage: Language.japanese.code,
      gemmaModel: TranslationModel.default.id,
      humanizationEngine: HumanizationEngine.translateGemma.rawValue,
      detectorEngine: AIDetectorEngine.disabled.rawValue,
      targetAIScore: 20.0,
    ])
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct CostSummary {
  let charges: [GenerationCharge]
  var total: Double { charges.compactMap(\.costUSD).reduce(0, +) }
  var unknownCount: Int { charges.filter { $0.costUSD == nil }.count }
  /// Sum of known costs, or nil when no charge has a known amount.
  var knownTotal: Double? { charges.contains { $0.costUSD != nil } ? total : nil }
  var hasEstimate: Bool { charges.contains { $0.estimated } }
  var totalLabel: String { charges.isEmpty ? Self.usd(0) : label }
  var label: String {
    guard !charges.isEmpty else { return LocalizableKey.costUnavailable.string }
    guard charges.contains(where: { $0.costUSD != nil }) else { return LocalizableKey.costUnavailable.string }
    return (hasEstimate ? "≈ " : "") + Self.usd(total) + (unknownCount > 0 ? " + ?" : "")
  }
  static func usd(_ amount: Double) -> String {
    if amount > 0, amount < 0.000001 {
      return "< " + 0.000001.formatted(.currency(code: "USD").precision(.fractionLength(6)))
    }
    return amount.formatted(.currency(code: "USD").precision(.fractionLength(2...6)))
  }
}
