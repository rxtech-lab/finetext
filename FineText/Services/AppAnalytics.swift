import FirebaseAnalytics
import FirebaseCore
import Foundation

/// Anonymous product analytics (Google Analytics for Firebase).
///
/// Only feature names, model identifiers, provider kinds, settings choices and timings are sent.
/// Never log user text, prompts, outputs, images, API keys or custom provider URLs.
@MainActor enum AppAnalytics {
  static let enabledKey = DefaultsKey.analyticsEnabled

  enum Event: String {
    case appLaunched = "app_launched"
    case featureUsed = "feature_used"
    case itemAdded = "item_added"
    case generationStarted = "generation_started"
    case generationCompleted = "generation_completed"
    case generationFailed = "generation_failed"
    case generationCancelled = "generation_cancelled"
    case runAll = "run_all"
    case outputCopied = "output_copied"
    case imageSaved = "image_saved"
    case imageRefinementUndone = "image_refinement_undone"
    case sessionCleared = "session_cleared"
    case sessionOpened = "session_opened"
    case sessionDeleted = "session_deleted"
    case providerSaved = "provider_saved"
    case providerDeleted = "provider_deleted"
    case modelDownloaded = "model_downloaded"
    case modelRemoved = "model_removed"
    case settingChanged = "setting_changed"
  }

  static var isEnabled: Bool {
    UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
  }

  /// Configures Firebase once at launch. Debug builds only collect when launched with `-FIRDebugEnabled`
  /// so development runs don't pollute production reports (they show up in Firebase DebugView instead).
  static func configure() {
    guard FirebaseApp.app() == nil,
          Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
    FirebaseApp.configure()
    applyCollectionSetting()
    Analytics.setUserProperty(Locale.current.language.languageCode?.identifier, forName: "app_language")
    log(.appLaunched, ["app_version": AppUpdater.versionString])
  }

  static func setEnabled(_ enabled: Bool) {
    if !enabled { log(.settingChanged, ["setting": "analytics", "value": "off"]) }
    UserDefaults.standard.set(enabled, forKey: enabledKey)
    applyCollectionSetting()
    if enabled { log(.settingChanged, ["setting": "analytics", "value": "on"]) }
  }

  private static var collects: Bool {
    #if DEBUG
    return isEnabled && ProcessInfo.processInfo.arguments.contains("-FIRDebugEnabled")
    #else
    return isEnabled
    #endif
  }

  private static func applyCollectionSetting() {
    guard FirebaseApp.app() != nil else { return }
    Analytics.setAnalyticsCollectionEnabled(collects)
  }

  static func log(_ event: Event, _ parameters: [String: Any] = [:]) {
    guard FirebaseApp.app() != nil, collects else { return }
    // GA4 limits: 40-char names, 100-char string values, 25 parameters per event.
    let clean = parameters.reduce(into: [String: Any]()) { result, entry in
      let key = String(entry.key.prefix(40))
      switch entry.value {
      case let value as String: result[key] = String(value.prefix(100))
      case let value as Bool: result[key] = value ? 1 : 0
      case let value as Int: result[key] = value
      case let value as Double where value.isFinite: result[key] = value
      default: break
      }
    }
    Analytics.logEvent(event.rawValue, parameters: clean.isEmpty ? nil : clean)
  }

  static func screen(_ name: String) {
    guard FirebaseApp.app() != nil, collects else { return }
    Analytics.logEvent(AnalyticsEventScreenView, parameters: [
      AnalyticsParameterScreenName: name,
      AnalyticsParameterScreenClass: name,
    ])
  }

  static func feature(_ name: String, _ extra: [String: Any] = [:]) {
    log(.featureUsed, extra.merging(["feature": name]) { current, _ in current })
  }

  // MARK: Model description

  /// Model parameters shared by generation events: the model id and a coarse provider kind.
  static func modelParameters(_ model: ModelRef, providers: ProviderStore) -> [String: Any] {
    [
      "model": model.modelID.isEmpty ? "default" : model.modelID,
      "provider_type": providerType(model, providers: providers),
    ]
  }

  /// Coarse provider classification. Known public API hosts are named; anything else is reported as
  /// `custom` so self-hosted or private endpoints are never sent.
  static func providerType(_ model: ModelRef, providers: ProviderStore) -> String {
    if model.isLocal { return "local_mlx" }
    if providers.isCodex(model) { return "codex" }
    if providers.isClaudeCode(model) { return "claude_code" }
    return providerType(baseURL: providers.provider(model.providerID)?.baseURL)
  }

  static func providerType(baseURL: String?) -> String {
    guard let host = baseURL.flatMap({ URL(string: $0)?.host?.lowercased() }) else { return "custom" }
    let known: [(String, String)] = [
      ("ai-gateway.vercel.sh", "vercel_ai_gateway"), ("openai.com", "openai"), ("openrouter.ai", "openrouter"),
      ("anthropic.com", "anthropic"), ("googleapis.com", "google"), ("x.ai", "xai"), ("groq.com", "groq"),
      ("deepseek.com", "deepseek"), ("mistral.ai", "mistral"), ("together.xyz", "together"),
      ("fireworks.ai", "fireworks"), ("azure.com", "azure"), ("moonshot.ai", "moonshot"),
      ("dashscope.aliyuncs.com", "qwen"), ("bigmodel.cn", "zhipu"),
    ]
    if host == "localhost" || host == "127.0.0.1" { return "localhost" }
    return known.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) })?.1 ?? "custom"
  }

  static func errorType(_ error: Error) -> String {
    let ns = error as NSError
    return "\(ns.domain.split(separator: ".").last ?? "unknown")_\(ns.code)"
  }
}
