import Foundation

// MARK: - Detection

/// A local Codex CLI install that FineText can drive through `codex app-server`.
struct CodexInstall: Equatable, Sendable {
  let executable: URL
  let version: String
}

enum CodexLocator {
  /// Common install locations: Homebrew, npm/bun/volta globals, and the binary bundled in Codex.app.
  private static var candidates: [String] {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    return [
      "/opt/homebrew/bin/codex",
      "/usr/local/bin/codex",
      "\(home)/.local/bin/codex",
      "\(home)/.npm-global/bin/codex",
      "\(home)/.bun/bin/codex",
      "\(home)/.volta/bin/codex",
      "\(home)/.cargo/bin/codex",
      "/Applications/Codex.app/Contents/Resources/codex",
      "\(home)/Applications/Codex.app/Contents/Resources/codex",
    ]
  }

  /// Extra PATH entries so npm-installed `codex` (a `#!/usr/bin/env node` script) can find node
  /// even though GUI apps launch with a minimal PATH.
  static func environment(for executable: URL) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let extra = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin",
                 "\(home)/.volta/bin", "\(home)/.bun/bin"]
    env["PATH"] = (extra + [env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"]).joined(separator: ":")
    return env
  }

  static func locate() async -> CodexInstall? {
    let fm = FileManager.default
    var paths = candidates.filter { fm.isExecutableFile(atPath: $0) }
    if paths.isEmpty, let fromShell = await run("/bin/zsh", ["-lc", "command -v codex"])?.trimmed, fm.isExecutableFile(atPath: fromShell) {
      paths.append(fromShell)
    }
    for path in paths {
      let url = URL(fileURLWithPath: path)
      guard let output = await run(path, ["--version"], environment: environment(for: url)) else { continue }
      let version = output.trimmed.split(separator: " ").last.map(String.init) ?? output.trimmed
      return CodexInstall(executable: url, version: version)
    }
    return nil
  }

  private static func run(_ path: String, _ arguments: [String], environment: [String: String]? = nil) async -> String? {
    await withCheckedContinuation { continuation in
      let process = Process()
      process.executableURL = URL(fileURLWithPath: path)
      process.arguments = arguments
      if let environment { process.environment = environment }
      let pipe = Pipe()
      process.standardOutput = pipe
      process.standardError = FileHandle.nullDevice
      process.terminationHandler = { process in
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        continuation.resume(returning: process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil)
      }
      do { try process.run() } catch { continuation.resume(returning: nil) }
    }
  }
}

// MARK: - App server

enum CodexError: LocalizedError {
  case notInstalled
  case notSignedIn
  case server(String)
  case noImage(String?)

  var errorDescription: String? {
    switch self {
    case .notInstalled: LocalizableKey.codexIsnTInstalledInstallItWithBrewInstallCodexOrNpmIGOpenaiCodex.string
    case .notSignedIn: LocalizableKey.codexIsnTSignedInRunCodexLoginInTerminalFirst.string
    case .server(let message): LocalizableKey.codexError.format(message)
    case .noImage(let reply):
      if let reply, !reply.isEmpty { LocalizableKey.codexNoImageReply.format(reply) } else { LocalizableKey.codexDidnTGenerateAnImage.string }
    }
  }
}

/// Drives `codex app-server` over JSON-RPC (JSONL on stdio). Each run starts its own short-lived process and an
/// ephemeral, read-only thread with a single turn, then exits.
final class CodexSession: @unchecked Sendable {
  private let process = Process()
  private let input = Pipe()
  private let output = Pipe()
  private let lock = NSLock()
  private var nextID = 0

  init(install: CodexInstall) {
    process.executableURL = install.executable
    process.arguments = ["app-server"]
    process.environment = CodexLocator.environment(for: install.executable)
    process.currentDirectoryURL = Self.workingDirectory
    process.standardInput = input
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
  }

