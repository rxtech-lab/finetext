import Foundation

enum SettingsTab: String, CaseIterable {
  case general, platforms, providers, agents, flowcy, local, humanizer, mcp
}

/// Navigation only: links never start generation, downloads, or account actions.
enum DeepLink: Equatable {
  case rewrite
  case settings(SettingsTab)
  case huggingFace

  init?(url: URL) {
    guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
          parts.scheme?.lowercased() == "finetext",
          parts.user == nil, parts.password == nil, parts.port == nil,
          parts.query == nil, parts.fragment == nil else { return nil }
    switch (parts.host?.lowercased(), parts.path) {
    case ("rewrite", ""), ("rewrite", "/"): self = .rewrite
    case ("settings", ""), ("settings", "/"): self = .settings(.general)
    case ("settings", "/local/hugging-face"): self = .huggingFace
    case ("settings", let path):
      guard path.hasPrefix("/"), let tab = SettingsTab(rawValue: String(path.dropFirst())) else { return nil }
      self = .settings(tab)
    default: return nil
    }
  }
}
