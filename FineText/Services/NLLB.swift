import Foundation
import HuggingFace
import Hub
import NaturalLanguage
import OnnxRuntimeBindings
import Tokenizers

/// Meta's encoder-decoder model runs in-process through ONNX Runtime's native Swift/ObjC binding.
/// The public ONNX conversion preserves NLLB weights; no Python or server is used.
actor NLLB {
  static let shared = NLLB()
  static let repository = "Xenova/nllb-200-distilled-600M"
  static let revision = "261c31d1a5732c67cdd16d80e8d6088507c7ccea"
  static let files = ["config.json", "tokenizer.json", "tokenizer_config.json", "special_tokens_map.json",
    "onnx/encoder_model_quantized.onnx", "onnx/decoder_model_quantized.onnx", "onnx/decoder_with_past_model_quantized.onnx"]
  private var loaded: Loaded?
  private var idleTask: Task<Void, Never>?

  private struct Loaded {
    let environment: ORTEnv
    let encoder: ORTSession
    let decoder: ORTSession
    let cachedDecoder: ORTSession
    let tokenizer: any Tokenizer
  }

  func localSnapshot(_ id: String) async -> URL? {
    guard id == Self.repository, let repo = Repo.ID(rawValue: id),
          let directory = try? await HubClient(cache: MLXHub.cache).downloadSnapshot(
            of: repo, revision: Self.revision, matching: Self.files, localFilesOnly: true),
          Self.files.allSatisfy({ FileManager.default.fileExists(atPath: directory.appending(path: $0).path) })
    else { return nil }
    return directory
  }

  func download(_ id: String, progress: @MainActor @Sendable @escaping (Int64, Int64) -> Void) async throws {
    guard id == Self.repository, let repo = Repo.ID(rawValue: id) else { throw MLXHubError.invalidRepository(id) }
    _ = try await HubClient(cache: MLXHub.cache).downloadSnapshot(of: repo, revision: Self.revision, matching: Self.files) { value in
      progress(Int64((value.fractionCompleted * Double(value.totalUnitCount)).rounded()), value.totalUnitCount)
    }
    try Task.checkCancellation()
    guard await localSnapshot(id) != nil else { throw MLXHubError.notDownloaded }
  }

  func remove(_ id: String) throws {
    unload()
    try MLXHub.remove(id)
  }

  private func unload() {
    idleTask?.cancel()
    idleTask = nil
    loaded = nil
  }

  private func load(_ id: String) async throws -> Loaded {
    if let loaded { return loaded }
    guard let directory = await localSnapshot(id) else { throw MLXHubError.notDownloaded }
    let environment = try ORTEnv(loggingLevel: .warning)
    let options = try ORTSessionOptions()
    try options.setIntraOpNumThreads(Int32(min(ProcessInfo.processInfo.activeProcessorCount, 8)))
    try options.setGraphOptimizationLevel(.all)
    func session(_ filename: String) throws -> ORTSession {
      try ORTSession(env: environment, modelPath: directory.appending(path: "onnx/\(filename)_quantized.onnx").path, sessionOptions: options)
    }
    let tokenizer = try Self.tokenizer(at: directory)
    let result = try Loaded(environment: environment, encoder: session("encoder_model"), decoder: session("decoder_model"),
                            cachedDecoder: session("decoder_with_past_model"), tokenizer: tokenizer)
    loaded = result
    return result
  }

  static func tokenizer(at directory: URL) throws -> any Tokenizer {
    // This export stores NLLB's SentencePiece vocabulary as BPE. Select the native BPE
    // implementation while retaining the export's normalizer, decoder and added token IDs.
    guard var config = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appending(path: "tokenizer_config.json"))) as? [NSString: Any] else {
      throw NLLBError.invalidOutput
    }
    config["tokenizer_class"] = "PreTrainedTokenizer"
    let data = try JSONDecoder().decode(Config.self, from: Data(contentsOf: directory.appending(path: "tokenizer.json")))
    return try AutoTokenizer.from(tokenizerConfig: Config(config), tokenizerData: data)
  }

  func humanize(
    _ text: String, rounds: Int, pivot preferred: Language, model: TranslationModel,
    progress: @MainActor @Sendable @escaping (Int) -> Void
  ) async throws -> String {
    idleTask?.cancel()
    defer {
      idleTask = Task { [weak self] in
        try? await Task.sleep(for: .seconds(300))
        guard !Task.isCancelled else { return }
        await self?.unload()
      }
    }
    let source = TranslationEngine.detectLanguage(text)
    let pivot = source.code == preferred.code ? (source.code == "en" ? Language.japanese : .english) : preferred
    guard let sourceCode = Self.languages[source.code], let pivotCode = Self.languages[pivot.code] else {
      throw NLLBError.unsupportedLanguage
    }
    let runtime = try await load(model.id)
    var current = text
    for round in 1...max(1, rounds) {
      try Task.checkCancellation()
      await progress(round)
      let intermediate = try translate(current, from: sourceCode, to: pivotCode, runtime: runtime)
      current = try translate(intermediate, from: pivotCode, to: sourceCode, runtime: runtime)
    }
    return current
  }

  private func translate(_ text: String, from source: String, to target: String, runtime: Loaded) throws -> String {
    let tokenizer = runtime.tokenizer
    guard let sourceID = tokenizer.convertTokenToId(source), let targetID = tokenizer.convertTokenToId(target) else {
      throw NLLBError.unsupportedLanguage
    }
    return try text.components(separatedBy: "\n\n").map { paragraph in
      guard !paragraph.trimmed.isEmpty else { return paragraph }
      var pieces: [String] = []
      // Translate sentence by sentence: NLLB can omit later sentences in a multi-sentence input.
      // Long sentences are split by tokens without truncating their content.
      for tokens in Self.chunks(paragraph, tokenizer: tokenizer) {
        try Task.checkCancellation()
        let input = [sourceID] + tokens + [2]
        let ids = try Self.tensor(input)
        let mask = try Self.tensor(Array(repeating: 1, count: input.count))
        guard let hidden = try runtime.encoder.run(withInputs: ["input_ids": ids, "attention_mask": mask],
                                                  outputNames: ["last_hidden_state"], runOptions: nil)["last_hidden_state"] else {
          throw NLLBError.invalidOutput
        }
        var generated = [2, targetID] // decoder_start_token_id (EOS), forced target language
        var cache: [String: ORTValue] = [:]
        var finished = false
        for step in 0..<512 {
          try Task.checkCancellation()
          let session = step == 0 ? runtime.decoder : runtime.cachedDecoder
          var inputs = cache
          inputs["input_ids"] = try Self.tensor(step == 0 ? generated : [generated.last!])
          inputs["encoder_hidden_states"] = hidden
          inputs["encoder_attention_mask"] = mask
          let inputNames = Set(try session.inputNames())
          inputs = inputs.filter { inputNames.contains($0.key) }
          let outputs = try session.run(withInputs: inputs, outputNames: Set(session.outputNames()), runOptions: nil)
          guard let logits = outputs["logits"] else { throw NLLBError.invalidOutput }
          for (key, value) in outputs where key.hasPrefix("present.") {
            cache[key.replacingOccurrences(of: "present.", with: "past_key_values.")] = value
          }
          let next = try Self.lastToken(logits)
          if next == 2 { finished = true; break }
          generated.append(next)
        }
        guard finished else { throw NLLBError.outputLimit }
        let translated = tokenizer.decode(tokens: Array(generated.dropFirst(2)), skipSpecialTokens: true).trimmed
        guard !translated.isEmpty else { throw MLXHubError.empty }
        pieces.append(translated)
      }
      return pieces.joined(separator: " ")
    }.joined(separator: "\n\n")
  }

  static func chunks(_ paragraph: String, tokenizer: any Tokenizer) -> [[Int]] {
    let splitter = NLTokenizer(unit: .sentence)
    splitter.string = paragraph
    var sentences: [String] = []
    splitter.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
      sentences.append(String(paragraph[range]))
      return true
    }
    if sentences.isEmpty { sentences = [paragraph] }
    return sentences.flatMap { sentence -> [[Int]] in
      let tokens = tokenizer.encode(text: sentence, addSpecialTokens: false)
      return stride(from: 0, to: tokens.count, by: 400).map {
        Array(tokens[$0..<min($0 + 400, tokens.count)])
      }
    }
  }

  private static func tensor(_ tokens: [Int]) throws -> ORTValue {
    let values = tokens.map(Int64.init)
    let data = values.withUnsafeBytes { NSMutableData(bytes: $0.baseAddress!, length: $0.count) }
    return try ORTValue(tensorData: data, elementType: .int64, shape: [1, NSNumber(value: tokens.count)])
  }

  private static func lastToken(_ logits: ORTValue) throws -> Int {
    let shape = try logits.tensorTypeAndShapeInfo()
    guard shape.elementType == .float, shape.shape.count == 3,
          let vocabulary = shape.shape.last?.intValue, vocabulary > 0 else { throw NLLBError.invalidOutput }
    let data = try logits.tensorData()
    let count = data.length / MemoryLayout<Float>.stride
    guard count >= vocabulary else { throw NLLBError.invalidOutput }
    let values = data.bytes.assumingMemoryBound(to: Float.self).advanced(by: count - vocabulary)
    var best = 0
    for index in 1..<vocabulary where values[index] > values[best] { best = index }
    return best
  }

  static let languages = [
    "en": "eng_Latn", "ja": "jpn_Jpan", "zh": "zho_Hans", "zh-Hans": "zho_Hans", "zh-Hant": "zho_Hant",
    "ko": "kor_Hang", "es": "spa_Latn", "fr": "fra_Latn", "de": "deu_Latn", "it": "ita_Latn", "pt": "por_Latn",
    "nl": "nld_Latn", "ru": "rus_Cyrl", "uk": "ukr_Cyrl", "pl": "pol_Latn", "sv": "swe_Latn", "tr": "tur_Latn",
    "ar": "arb_Arab", "hi": "hin_Deva", "id": "ind_Latn", "vi": "vie_Latn", "th": "tha_Thai",
  ]
}

enum NLLBError: LocalizedError {
  case unsupportedLanguage, invalidOutput, outputLimit
  var errorDescription: String? {
    switch self {
    case .unsupportedLanguage: LocalizableKey.nllbUnsupportedLanguage.string
    case .invalidOutput: LocalizableKey.nllbInvalidOutput.string
    case .outputLimit: LocalizableKey.nllbOutputLimit.string
    }
  }
}
