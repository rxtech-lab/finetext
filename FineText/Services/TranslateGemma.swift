import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon
import NaturalLanguage
import Tokenizers

/// Translation checkpoints supported by the humanizer.
struct TranslationModel: Hashable, Identifiable, Sendable {
  let id: String
  let name: String
  let size: String

  var isNLLB: Bool { id.hasPrefix("Xenova/nllb-") }

  static let all = [
    TranslationModel(id: "mlx-community/translategemma-4b-it-4bit", name: "TranslateGemma 4B", size: "≈ 3 GB"),
    TranslationModel(id: "mlx-community/translategemma-12b-it-4bit", name: "TranslateGemma 12B", size: "≈ 8 GB"),
    TranslationModel(id: "mlx-community/translategemma-27b-it-4bit", name: "TranslateGemma 27B", size: "≈ 16 GB"),
    TranslationModel(id: NLLB.repository, name: "Meta NLLB-200 600M", size: "≈ 1.34 GB"),
  ]
  static let `default` = all[0]

  static func named(_ id: String?) -> TranslationModel {
    all.first { $0.id == id } ?? .default
  }

  static func fromDefaults() -> TranslationModel {
    named(UserDefaults.standard.string(forKey: DefaultsKey.gemmaModel))
  }
}

enum TranslateGemmaError: LocalizedError {
  case empty

  var errorDescription: String? { LocalizableKey.translategemmaReturnedNoText.string }
}

