import AppKit
import Foundation
import Security
import RxAgentSDK

// MARK: - Keychain

enum Keychain {
  private static let service = "app.rxlab.finetext.providers"

  private static func query(_ account: String) -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
  }

  static func set(_ value: String, account: String) {
    SecItemDelete(query(account) as CFDictionary)
    guard !value.isEmpty else { return }
    var item = query(account)
    item[kSecValueData as String] = Data(value.utf8)
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    SecItemAdd(item as CFDictionary, nil)
  }

  static func get(account: String) -> String {
    var item = query(account)
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return "" }
    return String(decoding: data, as: UTF8.self)
  }

  static func delete(account: String) {
    SecItemDelete(query(account) as CFDictionary)
  }
}

// MARK: - Providers

@MainActor @Observable final class ProviderStore {
  private(set) var providers: [Provider] = []
  private(set) var models: [UUID: [RemoteModel]] = [:]
  private(set) var loading: Set<UUID> = []
  private(set) var errors: [UUID: String] = [:]
  /// MLX models downloaded from Hugging Face; exposed as the "On This Mac" provider.
  let local = LocalModelStore()
  /// Local Codex CLI, used as a built-in text and image provider through `codex app-server`.
  private(set) var codex: CodexInstall?
  private(set) var detectingCodex = false

  static let codexProvider = Provider(id: UUID(uuidString: "C0DE0000-0000-4000-8000-00000000C0DE")!, name: "Codex", baseURL: "")
  static let codexImageModel = RemoteModel(id: "codex-image", generatesImages: true, generatesText: false)
  static let codexImageRef = ModelRef(providerID: codexProvider.id, modelID: codexImageModel.id)
  /// Uses whichever model is the default in the user's Codex config.
  static let codexTextModel = RemoteModel(id: "codex-text", generatesImages: false, generatesText: true)
  static let codexTextRef = ModelRef(providerID: codexProvider.id, modelID: codexTextModel.id)

  private(set) var claudeCode: ClaudeCodeInstall?
  private(set) var detectingClaudeCode = false
  static let claudeCodeProvider = Provider(id: UUID(uuidString: "C1A0DE00-0000-4000-8000-000000000001")!, name: "Claude Code", baseURL: "")
  static let claudeCodeTextModel = RemoteModel(id: "claude-code-text", generatesImages: false, generatesText: true)
  static let claudeCodeTextRef = ModelRef(providerID: claudeCodeProvider.id, modelID: claudeCodeTextModel.id)

  /// Flowcy cloud models, available after signing in with an rxlab account.
  let flowcy = FlowcyAccount()
  static let flowcyProvider = Provider(id: UUID(uuidString: "F10C0000-0000-4000-8000-00000000F10C")!, name: "Flowcy", baseURL: "")

