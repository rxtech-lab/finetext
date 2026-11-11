import SwiftUI

/// Grammar results as flowing text: each original word in red with a strike-through, its correction in green beside it.
/// Hovering a correction opens a popover with the error and alternative replacements.
///
/// Animation: while the model proofreads, the text stays in place. Words not checked yet are dimmed and brighten
/// as the stream reaches them, like a proofreading sweep. Each correction then draws a red strike through the
/// original and springs the green replacement in beside it, nudging the following words aside. Finished results
/// reveal their corrections one after another.
struct GrammarCorrectionsView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Binding var output: String
  /// The author's text the model hasn't reached yet, shown dimmed while streaming.
  var unchecked: String?
  var showsCorrections = true
  var isStreaming = false

  var body: some View {
    let tokens = Self.tokens(GrammarMarkup.parse(output), unchecked: unchecked ?? "")
    ScrollView {
      GrammarFlowLayout(lineSpacing: 5) {
        ForEach(tokens) { token in
          switch token.kind {
          case .word(let text):
            Text(text)
              .opacity(token.pending ? 0.35 : 1)
              .layoutValue(key: SpaceAfter.self, value: token.spaceAfter)
          case .lineBreak:
            Text(" ").frame(width: 0).layoutValue(key: LineBreak.self, value: true)
          case .fix(let index, let ordinal, let fix):
            GrammarFixChip(fix: fix, index: index, output: $output, showsCorrection: showsCorrections,
                           revealDelay: isStreaming ? 0.05 : 0.15 + min(Double(ordinal) * 0.09, 1.5),
                           isStreaming: isStreaming)
              .layoutValue(key: SpaceAfter.self, value: token.spaceAfter)
          }
        }
      }
      .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: unchecked)
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
  }

  struct Token: Identifiable {
    /// A correction keeps its segment index (for edits) and its position among corrections (for staggering).
    enum Kind { case word(String), lineBreak, fix(index: Int, ordinal: Int, GrammarFix) }
    let id: Int
    let kind: Kind
    var spaceAfter = false
    var pending = false
  }

  /// Checked tokens followed by dimmed unchecked ones. IDs stay stable as words move from unchecked to checked.
  static func tokens(_ segments: [GrammarSegment], unchecked: String) -> [Token] {
    var checked = tokens(segments)
    if unchecked.first?.isWhitespace == true, !checked.isEmpty { checked[checked.count - 1].spaceAfter = true }
    return checked + tokens([.text(unchecked)], pending: true, startID: checked.count)
  }

  /// Splits text into words so lines can wrap around corrections. Ideographic text wraps per character.
  static func tokens(_ segments: [GrammarSegment], pending: Bool = false, startID: Int = 0) -> [Token] {
    var tokens: [Token] = []
    var ordinal = 0
    func add(_ kind: Token.Kind) { tokens.append(Token(id: startID + tokens.count, kind: kind, pending: pending)) }
    func markSpace() {
      if let last = tokens.indices.last { tokens[last].spaceAfter = true }
    }
    for (index, segment) in segments.enumerated() {
      switch segment {
      case .fix(let fix):
        add(.fix(index: index, ordinal: ordinal, fix))
        ordinal += 1
      case .text(let text):
        var word = ""
        func flush() {
          if !word.isEmpty { add(.word(word)); word = "" }
        }
        for character in text {
          if character.isNewline {
            flush(); add(.lineBreak)
          } else if character.isWhitespace {
            flush(); markSpace()
          } else if character.unicodeScalars.first?.properties.isIdeographic == true {
            flush(); add(.word(String(character)))
          } else {
            word.append(character)
          }
        }
        flush()
      }
    }
    return tokens
  }
}

private struct SpaceAfter: LayoutValueKey { static let defaultValue = false }
private struct LineBreak: LayoutValueKey { static let defaultValue = false }

/// Wraps words like text. A line break starts a new line; two in a row leave an empty line.
private struct GrammarFlowLayout: Layout {
  var lineSpacing: CGFloat
  private let spaceWidth: CGFloat = 4

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 400
    return CGSize(width: width, height: arrange(subviews, width: width).height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let frames = arrange(subviews, width: bounds.width).frames
    for (subview, frame) in zip(subviews, frames) {
      subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                    proposal: ProposedViewSize(frame.size))
    }
  }

  private func arrange(_ subviews: Subviews, width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
    var frames = Array(repeating: CGRect.zero, count: subviews.count)
    var line: [(index: Int, size: CGSize, x: CGFloat)] = []
    var x: CGFloat = 0, y: CGFloat = 0
    func finishLine(minimumHeight: CGFloat = 0) {
      let height = max(minimumHeight, line.map(\.size.height).max() ?? 0)
      // Baseline-ish alignment: center each item vertically in its line.
      for item in line {
        frames[item.index] = CGRect(x: item.x, y: y + (height - item.size.height) / 2, width: item.size.width, height: item.size.height)
      }
      y += height + lineSpacing
      line = []
      x = 0
    }
    for (index, subview) in subviews.enumerated() {
      let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
      if subview[LineBreak.self] {
        // A break on an empty line keeps the blank line visible.
        finishLine(minimumHeight: line.isEmpty ? size.height : 0)
        continue
      }
      if x > 0, x + size.width > width { finishLine() }
      line.append((index, CGSize(width: min(size.width, width), height: size.height), x))
      x += size.width + (subview[SpaceAfter.self] ? spaceWidth : 0)
    }
    if !line.isEmpty { finishLine() }
    return (frames, max(0, y - lineSpacing))
  }
}

