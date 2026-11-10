import Foundation
import RxAuthSwift

/// Flowcy account: rxlab OAuth sign-in plus the Flowcy agent model catalog and chat stream
/// (`GET /api/v1/agent/models`, `POST /api/v1/agent/chat`). Usage is billed to the Flowcy plan.
@MainActor @Observable final class FlowcyAccount {
  struct Model: Codable, Identifiable, Hashable, Sendable {
    let modelId: String
    let alias: String
    var id: String { modelId }
  }

  static let issuer = "https://auth.rxlab.app"
  static let redirectURI = "finetext://oauth-callback"
  /// `read:*` names are what rxlab-auth clients allow; `read:email` lets Flowcy resolve the account email.
  static let scopes = ["openid", "read:profile", "read:email"]
  private static let keychainService = "app.rxlab.finetext.rxauth"
  private static let modelCacheKey = "flowcyModels"

  /// First-party rxlab-auth client registered for FineText, injected from the xcconfig.
  static var clientID: String? { infoValue("FlowcyOAuthClientID") }

  /// Every build configuration uses the production Flowcy server.
  static var baseURL: URL {
    infoValue("FlowcyBaseURL").flatMap(URL.init(string:)) ?? URL(string: "https://www.flowcy.dev")!
  }

  /// Passkeys need the `webcredentials:rxlab.app` entitlement, which only builds signed with a
  /// provisioning profile carry. Builds without it show password sign-in only.
  static var passkeysEnabled: Bool { infoValue("FlowcyPasskeysEnabled") == "YES" }

  private static func configuration(passkeys: Bool) -> RxAuthConfiguration {
    let path = { (value: String) in passkeys ? value : nil }
    return RxAuthConfiguration(
      issuer: issuer, clientID: clientID ?? "", redirectURI: redirectURI, scopes: scopes,
      passkeyChallengePath: path("/api/oauth/passkey/authenticate/options"),
      passkeyVerificationPath: path("/api/oauth/passkey/authenticate/verify"),
      passkeyRegistrationChallengePath: path("/api/oauth/passkey/register/options"),
      passkeyRegistrationVerificationPath: path("/api/oauth/passkey/register/verify"),
      passkeyUpgradeChallengePath: path("/api/oauth/passkey/upgrade/options"),
      passkeyUpgradeVerificationPath: path("/api/oauth/passkey/upgrade/verify"),
      passkeyAccountCreationOptionsPath: path("/api/oauth/passkey/account-creation/options"),
      passkeyAccountCreationVerifyPath: path("/api/oauth/passkey/account-creation/verify"),
      // Matches the associated-domains entitlement and https://rxlab.app/.well-known/apple-app-site-association.
      passkeyRelyingPartyIdentifier: passkeys ? "rxlab.app" : nil,
      keychainServiceName: keychainService
    )
  }

  let manager: OAuthManager
  private let storage: KeychainTokenStorage
  private(set) var models: [Model] = []
  private(set) var loadingModels = false
  private(set) var modelError: String?
  /// Plan spend windows from `GET /api/v1/agent/usage`.
  private(set) var usage: [UsageMeter] = []
  private(set) var loadingUsage = false
  private(set) var usageError: String?
  private(set) var usageUpdated: Date?

  /// One rolling spend window. Amounts are integer micro-USD (1 USD = 1,000,000).
  struct UsageMeter: Decodable, Identifiable, Hashable, Sendable {
    let key: String
    let used: Double
    let limit: Double?
    let resetsAt: Date?
    var id: String { key }
    var usedUSD: Double { used / 1_000_000 }
    var limitUSD: Double? { limit.map { $0 / 1_000_000 } }
    /// 0…1 share of the allowance, or nil when the window is unlimited.
    var fraction: Double? { limit.flatMap { $0 > 0 ? min(1, used / $0) : nil } }
    /// Sort order and title: 5 hours, 7 days, 30 days.
    var order: Int { ["agent_cost_5h": 0, "agent_cost_7d": 1, "agent_cost_30d": 2][key] ?? 3 }
  }

  var isConfigured: Bool { Self.clientID != nil }
  var isSignedIn: Bool { manager.authState == .authenticated }
  var user: User? { manager.currentUser }

  init() {
    storage = KeychainTokenStorage(serviceName: Self.keychainService)
    manager = OAuthManager(
      configuration: Self.configuration(passkeys: Self.passkeysEnabled),
      tokenStorage: storage
    )
    if let data = UserDefaults.standard.data(forKey: Self.modelCacheKey),
       let cached = try? JSONDecoder().decode([Model].self, from: data) {
      models = cached
    }
    guard isConfigured else { return }
    Task {
      await manager.checkExistingAuth()
      if isSignedIn {
        await loadModels()
        await loadUsage()
      }
    }
  }

  func didSignIn() {
    Task {
      await loadModels()
      await loadUsage()
    }
  }

  func signOut() async {
    await manager.logout()
    models = []
    modelError = nil
    usage = []
    usageError = nil
    usageUpdated = nil
    UserDefaults.standard.removeObject(forKey: Self.modelCacheKey)
  }

  func alias(for modelID: String) -> String? { models.first { $0.modelId == modelID }?.alias }

