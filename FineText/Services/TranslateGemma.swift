import Foundation
import NaturalLanguage

/// TranslateGemma runs as an external component through a local Ollama server.
/// FineText never bundles the weights; the user downloads them from Settings.
struct TranslateGemmaClient: Sendable {
  let baseURL: URL
  let model: String

  static let availableModels = ["translategemma:4b", "translategemma:12b", "translategemma:27b"]
  static let ollamaDownloadURL = URL(string: "https://ollama.com/download")!

  static func fromDefaults() throws -> TranslateGemmaClient {
    let defaults = UserDefaults.standard
    var string = (defaults.string(forKey: DefaultsKey.ollamaURL) ?? "http://localhost:11434").trimmed
    while string.hasSuffix("/") { string.removeLast() }
    guard let url = URL(string: string) else { throw APIError.invalidURL }
    return TranslateGemmaClient(baseURL: url, model: (defaults.string(forKey: DefaultsKey.gemmaModel) ?? availableModels[0]).trimmed)
  }

  private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 600) throws -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
    request.httpMethod = method
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    return request
  }

  private func matches(_ name: String) -> Bool {
    name == model || name == model + ":latest" || (model.hasSuffix(":latest") && name == String(model.dropLast(7)))
  }

  // MARK: Status

  func isInstalled() async throws -> Bool {
    let (data, response) = try await URLSession.shared.data(for: request("api/tags", timeout: 5))
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw APIError.http(http.statusCode, OpenAIClient.errorMessage(from: data))
    }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let names = ((json?["models"] as? [[String: Any]]) ?? []).compactMap { $0["name"] as? String }
    return names.contains(where: matches)
  }

  struct PullProgress: Sendable {
    let status: String
    let fraction: Double?
  }

  func pull(progress: @MainActor @Sendable (PullProgress) -> Void) async throws {
    let (bytes, response) = try await URLSession.shared.bytes(for: request("api/pull", method: "POST", body: ["model": model, "stream": true], timeout: 3600))
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw APIError.http(http.statusCode, "Ollama could not start the download")
    }
    for try await line in bytes.lines {
      try Task.checkCancellation()
      guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
      if let error = json["error"] as? String { throw APIError.http(500, error) }
      let status = (json["status"] as? String) ?? ""
      var fraction: Double?
      if let total = (json["total"] as? NSNumber)?.doubleValue, total > 0 {
        fraction = ((json["completed"] as? NSNumber)?.doubleValue ?? 0) / total
      }
      await progress(PullProgress(status: status, fraction: fraction))
    }
  }

  func remove() async throws {
    let (data, response) = try await URLSession.shared.data(for: request("api/delete", method: "DELETE", body: ["model": model], timeout: 30))
    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
      throw APIError.http(http.statusCode, OpenAIClient.errorMessage(from: data))
    }
  }

  // MARK: Translation

  /// TranslateGemma's recommended prompt format.
  static func prompt(_ text: String, from source: Language, to target: Language) -> String {
    """
    You are a professional \(source.name) (\(source.code)) to \(target.name) (\(target.code)) translator. \
    Your goal is to accurately convey the meaning and nuances of the original \(source.name) text while adhering to \
    \(target.name) grammar, vocabulary, and cultural sensitivities.
    Produce only the \(target.name) translation, without any additional explanations or commentary. \
    Please translate the following \(source.name) text into \(target.name):


    \(text)
    """
  }

  func translate(_ text: String, from source: Language, to target: Language) async throws -> String {
    var output: [String] = []
    for chunk in Self.chunks(of: text) {
      try Task.checkCancellation()
      if chunk.trimmed.isEmpty { output.append(chunk); continue }
      let body: [String: Any] = [
        "model": model,
        "stream": false,
        "messages": [["role": "user", "content": Self.prompt(chunk, from: source, to: target)]],
      ]
      let (data, response) = try await URLSession.shared.data(for: request("api/chat", method: "POST", body: body))
      if let http = response as? HTTPURLResponse, http.statusCode != 200 {
        throw APIError.http(http.statusCode, OpenAIClient.errorMessage(from: data))
      }
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      guard let content = (json?["message"] as? [String: Any])?["content"] as? String, !content.trimmed.isEmpty else {
        throw APIError.empty
      }
      output.append(content.trimmed)
    }
    return output.joined(separator: "\n\n")
  }

  /// Round-trips text through a pivot language to break up LLM phrasing patterns.
  func humanize(_ text: String, rounds: Int, pivot preferred: Language, progress: @MainActor @Sendable (Int) -> Void) async throws -> String {
    let source = Self.detectLanguage(text)
    let pivot = source.code == preferred.code ? (source.code == "en" ? Language.japanese : .english) : preferred
    var current = text
    for round in 1...max(rounds, 1) {
      await progress(round)
      let intermediate = try await translate(current, from: source, to: pivot)
      current = try await translate(intermediate, from: pivot, to: source)
    }
    return current
  }

  static func detectLanguage(_ text: String) -> Language {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    guard let language = recognizer.dominantLanguage else { return .english }
    return Language.named(code: language.rawValue)
  }

  /// TranslateGemma has a small context window; translate long posts paragraph group by group.
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

/// Settings-side state for the external TranslateGemma component.
@MainActor @Observable final class TranslateGemmaManager {
  enum State: Equatable {
    case unknown, checking, serverUnavailable(String), notInstalled, installed
    case downloading(String, Double?)
    case failed(String)
  }

  var state: State = .unknown
  private var task: Task<Void, Never>?

  var isDownloading: Bool { if case .downloading = state { true } else { false } }

  func refresh() {
    guard !isDownloading else { return }
    state = .checking
    Task {
      do {
        let installed = try await TranslateGemmaClient.fromDefaults().isInstalled()
        state = installed ? .installed : .notInstalled
      } catch {
        state = .serverUnavailable(error.localizedDescription)
      }
    }
  }

  func download() {
    task?.cancel()
    state = .downloading("Starting…", nil)
    task = Task {
      do {
        try await TranslateGemmaClient.fromDefaults().pull { [weak self] progress in
          self?.state = .downloading(progress.status.isEmpty ? "Downloading…" : progress.status.capitalized, progress.fraction)
        }
        state = .installed
        refresh()
      } catch is CancellationError {
        state = .notInstalled
      } catch let error as URLError where error.code == .cancelled {
        state = .notInstalled
      } catch {
        state = .failed(error.localizedDescription)
      }
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
    state = .notInstalled
  }

  func remove() {
    state = .checking
    Task {
      do {
        try await TranslateGemmaClient.fromDefaults().remove()
      } catch {
        state = .failed(error.localizedDescription)
        return
      }
      refresh()
    }
  }
}