  static let presets: [Provider] = [
    Provider(name: "OpenAI", baseURL: "https://api.openai.com/v1"),
    Provider(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1"),
    Provider(name: "Vercel AI Gateway", baseURL: "https://ai-gateway.vercel.sh/v1"),
    Provider(name: "Ollama", baseURL: "http://localhost:11434/v1"),
    Provider(name: "LM Studio", baseURL: "http://localhost:1234/v1"),
  ]

  init() {
    let defaults = UserDefaults.standard
    if let data = defaults.data(forKey: DefaultsKey.providers), let saved = try? JSONDecoder().decode([Provider].self, from: data) {
      providers = saved
    }
    if let data = defaults.data(forKey: DefaultsKey.modelCache), let cache = try? JSONDecoder().decode([UUID: [RemoteModel]].self, from: data) {
      models = cache
    }
    Task { await refreshAll() }
    Task { await detectCodex() }
    Task { await detectClaudeCode() }
  }

  func detectCodex() async {
    guard !detectingCodex else { return }
    detectingCodex = true
    codex = await CodexLocator.locate()
    detectingCodex = false
    await refreshCLIModels(Self.codexProvider.id)
  }

  func detectClaudeCode() async {
    guard !detectingClaudeCode else { return }
    detectingClaudeCode = true
    defer { detectingClaudeCode = false }
    claudeCode = await ClaudeCodeLocator.locate()
    await refreshCLIModels(Self.claudeCodeProvider.id)
  }

  func agentClient(for ref: ModelRef) throws -> any AgentClient {
    if isCodex(ref) {
      guard let codex else { throw CodexError.notInstalled }
      return AgentTextSession.codex(codex)
    }
    guard let claudeCode else { throw ClaudeCodeError.notInstalled }
    return AgentTextSession.claude(claudeCode)
  }

  private(set) var cliModelNames: [UUID: [String: String]] = [:]

  func refreshCLIModels(_ id: UUID) async {
    guard !loading.contains(id) else { return }
    let ref = ModelRef(providerID: id, modelID: "")
    guard let client = try? agentClient(for: ref) else { return }
    loading.insert(id)
    defer { loading.remove(id) }
    let options = await client.availableModels()
    var seen = Set<String>()
    let unique = options.filter { !$0.id.isEmpty && seen.insert($0.id).inserted && CLIModels.explicitModel($0.id) != nil }
    models[id] = unique.map { RemoteModel(id: $0.id, generatesImages: false, generatesText: true) }
    cliModelNames[id] = Dictionary(uniqueKeysWithValues: unique.map { ($0.id, $0.displayName) })
    persist()
  }

  func modelName(_ ref: ModelRef) -> String {
    if isFlowcy(ref) { return flowcy.alias(for: ref.modelID) ?? ref.modelID }
    if (isCodex(ref) || isClaudeCode(ref)) && CLIModels.explicitModel(ref.modelID) == nil {
      return LocalizableKey.cliDefaultModel.string
    }
    return cliModelNames[ref.providerID]?[ref.modelID] ?? ref.modelID
  }

  func isClaudeCode(_ ref: ModelRef) -> Bool { ref.providerID == Self.claudeCodeProvider.id }

  func isCodex(_ ref: ModelRef) -> Bool { ref.providerID == Self.codexProvider.id }

  func isFlowcy(_ ref: ModelRef) -> Bool { ref.providerID == Self.flowcyProvider.id }

  /// True when at least one source can serve this kind of model (user providers, Codex, or local MLX models for text).
  func hasSources(for kind: ModelKind) -> Bool {
    !providers.isEmpty || codex != nil || (kind == .text && (claudeCode != nil || flowcy.isSignedIn || !local.models.isEmpty))
  }

  private func persist() {
    let defaults = UserDefaults.standard
    defaults.set(try? JSONEncoder().encode(providers), forKey: DefaultsKey.providers)
    defaults.set(try? JSONEncoder().encode(models), forKey: DefaultsKey.modelCache)
  }

  func provider(_ id: UUID) -> Provider? {
    if id == Self.codexProvider.id { return codex == nil ? nil : Self.codexProvider }
    if id == Self.claudeCodeProvider.id { return claudeCode == nil ? nil : Self.claudeCodeProvider }
    if id == Self.flowcyProvider.id { return flowcy.isSignedIn ? Self.flowcyProvider : nil }
    return providers.first { $0.id == id }
  }
  func apiKey(for id: UUID) -> String { Keychain.get(account: id.uuidString) }

  func save(_ provider: Provider, apiKey: String) {
    if let index = providers.firstIndex(where: { $0.id == provider.id }) {
      providers[index] = provider
    } else {
      providers.append(provider)
    }
    Keychain.set(apiKey, account: provider.id.uuidString)
    persist()
    AppAnalytics.log(.providerSaved, ["provider_type": AppAnalytics.providerType(baseURL: provider.baseURL)])
    Task { await refresh(provider.id) }
  }

  func delete(_ provider: Provider) {
    providers.removeAll { $0.id == provider.id }
    models[provider.id] = nil
    errors[provider.id] = nil
    Keychain.delete(account: provider.id.uuidString)
    persist()
    AppAnalytics.log(.providerDeleted, ["provider_type": AppAnalytics.providerType(baseURL: provider.baseURL)])
  }

  /// Whether a saved model reference can still run (its provider exists or the local model is downloaded).
  func isAvailable(_ ref: ModelRef) -> Bool {
    ref.isLocal ? local.isInstalled(ref.modelID) : provider(ref.providerID) != nil
  }

  func client(for ref: ModelRef) throws -> OpenAIClient {
    guard let provider = provider(ref.providerID) else {
      throw APIError.http(0, LocalizableKey.providerRemoved.format(ref.modelID))
    }
    return try OpenAIClient(baseURL: provider.baseURL, apiKey: apiKey(for: provider.id))
  }

  func refreshAll() async {
    await withTaskGroup(of: Void.self) { group in
      for provider in providers { group.addTask { await self.refresh(provider.id) } }
    }
  }

  func refresh(_ id: UUID) async {
    guard let provider = provider(id), !loading.contains(id) else { return }
    loading.insert(id)
    defer { loading.remove(id) }
    do {
      let list = try await OpenAIClient(baseURL: provider.baseURL, apiKey: apiKey(for: id)).listModels()
      models[id] = list
      errors[id] = nil
      persist()
    } catch {
      errors[id] = error.localizedDescription
    }
  }

  func models(for id: UUID, kind: ModelKind) -> [RemoteModel] {
    if id == Self.codexProvider.id {
      guard codex != nil else { return [] }
      return kind == .image ? [Self.codexImageModel] : [Self.codexTextModel] + (models[id] ?? [])
    }
    if id == Self.claudeCodeProvider.id {
      return kind == .text && claudeCode != nil ? [Self.claudeCodeTextModel] + (models[id] ?? []) : []
    }
    if id == Self.flowcyProvider.id {
      guard kind == .text, flowcy.isSignedIn else { return [] }
      return flowcy.models.map { RemoteModel(id: $0.modelId, generatesImages: false, generatesText: true) }
    }
    if id == Provider.localID {
      return kind == .text ? local.models.map { RemoteModel(id: $0.id, generatesImages: false, generatesText: true) } : []
    }
    return (models[id] ?? []).filter { kind == .image ? $0.generatesImages : $0.generatesText }
  }

  func displayName(_ ref: ModelRef) -> String {
    if isClaudeCode(ref) || isCodex(ref) {
      let provider = isCodex(ref) ? "Codex" : "Claude Code"
      return CLIModels.explicitModel(ref.modelID) == nil ? provider : "\(modelName(ref)) · \(provider)"
    }
    if isFlowcy(ref) { return "\(modelName(ref)) · Flowcy" }
    let name = ref.modelID.split(separator: "/").last.map(String.init) ?? ref.modelID
    if ref.isLocal { return "\(name) · \(Provider.localName)" }
    guard providers.count > 1, let provider = provider(ref.providerID) else { return name }
    return "\(name) · \(provider.name)"
  }
}

// MARK: - Last picks

@MainActor @Observable final class Preferences {
  struct Stored: Codable {
    var customPlatforms: [CustomPlatform]?
    var lastCustomPlatformID: UUID?
    /// Preset id. Older builds stored the enum raw value, which is the same string.
    var lastPlatform: String?
    var lastLanguage: String?
    var lastRewriteLanguage: String?
    var lastModels: [String: ModelRef] = [:]
    var recentModels: [String: [ModelRef]] = [:]
    var tones: [String: Tone] = [:]
  }