/// Routes translation to MLX TranslateGemma or the local Meta NLLB runtime.
/// The weights are not bundled; they are downloaded from Hugging Face from Settings.
actor TranslationEngine {
  static let shared = TranslationEngine()

  /// Unload the weights after this long without a translation to give the memory back.
  private static let idleUnloadDelay: Duration = .seconds(300)

  private var loaded: (id: String, container: ModelContainer)?
  private var idleTask: Task<Void, Never>?

  // MARK: Download management

  /// The local snapshot folder when every file of the model is on disk, otherwise nil.
  func localSnapshot(_ model: TranslationModel) async -> URL? {
    if model.isNLLB { return await NLLB.shared.localSnapshot(model.id) }
    return await MLXHub.localSnapshot(model.id)
  }

  func isInstalled(_ model: TranslationModel) async -> Bool {
    await localSnapshot(model) != nil
  }

  func download(_ model: TranslationModel, progress: @MainActor @Sendable @escaping (Int64, Int64) -> Void) async throws {
    if model.isNLLB {
      try await NLLB.shared.download(model.id, progress: progress)
    } else {
      try await MLXHub.download(model.id, progress: progress)
    }
  }

  func remove(_ model: TranslationModel) async throws {
    if model.isNLLB { try await NLLB.shared.remove(model.id); return }
    if loaded?.id == model.id { unload() }
    try MLXHub.remove(model.id)
  }

  // MARK: Model lifetime

  private func container(for model: TranslationModel) async throws -> ModelContainer {
    if let loaded, loaded.id == model.id { return loaded.container }
    unload()
    guard let folder = await localSnapshot(model) else { throw MLXHubError.notDownloaded }
    let configuration = ModelConfiguration(directory: folder, extraEOSTokens: ["<end_of_turn>"])
    let container = try await MLXHub.load(configuration)
    loaded = (model.id, container)
    return container
  }

  private func unload() {
    idleTask?.cancel()
    idleTask = nil
    loaded = nil
    Memory.clearCache()
  }

  private func scheduleIdleUnload() {
    idleTask?.cancel()
    idleTask = Task { [weak self] in
      try? await Task.sleep(for: Self.idleUnloadDelay)
      guard !Task.isCancelled else { return }
      await self?.unload()
    }
  }

  // MARK: Translation

  /// TranslateGemma's prompt, identical to what its chat template renders for a text request.
  static func prompt(_ text: String, from source: Language, to target: Language) -> String {
    """
    You are a professional \(source.name) (\(source.code)) to \(target.name) (\(target.code)) translator. \
    Your goal is to accurately convey the meaning and nuances of the original \(source.name) text while adhering to \
    \(target.name) grammar, vocabulary, and cultural sensitivities.
    Produce only the \(target.name) translation, without any additional explanations or commentary. \
    Please translate the following \(source.name) text into \(target.name):


    \(text.trimmed)
    """
  }

  func translate(_ text: String, from source: Language, to target: Language, model: TranslationModel) async throws -> String {
    idleTask?.cancel()
    defer { scheduleIdleUnload() }
    let container = try await container(for: model)
    var output: [String] = []
    for chunk in Self.chunks(of: text) {
      try Task.checkCancellation()
      if chunk.trimmed.isEmpty { output.append(chunk); continue }
      let translated = try await generate(Self.prompt(chunk, from: source, to: target), with: container)
      guard !translated.isEmpty else { throw TranslateGemmaError.empty }
      output.append(translated)
    }
    return output.joined(separator: "\n\n")
  }

  private func generate(_ prompt: String, with container: ModelContainer) async throws -> String {
    // The chat template expects structured content; render its Gemma turn format directly.
    // The tokenizer adds <bos>.
    let rendered = "<start_of_turn>user\n\(prompt)<end_of_turn>\n<start_of_turn>model\n"
    let tokens = await container.encode(rendered)
    let parameters = GenerateParameters(maxTokens: 2048, temperature: 0.7, topP: 0.95, topK: 64)
    let stream = try await container.generate(input: LMInput(tokens: MLXArray(tokens)), parameters: parameters)
    var result = ""
    for await event in stream {
      try Task.checkCancellation()
      if case .chunk(let text) = event { result += text }
    }
    return result.replacingOccurrences(of: "<end_of_turn>", with: "").trimmed
  }

  /// Round-trips text through a pivot language to break up LLM phrasing patterns.
  func humanize(
    _ text: String, rounds: Int, pivot preferred: Language, model: TranslationModel,
    progress: @MainActor @Sendable @escaping (Int) -> Void
  ) async throws -> String {
    if model.isNLLB {
      return try await NLLB.shared.humanize(text, rounds: rounds, pivot: preferred, model: model, progress: progress)
    }
    let source = Self.detectLanguage(text)
    let pivot = source.code == preferred.code ? (source.code == "en" ? Language.japanese : .english) : preferred
    var current = text
    for round in 1...max(rounds, 1) {
      await progress(round)
      let intermediate = try await translate(current, from: source, to: pivot, model: model)
      current = try await translate(intermediate, from: pivot, to: source, model: model)
    }
    return current
  }

  static func detectLanguage(_ text: String) -> Language {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage else { return .english }
    return Language.named(code: language.rawValue)
  }

  /// TranslateGemma was trained on short inputs; translate long posts paragraph group by group.
  static func chunks(of text: String, limit: Int = 1500) -> [String] {
    let paragraphs = text.components(separatedBy: "\n\n")
    var result: [String] = []
    var current = ""
    for paragraph in paragraphs {
      if !current.isEmpty, current.count + paragraph.count + 2 > limit {
        result.append(current)
        current = paragraph
      } else {
        current = current.isEmpty ? paragraph : current + "\n\n" + paragraph
      }
    }
    if !current.isEmpty { result.append(current) }
    return result
  }
}

// MARK: - MLX bridges

/// Models are always loaded from a local snapshot folder; downloads go through `TranslateGemma.download`.
struct LocalOnlyDownloader: MLXLMCommon.Downloader {
  func download(
    id: String, revision: String?, matching patterns: [String], useLatest: Bool,
    progressHandler: @Sendable @escaping (Progress) -> Void
  ) async throws -> URL {
    throw MLXHubError.notDownloaded
  }
}

