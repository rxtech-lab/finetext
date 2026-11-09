import AppKit

@main struct RefinementWordLayoutTests {
  static func main() {
    let before = RefinementWordLayout(text: "hello world hello removed", width: 350)
    let after = RefinementWordLayout(text: "world hello added hello", width: 350)
    let shared = Set(before.words.map(\.id)).intersection(after.words.map(\.id))
    assert(shared.count == 3, "Repeated words must keep unique shared identities")
    assert(Set(after.words.map(\.id)).count == after.words.count)
    let oldWorld = before.words.first { $0.text == "world" }!
    let newWorld = after.words.first { $0.text == "world" }!
    assert(oldWorld.id == newWorld.id && oldWorld.rect != newWorld.rect, "Moved words retain identity")
    assert(!shared.contains(before.words.last!.id), "Removed words must exit")
    assert(!shared.contains(after.words.first { $0.text == "added" }!.id), "New words must enter")

    let text = "Hello,  world!\n\n你好，世界！\t👩🏽‍💻 café"
    let multilingual = RefinementWordLayout(text: text, width: 170)
    assert(multilingual.words.map(\.text).joined() == text.filter { !$0.isWhitespace }, "Preserve punctuation, Unicode and emoji")
    assert(multilingual.height > before.height, "Paragraphs and wrapping must affect height")
    assert(multilingual.words.allSatisfy { $0.rect.minX >= 0 && $0.rect.minY >= 0 })
    let narrow = RefinementWordLayout(text: "supercalifragilisticexpialidocious", width: 55)
    assert(narrow.words.count > 1, "Long words must wrap into fragments")
    assert(narrow.words.map(\.text).joined() == "supercalifragilisticexpialidocious")
    assert(RefinementWordLayout(text: "", width: 200).words.isEmpty)
    assert(RefinementWordLayout(text: " \n\t", width: 200).words.isEmpty)
    let source = RefinementWordLayout(text: "alpha beta gamma old stale", width: 350)
    let revised = RefinementWordLayout(text: "gamma alpha beta new fresh", width: 350)
    let plan = RefinementChangePlan(before: source, after: revised)
    func kind(_ text: String, in layout: RefinementWordLayout) -> RefinementChange? {
      plan.categories[layout.words.first { $0.text == text }!.id]
    }
    assert(kind("gamma", in: revised) == .moved, "Actual reorder must be blue")
    assert(kind("alpha", in: revised) == .unchanged && kind("beta", in: revised) == .unchanged)
    assert(kind("old", in: source) == .deleted && kind("stale", in: source) == .deleted)
    assert(kind("new", in: revised) == .added && kind("fresh", in: revised) == .added)
    let groups = RefinementChangePlan.groups(revised.words) { plan.categories[$0.id] ?? .unchanged }
    assert(groups.map { $0.map(\.text) } == [["gamma"], ["new", "fresh"]], "Play change phrases in reading order")
    let separated = RefinementWordLayout(text: "one alpha two beta three", width: 350)
    let additions = RefinementChangePlan(before: RefinementWordLayout(text: "alpha beta", width: 350), after: separated)
    let orderedGroups = RefinementChangePlan.groups(separated.words) { additions.categories[$0.id] ?? .unchanged }
    assert(orderedGroups.map { $0.map(\.text) } == [["one"], ["two"], ["three"]], "Unchanged words separate sequential changes")
    assert(!additions.categories.values.contains(.moved), "Insertions must not mark reflow as reordered text")
    let sameText = "hello hello world hello"
    let identical = RefinementChangePlan(before: RefinementWordLayout(text: sameText, width: 350),
                                        after: RefinementWordLayout(text: sameText, width: 60))
    assert(identical.categories.values.allSatisfy { $0 == .unchanged }, "Reflow and repeated words stay unchanged")
    let allAdded = RefinementChangePlan(before: RefinementWordLayout(), after: revised)
    assert(allAdded.categories.values.allSatisfy { $0 == .added })
    let allDeleted = RefinementChangePlan(before: source, after: RefinementWordLayout())
    assert(allDeleted.categories.values.allSatisfy { $0 == .deleted })
    func word(_ text: String, x: CGFloat, y: CGFloat = 0) -> RefinementWordLayout.Word {
      .init(id: .init(text: text, occurrence: 0, fragment: 0), text: text,
            rect: CGRect(x: x, y: y, width: 30, height: 18), glyphImage: nil)
    }
    let swapSource = [word("alpha", x: 0), word("beta", x: 80)]
    let swapTarget = [word("beta", x: 0), word("alpha", x: 80)]
    let swap = RefinementMovementPlan(from: swapSource, to: swapTarget)
    assert(swap.relocatedIDs == Set(swapSource.map(\.id)), "Swapping words must not slide through each other")
    let clear = RefinementMovementPlan(from: [word("alpha", x: 0), word("beta", x: 150)],
                                       to: [word("alpha", x: 45), word("beta", x: 150)])
    assert(clear.relocatedIDs.isEmpty, "A clear movement path should retain the slide animation")
    let wrapping = RefinementMovementPlan(from: [word("alpha", x: 80), word("beta", x: 0, y: 20)],
                                          to: [word("alpha", x: 0, y: 20), word("beta", x: 40, y: 20)])
    assert(!wrapping.relocatedIDs.isEmpty, "Line wraps must not slide into occupied text")
    let paragraphs = "Mixed English 和中文文字，with 👩🏽‍💻 emoji and café.\n\n" + String(repeating: "Long words wrap safely. ", count: 10)
    let compact = RefinementWordLayout(text: paragraphs, width: 150)
    let expanded = RefinementWordLayout(text: paragraphs, width: 350)
    let resizing = RefinementMovementPlan(from: compact.words, to: expanded.words)
    let startRects = Dictionary(uniqueKeysWithValues: compact.words.map { ($0.id, $0.rect) })
    for item in expanded.words where !resizing.relocatedIDs.contains(item.id) {
      guard let start = startRects[item.id], start != item.rect else { continue }
      let path = start.union(item.rect)
      for other in expanded.words where other.id != item.id {
        let otherPath = startRects[other.id].map { $0.union(other.rect) } ?? other.rect
        let intersection = path.intersection(otherPath)
        assert(intersection.isNull || intersection.width <= 0.25 || intersection.height <= 0.25,
               "Every visible slide must be free of other glyph paths")
      }
    }
    for preparation in [0.0, 0.4, 1.5, 2.0] {
      let timing = RefinementAnimationTiming(preparationSeconds: preparation)
      let duration = RefinementAnimationTiming.Phase.allCases.reduce(0.0) { $0 + timing.scaled($1.duration) }
      assert(duration <= max(0, RefinementAnimationTiming.maximumDuration - preparation) + 0.000001,
             "Parallel phases and highlight cleanup must share the deadline")
      assert(timing.scale >= 0 && timing.scale <= 1)
    }
    assert(RefinementAnimationTiming().scale == 1, "Normal transitions keep full smooth easing durations")
    assert(RefinementAnimationTiming(preparationSeconds: 2).scale == 0,
           "A delayed frame must settle without extending playback")
    print("Passed layout, categories, collision-free movement and whole-sequence duration checks.")
  }
}
