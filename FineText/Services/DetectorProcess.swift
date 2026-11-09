import Foundation
import Darwin

/// A subprocess owns its inference memory and gives it back on exit. Text travels over stdin,
/// never command arguments or disk; stdout/stderr use files so full pipe buffers cannot deadlock.
final class DetectorProcess: @unchecked Sendable {
  private let lock = NSLock()
  private let process = Process()
  private var cancelled = false

  func launch(executable: URL, arguments: [String], input: Pipe?, output: FileHandle, error: FileHandle) throws {
    lock.lock()
    defer { lock.unlock() }
    guard !cancelled else { throw CancellationError() }
    process.executableURL = executable
    process.arguments = arguments
    process.standardInput = input ?? Pipe()
    process.standardOutput = output
    process.standardError = error
    var environment = ProcessInfo.processInfo.environment
    environment["HF_HUB_OFFLINE"] = "1"
    environment["TRANSFORMERS_OFFLINE"] = "1"
    environment["TOKENIZERS_PARALLELISM"] = "false"
    environment["PYTHONUNBUFFERED"] = "1"
    environment["PYTHONNOUSERSITE"] = "1"
    environment.removeValue(forKey: "PYTHONPATH")
    environment.removeValue(forKey: "PYTHONHOME")
    process.environment = environment
    try process.run()
  }

  var isRunning: Bool { process.isRunning }
  var exitStatus: Int32 { process.terminationStatus }

  func cancel(force: Bool = false) {
    lock.lock()
    defer { lock.unlock() }
    cancelled = true
    if process.isRunning {
      if force { kill(process.processIdentifier, SIGKILL) } else { process.terminate() }
    }
  }

  static func run(
    _ executable: URL, _ arguments: [String], input: Data? = nil,
    onOutput: (@MainActor @Sendable (String) -> Void)? = nil
  ) async throws -> Data {
    let job = DetectorProcess()
    return try await withTaskCancellationHandler {
      let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      let outURL = folder.appending(path: "stdout")
      let errURL = folder.appending(path: "stderr")
      FileManager.default.createFile(atPath: outURL.path, contents: nil)
      FileManager.default.createFile(atPath: errURL.path, contents: nil)
      let output = try FileHandle(forWritingTo: outURL)
      let error = try FileHandle(forWritingTo: errURL)
      defer { try? output.close(); try? error.close() }
      let outputReader = try FileHandle(forReadingFrom: outURL)
      let errorReader = try FileHandle(forReadingFrom: errURL)
      defer { try? outputReader.close(); try? errorReader.close() }
      func reportOutput() async throws {
        guard let onOutput else { return }
        for reader in [outputReader, errorReader] {
          let data = try reader.readToEnd() ?? Data()
          guard !data.isEmpty else { continue }
          // pip uses carriage returns for progress; retain only the latest bounded line.
          if let line = String(decoding: data, as: UTF8.self).split(whereSeparator: { $0.isNewline }).last {
            try Task.checkCancellation()
            await onOutput(String(line.suffix(400)))
          }
        }
      }
      let pipe = Pipe()
      _ = fcntl(pipe.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
      try job.launch(executable: executable, arguments: arguments, input: pipe, output: output, error: error)
      // Write off the cooperative executor: a long document can exceed a pipe's buffer.
      let writer = Task.detached {
        defer { try? pipe.fileHandleForWriting.close() }
        if let input { try pipe.fileHandleForWriting.write(contentsOf: input) }
      }
      while job.isRunning {
        try await reportOutput()
        try await Task.sleep(for: .milliseconds(100))
      }
      try await reportOutput()
      try Task.checkCancellation()
      guard job.exitStatus == 0 else {
        let data = (try? Data(contentsOf: errURL)) ?? Data()
        throw AIDetectorError.process(String(decoding: data.suffix(2500), as: UTF8.self))
      }
      try await writer.value
      return try Data(contentsOf: outURL)
    } onCancel: {
      job.cancel()
      Task.detached {
        try? await Task.sleep(for: .seconds(2))
        job.cancel(force: true)
      }
    }
  }
}

