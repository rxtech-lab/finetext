import AppKit
import SwiftUI

@MainActor @Observable final class AppNavigation {
  static let shared = AppNavigation()
  struct Request {
    let id = UUID()
    let destination: DeepLink
  }
  var request: Request?
  var browseHuggingFace = false
}

/// Receives URLs even on cold launch, before a Settings or menu view exists.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
  func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      guard let destination = DeepLink(url: url) else { continue }
      AppNavigation.shared.request = .init(destination: destination)
    }
  }
}

/// The menu label stays mounted when the menu and Settings are closed.
struct DeepLinkMenuLabel: View {
  let workspace: Workspace
  @Environment(\.openSettings) private var openSettings
  @Environment(\.openWindow) private var openWindow
  @State private var navigation = AppNavigation.shared

  var body: some View {
    Image(systemName: "wand.and.sparkles")
      .onChange(of: navigation.request?.id, initial: true) { _, _ in
        guard let request = navigation.request else { return }
        navigation.request = nil
        switch request.destination {
        case .rewrite:
          workspace.route = nil
          workspace.tab = .rewrite
          openWindow(id: "workspace")
        case .settings(let tab):
          showSettings(tab)
        case .huggingFace:
          navigation.browseHuggingFace = true
          showSettings(.local)
        }
        NSApp.activate()
      }
  }

  private func showSettings(_ tab: SettingsTab) {
    UserDefaults.standard.set(tab.rawValue, forKey: DefaultsKey.settingsTab)
    openSettings()
  }
}
