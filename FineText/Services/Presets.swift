import Foundation
import Observation

// MARK: - Catalog

/// Text keyed by locale ("en", "zh-CN", "zh-HK", "zh-TW"); "en" is always present.
struct LocalizedText: Codable, Hashable, Sendable {
  var values: [String: String]

  init(_ values: [String: String]) { self.values = values }
  init(from decoder: Decoder) throws { values = try decoder.singleValueContainer().decode([String: String].self) }
  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(values)
  }

  var english: String { values["en"] ?? values.values.sorted().first ?? "" }

  /// The best match for the app's interface language, falling back to its base language, then English.
  var localized: String { resolved(for: Bundle.main.preferredLocalizations.first ?? "en") }

  func resolved(for locale: String) -> String {
    if let exact = values[locale] { return exact }
    let base = locale.split(separator: "-").first.map(String.init) ?? locale
    if let match = values.first(where: { $0.key.split(separator: "-").first.map(String.init) == base }) { return match.value }
    return english
  }
}

/// One part of a structured result, shown in its own text box with its own copy button.
struct PresetField: Codable, Hashable, Sendable, Identifiable {
  let id: String
  let label: LocalizedText
  var multiline = false
  var characterLimit: Int?

  enum CodingKeys: String, CodingKey { case id, label, multiline, characterLimit }
  init(id: String, label: LocalizedText, multiline: Bool = false, characterLimit: Int? = nil) {
    self.id = id
    self.label = label
    self.multiline = multiline
    self.characterLimit = characterLimit
  }
  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    label = try container.decode(LocalizedText.self, forKey: .label)
    multiline = try container.decodeIfPresent(Bool.self, forKey: .multiline) ?? false
    characterLimit = try container.decodeIfPresent(Int.self, forKey: .characterLimit)
  }
}

/// What the app does with a preset. Unknown kinds from newer catalogs fall back to a rewrite.
enum PresetKind: String, Codable, Sendable {
  case rewrite
  /// Proofread only: the model marks each correction inline (see `GrammarMarkup`).
  case grammar

  init(_ raw: String?) { self = raw.flatMap(PresetKind.init(rawValue:)) ?? .rewrite }
}

/// A rewrite preset from the cloud catalog. `template` holds the platform guidelines.
struct Preset: Codable, Hashable, Sendable, Identifiable {
  let id: String
  let title: LocalizedText
  let promptTitle: String
  var symbol: String?
  /// Raw kind, kept as text so a newer catalog's kinds never fail decoding.
  var kind: String?
  var tone: String?
  var characterLimit: Int?
  var fields: [PresetField]?
  let template: String

  var defaultTone: Tone { tone.flatMap(Tone.init(rawValue:)) ?? .natural }
  var presetKind: PresetKind { PresetKind(kind) }
}

struct PresetMenu: Codable, Hashable, Sendable, Identifiable {
  let id: String
  let title: LocalizedText
  var symbol: String?
  let children: [PresetNode]

  /// Whether a preset with this id appears anywhere under the menu.
  func contains(_ presetID: String) -> Bool {
    children.contains { node in
      switch node {
      case .menu(let menu): menu.contains(presetID)
      case .preset(let preset): preset.id == presetID
      case .unsupported: false
      }
    }
  }
}

enum PresetNode: Codable, Hashable, Sendable, Identifiable {
  case menu(PresetMenu)
  case preset(Preset)
  /// A node type from a newer catalog schema; older apps skip it.
  case unsupported

  private enum CodingKeys: String, CodingKey { case type }

  init(from decoder: Decoder) throws {
    switch try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .type) {
    case "menu": self = .menu(try PresetMenu(from: decoder))
    case "preset": self = .preset(try Preset(from: decoder))
    default: self = .unsupported
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .menu(let menu): try container.encode("menu", forKey: .type); try menu.encode(to: encoder)
    case .preset(let preset): try container.encode("preset", forKey: .type); try preset.encode(to: encoder)
    case .unsupported: try container.encode("unsupported", forKey: .type)
    }
  }

  var id: String {
    switch self {
    case .menu(let menu): "menu:" + menu.id
    case .preset(let preset): preset.id
    case .unsupported: "unsupported"
    }
  }
}

struct PresetCatalog: Codable, Hashable, Sendable {
  static let supportedSchemaVersion = 1

  let schemaVersion: Int
  let version: String
  let items: [PresetNode]

