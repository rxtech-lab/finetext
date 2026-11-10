import Foundation
import Network
import Observation

/// One MCP request as shown in Settings → MCP → Request Log. Updated live while a tool runs.
@MainActor @Observable final class MCPLogEntry: Identifiable {
  enum Status: Equatable { case running, succeeded, failed(String), cancelled }

  let id = UUID()
  let date = Date.now
  let method: String
  let tool: String?
  let client: String
  let request: String
  private(set) var response = ""
  private(set) var status: Status = .running
  private(set) var duration: TimeInterval?
  private(set) var progress: [String] = []

  init(method: String, tool: String?, client: String, request: String) {
    self.method = method
    self.tool = tool
    self.client = client
    self.request = request
  }

  var title: String { tool ?? method }

  func report(_ message: String) {
    guard progress.last != message else { return }
    progress.append(message)
  }

  func finish(_ status: Status, response: String) {
    self.status = status
    self.response = response
    duration = Date.now.timeIntervalSince(date)
  }
}

/// A local MCP server (Streamable HTTP transport, protocol 2025-06-18) bound to 127.0.0.1.
/// Tool calls answer with an SSE stream when the client accepts one, so progress notifications
/// reach it while humanization rounds run. Closing the connection cancels the tool call.
@MainActor @Observable final class MCPServer {
  enum State: Equatable { case stopped, starting, running, failed(String) }

  static let defaultPort = 47821
  static let enabledKey = "mcpServerEnabled"
  static let portKey = "mcpServerPort"
  static let supportedVersions = ["2025-06-18", "2025-03-26", "2024-11-05"]
  private static let logLimit = 200
  private static let maxBodySize = 4 << 20

  private(set) var state: State = .stopped
  private(set) var log: [MCPLogEntry] = []
  private(set) var port: Int
  private let tools: MCPTools
  private var listener: NWListener?
  private var connections: [ObjectIdentifier: NWConnection] = [:]

  var isEnabled: Bool {
    didSet {
      UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
      isEnabled ? start() : stop()
    }
  }

  var url: String { "http://127.0.0.1:\(port)/mcp" }
  var runningCount: Int { log.filter { $0.status == .running }.count }

  init(tools: MCPTools) {
    self.tools = tools
    let defaults = UserDefaults.standard
    defaults.register(defaults: [Self.enabledKey: true, Self.portKey: Self.defaultPort])
    isEnabled = defaults.bool(forKey: Self.enabledKey)
    let saved = defaults.integer(forKey: Self.portKey)
    port = (1024...65535).contains(saved) ? saved : Self.defaultPort
    if isEnabled { start() }
  }

  func setPort(_ value: Int) {
    guard (1024...65535).contains(value), value != port else { return }
    port = value
    UserDefaults.standard.set(value, forKey: Self.portKey)
    if isEnabled { start() }
  }

  func clearLog() { log.removeAll { $0.status != .running } }

  // MARK: Listener

