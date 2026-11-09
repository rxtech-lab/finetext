import Foundation
import NaturalLanguage
import Darwin

enum DetectorSetupPhase: Equatable, Sendable {
  case checkingPython, creatingRuntime, installingDependencies, verifyingRuntime, downloadingModel

  var title: String {
    switch self {
    case .checkingPython: LocalizableKey.detectorCheckingPython.string
    case .creatingRuntime: LocalizableKey.detectorCreatingRuntime.string
    case .installingDependencies: LocalizableKey.detectorInstallingDependencies.string
    case .verifyingRuntime: LocalizableKey.detectorVerifyingRuntime.string
    case .downloadingModel: LocalizableKey.detectorDownloadingModel.string
    }
  }
}

enum AIDetectorEngine: String, CaseIterable, Identifiable, Sendable {
  case disabled, desklib, tropa
  var id: String { rawValue }
  var name: String {
    switch self {
    case .disabled: LocalizableKey.off.string
    case .desklib: "Desklib v1.01"
    case .tropa: "Tropa Mini"
    }
  }
  var repository: String {
    switch self {
    case .disabled: ""
    case .desklib: "desklib/ai-text-detector-v1.01"
    case .tropa: "wasitaigeneratedcom/tropa-mini-ai-text-detector"
    }
  }
  var license: String { self == .tropa ? "Apache-2.0" : "MIT" }
  static var selected: Self {
    Self(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.detectorEngine) ?? "") ?? .disabled
  }
}

enum AIDetectorError: LocalizedError {
  case notReady, pythonMissing, runnerMissing, invalidScore, unsupportedText, emptyText, process(String)
  var errorDescription: String? {
    switch self {
    case .notReady: LocalizableKey.detectorNotReady.string
    case .pythonMissing: LocalizableKey.detectorPythonMissing.string
    case .runnerMissing: LocalizableKey.detectorRunnerMissing.string
    case .invalidScore: LocalizableKey.detectorInvalidScore.string
    case .unsupportedText: LocalizableKey.detectorUnsupportedText.string
    case .emptyText: LocalizableKey.localModelEmpty.string
    case .process(let message): LocalizableKey.detectorFailure.format(message)
    }
  }
}

actor AIDetector {
  static let shared = AIDetector()
  static let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appending(path: "FineText/DetectorRuntime-v1", directoryHint: .isDirectory)
  private static var python: URL { support.appending(path: "bin/python3") }
  private static var marker: URL { support.appending(path: "ready") }
  private static var runner: URL? { Bundle.main.url(forResource: "ai_detector", withExtension: "py") }
  private var preparing = false

  func runtimeIsInstalled() -> Bool {
    FileManager.default.isExecutableFile(atPath: Self.python.path)
      && FileManager.default.fileExists(atPath: Self.marker.path)
  }

  func isInstalled(_ engine: AIDetectorEngine) async -> Bool {
    guard engine != .disabled,
          FileManager.default.isExecutableFile(atPath: Self.python.path),
          FileManager.default.fileExists(atPath: Self.marker.path) else { return false }
    return await MLXHub.localSnapshot(engine.repository) != nil
  }

  func download(
    _ engine: AIDetectorEngine,
    phase: @MainActor @Sendable @escaping (DetectorSetupPhase) -> Void,
    runtimeOutput: @MainActor @Sendable @escaping (String) -> Void,
    progress: @MainActor @Sendable @escaping (Int64, Int64) -> Void
  ) async throws {
    guard engine != .disabled, !preparing else { throw AIDetectorError.notReady }
    preparing = true
    defer { preparing = false }
    try await prepareRuntime(phase: phase, output: runtimeOutput)
    try Task.checkCancellation()
    await phase(.downloadingModel)
    try await MLXHub.download(engine.repository, progress: progress)
  }

  private func prepareRuntime(
    phase: @MainActor @Sendable (DetectorSetupPhase) -> Void,
    output: @MainActor @Sendable @escaping (String) -> Void
  ) async throws {
    guard let runner = Self.runner else { throw AIDetectorError.runnerMissing }
    if FileManager.default.fileExists(atPath: Self.marker.path),
       FileManager.default.isExecutableFile(atPath: Self.python.path) { return }
    await phase(.checkingPython)
    let candidates = ["/opt/homebrew/bin/python3.12", "/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3",
                      "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
                      "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3", "/usr/local/bin/python3"]
      + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/python3" }
    var host: URL?
    for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
      do {
        _ = try await DetectorProcess.run(URL(fileURLWithPath: path), ["-c", "import sys; sys.exit(0 if (3,10) <= sys.version_info[:2] < (3,14) else 1)"])
        host = URL(fileURLWithPath: path)
        break
      } catch is CancellationError { throw CancellationError() } catch { continue }
    }
    guard let host else { throw AIDetectorError.pythonMissing }
    await phase(.creatingRuntime)
    _ = try await DetectorProcess.run(host, ["-m", "venv", Self.support.path])
    var install = ["-m", "pip", "install", "--disable-pip-version-check"]
    // Python.org installations may have no OpenSSL CA file until their certificate
    // setup script runs. Use macOS's CA bundle while keeping TLS verification on.
    if FileManager.default.fileExists(atPath: "/etc/ssl/cert.pem") { install += ["--cert", "/etc/ssl/cert.pem"] }
    install += ["torch>=2.6,<3", "transformers>=4.48,<5", "sentencepiece>=0.2,<1", "protobuf>=5,<7"]
    await phase(.installingDependencies)
    _ = try await DetectorProcess.run(Self.python, install, onOutput: output)
    await phase(.verifyingRuntime)
    _ = try await DetectorProcess.run(Self.python, [runner.path, "--verify"], onOutput: output)
    try Task.checkCancellation()
    try Data("ready".utf8).write(to: Self.marker, options: .atomic)
  }

  func remove(_ engine: AIDetectorEngine) throws {
    guard !preparing, engine != .disabled else { throw AIDetectorError.notReady }
    try MLXHub.remove(engine.repository)
  }

  static func validate(_ text: String) throws {
    let recognizer = NLLanguageRecognizer()
    recognizer.processString(text)
    var words = 0
    text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { _, _, _, _ in words += 1 }
    guard recognizer.dominantLanguage == .english, words >= 50 else { throw AIDetectorError.unsupportedText }
  }

  func score(_ text: String, engine: AIDetectorEngine) async throws -> Double {
    try Task.checkCancellation()
    try Self.validate(text)
    guard let runner = Self.runner, await isInstalled(engine), let folder = await MLXHub.localSnapshot(engine.repository) else {
      throw AIDetectorError.notReady
    }
    let input = try JSONEncoder().encode(Request(folder: folder.path, text: text, engine: engine.rawValue))
    let data = try await DetectorProcess.run(Self.python, [runner.path], input: input)
    let response = try JSONDecoder().decode(Response.self, from: data)
    guard response.score.isFinite, (0...100).contains(response.score) else { throw AIDetectorError.invalidScore }
    return response.score
  }

  private struct Request: Encodable { let folder: String; let text: String; let engine: String }
  private struct Response: Decodable { let score: Double }
}

