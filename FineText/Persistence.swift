import Foundation
import SwiftData

/// One refinement session: the original text and every rewrite, translation and image made from it.
/// The current session survives closing the menu and quitting the app until the user clears it.
@Model final class RefinementSession {
  var id = UUID()
  var createdAt = Date.now
  var updatedAt = Date.now
  var originalText = ""
  @Relationship(deleteRule: .cascade, inverse: \RewriteItem.session) var rewrites: [RewriteItem] = []
  @Relationship(deleteRule: .cascade, inverse: \TranslationItem.session) var translations: [TranslationItem] = []
  @Relationship(deleteRule: .cascade, inverse: \ImageItem.session) var images: [ImageItem] = []

  init() {}

  var sortedRewrites: [RewriteItem] { rewrites.sorted { $0.createdAt < $1.createdAt } }
  var sortedTranslations: [TranslationItem] { translations.sorted { $0.createdAt < $1.createdAt } }
  var sortedImages: [ImageItem] { images.sorted { $0.createdAt < $1.createdAt } }

  var isEmpty: Bool { originalText.trimmed.isEmpty && rewrites.isEmpty && translations.isEmpty && images.isEmpty }

  var title: String {
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
  var platformRaw = Platform.x.rawValue
  var toneRaw = Tone.casual.rawValue
  var providerID = UUID()
  var modelID = ""
  var output = ""
  var note: String?
  var session: RefinementSession?

  init(platform: Platform, tone: Tone, model: ModelRef) {
    platformRaw = platform.rawValue
    toneRaw = tone.rawValue
    providerID = model.providerID
    modelID = model.modelID
  }

  var isCustomPlatform: Bool { customPlatformID != nil }
  var platformTitle: String { customPlatformName ?? platform.title }
  var platformSymbol: String { isCustomPlatform ? "slider.horizontal.3" : platform.symbol }
  var characterLimit: Int? { isCustomPlatform ? nil : platform.characterLimit }

  var platform: Platform { Platform(rawValue: platformRaw) ?? .x }
  var tone: Tone {
    get { Tone(rawValue: toneRaw) ?? platform.defaultTone }
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

enum Persistence {
  static func makeContainer() -> ModelContainer {
    let schema = Schema([RefinementSession.self, RewriteItem.self, TranslationItem.self, ImageItem.self])
    do {
      return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema))
    } catch {
      // Never block the app on a broken store; fall back to memory for this launch.
      return try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }
  }
}
