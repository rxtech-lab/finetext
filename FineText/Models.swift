import Foundation

// MARK: - Platforms & tones

enum Platform: String, CaseIterable, Codable, Identifiable, Sendable {
  case x, xReply, xThread, reddit, redditComment, linkedin, linkedinComment, linkedinChat, blog, message
  case youtubeComment, youtubeTitle, youtubeDescription
  case productHunt, productHuntComment, productHuntReply, productHuntTagline, productHuntDescription, productHuntMakerComment

  var id: String { rawValue }

  var title: String {
    switch self {
    case .x, .xReply, .xThread: "X · \(variantTitle)"
    case .reddit, .redditComment: "Reddit · \(variantTitle)"
    case .linkedin, .linkedinComment, .linkedinChat: "LinkedIn · \(variantTitle)"
    case .youtubeComment, .youtubeTitle, .youtubeDescription: "YouTube · \(variantTitle)"
    case .productHunt, .productHuntComment, .productHuntReply, .productHuntTagline, .productHuntDescription, .productHuntMakerComment:
      "Product Hunt · \(variantTitle)"
    case .blog: LocalizableKey.blogPost.string
    case .message: LocalizableKey.message.string
    }
  }

  /// Top-level entries; variants are selected in a submenu before the model.
  static let menuPlatforms: [Platform] = [.x, .reddit, .linkedin, .youtubeComment, .productHunt, .blog, .message]

  var variants: [Platform] {
    switch self {
    case .x, .xReply, .xThread: [.x, .xReply, .xThread]
    case .reddit, .redditComment: [.reddit, .redditComment]
    case .linkedin, .linkedinComment, .linkedinChat: [.linkedin, .linkedinComment, .linkedinChat]
    case .youtubeComment, .youtubeTitle, .youtubeDescription: [.youtubeComment, .youtubeTitle, .youtubeDescription]
    case .productHunt, .productHuntComment, .productHuntReply, .productHuntTagline, .productHuntDescription, .productHuntMakerComment:
      [.productHunt, .productHuntComment, .productHuntReply, .productHuntTagline, .productHuntDescription, .productHuntMakerComment]
    default: []
    }
  }

  var menuTitle: String {
    switch self {
    case .x, .xReply, .xThread: "X"
    case .reddit, .redditComment: "Reddit"
    case .linkedin, .linkedinComment, .linkedinChat: "LinkedIn"
    case .youtubeComment, .youtubeTitle, .youtubeDescription: "YouTube"
    case .productHunt, .productHuntComment, .productHuntReply, .productHuntTagline, .productHuntDescription, .productHuntMakerComment:
      "Product Hunt"
    default: title
    }
  }

  var variantTitle: String {
    switch self {
    case .x, .reddit, .linkedin, .productHunt: LocalizableKey.postVariant.string
    case .xReply, .productHuntReply: LocalizableKey.replyVariant.string
    case .xThread: LocalizableKey.threadVariant.string
    case .redditComment, .linkedinComment, .youtubeComment, .productHuntComment: LocalizableKey.commentVariant.string
    case .youtubeTitle: LocalizableKey.titleVariant.string
    case .youtubeDescription, .productHuntDescription: LocalizableKey.descriptionVariant.string
    case .productHuntTagline: LocalizableKey.taglineVariant.string
    case .productHuntMakerComment: LocalizableKey.makerCommentVariant.string
    case .linkedinChat: LocalizableKey.chatVariant.string
    default: title
    }
  }

  /// Stable English label used in model instructions.
  var promptTitle: String {
    switch self {
    case .x: "X Post"
    case .xReply: "X Reply"
    case .xThread: "X Thread"
    case .reddit: "Reddit Post"
    case .redditComment: "Reddit Comment"
    case .linkedin: "LinkedIn Post"
    case .linkedinComment: "LinkedIn Comment"
    case .linkedinChat: "LinkedIn Chat"
    case .youtubeComment: "YouTube Comment"
    case .youtubeTitle: "YouTube Title"
    case .youtubeDescription: "YouTube Description"
    case .productHunt: "Product Hunt Post"
    case .productHuntComment: "Product Hunt Comment"
    case .productHuntReply: "Product Hunt Reply"
    case .productHuntTagline: "Product Hunt Tagline"
    case .productHuntDescription: "Product Hunt Description"
    case .productHuntMakerComment: "Product Hunt Maker Comment"
    case .blog: "Blog Post"
    case .message: "Message"
    }
  }