  static var workingDirectory: URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "FineText-Codex", directoryHint: .isDirectory)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  /// Runs one turn and terminates the server when done or cancelled.
  static func perform<T>(install: CodexInstall, turn: Turn<T>, onStatus: @MainActor @Sendable (String) -> Void) async throws -> T {
    let session = CodexSession(install: install)
    return try await withTaskCancellationHandler {
      try await session.run(turn, onStatus: onStatus)
    } onCancel: {
      session.terminate()
    }
  }

  /// A single turn: what to send and how to read the notifications it produces.
  struct Turn<T> {
    var instructions: String
    var input: [[String: Any]]
    var effort: String?
    /// Called for every server notification; return a value to finish the run.
    var handle: (_ method: String, _ params: [String: Any]) async throws -> T?
  }

  func terminate() {
    if process.isRunning { process.terminate() }
  }

  private func send(_ object: [String: Any]) throws {
    var data = try JSONSerialization.data(withJSONObject: object)
    data.append(0x0A)
    try input.fileHandleForWriting.write(contentsOf: data)
  }

  @discardableResult
  private func request(_ method: String, _ params: [String: Any]) throws -> Int {
    lock.lock()
    nextID += 1
    let id = nextID
    lock.unlock()
    try send(["id": id, "method": method, "params": params])
    return id
  }

  private func run<T>(_ turn: Turn<T>, onStatus: @MainActor @Sendable (String) -> Void) async throws -> T {
    try process.run()
    defer { terminate() }
    await onStatus(LocalizableKey.startingCodex.string)

    let initID = try request("initialize", [
      "clientInfo": ["name": "finetext", "title": "FineText", "version": AppInfo.version],
      "capabilities": NSNull(),
    ])
    var accountID: Int?
    var threadID: String?

    for try await line in output.fileHandleForReading.bytes.lines {
      try Task.checkCancellation()
      guard let data = line.data(using: .utf8),
            let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
      let method = message["method"] as? String
      let params = message["params"] as? [String: Any] ?? [:]

      // Server → client request (approvals, etc.). The thread is read-only, so decline everything.
      if method != nil, let id = message["id"] {
        try send(["id": id, "result": ["decision": "decline"]])
        continue
      }

      // Responses to our requests.
      if let id = message["id"] as? Int {
        if let error = message["error"] as? [String: Any] {
          throw CodexError.server((error["message"] as? String) ?? LocalizableKey.requestFailed.string)
        }
        let result = message["result"] as? [String: Any] ?? [:]
        switch id {
        case initID:
          try send(["method": "initialized"])
          accountID = try request("account/read", [:])
        case accountID:
          let requiresAuth = result["requiresOpenaiAuth"] as? Bool ?? false
          if requiresAuth, result["account"] == nil || result["account"] is NSNull { throw CodexError.notSignedIn }
          try request("thread/start", [
            "cwd": Self.workingDirectory.path,
            "approvalPolicy": "never",
            "sandbox": "read-only",
            "ephemeral": true,
            "developerInstructions": turn.instructions,
          ])
        default:
          if threadID == nil, let thread = result["thread"] as? [String: Any], let id = thread["id"] as? String {
            threadID = id
            var params: [String: Any] = ["threadId": id, "input": turn.input]
            if let effort = turn.effort { params["effort"] = effort }
            try request("turn/start", params)
            await onStatus(LocalizableKey.codexIsThinking.string)
          }
        }
        continue
      }

      guard let method else { continue }
      if method == "error", let error = params["error"] as? [String: Any], let text = error["message"] as? String,
         params["willRetry"] as? Bool != true {
        throw CodexError.server(text)
      }
      if method == "turn/completed", let error = (params["turn"] as? [String: Any])?["error"] as? [String: Any],
         let text = error["message"] as? String {
        throw CodexError.server(text)
      }
      if let value = try await turn.handle(method, params) { return value }
    }
    try Task.checkCancellation()
    throw CodexError.server(LocalizableKey.theAppServerExitedUnexpectedlyMakeSureCodexWorksInTerminal.string)
  }

  static func textInput(_ text: String) -> [String: Any] {
    ["type": "text", "text": text, "text_elements": [Any]()]
  }

  private static let toolRules = "Do not run shell commands, read or edit files, browse, or ask follow-up questions."
}

// MARK: - Images

extension CodexSession {
  /// Generates an image with Codex's built-in image tool. Pass `inputImage` to edit an existing image; it's
  /// attached to the turn as a local image.
  static func generateImage(install: CodexInstall, prompt: String, inputImage: Data? = nil,
                            onStatus: @MainActor @Sendable @escaping (String) -> Void) async throws -> Data {
    var attachment: URL?
    if let inputImage {
      let url = workingDirectory.appending(path: "input-\(UUID().uuidString).png")
      try inputImage.write(to: url)
      attachment = url
    }
    defer { if let attachment { try? FileManager.default.removeItem(at: attachment) } }

    var input = [textInput(prompt)]
    if let attachment { input.append(["type": "localImage", "path": attachment.path]) }

    final class State: @unchecked Sendable { var lastReply: String?; var failure: String? }
    let state = State()
    let turn = Turn<Data>(instructions: imageInstructions, input: input, effort: nil) { method, params in
      switch method {
      case "item/started":
        if (params["item"] as? [String: Any])?["type"] as? String == "imageGeneration" {
          await onStatus(LocalizableKey.codexIsGeneratingTheImage.string)
        }
      case "item/completed":
        guard let item = params["item"] as? [String: Any] else { return nil }
        switch item["type"] as? String {
        case "imageGeneration":
          if let image = imageData(from: item) { return image }
          if let failure = item["failure"] as? [String: Any] {
            state.failure = failure["type"] as? String == "usageLimitExceeded"
              ? LocalizableKey.codexImageGenerationLimitReachedTryAgainLater.string
              : LocalizableKey.imageGenerationFailed.string
          }
        case "agentMessage":
          if let text = (item["text"] as? String)?.trimmed, !text.isEmpty { state.lastReply = text }
        default: break
        }
      case "turn/completed":
        if let failure = state.failure { throw CodexError.server(failure) }
        throw CodexError.noImage(state.lastReply)
      default: break
      }
      return nil
    }
    return try await perform(install: install, turn: turn, onStatus: onStatus)
  }

  private static func imageData(from item: [String: Any]) -> Data? {
    if let base64 = item["result"] as? String, !base64.isEmpty {
      let payload = base64.hasPrefix("data:") ? String(base64[(base64.firstIndex(of: ",").map { base64.index(after: $0) } ?? base64.startIndex)...]) : base64
      if let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters) { return data }
    }
    if let path = item["savedPath"] as? String, let data = FileManager.default.contents(atPath: path) { return data }
    return nil
  }

  private static let imageInstructions = """
    You are an image generator inside the FineText app. For every request, call your image generation tool exactly once \
    using the user's description, then stop. When an image is attached, edit that image as the user asks instead of \
    starting from scratch. When the user asks for a transparent background, request a transparent background from the \
    image tool. \(toolRules)
    """
}

enum AppInfo {
  static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
}
