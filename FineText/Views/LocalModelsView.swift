import SwiftUI

// MARK: - Settings tab

/// Downloaded MLX chat models that rewrite and translate on this Mac, plus a Hugging Face browser.
struct LocalModelsSettingsView: View {
  @Environment(LocalModelStore.self) private var store
  @State private var selection: String?
  @State private var browsing = false
  @State private var pendingRemove: LocalModel?
  @State private var toast: Toast?

  var body: some View {
    VStack(spacing: 0) {
      if store.models.isEmpty && store.downloads.isEmpty {
        ContentUnavailableView {
          Label(LocalizableKey.noLocalModels.string, systemImage: "cpu")
        } description: {
          Text(LocalizableKey.downloadLocalExplanation.string)
        } actions: {
          Button(LocalizableKey.browseHuggingFace.string) { browsing = true }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(selection: $selection) {
          let pending = store.downloads.keys.filter { !store.isInstalled($0) }.sorted()
          if !pending.isEmpty {
            Section(LocalizableKey.downloadingSection.string) {
              ForEach(pending, id: \.self) { id in
                DownloadingModelRow(id: id)
              }
            }
          }
          Section(LocalizableKey.downloaded.string) {
            ForEach(store.models) { model in
              LocalModelRow(model: model)
                .tag(model.id)
                .contextMenu {
                  Button(LocalizableKey.viewOnHuggingFace.string) { NSWorkspace.shared.open(HubCatalog.pageURL(model.id)) }
                  Divider()
                  Button(LocalizableKey.removeMenu.string, role: .destructive) { pendingRemove = model }
                }
            }
          }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
      }
      Divider()
      HStack(spacing: 6) {
        Button { browsing = true } label: { Image(systemName: "plus") }
          .help(LocalizableKey.browseHuggingFaceHelp.string)
        Button {
          pendingRemove = selection.flatMap(store.model)
        } label: { Image(systemName: "minus") }
          .disabled(selection.flatMap(store.model) == nil)
          .help(LocalizableKey.removeModelHelp.string)
        Spacer()
        Text(LocalizableKey.pickLocalModels.format(Provider.localName))
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(LocalizableKey.browseHuggingFace.string) { browsing = true }
      }
      .buttonStyle(.borderless)
      .padding(8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottom) { SettingsToast(toast: toast) }
    .sheet(isPresented: $browsing) { HubBrowserSheet() }
    .confirmationDialog(
      LocalizableKey.removeNamedModel.format(pendingRemove?.name ?? LocalizableKey.model.string),
      isPresented: Binding(get: { pendingRemove != nil }, set: { if !$0 { pendingRemove = nil } })
    ) {
      Button(LocalizableKey.remove.string, role: .destructive) {
        if let model = pendingRemove { remove(model) }
        pendingRemove = nil
      }
    } message: {
      Text(LocalizableKey.removeLocalExplanation.string)
    }
  }

  private func remove(_ model: LocalModel) {
    Task {
      do {
        try await store.remove(model.id)
        if selection == model.id { selection = nil }
        show(Toast(message: LocalizableKey.removedModel.format(model.name), symbol: "trash"))
        Haptics.success()
      } catch {
        show(Toast(message: error.localizedDescription, symbol: "xmark.octagon", isError: true))
        Haptics.failure()
      }
    }
  }

  private func show(_ value: Toast) {
    toast = value
    Task {
      try? await Task.sleep(for: .seconds(1.8))
      if toast?.id == value.id { toast = nil }
    }
  }
}

struct LocalModelRow: View {
  let model: LocalModel

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "cpu").foregroundStyle(.tint).frame(width: 20)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.name).font(.headline).lineLimit(1)
        Text(model.author).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      if let size = model.sizeBytes {
        Text(size.formatted(.byteCount(style: .file))).font(.caption).foregroundStyle(.secondary).monospacedDigit()
      }
    }
    .padding(.vertical, 4)
  }
}