@MainActor @Observable final class AIDetectorManager {
  enum State: Equatable {
    case checking, notInstalled, installed, downloading(DownloadProgress), removing, failed(String)
  }
  var state: State = .checking
  private(set) var runtimeReady = false
  private(set) var phase: DetectorSetupPhase = .checkingPython
  private(set) var runtimeOutput = ""
  private(set) var isCancelling = false
  private var task: Task<Void, Never>?
  private var operation: UUID?
  var isBusy: Bool {
    switch state { case .downloading, .removing: true; default: false }
  }

  func refresh() {
    guard !isBusy else { return }
    let engine = AIDetectorEngine.selected
    let token = UUID()
    operation = token
    state = .checking
    task = Task {
      let runtimeReady = await AIDetector.shared.runtimeIsInstalled()
      let installed = await AIDetector.shared.isInstalled(engine)
      guard operation == token else { return }
      self.runtimeReady = runtimeReady
      state = installed ? .installed : .notInstalled
    }
  }

  func download() {
    guard !isBusy else { return }
    let engine = AIDetectorEngine.selected
    let token = UUID()
    operation = token
    runtimeOutput = ""
    phase = .checkingPython
    isCancelling = false
    state = .downloading(DownloadProgress())
    task = Task {
      defer { if operation == token { isCancelling = false } }
      do {
        try await AIDetector.shared.download(engine, phase: { phase in
          guard self.operation == token else { return }
          self.phase = phase
          self.runtimeOutput = ""
          if phase == .downloadingModel { self.runtimeReady = true }
        }, runtimeOutput: { line in
          guard self.operation == token else { return }
          self.runtimeOutput = line
        }) { completed, total in
          guard self.operation == token, case .downloading(var progress) = self.state else { return }
          progress.update(completed: completed, total: total)
          self.state = .downloading(progress)
        }
        try Task.checkCancellation()
        guard operation == token else { return }
        state = .installed
        runtimeReady = true
        AppAnalytics.log(.modelDownloaded, ["model_kind": "ai_detector", "model": engine.rawValue])
        Haptics.success()
      } catch is CancellationError {
        if operation == token { state = .notInstalled }
      } catch let error as URLError where error.code == .cancelled {
        if operation == token { state = .notInstalled }
      } catch {
        if operation == token { state = .failed(error.localizedDescription); Haptics.failure() }
      }
    }
  }

  func cancel() {
    // Keep the operation busy until its task acknowledges cancellation; a second install
    // must not race pip or write into the same model snapshot.
    task?.cancel()
    isCancelling = true
  }

  func remove() {
    guard !isBusy else { return }
    let engine = AIDetectorEngine.selected
    state = .removing
    task = Task {
      do {
        try await AIDetector.shared.remove(engine)
        state = .notInstalled
        AppAnalytics.log(.modelRemoved, ["model_kind": "ai_detector", "model": engine.rawValue])
        Haptics.success()
      } catch { state = .failed(error.localizedDescription); Haptics.failure() }
    }
  }
}