  var symbol: String {
    switch self {
    case .x, .xReply, .xThread: "xmark"
    case .reddit, .redditComment: "bubble.left.and.bubble.right"
    case .linkedin: "briefcase"
    case .linkedinComment: "text.bubble"
    case .linkedinChat: "message"
    case .youtubeComment: "text.bubble"
    case .youtubeTitle, .youtubeDescription: "play.rectangle"
    case .productHunt, .productHuntTagline, .productHuntDescription: "sparkles"
    case .productHuntComment, .productHuntMakerComment: "text.bubble"
    case .productHuntReply: "arrowshape.turn.up.left"
    case .blog: "doc.richtext"
    case .message: "message"
    }
  }

  var defaultTone: Tone {
    switch self {
    case .x, .xReply, .xThread: .witty
    case .reddit, .redditComment: .casual
    case .linkedin: .professional
    case .linkedinComment, .linkedinChat: .natural
    case .youtubeComment: .casual
    case .youtubeTitle: .concise
    case .youtubeDescription: .informative
    case .productHunt: .enthusiastic
    case .productHuntComment, .productHuntReply: .natural
    case .productHuntTagline: .concise
    case .productHuntDescription: .informative
    case .productHuntMakerComment: .friendly
    case .blog: .storytelling
    case .message: .natural
    }
  }

  /// Soft character limit shown in the editor; nil means no limit.
  var characterLimit: Int? {
    switch self {
    case .x, .xReply: 280
    default: nil
    }
  }

