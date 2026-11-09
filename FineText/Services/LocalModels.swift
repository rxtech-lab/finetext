import Foundation
import HuggingFace
import MLX
import MLXLLM
import MLXLMCommon

// MARK: - Hub storage

enum MLXHubError: LocalizedError {
  case notDownloaded, invalidRepository(String), empty

  var errorDescription: String? {
    switch self {
    case .notDownloaded: LocalizableKey.localModelNotDownloaded.string
    case .invalidRepository(let id): LocalizableKey.invalidRepository.format(id)
    case .empty: LocalizableKey.localModelEmpty.string
    }
  }
}

/// Downloads, finds and loads MLX checkpoints from Hugging Face. Shared by TranslateGemma and the local
/// rewrite models so every model lives in one cache inside the app's Application Support folder.
enum MLXHub {
  static let cache: HubCache = {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return HubCache(cacheDirectory: base.appending(path: "FineText/Models", directoryHint: .isDirectory))
  }()

  static let patterns = ["*.safetensors", "*.json", "*.jinja", "tokenizer.model"]

  private static func repo(_ id: String) throws -> Repo.ID {
    guard let repo = Repo.ID(rawValue: id) else { throw MLXHubError.invalidRepository(id) }
    return repo
  }

  private static func hub() -> HubClient { HubClient(cache: cache) }

  /// The local snapshot folder when every file of the model is on disk, otherwise nil.
  static func localSnapshot(_ id: String) async -> URL? {
    guard let repo = try? repo(id),
          let folder = try? await hub().downloadSnapshot(of: repo, matching: patterns, localFilesOnly: true),
          isComplete(folder)
    else { return nil }
    return folder
  }

  /// Reports (downloaded, total) in bytes. Snapshot progress is weighted by each file's byte size, but its
  /// `completedUnitCount` only moves when a whole file finishes; `fractionCompleted` includes in-flight bytes.
  static func download(_ id: String, progress: @MainActor @Sendable @escaping (Int64, Int64) -> Void) async throws {
    let folder = try await hub().downloadSnapshot(of: repo(id), matching: patterns) { value in
      let total = value.totalUnitCount
      progress(Int64((value.fractionCompleted * Double(total)).rounded()), total)
    }
    try Task.checkCancellation()
    guard isComplete(folder) else { throw MLXHubError.notDownloaded }
  }

  static func remove(_ id: String) throws {
    let folder = cache.repoDirectory(repo: try repo(id), kind: .model)
    if FileManager.default.fileExists(atPath: folder.path) {
      try FileManager.default.removeItem(at: folder)
    }
  }

  static func load(_ configuration: ModelConfiguration) async throws -> ModelContainer {
    try await LLMModelFactory.shared.loadContainer(
      from: LocalOnlyDownloader(), using: TransformersTokenizerLoader(), configuration: configuration
    )
  }

  /// config.json, the tokenizer and every weight shard listed in the index are present.
  static func isComplete(_ folder: URL) -> Bool {
    let fm = FileManager.default
    func exists(_ name: String) -> Bool { fm.fileExists(atPath: folder.appending(path: name).path) }
    guard exists("config.json"), exists("tokenizer.json") || exists("tokenizer.model") else { return false }
    let index = folder.appending(path: "model.safetensors.index.json")
    if let data = try? Data(contentsOf: index),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let map = json["weight_map"] as? [String: String] {
      return Set(map.values).allSatisfy(exists)
    }
    return exists("model.safetensors")
  }
}

// MARK: - Download progress

struct DownloadProgress: Equatable, Sendable {
  var completedBytes: Int64 = 0
  var totalBytes: Int64 = 0
  var bytesPerSecond: Double?
  private var sampleBytes: Int64?
  private var sampleTime: ContinuousClock.Instant?

  init(totalBytes: Int64 = 0) {
    self.totalBytes = totalBytes
  }

