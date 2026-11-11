import Foundation

/// One correction suggested by a grammar preset.
struct GrammarFix: Hashable, Sendable {
  /// The author's characters being replaced; empty when words are inserted.
  var original: String
  /// The correction; empty when words are deleted.
  var replacement: String
  var reason: String
  var alternatives: [String]
}

enum GrammarSegment: Hashable, Sendable {
  case text(String)
  case fix(GrammarFix)
}

/// Grammar results are the author's text with each correction marked inline:
/// `<fix><from>has</from><to>have</to><why>…</why><alt>had</alt></fix>`.
/// Parsing tolerates streaming, so a half-written tag never leaks into the readable text.
enum GrammarMarkup {
  private static let open = "<fix>", close = "</fix>"

  static func formatInstruction(explanationLanguage: String) -> String {
    """
    Return the author's full text with every correction marked inline in exactly this format:
    <fix><from>original words</from><to>corrected words</to><why>short explanation</why><alt>another correct option</alt></fix>
    - Everything outside <fix> tags must be the author's original text, character for character, including spaces, line breaks and Markdown.
    - <from> holds exactly the original characters being replaced and <to> their correction. Use an empty <from></from> to insert missing words and an empty <to></to> to remove words.
    - Keep unchanged spaces and punctuation outside the tag. Mark each error separately and keep it to a word or short phrase.
    - <why> names the kind of error and explains it in one short sentence, written in \(explanationLanguage).
    - Add up to three <alt> tags with other correct replacements, only when they are genuinely different and fit the sentence.
    - If there are no errors, return the text unchanged with no tags. Add no commentary before or after the text.
    Example: "I has two cat." becomes:
    I <fix><from>has</from><to>have</to><why>Subject-verb agreement: "I" takes "have".</why><alt>had</alt></fix> two <fix><from>cat</from><to>cats</to><why>Plural: "two" needs a plural noun.</why></fix>.
    """
  }

  static func parse(_ text: String) -> [GrammarSegment] {
    var segments: [GrammarSegment] = []
    var rest = Substring(text)
    func appendText(_ value: Substring) {
      guard !value.isEmpty else { return }
      if case .text(let previous)? = segments.last {
        segments[segments.count - 1] = .text(previous + value)
      } else {
        segments.append(.text(String(value)))
      }
    }
    while let start = rest.range(of: open) {
      appendText(rest[..<start.lowerBound])
      let body = rest[start.upperBound...]
      let end = body.range(of: close)
      let inner = body[..<(end?.lowerBound ?? body.endIndex)]
      rest = end.map { body[$0.upperBound...] } ?? ""
      let original = value("from", in: inner)
      let replacement = value("to", in: inner)
      guard end != nil, let original, let replacement else {
        // Still streaming: keep showing the author's words; the correction animates in once the tag closes.
        appendText(Substring(original ?? partialValue("from", in: inner)))
        continue
      }
      if original == replacement {
        appendText(Substring(original))
        continue
      }
      let alternatives = values("alt", in: inner).filter { !$0.isEmpty && $0 != replacement && $0 != original }
      segments.append(.fix(GrammarFix(original: original, replacement: replacement,
                                      reason: (value("why", in: inner) ?? "").trimmed, alternatives: alternatives)))
    }
    appendText(withoutPartialTag(rest))
    return segments
  }

  static func compose(_ segments: [GrammarSegment]) -> String {
    segments.map { segment in
      switch segment {
      case .text(let text): text
      case .fix(let fix):
        "<fix><from>\(fix.original)</from><to>\(fix.replacement)</to><why>\(fix.reason)</why>"
          + fix.alternatives.map { "<alt>\($0)</alt>" }.joined() + "</fix>"
      }
    }.joined()
  }

  /// The corrected text, for copying, counts, translation and history previews.
  static func plainText(_ text: String) -> String {
    parse(text).map { segment in
      switch segment {
      case .text(let text): text
      case .fix(let fix): fix.replacement
      }
    }.joined()
  }

  /// The author's text the markup has covered so far: plain text plus each correction's original words.
  static func originalText(_ segments: [GrammarSegment]) -> String {
    segments.map { segment in
      switch segment {
      case .text(let text): text
      case .fix(let fix): fix.original
      }
    }.joined()
  }

  /// While streaming, the part of `original` the model has not reached yet, or nil when the stream drifted from it.
  static func unchecked(original: String, markup: String) -> String? {
    let covered = originalText(parse(markup))
    guard original.hasPrefix(covered) else { return nil }
    return String(original.dropFirst(covered.count))
  }

  static func fixes(in text: String) -> [GrammarFix] {
    parse(text).compactMap { if case .fix(let fix) = $0 { fix } else { nil } }
  }

  /// Swaps the correction at `index` (a segment index) for one of its alternatives, keeping the old one as an alternative.
  static func choose(_ alternative: String, at index: Int, in text: String) -> String {
    var segments = parse(text)
    guard segments.indices.contains(index), case .fix(var fix) = segments[index] else { return text }
    fix.alternatives = [fix.replacement] + fix.alternatives.filter { $0 != alternative }
    fix.replacement = alternative
    segments[index] = .fix(fix)
    return compose(segments)
  }

  /// Drops the correction at `index` and keeps the author's original words.
  static func keepOriginal(at index: Int, in text: String) -> String {
    var segments = parse(text)
    guard segments.indices.contains(index), case .fix(let fix) = segments[index] else { return text }
    segments[index] = .text(fix.original)
    return compose(segments)
  }

  /// Text of the first complete `<tag>…</tag>`, or nil while it is missing or still streaming.
  private static func value(_ tag: String, in inner: Substring) -> String? {
    guard let start = inner.range(of: "<\(tag)>") else { return nil }
    let body = inner[start.upperBound...]
    guard let end = body.range(of: "</\(tag)>") else { return nil }
    return String(body[..<end.lowerBound])
  }

  /// Text streamed so far inside an unclosed `<tag>`, without a half-written closing tag.
  private static func partialValue(_ tag: String, in inner: Substring) -> String {
    guard let start = inner.range(of: "<\(tag)>") else { return "" }
    let body = inner[start.upperBound...]
    if let end = body.range(of: "</\(tag)>") { return String(body[..<end.lowerBound]) }
    if let last = body.lastIndex(of: "<"), "</\(tag)>".hasPrefix(body[last...]) { return String(body[..<last]) }
    return String(body)
  }

  private static func values(_ tag: String, in inner: Substring) -> [String] {
    var result: [String] = []
    var rest = inner
    while let start = rest.range(of: "<\(tag)>"), let end = rest[start.upperBound...].range(of: "</\(tag)>") {
      result.append(String(rest[start.upperBound..<end.lowerBound]).trimmed)
      rest = rest[end.upperBound...]
    }
    return result
  }

  /// Hides a `<fix>` opening tag that is still arriving, e.g. a trailing "<fi".
  private static func withoutPartialTag(_ text: Substring) -> Substring {
    guard let last = text.lastIndex(of: "<") else { return text }
    let tail = text[last...]
    return open.hasPrefix(tail) ? text[..<last] : text
  }
}
