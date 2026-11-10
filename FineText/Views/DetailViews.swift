import SwiftData
import SwiftUI

/// Header used by every pushed page inside the menu bar window.
struct PageHeader<Trailing: View>: View {
  @Environment(Workspace.self) private var workspace
  let title: String
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(spacing: 8) {
      Button {
        workspace.route = nil
      } label: {
        Label(LocalizableKey.back.string, systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 20, height: 20)
      }
      .buttonStyle(.borderless)
      .keyboardShortcut(.escape, modifiers: [])
      Text(title).font(.headline).lineLimit(1)
      Spacer()
      trailing
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}

struct OutputEditor: View {
  @Binding var text: String
  var limit: Int?

  var body: some View {
    VStack(alignment: .trailing, spacing: 4) {
      TextEditor(text: $text)
        .font(.body)
        .scrollContentBackground(.hidden)
        .padding(6)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
      if let limit {
        Text("\(text.count)/\(limit)").font(.caption2).foregroundStyle(text.count > limit ? .red : .secondary)
      } else {
        Text(LocalizableKey.characterCount.format(text.count)).font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

struct DeleteButton: View {
  let title: String
  let action: () -> Void
  @State private var confirm = false

  var body: some View {
    IconButton("trash", help: LocalizableKey.remove.string) { confirm = true }
      .confirmationDialog(title, isPresented: $confirm) {
        Button(LocalizableKey.remove.string, role: .destructive, action: action)
      }
  }
}

struct ModelPickerMenu: View {
  @Environment(ProviderStore.self) private var providers
  @Environment(Preferences.self) private var preferences
  @Environment(\.openSettings) private var openSettings
  let kind: ModelKind
  let purpose: Preferences.Purpose
  let current: ModelRef
  let onPick: (ModelRef) -> Void

  var body: some View {
    LabeledContent(LocalizableKey.model.string) {
      LazyPullDownMenu(title: providers.displayName(current)) {
        ModelMenuEntries(providers: providers, preferences: preferences, openSettings: openSettings)
          .entries(kind: kind, purpose: purpose, onPick: onPick)
      }
      .fixedSize()
    }
  }
}

// MARK: - Rewrite

struct RewriteDetailView: View {
  @Environment(Workspace.self) private var workspace
  @Environment(Preferences.self) private var preferences
  let id: UUID

  var body: some View {
    if let item = workspace.session.rewrites.first(where: { $0.id == id }) {
      @Bindable var item = item
      let status = workspace.status(id)
      VStack(spacing: 0) {
        PageHeader(title: LocalizableKey.rewriteTitle.format(item.platformTitle)) {
          DeleteButton(title: LocalizableKey.removeThisRewrite.string) { workspace.remove(item, id: id) }
        }
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          Picker(LocalizableKey.tone.string, selection: $item.tone) {
            ForEach(Tone.allCases) { Text($0.title).tag($0) }
          }
          .onChange(of: item.tone) { _, tone in preferences.setTone(tone, for: item) }
          ModelPickerMenu(kind: .text, purpose: .rewrite, current: item.model) {
            item.model = $0
            preferences.remember($0, for: .rewrite)
          }
          LabeledContent(LocalizableKey.recordedCost.string) { CostLabel(summary: workspace.cost(for: item.id)) }
          StatusLine(status: status)
          if let note = item.note {
            Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
          }
          RefinementResultView(
            original: item.refinementSource ?? workspace.originalText,
            output: $item.output, status: status, limit: item.characterLimit, assessment: item,
            preview: workspace.refinementPreviews[id], fields: item.fields
          )
        }
        .padding(14)
        Divider()
        ActionBar(status: status, hasOutput: !item.output.isEmpty, runTitle: item.output.isEmpty ? LocalizableKey.rewrite.string : LocalizableKey.regenerate.string,
                  onRun: { workspace.run(item) }, onStop: { workspace.stop(id) }, onCopy: { workspace.copy(item.plainOutput) })
      }
    } else {
      MissingItemView()
    }
  }
}

// MARK: - Translation

struct TranslationDetailView: View {
  @Environment(Workspace.self) private var workspace
  @Environment(Preferences.self) private var preferences
  let id: UUID

  var body: some View {
    if let item = workspace.session.translations.first(where: { $0.id == id }) {
      @Bindable var item = item
      let status = workspace.status(id)
      VStack(spacing: 0) {
        PageHeader(title: LocalizableKey.translationTitle.format(item.language.localizedName)) {
          DeleteButton(title: LocalizableKey.removeThisTranslation.string) { workspace.remove(item, id: id) }
        }
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          Picker(LocalizableKey.language.string, selection: $item.language) {
            ForEach(Language.all) { Text($0.localizedName).tag($0) }
          }
          Picker(LocalizableKey.from.string, selection: $item.sourceRewriteID) {
            Text(LocalizableKey.original.string).tag(UUID?.none)
            ForEach(workspace.session.sortedRewrites) { rewrite in
              Text("\(rewrite.platformTitle) · \(rewrite.tone.title)").tag(UUID?.some(rewrite.id))
            }
          }
          ModelPickerMenu(kind: .text, purpose: .translate, current: item.model) {
            item.model = $0
            preferences.remember($0, for: .translate)
          }
          LabeledContent(LocalizableKey.recordedCost.string) { CostLabel(summary: workspace.cost(for: item.id)) }
          StatusLine(status: status)
          OutputEditor(text: $item.output)
        }
        .padding(14)
        Divider()
        ActionBar(status: status, hasOutput: !item.output.isEmpty, runTitle: item.output.isEmpty ? LocalizableKey.translate.string : LocalizableKey.retranslate.string,
                  onRun: { workspace.run(item) }, onStop: { workspace.stop(id) }, onCopy: { workspace.copy(item.output) })
      }
    } else {
      MissingItemView()
    }
  }
}

// MARK: - Image

struct ImageDetailView: View {
  @Environment(Workspace.self) private var workspace
  @Environment(Preferences.self) private var preferences
  let id: UUID
  @State private var showRefine = false

  var body: some View {
    if let item = workspace.session.images.first(where: { $0.id == id }) {
      @Bindable var item = item
      let status = workspace.status(id)
      VStack(spacing: 0) {
        PageHeader(title: LocalizableKey.image.string) {
          DeleteButton(title: LocalizableKey.removeThisImage.string) { workspace.remove(item, id: id) }
        }
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          ModelPickerMenu(kind: .image, purpose: .image, current: item.model) {
            item.model = $0
            preferences.remember($0, for: .image)
          }
          Picker(LocalizableKey.size.string, selection: $item.size) {
            ForEach(ImageSize.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          VStack(alignment: .leading, spacing: 2) {
            Toggle(LocalizableKey.transparentBackground.string, isOn: $item.transparentBackground)
              .toggleStyle(.switch)
              .controlSize(.small)
              .onChange(of: item.transparentBackground) { Haptics.tap() }
            if item.transparentBackground {
              Text(workspace.backgroundMode(for: item) == .native
                   ? LocalizableKey.transparentNativeHint.string
                   : LocalizableKey.transparentGreenScreenHint.string)
                .font(.caption).foregroundStyle(.secondary)
            }
          }
          TextField(LocalizableKey.artDirectionOptionalEGFlatIllustrationWarmColors.string, text: $item.instruction, axis: .vertical)
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
          LabeledContent(LocalizableKey.recordedCost.string) { CostLabel(summary: workspace.cost(for: item.id)) }
          StatusLine(status: status)
          ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.background.secondary)
            if let data = item.imageData, let image = NSImage(data: data) {
              Image(nsImage: image).resizable().scaledToFit()
                .background { if item.transparentBackground, BackgroundRemover.hasAlphaChannel(data) { Checkerboard() } }
                .clipShape(RoundedRectangle(cornerRadius: 8)).padding(6)
                .draggable(Image(nsImage: image))
                .overlay {
                  if status.isRunning {
                    ProgressView().controlSize(.regular)
                      .padding(14)
                      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                  }
                }
            } else if status.isRunning {
              ProgressView(LocalizableKey.generating.string)
            } else {
              Label(LocalizableKey.theImageIsBasedOnYourOriginalPost.string, systemImage: "photo")
                .foregroundStyle(.secondary).font(.callout)
            }
          }
          .frame(maxHeight: .infinity)
        }
        .padding(14)
        Divider()
        HStack {
          if item.imageData != nil {
            Menu {
              Button(LocalizableKey.saveToPicturesFinetext.string) { workspace.saveImageToPictures(item) }
              Button(LocalizableKey.saveAs.string) { workspace.saveImageAs(item) }
            } label: {
              Label(LocalizableKey.save.string, systemImage: "square.and.arrow.down")
            }
            .fixedSize()
            Button { workspace.copyImage(item) } label: { Label(LocalizableKey.copy.string, systemImage: "doc.on.doc") }
            if item.canUndoRefinement, !status.isRunning {
              IconButton("arrow.uturn.backward", help: LocalizableKey.undoRefinement.string) { workspace.undoRefinement(item) }
            }
          }
          Spacer()
          if status.isRunning {
            Button(LocalizableKey.stop.string, role: .cancel) { workspace.stop(id) }
          } else {
            if item.imageData != nil {
              Button { showRefine = true } label: { Label(LocalizableKey.refine.string, systemImage: "wand.and.stars") }
                .keyboardShortcut("r", modifiers: .command)
            }
            Button { workspace.run(item) } label: {
              Label(item.imageData == nil ? LocalizableKey.generate.string : LocalizableKey.regenerate.string, systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }
      .sheet(isPresented: $showRefine) {
        RefineImageSheet(item: item) { instruction in workspace.refine(item, instruction: instruction) }
      }
    } else {
      MissingItemView()
    }
  }
}

/// Collects a follow-up instruction for editing the current image. The edit itself runs in the detail page.
struct RefineImageSheet: View {
  @Environment(\.dismiss) private var dismiss
  let item: ImageItem
  let onRefine: (String) -> Void
  @State private var instruction = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(LocalizableKey.refineImage.string).font(.headline)
      HStack(alignment: .top, spacing: 12) {
        if let data = item.imageData, let image = NSImage(data: data) {
          Image(nsImage: image).resizable().scaledToFit()
            .background { if item.transparentBackground, BackgroundRemover.hasAlphaChannel(data) { Checkerboard() } }
            .frame(width: 96, height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        Text(LocalizableKey.refineHint.string).font(.callout).foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      TextField(LocalizableKey.refinePlaceholder.string, text: $instruction, axis: .vertical)
        .lineLimit(3...6)
        .textFieldStyle(.roundedBorder)
      Spacer(minLength: 0)
      HStack {
        Spacer()
        Button(LocalizableKey.cancel.string, role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button {
          onRefine(instruction)
          dismiss()
        } label: {
          Label(LocalizableKey.refine.string, systemImage: "wand.and.stars")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(instruction.trimmed.isEmpty)
      }
    }
    .padding(16)
    .frame(width: 380, height: 300)
  }
}

/// Grey checkerboard shown behind transparent images.
struct Checkerboard: View {
  var body: some View {
    Canvas { context, size in
      let tile: CGFloat = 8
      for row in 0..<Int((size.height / tile).rounded(.up)) {
        for column in 0..<Int((size.width / tile).rounded(.up)) where (row + column).isMultiple(of: 2) {
          context.fill(Path(CGRect(x: CGFloat(column) * tile, y: CGFloat(row) * tile, width: tile, height: tile)),
                       with: .color(.gray.opacity(0.18)))
        }
      }
    }
  }
}

struct ActionBar: View {
  let status: JobStatus
  let hasOutput: Bool
  let runTitle: String
  let onRun: () -> Void
  let onStop: () -> Void
  let onCopy: () -> Void

  var body: some View {
    HStack {
      Button(action: onCopy) { Label(LocalizableKey.copy.string, systemImage: "doc.on.doc") }
        .disabled(!hasOutput)
        .keyboardShortcut("c", modifiers: [.command, .shift])
      Spacer()
      if status.isRunning {
        Button(LocalizableKey.stop.string, role: .cancel, action: onStop)
      } else {
        Button(action: onRun) { Label(runTitle, systemImage: "sparkles") }
          .buttonStyle(.borderedProminent)
          .keyboardShortcut(.return, modifiers: .command)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }
}

struct MissingItemView: View {
  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: LocalizableKey.notFound.string) { EmptyView() }
      Divider()
      ContentUnavailableView(LocalizableKey.thisItemWasRemoved.string, systemImage: "questionmark.square.dashed")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
  }
}

// MARK: - History

struct HistoryView: View {
  @Environment(Workspace.self) private var workspace
  @State private var sessions: [RefinementSession] = []
  @State private var pendingDelete: RefinementSession?
  @State private var searchText = ""
  @State private var showingSearch = false
  @State private var appliedSearchText = ""
  @State private var hasMore = true
  @State private var isLoading = false
  @State private var isSummarizing = false
  @State private var loadFailed = false
  @FocusState private var searchFocused: Bool

  private var groups: [(date: Date, sessions: [RefinementSession])] {
    let grouped = Dictionary(grouping: sessions) { Calendar.current.startOfDay(for: $0.updatedAt) }
    return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
  }

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: LocalizableKey.history.string) {
        IconButton(showingSearch ? "xmark" : "magnifyingglass", help: LocalizableKey.searchHistory.string) {
          showingSearch.toggle()
          if showingSearch { searchFocused = true } else { searchText = "" }
        }
      }
      if showingSearch {
        TextField(LocalizableKey.searchHistory.string, text: $searchText)
          .textFieldStyle(.roundedBorder)
          .focused($searchFocused)
          .padding(.horizontal, 14).padding(.bottom, 10)
      }
      Divider()
      if sessions.isEmpty && !isLoading && !loadFailed {
        ContentUnavailableView(
          searchText.trimmed.isEmpty ? LocalizableKey.noSessionsYet.string : LocalizableKey.noHistoryResults.string,
          systemImage: searchText.trimmed.isEmpty ? "clock" : "magnifyingglass",
          description: Text(LocalizableKey.yourRefinementsAreSavedHereAutomatically.string))
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List {
          ForEach(groups, id: \.date) { group in
            Section {
              ForEach(group.sessions) { session in historyRow(session) }
            } header: {
              Text(dateLabel(group.date))
            }
          }
          if hasMore {
            ProgressView().frame(maxWidth: .infinity).id(sessions.count)
              .onAppear { loadPage() }
          }
          if loadFailed {
            Button(LocalizableKey.retry.string) { hasMore = true; loadPage() }
              .frame(maxWidth: .infinity)
          }
        }
        .listStyle(.inset)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .overlay(alignment: .bottom) {
      if isSummarizing {
        HStack(spacing: 8) {
          ProgressView().controlSize(.small)
          Text(LocalizableKey.summarizingHistory.string).font(.caption)
        }
        .padding(10).background(.regularMaterial, in: Capsule()).padding(12)
        .allowsHitTesting(false)
      }
    }
    .task(id: searchText) {
      if !searchText.isEmpty {
        do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
      }
      appliedSearchText = searchText
      sessions = []
      hasMore = true
      loadPage()
    }
    .task(id: sessions.map(\.id)) {
      for session in sessions {
        guard !Task.isCancelled else { return }
        isSummarizing = true
        await workspace.summarizeTitle(for: session)
        isSummarizing = false
      }
    }
    .confirmationDialog(LocalizableKey.deleteThisSession.string, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
      Button(LocalizableKey.delete.string, role: .destructive) {
        if let pendingDelete {
          workspace.deleteSession(pendingDelete)
          sessions = []
          hasMore = true
          loadPage()
        }
        pendingDelete = nil
      }
    } message: {
      Text(LocalizableKey.itsTextRewritesTranslationsAndImagesAreRemovedPermanently.string)
    }
  }

  private func dateLabel(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) { return LocalizableKey.today.string }
    if Calendar.current.isDateInYesterday(date) { return LocalizableKey.yesterday.string }
    return date.formatted(date: .abbreviated, time: .omitted)
  }

  private func loadPage() {
    guard !isLoading, hasMore, searchText == appliedSearchText else { return }
    isLoading = true
    defer { isLoading = false }
    let query = appliedSearchText.trimmed
    do {
      let page = try HistoryStore.page(in: workspace.context, query: query, offset: sessions.count)
      sessions.append(contentsOf: page)
      hasMore = page.count == 20
      loadFailed = false
    } catch {
      hasMore = false
      loadFailed = true
      workspace.flash(LocalizableKey.historyLoadFailed.string, symbol: "exclamationmark.triangle", isError: true)
    }
  }

  private func historyRow(_ session: RefinementSession) -> some View {
    Button {
      workspace.open(session)
    } label: {
      VStack(alignment: .leading, spacing: 3) {
        HStack {
          Text(session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
          if session.id == workspace.session.id {
            Text(LocalizableKey.current.string).font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
              .background(.tint.opacity(0.2), in: Capsule())
          }
        }
        Text(LocalizableKey.sessionCounts.format(session.rewrites.count, session.translations.count, session.images.count))
          .font(.caption).foregroundStyle(.secondary)
        CostLabel(summary: workspace.sessionCost(session.id))
        Text(session.updatedAt, format: .relative(presentation: .named))
          .font(.caption2).foregroundStyle(.tertiary)
      }
      .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .contextMenu { Button(LocalizableKey.delete.string, role: .destructive) { pendingDelete = session } }
    .swipeActions { Button(LocalizableKey.delete.string, role: .destructive) { pendingDelete = session } }
  }
}
