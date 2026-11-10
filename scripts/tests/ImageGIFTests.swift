import Foundation
import ImageIO
import AppKit
import SwiftData

enum HumanizationEngine: String { case translateGemma }
enum AIDetectorEngine: String { case disabled }
struct TranslationModel { var id = "test"; static let `default` = TranslationModel() }

final class ImageProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var check: ((URLRequest, Data) throws -> Void)?
  nonisolated(unsafe) static var response = Data()
  nonisolated(unsafe) static var statusCode = 200
  override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "gif.test" }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    do {
      var body = request.httpBody ?? Data()
      if let stream = request.httpBodyStream {
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
          let count = stream.read(&bytes, maxLength: bytes.count)
          if count <= 0 { break }
          body.append(contentsOf: bytes.prefix(count))
        }
      }
      try Self.check?(request, body)
      client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: Self.response)
      client?.urlProtocolDidFinishLoading(self)
    } catch { client?.urlProtocol(self, didFailWithError: error) }
  }
  override func stopLoading() {}
}

@main struct ImageGIFTests {
  /// Same binary doubles as a deterministic Codex app-server fixture.
  static func fakeCodex() throws {
    func send(_ value: [String: Any]) throws {
      var data = try JSONSerialization.data(withJSONObject: value); data.append(10)
      try FileHandle.standardOutput.write(contentsOf: data)
    }
    while let line = readLine() {
      let message = try JSONSerialization.jsonObject(with: Data(line.utf8)) as! [String: Any]
      guard let id = message["id"] as? Int, let method = message["method"] as? String else { continue }
      var result: [String: Any] = [:]
      if method == "account/read" { result = ["requiresOpenaiAuth": false] }
      if method == "thread/start" { result = ["thread": ["id": "fixture"]] }
      try send(["id": id, "result": result])
      if method == "turn/start" {
        let params = message["params"] as! [String: Any]
        let input = params["input"] as! [[String: Any]]
        precondition((input.first?["text"] as? String)?.contains("3 columns by 3 rows") == true)
        let sheet = try Data(contentsOf: URL(fileURLWithPath: ProcessInfo.processInfo.environment["FINETEXT_TEST_SHEET"]!))
        try send(["method": "item/completed", "params": ["item": ["type": "imageGeneration", "result": sheet.base64EncodedString()]]])
      }
    }
  }