struct DownloadingModelRow: View {
  @Environment(LocalModelStore.self) private var store
  let id: String

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(id.split(separator: "/").last.map(String.init) ?? id).font(.headline).lineLimit(1)
        Spacer()
        Button(LocalizableKey.cancel.string, role: .destructive) {
          store.cancel(id)
          Haptics.tap()
        }
        .buttonStyle(.borderless)
      }
      DownloadProgressView(progress: store.downloads[id])
    }
    .padding(.vertical, 4)
  }
}

struct DownloadProgressView: View {
  let progress: DownloadProgress?

  var body: some View {
    let progress = progress ?? DownloadProgress()
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Text(progress.fraction == nil ? LocalizableKey.preparingDownload.string : LocalizableKey.downloading.string)
        Spacer()
        if let fraction = progress.fraction {
          Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
        }
      }
      if let fraction = progress.fraction {
        ProgressView(value: fraction)
      } else {
        ProgressView().progressViewStyle(.linear)
      }
      HStack {
        Text(LocalizableKey.downloadBytes.format(
          progress.completedBytes.formatted(.byteCount(style: .file)),
          progress.totalBytes > 1 ? progress.totalBytes.formatted(.byteCount(style: .file)) : LocalizableKey.unknown.string
        ))
        Spacer()
        Text(progress.bytesPerSecond.map { LocalizableKey.downloadSpeed.format(Int64($0).formatted(.byteCount(style: .file))) } ?? "—")
      }
      .font(.caption).foregroundStyle(.secondary).monospacedDigit()
    }
  }
}

extension View {
  func modelDownloadOverlay() -> some View {
    modifier(ModelDownloadOverlay())
  }
}

/// Attached to each presentation surface so downloads remain visible above native sheets.
private struct ModelDownloadOverlay: ViewModifier {
  @Environment(LocalModelStore.self) private var store
  @Environment(TranslationModelManager.self) private var gemma

  private var isDownloading: Bool { !store.downloads.isEmpty || gemma.isDownloading }
  private var cardHeight: CGFloat {
    min(340, CGFloat(96 + 156 * (store.downloads.count + (gemma.isDownloading ? 1 : 0))))
  }

  func body(content: Content) -> some View {
    content
      .disabled(isDownloading || gemma.isRemoving)
      .overlay {
        if gemma.isRemoving {
          ZStack {
            Color.black.opacity(0.18).ignoresSafeArea()
            ProgressView(LocalizableKey.removingTranslationModel.string)
              .padding(24)
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
          }
        }
      }
      .overlay {
        if isDownloading {
          GeometryReader { geometry in
            ZStack {
              Color.black.opacity(0.18).ignoresSafeArea()
              ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                  Text(LocalizableKey.downloadingSection.string).font(.title3.bold())
                  ForEach(store.downloads.keys.sorted(), id: \.self) { id in
                    downloadCard(id: id, progress: store.downloads[id]) { store.cancel(id) }
                  }
                  if case .downloading(let progress) = gemma.state {
                    downloadCard(id: gemma.downloadingModel?.id ?? TranslationModel.default.id, progress: progress) {
                      gemma.cancel()
                    }
                  }
                }
                .padding(20)
              }
              .scrollBounceBehavior(.basedOnSize)
              .frame(width: min(440, max(0, geometry.size.width - 32)), height: min(cardHeight, max(0, geometry.size.height - 32)))
              .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
              .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.separator) }
              .shadow(radius: 20, y: 8)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .environment(\.isEnabled, true)
          }
        }
      }
  }

  private func downloadCard(id: String, progress: DownloadProgress?, cancel: @escaping () -> Void) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(id.split(separator: "/").last.map(String.init) ?? id)
        .font(.headline).textSelection(.enabled)
      DownloadProgressView(progress: progress)
      HStack {
        Spacer()
        Button(LocalizableKey.cancelDownload.string, role: .destructive) {
          Haptics.tap()
          cancel()
        }
        .buttonStyle(.bordered)
      }
    }
  }
}

struct SettingsToast: View {
  let toast: Toast?

