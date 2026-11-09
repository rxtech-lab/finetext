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
  @State private var showingBefore = false
  @State private var showEditor = false
  @State private var replayToken = 0

  private var showsOriginal: Bool { showingBefore || output.isEmpty }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(showsOriginal ? LocalizableKey.beforeRefinement.string : LocalizableKey.afterRefinement.string)
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
        Image(systemName: "info.circle")
          .foregroundStyle(.secondary)
          .help(LocalizableKey.refinementChangeLegend.string)
          .accessibilityLabel(LocalizableKey.refinementChangeLegend.string)
        Spacer()
        Button {
          Haptics.tap()
          withAnimation(reduceMotion ? nil : .spring(duration: 0.22, bounce: 0.05)) {
            showingBefore.toggle()
            replayToken += 1
          }
        } label: {
          Image(systemName: showingBefore ? "sparkles" : "clock.arrow.circlepath")
            .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
          Text(showingBefore ? LocalizableKey.afterRefinement.string : LocalizableKey.beforeRefinement.string)
            .contentTransition(.numericText())
        }
        .help(showingBefore ? LocalizableKey.showAfterRefinement.string : LocalizableKey.showBeforeRefinement.string)
        .disabled(output.isEmpty || status.isRunning)
        IconButton("square.and.pencil", help: LocalizableKey.edit.string) { showEditor = true }
          .disabled(output.isEmpty || status.isRunning)
      }
      AnimatedRefinementText(
        text: showsOriginal ? original : output, original: original,
        refined: output, animateChanges: status.isRunning, replayToken: replayToken
      )
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
        .overlay(alignment: .bottom) {
          if status.isRunning {
            VStack(spacing: 8) {
              if case .running(let message) = status { ProgressView(message) }
              if let assessment, let score = assessment.finalAIScore {
                Text(LocalizableKey.aiScoreValue.format(score.formatted(.number.precision(.fractionLength(1)))))
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
      HStack {
        if !showsOriginal, let assessment, assessment.aiScoredText == output, assessment.finalAIScore != nil {
          AIScoreButton(item: assessment)
        }
        Spacer()
        Group {
          if let limit, !showsOriginal {
            Text("\(output.count)/\(limit)")
              .foregroundStyle(output.count > limit ? .red : .secondary)
          } else {
            Text(LocalizableKey.characterCount.format((showsOriginal ? original : output).count))
              .foregroundStyle(.secondary)
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
      RewriteOutputSheet(text: $output, limit: limit)
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