  /// Every preset with the titles of the menus that lead to it.
  var entries: [PresetEntry] {
    var result: [PresetEntry] = []
    func visit(_ nodes: [PresetNode], path: [LocalizedText]) {
      for node in nodes {
        switch node {
        case .menu(let menu): visit(menu.children, path: path + [menu.title])
        case .preset(let preset): result.append(PresetEntry(preset: preset, path: path + [preset.title]))
        case .unsupported: break
        }
      }
    }
    visit(items, path: [])
    return result
  }

  static func decode(_ data: Data) throws -> PresetCatalog {
    let catalog = try JSONDecoder().decode(PresetCatalog.self, from: data)
    guard catalog.schemaVersion <= supportedSchemaVersion else { throw PresetStore.Failure.unsupportedSchema }
    guard !catalog.entries.isEmpty else { throw PresetStore.Failure.empty }
    return catalog
  }
}

/// A preset with its menu path, e.g. ["Email", "Send"], shown as "Email · Send".
struct PresetEntry: Hashable, Sendable, Identifiable {
  let preset: Preset
  let path: [LocalizedText]
  var id: String { preset.id }
  var title: String { path.map(\.localized).joined(separator: " · ") }
}

/// What a rewrite keeps about its preset, so history and regeneration survive catalog changes.
struct PresetSnapshot: Codable, Hashable, Sendable {
  var id: String
  var path: [LocalizedText]
  var promptTitle: String
  var symbol: String?
  var kind: String?
  var tone: String?
  var characterLimit: Int?
  var fields: [PresetField]?
  var template: String

  init(_ entry: PresetEntry) {
    id = entry.preset.id
    path = entry.path
    promptTitle = entry.preset.promptTitle
    symbol = entry.preset.symbol
    kind = entry.preset.kind
    tone = entry.preset.tone
    characterLimit = entry.preset.characterLimit
    fields = entry.preset.fields
    template = entry.preset.template
  }

  var title: String { path.map(\.localized).joined(separator: " · ") }
  var defaultTone: Tone { tone.flatMap(Tone.init(rawValue:)) ?? .natural }
  var presetKind: PresetKind { PresetKind(kind) }

