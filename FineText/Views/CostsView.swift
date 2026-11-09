import SwiftUI

struct CostLabel: View {
  let summary: CostSummary
  var body: some View {
    Text(summary.label).monospacedDigit().font(.caption2).foregroundStyle(.secondary)
      .help(LocalizableKey.costTrackingHint.string)
  }
}

struct CostsSheet: View {
  @Environment(Workspace.self) private var workspace
  @Environment(\.dismiss) private var dismiss
  @State private var allTime = false

  private var charges: [GenerationCharge] {
    workspace.charges.filter { allTime || $0.sessionID == workspace.session.id }
      .sorted { $0.createdAt > $1.createdAt }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(LocalizableKey.usageCosts.string).font(.headline)
        Spacer()
        Button(LocalizableKey.done.string) { dismiss() }.keyboardShortcut(.cancelAction)
      }
      Picker(LocalizableKey.usageCosts.string, selection: $allTime) {
        Text(LocalizableKey.currentSession.string).tag(false)
        Text(LocalizableKey.allTime.string).tag(true)
      }.pickerStyle(.segmented)
      LabeledContent(LocalizableKey.recordedTotal.string) {
        Text(CostSummary(charges: charges).totalLabel).monospacedDigit().font(.headline)
      }
      Text(LocalizableKey.costTrackingHint.string).font(.caption).foregroundStyle(.secondary)
      let unknown = CostSummary(charges: charges).unknownCount
      if unknown > 0 {
        Text(LocalizableKey.unpricedRequests.format(unknown)).font(.caption).foregroundStyle(.orange)
      }
      List(charges) { charge in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(kindTitle(charge.kind)).font(.subheadline.weight(.semibold))
            Spacer()
            CostLabel(summary: CostSummary(charges: [charge]))
          }
          Text(charge.modelID).font(.caption).foregroundStyle(.secondary).lineLimit(1)
          Text(charge.createdAt, format: .dateTime.month().day().hour().minute())
            .font(.caption2).foregroundStyle(.tertiary)
        }
      }
      .overlay { if charges.isEmpty { Text(LocalizableKey.noRecordedCosts.string).foregroundStyle(.secondary) } }
    }
    .padding(16)
    .frame(width: 408, height: 560, alignment: .top)
    .frame(maxHeight: .infinity)
  }

  private func kindTitle(_ kind: String) -> String {
    switch kind {
    case "rewrite": LocalizableKey.rewrite.string
    case "translation": LocalizableKey.translate.string
    case "image": LocalizableKey.image.string
    default: LocalizableKey.historyTitle.string
    }
  }
}