  func start() {
    stop()
    guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    // Loopback only: other machines on the network can never reach the tools.
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: endpointPort)
    do {
      let listener = try NWListener(using: parameters)
      state = .starting
      listener.stateUpdateHandler = { [weak self] newState in
        MainActor.assumeIsolated {
          guard let self, self.listener === listener else { return }
          switch newState {
          case .ready: self.state = .running
          case .failed(let error): self.state = .failed(error.localizedDescription); listener.cancel()
          case .cancelled: if self.state == .running { self.state = .stopped }
          default: break
          }
        }
      }
      listener.newConnectionHandler = { [weak self] connection in
        MainActor.assumeIsolated { self?.accept(connection) }
      }
      self.listener = listener
      listener.start(queue: .main)
    } catch {
      state = .failed(error.localizedDescription)
    }
  }

  func stop() {
    listener?.cancel()
    listener = nil
    connections.values.forEach { $0.cancel() }
    connections.removeAll()
    state = .stopped
  }

  private func accept(_ connection: NWConnection) {
    let key = ObjectIdentifier(connection)
    connections[key] = connection
    connection.stateUpdateHandler = { [weak self] newState in
      switch newState {
      case .failed, .cancelled: MainActor.assumeIsolated { _ = self?.connections.removeValue(forKey: key) }
      default: break
      }
    }
    connection.start(queue: .main)
    receive(on: connection, buffer: Data())
  }

  private func receive(on connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
      MainActor.assumeIsolated {
        guard let self else { return }
        var buffer = buffer
        if let data { buffer.append(data) }
        switch HTTPRequest.parse(buffer, maxBody: Self.maxBodySize) {
        case .complete(let request): self.handle(request, on: connection)
        case .invalid(let status): self.respond(connection, status: status, body: Data())
        case .incomplete:
          if isComplete || error != nil { connection.cancel() } else { self.receive(on: connection, buffer: buffer) }
        }
      }
    }
  }

  // MARK: HTTP

  private func handle(_ request: HTTPRequest, on connection: NWConnection) {
    // DNS-rebinding protection: browsers may only reach this server from local pages.
    if let origin = request.headers["origin"], let host = URL(string: origin)?.host, !["localhost", "127.0.0.1", "::1"].contains(host) {
      return respond(connection, status: 403, body: Data("Forbidden origin".utf8))
    }
    guard request.path.split(separator: "?").first.map(String.init) == "/mcp" else {
      return respond(connection, status: 404, body: Data("Not found. The MCP endpoint is /mcp.".utf8))
    }
    switch request.method {
    case "POST": handleRPC(request, on: connection)
    case "DELETE": respond(connection, status: 200, body: Data())
    // No server-initiated stream: every response is tied to a POST.
    default: respond(connection, status: 405, body: Data(), extraHeaders: ["Allow": "POST, DELETE"])
    }
  }

  private func handleRPC(_ request: HTTPRequest, on connection: NWConnection) {
    guard let object = try? JSONSerialization.jsonObject(with: request.body) else {
      return respondJSON(connection, Self.error(id: NSNull(), code: -32700, message: "Parse error"))
    }
    if object is [Any] {
      return respondJSON(connection, Self.error(id: NSNull(), code: -32600, message: "Batch requests are not supported"))
    }
    guard let message = object as? [String: Any], let method = message["method"] as? String else {
      // A response or malformed message from the client; nothing to answer.
      return respond(connection, status: 202, body: Data())
    }
    guard let id = message["id"] else {
      return respond(connection, status: 202, body: Data()) // notification
    }
    let params = message["params"] as? [String: Any] ?? [:]
    let client = request.headers["user-agent"].map { String($0.prefix(60)) } ?? "unknown"

    switch method {
    case "initialize":
      let requested = params["protocolVersion"] as? String ?? ""
      let version = Self.supportedVersions.contains(requested) ? requested : Self.supportedVersions[0]
      respondJSON(connection, Self.result(id: id, [
        "protocolVersion": version,
        "capabilities": ["tools": ["listChanged": false]],
        "serverInfo": ["name": "finetext", "title": "FineText", "version": AppUpdater.versionString],
        "instructions": MCPTools.instructions,
      ]))
      let name = (params["clientInfo"] as? [String: Any])?["name"] as? String
      record(method: method, tool: nil, client: name ?? client, request: message).finish(.succeeded, response: "protocol \(version)")
    case "ping":
      respondJSON(connection, Self.result(id: id, [:]))
    case "tools/list":
      let response = Self.result(id: id, ["tools": MCPTools.definitions])
      respondJSON(connection, response)
      record(method: method, tool: nil, client: client, request: message).finish(.succeeded, response: "\(MCPTools.definitions.count) tools")
    case "tools/call":
      callTool(id: id, params: params, message: message, client: client, request: request, on: connection)
    default:
      respondJSON(connection, Self.error(id: id, code: -32601, message: "Method not found: \(method)"))
    }
  }

  private func callTool(id: Any, params: [String: Any], message: [String: Any], client: String,
                        request: HTTPRequest, on connection: NWConnection) {
    let name = params["name"] as? String ?? ""
    let arguments = params["arguments"] as? [String: Any] ?? [:]
    let progressToken = (params["_meta"] as? [String: Any])?["progressToken"]
    let entry = record(method: "tools/call", tool: name, client: client, request: message)
    let streaming = request.headers["accept"]?.contains("text/event-stream") == true
    if streaming { startEventStream(connection) }
    var step = 0
    let progress: @MainActor (String) -> Void = { [weak self] text in
      entry.report(text)
      guard streaming, let progressToken, let self else { return }
      step += 1
      self.sendEvent(connection, ["jsonrpc": "2.0", "method": "notifications/progress",
                                  "params": ["progressToken": progressToken, "progress": step, "message": text]])
    }
    let task = Task { [weak self] in
      let outcome = await self?.tools.call(name, arguments: arguments, progress: progress)
      guard let self, let outcome else { return }
      let status: MCPLogEntry.Status = Task.isCancelled ? .cancelled : (outcome.isError ? .failed(outcome.text) : .succeeded)
      entry.finish(status, response: outcome.logText)
      guard !Task.isCancelled else { return }
      let response = Self.result(id: id, outcome.payload)
      if streaming {
        self.sendEvent(connection, response, final: true)
      } else {
        self.respondJSON(connection, response)
      }
    }
    // The client closing the connection (e.g. pressing Esc in vc-email) stops the tool and its model calls.
    watchForDisconnect(connection) {
      guard entry.status == .running else { return }
      task.cancel()
      entry.finish(.cancelled, response: "Client disconnected")
    }
  }

  private func watchForDisconnect(_ connection: NWConnection, onClose: @escaping @MainActor () -> Void) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { [weak self] data, _, isComplete, error in
      MainActor.assumeIsolated {
        if isComplete || error != nil { onClose() } else if data != nil { self?.watchForDisconnect(connection, onClose: onClose) }
      }
    }
  }

  private func record(method: String, tool: String?, client: String, request: [String: Any]) -> MCPLogEntry {
    let entry = MCPLogEntry(method: method, tool: tool, client: client, request: Self.pretty(request))
    log.insert(entry, at: 0)
    if log.count > Self.logLimit { log.removeLast(log.count - Self.logLimit) }
    return entry
  }

  // MARK: Responses

  private func respondJSON(_ connection: NWConnection, _ object: [String: Any]) {
    let body = (try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])) ?? Data()
    respond(connection, status: 200, body: body, extraHeaders: ["Content-Type": "application/json"])
  }

  private func respond(_ connection: NWConnection, status: Int, body: Data, extraHeaders: [String: String] = [:]) {
    var head = "HTTP/1.1 \(status) \(HTTPRequest.reason(status))\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
    for (key, value) in extraHeaders { head += "\(key): \(value)\r\n" }
    connection.send(content: Data((head + "\r\n").utf8) + body, isComplete: true, completion: .contentProcessed { _ in
      connection.cancel()
    })
  }

  private func startEventStream(_ connection: NWConnection) {
    let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: close\r\n\r\n"
    connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in })
  }

  private func sendEvent(_ connection: NWConnection, _ object: [String: Any], final: Bool = false) {
    guard let json = try? JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes]),
          let text = String(data: json, encoding: .utf8) else { return }
    let event = Data("event: message\ndata: \(text)\n\n".utf8)
    connection.send(content: event, isComplete: final, completion: .contentProcessed { _ in
      if final { connection.cancel() }
    })
  }

  private static func result(id: Any, _ result: [String: Any]) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "result": result]
  }

  private static func error(id: Any, code: Int, message: String) -> [String: Any] {
    ["jsonrpc": "2.0", "id": id, "error": ["code": code, "message": message]]
  }

  nonisolated static func pretty(_ object: Any) -> String {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
          let text = String(data: data, encoding: .utf8) else { return String(describing: object) }
    return text.count > 20000 ? String(text.prefix(20000)) + "\n…" : text
  }
}

