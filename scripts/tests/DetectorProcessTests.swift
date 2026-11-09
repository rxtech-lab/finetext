import Foundation
import Darwin

enum AIDetectorError: Error { case process(String) }

@MainActor final class OutputRecorder {
  var latest = ""
}

@main struct DetectorProcessTests {
  @MainActor static func main() async throws {
    let python = URL(fileURLWithPath: CommandLine.arguments[1])
    let recorder = OutputRecorder()
    let streaming = Task {
      try await DetectorProcess.run(python, ["-c", "import time; print('Installing runtime package', flush=True); time.sleep(2); print('Ready', flush=True)"],
        onOutput: { recorder.latest = $0 })
    }
    let outputDeadline = ContinuousClock.now.advanced(by: .seconds(10))
    while recorder.latest.isEmpty {
      precondition(ContinuousClock.now < outputDeadline, "Setup output must arrive before the worker exits")
      try await Task.sleep(for: .milliseconds(20))
    }
    precondition(recorder.latest == "Installing runtime package")
    _ = try await streaming.value
    precondition(recorder.latest == "Ready", "Final installer output must be delivered")
    let output = try await DetectorProcess.run(python, ["-c", "import sys; sys.stderr.write('e'*200000); print('o'*200000)"])
    precondition(output.count == 200001, "Large stdout/stderr must not block")
    let input = Data(repeating: 120, count: 200000)
    let echoed = try await DetectorProcess.run(python, ["-c", "import sys; print(len(sys.stdin.buffer.read()))"], input: input)
    precondition(String(decoding: echoed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "200000")
    do {
      _ = try await DetectorProcess.run(python, ["-c", "import sys; sys.stderr.write('diagnostic'); sys.exit(7)"])
      fatalError("Failed subprocess must not succeed")
    } catch AIDetectorError.process(let message) { precondition(message.contains("diagnostic")) }

    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let marker = directory.appending(path: "pid")
    let task = Task {
      try await DetectorProcess.run(python, ["-c", "import os,sys,time,signal; from pathlib import Path; signal.signal(signal.SIGTERM, signal.SIG_IGN); Path(sys.argv[1]).write_text(str(os.getpid())); time.sleep(30)", marker.path])
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while !FileManager.default.fileExists(atPath: marker.path) {
      precondition(ContinuousClock.now < deadline, "Worker should launch")
      try await Task.sleep(for: .milliseconds(20))
    }
    let pid = Int32(try String(contentsOf: marker, encoding: .utf8))!
    task.cancel()
    do { _ = try await task.value; fatalError("Cancelled process must throw") } catch is CancellationError {}
    let stopDeadline = ContinuousClock.now.advanced(by: .seconds(5))
    while kill(pid, 0) == 0 {
      precondition(ContinuousClock.now < stopDeadline, "Unresponsive worker must be killed")
      try await Task.sleep(for: .milliseconds(50))
    }

    let never = directory.appending(path: "never")
    let early = Task {
      try await DetectorProcess.run(python, ["-c", "from pathlib import Path; import sys; Path(sys.argv[1]).touch()", never.path])
    }
    early.cancel()
    do { _ = try await early.value; fatalError("Pre-launch cancellation") } catch is CancellationError {}
    precondition(!FileManager.default.fileExists(atPath: never.path))
    print("Detector subprocess tests passed: large I/O, errors, cancellation, forced cleanup, pre-launch cancellation.")
  }
}