/// One correction. The popover opens on hover and stays open while the pointer is over it.
private struct GrammarFixChip: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let fix: GrammarFix
  let index: Int
  @Binding var output: String
  var showsCorrection = true
  var revealDelay: Double = 0
  var isStreaming = false
  /// 0 → 1 as the red strike draws across the original words.
  @State private var strike: CGFloat = 0
  @State private var showsReplacement = false
  @State private var showsDetails = false
  @State private var hoveringChip = false
  @State private var hoveringPopover = false
  @State private var closeTask: Task<Void, Never>?

  var body: some View {
    HStack(spacing: 3) {
      if showsCorrection, !fix.original.isEmpty {
        Text(fix.original)
          .foregroundStyle(strike > 0 ? Color.red : Color.primary)
          .overlay(alignment: .leading) {
            Rectangle()
              .fill(.red)
              .frame(height: 1.5)
              .scaleEffect(x: strike, anchor: .leading)
          }
          .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.8, anchor: .trailing))))
      }
      if !fix.replacement.isEmpty, showsReplacement || !showsCorrection {
        Text(fix.replacement)
          .fontWeight(showsCorrection ? .medium : .regular)
          .foregroundStyle(showsCorrection ? Color.green : Color.primary)
          .contentTransition(.numericText())
          .transition(.asymmetric(
            insertion: .scale(scale: 0.4, anchor: .leading).combined(with: .opacity).combined(with: .offset(y: 5)),
            removal: .opacity
          ))
      }
    }
    .padding(.horizontal, showsCorrection ? 3 : 0)
    .background(Color.red.opacity(showsCorrection ? (hoveringChip ? 0.16 : 0.08) * strike : 0), in: RoundedRectangle(cornerRadius: 4))
    .contentShape(Rectangle())
    .onAppear(perform: reveal)
    .onHover { hovering in
      hoveringChip = hovering
      if hovering { open() } else { scheduleClose() }
    }
    .onTapGesture { open() }
    .popover(isPresented: $showsDetails, arrowEdge: .bottom) {
      details
        .onHover { hovering in
          hoveringPopover = hovering
          if !hovering { scheduleClose() }
        }
    }
    .allowsHitTesting(showsCorrection)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("\(fix.original) → \(fix.replacement). \(fix.reason)")
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { open() }
  }

  private var title: String {
    if fix.original.isEmpty { return LocalizableKey.grammarInserted.format(fix.replacement) }
    if fix.replacement.isEmpty { return LocalizableKey.grammarRemoved.format(fix.original) }
    return "\(fix.original) → \(fix.replacement)"
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(title, systemImage: "exclamationmark.circle.fill")
        .font(.headline)
        .symbolRenderingMode(.multicolor)
      Text(fix.reason.isEmpty ? LocalizableKey.grammarCorrection.string : fix.reason)
        .font(.callout)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      if !fix.alternatives.isEmpty {
        Divider()
        Text(LocalizableKey.grammarAlternatives.string).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        ForEach(fix.alternatives, id: \.self) { alternative in
          Button {
            Haptics.tap()
            showsDetails = false
            withAnimation(reduceMotion ? nil : .spring(duration: 0.35, bounce: 0.25)) {
              output = GrammarMarkup.choose(alternative, at: index, in: output)
            }
          } label: {
            Label(LocalizableKey.useAlternative.format(alternative), systemImage: "arrow.left.arrow.right")
          }
          .buttonStyle(.borderless)
          .disabled(isStreaming)
        }
      }
      Divider()
      Button {
        Haptics.tap()
        showsDetails = false
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
          output = GrammarMarkup.keepOriginal(at: index, in: output)
        }
      } label: {
        Label(LocalizableKey.keepOriginal.string, systemImage: "arrow.uturn.backward")
      }
      .buttonStyle(.borderless)
      .disabled(isStreaming)
    }
    .padding(14)
    .frame(width: 280, alignment: .leading)
  }

  /// Strike first, then spring the replacement in so the eye reads "this → that".
  private func reveal() {
    guard strike == 0 else { return }
    guard !reduceMotion else {
      strike = 1
      showsReplacement = true
      return
    }
    withAnimation(.easeOut(duration: 0.28).delay(revealDelay)) { strike = 1 }
    withAnimation(.spring(duration: 0.4, bounce: 0.35).delay(revealDelay + 0.2)) { showsReplacement = true }
  }

  private func open() {
    closeTask?.cancel()
    showsDetails = true
  }

  /// A short delay lets the pointer travel from the word into the popover without closing it.
  private func scheduleClose() {
    closeTask?.cancel()
    closeTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled, !hoveringChip, !hoveringPopover else { return }
      showsDetails = false
    }
  }
}