  var fraction: Double? { totalBytes > 1 ? min(Double(completedBytes) / Double(totalBytes), 1) : nil }

  /// Progress arrives every ~100 ms; the speed is averaged over windows of at least 0.5 s
  /// and smoothed so the label does not flicker.
  mutating func update(completed: Int64, total: Int64) {
    completedBytes = completed
    if total > 1 { totalBytes = total }
    let now = ContinuousClock.now
    if let sampleBytes, let sampleTime {
      let elapsed = (now - sampleTime) / .seconds(1)
      guard elapsed >= 0.5 else { return }
      let instant = Double(max(completed - sampleBytes, 0)) / elapsed
      bytesPerSecond = bytesPerSecond.map { $0 * 0.6 + instant * 0.4 } ?? instant
    }
    sampleBytes = completed
    sampleTime = now
  }
}

// MARK: - Local text generation

/// Runs downloaded MLX chat models in-process for rewriting and translating.
actor LocalLLM {
  static let shared = LocalLLM()
  private static let idleUnloadDelay: Duration = .seconds(300)

  private var loaded: (id: String, container: ModelContainer)?
  private var idleTask: Task<Void, Never>?

  private func container(for id: String) async throws -> ModelContainer {
    if let loaded, loaded.id == id { return loaded.container }
    unload()
    guard let folder = await MLXHub.localSnapshot(id) else { throw MLXHubError.notDownloaded }
    let container = try await MLXHub.load(ModelConfiguration(directory: folder))
    loaded = (id, container)
    return container
  }

  func unload(_ id: String? = nil) {
    guard id == nil || loaded?.id == id else { return }
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

  /// Streams a chat reply. `onLoading` fires before the weights are read from disk.
  func streamChat(
    model id: String, messages: [ChatMessage],
    onLoading: @MainActor @Sendable () -> Void,
    onDelta: @MainActor @Sendable (String) -> Void
  ) async throws -> String {
    idleTask?.cancel()
    defer { scheduleIdleUnload() }
    if loaded?.id != id { await onLoading() }
    let container = try await container(for: id)
    try Task.checkCancellation()

    let chat: [Chat.Message] = messages.map { $0.role == "system" ? .system($0.content) : $0.role == "assistant" ? .assistant($0.content) : .user($0.content) }
    // Reasoning models (Qwen 3 and friends) skip the thinking block; rewrites don't need it.
    let input = try await container.prepare(input: UserInput(chat: chat, additionalContext: ["enable_thinking": false]))
    let parameters = GenerateParameters(maxTokens: 4096, temperature: 0.7, topP: 0.9)
    let stream = try await container.generate(input: input, parameters: parameters)
    var full = ""
    for await event in stream {
      try Task.checkCancellation()
      guard case .chunk(let text) = event, !text.isEmpty else { continue }
      full += text
      await onDelta(text)
    }
    guard !full.trimmed.isEmpty else { throw MLXHubError.empty }
    return full
  }
}

// MARK: - Downloaded models

struct LocalModel: Codable, Identifiable, Hashable, Sendable {
  /// Hugging Face repository id, e.g. `mlx-community/Qwen3-4B-4bit`.
  let id: String
  var sizeBytes: Int64?
  var addedAt = Date.now

  var name: String { id.split(separator: "/").last.map(String.init) ?? id }
  var author: String { id.split(separator: "/").first.map(String.init) ?? "" }
}

/// The MLX chat models downloaded for rewriting. They show up as the "On This Mac" provider.
@MainActor @Observable final class LocalModelStore {
  private(set) var models: [LocalModel] = []
  private(set) var downloads: [String: DownloadProgress] = [:]
  private(set) var failures: [String: String] = [:]
  private var tasks: [String: Task<Void, Never>] = [:]
  private var downloadIDs: [String: UUID] = [:]

  init() {
    if let data = UserDefaults.standard.data(forKey: DefaultsKey.localModels),
       let saved = try? JSONDecoder().decode([LocalModel].self, from: data) {
      models = saved
    }
    Task { await prune() }
  }

  private func persist() {
    UserDefaults.standard.set(try? JSONEncoder().encode(models), forKey: DefaultsKey.localModels)
  }

  /// Drops entries whose files were deleted outside the app.
  private func prune() async {
    var kept: [LocalModel] = []
    for model in models where await MLXHub.localSnapshot(model.id) != nil { kept.append(model) }
    if kept != models {
      models = kept
      persist()
    }
  }

  func isInstalled(_ id: String) -> Bool { models.contains { $0.id == id } }
  func isDownloading(_ id: String) -> Bool { downloads[id] != nil }
  func model(_ id: String) -> LocalModel? { models.first { $0.id == id } }

  func download(_ id: String, sizeBytes: Int64?) {
    guard tasks[id] == nil else { return }
    failures[id] = nil
    let downloadID = UUID()
    downloadIDs[id] = downloadID
    downloads[id] = DownloadProgress(totalBytes: sizeBytes ?? 0)
    tasks[id] = Task {
      defer {
        if downloadIDs[id] == downloadID {
          tasks[id] = nil
          downloads[id] = nil
          downloadIDs[id] = nil
        }
      }
      do {
        try await MLXHub.download(id) { completed, total in
          guard self.downloadIDs[id] == downloadID else { return }
          self.downloads[id]?.update(completed: completed, total: total)
        }
        try Task.checkCancellation()
        let size = downloads[id].flatMap { $0.totalBytes > 1 ? $0.totalBytes : nil } ?? sizeBytes
        models.removeAll { $0.id == id }
        models.insert(LocalModel(id: id, sizeBytes: size), at: 0)
        persist()
        AppAnalytics.log(.modelDownloaded, ["model_kind": "local_llm", "model": id])
        Haptics.success()
      } catch is CancellationError {
      } catch let error as URLError where error.code == .cancelled {
      } catch {
        if downloadIDs[id] == downloadID {
          failures[id] = error.localizedDescription
          Haptics.failure()
        }
      }
    }
  }

  func cancel(_ id: String) {
    tasks[id]?.cancel()
    tasks[id] = nil
    downloadIDs[id] = nil
    downloads[id] = nil
  }

  func remove(_ id: String) async throws {
    await LocalLLM.shared.unload(id)
    try MLXHub.remove(id)
    models.removeAll { $0.id == id }
    persist()
    AppAnalytics.log(.modelRemoved, ["model_kind": "local_llm", "model": id])
  }
}

// MARK: - Hugging Face catalog

struct HubModelSummary: Identifiable, Hashable, Sendable {
  let id: String
  let downloads: Int
  let likes: Int
  let parameters: Int64?
  let lastModified: Date?
  let gated: Bool

  var name: String { id.split(separator: "/").last.map(String.init) ?? id }
  var author: String { id.split(separator: "/").first.map(String.init) ?? "" }

  var parameterLabel: String? {
    guard let parameters, parameters > 0 else { return nil }
    let billions = Double(parameters) / 1e9
    return billions >= 1 ? LocalizableKey.billionParameters.format(billions.formatted(.number.precision(.fractionLength(0...1))))
      : LocalizableKey.millionParameters.format((Double(parameters) / 1e6).formatted(.number.precision(.fractionLength(0))))
  }
}

struct HubModelDetail: Sendable {
  let sizeBytes: Int64
  let modelType: String?
  let hasChatTemplate: Bool
  let files: Int
}

/// Read-only access to the public Hugging Face model catalog.
enum HubCatalog {
  enum Scope: String, CaseIterable, Identifiable {
    case community, all
    var id: String { rawValue }
    var title: String { self == .community ? LocalizableKey.mlxCommunity.string : LocalizableKey.allMLX.string }
  }

  enum Sort: String, CaseIterable, Identifiable {
    case downloads, trendingScore, likes, lastModified
    var id: String { rawValue }
    var title: String {
      switch self {
      case .downloads: LocalizableKey.mostDownloaded.string
      case .trendingScore: LocalizableKey.trending.string
      case .likes: LocalizableKey.mostLiked.string
      case .lastModified: LocalizableKey.recentlyUpdated.string
      }
    }
  }

  private static let base = URL(string: "https://huggingface.co/api/models")!

  static func search(_ query: String, scope: Scope, sort: Sort, limit: Int = 50) async throws -> [HubModelSummary] {
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    var items: [URLQueryItem] = [
      URLQueryItem(name: "library", value: "mlx"),
      URLQueryItem(name: "pipeline_tag", value: "text-generation"),
      URLQueryItem(name: "sort", value: sort.rawValue),
      URLQueryItem(name: "direction", value: "-1"),
      URLQueryItem(name: "limit", value: String(limit)),
    ]
    for field in ["downloads", "likes", "safetensors", "lastModified", "gated"] {
      items.append(URLQueryItem(name: "expand[]", value: field))
    }
    if scope == .community { items.append(URLQueryItem(name: "author", value: "mlx-community")) }
    if !query.trimmed.isEmpty { items.append(URLQueryItem(name: "search", value: query.trimmed)) }
    components.queryItems = items

    let (data, response) = try await URLSession.shared.data(from: components.url!)
    try check(response, data)
    guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
      throw APIError.decoding(LocalizableKey.invalidModelList.string)
    }
    let dates = ISO8601DateFormatter()
    dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return array.compactMap { object in
      guard let id = object["id"] as? String else { return nil }
      let safetensors = object["safetensors"] as? [String: Any]
      let gated = (object["gated"] as? Bool) ?? ((object["gated"] as? String).map { $0 != "false" } ?? false)
      return HubModelSummary(
        id: id,
        downloads: object["downloads"] as? Int ?? 0,
        likes: object["likes"] as? Int ?? 0,
        parameters: (safetensors?["total"] as? NSNumber)?.int64Value,
        lastModified: (object["lastModified"] as? String).flatMap(dates.date(from:)),
        gated: gated
      )
    }
  }

  /// Total size of the files FineText would download, plus the architecture from config.json.
  static func detail(_ id: String) async throws -> HubModelDetail {
    let url = base.appending(path: id).appending(queryItems: [URLQueryItem(name: "blobs", value: "true")])
    let (data, response) = try await URLSession.shared.data(from: url)
    try check(response, data)
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw APIError.decoding(LocalizableKey.invalidModelDetail.string)
    }
    let siblings = (json["siblings"] as? [[String: Any]]) ?? []
    let wanted = siblings.filter { file in
      guard let name = file["rfilename"] as? String, !name.contains("/") else { return false }
      return MLXHub.patterns.contains { pattern in
        pattern.hasPrefix("*") ? name.hasSuffix(pattern.dropFirst()) : name == pattern
      }
    }
    let size = wanted.reduce(Int64(0)) { $0 + ((($1["size"] as? NSNumber)?.int64Value) ?? 0) }
    let config = json["config"] as? [String: Any]
    let tokenizer = config?["tokenizer_config"] as? [String: Any]
    let names = Set(wanted.compactMap { $0["rfilename"] as? String })
    return HubModelDetail(
      sizeBytes: size,
      modelType: config?["model_type"] as? String,
      hasChatTemplate: tokenizer?["chat_template"] != nil || names.contains("chat_template.jinja") || names.contains("chat_template.json"),
      files: wanted.count
    )
  }

  static func pageURL(_ id: String) -> URL { URL(string: "https://huggingface.co/\(id)")! }

  private static func check(_ response: URLResponse, _ data: Data) throws {
    guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
    throw APIError.http(http.statusCode, OpenAIClient.errorMessage(from: data))
  }
}