  /// Platform guidelines with the template filled in. A broken template falls back to its raw text.
  func guidelines(tone: Tone, appLanguage: String = Bundle.main.preferredLocalizations.first ?? "en") -> String {
    var context: [String: TemplateValue] = [
      "tone": .string(tone.rawValue.capitalized),
      "tone_id": .string(tone.rawValue),
      "tone_guidance": .string(tone.guidance),
      "app_language": .string(appLanguage),
      "preset": .object(["id": .string(id), "title": .string(path.map(\.english).joined(separator: " · ")), "prompt_title": .string(promptTitle)]),
    ]
    if let characterLimit { context["character_limit"] = .number(Double(characterLimit)) }
    let rendered = (try? PresetTemplate.render(template, context: context)) ?? template
    return rendered.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

// MARK: - Structured output

/// Results of presets with fields are stored as `<field>value</field>` blocks, one per field.
enum StructuredOutput {
  static func formatInstruction(_ fields: [PresetField]) -> String {
    let lines = fields.map { "<\($0.id)>\($0.label.english)\($0.multiline ? " (may span several lines)" : "")</\($0.id)>" }
    return """
    Format the reply as these XML tags, in this order, with nothing before, between or after them:
    \(lines.joined(separator: "\n"))
    Put only that field's text inside each tag.
    """
  }

  /// Field values, or nil when the text has none of the tags (legacy or free-form output).
  static func parse(_ text: String, fields: [PresetField]) -> [String: String]? {
    var values: [String: String] = [:]
    for (index, field) in fields.enumerated() {
      guard let open = text.range(of: "<\(field.id)>") else { continue }
      let rest = text[open.upperBound...]
      // Tolerate a missing closing tag by stopping at the next field's opening tag.
      let nextOpen = fields[(index + 1)...].compactMap { rest.range(of: "<\($0.id)>")?.lowerBound }.min()
      let close = rest.range(of: "</\(field.id)>")?.lowerBound
      let end = [close, nextOpen].compactMap { $0 }.min() ?? rest.endIndex
      values[field.id] = unwrap(String(rest[..<end]))
    }
    return values.isEmpty ? nil : values
  }

  /// Removes only the line breaks `compose` puts around a value, so edits keep their own whitespace.
  private static func unwrap(_ value: String) -> String {
    var value = value
    if value.hasPrefix("\n") { value.removeFirst() }
    if value.hasSuffix("\n") { value.removeLast() }
    return value
  }

  static func compose(_ values: [String: String], fields: [PresetField]) -> String {
    fields.map { "<\($0.id)>\n\(values[$0.id] ?? "")\n</\($0.id)>" }.joined(separator: "\n")
  }

  /// Readable text for copying, previews, translation and AI scoring.
  static func plainText(_ text: String, fields: [PresetField]?) -> String {
    guard let fields, let values = parse(text, fields: fields) else { return text }
    return fields.compactMap { field in
      guard let value = values[field.id]?.trimmed, !value.isEmpty else { return nil }
      return field.multiline ? value : "\(field.label.localized): \(value)"
    }.joined(separator: "\n\n")
  }
}

// MARK: - Store

/// Downloads the rewrite preset catalog from the website every few hours and caches it for offline use.
/// Order of preference: the last downloaded catalog, then the copy bundled with the app.
@MainActor @Observable final class PresetStore {
  enum Failure: LocalizedError {
    case unsupportedSchema, empty, http(Int)
    var errorDescription: String? {
      switch self {
      case .unsupportedSchema: LocalizableKey.presetsNeedNewerApp.string
      case .empty: LocalizableKey.presetsEmpty.string
      case .http(let code): "HTTP \(code)"
      }
    }
  }

  static let refreshInterval: Duration = .seconds(4 * 60 * 60)
  private static let lastCheckedKey = "presetsLastChecked"

  private(set) var catalog: PresetCatalog
  private(set) var entries: [PresetEntry]
  private(set) var isRefreshing = false
  private(set) var lastChecked: Date?
  private(set) var lastError: String?
  private var autoRefresh: Task<Void, Never>?
  private let remoteURL: URL?
  private let cacheURL: URL
  private let session: URLSession

  init(remoteURL: URL? = PresetStore.configuredURL, cacheURL: URL = PresetStore.defaultCacheURL,
       bundled: URL? = Bundle.main.url(forResource: "presets", withExtension: "json"), session: URLSession = .shared) {
    self.remoteURL = remoteURL
    self.cacheURL = cacheURL
    self.session = session
    let cached = (try? Data(contentsOf: cacheURL)).flatMap { try? PresetCatalog.decode($0) }
    let fallback = bundled.flatMap { try? Data(contentsOf: $0) }.flatMap { try? PresetCatalog.decode($0) }
    let catalog = cached ?? fallback ?? PresetCatalog(schemaVersion: 1, version: "empty", items: [])
    self.catalog = catalog
    entries = catalog.entries
    lastChecked = UserDefaults.standard.object(forKey: Self.lastCheckedKey) as? Date
  }

  /// `PresetsURL` in Info.plist: localhost for Debug, the production website for Release.
  static var configuredURL: URL? {
    (Bundle.main.object(forInfoDictionaryKey: "PresetsURL") as? String)
      .map(\.trimmed).flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : URL(string: $0) }
  }

  static var defaultCacheURL: URL {
    URL.applicationSupportDirectory.appending(path: "FineText", directoryHint: .isDirectory).appending(path: "presets.json")
  }

  func entry(id: String) -> PresetEntry? { entries.first { $0.id == id } }

  /// Checks on launch when the cached copy is due, then every `refreshInterval` while the app runs.
  func startAutoRefresh() {
    guard autoRefresh == nil else { return }
    autoRefresh = Task { [weak self] in
      let interval = Double(Self.refreshInterval.components.seconds)
      while !Task.isCancelled {
        guard let self else { return }
        var wait = interval - (self.lastChecked.map { Date.now.timeIntervalSince($0) } ?? .infinity)
        if wait <= 0 {
          await self.refresh()
          // Offline or failing: retry sooner than the regular interval.
          wait = self.lastError == nil ? interval : 30 * 60
        }
        try? await Task.sleep(for: .seconds(max(60, wait)))
      }
    }
  }

  /// Returns true when a different catalog was installed.
  @discardableResult
  func refresh() async -> Bool {
    guard let remoteURL, !isRefreshing else { return false }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      var request = URLRequest(url: remoteURL, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30)
      request.setValue("application/json", forHTTPHeaderField: "Accept")
      let (data, response) = try await session.data(for: request)
      if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw Failure.http(http.statusCode) }
      let fresh = try PresetCatalog.decode(data)
      lastChecked = .now
      UserDefaults.standard.set(lastChecked, forKey: Self.lastCheckedKey)
      lastError = nil
      guard fresh.version != catalog.version else { return false }
      try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: cacheURL, options: .atomic)
      catalog = fresh
      entries = fresh.entries
      return true
    } catch {
      // Keep the current catalog; the next scheduled check tries again.
      lastError = error.localizedDescription
      return false
    }
  }
}