  @MainActor static func main() async throws {
    if CommandLine.arguments.contains("app-server") { try fakeCodex(); return }
    let temporary = URL(fileURLWithPath: CommandLine.arguments[1])
    let grid = GIFFrameGrid(frameCount: 7, durationMS: 237, size: "512x512")
    precondition(grid.columns == 3 && grid.rows == 3 && grid.size == "1920x1920")
    precondition(grid.durationMS == 230)
    for count in 2...16 {
      for size in ["512x512", "768x512", "512x768"] {
        let plan = GIFFrameGrid(frameCount: count, durationMS: 200, size: size)
        let pixels = plan.columns * plan.frameWidth * plan.rows * plan.frameHeight
        precondition(pixels >= 655_360 && pixels <= 8_294_400)
        precondition(plan.columns * plan.frameWidth <= 3840 && plan.rows * plan.frameHeight <= 3840)
        precondition(plan.columns * plan.rows >= count)
      }
    }
    // Unique cell colors verify row-major cropping, including the transition to a new row.
    let colors: [[UInt8]] = [[255,0,0], [0,255,0], [0,0,255], [255,255,0], [0,255,255], [255,0,255], [255,128,0], [255,255,255], [0,0,0]]
    var pixels = [UInt8](repeating: 255, count: 48 * 48 * 4)
    for y in 0..<48 { for x in 0..<48 {
      let color = colors[y / 16 * 3 + x / 16]
      for component in 0..<3 { pixels[(y * 48 + x) * 4 + component] = color[component] }
    } }
    let provider = CGDataProvider(data: Data(pixels) as CFData)!
    let original = CGImage(width: 48, height: 48, bitsPerComponent: 8, bitsPerPixel: 32,
                           bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    let png = NSMutableData()
    let pngDestination = CGImageDestinationCreateWithData(png, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(pngDestination, original, nil)
    precondition(CGImageDestinationFinalize(pngDestination))
    let sheet = png as Data
    let gif = try grid.assemble(sheet)
    let source = CGImageSourceCreateWithData(gif as CFData, nil)!
    precondition(ImageOutput.isAnimatedGIF(gif) && CGImageSourceGetCount(source) == 7)
    let metadata = CGImageSourceCopyProperties(source, nil) as! [String: Any]
    precondition((metadata[kCGImagePropertyGIFDictionary as String] as! [String: Any])[kCGImagePropertyGIFLoopCount as String] as! Int == 0)
    for index in 0..<7 {
      let frame = CGImageSourceCreateImageAtIndex(source, index, nil)!
      precondition(frame.width == 16 && frame.height == 16)
      let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(frame, in: CGRect(x: 0, y: 0, width: 16, height: 16))
      let pixel = context.data!.assumingMemoryBound(to: UInt8.self).advanced(by: (8 * 16 + 8) * 4)
      for component in 0..<3 {
        precondition(abs(Int(pixel[component]) - Int(colors[index][component])) < 8,
                     "Frame \(index) component \(component): \(pixel[component]) expected \(colors[index][component])")
      }
      let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as! [String: Any]
      let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as! [String: Any]
      precondition(abs((gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as! Double) - 0.23) < 0.001)
    }
    do { _ = try grid.assemble(Data()); preconditionFailure("Reject invalid sheet") } catch APIError.decoding { }
    let still = ImageOutput.stillReference(gif)
    precondition(!ImageOutput.isGIF(still) && NSImage(data: still) != nil)
    precondition(ImageOutput.supportsGIF(modelID: "openai/gpt-image-2.6-flare"))
    precondition(!ImageOutput.supportsGIF(modelID: "gpt-image-2.5-flare"))

    URLProtocol.registerClass(ImageProtocol.self)
    defer { URLProtocol.unregisterClass(ImageProtocol.self) }
    ImageProtocol.response = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": sheet.base64EncodedString()]]])
    let client = try OpenAIClient(baseURL: "https://gif.test/v1", apiKey: "")
    ImageProtocol.check = { request, body in
      precondition(request.url!.path == "/v1/images/generations")
      let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
      precondition(json["output_format"] == nil && json["frame_count"] == nil && json["frame_duration_ms"] == nil)
      precondition(json["size"] as? String == "1920x1920")
      precondition((json["prompt"] as? String)?.contains("3 columns by 3 rows") == true)
      precondition((json["prompt"] as? String)?.contains("progressive motion") == true)
    }
    let generated = try await client.generateImage(model: "gpt-image-2.6-sunburst", prompt: "Loop", size: "512x512", animatedGIF: true, frameCount: 7, frameDurationMS: 237)
    precondition(CGImageSourceGetCount(CGImageSourceCreateWithData(generated as CFData, nil)!) == 7)
    ImageProtocol.check = { request, body in
      precondition(request.url!.path == "/v1/images/edits")
      let text = String(decoding: body, as: UTF8.self)
      precondition(!text.contains("name=\"output_format\"") && !text.contains("name=\"frame_count\""))
      precondition(text.contains("3 columns by 3 rows"))
      precondition(body.range(of: still) != nil && body.range(of: gif) == nil)
    }
    let edited = try await client.editImage(model: "gpt-image-2.6-flare", image: gif, prompt: "Blink", size: "512x512", animatedGIF: true, frameCount: 7)
    precondition(CGImageSourceGetCount(CGImageSourceCreateWithData(edited as CFData, nil)!) == 7)

    for count in 2...64 {
      let plan = GIFAnimationPlan(frameCount: count, durationMS: 200, size: "512x512")
      precondition(plan.grids.reduce(0) { $0 + $1.frameCount } == count)
      precondition(plan.grids.allSatisfy { (2...16).contains($0.frameCount) })
      precondition(plan.grids.count == (count + 15) / 16)
    }
    var requests = 0
    ImageProtocol.check = { request, body in
      requests += 1
      if requests == 1 {
        precondition(request.url!.path == "/v1/images/generations")
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        precondition((json["prompt"] as? String)?.contains("global frames 1 through 9") == true)
      } else {
        precondition(requests == 2 && request.url!.path == "/v1/images/edits")
        let text = String(decoding: body, as: UTF8.self)
        precondition(text.contains("global frames 10 through 18"))
        precondition(text.contains("NEXT moment"))
        precondition(text.contains("final global frame loops back"))
        precondition(!text.contains("name=\"output_format\""))
      }
    }
    let multiple = try await client.generateImage(model: "gpt-image-2.6-flare", prompt: "Blink", size: "512x512", animatedGIF: true, frameCount: 18, frameDurationMS: 240)
    precondition(requests == 2)
    let multipleSource = CGImageSourceCreateWithData(multiple as CFData, nil)!
    precondition(CGImageSourceGetCount(multipleSource) == 18)
    for index in 0..<18 {
      let frame = CGImageSourceCreateImageAtIndex(multipleSource, index, nil)!
      precondition(frame.width == 16 && frame.height == 16)
      let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
      context.draw(frame, in: CGRect(x: 0, y: 0, width: 16, height: 16))
      let pixel = context.data!.assumingMemoryBound(to: UInt8.self).advanced(by: (8 * 16 + 8) * 4)
      for component in 0..<3 { precondition(abs(Int(pixel[component]) - Int(colors[index % 9][component])) < 8) }
      let properties = CGImageSourceCopyPropertiesAtIndex(multipleSource, index, nil) as! [String: Any]
      let gifProperties = properties[kCGImagePropertyGIFDictionary as String] as! [String: Any]
      precondition(abs((gifProperties[kCGImagePropertyGIFUnclampedDelayTime as String] as! Double) - 0.24) < 0.001)
    }
    requests = 0
    ImageProtocol.check = { _, _ in
      requests += 1
      if requests == 2 {
        ImageProtocol.statusCode = 404
        ImageProtocol.response = Data("{\"error\":{\"message\":\"Image editing unsupported\"}}".utf8)
      }
    }
    do {
      _ = try await client.generateImage(model: "gpt-image-2.6-flare", prompt: "Blink", size: "512x512", animatedGIF: true, frameCount: 18)
      preconditionFailure("Continuation failure must stop the animation")
    } catch APIError.decoding { precondition(requests == 2) }
    ImageProtocol.statusCode = 200
    ImageProtocol.response = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": sheet.base64EncodedString()]]])
    let cancelled = Task {
      try await GIFAnimationPlan(frameCount: 64, durationMS: 200, size: "512x512").render(direction: "Loop", reference: nil) { _, _, _, _, _ in
        preconditionFailure("Cancelled animation must not make image requests")
      }
    }
    cancelled.cancel()
    do { _ = try await cancelled.value; preconditionFailure("Expected cancellation") } catch is CancellationError { }

    let fixturePath = temporary.appendingPathComponent("sheet.png")
    try sheet.write(to: fixturePath)
    setenv("FINETEXT_TEST_SHEET", fixturePath.path, 1)
    defer { unsetenv("FINETEXT_TEST_SHEET") }
    let codex = try await CodexSession.generateImage(install: CodexInstall(executable: URL(fileURLWithPath: CommandLine.arguments[0]), version: "fixture"), prompt: "Blink", animatedGIF: true, frameCount: 18) { _ in }
    precondition(CGImageSourceGetCount(CGImageSourceCreateWithData(codex as CFData, nil)!) == 18)

    let schema = Schema([RefinementSession.self, RewriteItem.self, TranslationItem.self, ImageItem.self, GenerationCharge.self])
    let config = ModelConfiguration(schema: schema, url: temporary.appendingPathComponent("gif.store"))
    do {
      let container = try ModelContainer(for: schema, configurations: config)
      let item = ImageItem(model: ModelRef(providerID: UUID(), modelID: "gpt-image-2.6-flare"))
      precondition(!item.animatedGIF && item.gifFrameCount == 9 && item.gifFrameDurationMS == 200)
      item.animatedGIF = true; item.imageData = gif; item.gifFrameCount = 7
      container.mainContext.insert(item)
      try container.mainContext.save()
    }
    let reopened = try ModelContainer(for: schema, configurations: config)
    let item = try reopened.mainContext.fetch(FetchDescriptor<ImageItem>()).first!
    precondition(item.animatedGIF && item.gifFrameCount == 7 && item.imageData == gif)
    print("Single/multiple GIF grids, frame order, timing, cancellation, Codex and persistence passed")
  }
}
