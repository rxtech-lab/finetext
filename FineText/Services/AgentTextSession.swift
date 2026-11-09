import Foundation
import RxAgentSDK

/// Stable legacy IDs continue to mean the CLI's configured default.
enum CLIModels {
  static func explicitModel(_ id: String) -> String? {
    ["codex-text", "claude-code-text", "codex-image"].contains(id) ? nil : id
  }
}

enum AgentTextSession {
  static func codex(_ install: CodexInstall) -> CodexClient {
    CodexClient(binaryPath: install.executable.path, approvalPolicy: .untrusted, sandbox: .readOnly,
                environment: CodexLocator.environment(for: install.executable))
  }

  static func claude(_ install: ClaudeCodeInstall) -> ClaudeCodeClient {
    ClaudeCodeClient(binaryPath: install.executable.path,
                     extraArguments: ["--no-session-persistence", "--tools", "", "--disable-slash-commands",
                                      "--strict-mcp-config", "--mcp-config", "{\"mcpServers\":{}}"],
                     environment: ClaudeCodeLocator.environment(for: install.executable), preapprovedTools: [])
  }

  /// A new SDK client and thread per writing request prevent drafts sharing context.
  static func chat(
    client: any AgentClient, messages: [ChatMessage], model: String?, status: String,
    onStatus: @MainActor @Sendable @escaping (String) -> Void,
    onUsage: @MainActor @Sendable @escaping (GenerationUsage) -> Void = { _ in },
    onDelta: @MainActor @Sendable @escaping (String) -> Void
  ) async throws -> String {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FineText-Agent-\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let conversation = messages.filter { $0.role != "system" }
    let prompt = conversation.count == 1 ? conversation[0].content
      : conversation.map { "\($0.role.capitalized):\n\($0.content)" }.joined(separator: "\n\n")
    let instructions = (messages.filter { $0.role == "system" }.map(\.content) + [
      "You are a writing assistant inside FineText. Return only the requested text. Do not use tools, read files, run commands, browse, or ask follow-up questions."
    ]).joined(separator: "\n\n")
    let request = AgentSendRequest(threadID: AgentThreadID(), prompt: prompt, workingDirectory: directory,
                                   model: model, contextText: instructions, allowedTools: [])
    return try await withTaskCancellationHandler {
      defer { Task {
        await client.cancel(turn: request.turnID)
        await client.endSession(thread: request.threadID)
      } }
      try Task.checkCancellation()
      await onStatus(status)
      var reply = ""
      for await event in client.send(request) {
        try Task.checkCancellation()
        switch event {
        case .usage(let usage), .messageEnded(_, let usage?):
          await onUsage(GenerationUsage(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
                                       cachedTokens: usage.cacheReadTokens, costUSD: usage.totalCostUSD))
        case .textDelta(let delta):
          reply += delta
          await onDelta(delta)
        case .failed(let error):
          if error == .cancelled { throw CancellationError() }
          throw APIError.http(0, error.description)
        case .turnEnded(let result):
          if result.isBackgroundFollowUp { continue }
          if let usage = result.usage {
            await onUsage(GenerationUsage(inputTokens: usage.inputTokens, outputTokens: usage.outputTokens,
                                         cachedTokens: usage.cacheReadTokens, costUSD: usage.totalCostUSD))
          }
          guard !result.isError else { throw APIError.http(0, LocalizableKey.requestFailed.string) }
          guard !reply.trimmed.isEmpty else { throw APIError.empty }
          return reply
        default: break
        }
      }
      try Task.checkCancellation()
      throw APIError.empty
    } onCancel: {
      Task { await client.cancel(turn: request.turnID) }
    }
  }
}
