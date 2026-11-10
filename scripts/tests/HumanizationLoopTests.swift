import Foundation

// Keep this test executable independent of AppKit, model downloads, and paid providers.
enum DefaultsKey {
  static let humanizationMode = "humanizationMode"
  static let humanizeRounds = "humanizeRounds"
}
enum AIDetectorError: Error { case notReady, emptyText }

@main struct HumanizationLoopTests {
  @MainActor static func main() async throws {
    func expect(_ value: Bool, _ message: String) {
      precondition(value, message)
    }
    let suite = "HumanizationTests-\(UUID())"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(0, forKey: DefaultsKey.humanizeRounds)
    expect(HumanizationMode.selected(in: defaults) == .off, "Migrate disabled humanizer")
    defaults.set(3, forKey: DefaultsKey.humanizeRounds)
    expect(HumanizationMode.selected(in: defaults) == .manual, "Migrate fixed rounds")
    defaults.set("automatic", forKey: DefaultsKey.humanizationMode)
    expect(HumanizationMode.selected(in: defaults) == .automatic, "Persist automatic mode")

    var updates = 0
    let unlimited = try await HumanizationLoop.run(
      text: "0", mode: .automatic, rounds: 1, target: 20,
      score: { 100 - Double($0)! * 2 },
      refine: { _, round in String(round) }, update: { _ in updates += 1 }
    )
    expect(unlimited.rounds == 40 && unlimited.score == 20 && unlimited.text == "40", "No hidden round cap")
    expect(updates == 41, "Score initial text and every completed round")

    let satisfied = try await HumanizationLoop.run(
      text: "already good", mode: .automatic, rounds: 3, target: 20,
      score: { _ in 10 }, refine: { _, _ in fatalError("Already met target") }, update: { _ in }
    )
    expect(satisfied.rounds == 0, "Avoid unnecessary round trips")

    let unchanged = try await HumanizationLoop.run(
      text: "original", mode: .automatic, rounds: 1, target: 20,
      score: { _ in 80 }, refine: { _, round in "candidate \(round)" }, update: { _ in }
    )
    expect(unchanged.rounds == 3 && unchanged.text == "original" && unchanged.score == 80,
           "Three equal scores stop automatic checking and preserve the original")
    expect(unchanged.stoppedForPlateau, "Report why unchanged output was retained")

    var scoreCalls = 0
    let echoed = try await HumanizationLoop.run(
      text: "original", mode: .automatic, rounds: 1, target: 20,
      score: { _ in scoreCalls += 1; return 80 },
      refine: { text, _ in "\n\(text)\n" }, update: { _ in }
    )
    expect(echoed.rounds == 3 && echoed.stoppedForPlateau && scoreCalls == 1,
           "Echoed input counts toward plateau without re-running the detector")

    var previews: [String] = []
    var inputs: [String] = []
    let previewed = try await HumanizationLoop.run(
      text: "0", mode: .manual, rounds: 3, target: 0,
      score: { text in
        if text != "0" { expect(previews.last == text, "Show each candidate before slow scoring") }
        return text == "0" ? 50 : 80
      },
      refine: { text, round in inputs.append(text); return String(round) },
      preview: { previews.append($0) }, update: { _ in }
    )
    expect(previews == ["1", "2", "3"] && inputs == ["0", "1", "2"],
           "Preview every round, and refine the previous candidate rather than the retained best")
    expect(previewed.text == "0" && previewed.score == 50, "Previews never replace the saved best")
    expect(Set((1...3).map { HumanizationLoop.editingFocus(round: $0) }).count == 3,
           "Successive rounds use different editing strategies")

    var retainedText = ""
    var pendingText = ""
    let interrupted = Task { @MainActor in
      try await HumanizationLoop.run(
        text: "saved best", mode: .manual, rounds: 2, target: 0,
        score: { text in
          if text != "saved best" { try await Task.sleep(for: .seconds(10)) }
          return 50
        }, refine: { _, _ in "unscored draft" },
        preview: { pendingText = $0 }, update: { retainedText = $0.text }
      )
    }
    while pendingText.isEmpty { try await Task.sleep(for: .milliseconds(1)) }
    interrupted.cancel()
    do { _ = try await interrupted.value; fatalError("Scoring must cancel") } catch is CancellationError {}
    expect(pendingText == "unscored draft" && retainedText == "saved best",
           "Cancellation during scoring never commits the preview")

    let plateauScores = [90.0, 60, 70, 80, 75]
    let plateau = try await HumanizationLoop.run(
      text: "0", mode: .automatic, rounds: 1, target: 20,
      score: { plateauScores[Int($0)!] }, refine: { _, round in String(round) }, update: { _ in }
    )
    expect(plateau.rounds == 4 && plateau.text == "1" && plateau.score == 60,
           "Worse scores count as no improvement, including partial recovery above the best")

    let resetScores = [90.0, 80, 85, 80, 70, 75, 72, 70]
    let reset = try await HumanizationLoop.run(
      text: "0", mode: .automatic, rounds: 1, target: 20,
      score: { resetScores[Int($0)!] }, refine: { _, round in String(round) }, update: { _ in }
    )
    expect(reset.rounds == 7 && reset.text == "4" && reset.score == 70,
           "A new best score resets the three-round streak")

    let fixed = try await HumanizationLoop.run(
      text: "original", mode: .manual, rounds: 5, target: 20,
      score: { _ in 80 }, refine: { _, round in String(round) }, update: { _ in }
    )
    expect(fixed.rounds == 5, "Fixed-round mode retains the requested round count")

    let values = [90.0, 30, 70, 60]
    let manual = try await HumanizationLoop.run(
      text: "0", mode: .manual, rounds: 3, target: 0,
      score: { values[Int($0)!] }, refine: { _, round in String(round) }, update: { _ in }
    )
    expect(manual.rounds == 3 && manual.text == "1" && manual.score == 30, "Keep best when later rounds regress")
    let unscored = try await HumanizationLoop.run(
      text: "0", mode: .manual, rounds: 2, target: 0,
      score: nil, refine: { _, round in String(round) }, update: { _ in }
    )
    expect(unscored.text == "2" && unscored.score == nil, "Manual mode works without a detector")

    let newlyEligible = try await HumanizationLoop.run(
      text: "short", mode: .manual, rounds: 2, target: 0,
      score: { $0 == "short" ? nil : 40 },
      refine: { _, round in round == 1 ? "eligible draft" : "short" }, update: { _ in }
    )
    expect(newlyEligible.text == "eligible draft" && newlyEligible.score == 40,
           "Score later eligible drafts and retain them when a later draft is unsupported")
    let stillUnsupported = try await HumanizationLoop.run(
      text: "short", mode: .manual, rounds: 2, target: 0,
      score: { _ in nil }, refine: { _, round in "short \(round)" }, update: { _ in }
    )
    expect(stillUnsupported.text == "short 2" && stillUnsupported.score == nil,
           "Manual refinement continues while drafts remain unsupported")
    do {
      _ = try await HumanizationLoop.run(text: "0", mode: .automatic, rounds: 3, target: 20,
        score: nil, refine: { text, _ in text }, update: { _ in })
      fatalError("Automatic mode must require a detector")
    } catch AIDetectorError.notReady {}

    var last: HumanizationLoop.Result?
    let task = Task { @MainActor in
      try await HumanizationLoop.run(text: "0", mode: .automatic, rounds: 1, target: 0,
        score: { 90 - min(80, Double($0)!) },
        refine: { _, round in
          try await Task.sleep(for: .milliseconds(1))
          return String(round)
        }, update: { last = $0 })
    }
    while (last?.rounds ?? 0) < 8 { try await Task.sleep(for: .milliseconds(1)) }
    task.cancel()
    do { _ = try await task.value; fatalError("Cancellation must escape") } catch is CancellationError {}
    let stopped = last!.rounds
    try await Task.sleep(for: .milliseconds(10))
    expect(last!.rounds == stopped && last!.score != nil, "Stop retains last best result without late updates")
    print("Humanization loop tests passed: migration, 40 rounds, target, three-round plateau, streak reset, regression, manual, cancellation.")
  }
}