/// A minimal HTTP/1.1 request parser: enough for JSON-RPC POSTs from MCP clients.
struct HTTPRequest {
  enum Parse { case incomplete, invalid(Int), complete(HTTPRequest) }

  let method: String
  let path: String
  let headers: [String: String]
  let body: Data

  static func parse(_ data: Data, maxBody: Int) -> Parse {
    guard let separator = data.range(of: Data("\r\n\r\n".utf8)) else {
      return data.count > 64 * 1024 ? .invalid(431) : .incomplete
    }
    guard let head = String(data: data[data.startIndex..<separator.lowerBound], encoding: .utf8) else { return .invalid(400) }
    let lines = head.components(separatedBy: "\r\n")
    let parts = lines.first?.split(separator: " ") ?? []
    guard parts.count >= 2 else { return .invalid(400) }
    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
      guard let colon = line.firstIndex(of: ":") else { continue }
      headers[line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    if headers["transfer-encoding"]?.lowercased().contains("chunked") == true { return .invalid(411) }
    let length = Int(headers["content-length"] ?? "0") ?? -1
    guard length >= 0 else { return .invalid(400) }
    guard length <= maxBody else { return .invalid(413) }
    let available = data.distance(from: separator.upperBound, to: data.endIndex)
    guard available >= length else { return .incomplete }
    let start = separator.upperBound
    let body = Data(data[start..<data.index(start, offsetBy: length)])
    return .complete(HTTPRequest(method: String(parts[0]).uppercased(), path: String(parts[1]), headers: headers, body: body))
  }

  static func reason(_ status: Int) -> String {
    switch status {
    case 200: "OK"
    case 202: "Accepted"
    case 400: "Bad Request"
    case 403: "Forbidden"
    case 404: "Not Found"
    case 405: "Method Not Allowed"
    case 411: "Length Required"
    case 413: "Payload Too Large"
    case 431: "Request Header Fields Too Large"
    default: "Error"
    }
  }
}
