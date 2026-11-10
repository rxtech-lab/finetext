import Foundation
import ImageIO

// MARK: - Presets & tones

// Built-in rewrite presets come from the cloud catalog (see Services/Presets.swift).

/// Reusable rewrite rules. IDs remain stable when the user renames a preset.
struct CustomPlatform: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var instruction: String
  /// Submenu path such as "Work/Clients"; nil keeps the preset at the top level.
  var folder: String? = nil

  /// Folder names from the outermost submenu inwards.
  var folderPath: [String] { Self.path(folder ?? "") }

  static func path(_ folder: String) -> [String] {
    folder.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
  }

  /// Canonical "A/B" form, or nil for the top level.
  static func normalizedFolder(_ folder: String?) -> String? {
    let path = path(folder ?? "")
    return path.isEmpty ? nil : path.joined(separator: "/")
  }

  /// Every folder path in use, including parents, e.g. ["Work", "Work/Clients"].
  static func folders(in platforms: [CustomPlatform]) -> [String] {
    Set(platforms.flatMap { platform in
      platform.folderPath.indices.map { platform.folderPath[...$0].joined(separator: "/") }
    }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }
}

/// Custom presets arranged as nested submenus: folders (sorted) first, then presets in saved order.
enum CustomPlatformNode: Identifiable, Hashable, Sendable {
  case folder(name: String, path: String, children: [CustomPlatformNode])
  case platform(CustomPlatform)

  var id: String {
    switch self {
    case .folder(_, let path, _): "folder:" + path
    case .platform(let platform): platform.id.uuidString
    }
  }

  func contains(_ id: UUID?) -> Bool {
    switch self {
    case .folder(_, _, let children): children.contains { $0.contains(id) }
    case .platform(let platform): platform.id == id
    }
  }

  static func tree(_ platforms: [CustomPlatform], depth: Int = 0, parent: [String] = []) -> [CustomPlatformNode] {
    var names: [String] = []
    var grouped: [String: [CustomPlatform]] = [:]
    var leaves: [CustomPlatformNode] = []
    for platform in platforms {
      let path = platform.folderPath
      guard path.count > depth else { leaves.append(.platform(platform)); continue }
      if grouped[path[depth]] == nil { names.append(path[depth]) }
      grouped[path[depth], default: []].append(platform)
    }
    let folders = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }.map { name in
      CustomPlatformNode.folder(name: name, path: (parent + [name]).joined(separator: "/"),
                                children: tree(grouped[name]!, depth: depth + 1, parent: parent + [name]))
    }
    return folders + leaves
  }
}

enum Tone: String, CaseIterable, Codable, Identifiable, Sendable {
  case natural, professional, casual, witty, friendly, enthusiastic, informative, storytelling, bold, concise, empathetic

  var id: String { rawValue }
  var title: String {
    switch self {
    case .natural: LocalizableKey.natural.string
    case .professional: LocalizableKey.professional.string
    case .casual: LocalizableKey.casual.string
    case .witty: LocalizableKey.witty.string
    case .friendly: LocalizableKey.friendly.string
    case .enthusiastic: LocalizableKey.enthusiastic.string
    case .informative: LocalizableKey.informative.string
    case .storytelling: LocalizableKey.storytelling.string
    case .bold: LocalizableKey.bold.string
    case .concise: LocalizableKey.concise.string
    case .empathetic: LocalizableKey.empathetic.string
    }
  }

  var guidance: String {
    switch self {
    case .natural: "how the author would actually say it in person: plain words, relaxed rhythm, nothing performative"
    case .professional: "polished, credible and confident without jargon"
    case .casual: "relaxed and conversational, like talking to a friend"
    case .witty: "clever and playful with light humor, never cringe"
    case .friendly: "warm, approachable and positive"
    case .enthusiastic: "energetic and excited, but still sincere"
    case .informative: "clear, factual and helpful, focused on the key information"
    case .storytelling: "narrative, with a personal arc that pulls the reader in"
    case .bold: "direct, opinionated and a little provocative"
    case .concise: "as short and crisp as possible, every word earns its place"
    case .empathetic: "understanding, human and supportive"
    }
  }
}

// MARK: - Languages

struct Language: Hashable, Codable, Identifiable, Sendable {
  let code: String
  let name: String
  var id: String { code }

  /// Localized display name; `name` stays stable for Codable and model prompts.
  var localizedName: String {
    Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
      .localizedString(forIdentifier: code) ?? name
  }

  static let english = Language(code: "en", name: "English")
  static let japanese = Language(code: "ja", name: "Japanese")

