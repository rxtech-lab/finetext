import AppKit
import Sparkle
import SwiftData
import SwiftUI

@main struct FineTextApp: App {
  @State private var providers: ProviderStore
  @State private var preferences: Preferences
  @State private var presets: PresetStore
  @State private var workspace: Workspace
  @State private var gemma = TranslationModelManager()
  @State private var updater = AppUpdater()
  @State private var detector = AIDetectorManager()
  private let container: ModelContainer

  init() {
    DefaultsKey.register()
    AppAnalytics.configure()
    let container = Persistence.makeContainer()
    let providers = ProviderStore()
    let preferences = Preferences()
    let presets = PresetStore()
    presets.startAutoRefresh()
    self.container = container
    _providers = State(initialValue: providers)
    _preferences = State(initialValue: preferences)
    _presets = State(initialValue: presets)
    _workspace = State(initialValue: Workspace(container: container, providers: providers, preferences: preferences, presets: presets))
  }

  var body: some Scene {
    MenuBarExtra {
      MenuContentView()
        .environment(workspace)
        .environment(providers)
        .environment(preferences)
        .environment(presets)
        .environment(updater)
        .modelContainer(container)
    } label: {
      Image(systemName: "wand.and.sparkles")
    }
    .menuBarExtraStyle(.window)

    Settings {
      SettingsView()
        .environment(providers)
        .environment(providers.local)
        .environment(preferences)
        .environment(presets)
        .environment(gemma)
        .environment(detector)
        .environment(updater)
    }
  }
}

/// Sparkle updater. Only started when the build carries a public EdDSA key (CI release builds).
@MainActor @Observable final class AppUpdater {
  private let controller: SPUStandardUpdaterController
  let isConfigured: Bool

  init() {
    let key = (Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String ?? "").trimmed
    isConfigured = !key.isEmpty && !key.hasPrefix("$(")
    controller = SPUStandardUpdaterController(startingUpdater: isConfigured, updaterDelegate: nil, userDriverDelegate: nil)
  }

  var automaticallyChecks: Bool {
    get { access(keyPath: \.automaticallyChecks); return controller.updater.automaticallyChecksForUpdates }
    set { withMutation(keyPath: \.automaticallyChecks) { controller.updater.automaticallyChecksForUpdates = newValue } }
  }

  func checkForUpdates() {
    NSApp.activate()
    controller.checkForUpdates(nil)
  }

  static var versionString: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "0"
    let build = info?["CFBundleVersion"] as? String ?? "0"
    return "\(version) (\(build))"
  }
}
