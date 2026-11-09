import AppKit
import SwiftUI

struct AnimatedRefinementText: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let text: String
  var original: String? = nil
  var refined: String? = nil
  var animateChanges = false
  var replayToken = 0
  @State private var words: [AnimatedWord] = []
  @State private var height: CGFloat = 0
  @State private var previousWords: [AnimatedWord] = []
  @State private var canvasPhase = 1.0
  @State private var canvasStart = 0.0
  @State private var previousRequest: Request?
  @State private var pendingRequest: Request?

  private enum PlaybackDeadline: Error { case reached }

  private struct Request: Equatable {
    let text: String
    let original: String?
    let refined: String?
    let width: CGFloat
    let reduceMotion: Bool
    let animateChanges: Bool
    let replayToken: Int
  }

  /// Streaming deltas update pendingRequest without cancelling the currently playing phrase.
  /// Stopping, replaying, resizing and dismissal still cancel playback immediately.
  private struct PlaybackKey: Equatable {
    let width: CGFloat
    let reduceMotion: Bool
    let animateChanges: Bool
    let replayToken: Int
    let staticRequest: Request?
  }

  private struct AnimatedWord: Identifiable {
    var word: RefinementWordLayout.Word
    var category: RefinementChange
    var reveal: CGFloat = 1
    var strike: CGFloat = 0
    var opacity: Double = 1
    var id: RefinementWordLayout.Word.ID { word.id }
  }

  var body: some View {
    GeometryReader { geometry in
      let request = Request(text: text, original: original, refined: refined,
                            width: max(1, geometry.size.width - 20), reduceMotion: reduceMotion,
                            animateChanges: animateChanges, replayToken: replayToken)
      let key = PlaybackKey(width: request.width, reduceMotion: reduceMotion,
                            animateChanges: animateChanges, replayToken: replayToken,
                            staticRequest: animateChanges ? nil : request)
      ScrollView {
        WordCanvas(source: previousWords, target: words, start: canvasStart, phase: canvasPhase)
        .frame(width: request.width, height: height, alignment: .topLeading)
        .padding(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityValue(LocalizableKey.refinementChangeLegend.string)
      }
      .help(LocalizableKey.refinementChangeLegend.string)
      .onChange(of: request, initial: true) { _, latest in pendingRequest = latest }
      .task(id: key) {
        // Always render the current text statically when this field first appears.
        if previousRequest == nil { await present(request) }
        if !request.animateChanges {
          await present(request)
          return
        }
        do {
          while !Task.isCancelled {
            let latest = pendingRequest ?? request
            if latest != previousRequest { await present(latest) }
            try await Task.sleep(for: .milliseconds(35))
          }
        } catch { return }
      }
    }
  }

  @MainActor private func present(_ request: Request) async {
    let clock = ContinuousClock()
    let started = clock.now
    let target = RefinementWordLayout(text: request.text, width: request.width, rendersGlyphs: true)
    let comparison: RefinementChangePlan?
    if let original = request.original, let refined = request.refined, !refined.isEmpty {
      comparison = RefinementChangePlan(
        before: RefinementWordLayout(text: original, width: request.width),
        after: RefinementWordLayout(text: refined, width: request.width)
      )
    } else { comparison = nil }
    func category(_ word: RefinementWordLayout.Word) -> RefinementChange {
      comparison?.categories[word.id] ?? .unchanged
    }
    func settled(_ word: RefinementWordLayout.Word) -> AnimatedWord {
      // Comparison colors and marks belong only to active playback, including the before view.
      AnimatedWord(word: word, category: .unchanged, reveal: 0, strike: 0)
    }
    @MainActor func transition(_ animation: Animation, update: () -> Void) {
      previousWords = words
      canvasStart = canvasPhase
      update()
      withAnimation(animation) { canvasPhase += 1 }
    }
    @MainActor func settleCanvas() {
      previousWords = words
      canvasStart = canvasPhase
      canvasPhase += 1
    }
    let previous = previousRequest
    previousRequest = request
    // An ordinary navigation, edit or completed run renders immediately. Only generation
    // updates and an explicit before/after button press are allowed to start playback.
    let shouldAnimate = previous != nil && (request.animateChanges || previous?.replayToken != request.replayToken)
    let startingRun = request.animateChanges && previous?.animateChanges == false
    if !shouldAnimate || startingRun || request.reduceMotion || previous?.width != request.width {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        words = target.words.map(settled)
        height = target.height
        settleCanvas()
      }
      return
    }
    let targetIDs = Set(target.words.map(\.id))
    let oldWords = words.map(\.word)
    let removedIDs = Set(oldWords.map(\.id)).subtracting(targetIDs)
    let existing = Set(oldWords.map(\.id)).intersection(targetIDs)
    let destinations = Dictionary(uniqueKeysWithValues: target.words.map { ($0.id, $0) })
    let movement = RefinementMovementPlan(from: oldWords.filter { targetIDs.contains($0.id) }, to: target.words)
    let hiddenIDs = movement.relocatedIDs
    let elapsed = started.duration(to: clock.now)
    let preparationSeconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let timing = RefinementAnimationTiming(preparationSeconds: preparationSeconds)
    let playbackStarted = clock.now
    let deadline = started.advanced(by: .seconds(RefinementAnimationTiming.maximumDuration))
    var scheduledSeconds = 0.0
    @MainActor func pause(_ phase: RefinementAnimationTiming.Phase) async throws {
      try Task.checkCancellation()
      scheduledSeconds += timing.scaled(phase.duration)
      // Absolute times absorb scheduler/rendering overhead instead of adding it per word.
      let next = min(deadline, playbackStarted.advanced(by: .seconds(scheduledSeconds)))
      if clock.now < next { try await clock.sleep(until: next) }
      if clock.now >= deadline { throw PlaybackDeadline.reached }
    }
    @MainActor func finish() {
      var transaction = Transaction(animation: nil)
      transaction.disablesAnimations = true
      withTransaction(transaction) {
        words = target.words.map(settled)
        height = target.height
        settleCanvas()
      }
    }
    do {
      // Prepare all outgoing marks in one update, then draw them together.
      words = words.map { item in
        var item = item
        if removedIDs.contains(item.id) {
          item.category = category(item.word) == .added ? .added : .deleted
          item.reveal = 0
          item.strike = 0
        }
        return item
      }
      try await pause(.prepare)
      transition(.easeInOut(duration: timing.scaled(RefinementAnimationTiming.Phase.mark.duration))) {
        words = words.map { item in
          var item = item
          if removedIDs.contains(item.id) {
            item.reveal = 1
            item.strike = item.category == .deleted ? 1 : 0
          }
          return item
        }
      }
      try await pause(.mark)

      // Deletions and reordered words that would cross gliding text fade before reflow begins.
      transition(.easeOut(duration: timing.scaled(RefinementAnimationTiming.Phase.fade.duration))) {
        words = words.map { item in
          var item = item
          if removedIDs.contains(item.id) || hiddenIDs.contains(item.id) { item.opacity = 0 }
          return item
        }
      }
      try await pause(.fade)
      var relocation = Transaction(animation: nil)
      relocation.disablesAnimations = true
      withTransaction(relocation) {
        words = words.filter { !removedIDs.contains($0.id) }.map { item in
          var item = item
          if hiddenIDs.contains(item.id), let destination = destinations[item.id] {
            item.word = destination
          }
          return item
        }
        words += target.words.filter { !existing.contains($0.id) }.map { word in
          var item = settled(word)
          item.opacity = 0
          return item
        }
        height = max(height, target.height)
      }
      try await pause(.stage)

      // Shared words glide together along clear paths. Insertions, moved highlights and
      // restored deletion marks reveal simultaneously with the same smooth easing curve.
      transition(.smooth(duration: timing.scaled(RefinementAnimationTiming.Phase.morph.duration))) {
        words = words.map { item in
          var item = item
          if let destination = destinations[item.id] {
            item.word = destination
            item.category = category(destination)
            item.opacity = 1
            item.reveal = item.category == .unchanged ? 0 : 1
            item.strike = item.category == .deleted ? 1 : 0
          }
          return item
        }
      }
      try await pause(.morph)
      try await pause(.hold)
      transition(.easeOut(duration: timing.scaled(RefinementAnimationTiming.Phase.cleanup.duration))) {
        words = words.map { item in
          var item = item
          item.category = .unchanged
          item.reveal = 0
          item.strike = 0
          return item
        }
        height = target.height
      }
      try await pause(.cleanup)
      finish()
    } catch PlaybackDeadline.reached {
      // A busy render loop must not leave gaps or unfinished marks beyond the time budget.
      if !Task.isCancelled { finish() }
    } catch {
      // A replacement task owns the current visible words; cancelled tasks never settle over it.
      return
    }
  }

  /// A single animatable Canvas avoids hundreds of independently animated view/layout trees.
  /// Geometry, opacity, mark lengths and colors all interpolate from the same frame clock.
  private struct WordCanvas: View, Animatable {
    let source: [AnimatedWord]
    let target: [AnimatedWord]
    let start: Double
    nonisolated var phase: Double

    nonisolated var animatableData: Double {
      get { phase }
      set { phase = newValue }
    }

    var body: some View {
      let progress = min(1, max(0, phase - start))
      let origins = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
      Canvas { context, _ in
        for item in target {
          let old = origins[item.id] ?? item
          func mix(_ from: CGFloat, _ to: CGFloat) -> CGFloat { from + (to - from) * progress }
          let rect = CGRect(x: mix(old.word.rect.minX, item.word.rect.minX),
                            y: mix(old.word.rect.minY, item.word.rect.minY),
                            width: mix(old.word.rect.width, item.word.rect.width),
                            height: mix(old.word.rect.height, item.word.rect.height))
          // Entering words bloom late so gliding text has mostly cleared their space.
          let fadeProgress = old.opacity < item.opacity ? progress * progress : progress
          var opacity = old.opacity + (item.opacity - old.opacity) * fadeProgress
          // Words wrapping to another line soften mid-flight so they read as passing behind text.
          if abs(old.word.rect.minY - item.word.rect.minY) > 0.5 {
            opacity *= 1 - 0.45 * sin(.pi * progress)
          }
          guard opacity > 0.001 else { continue }
          let reveal = mix(old.reveal, item.reveal)
          let strike = mix(old.strike, item.strike)
          let oldTint = old.category.nsColor
          let tint = oldTint.blended(withFraction: progress, of: item.category.nsColor) ?? item.category.nsColor
          let color = Color(nsColor: tint)
          var layer = context
          layer.opacity = opacity
          let oldAlpha = old.category == .unchanged ? 0.0 : 0.17
          let newAlpha = item.category == .unchanged ? 0.0 : 0.17
          let alpha = oldAlpha + (newAlpha - oldAlpha) * progress
          if reveal > 0.001, alpha > 0.001 {
            let background = CGRect(x: rect.minX, y: rect.minY,
                                    width: (rect.width + 2) * reveal, height: rect.height)
            layer.fill(RoundedRectangle(cornerRadius: 2).path(in: background), with: .color(color.opacity(alpha)))
          }
          if let image = item.word.glyphImage {
            var resolved = layer.resolve(Image(nsImage: image).renderingMode(image.isTemplate ? .template : .original))
            if image.isTemplate { resolved.shading = .color(color) }
            layer.draw(resolved, in: rect)
          }
          if strike > 0.001 {
            let line = CGRect(x: rect.minX, y: rect.midY - 0.75, width: rect.width * strike, height: 1.5)
            layer.fill(Path(line), with: .color(.red))
          }
        }
      }
    }
  }
}

private extension RefinementChange {
  var nsColor: NSColor {
    switch self {
    case .unchanged: .labelColor
    case .added: .systemGreen
    case .deleted: .systemRed
    case .moved: .systemBlue
    }
  }
}