  static let all: [Language] = [
    .english, .japanese,
    Language(code: "zh-Hans", name: "Chinese (Simplified)"),
    Language(code: "zh-Hant", name: "Chinese (Traditional)"),
    Language(code: "ko", name: "Korean"),
    Language(code: "es", name: "Spanish"),
    Language(code: "fr", name: "French"),
    Language(code: "de", name: "German"),
    Language(code: "it", name: "Italian"),
    Language(code: "pt", name: "Portuguese"),
    Language(code: "nl", name: "Dutch"),
    Language(code: "ru", name: "Russian"),
    Language(code: "uk", name: "Ukrainian"),
    Language(code: "pl", name: "Polish"),
    Language(code: "sv", name: "Swedish"),
    Language(code: "tr", name: "Turkish"),
    Language(code: "ar", name: "Arabic"),
    Language(code: "hi", name: "Hindi"),
    Language(code: "id", name: "Indonesian"),
    Language(code: "vi", name: "Vietnamese"),
    Language(code: "th", name: "Thai"),
  ]

  static func named(code: String) -> Language {
    if let known = all.first(where: { $0.code == code }) { return known }
    let name = Locale(identifier: "en").localizedString(forIdentifier: code) ?? code
    return Language(code: code, name: name)
  }
}

// MARK: - Providers & models

struct Provider: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var baseURL: String

  /// Pseudo provider id for MLX models downloaded from Hugging Face and run on this Mac.
  static let localID = UUID(uuidString: "00000000-0000-0000-0000-00000000F17E")!
  static var localName: String { LocalizableKey.onThisMac.string }
}

struct ModelRef: Codable, Hashable, Sendable {
  let providerID: UUID
  let modelID: String

  var isLocal: Bool { providerID == Provider.localID }
}

enum ModelKind: String, Sendable {
  case text, image
}

struct RemoteModel: Codable, Identifiable, Hashable, Sendable {
  let id: String
  let generatesImages: Bool
  let generatesText: Bool
  var pricing: ModelPricing? = nil
}

// MARK: - Jobs

enum JobStatus: Equatable, Sendable {
  case idle
  case running(String)
  case done
  case failed(String)

  var isRunning: Bool { if case .running = self { true } else { false } }
}

enum ImageSize: String, CaseIterable, Identifiable, Sendable {
  case square, landscape, portrait
  var id: String { rawValue }
  var title: String {
    switch self {
    case .square: LocalizableKey.square.string
    case .landscape: LocalizableKey.landscape.string
    case .portrait: LocalizableKey.portrait.string
    }
  }

  func value(for modelID: String) -> String {
    let dalle3 = modelID.lowercased().contains("dall-e-3")
    switch self {
    case .square: return "1024x1024"
    case .landscape: return dalle3 ? "1792x1024" : "1536x1024"
    case .portrait: return dalle3 ? "1024x1792" : "1024x1536"
    }
  }
}

// MARK: - Defaults

enum DefaultsKey {
  static let humanizationMode = "humanizationMode"
  static let humanizationEngine = "humanizationEngine"
  static let detectorEngine = "aiDetectorEngine"
  static let targetAIScore = "targetAIScore"
  static let humanizeRounds = "humanizeRounds"
  static let pivotLanguage = "pivotLanguage"
  static let gemmaModel = "translateGemmaMLXModel"
  static let draft = "draftText"
  static let providers = "providers"
  static let modelCache = "modelCache"
  static let preferences = "preferences"
  static let localModels = "localModels"
  static let settingsTab = "settingsTab"
  static let analyticsEnabled = "analyticsEnabled"

