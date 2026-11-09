import SwiftUI

/// Engine selection and model lifecycle live on their own full-height settings surface.
struct AIDetectorSettingsSheet: View {
  @Environment(AIDetectorManager.self) private var manager
  @Environment(\.dismiss) private var dismiss
  @AppStorage(DefaultsKey.detectorEngine) private var engine = AIDetectorEngine.disabled
  @State private var confirmRemoval = false
  @State private var showDownload = false
  @State private var toast: Toast?

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section(LocalizableKey.aiDetector.string) {
          Picker(LocalizableKey.detectorEngine.string, selection: $engine) {
            ForEach(AIDetectorEngine.allCases) { Text($0.name).tag($0) }
          }
          .disabled(manager.isBusy)
          .onChange(of: engine) { manager.refresh(); Haptics.tap() }
        }
        if engine != .disabled {
          Section {
            LabeledContent(LocalizableKey.model.string, value: engine.name)
            LabeledContent(LocalizableKey.downloadSize.string, value: "≈ 1.75 GB")
            LabeledContent(LocalizableKey.license.string, value: engine.license)
            Link(LocalizableKey.viewOnHuggingFace.string, destination: HubCatalog.pageURL(engine.repository))
            LabeledContent(LocalizableKey.detectorRuntime.string) {
              Text(manager.runtimeReady ? LocalizableKey.ready.string : LocalizableKey.detectorRuntimeNotInstalled.string)
                .foregroundStyle(manager.runtimeReady ? .green : .secondary)
            }
            LabeledContent(LocalizableKey.status.string) { status }
            HStack {
              Spacer()
              if manager.state == .installed {
                Button(LocalizableKey.removeModel.string, role: .destructive) { confirmRemoval = true }
              } else {
                Button(LocalizableKey.downloadAction.string) { showDownload = true }
                  .buttonStyle(.borderedProminent)
                  .disabled(manager.isBusy)
              }
            }
          } footer: {
            Text(LocalizableKey.detectorDownloadHelp.string).font(.caption).foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Section {
          Text(LocalizableKey.detectorScoreHelp.string).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button(LocalizableKey.done.string) { dismiss() }.keyboardShortcut(.defaultAction)
      }.padding(12)
    }
    .frame(width: 500, height: 460)
    .frame(maxHeight: .infinity)
    .onAppear { manager.refresh() }
    .sheet(isPresented: $showDownload) { AIDetectorDownloadSheet(engine: engine) }
    .confirmationDialog(LocalizableKey.removeModel.string, isPresented: $confirmRemoval) {
      Button(LocalizableKey.removeModel.string, role: .destructive) { manager.remove() }
    } message: { Text(LocalizableKey.detectorRemoveHelp.string) }
    .overlay {
      if manager.state == .removing {
        ZStack { Rectangle().fill(.regularMaterial); ProgressView(LocalizableKey.removingDetector.string) }
      }
    }
    .overlay(alignment: .bottom) { SettingsToast(toast: toast) }
    .onChange(of: manager.state) { old, new in
      guard old == .removing else { return }
      if new == .notInstalled {
        toast = Toast(message: LocalizableKey.removedModel.format(engine.name), symbol: "trash")
      } else if case .failed(let message) = new {
        toast = Toast(message: message, symbol: "exclamationmark.triangle", isError: true)
      }
    }
    .task(id: toast?.id) {
      guard toast != nil else { return }
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { toast = nil }
    }
  }

  @ViewBuilder private var status: some View {
    switch manager.state {
    case .checking: ProgressView().controlSize(.small)
    case .installed: Label(LocalizableKey.ready.string, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    case .notInstalled: Text(LocalizableKey.notDownloaded.string).foregroundStyle(.secondary)
    case .downloading: Text(manager.phase.title)
    case .removing: Text(LocalizableKey.removingDetector.string)
    case .failed(let message):
      Button(LocalizableKey.detectorShowError.string) { showDownload = true }
        .help(message)
    }
  }
}

private struct AIDetectorDownloadSheet: View {
  @Environment(AIDetectorManager.self) private var manager
  @Environment(\.dismiss) private var dismiss
  let engine: AIDetectorEngine

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        Image(systemName: "cpu").font(.title).foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 3) {
          Text(engine.name).font(.headline)
          Text("≈ 1.75 GB · \(engine.license)").font(.caption).foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
      }
      .padding(20)
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          runtimeStatus
          Text(LocalizableKey.detectorDownloadHelp.string)
            .font(.callout).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .overlay {
        switch manager.state {
        case .downloading(let progress):
          statusOverlay {
            runtimeStatus
            Divider()
            Text(manager.isCancelling ? LocalizableKey.detectorCancelling.string : manager.phase.title)
              .font(.headline).fixedSize(horizontal: false, vertical: true)
            if manager.phase == .downloadingModel {
              DownloadProgressView(progress: progress)
            } else {
              ProgressView().progressViewStyle(.linear)
              if !manager.runtimeOutput.isEmpty {
                Text(manager.runtimeOutput)
                  .font(.caption.monospaced()).foregroundStyle(.secondary)
                  .lineLimit(4).textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
            }
          }
        case .failed(let message):
          statusOverlay {
            runtimeStatus
            Divider()
            Label(message, systemImage: "exclamationmark.triangle")
              .foregroundStyle(.red).textSelection(.enabled)
              .fixedSize(horizontal: false, vertical: true)
          }
        case .installed:
          statusOverlay {
            runtimeStatus
            Divider()
            Label(LocalizableKey.detectorModelReady.string, systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          }
        default: EmptyView()
        }
      }
      Divider()
      HStack {
        if manager.isBusy {
          Button(LocalizableKey.cancelDownload.string, role: .destructive) {
            manager.cancel()
            Haptics.tap()
          }
          .disabled(manager.isCancelling)
          .keyboardShortcut(.cancelAction)
        } else {
          Spacer()
          Button(LocalizableKey.done.string) { dismiss() }.keyboardShortcut(.cancelAction)
          if manager.state != .installed {
            Button(LocalizableKey.downloadAction.string) { manager.download(); Haptics.tap() }
              .buttonStyle(.borderedProminent)
              .keyboardShortcut(.defaultAction)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(12)
    }
    .frame(width: 440, height: 380)
    .frame(maxHeight: .infinity)
    .interactiveDismissDisabled(manager.isBusy)
  }

  private var runtimeStatus: some View {
    LabeledContent(LocalizableKey.detectorRuntime.string) {
      Label(manager.runtimeReady ? LocalizableKey.ready.string : (manager.isBusy ? LocalizableKey.detectorRuntimePreparing.string : LocalizableKey.detectorRuntimeNotInstalled.string),
            systemImage: manager.runtimeReady ? "checkmark.circle.fill" : "circle.dashed")
        .foregroundStyle(manager.runtimeReady ? .green : .secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private func statusOverlay<Content: View>(@ViewBuilder content: () -> Content) -> some View {
    ZStack(alignment: .topLeading) {
      Rectangle().fill(.regularMaterial)
      ScrollView {
        VStack(alignment: .leading, spacing: 16, content: content)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(20)
      }.scrollBounceBehavior(.basedOnSize)
    }
  }
}