  var body: some View {
    Group {
      if let toast {
        Label(toast.message, systemImage: toast.symbol)
          .font(.callout.weight(.medium))
          .foregroundStyle(toast.isError ? .red : .primary)
          .lineLimit(2)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.regularMaterial, in: Capsule())
          .shadow(radius: 6, y: 2)
          .padding(.bottom, 52)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .id(toast.id)
      }
    }
    .animation(.spring(duration: 0.3), value: toast)
  }
}

// MARK: - Hugging Face browser

/// Searches MLX text-generation models on Hugging Face; picking one pushes its download page.
struct HubBrowserSheet: View {
  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var scope = HubCatalog.Scope.community
  @State private var sort = HubCatalog.Sort.downloads
  @State private var results: [HubModelSummary] = []
  @State private var loading = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        HStack(spacing: 8) {
          HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(LocalizableKey.searchModels.string, text: $query)
              .textFieldStyle(.plain)
            if !query.isEmpty {
              Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless).foregroundStyle(.secondary)
            }
          }
          .padding(6)
          .background(.background.secondary, in: RoundedRectangle(cornerRadius: 7))
          Picker(LocalizableKey.source.string, selection: $scope) {
            ForEach(HubCatalog.Scope.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
          Picker(LocalizableKey.sort.string, selection: $sort) {
            ForEach(HubCatalog.Sort.allCases) { Text($0.title).tag($0) }
          }
          .labelsHidden()
          .fixedSize()
        }
        .padding(10)
        Divider()
        content
        Divider()
        HStack {
          Text(LocalizableKey.mlxModelsHint.string)
            .font(.caption).foregroundStyle(.secondary)
          Spacer()
          Button(LocalizableKey.done.string) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        .padding(10)
      }
      .navigationTitle("Hugging Face")
      .navigationDestination(for: HubModelSummary.self) { HubModelDetailView(summary: $0) }
    }
    .frame(width: 560)
    .frame(minHeight: 440, maxHeight: .infinity)
    .modelDownloadOverlay()
    .task(id: "\(query)|\(scope.rawValue)|\(sort.rawValue)") { await search() }
  }

  @ViewBuilder private var content: some View {
    if let error, results.isEmpty {
      ContentUnavailableView {
        Label(LocalizableKey.couldNotLoadModels.string, systemImage: "wifi.exclamationmark")
      } description: {
        Text(error)
      } actions: {
        Button(LocalizableKey.tryAgain.string) { Task { await search(debounce: false) } }
      }
      .frame(maxHeight: .infinity)
    } else if results.isEmpty {
      if loading {
        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView.search(text: query).frame(maxHeight: .infinity)
      }
    } else {
      List(results) { model in
        NavigationLink(value: model) { HubModelRow(model: model) }
      }
      .listStyle(.inset(alternatesRowBackgrounds: true))
      .overlay(alignment: .top) {
        if loading { ProgressView().controlSize(.small).padding(6) }
      }
    }
  }

  private func search(debounce: Bool = true) async {
    if debounce { try? await Task.sleep(for: .milliseconds(350)) }
    guard !Task.isCancelled else { return }
    loading = true
    defer { loading = false }
    do {
      let found = try await HubCatalog.search(query, scope: scope, sort: sort)
      guard !Task.isCancelled else { return }
      results = found
      error = nil
    } catch is CancellationError {
    } catch let failure as URLError where failure.code == .cancelled {
    } catch {
      self.error = error.localizedDescription
      results = []
    }
  }
}

struct HubModelRow: View {
  @Environment(LocalModelStore.self) private var store
  let model: HubModelSummary