  static func register() {
    UserDefaults.standard.register(defaults: [
      humanizeRounds: 3,
      pivotLanguage: Language.japanese.code,
      gemmaModel: TranslationModel.default.id,
      humanizationEngine: HumanizationEngine.translateGemma.rawValue,
      detectorEngine: AIDetectorEngine.disabled.rawValue,
      targetAIScore: 20.0,
    ])
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

struct CostSummary {
  let charges: [GenerationCharge]
  var total: Double { charges.compactMap(\.costUSD).reduce(0, +) }
  var unknownCount: Int { charges.filter { $0.costUSD == nil }.count }
  /// Sum of known costs, or nil when no charge has a known amount.
  var knownTotal: Double? { charges.contains { $0.costUSD != nil } ? total : nil }
  var hasEstimate: Bool { charges.contains { $0.estimated } }
  var totalLabel: String { charges.isEmpty ? Self.usd(0) : label }
  var label: String {
    guard !charges.isEmpty else { return LocalizableKey.costUnavailable.string }
    guard charges.contains(where: { $0.costUSD != nil }) else { return LocalizableKey.costUnavailable.string }
    return (hasEstimate ? "≈ " : "") + Self.usd(total) + (unknownCount > 0 ? " + ?" : "")
  }
  static func usd(_ amount: Double) -> String {
    if amount > 0, amount < 0.000001 {
      return "< " + 0.000001.formatted(.currency(code: "USD").precision(.fractionLength(6)))
    }
    return amount.formatted(.currency(code: "USD").precision(.fractionLength(2...6)))
  }
}

/// GIF bytes must survive persistence, copying and export without being flattened to PNG.
enum ImageOutput {
  static func supportsGIF(modelID: String) -> Bool {
    let id = modelID.lowercased().split(separator: "/").last.map(String.init) ?? ""
    return id == "gpt-image-2.6-flare" || id.hasPrefix("gpt-image-2.6-flare-")
      || id == "gpt-image-2.6-sunburst" || id.hasPrefix("gpt-image-2.6-sunburst-")
  }

  static func isGIF(_ data: Data) -> Bool {
    ["GIF87a", "GIF89a"].contains(String(decoding: data.prefix(6), as: UTF8.self))
  }

  static func isAnimatedGIF(_ data: Data) -> Bool {
    guard isGIF(data), let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
    return CGImageSourceGetCount(source) > 1
  }

  /// Image edits accept still references, so extract a PNG frame from an existing animation.
  static func stillReference(_ data: Data) -> Data {
    guard isGIF(data), let source = CGImageSourceCreateWithData(data as CFData, nil),
          let frame = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return data }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else { return data }
    CGImageDestinationAddImage(destination, frame, nil)
    return CGImageDestinationFinalize(destination) ? output as Data : data
  }
}

/// One image request produces a contact sheet; ImageIO turns its cells into timed frames.
struct GIFFrameGrid: Sendable {
  let frameCount: Int
  let durationMS: Int
  let columns: Int
  let rows: Int
  let frameWidth: Int
  let frameHeight: Int

  init(frameCount: Int, durationMS: Int, size: String) {
    self.frameCount = min(16, max(2, frameCount))
    self.durationMS = min(2000, max(20, durationMS / 10 * 10))
    columns = Int(ceil(sqrt(Double(self.frameCount))))
    rows = (self.frameCount + columns - 1) / columns
    let dimensions = size.split(separator: "x").compactMap { Int($0) }
    if dimensions.count == 2, dimensions[0] > dimensions[1] {
      frameWidth = 768; frameHeight = 512
    } else if dimensions.count == 2, dimensions[0] < dimensions[1] {
      frameWidth = 512; frameHeight = 768
    } else {
      frameWidth = 640; frameHeight = 640
    }
  }

  var size: String { "\(columns * frameWidth)x\(rows * frameHeight)" }

  func prompt(_ direction: String) -> String {
    """
    \(direction)

    Deliver ONE still PNG animation sprite sheet, exactly \(columns) columns by \(rows) rows,
    filling the entire \(size) canvas. Every cell is exactly \(frameWidth)x\(frameHeight) pixels.
    The first \(frameCount) cells are consecutive frames of ONE seamless looping animation,
    ordered left to right, then top to bottom. Each frame lasts \(durationMS) milliseconds.
    Show progressive motion across cells; keep the subject identity, scale, camera, lighting,
    background and position consistent. Make the last frame transition smoothly to the first.
    If no motion is specified, use a subtle natural motion suitable for the subject.
    No grid lines, borders, padding, gutters, labels, numbers, text or captions. All cells
    have equal dimensions and touch their neighbours edge to edge. Keep the subject fully
    inside each cell. Leave any unused trailing cells blank. Return a still sprite sheet,
    not a GIF and not a single enlarged scene. An attached image is a visual reference;
    redraw the complete animation grid to incorporate the requested changes.
    """
  }

