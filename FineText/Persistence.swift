import Foundation
import SwiftData

/// One refinement session: the original text and every rewrite, translation and image made from it.
/// The current session survives closing the menu and quitting the app until the user clears it.
@Model final class RefinementSession {
  var id = UUID()
  var createdAt = Date.now
  var updatedAt = Date.now
  var originalText = ""
  var summaryTitle = ""
  var summarySource: String?
  @Relationship(deleteRule: .cascade, inverse: \RewriteItem.session) var rewrites: [RewriteItem] = []
  @Relationship(deleteRule: .cascade, inverse: \TranslationItem.session) var translations: [TranslationItem] = []
  @Relationship(deleteRule: .cascade, inverse: \ImageItem.session) var images: [ImageItem] = []

  init() {}

  var sortedRewrites: [RewriteItem] { rewrites.sorted { $0.createdAt < $1.createdAt } }
  var sortedTranslations: [TranslationItem] { translations.sorted { $0.createdAt < $1.createdAt } }
  var sortedImages: [ImageItem] { images.sorted { $0.createdAt < $1.createdAt } }

  var isEmpty: Bool { originalText.trimmed.isEmpty && rewrites.isEmpty && translations.isEmpty && images.isEmpty }

  /// Bounded source keeps history title requests small, including image-only sessions.
  var titleSource: String {
    ([String(originalText.prefix(6000))]
      + sortedRewrites.map { String($0.output.prefix(1000)) }
      + sortedTranslations.map { String($0.output.prefix(500)) }
      + sortedImages.map { String($0.instruction.prefix(500)) })
      .joined(separator: "\n\n").prefix(12000).description
  }

  var title: String {
    if summarySource == titleSource, !summaryTitle.isEmpty { return summaryTitle }
    let line = originalText.trimmed.components(separatedBy: .newlines).first ?? ""
    return line.isEmpty ? LocalizableKey.untitledSession.string : String(line.prefix(80))
  }
}

@Model final class RewriteItem {
  var id = UUID()
  var createdAt = Date.now
  // Snapshots preserve history and regeneration after a preset is edited or deleted.
  var customPlatformID: UUID?
  var customPlatformName: String?
  var customPlatformInstruction: String?
  /// The cloud preset id (older builds stored the same ids as enum raw values).
  var platformRaw = "x"
  /// JSON `PresetSnapshot`, refreshed from the catalog when the rewrite is added or run.
  var presetSnapshotData: Data?
  var toneRaw = Tone.casual.rawValue
  var providerID = UUID()
  var modelID = ""
  var output = ""
  /// The actual input used for this rewrite, even if the session draft changes later.
  var refinementSource: String?
  var note: String?
  var initialAIScore: Double?
  var finalAIScore: Double?
  var targetAIScore: Double?
  var detectorEngineRaw: String?
  var aiScoredText: String?
  var humanizationRounds = 0
  var session: RefinementSession?

  init(presetID: String, tone: Tone, model: ModelRef) {
    platformRaw = presetID
    toneRaw = tone.rawValue
    providerID = model.providerID
    modelID = model.modelID
  }

  var preset: PresetSnapshot? {
    get { presetSnapshotData.flatMap { try? JSONDecoder().decode(PresetSnapshot.self, from: $0) } }
    set { presetSnapshotData = newValue.flatMap { try? JSONEncoder().encode($0) } }
  }

  var isCustomPlatform: Bool { customPlatformID != nil }
  var platformTitle: String { customPlatformName ?? preset?.title ?? platformRaw }
  var platformSymbol: String { isCustomPlatform ? "slider.horizontal.3" : preset?.symbol ?? "text.bubble" }
  var fields: [PresetField]? { isCustomPlatform ? nil : preset?.fields }
  /// Readable output: structured fields become labelled text.
  var plainOutput: String { StructuredOutput.plainText(output, fields: fields) }
  var characterLimit: Int? { isCustomPlatform ? nil : preset?.characterLimit }
  var defaultTone: Tone { isCustomPlatform ? .natural : preset?.defaultTone ?? .natural }

  var tone: Tone {
    get { Tone(rawValue: toneRaw) ?? defaultTone }
    set { toneRaw = newValue.rawValue }
  }
  var model: ModelRef {
    get { ModelRef(providerID: providerID, modelID: modelID) }
    set { providerID = newValue.providerID; modelID = newValue.modelID }
  }
}

@Model final class TranslationItem {
  var id = UUID()
  var createdAt = Date.now
  var languageCode = Language.japanese.code
  var providerID = UUID()
  var modelID = ""
  /// nil translates the original text; otherwise the id of a rewrite in the same session.
  var sourceRewriteID: UUID?
  var output = ""
  var session: RefinementSession?

  init(language: Language, model: ModelRef, sourceRewriteID: UUID?) {
    languageCode = language.code
    providerID = model.providerID
    modelID = model.modelID
    self.sourceRewriteID = sourceRewriteID
  }

  var language: Language {
    get { Language.named(code: languageCode) }
    set { languageCode = newValue.code }
  }
  var model: ModelRef {
    get { ModelRef(providerID: providerID, modelID: modelID) }
    set { providerID = newValue.providerID; modelID = newValue.modelID }
  }
}

@Model final class ImageItem {
  var id = UUID()
  var createdAt = Date.now
  var providerID = UUID()
  var modelID = ""
  var instruction = ""
  var sizeRaw = ImageSize.square.rawValue
  @Attribute(.externalStorage) var imageData: Data?
  /// Ask for a cut-out subject on a transparent background.
  var transparentBackground = false
  /// The unkeyed green-screen render behind `imageData`, kept so refinements edit the original pixels.
  @Attribute(.externalStorage) var rawImageData: Data?
  /// The image before the last refinement, for one-step undo.
  @Attribute(.externalStorage) var previousImageData: Data?
  @Attribute(.externalStorage) var previousRawImageData: Data?
  var session: RefinementSession?

  init(model: ModelRef) {
    providerID = model.providerID
    modelID = model.modelID
  }

  var size: ImageSize {
    get { ImageSize(rawValue: sizeRaw) ?? .square }
    set { sizeRaw = newValue.rawValue }
  }
  var model: ModelRef {
    get { ModelRef(providerID: providerID, modelID: modelID) }
    set { providerID = newValue.providerID; modelID = newValue.modelID }
  }
  var canUndoRefinement: Bool { previousImageData != nil }
}

/// Independent ledger: deleting an output or a session never erases recorded spend.
@Model final class GenerationCharge {
  var id = UUID()
  var createdAt = Date.now
  var sessionID: UUID
  var itemID: UUID
  var modelID: String
  var kind: String
  var costUSD: Double?
  var costSource: String?
  var inputTokens: Int?
  var outputTokens: Int?
  var cachedTokens: Int?
  var estimated = false

  init(sessionID: UUID, itemID: UUID, modelID: String, kind: String) {
    self.sessionID = sessionID
    self.itemID = itemID
    self.modelID = modelID
    self.kind = kind
  }
}

enum Persistence {
  static func makeContainer() -> ModelContainer {
    let schema = Schema([RefinementSession.self, RewriteItem.self, TranslationItem.self, ImageItem.self, GenerationCharge.self])
    do {
      return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
    } catch {
      // Never block the app on a broken store; fall back to memory for this launch.
      return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
  }
}