  var guidelines: String {
    switch self {
    case .x:
      """
      - A single post of at most 280 characters (count carefully).
      - Lead with the most interesting idea. Punchy, scannable.
      - At most 1-2 relevant hashtags, only if they add value. No hashtag walls.
      """
    case .xReply:
      """
      - A single reply of at most 280 characters (count carefully).
      - Respond directly and naturally to the point in the source; keep the author's intended meaning.
      - No title, thread numbering, or hashtags. Do not invent context about the post being replied to.
      """
    case .xThread:
      """
      - A thread of connected X posts, each at most 280 characters including its numbering.
      - Separate posts with a blank line and number them 1/N, 2/N, and so on.
      - Open with a clear hook. Give each post a complete thought and keep a logical progression.
      - Use only as many posts as needed. Preserve the source facts; do not pad or invent details.
      """
    case .reddit:
      """
      - Start with a line "Title: <title>" followed by a blank line and the body.
      - Conversational and authentic, like a community member, not a marketer.
      - No hashtags. Markdown is allowed. Invite discussion naturally at the end.
      """
    case .redditComment:
      """
      - A Reddit comment, not a standalone post: no title or "Title:" line.
      - Conversational, authentic, and relevant to the point in the source, like a community member.
      - Preserve the author's intent. Do not invent context about the parent post or other commenters.
      - No hashtags or promotional language. Markdown is allowed; keep the response focused.
      """
    case .linkedin:
      """
      - Open with a strong one-line hook, then short paragraphs of 1-3 sentences.
      - Share a takeaway or lesson; keep it credible and specific.
      - End with a light question or call to action and 3-5 hashtags on the last line.
      """
    case .linkedinComment:
      """
      - A comment on a LinkedIn post, not a standalone post: no title, opening hook, or hashtags.
      - Keep it concise, thoughtful and conversational, with a professional but natural tone.
      - Preserve the author's point and contribute something specific rather than generic praise.
      - Do not invent facts, personal experiences, or context about the parent post.
      - No promotional pitch or forced question at the end.
      """
    case .linkedinChat:
      """
      - A private LinkedIn chat message, not a public post or email.
      - Use natural, concise language suitable for a professional conversation, with short paragraphs.
      - Preserve the author's intent, relationship and level of familiarity; do not invent prior contact.
      - No title, hashtags, public call to action, unsolicited sales pitch, or formal email sign-off.
      - Avoid canned greetings and networking clichés. Keep any request direct and low-pressure.
      """
    case .youtubeComment:
      """
      - A single YouTube comment: concise, conversational, and relevant to the source.
      - Preserve the author's point and tone. Do not invent video details, quotes, or context about other commenters.
      - No title, hashtags, promotional pitch, or generic praise. Output only the comment.
      """
    case .youtubeTitle:
      """
      - A single concise YouTube video title on one line. Output only the title, without quotes or a label.
      - Put the main topic first and make the value clear using natural, specific wording.
      - Preserve the source meaning. Avoid misleading clickbait, exaggerated promises, all caps, and hashtag walls.
      - Do not invent names, numbers, outcomes, or video content. Do not provide multiple alternatives.
      """
    case .youtubeDescription:
      """
      - A YouTube video description with a clear opening summary, followed by short, readable paragraphs as needed.
      - Explain the topic and value using only information in the source. Preserve any supplied links and credits.
      - Do not invent timestamps, chapters, URLs, sponsors, social handles, or claims about the video.
      - No title or description label, forced subscription pitch, or hashtag walls. Output only the description.
      """
    case .productHunt:
      """
      - A Product Hunt launch post: introduce the product, the problem it solves, and who it helps.
      - Lead with the concrete value, then use short paragraphs for the key features supported by the source.
      - Keep enthusiasm grounded and invite useful feedback naturally. No hashtag walls or requests for upvotes.
      - Preserve supplied product names and links. Do not invent features, pricing, metrics, testimonials, or launch status.
      - Output only the post, without a label or extra alternatives.
      """
    case .productHuntComment:
      """
      - A concise Product Hunt community comment, responding to the specific point in the source.
      - Keep it thoughtful and conversational; preserve any feedback or question rather than substituting generic praise.
      - Do not pretend to have tried the product or invent features, experiences, or a relationship with the maker.
      - No title, hashtags, promotional pitch, or requests for upvotes. Output only the comment.
      """
    case .productHuntReply:
      """
      - A direct, conversational reply to a Product Hunt comment or question.
      - Address the point in the source, preserving the author's role and intent without inventing the parent comment.
      - Do not invent product capabilities, commitments, roadmap dates, or personal experiences.
      - Keep it focused and helpful, without a title, hashtags, or requests for upvotes. Output only the reply.
      """
    case .productHuntTagline:
      """
      - A single short Product Hunt product tagline on one line, without quotes or a label.
      - State what the product does or its main benefit in plain, specific language; put the core idea first.
      - Preserve the source meaning. Avoid jargon, vague superlatives, unsupported comparisons, and invented claims.
      - No hashtags, calls to action, or multiple alternatives. Output only the tagline.
      """
    case .productHuntDescription:
      """
      - A compact Product Hunt product description explaining what it does, who it helps, and the main benefit.
      - Use a few clear sentences grounded in the source, prioritizing concrete capabilities over marketing adjectives.
      - Preserve supplied product names and links. Do not invent features, pricing, integrations, or results.
      - No title, hashtags, requests for upvotes, or extra alternatives. Output only the description.
      """
    case .productHuntMakerComment:
      """
      - An introductory Product Hunt maker comment, written in the maker's natural voice.
      - Use the source to explain why the product was built, the problem it addresses, and what makes it useful.
      - Use short paragraphs and close with an invitation for questions or specific feedback when appropriate.
      - Preserve the source's singular or team voice. Do not invent a founder story, users, traction, offers, or roadmap promises.
      - No title, hashtags, or requests for upvotes. Output only the maker comment.
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
