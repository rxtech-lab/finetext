import AppKit
import Foundation
import SwiftData

enum Route: Hashable {
  case rewrite(UUID), translation(UUID), image(UUID), history
}

enum WorkTab: String, CaseIterable, Identifiable {
  case rewrite = "Rewrite", translate = "Translate", image = "Image"
  var id: String { rawValue }
}

/// Owns the current session and runs the AI jobs. Runtime status lives here; results live in SwiftData.
@MainActor @Observable final class Workspace {
  let context: ModelContext
  let providers: ProviderStore
  let preferences: Preferences

  private(set) var session: RefinementSession
  var tab: WorkTab = .rewrite
  var route: Route?
  var toast: Toast?
  private(set) var statuses: [UUID: JobStatus] = [:]
  private var tasks: [UUID: Task<Void, Never>] = [:]
  private var toastTask: Task<Void, Never>?

  init(container: ModelContainer, providers: ProviderStore, preferences: Preferences) {
    context = container.mainContext
    self.providers = providers
    self.preferences = preferences
    var descriptor = FetchDescriptor<RefinementSession>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
    descriptor.fetchLimit = 1
    if let latest = try? context.fetch(descriptor).first {
      session = latest
    } else {
      let fresh = RefinementSession()
      context.insert(fresh)
      session = fresh
    }
  }

  // MARK: Session

  var originalText: String {
    get { session.originalText }
    set {
      session.originalText = newValue
      touch()
    }
  }

  private func touch() {
    session.updatedAt = .now
  }

  func save() {
    try? context.save()
  }

  /// Starts a new empty session. The previous one stays in History unless it was empty.
  func clear() {
    cancelAll()
    if session.isEmpty { context.delete(session) }
    let fresh = RefinementSession()
    context.insert(fresh)
    session = fresh
    route = nil
    save()
    flash("Cleared", symbol: "sparkles")
  }

  func open(_ other: RefinementSession) {
    guard other.id != session.id else { route = nil; return }
    cancelAll()
    if session.isEmpty { context.delete(session) }
    session = other
    touch()
    route = nil
    save()
  }

  func deleteSession(_ other: RefinementSession) {
    if other.id == session.id {
      cancelAll()
      let fresh = RefinementSession()
      context.insert(fresh)
      session = fresh
    }
    context.delete(other)
    save()
    flash("Session deleted", symbol: "trash")
  }

  private func cancelAll() {
    tasks.values.forEach { $0.cancel() }
    tasks.removeAll()
    statuses.removeAll()
  }

  func status(_ id: UUID) -> JobStatus { statuses[id] ?? .idle }

  // MARK: Toast