/// Loads the tokenizer with swift-transformers.
struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
  func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
    TokenizerBridge(try await AutoTokenizer.from(modelFolder: directory))
  }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
  let upstream: any Tokenizers.Tokenizer

  init(_ upstream: any Tokenizers.Tokenizer) { self.upstream = upstream }

  func encode(text: String, addSpecialTokens: Bool) -> [Int] {
    upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
  }

  func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
    upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
  }

  func convertTokenToId(_ token: String) -> Int? { upstream.convertTokenToId(token) }
  func convertIdToToken(_ id: Int) -> String? { upstream.convertIdToToken(id) }

  var bosToken: String? { upstream.bosToken }
  var eosToken: String? { upstream.eosToken }
  var unknownToken: String? { upstream.unknownToken }

  func applyChatTemplate(
    messages: [[String: any Sendable]], tools: [[String: any Sendable]]?, additionalContext: [String: any Sendable]?
  ) throws -> [Int] {
    do {
      return try upstream.applyChatTemplate(messages: messages, tools: tools, additionalContext: additionalContext)
    } catch Tokenizers.TokenizerError.missingChatTemplate {
      throw MLXLMCommon.TokenizerError.missingChatTemplate
    }
  }
}

// MARK: - Settings state

/// Settings-side state for the selected downloadable translation model.
@MainActor @Observable final class TranslationModelManager {
  enum State: Equatable {
    case unknown, checking, notInstalled, installed
    case downloading(DownloadProgress)
    case failed(String)
  }

  var state: State = .unknown
  private(set) var isRemoving = false
  private(set) var toast: Toast?
  private var task: Task<Void, Never>?
  private var downloadID: UUID?
  private(set) var downloadingModel: TranslationModel?

  var isDownloading: Bool { if case .downloading = state { true } else { false } }

  func refresh() {
    guard !isDownloading, !isRemoving else { return }
    state = .checking
    let model = TranslationModel.fromDefaults()
    Task {
      let installed = await TranslationEngine.shared.isInstalled(model)
      guard state == .checking, model == TranslationModel.fromDefaults() else { return }
      state = installed ? .installed : .notInstalled
    }
  }

  func download() {
    guard !isDownloading, !isRemoving else { return }
    let downloadID = UUID()
    self.downloadID = downloadID
    state = .downloading(DownloadProgress())
    let model = TranslationModel.fromDefaults()
    downloadingModel = model
    task = Task {
      defer {
        if self.downloadID == downloadID {
          self.downloadID = nil
          downloadingModel = nil
          task = nil
        }
      }
      do {
        try await TranslationEngine.shared.download(model) { completed, total in
          guard self.downloadID == downloadID else { return }
          self.update(completed: completed, total: total)
        }
        try Task.checkCancellation()
        guard self.downloadID == downloadID else { return }
        state = .installed
        AppAnalytics.log(.modelDownloaded, ["model_kind": "translation", "model": model.id])
        Haptics.success()
      } catch is CancellationError {
        if self.downloadID == downloadID { state = .notInstalled }
      } catch let error as URLError where error.code == .cancelled {
        if self.downloadID == downloadID { state = .notInstalled }
      } catch {
        if self.downloadID == downloadID {
          state = .failed(error.localizedDescription)
          Haptics.failure()
        }
      }
    }
  }

  private func update(completed: Int64, total: Int64) {
    guard case .downloading(var progress) = state else { return }
    progress.update(completed: completed, total: total)
    state = .downloading(progress)
  }

  func cancel() {
    task?.cancel()
    task = nil
    downloadID = nil
    downloadingModel = nil
    state = .notInstalled
  }

  func remove() {
    guard !isDownloading, !isRemoving else { return }
    isRemoving = true
    state = .checking
    let model = TranslationModel.fromDefaults()
    Task {
      do {
        try await TranslationEngine.shared.remove(model)
        isRemoving = false
        AppAnalytics.log(.modelRemoved, ["model_kind": "translation", "model": model.id])
        Haptics.success()
        show(Toast(message: LocalizableKey.removedModel.format(model.name), symbol: "trash"))
        refresh()
      } catch {
        isRemoving = false
        state = .failed(error.localizedDescription)
        Haptics.failure()
        show(Toast(message: error.localizedDescription, symbol: "exclamationmark.triangle", isError: true))
      }
    }
  }

  private func show(_ value: Toast) {
    toast = value
    Task {
      try? await Task.sleep(for: .seconds(4))
      if toast?.id == value.id { toast = nil }
    }
  }
}
