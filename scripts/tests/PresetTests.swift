import Foundation

// Only the app's unrelated model-download defaults are stubbed in this standalone check.
enum HumanizationEngine: String { case translateGemma }
enum AIDetectorEngine: String { case disabled }
struct TranslationModel { var id = "test"; static let `default` = TranslationModel() }

private struct TemplateCases: Decodable {
  struct Render: Decodable { let name: String; let template: String; let context: [String: TemplateValue]; let expected: String }
  struct Failure: Decodable { let name: String; let template: String }
  let render: [Render]
  let errors: [Failure]
}

/// Serves canned catalog responses to `PresetStore` without a network.
final class MockServer: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var response: (status: Int, body: Data)?
  nonisolated(unsafe) static var requests = 0

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    Self.requests += 1
    guard let response = Self.response else {
      client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
      return
    }
    let http = HTTPURLResponse(url: request.url!, statusCode: response.status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: response.body)
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}

func check(_ condition: @autoclosure () -> Bool, _ message: String, file: StaticString = #file, line: UInt = #line) {
  if !condition() {
    print("FAIL \(file):\(line): \(message)")
    exit(1)
  }
}

@main struct PresetTests {
  @MainActor static func main() async throws {
    let root = URL(fileURLWithPath: CommandLine.arguments[1])
    let scratch = URL(fileURLWithPath: CommandLine.arguments[2])
    try templateCases(root)
    let bundled = root.appending(path: "FineText/Resources/presets.json")
    try bundledCatalog(bundled)
    structuredOutput()
    customPlatformTree()
    try await store(bundled: bundled, scratch: scratch)
    print("Preset tests passed.")
  }

  static func templateCases(_ root: URL) throws {
    let data = try Data(contentsOf: root.appending(path: "website/src/lib/preset-template-cases.json"))
    let cases = try JSONDecoder().decode(TemplateCases.self, from: data)
    for item in cases.render {
      let output = try PresetTemplate.render(item.template, context: item.context)
      check(output == item.expected, "\(item.name): expected \(item.expected.debugDescription), got \(output.debugDescription)")
    }
    for item in cases.errors {
      check((try? PresetTemplate.render(item.template, context: [:])) == nil, "\(item.name) should fail")
    }
    print("Template cases: \(cases.render.count) rendered, \(cases.errors.count) rejected, matching the website.")
  }

