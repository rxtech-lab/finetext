import AppKit
import NaturalLanguage

/// TextKit handles whitespace, paragraph breaks, wrapping and bidirectional text. Token occurrence
/// IDs are deterministic in both versions, so repeated words never share an animation identity.
struct RefinementWordLayout {
  struct Word: Identifiable {
    struct ID: Hashable {
      let text: String
      let occurrence: Int
      let fragment: Int
    }
    let id: ID
    let text: String
    let rect: CGRect
    let glyphImage: NSImage?
  }
  var words: [Word] = []
  var height: CGFloat = 0

  init() {}

  init(text: String, width: CGFloat, rendersGlyphs: Bool = false) {
    guard !text.isEmpty else { return }
    let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    let storage = NSTextStorage(string: text, attributes: [.font: font])
    let manager = NSLayoutManager()
    let container = NSTextContainer(size: NSSize(width: width, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    manager.addTextContainer(container)
    storage.addLayoutManager(manager)
    manager.ensureLayout(for: container)
    height = max(font.boundingRectForFont.height, manager.usedRect(for: container).maxY)

    let tokenizer = NLTokenizer(unit: .word)
    tokenizer.string = text
    var ranges: [NSRange] = []
    var cursor = text.startIndex
    func appendPunctuation(_ range: Range<String.Index>) {
      for index in text[range].indices where !text[index].isWhitespace {
        ranges.append(NSRange(index..<text.index(after: index), in: text))
      }
    }
    tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
      appendPunctuation(cursor..<range.lowerBound)
      ranges.append(NSRange(range, in: text))
      cursor = range.upperBound
      return true
    }
    appendPunctuation(cursor..<text.endIndex)

    let source = text as NSString
    var positionedWords: [Word] = []
    var occurrences: [String: Int] = [:]
    for range in ranges {
      let token = source.substring(with: range)
      let occurrence = occurrences[token, default: 0]
      occurrences[token] = occurrence + 1
      let glyphs = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
      var fragment = 0
      // Split unusually long words at line breaks without losing the original layout.
      manager.enumerateLineFragments(forGlyphRange: glyphs) { _, _, _, lineGlyphs, _ in
        let intersection = NSIntersectionRange(glyphs, lineGlyphs)
        guard intersection.length > 0 else { return }
        let characters = NSIntersectionRange(range, manager.characterRange(forGlyphRange: intersection, actualGlyphRange: nil))
        let rect = manager.boundingRect(forGlyphRange: intersection, in: container)
        var image: NSImage?
        if rendersGlyphs, rect.width > 0, rect.height > 0 {
          // Draw the original glyphs, including kerning, fallback fonts and baseline, into
          // exactly the rectangle used for placement. Re-shaping each token as SwiftUI Text
          // can give it a different width or height and overlap adjacent words/lines.
          let snapshot = NSImage(size: rect.size)
          snapshot.lockFocusFlipped(true)
          manager.drawGlyphs(forGlyphRange: intersection, at: NSPoint(x: -rect.minX, y: -rect.minY))
          snapshot.unlockFocus()
          snapshot.isTemplate = !token.unicodeScalars.contains {
            $0.properties.isEmojiPresentation || $0.value == 0x200D
          }
          image = snapshot
        }
        positionedWords.append(Word(id: .init(text: token, occurrence: occurrence, fragment: fragment),
                          text: source.substring(with: characters), rect: rect, glyphImage: image))
        fragment += 1
      }
    }
    words = positionedWords
  }
}

/// Categories describe the original-to-refined comparison, including when viewing it backwards.
enum RefinementChange: String, Hashable {
  case unchanged, added, deleted, moved
}

struct RefinementChangePlan {
  typealias Word = RefinementWordLayout.Word
  var categories: [Word.ID: RefinementChange] = [:]

  init(before: RefinementWordLayout, after: RefinementWordLayout) {
    let beforeIndices = Dictionary(uniqueKeysWithValues: before.words.enumerated().map { ($0.element.id, $0.offset) })
    let afterIDs = Set(after.words.map(\.id))
    for word in before.words where !afterIDs.contains(word.id) { categories[word.id] = .deleted }
    let shared = after.words.filter { beforeIndices[$0.id] != nil }
    // The longest increasing subsequence stays in reading order. An insertion or line reflow
    // therefore does not incorrectly mark every following word as moved. O(n log n).
    var tails: [Int] = []
    var predecessors = Array(repeating: -1, count: shared.count)
    for index in shared.indices {
      let sourceIndex = beforeIndices[shared[index].id]!
      var low = 0
      var high = tails.count
      while low < high {
        let middle = (low + high) / 2
        if beforeIndices[shared[tails[middle]].id]! < sourceIndex { low = middle + 1 }
        else { high = middle }
      }
      if low > 0 { predecessors[index] = tails[low - 1] }
      if low == tails.count { tails.append(index) } else { tails[low] = index }
    }
    var ordered: Set<Word.ID> = []
    var index = tails.last ?? -1
    while index >= 0 {
      ordered.insert(shared[index].id)
      index = predecessors[index]
    }
    for word in after.words {
      categories[word.id] = beforeIndices[word.id] == nil ? .added : ordered.contains(word.id) ? .unchanged : .moved
    }
  }

  /// Adjacent changes form a phrase; groups play in reading order, never concurrently.
  static func groups(_ words: [Word], category: (Word) -> RefinementChange) -> [[Word]] {
    var result: [[Word]] = []
    var previous: RefinementChange?
    for word in words {
      let kind = category(word)
      if kind != .unchanged {
        if previous == kind { result[result.count - 1].append(word) }
        else { result.append([word]) }
      }
      previous = kind
    }
    return result
  }
}

/// Only slide words whose whole travel area is free. Other words fade out, relocate while
/// invisible, then return at their destination; they never cross another visible glyph run.
struct RefinementMovementPlan {
  let relocatedIDs: Set<RefinementWordLayout.Word.ID>

  init(from source: [RefinementWordLayout.Word], to target: [RefinementWordLayout.Word]) {
    let sourceRects = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0.rect) })
    let paths = target.map { word in
      (id: word.id, rect: sourceRects[word.id].map { $0.union(word.rect) } ?? word.rect)
    }
    var relocated: Set<RefinementWordLayout.Word.ID> = []
    for (word, path) in zip(target, paths) {
      guard let start = sourceRects[word.id], start != word.rect else { continue }
      if paths.contains(where: { other in
        guard other.id != word.id else { return false }
        let overlap = path.rect.intersection(other.rect)
        return !overlap.isNull && overlap.width > 0.25 && overlap.height > 0.25
      }) { relocated.insert(word.id) }
    }
    relocatedIDs = relocated
  }
}

/// Fixed parallel phases keep pacing independent of word count. Every phase, including
/// highlight cleanup and layout preparation, shares the same two-second wall-clock budget.
struct RefinementAnimationTiming {
  static let maximumDuration = 1.9 // Reserve a frame before the user's two-second limit.

  enum Phase: CaseIterable {
    case prepare, mark, fade, stage, morph, hold, cleanup

    var duration: Double {
      switch self {
      case .prepare, .stage: 0.034
      case .mark: 0.28
      case .fade: 0.16
      case .morph: 0.52
      case .hold: 0.20
      case .cleanup: 0.24
      }
    }
  }

  let scale: Double
  let nominalDuration = Phase.allCases.reduce(0.0) { $0 + $1.duration }

  init(preparationSeconds: Double = 0) {
    let available = max(0, Self.maximumDuration - preparationSeconds)
    scale = min(1, available / nominalDuration)
  }

  func scaled(_ seconds: Double) -> Double { seconds * scale }
}
