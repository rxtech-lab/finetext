import AppKit
import CoreImage
import Vision

/// How a transparent image is produced for a given model.
enum BackgroundMode: Sendable {
  /// A normal, opaque image.
  case opaque
  /// The model can return a PNG with alpha itself (Codex, OpenAI `gpt-image-*`).
  case native
  /// The model draws on a chroma-key green screen and FineText keys it out locally.
  case greenScreen

  /// OpenAI's GPT Image family (also when routed through OpenRouter / AI Gateway as `openai/gpt-image-1`)
  /// accepts `background: "transparent"`. DALL·E and other families don't.
  static func supportsNativeTransparency(modelID: String) -> Bool {
    modelID.lowercased().contains("gpt-image")
  }
}

enum BackgroundRemovalError: LocalizedError {
  case unreadable
  case failed

  var errorDescription: String? {
    switch self {
    case .unreadable: LocalizableKey.unreadableImage.string
    case .failed: LocalizableKey.backgroundRemovalFailed.string
    }
  }
}

/// Local, on-device background removal: chroma keying for green-screen renders, with Vision's
/// foreground segmentation as a fallback when the model ignored the green screen or the transparency flag.
enum BackgroundRemover {
  /// Keys out the green screen. Falls back to Vision subject lifting when the border isn't green.
  static func removeGreenScreen(_ data: Data) throws -> Data {
    guard let bitmap = RGBABitmap(data: data) else { throw BackgroundRemovalError.unreadable }
    if let keyed = chromaKey(bitmap) { return keyed }
    if let lifted = try liftSubject(bitmap.cgImage) { return lifted }
    throw BackgroundRemovalError.failed
  }

  /// Ensures a natively transparent result really has alpha; some gateways drop the `background` option.
  static func ensureTransparent(_ data: Data) throws -> Data {
    guard let bitmap = RGBABitmap(data: data) else { throw BackgroundRemovalError.unreadable }
    if bitmap.transparentFraction > 0.01 { return data }
    if let keyed = chromaKey(bitmap) { return keyed }
    return try liftSubject(bitmap.cgImage) ?? data
  }

  /// Puts a transparent image back on a green screen so a green-screen model can edit it.
  static func compositeOnGreen(_ data: Data) -> Data {
    guard let bitmap = RGBABitmap(data: data), bitmap.transparentFraction > 0.001 else { return data }
    let width = bitmap.width, height = bitmap.height
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return data }
    context.setFillColor(CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(bitmap.cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    return context.makeImage().flatMap(png) ?? data
  }

  /// Cheap header check (no decode) used by views to decide whether to draw a checkerboard.
  static func hasAlphaChannel(_ data: Data) -> Bool {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return false }
    return properties[kCGImagePropertyHasAlpha] as? Bool ?? false
  }

  // MARK: Chroma key

  /// Samples the border to find the actual key colour (models rarely hit #00FF00 exactly), then builds a soft
  /// alpha matte from chroma distance and removes green spill from the edges. Returns nil when the border
  /// isn't a green screen.
  private static func chromaKey(_ bitmap: RGBABitmap) -> Data? {
    var pixels = bitmap.pixels
    let width = bitmap.width, height = bitmap.height

    // 1. Estimate the key colour from greenish border pixels.
    var samples: [(Double, Double, Double)] = []
    var borderCount = 0
    let inset = max(1, min(width, height) / 100)
    func sample(_ x: Int, _ y: Int) {
      borderCount += 1
      let i = (y * width + x) * 4
      let r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
      if g > r + 40, g > b + 40 { samples.append((r, g, b)) }
    }
    let step = max(1, max(width, height) / 400)
    for x in stride(from: 0, to: width, by: step) { sample(x, inset); sample(x, height - 1 - inset) }
    for y in stride(from: 0, to: height, by: step) { sample(inset, y); sample(width - 1 - inset, y) }
    guard borderCount > 0, Double(samples.count) / Double(borderCount) > 0.4 else { return nil }
    func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
    let key = (median(samples.map(\.0)), median(samples.map(\.1)), median(samples.map(\.2)))
    let (keyCb, keyCr) = chroma(key.0, key.1, key.2)

    // 2. Soft matte: fully transparent near the key chroma, fully opaque beyond `outer`.
    let inner = 0.10, outer = 0.22
    var cleared = 0
    for p in 0..<(width * height) {
      let i = p * 4
      var r = Double(pixels[i]), g = Double(pixels[i + 1]), b = Double(pixels[i + 2])
      let (cb, cr) = chroma(r, g, b)
      let distance = ((cb - keyCb) * (cb - keyCb) + (cr - keyCr) * (cr - keyCr)).squareRoot()
      let t = min(1, max(0, (distance - inner) / (outer - inner)))
      let alpha = t * t * (3 - 2 * t)

      // 3. Despill: pull green down to the other channels on pixels that are near the key.
      if distance < outer * 1.8 {
        let limit = max(r, b)
        if g > limit { g = limit }
      }
      if alpha < 0.02 { cleared += 1 }
      r *= alpha; g *= alpha; b *= alpha
      pixels[i] = UInt8(r.rounded())
      pixels[i + 1] = UInt8(g.rounded())
      pixels[i + 2] = UInt8(b.rounded())
      pixels[i + 3] = UInt8((alpha * 255).rounded())
    }
    // Nothing (or everything) removed means the key was wrong; let the caller fall back.
    let fraction = Double(cleared) / Double(width * height)
    guard fraction > 0.03, fraction < 0.98 else { return nil }
    return RGBABitmap.makeImage(pixels: pixels, width: width, height: height).flatMap(png)
  }

  /// Normalised YCbCr chroma for 0…255 RGB.
  private static func chroma(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double) {
    let r = r / 255, g = g / 255, b = b / 255
    return (-0.168736 * r - 0.331264 * g + 0.5 * b, 0.5 * r - 0.418688 * g - 0.081312 * b)
  }

  // MARK: Vision fallback

  private static func liftSubject(_ image: CGImage) throws -> Data? {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image)
    try handler.perform([request])
    guard let observation = request.results?.first, !observation.allInstances.isEmpty else { return nil }
    let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
    let ciImage = CIImage(cvPixelBuffer: buffer)
    return CIContext().createCGImage(ciImage, from: ciImage.extent).flatMap(png)
  }

  static func png(_ image: CGImage) -> Data? {
    NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
  }
}

/// An image redrawn as 8-bit premultiplied RGBA in sRGB.
private struct RGBABitmap {
  let cgImage: CGImage
  let width: Int
  let height: Int
  let pixels: [UInt8]

  init?(data: Data) {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    let width = image.width, height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
      guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
      context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
      return true
    }
    guard drawn else { return nil }
    self.width = width
    self.height = height
    self.pixels = pixels
    cgImage = image
  }

  var transparentFraction: Double {
    var count = 0
    for p in stride(from: 3, to: pixels.count, by: 4) where pixels[p] < 250 { count += 1 }
    return Double(count) / Double(max(1, width * height))
  }

  static func makeImage(pixels: [UInt8], width: Int, height: Int) -> CGImage? {
    var pixels = pixels
    return pixels.withUnsafeMutableBytes { buffer in
      CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
        .makeImage()
    }
  }
}