  func flash(_ message: String, symbol: String, isError: Bool = false) {
    isError ? Haptics.failure() : Haptics.success()
    toast = Toast(message: message, symbol: symbol, isError: isError)
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(for: .seconds(1.6))
      if !Task.isCancelled { toast = nil }
    }
  }

  func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    flash("Copied to clipboard", symbol: "doc.on.doc")
  }

  // MARK: Add

  @discardableResult
  func addRewrite(platform: Platform, model: ModelRef) -> RewriteItem {
    preferences.remember(platform: platform)
    preferences.remember(model, for: .rewrite)
    let item = RewriteItem(platform: platform, tone: preferences.tone(for: platform), model: model)
    session.rewrites.append(item)
    touch()
    Haptics.tap()
    return item
  }

  @discardableResult
  func addTranslation(language: Language, model: ModelRef, source: UUID?) -> TranslationItem {
    preferences.remember(language: language)
    preferences.remember(model, for: .translate)
    let item = TranslationItem(language: language, model: model, sourceRewriteID: source)
    session.translations.append(item)
    touch()
    Haptics.tap()
    return item
  }

  @discardableResult
  func addImage(model: ModelRef) -> ImageItem {
    preferences.remember(model, for: .image)
    let item = ImageItem(model: model)
    session.images.append(item)
    touch()
    Haptics.tap()
    return item
  }

  func remove(_ item: any PersistentModel, id: UUID) {
    tasks[id]?.cancel()
    tasks[id] = nil
    statuses[id] = nil
    if route != nil { route = nil }
    context.delete(item)
    touch()
    save()
    flash("Removed", symbol: "trash")
  }

  func stop(_ id: UUID) {
    tasks[id]?.cancel()
    tasks[id] = nil
    statuses[id] = .idle
  }

  // MARK: Run

  func runAll() {
    switch tab {
    case .rewrite: session.sortedRewrites.forEach(run)
    case .translate: session.sortedTranslations.forEach(run)
    case .image: session.sortedImages.forEach(run)
    }
  }

  var canRunAll: Bool {
    guard !originalText.trimmed.isEmpty else { return false }
    switch tab {
    case .rewrite: return !session.rewrites.isEmpty
    case .translate: return !session.translations.isEmpty
    case .image: return !session.images.isEmpty
    }
  }

  var isRunningAny: Bool { statuses.values.contains { $0.isRunning } }

  private func start(_ id: UUID, _ work: @escaping @MainActor () async throws -> Void) {
    tasks[id]?.cancel()
    statuses[id] = .running("Starting…")
    tasks[id] = Task {
      do {
        try await work()
        statuses[id] = .done
        save()
      } catch is CancellationError {
        statuses[id] = .idle
      } catch let error as URLError where error.code == .cancelled {
        statuses[id] = .idle
      } catch {
        statuses[id] = .failed(error.localizedDescription)
      }
      tasks[id] = nil
    }
  }

  func run(_ item: RewriteItem) {
    let text = originalText.trimmed
    guard !text.isEmpty else { return flash("Add your original post first", symbol: "exclamationmark.triangle", isError: true) }
    let id = item.id
    let messages = Prompts.rewrite(text, platform: item.platform, tone: item.tone)
    preferences.setTone(item.tone, for: item.platform)
    start(id) { [providers] in
      let client = try providers.client(for: item.model)
      item.output = ""
      item.note = nil
      self.statuses[id] = .running("Rewriting…")
      let raw = try await client.streamChat(model: item.modelID, messages: messages) { delta in item.output += delta }
      item.output = Prompts.clean(raw)
      try await self.humanize(item, id: id)
    }
  }

  private func humanize(_ item: RewriteItem, id: UUID) async throws {
    let defaults = UserDefaults.standard
    let rounds = defaults.integer(forKey: DefaultsKey.humanizeRounds)
    guard rounds > 0 else { return }
    let pivot = Language.named(code: defaults.string(forKey: DefaultsKey.pivotLanguage) ?? Language.japanese.code)
    do {
      let gemma = try TranslateGemmaClient.fromDefaults()
      guard try await gemma.isInstalled() else {
        item.note = "Humanizer skipped: download TranslateGemma in Settings."
        return
      }
      let result = try await gemma.humanize(item.output, rounds: rounds, pivot: pivot) { [weak self] round in
        self?.statuses[id] = .running("Humanizing \(round)/\(rounds) via \(pivot.name)…")
      }
      item.output = result
    } catch let error as CancellationError {
      throw error
    } catch {
      item.note = "Humanizer skipped: \(error.localizedDescription)"
    }
  }

  func sourceText(for item: TranslationItem) -> String {
    if let rewriteID = item.sourceRewriteID, let rewrite = session.rewrites.first(where: { $0.id == rewriteID }) {
      return rewrite.output
    }
    return originalText
  }

  func sourceTitle(for item: TranslationItem) -> String {
    if let rewriteID = item.sourceRewriteID, let rewrite = session.rewrites.first(where: { $0.id == rewriteID }) {
      return "\(rewrite.platform.title) rewrite"
    }
    return "Original"
  }

  func run(_ item: TranslationItem) {
    let text = sourceText(for: item).trimmed
    guard !text.isEmpty else { return flash("Nothing to translate yet", symbol: "exclamationmark.triangle", isError: true) }
    let id = item.id
    let messages = Prompts.translate(text, to: item.language)
    start(id) { [providers] in
      let client = try providers.client(for: item.model)
      item.output = ""
      self.statuses[id] = .running("Translating to \(item.language.name)…")
      let raw = try await client.streamChat(model: item.modelID, messages: messages) { delta in item.output += delta }
      item.output = Prompts.clean(raw)
    }
  }

  func run(_ item: ImageItem) {
    let text = originalText.trimmed
    guard !text.isEmpty || !item.instruction.trimmed.isEmpty else {
      return flash("Add a post or an instruction first", symbol: "exclamationmark.triangle", isError: true)
    }
    let id = item.id
    let prompt = Prompts.image(post: text, instruction: item.instruction)
    let size = item.size.value(for: item.modelID)
    start(id) { [providers] in
      let client = try providers.client(for: item.model)
      self.statuses[id] = .running("Generating image…")
      item.imageData = try await client.generateImage(model: item.modelID, prompt: prompt, size: size)
    }
  }

  // MARK: Images

  func copyImage(_ item: ImageItem) {
    guard let data = item.imageData, let image = NSImage(data: data) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
    flash("Image copied", symbol: "photo.on.rectangle")
  }

  static var picturesFolder: URL {
    // Real ~/Pictures (allowed by the pictures entitlement), not the sandbox container.
    let home = getpwuid(getuid()).map { URL(fileURLWithPath: String(cString: $0.pointee.pw_dir)) } ?? URL.homeDirectory
    return home.appending(path: "Pictures/FineText", directoryHint: .isDirectory)
  }

  func saveImageToPictures(_ item: ImageItem) {
    guard let data = item.imageData else { return }
    do {
      let folder = Self.picturesFolder
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let name = "FineText \(Date.now.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false).timeSeparator(.omitted))).png"
      let url = folder.appending(path: name)
      try Self.png(data).write(to: url)
      flash("Saved to Pictures/FineText", symbol: "square.and.arrow.down")
    } catch {
      flash("Save failed: \(error.localizedDescription)", symbol: "xmark.octagon", isError: true)
    }
  }

  func saveImageAs(_ item: ImageItem) {
    guard let data = item.imageData else { return }
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = "FineText Image.png"
    panel.canCreateDirectories = true
    NSApp.activate()
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try Self.png(data).write(to: url)
      flash("Image saved", symbol: "square.and.arrow.down")
    } catch {
      flash("Save failed: \(error.localizedDescription)", symbol: "xmark.octagon", isError: true)
    }
  }

  private static func png(_ data: Data) -> Data {
    guard let rep = NSBitmapImageRep(data: data), let png = rep.representation(using: .png, properties: [:]) else { return data }
    return png
  }
}

