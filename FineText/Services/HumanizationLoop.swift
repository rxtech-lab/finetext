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
  struct Result: Sendable {
    let text: String
    let score: Double?
    let rounds: Int
  }

  static func run(
    text: String, mode: HumanizationMode, rounds: Int, target: Double,
    score: (@MainActor (String) async throws -> Double)?,
    refine: @MainActor (String, Int) async throws -> String,
    update: @MainActor (Result) -> Void
  ) async throws -> Result {
    guard mode != .automatic || score != nil else { throw AIDetectorError.notReady }
    let target = min(100, max(0, target.isFinite ? target : 20))
    var best = Result(text: text, score: try await score?(text), rounds: 0)
    try Task.checkCancellation()
    await update(best)
    guard mode != .off else { return best }
    var current = text
    var completed = 0
    var roundsWithoutImprovement = 0
    while mode == .automatic || completed < max(0, rounds) {
      try Task.checkCancellation()
      if mode == .automatic, let value = best.score, value <= target { break }
      let candidate = try await refine(current, completed + 1)
      try Task.checkCancellation()
      guard !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIDetectorError.emptyText }
      let value = try await score?(candidate)
      try Task.checkCancellation()
      completed += 1
      current = candidate
      if value == nil || best.score == nil || value! < best.score! {
        best = Result(text: candidate, score: value, rounds: completed)
        roundsWithoutImprovement = 0
      } else {
        best = Result(text: best.text, score: best.score, rounds: completed)
        roundsWithoutImprovement += 1
      }
      await update(best)
      if mode == .automatic, roundsWithoutImprovement >= 3 { break }
    }
    return best
  }
}