  static func bundledCatalog(_ url: URL) throws {
    let catalog = try PresetCatalog.decode(try Data(contentsOf: url))
    let entries = catalog.entries
    check(entries.count == 21, "expected 21 migrated presets, got \(entries.count)")
    check(Set(entries.map(\.id)).count == entries.count, "duplicate preset ids")
    for id in ["x", "xReply", "emailSend", "reddit", "blog", "message", "productHuntMakerComment"] {
      check(catalog.entries.contains { $0.id == id }, "missing legacy id \(id)")
    }
    let x = entries.first { $0.id == "x" }!
    check(x.path.map(\.english) == ["X", "Post"], "X post path")
    check(x.path.last!.resolved(for: "zh-TW") == "貼文", "localized title")
    check(x.path.last!.resolved(for: "fr") == "Post", "English fallback")
    let guidelines = PresetSnapshot(x).guidelines(tone: .witty)
    check(guidelines.contains("at most 280 characters"), "character_limit renders: \(guidelines)")
    for entry in entries {
      let rendered = PresetSnapshot(entry).guidelines(tone: entry.preset.defaultTone)
      check(!rendered.isEmpty && !rendered.contains("{{") && !rendered.contains("{%"), "\(entry.id) renders cleanly")
      check((try? PresetTemplate.render(entry.preset.template, context: [:])) != nil, "\(entry.id) template parses")
    }
    let email = entries.first { $0.id == "emailSend" }!
    check(email.path.map(\.english) == ["Email", "Send"], "email path")
    check(email.preset.fields?.map(\.id) == ["subject", "body"], "email fields")
    check(email.preset.fields?.last?.multiline == true, "email body is multiline")
    check(email.preset.defaultTone == .professional, "email tone")

    // Nested menus of any depth and node types from newer catalogs.
    let nested = """
    {"schemaVersion":1,"version":"v","items":[{"type":"menu","id":"a","title":{"en":"A"},"children":[
      {"type":"menu","id":"a/b","title":{"en":"B"},"children":[{"type":"menu","id":"a/b/c","title":{"en":"C"},"children":[
        {"type":"preset","id":"deep","title":{"en":"Deep"},"promptTitle":"Deep","template":"x"}]}]},
      {"type":"divider"}]}]}
    """
    let deep = try PresetCatalog.decode(Data(nested.utf8))
    check(deep.entries.map(\.title) == ["A · B · C · Deep"], "deep path \(deep.entries.map(\.title))")
    if case .menu(let menu) = deep.items[0] { check(menu.contains("deep") && !menu.contains("nope"), "menu contains") }
    check((try? PresetCatalog.decode(Data(#"{"schemaVersion":99,"version":"v","items":[]}"#.utf8))) == nil, "newer schema rejected")
    check((try? PresetCatalog.decode(Data(#"{"schemaVersion":1,"version":"v","items":[]}"#.utf8))) == nil, "empty rejected")
    print("Bundled catalog: \(entries.count) presets render; legacy ids, fields and nesting verified.")
  }

  static func structuredOutput() {
    let fields = [
      PresetField(id: "subject", label: LocalizedText(["en": "Subject"])),
      PresetField(id: "body", label: LocalizedText(["en": "Body"]), multiline: true),
    ]
    let model = "<subject>Lunch on Friday?</subject>\n<body>\nHi Sam,\n\nAre you free?\n</body>"
    let values = StructuredOutput.parse(model, fields: fields)
    check(values == ["subject": "Lunch on Friday?", "body": "Hi Sam,\n\nAre you free?"], "parse \(String(describing: values))")
    check(StructuredOutput.plainText(model, fields: fields) == "Subject: Lunch on Friday?\n\nHi Sam,\n\nAre you free?", "plain text")
    // Streaming output without closing tags still splits per field.
    let partial = StructuredOutput.parse("<subject>Hello\n<body>Draft so f", fields: fields)
    check(partial == ["subject": "Hello", "body": "Draft so f"], "partial \(String(describing: partial))")
    check(StructuredOutput.parse("Subject: legacy text", fields: fields) == nil, "legacy text has no fields")
    check(StructuredOutput.plainText("Subject: legacy text", fields: fields) == "Subject: legacy text", "legacy passthrough")
    // Editing a field keeps the user's own whitespace, including a trailing newline.
    var edited = values!
    edited["body"] = "Hi Sam,\n"
    let composed = StructuredOutput.compose(edited, fields: fields)
    check(StructuredOutput.parse(composed, fields: fields)?["body"] == "Hi Sam,\n", "round trip keeps whitespace")
    check(StructuredOutput.formatInstruction(fields).contains("<body>Body (may span several lines)</body>"), "format instruction")
    print("Structured output: parse, partial streams, legacy text, edits and plain text verified.")
  }

  static func customPlatformTree() {
    let a = CustomPlatform(name: "A", instruction: "a")
    let deep = CustomPlatform(name: "Deep", instruction: "d", folder: "Work/Clients/Acme")
    let client = CustomPlatform(name: "Client", instruction: "c", folder: "Work/Clients")
    let notes = CustomPlatform(name: "Notes", instruction: "n", folder: "Personal")
    let tree = CustomPlatformNode.tree([a, deep, client, notes])
    check(tree.map(\.id) == ["folder:Personal", "folder:Work", a.id.uuidString], "folders first, sorted, then presets: \(tree.map(\.id))")
    guard case .folder(_, _, let work) = tree[1], case .folder(let name, let path, let clients) = work[0] else { return check(false, "nested folders") }
    check(name == "Clients" && path == "Work/Clients", "folder path")
    check(clients.map(\.id) == ["folder:Work/Clients/Acme", client.id.uuidString], "third level")
    check(tree[1].contains(deep.id) && !tree[0].contains(deep.id), "contains")
    check(CustomPlatform.normalizedFolder(" Work / / Clients/ ") == "Work/Clients", "normalize")
    check(CustomPlatform.normalizedFolder(" / ") == nil, "empty folder is top level")
    check(CustomPlatform.folders(in: [deep, notes]) == ["Personal", "Work", "Work/Clients", "Work/Clients/Acme"], "folder list")
    // Presets saved before folders existed still decode.
    let legacy = try? JSONDecoder().decode(CustomPlatform.self, from: Data(#"{"id":"\#(UUID().uuidString)","name":"Old","instruction":"x"}"#.utf8))
    check(legacy?.folder == nil && legacy?.name == "Old", "legacy custom preset decodes")
    print("Custom presets: nested submenus, ordering, normalization and legacy decoding verified.")
  }

  @MainActor static func store(bundled: URL, scratch: URL) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockServer.self]
    let session = URLSession(configuration: configuration)
    let cache = scratch.appending(path: "cache/presets.json")
    let remote = URL(string: "http://localhost:3000/api/presets")!
    let bundledVersion = try PresetCatalog.decode(Data(contentsOf: bundled)).version

    // First launch, offline: the bundled catalog is used and kept.
    MockServer.response = nil
    let offline = PresetStore(remoteURL: remote, cacheURL: cache, bundled: bundled, session: session)
    check(offline.catalog.version == bundledVersion, "bundled fallback")
    let r1 = await offline.refresh()
    check(r1 == false && offline.lastError != nil, "offline refresh fails softly")
    check(offline.entries.count == 21, "offline keeps presets")

    // A new catalog downloads, replaces the menu and is cached for later launches.
    let fresh = """
    {"schemaVersion":1,"version":"new","items":[{"type":"menu","id":"m","title":{"en":"Menu"},"children":[
      {"type":"preset","id":"x","title":{"en":"Post"},"promptTitle":"X Post","characterLimit":200,"template":"limit {{ character_limit }}"}]}]}
    """
    MockServer.response = (200, Data(fresh.utf8))
    let r2 = await offline.refresh()
    check(r2 == true, "new catalog installed")
    check(offline.catalog.version == "new" && offline.lastError == nil && offline.lastChecked != nil, "store updated")
    check(offline.entry(id: "x").map { PresetSnapshot($0).guidelines(tone: .natural) } == "limit 200", "fresh template")
    let r3 = await offline.refresh()
    check(r3 == false, "same version is not reinstalled")

    // Server errors and bad payloads keep the cached copy.
    MockServer.response = (500, Data())
    let r4 = await offline.refresh()
    check(r4 == false && offline.catalog.version == "new", "HTTP error keeps cache")
    MockServer.response = (200, Data("not json".utf8))
    let r5 = await offline.refresh()
    check(r5 == false && offline.catalog.version == "new", "bad JSON keeps cache")

    // The next launch reads the cache, even offline.
    MockServer.response = nil
    let relaunched = PresetStore(remoteURL: remote, cacheURL: cache, bundled: bundled, session: session)
    check(relaunched.catalog.version == "new", "cache survives relaunch")

    // Without a configured URL nothing is requested.
    let before = MockServer.requests
    let unconfigured = PresetStore(remoteURL: nil, cacheURL: scratch.appending(path: "none.json"), bundled: bundled, session: session)
    let r6 = await unconfigured.refresh()
    check(r6 == false && MockServer.requests == before, "no URL, no request")
    print("Preset store: bundled fallback, download, cache, relaunch and failure handling verified.")
  }
}