  func assemble(_ data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
          sheet.width >= columns, sheet.height >= rows else {
      throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "com.compuserve.gif" as CFString, frameCount, nil) else {
      throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    let cellWidth = sheet.width / columns
    let cellHeight = sheet.height / rows
    for index in 0..<frameCount {
      try Task.checkCancellation()
      let rect = CGRect(x: (index % columns) * cellWidth, y: (index / columns) * cellHeight,
                        width: cellWidth, height: cellHeight)
      guard let frame = sheet.cropping(to: rect) else {
        throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
      }
      // Materialize each crop into its own bitmap. GIF encoding must not retain the
      // sprite sheet's shared backing buffer/row stride for a subimage.
      guard let context = CGContext(data: nil, width: cellWidth, height: cellHeight,
                                    bitsPerComponent: 8, bytesPerRow: cellWidth * 4,
                                    space: CGColorSpaceCreateDeviceRGB(),
                                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
        throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
      }
      context.setFillColor(CGColor(gray: 1, alpha: 1))
      context.fill(CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))
      context.draw(frame, in: CGRect(x: 0, y: 0, width: cellWidth, height: cellHeight))
      guard let bitmap = context.makeImage() else { throw APIError.decoding(LocalizableKey.gifGridInvalid.string) }
      let delay = Double(durationMS) / 1000
      CGImageDestinationAddImage(destination, bitmap, [kCGImagePropertyGIFDictionary:
        [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
    }
    guard CGImageDestinationFinalize(destination) else { throw APIError.decoding(LocalizableKey.gifGridInvalid.string) }
    return output as Data
  }
}

/// Bounded sequential grids keep individual image requests within their pixel budget.
struct GIFAnimationPlan: Sendable {
  static let maximumFrames = 64
  let grids: [GIFFrameGrid]
  let frameCount: Int

  init(frameCount: Int, durationMS: Int, size: String) {
    self.frameCount = min(Self.maximumFrames, max(2, frameCount))
    let count = (self.frameCount + 15) / 16
    // Balance grids so a remainder of one never creates a one-frame sheet.
    let total = self.frameCount
    grids = (0..<count).map { index in
      GIFFrameGrid(frameCount: total / count + (index < total % count ? 1 : 0),
                   durationMS: durationMS, size: size)
    }
  }

  func render(direction: String, reference: Data?,
              generate: @Sendable (String, String, Data?, Int, Int) async throws -> Data) async throws -> Data {
    var previous = reference.map(ImageOutput.stillReference)
    var animations: [Data] = []
    var offset = 0
    for (index, grid) in grids.enumerated() {
      try Task.checkCancellation()
      var prompt = grid.prompt(direction)
      if grids.count > 1 {
        prompt += """

        This is grid \(index + 1) of \(grids.count), containing global frames \(offset + 1) through \(offset + grid.frameCount)
        of a single \(frameCount)-frame animation. These timeline instructions override per-sheet looping:
        do NOT restart or loop the motion inside this grid. Continue the full motion over all \(frameCount) frames.
        \(index > 0 ? "The attached image is the final frame of the previous grid. Begin with the NEXT moment after that frame; do not duplicate it. Preserve its identity, scale, background and camera." : "Establish the opening pose and begin the motion gradually.")
        \(index == grids.count - 1 ? "Finish the overall motion so the final global frame loops back to the original opening pose." : "End with motion still in progress so the next grid can continue seamlessly.")
        """
      }
      let sheet = try await generate(prompt, grid.size, previous, index + 1, grids.count)
      try Task.checkCancellation()
      let animation = try await Task.detached { try grid.assemble(sheet) }.value
      animations.append(animation)
      previous = try Self.lastFrame(animation)
      offset += grid.frameCount
    }
    try Task.checkCancellation()
    if animations.count == 1 { return animations[0] }
    return try await Task.detached { try Self.join(animations, durationMS: grids[0].durationMS) }.value
  }

  private static func lastFrame(_ data: Data) throws -> Data {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let frame = CGImageSourceCreateImageAtIndex(source, CGImageSourceGetCount(source) - 1, nil) else {
      throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
    }
    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil) else {
      throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
    }
    CGImageDestinationAddImage(destination, frame, nil)
    guard CGImageDestinationFinalize(destination) else { throw APIError.decoding(LocalizableKey.gifGridInvalid.string) }
    return output as Data
  }

  private static func join(_ animations: [Data], durationMS: Int) throws -> Data {
    let sources = try animations.map { data -> CGImageSource in
      guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
        throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
      }
      return source
    }
    let total = sources.reduce(0) { $0 + CGImageSourceGetCount($1) }
    let output = NSMutableData()
    guard let first = sources.first, let opening = CGImageSourceCreateImageAtIndex(first, 0, nil),
          let destination = CGImageDestinationCreateWithData(output, "com.compuserve.gif" as CFString, total, nil) else {
      throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
    }
    CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
    for source in sources {
      for index in 0..<CGImageSourceGetCount(source) {
        try Task.checkCancellation()
        guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil),
              let context = CGContext(data: nil, width: opening.width, height: opening.height,
                                      bitsPerComponent: 8, bytesPerRow: opening.width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
          throw APIError.decoding(LocalizableKey.gifGridInvalid.string)
        }
        context.draw(frame, in: CGRect(x: 0, y: 0, width: opening.width, height: opening.height))
        guard let normalized = context.makeImage() else { throw APIError.decoding(LocalizableKey.gifGridInvalid.string) }
        let delay = Double(durationMS) / 1000
        CGImageDestinationAddImage(destination, normalized, [kCGImagePropertyGIFDictionary:
          [kCGImagePropertyGIFDelayTime: delay, kCGImagePropertyGIFUnclampedDelayTime: delay]] as CFDictionary)
      }
    }
    guard CGImageDestinationFinalize(destination) else { throw APIError.decoding(LocalizableKey.gifGridInvalid.string) }
    return output as Data
  }
}
