import SwiftUI

/// Plan usage is shared across Flowcy requests, rather than a per-request dollar cost.
struct FlowcyUsageLabel: View {
  @Environment(ProviderStore.self) private var providers

  var body: some View {
    let flowcy = providers.flowcy
    let meters = flowcy.usage.compactMap { meter in
      meter.fraction.map { (meter: meter, percentage: $0.formatted(.percent.precision(.fractionLength(0)))) }
    }
    Group {
      if meters.isEmpty {
        Text(flowcy.loadingUsage ? LocalizableKey.flowcyUsageLoading.string
          : (flowcy.usageError ?? LocalizableKey.flowcyUsageEmpty.string))
      } else {
        Text(meters.map { entry in
          let meter = entry.meter
          let window = ["agent_cost_5h": "5h", "agent_cost_7d": "7d", "agent_cost_30d": "30d"][meter.key]
            ?? FlowcyUsageView.title(meter.key)
          return "\(window) \(entry.percentage)"
        }.joined(separator: " · "))
        .accessibilityLabel(meters.map { entry in
          let meter = entry.meter
          return "\(FlowcyUsageView.title(meter.key)) \(entry.percentage)"
        }.joined(separator: ", "))
      }
    }
    .monospacedDigit().font(.caption2).foregroundStyle(.secondary)
    .help(LocalizableKey.flowcyUsageHint.string)
    .task { await flowcy.loadUsage() }
  }
}

struct GenerationUsageLabel: View {
  @Environment(ProviderStore.self) private var providers
  let model: ModelRef
  let summary: CostSummary

  var body: some View {
    if providers.isFlowcy(model) {
      FlowcyUsageLabel()
    } else {
      CostLabel(summary: summary)
    }
  }
}

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
      if workspace.providers.flowcy.isSignedIn {
        GroupBox(LocalizableKey.flowcyUsage.string) {
          VStack(alignment: .leading, spacing: 8) { FlowcyUsageView(flowcy: workspace.providers.flowcy) }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await workspace.providers.flowcy.loadUsage() }
      }
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