  private(set) var stored: Stored {
    didSet { UserDefaults.standard.set(try? JSONEncoder().encode(stored), forKey: DefaultsKey.preferences) }
  }

  init() {
    if let data = UserDefaults.standard.data(forKey: DefaultsKey.preferences), let saved = try? JSONDecoder().decode(Stored.self, from: data) {
      stored = saved
    } else {
      stored = Stored()
    }
  }

  enum Purpose: String { case rewrite, translate, image }

  var customPlatforms: [CustomPlatform] { stored.customPlatforms ?? [] }
  var lastCustomPlatform: CustomPlatform? { customPlatforms.first { $0.id == stored.lastCustomPlatformID } }
  var lastPresetID: String? { stored.lastPlatform }

  func saveCustomPlatform(_ platform: CustomPlatform) {
    var platforms = customPlatforms
    var clean = platform
    clean.name = clean.name.trimmed
    clean.instruction = clean.instruction.trimmed
    clean.folder = CustomPlatform.normalizedFolder(clean.folder)
    guard !clean.name.isEmpty, !clean.instruction.isEmpty else { return }
    if let index = platforms.firstIndex(where: { $0.id == clean.id }) {
      platforms[index] = clean
    } else {
      platforms.append(clean)
    }
    stored.customPlatforms = platforms
  }

  func deleteCustomPlatform(_ id: UUID) {
    stored.customPlatforms = customPlatforms.filter { $0.id != id }
    stored.tones["custom-" + id.uuidString] = nil
    if stored.lastCustomPlatformID == id { stored.lastCustomPlatformID = nil }
  }

  func remember(customPlatform: CustomPlatform) {
    stored.lastPlatform = nil
    stored.lastCustomPlatformID = customPlatform.id
  }

  func tone(for item: RewriteItem) -> Tone {
    stored.tones[item.customPlatformID.map { "custom-" + $0.uuidString } ?? item.platformRaw]
      ?? item.defaultTone
  }

  func setTone(_ tone: Tone, for item: RewriteItem) {
    stored.tones[item.customPlatformID.map { "custom-" + $0.uuidString } ?? item.platformRaw] = tone
  }
  var lastLanguage: Language? { stored.lastLanguage.map(Language.named(code:)) }
  var lastRewriteLanguage: Language? { stored.lastRewriteLanguage.map(Language.named(code:)) }
  func remember(rewriteLanguage: Language?) { stored.lastRewriteLanguage = rewriteLanguage?.code }
  func lastModel(_ purpose: Purpose) -> ModelRef? { stored.lastModels[purpose.rawValue] }
  func recentModels(_ purpose: Purpose) -> [ModelRef] { stored.recentModels[purpose.rawValue] ?? [] }
  func tone(for preset: Preset) -> Tone { stored.tones[preset.id] ?? preset.defaultTone }

  func remember(_ model: ModelRef, for purpose: Purpose) {
    stored.lastModels[purpose.rawValue] = model
    var recent = stored.recentModels[purpose.rawValue] ?? []
    recent.removeAll { $0 == model }
    recent.insert(model, at: 0)
    stored.recentModels[purpose.rawValue] = Array(recent.prefix(4))
  }

  func remember(preset: Preset) {
    stored.lastPlatform = preset.id
    stored.lastCustomPlatformID = nil
  }
  func remember(language: Language) { stored.lastLanguage = language.code }
  func setTone(_ tone: Tone, for preset: Preset) { stored.tones[preset.id] = tone }
}

// MARK: - Feedback

enum Haptics {
  static func tap() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
  static func success() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
  static func failure() { NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now) }
}

struct Toast: Equatable, Identifiable {
  let id = UUID()
  let message: String
  let symbol: String
  var isError = false
}
