import AppKit
import Foundation
import Security

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

  static let presets: [Provider] = [
    Provider(name: "OpenAI", baseURL: "https://api.openai.com/v1"),
    Provider(name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1"),
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
  }

  private func persist() {
    let defaults = UserDefaults.standard
    defaults.set(try? JSONEncoder().encode(providers), forKey: DefaultsKey.providers)
    defaults.set(try? JSONEncoder().encode(models), forKey: DefaultsKey.modelCache)
  }

  func provider(_ id: UUID) -> Provider? { providers.first { $0.id == id } }
  func apiKey(for id: UUID) -> String { Keychain.get(account: id.uuidString) }

  func save(_ provider: Provider, apiKey: String) {
    if let index = providers.firstIndex(where: { $0.id == provider.id }) {
      providers[index] = provider
    } else {
      providers.append(provider)
    }
    Keychain.set(apiKey, account: provider.id.uuidString)
    persist()
    Task { await refresh(provider.id) }
  }

  func delete(_ provider: Provider) {
    providers.removeAll { $0.id == provider.id }
    models[provider.id] = nil
    errors[provider.id] = nil
    Keychain.delete(account: provider.id.uuidString)
    persist()
  }

  func client(for ref: ModelRef) throws -> OpenAIClient {
    guard let provider = provider(ref.providerID) else {
      throw APIError.http(0, "The provider for \(ref.modelID) was removed. Pick another model.")
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
    (models[id] ?? []).filter { kind == .image ? $0.generatesImages : $0.generatesText }
  }

  func displayName(_ ref: ModelRef) -> String {
    let name = ref.modelID.split(separator: "/").last.map(String.init) ?? ref.modelID
    guard providers.count > 1, let provider = provider(ref.providerID) else { return name }
    return "\(name) · \(provider.name)"
  }
}

// MARK: - Last picks

@MainActor @Observable final class Preferences {
  struct Stored: Codable {
    var lastPlatform: Platform?
    var lastLanguage: String?
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

  var lastPlatform: Platform? { stored.lastPlatform }
  var lastLanguage: Language? { stored.lastLanguage.map(Language.named(code:)) }
  func lastModel(_ purpose: Purpose) -> ModelRef? { stored.lastModels[purpose.rawValue] }
  func recentModels(_ purpose: Purpose) -> [ModelRef] { stored.recentModels[purpose.rawValue] ?? [] }
  func tone(for platform: Platform) -> Tone { stored.tones[platform.rawValue] ?? platform.defaultTone }

  func remember(_ model: ModelRef, for purpose: Purpose) {
    stored.lastModels[purpose.rawValue] = model
    var recent = stored.recentModels[purpose.rawValue] ?? []
    recent.removeAll { $0 == model }
    recent.insert(model, at: 0)
    stored.recentModels[purpose.rawValue] = Array(recent.prefix(4))
  }

  func remember(platform: Platform) { stored.lastPlatform = platform }
  func remember(language: Language) { stored.lastLanguage = language.code }
  func setTone(_ tone: Tone, for platform: Platform) { stored.tones[platform.rawValue] = tone }
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