  func loadModels() async {
    guard isSignedIn, !loadingModels else { return }
    loadingModels = true
    defer { loadingModels = false }
    do {
      let (bytes, _) = try await send("agent/models")
      let data = try await Self.collect(bytes, limit: 4_000_000)
      struct Catalog: Decodable { let models: [Model] }
      models = try JSONDecoder().decode(Catalog.self, from: data).models
      modelError = nil
      UserDefaults.standard.set(try? JSONEncoder().encode(models), forKey: Self.modelCacheKey)
    } catch is CancellationError {
    } catch {
      modelError = error.localizedDescription
    }
  }

  func loadUsage() async {
    guard isSignedIn, !loadingUsage else { return }
    loadingUsage = true
    defer { loadingUsage = false }
    do {
      let (bytes, _) = try await send("agent/usage")
      let data = try await Self.collect(bytes, limit: 1_000_000)
      struct Response: Decodable { let meters: [UsageMeter] }
      let decoder = JSONDecoder()
      decoder.dateDecodingStrategy = .custom { decoder in
        let text = try decoder.singleValueContainer().decode(String.self)
        let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let date = (try? fractional.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text)) { return date }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date \(text)"))
      }
      usage = try decoder.decode(Response.self, from: data).meters.sorted { $0.order < $1.order }
      usageError = nil
      usageUpdated = .now
    } catch is CancellationError {
    } catch {
      usageError = error.localizedDescription
    }
  }

  /// Streams one Flowcy agent turn. No tools are offered, so the reply is plain text.
  func streamChat(modelID: String, messages: [ChatMessage], onDelta: @MainActor @Sendable (String) -> Void) async throws -> String {
    let payload: [String: Any] = [
      "modelId": modelID,
      // The endpoint accepts user/assistant/tool turns only.
      "messages": messages.map { ["role": $0.role == "assistant" ? "assistant" : "user", "content": $0.content] },
      "tools": [Any](),
    ]
    let (bytes, response) = try await send("agent/chat", body: try JSONSerialization.data(withJSONObject: payload))
    guard response.value(forHTTPHeaderField: "Content-Type")?.contains("application/x-ndjson") == true else {
      throw FlowcyError.stream
    }
    var reply = ""
    for try await line in bytes.lines {
      try Task.checkCancellation()
      guard !line.isEmpty else { continue }
      guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
        throw FlowcyError.stream
      }
      switch event["type"] as? String {
      case "text":
        guard let text = event["text"] as? String else { throw FlowcyError.stream }
        reply += text
        onDelta(text)
      case "finish":
        guard !reply.trimmed.isEmpty else { throw APIError.empty }
        return reply
      case "error":
        throw FlowcyError.stream
      default:
        continue // Tool calls and future event types are not used for writing.
      }
    }
    try Task.checkCancellation()
    throw FlowcyError.interrupted
  }

  // MARK: - HTTP

  private func send(_ path: String, body: Data? = nil) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
    for forceRefresh in [false, true] {
      let token = try await accessToken(forceRefresh: forceRefresh)
      var request = URLRequest(url: Self.baseURL.appending(path: "api/v1").appending(path: path), timeoutInterval: 120)
      request.httpMethod = body == nil ? "GET" : "POST"
      request.httpBody = body
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      let (bytes, response) = try await URLSession.shared.bytes(for: request)
      guard let http = response as? HTTPURLResponse else { throw FlowcyError.stream }
      if http.statusCode == 401, !forceRefresh { continue }
      guard (200..<300).contains(http.statusCode) else {
        if http.statusCode == 401 { throw FlowcyError.sessionExpired }
        if http.statusCode == 429 { throw FlowcyError.limitReached }
        let data = (try? await Self.collect(bytes, limit: 64_000)) ?? Data()
        let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
        throw APIError.http(http.statusCode, message ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
      }
      return (bytes, http)
    }
    throw FlowcyError.sessionExpired
  }

  /// A server 401 can reject a token whose stored expiry still looks fresh, so a forced
  /// refresh marks it expired first; `refreshTokenIfNeeded` coalesces concurrent refreshes.
  private func accessToken(forceRefresh: Bool) async throws -> String {
    guard isSignedIn else { throw FlowcyError.signedOut }
    if forceRefresh { try? storage.saveExpiresAt(.distantPast) }
    do {
      try await manager.refreshTokenIfNeeded()
    } catch {
      throw FlowcyError.sessionExpired
    }
    guard let token = storage.getAccessToken() else { throw FlowcyError.signedOut }
    return token
  }

  private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
    var data = Data()
    for try await byte in bytes {
      data.append(byte)
      guard data.count <= limit else { throw FlowcyError.stream }
    }
    return data
  }

  private static func infoValue(_ key: String) -> String? {
    guard let value = (Bundle.main.object(forInfoDictionaryKey: key) as? String)?.trimmed,
          !value.isEmpty, !value.hasPrefix("$(") else { return nil }
    return value
  }
}

enum FlowcyError: LocalizedError {
  case signedOut, sessionExpired, limitReached, stream, interrupted

  var errorDescription: String? {
    switch self {
    case .signedOut: LocalizableKey.flowcySignInRequired.string
    case .sessionExpired: LocalizableKey.flowcySessionExpired.string
    case .limitReached: LocalizableKey.flowcyLimitReached.string
    case .stream: LocalizableKey.flowcyStreamFailed.string
    case .interrupted: LocalizableKey.flowcyInterrupted.string
    }
  }
}
