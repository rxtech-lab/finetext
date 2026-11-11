import Foundation

@main struct DeepLinkTests {
  static func main() {
    let routes: [(String, DeepLink)] = [
      ("finetext://rewrite", .rewrite),
      ("finetext://rewrite/", .rewrite),
      ("finetext://settings", .settings(.general)),
      ("finetext://settings/local/hugging-face", .huggingFace),
    ] + SettingsTab.allCases.map { ("finetext://settings/\($0.rawValue)", .settings($0)) }
    for (url, expected) in routes {
      precondition(DeepLink(url: URL(string: url)!) == expected, url)
    }
    for url in ["https://settings/providers", "finetext://oauth-callback?code=secret",
                "finetext://settings/missing", "finetext://settings/providers/delete",
                "finetext://rewrite?text=untrusted", "finetext://settings/providers#delete",
                "finetext://user@settings/providers", "finetext://settings:123/providers"] {
      precondition(DeepLink(url: URL(string: url)!) == nil, url)
    }
    print("Deep link navigation and rejection checks passed")
  }
}