  var body: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text(model.name).font(.headline).lineLimit(1)
        HStack(spacing: 10) {
          Text(model.author)
          Label(model.downloads.formatted(.number.notation(.compactName)), systemImage: "arrow.down.circle")
          Label(model.likes.formatted(.number.notation(.compactName)), systemImage: "heart")
          if let params = model.parameterLabel { Text(params) }
        }
        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      if store.isInstalled(model.id) {
        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help(LocalizableKey.downloaded.string)
      } else if store.isDownloading(model.id) {
        ProgressView(value: store.downloads[model.id]?.fraction ?? 0).progressViewStyle(.circular).controlSize(.small)
      } else if model.gated {
        Image(systemName: "lock.fill").foregroundStyle(.secondary).help(LocalizableKey.licenseRequired.string)
      }
    }
    .padding(.vertical, 3)
  }
}

struct HubModelDetailView: View {
  @Environment(LocalModelStore.self) private var store
  let summary: HubModelSummary
  @State private var detail: HubModelDetail?
  @State private var detailError: String?

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          HStack(spacing: 12) {
            Image(systemName: "cpu")
              .font(.system(size: 26))
              .foregroundStyle(.tint)
              .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
              Text(summary.name).font(.headline).lineLimit(2)
              Text(summary.id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
          }
          .padding(.vertical, 4)
        }

        Section(LocalizableKey.details.string) {
          LabeledContent(LocalizableKey.downloadSize.string) {
            if let detail {
              Text(detail.sizeBytes.formatted(.byteCount(style: .file))).monospacedDigit()
            } else if detailError != nil {
              Text(LocalizableKey.unknown.string).foregroundStyle(.secondary)
            } else {
              ProgressView().controlSize(.small)
            }
          }
          if let params = summary.parameterLabel { LabeledContent(LocalizableKey.parameters.string, value: params) }
          if let type = detail?.modelType { LabeledContent(LocalizableKey.architecture.string, value: type) }
          LabeledContent(LocalizableKey.downloads.string, value: summary.downloads.formatted())
          LabeledContent(LocalizableKey.likes.string, value: summary.likes.formatted())
          if let date = summary.lastModified {
            LabeledContent(LocalizableKey.updated.string, value: date.formatted(date: .abbreviated, time: .omitted))
          }
          Link(LocalizableKey.viewOnHuggingFace.string, destination: HubCatalog.pageURL(summary.id))
        }

        if let warning {
          Section {
            Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
          }
        }

        Section(LocalizableKey.downloadAction.string) { downloadContent }
      }
      .formStyle(.grouped)
    }
    .navigationTitle(summary.name)
    .task { await loadDetail() }
  }

  private var warning: String? {
    if summary.gated { return LocalizableKey.gatedModelWarning.string }
    if let detail, !detail.hasChatTemplate { return LocalizableKey.noChatTemplateWarning.string }
    if let detail, detail.sizeBytes > 0, detail.sizeBytes > physicalMemory * 3 / 4 {
      return LocalizableKey.modelMemoryWarning.format(physicalMemory.formatted(.byteCount(style: .memory)))
    }
    return nil
  }

  private var physicalMemory: Int64 { Int64(ProcessInfo.processInfo.physicalMemory) }

  @ViewBuilder private var downloadContent: some View {
    if store.isInstalled(summary.id) {
      Label(LocalizableKey.downloadedPickLocal.format(Provider.localName), systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
    } else if store.isDownloading(summary.id) {
      DownloadProgressView(progress: store.downloads[summary.id])
      HStack {
        Spacer()
        Button(LocalizableKey.cancelDownload.string, role: .destructive) {
          store.cancel(summary.id)
          Haptics.tap()
        }
      }
    } else {
      if let failure = store.failures[summary.id] {
        Label(failure, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
      }
      HStack {
        Text(LocalizableKey.localStorageExplanation.string)
          .font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button(store.failures[summary.id] == nil ? LocalizableKey.downloadAction.string : LocalizableKey.retry.string) {
          Haptics.tap()
          store.download(summary.id, sizeBytes: detail?.sizeBytes)
        }
        .buttonStyle(.borderedProminent)
      }
    }
  }

  private func loadDetail() async {
    do {
      detail = try await HubCatalog.detail(summary.id)
    } catch {
      detailError = error.localizedDescription
    }
  }
}
