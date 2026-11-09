import Foundation
import HuggingFace
import NaturalLanguage

// Minimal host types let this exercise the production NLLB.swift without launching the menubar app.
struct TranslationModel: Sendable { let id: String }
struct Language: Sendable {
  let code: String
  static let english = Language(code: "en")
  static let japanese = Language(code: "ja")
}
enum TranslationEngine {
  static func detectLanguage(_ text: String) -> Language {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    return Language(code: recognizer.dominantLanguage?.rawValue ?? "en")
  }
}
enum MLXHubError: Error { case invalidRepository(String), notDownloaded, empty }
enum MLXHub {
  static let cache = HubCache(cacheDirectory: URL(fileURLWithPath: CommandLine.arguments[1]))
  static func remove(_ id: String) throws { throw MLXHubError.notDownloaded }
}
extension String { var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }
enum LocalizableKey {
  case nllbUnsupportedLanguage, nllbInvalidOutput, nllbOutputLimit
  var string: String { String(describing: self) }
}

@main struct NativeSmoke {
  static func main() async throws {
    let model = TranslationModel(id: NLLB.repository)
    var last = -1
    if await NLLB.shared.localSnapshot(model.id) == nil {
      try await NLLB.shared.download(model.id) { completed, total in
        let percent = total > 0 ? Int(Double(completed) / Double(total) * 100) : 0
        if percent / 10 != last / 10 { print("Download: \(percent)%"); last = percent }
      }
    }
    let snapshot = await NLLB.shared.localSnapshot(model.id)
    precondition(snapshot != nil)
    let tokenizer = try NLLB.tokenizer(at: snapshot!)
    let longSentence = Array(repeating: "translation", count: 950).joined(separator: " ")
    let chunks = NLLB.chunks(longSentence, tokenizer: tokenizer)
    precondition(chunks.count >= 3 && chunks.allSatisfy { $0.count <= 400 })
    precondition(chunks.flatMap { $0 } == tokenizer.encode(text: longSentence, addSpecialTokens: false))
    precondition(NLLB.chunks("First sentence. Second sentence.", tokenizer: tokenizer).count == 2)
    print("Sentence splitting and long-input preservation passed")
    let input = "The meeting starts at nine tomorrow morning. Please bring your notes."
    let output = try await NLLB.shared.humanize(input, rounds: 1, pivot: Language(code: "fr"), model: model) { round in
      print("Round \(round)")
    }
    print("Input: \(input)\nOutput: \(output)")
    precondition(!output.trimmed.isEmpty)
    precondition(output.lowercased().contains("meeting"))
    precondition(output.lowercased().contains("bring"))
    precondition(output.lowercased().contains("note"))
    precondition(TranslationEngine.detectLanguage(output).code == "en")
    let japanese = try await NLLB.shared.humanize(input, rounds: 1, pivot: .japanese, model: model) { _ in }
    print("Japanese round-trip: \(japanese)")
    precondition(!japanese.trimmed.isEmpty)
    let cancelled = Task {
      return try await NLLB.shared.humanize(input, rounds: 3, pivot: .japanese, model: model) { _ in }
    }
    try await Task.sleep(for: .milliseconds(50))
    cancelled.cancel()
    do { _ = try await cancelled.value; fatalError("Cancellation ignored") }
    catch is CancellationError { print("Cancellation passed") }
    print("Native NLLB smoke test passed.")
  }
}
