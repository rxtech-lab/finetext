import SwiftUI

struct AIScoreButton: View {
  let item: RewriteItem
  @State private var showDetails = false

  var body: some View {
    Button {
      showDetails = true
      Haptics.tap()
    } label: {
      Label(LocalizableKey.aiScoreValue.format(number(item.finalAIScore)), systemImage: "gauge.with.dots.needle.50percent")
    }
    .buttonStyle(.borderless)
    .sheet(isPresented: $showDetails) {
      VStack(spacing: 0) {
        Form {
          Section {
            LabeledContent(LocalizableKey.detectorEngine.string, value: AIDetectorEngine(rawValue: item.detectorEngineRaw ?? "")?.name ?? "—")
            LabeledContent(LocalizableKey.initialRewriteScore.string, value: "\(number(item.initialAIScore))/100")
            LabeledContent(LocalizableKey.finalAIScore.string, value: "\(number(item.finalAIScore))/100")
            if let target = item.targetAIScore {
              LabeledContent(LocalizableKey.targetAIScore.string, value: "\(number(target))/100")
              Label((item.finalAIScore ?? 100) <= target ? LocalizableKey.aiTargetReached.string : LocalizableKey.aiTargetNotReached.string,
                    systemImage: (item.finalAIScore ?? 100) <= target ? "checkmark.circle" : "info.circle")
            }
            LabeledContent(LocalizableKey.completedRounds.string, value: "\(item.humanizationRounds)")
          } header: {
            Text(LocalizableKey.aiDetector.string)
          } footer: {
            Text(LocalizableKey.detectorScoreHelp.string)
          }
        }.formStyle(.grouped)
        Divider()
        HStack {
          Spacer()
          Button(LocalizableKey.done.string) { showDetails = false }.keyboardShortcut(.defaultAction)
        }.padding(12)
      }
      .frame(width: 440, height: 400)
      .frame(maxHeight: .infinity)
    }
  }

  private func number(_ value: Double?) -> String {
    value?.formatted(.number.precision(.fractionLength(1))) ?? "—"
  }
}
