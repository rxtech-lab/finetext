import Foundation

enum HumanizationMode: String, CaseIterable {
  case off, manual, automatic

  static func selected(in defaults: UserDefaults = .standard) -> Self {
    if let raw = defaults.string(forKey: DefaultsKey.humanizationMode), let mode = Self(rawValue: raw) { return mode }
    return defaults.integer(forKey: DefaultsKey.humanizeRounds) > 0 ? .manual : .off
  }
}

enum HumanizationEngine: String, CaseIterable {
  case translateGemma, rewriteModel
}

/// Automatic mode has no round budget, but stops after three rounds without a new best score.
/// The caller owns cancellation and inference errors.
/// Keep the best scored candidate even when later rounds regress or the user stops.
enum HumanizationLoop {
  static func editingFocus(round: Int) -> String {
    switch max(0, round - 1) % 3 {
    case 0: "Rework formulaic openings and stock phrases. Use direct, specific wording grounded in the original."
    case 1: "Restructure sentences and vary their length. Combine repetitive points and split overloaded sentences."
    default: "Rework paragraph flow and transitions. Cut promotional filler and use the author's natural speaking voice."
    }
  }

  struct Result: Sendable {
    let text: String
    let score: Double?
    let rounds: Int
    var stoppedForPlateau = false
  }

  static func run(
    text: String, mode: HumanizationMode, rounds: Int, target: Double,
    score: (@MainActor (String) async throws -> Double)?,
    refine: @MainActor (String, Int) async throws -> String,
    preview: @MainActor (String) -> Void = { _ in },
    update: @MainActor (Result) -> Void
  ) async throws -> Result {
    guard mode != .automatic || score != nil else { throw AIDetectorError.notReady }
    let target = min(100, max(0, target.isFinite ? target : 20))
    var best = Result(text: text, score: try await score?(text), rounds: 0)
    try Task.checkCancellation()
    await update(best)
    guard mode != .off else { return best }
    var current = text
    var currentScore = best.score
    var completed = 0
    var roundsWithoutImprovement = 0
    while mode == .automatic || completed < max(0, rounds) {
      try Task.checkCancellation()
      if mode == .automatic, let value = best.score, value <= target { break }
      let candidate = try await refine(current, completed + 1)
      try Task.checkCancellation()
      guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIDetectorError.emptyText }
      await preview(candidate)
      // A model may echo its input. Re-scoring the same text wastes inference and
      // can turn detector noise into a false improvement.
      let unchanged = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        == current.trimmingCharacters(in: .whitespacesAndNewlines)
      let value = unchanged ? currentScore : try await score?(candidate)
      try Task.checkCancellation()
      completed += 1
      current = candidate
      currentScore = value
      if value == nil || best.score == nil || value! < best.score! {
        best = Result(text: candidate, score: value, rounds: completed)
        roundsWithoutImprovement = 0
      } else {
        best = Result(text: best.text, score: best.score, rounds: completed)
        roundsWithoutImprovement += 1
      }
      if mode == .automatic, roundsWithoutImprovement >= 3 {
        best.stoppedForPlateau = true
      }
      await update(best)
      if best.stoppedForPlateau { break }
    }
    return best
  }
}
