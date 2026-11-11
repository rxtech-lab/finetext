import AppKit
import SwiftUI

/// A single reading surface: shared word identities move between TextKit's exact positions.
struct RefinementResultView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let original: String
  @Binding var output: String
  let status: JobStatus
  var limit: Int?
  var assessment: RewriteItem?
  var preview: String?
  /// Structured presets (e.g. email subject + body) show one editable box per field.
  var fields: [PresetField]?
  /// Grammar presets mark corrections inline; they show as red strike-through originals beside green replacements.
  var grammar = false
  @AppStorage("showGrammarCorrections") private var showsCorrections = true
  @State private var showingBefore = false
  @State private var showEditor = false
  @State private var replayToken = 0

  private var displayedOutput: String { status.isRunning ? (preview ?? output) : output }
  /// Readable text for the animation and counts; field tags never show.
  private var displayedText: String {
    grammar ? GrammarMarkup.plainText(displayedOutput) : StructuredOutput.plainText(displayedOutput, fields: fields)
  }
  /// Grammar results use their own proofreading animation, from the first streamed word to the finished result.
  private var showsGrammar: Bool { grammar && !showsOriginal }
  private var showsGrammarSummary: Bool { showsGrammar && !status.isRunning }
  private var correctionCount: Int { GrammarMarkup.fixes(in: output).count }
  private var afterTitle: String { grammar ? LocalizableKey.correctedText.string : LocalizableKey.afterRefinement.string }
  private var showsOriginal: Bool { showingBefore || displayedOutput.isEmpty }
  private var showsFields: Bool {
    guard let fields, !showsOriginal, !status.isRunning else { return false }
    return StructuredOutput.parse(output, fields: fields) != nil
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(showsOriginal ? LocalizableKey.beforeRefinement.string : afterTitle)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .help(legend)
          .accessibilityLabel(legend)
        Spacer()
        if showsGrammarSummary, correctionCount > 0 {
          Toggle(isOn: $showsCorrections.animation(reduceMotion ? nil : .easeInOut(duration: 0.2))) {
            Label(showsCorrections ? LocalizableKey.hideCorrections.string : LocalizableKey.showCorrections.string,
                  systemImage: showsCorrections ? "eye.slash" : "eye")
          }
          .toggleStyle(.button)
          .help(showsCorrections ? LocalizableKey.hideCorrections.string : LocalizableKey.showCorrections.string)
          .onChange(of: showsCorrections) { _, _ in Haptics.tap() }
        }
        Button {
          Haptics.tap()
          withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05)) {
            showingBefore.toggle()
            replayToken += 1
          }
        } label: {
          Image(systemName: showingBefore ? "sparkles" : "clock.arrow.circlepath")
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
          Text(showingBefore ? afterTitle : LocalizableKey.beforeRefinement.string)
            .contentTransition(.numericText())
        }
        .help(showingBefore ? LocalizableKey.showAfterRefinement.string : LocalizableKey.showBeforeRefinement.string)
        .disabled(output.isEmpty || status.isRunning)
        if !showsFields {
          IconButton("square.and.pencil", help: LocalizableKey.edit.string) { showEditor = true }
            .disabled(output.isEmpty || status.isRunning)
        }
      }
      if showsFields, let fields {
        StructuredOutputView(output: $output, fields: fields)
          .transition(.opacity)
      } else if showsGrammar {
        GrammarCorrectionsView(
          output: $output,
          unchecked: status.isRunning ? GrammarMarkup.unchecked(original: original, markup: displayedOutput) : nil,
          showsCorrections: showsCorrections, isStreaming: status.isRunning
        )
        .overlay(alignment: .bottom) { runningOverlay }
        .transition(.opacity)
      } else {
        refinementText
      }
      HStack {
        if showsGrammarSummary {
          Label(correctionCount == 0 ? LocalizableKey.noGrammarIssues.string : LocalizableKey.grammarCorrectionCount.format(correctionCount),
                systemImage: correctionCount == 0 ? "checkmark.seal" : "exclamationmark.circle")
            .foregroundStyle(correctionCount == 0 ? .green : .secondary)
        }
        if !showsOriginal, let assessment, assessment.aiScoredText == displayedOutput, assessment.finalAIScore != nil {
          AIScoreButton(item: assessment)
        }
        Spacer()
        if !showsFields {
          Group {
            if let limit, !showsOriginal {
              Text("\(displayedText.count)/\(limit)")
                .foregroundStyle(displayedText.count > limit ? .red : .secondary)
            } else {
              Text(LocalizableKey.characterCount.format((showsOriginal ? original : displayedText).count))
                .foregroundStyle(.secondary)
            }
          }
        }
      }
      .font(.caption2)
      .frame(maxWidth: .infinity, alignment: .trailing)
    }
    .onChange(of: status.isRunning) { _, running in
      if running { showingBefore = false }
    }
    .sheet(isPresented: $showEditor) {
      // Grammar results are edited as plain corrected text; saving drops the correction marks.
      RewriteOutputSheet(text: grammar ? Binding(get: { GrammarMarkup.plainText(output) }, set: { output = $0 }) : $output, limit: limit)
    }
  }

  private var legend: String { grammar ? LocalizableKey.grammarLegend.string : LocalizableKey.refinementChangeLegend.string }

  private var refinementText: some View {
    AnimatedRefinementText(
      text: showsOriginal ? original : displayedText, original: original,
      refined: displayedText, animateChanges: status.isRunning, replayToken: replayToken
    )
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    .overlay(alignment: .bottom) { runningOverlay }
  }

  @ViewBuilder private var runningOverlay: some View {
    if status.isRunning {
      VStack(spacing: 8) {
        if case .running(let message) = status { ProgressView(message) }
        if let assessment, let score = assessment.finalAIScore {
          Text((preview == nil ? LocalizableKey.aiScoreValue : .bestAIScoreValue).format(score.formatted(.number.precision(.fractionLength(1)))))
            .font(.caption).monospacedDigit()
          if let target = assessment.targetAIScore {
            Text("\(LocalizableKey.targetAIScore.string): \(Int(target))/100").font(.caption).foregroundStyle(.secondary)
          }
        }
      }.padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(8)
        .allowsHitTesting(false)
    }
  }
}

private struct RewriteOutputSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Binding var text: String
  let limit: Int?
  @State private var draft = ""

  var body: some View {
    VStack(spacing: 12) {
      Text(LocalizableKey.edit.string).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
      OutputEditor(text: $draft, limit: limit)
      HStack {
        Spacer()
        Button(LocalizableKey.cancel.string, role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button(LocalizableKey.done.string) {
          text = draft
          Haptics.tap()
          dismiss()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
      }
    }
    .padding(16)
    .frame(width: 408, height: 520)
    .onAppear { draft = text }
  }
}

