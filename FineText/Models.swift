import Foundation

// MARK: - Platforms & tones

enum Platform: String, CaseIterable, Codable, Identifiable, Sendable {
  case x, reddit, linkedin, blog, message

  var id: String { rawValue }

  var title: String {
    switch self {
    case .x: "X"
    case .reddit: "Reddit"
    case .linkedin: "LinkedIn"
    case .blog: LocalizableKey.blogPost.string
    case .message: LocalizableKey.message.string
    }
  }

  /// Stable English label used in model instructions.
  var promptTitle: String {
    switch self {
    case .blog: "Blog Post"
    case .message: "Message"
    default: title
    }
  }

  var symbol: String {
    switch self {
    case .x: "xmark"
    case .reddit: "bubble.left.and.bubble.right"
    case .linkedin: "briefcase"
    case .blog: "doc.richtext"
    case .message: "message"
    }
  }

  var defaultTone: Tone {
    switch self {
    case .x: .witty
    case .reddit: .casual
    case .linkedin: .professional
    case .blog: .storytelling
    case .message: .natural
    }
  }

  /// Soft character limit shown in the editor; nil means no limit.
  var characterLimit: Int? { self == .x ? 280 : nil }

  var guidelines: String {
    switch self {
    case .x:
      """
      - A single post of at most 280 characters (count carefully).
      - Lead with the most interesting idea. Punchy, scannable.
      - At most 1-2 relevant hashtags, only if they add value. No hashtag walls.
      """
    case .reddit:
      """
      - Start with a line "Title: <title>" followed by a blank line and the body.
      - Conversational and authentic, like a community member, not a marketer.
      - No hashtags. Markdown is allowed. Invite discussion naturally at the end.
      """
    case .linkedin:
      """
      - Open with a strong one-line hook, then short paragraphs of 1-3 sentences.
      - Share a takeaway or lesson; keep it credible and specific.
      - End with a light question or call to action and 3-5 hashtags on the last line.
      """
    case .blog:
      """
      - Markdown blog post: a "# Title", a short intro, "##" section headings, and a conclusion.
      - Around 400-900 words, expanding on the original with useful detail but no invented facts.
      - Clear, readable paragraphs.
      """
    case .message:
      """
      - A chat message for a messaging app (iMessage, WhatsApp, Telegram, Slack DMs), written the way a real \
      person texts the people they know.
      - Natural and spoken: contractions, everyday words, short sentences. It should sound like the author \
      would say it out loud. Sentence fragments are fine.
      - No title, no hashtags, no Markdown, no bullet lists, no sign-off or formal greeting, no "I hope this \
      message finds you well".
      - Keep it short. Break longer content into a few short lines or paragraphs instead of one block.
      - Don't sound like an announcement, an email or marketing copy. Only use an emoji if it fits naturally.
      """
    }
  }
}

/// Reusable rewrite rules. IDs remain stable when the user renames a preset.
struct CustomPlatform: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var instruction: String
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
  static let humanizeRounds = "humanizeRounds"
  static let pivotLanguage = "pivotLanguage"
  static let gemmaModel = "translateGemmaMLXModel"
  static let draft = "draftText"
  static let providers = "providers"
  static let modelCache = "modelCache"
  static let preferences = "preferences"
  static let localModels = "localModels"
  static let settingsTab = "settingsTab"

  static func register() {
    UserDefaults.standard.register(defaults: [
      humanizeRounds: 3,
      pivotLanguage: Language.japanese.code,
      gemmaModel: TranslateGemmaModel.default.id,
    ])
  }
}

extension String {
  var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
