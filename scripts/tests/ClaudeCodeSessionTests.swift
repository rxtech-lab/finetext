import Foundation
import RxAgentSDK

struct ChatMessage: Sendable { let role: String; let content: String }
enum APIError: Error { case empty; case http(Int, String) }
extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

@main struct AgentAdapterTests {
  static func check(_ condition: Bool, _ message: String) throws {
    if !condition { throw NSError(domain: message, code: 1) }
  }

  @MainActor static func main() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appendingPathComponent("agent")
    func fixture(_ body: String) throws {
      try ("#!/usr/bin/python3\nimport sys, json, time\n" + body + "\n").write(to: executable, atomically: true, encoding: .utf8)
      try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }
    let messages = [ChatMessage(role: "system", content: "Rewrite this."),
                    ChatMessage(role: "user", content: String(repeating: "Long draft 中文\n", count: 20000))]
    var deltas = ""
    let claude = AgentTextSession.claude(ClaudeCodeInstall(executable: executable, version: "test"))
    let codex = AgentTextSession.codex(CodexInstall(executable: executable, version: "test"))
    try fixture("""
    msg = json.loads(sys.stdin.readline())
    assert msg['request']['subtype'] == 'initialize'
    print(json.dumps({'type':'control_response','response':{'request_id':msg['request_id'],
      'response':{'models':[{'value':'chosen-claude','displayName':'Chosen Claude'}]}}}), flush=True)
    time.sleep(1)
    """)
    let claudeModels = await claude.availableModels()
    try check(claudeModels.map(\.id) == ["chosen-claude"], "Discovers Claude models without a conversation")
    try fixture("""
    for line in sys.stdin:
        msg = json.loads(line)
        if 'id' not in msg: continue
        result = {'data':[{'id':'chosen-codex','displayName':'Chosen Codex'}]} if msg['method'] == 'model/list' else {}
        print(json.dumps({'id':msg['id'],'result':result}), flush=True)
    """)
    let codexModels = await codex.availableModels()
    try check(codexModels.map(\.id) == ["chosen-codex"], "Discovers Codex models without a conversation")
    // Verify the selected model reaches Claude's argv, while the draft stays on stdin.
    try fixture("""
    assert sys.argv[sys.argv.index('--model') + 1] == 'chosen-claude'
    assert '--no-session-persistence' in sys.argv and '--strict-mcp-config' in sys.argv
    assert sys.argv[sys.argv.index('--tools') + 1] == ''
    prompt = json.loads(sys.stdin.readline())['message']['content'][0]['text']
    assert len(prompt) > 100000 and 'Long draft' not in ' '.join(sys.argv)
    print(json.dumps({'type':'assistant','message':{'content':[{'type':'text','text':'Hello 中文'}]}}), flush=True)
    print(json.dumps({'type':'result','is_error':False}), flush=True)
    """)
    let result = try await AgentTextSession.chat(client: claude, messages: messages, model: "chosen-claude", status: "Writing",
                                                onStatus: { _ in }, onDelta: { deltas += $0 })
    try check(result == "Hello 中文" && deltas == result, "Claude response delivered once")
    // Codex's model is a turn/start parameter, and its thread must remain read-only.
    try fixture("""
    for line in sys.stdin:
        msg = json.loads(line)
        method = msg.get('method')
        if 'id' not in msg: continue
        params = msg.get('params', {})
        result = {}
        if method == 'thread/start':
            assert params['sandbox'] == 'read-only' and params['approvalPolicy'] == 'untrusted'
            assert 'Rewrite this.' in params['developerInstructions']
            result = {'thread':{'id':'test-thread'}}
        if method == 'turn/start':
            assert params['model'] == 'chosen-codex'
            assert len(params['input'][0]['text']) > 100000
        print(json.dumps({'id':msg['id'],'result':result}), flush=True)
        if method == 'turn/start':
            print(json.dumps({'method':'item/agentMessage/delta','params':{'delta':'Codex reply'}}), flush=True)
            print(json.dumps({'method':'turn/completed','params':{}}), flush=True)
    """)
    deltas = ""
    let codexResult = try await AgentTextSession.chat(client: codex, messages: messages, model: "chosen-codex", status: "Writing",
                                                     onStatus: { _ in }, onDelta: { deltas += $0 })
    try check(codexResult == "Codex reply" && deltas == codexResult, "Codex streams selected model")
    try check(CLIModels.explicitModel("codex-text") == nil && CLIModels.explicitModel("claude-code-text") == nil,
              "Saved default model references remain compatible")
    for body in [
      "sys.stdin.readline(); print(json.dumps({'type':'result','is_error':True}), flush=True)",
      "sys.stdin.readline(); print(json.dumps({'type':'result','is_error':False}), flush=True)",
      "sys.stdin.readline(); sys.exit(1)"
    ] {
      try fixture(body)
      var failed = false
      do {
        _ = try await AgentTextSession.chat(client: claude, messages: messages, model: nil, status: "Writing",
                                            onStatus: { _ in }, onDelta: { _ in })
      } catch { failed = true }
      try check(failed, "Rejects CLI errors, empty replies and unexpected exits")
    }
    try fixture("sys.stdin.readline(); time.sleep(20)")
    for client: any AgentClient in [claude, codex] {
      let task = Task {
        try await AgentTextSession.chat(client: client, messages: messages, model: nil, status: "Writing",
                                        onStatus: { _ in }, onDelta: { _ in })
      }
      try await Task.sleep(for: .milliseconds(200))
      task.cancel()
      do { _ = try await task.value; throw NSError(domain: "Cancellation ignored", code: 1) }
      catch is CancellationError { }
    }
    print("Passed SDK adapter tests: Claude/Codex model discovery and forwarding, large stdin, streaming, legacy defaults, errors, cancellation.")
  }
}
