import Foundation

struct ClaudeCodeInstall: Equatable, Sendable {
  let executable: URL
  let version: String
}

enum ClaudeCodeLocator {
  static func environment(for executable: URL) -> [String: String] {
    var environment = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    environment["PATH"] = ([executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin",
                             "\(home)/.local/bin", "\(home)/.volta/bin", "\(home)/.bun/bin",
                             environment["PATH"] ?? "/usr/bin:/bin"]).joined(separator: ":")
    return environment
  }

  static func locate() async -> ClaudeCodeInstall? {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var paths = ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                 "\(home)/.npm-global/bin/claude", "\(home)/.bun/bin/claude", "\(home)/.volta/bin/claude"]
      .filter { FileManager.default.isExecutableFile(atPath: $0) }
    if paths.isEmpty, let path = await probe("/bin/zsh", ["-lc", "command -v claude"])?.trimmed,
       FileManager.default.isExecutableFile(atPath: path) { paths.append(path) }
    for path in paths {
      let executable = URL(fileURLWithPath: path)
      if let version = await probe(path, ["--version"], environment: environment(for: executable))?.trimmed,
         !version.isEmpty { return ClaudeCodeInstall(executable: executable, version: version) }
    }
    return nil
  }

  private static func probe(_ path: String, _ arguments: [String], environment: [String: String]? = nil) async -> String? {
    await Task.detached {
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
      process.environment = environment
      process.standardInput = FileHandle.nullDevice
      process.standardOutput = output
      process.standardError = FileHandle.nullDevice
      do {
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
      } catch { return nil }
    }.value
  }
}

enum ClaudeCodeError: LocalizedError {
  case notInstalled
  case failed(String)

  var errorDescription: String? {
    switch self {
    case .notInstalled: LocalizableKey.claudeCodeNotInstalled.string
    case .failed(let message): LocalizableKey.claudeCodeError.format(message)
    }
  }
}