// MARK: - Prompts

enum Prompts {
  static let humanStyle = """
  Write like a real person, not an AI: vary sentence length, use plain words, keep the author's voice. \
  Avoid clichés such as "delve", "game-changer", "unlock", "elevate", "in today's fast-paced world", \
  "let's dive in", avoid overusing em dashes, and do not add emojis unless they suit the platform and tone.
  """

  static func rewrite(_ text: String, platform: Platform, tone: Tone) -> [ChatMessage] {
    [
      ChatMessage(role: "system", content: """
      You are an expert editor who adapts posts for \(platform.title).
      Tone: \(tone.title) — \(tone.guidance).
      Platform guidelines:
      \(platform.guidelines)
      Keep the original meaning and facts; never invent claims, numbers or links. \
      Write in the same language as the original post.
      \(humanStyle)
      Reply with the finished post only — no preamble, no explanations, no surrounding quotes.
      """),
      ChatMessage(role: "user", content: text),
    ]
  }

  static func translate(_ text: String, to language: Language) -> [ChatMessage] {
    [
      ChatMessage(role: "system", content: """
      Translate the user's text into \(language.name) (\(language.code)) as a native speaker would write it for social media. \
      Preserve meaning, tone, line breaks, Markdown, hashtags, @mentions and URLs. \
      Reply with the translation only.
      """),
      ChatMessage(role: "user", content: text),
    ]
  }

  static func image(post: String, instruction: String) -> String {
    var prompt = "Create an eye-catching illustration to accompany this social media post. Do not render any text in the image."
    if !post.isEmpty { prompt += "\n\nPost:\n\(post.prefix(2500))" }
    if !instruction.trimmed.isEmpty { prompt += "\n\nArt direction: \(instruction.trimmed)" }
    return prompt
  }

  /// Strips reasoning blocks and wrapping quotes some models add.
  static func clean(_ text: String) -> String {
    var result = text
    while let start = result.range(of: "<think>"), let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
      result.removeSubrange(start.lowerBound..<end.upperBound)
    }
    result = result.trimmed
    if result.count > 2, result.hasPrefix("\""), result.hasSuffix("\""), !result.dropFirst().dropLast().contains("\"") {
      result = String(result.dropFirst().dropLast())
    }
    return result
  }
}
