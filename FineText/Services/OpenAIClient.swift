import Foundation

struct ChatMessage: Codable, Sendable {
  let role: String
  let content: String
}

enum APIError: LocalizedError {
  case invalidURL
  case http(Int, String)
  case decoding(String)
  case empty

  var errorDescription: String? {
    switch self {
    case .invalidURL: "The endpoint URL is invalid."
    case .http(let code, let message): "HTTP \(code): \(message)"
    case .decoding(let message): "Unexpected response: \(message)"
    case .empty: "The model returned an empty response."
    }
  }
}

/// Minimal client for OpenAI-compatible endpoints (OpenAI, OpenRouter, Ollama, LM Studio, vLLM, …).
struct OpenAIClient: Sendable {
  let baseURL: URL
  let apiKey: String

  init(baseURL: String, apiKey: String) throws {
    var string = baseURL.trimmed
    while string.hasSuffix("/") { string.removeLast() }
    guard let url = URL(string: string), url.scheme?.hasPrefix("http") == true else { throw APIError.invalidURL }
    self.baseURL = url
    self.apiKey = apiKey.trimmed
  }

  private func request(_ path: String, method: String = "GET", body: [String: Any]? = nil, timeout: TimeInterval = 300) throws -> URLRequest {
    var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: timeout)
    request.httpMethod = method
    if !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
    request.setValue("https://finetext.rxlab.app", forHTTPHeaderField: "HTTP-Referer")
    request.setValue("FineText", forHTTPHeaderField: "X-Title")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    return request
  }

  private static func check(_ response: URLResponse, body: () async throws -> Data) async throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200..<300).contains(http.statusCode) else {
      let data = (try? await body()) ?? Data()
      throw APIError.http(http.statusCode, errorMessage(from: data))
    }
  }

  static func errorMessage(from data: Data) -> String {
    if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
      if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
      if let error = json["error"] as? String { return error }
      if let message = json["message"] as? String { return message }
    }
    let text = String(decoding: data.prefix(400), as: UTF8.self).trimmed
    return text.isEmpty ? "Request failed" : text
  }

  // MARK: Models

  func listModels() async throws -> [RemoteModel] {
    let (data, response) = try await URLSession.shared.data(for: request("models", timeout: 30))
    try await Self.check(response) { data }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw APIError.decoding("models list is not an object")
    }
    let items = (json["data"] as? [[String: Any]]) ?? (json["models"] as? [[String: Any]]) ?? []
    return items.compactMap(Self.classify).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
  }

  /// Uses whatever capability metadata the endpoint exposes (OpenRouter `architecture`,
  /// `capabilities`, `output_modalities`, Together `type`) and falls back to well-known model families.
  static func classify(_ object: [String: Any]) -> RemoteModel? {
    guard let id = (object["id"] as? String) ?? (object["name"] as? String) else { return nil }
    var outputs = Set<String>()
    if let architecture = object["architecture"] as? [String: Any] {
      outputs.formUnion((architecture["output_modalities"] as? [String]) ?? [])
      if outputs.isEmpty, let modality = architecture["modality"] as? String, let output = modality.components(separatedBy: "->").last {
        outputs.formUnion(output.components(separatedBy: "+"))
      }
    }
    outputs.formUnion((object["output_modalities"] as? [String]) ?? [])
    if let capabilities = object["capabilities"] as? [String] {
      if capabilities.contains(where: { $0.contains("image_generation") || $0 == "image" }) { outputs.insert("image") }
      if capabilities.contains(where: { $0.contains("completion") || $0.contains("chat") }) { outputs.insert("text") }
    } else if let capabilities = object["capabilities"] as? [String: Any] {
      if capabilities["image_generation"] as? Bool == true { outputs.insert("image") }
      if capabilities["chat"] as? Bool == true || capabilities["completion"] as? Bool == true { outputs.insert("text") }
    }
    if let type = object["type"] as? String {
      if type == "image" { outputs.insert("image") }
      if type == "chat" || type == "language" { outputs.insert("text") }
    }

    let lower = id.lowercased()
    if outputs.isEmpty {
      let imageFamilies = ["gpt-image", "dall-e", "dalle", "imagen", "flux", "stable-diffusion", "sdxl", "sd3", "midjourney",
                           "seedream", "recraft", "ideogram", "image-gen", "qwen-image", "hidream"]
      let nonText = ["embedding", "embed", "tts", "whisper", "transcribe", "moderation", "rerank", "realtime", "audio", "babbage", "davinci-002"]
      if imageFamilies.contains(where: lower.contains) {
        outputs.insert("image")
      } else if !nonText.contains(where: lower.contains) {
        outputs.insert("text")
      }
    }
    return RemoteModel(id: id, generatesImages: outputs.contains("image"), generatesText: outputs.contains("text"))
  }

  // MARK: Chat

  /// Streams a chat completion, reporting each delta. Falls back to a plain JSON body when the
  /// endpoint ignores `stream`.
  func streamChat(model: String, messages: [ChatMessage], onDelta: @MainActor @Sendable (String) -> Void) async throws -> String {
    let body: [String: Any] = [
      "model": model,
      "stream": true,
      "messages": messages.map { ["role": $0.role, "content": $0.content] },
    ]
    let (bytes, response) = try await URLSession.shared.bytes(for: request("chat/completions", method: "POST", body: body))
    try await Self.check(response) {
      var data = Data()
      for try await byte in bytes { data.append(byte) }
      return data
    }

    var full = ""
    if (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")?.contains("event-stream") == false {
      var data = Data()
      for try await byte in bytes { data.append(byte) }
      let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
      let choices = json?["choices"] as? [[String: Any]]
      full = ((choices?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
      await onDelta(full)
    } else {
      for try await line in bytes.lines {
        try Task.checkCancellation()
        guard line.hasPrefix("data:") else { continue }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { break }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        if let error = json["error"] as? [String: Any] {
          throw APIError.http(500, (error["message"] as? String) ?? "Stream error")
        }
        guard let choices = json["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any],
              let content = delta["content"] as? String, !content.isEmpty else { continue }
        full += content
        await onDelta(content)
      }
    }
    guard !full.trimmed.isEmpty else { throw APIError.empty }
    return full
  }

  // MARK: Images

  func generateImage(model: String, prompt: String, size: String) async throws -> Data {
    var body: [String: Any] = ["model": model, "prompt": prompt, "n": 1, "size": size]
    if model.lowercased().contains("dall-e") { body["response_format"] = "b64_json" }
    let (data, response) = try await URLSession.shared.data(for: request("images/generations", method: "POST", body: body, timeout: 600))
    try await Self.check(response) { data }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let first = (json["data"] as? [[String: Any]])?.first else {
      throw APIError.decoding("no image in response")
    }
    if let base64 = first["b64_json"] as? String, let image = Data(base64Encoded: base64) { return image }
    if let link = first["url"] as? String, let url = URL(string: link) {
      if link.hasPrefix("data:"), let comma = link.firstIndex(of: ","), let image = Data(base64Encoded: String(link[link.index(after: comma)...])) {
        return image
      }
      let (image, imageResponse) = try await URLSession.shared.data(from: url)
      try await Self.check(imageResponse) { image }
      return image
    }
    throw APIError.decoding("image payload missing")
  }
}
