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
        Label("Back", systemImage: "chevron.left").labelStyle(.iconOnly).frame(width: 20, height: 20)
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
        Text("\(text.count) characters").font(.caption2).foregroundStyle(.secondary)
      }
    }
  }
}

struct DeleteButton: View {
  let title: String
  let action: () -> Void
  @State private var confirm = false

  var body: some View {
    IconButton("trash", help: "Remove") { confirm = true }
      .confirmationDialog(title, isPresented: $confirm) {
        Button("Remove", role: .destructive, action: action)
      }
  }
}

struct ModelPickerMenu: View {
  @Environment(ProviderStore.self) private var providers
  let kind: ModelKind
  let purpose: Preferences.Purpose
  let current: ModelRef
  let onPick: (ModelRef) -> Void

  var body: some View {
    LabeledContent("Model") {
      Menu(providers.displayName(current)) {
        ModelMenuItems(kind: kind, purpose: purpose, onPick: onPick)
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
        PageHeader(title: "\(item.platform.title) Rewrite") {
          DeleteButton(title: "Remove this rewrite?") { workspace.remove(item, id: id) }
        }
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          Picker("Tone", selection: $item.tone) {
            ForEach(Tone.allCases) { Text($0.title).tag($0) }
          }
          .onChange(of: item.tone) { _, tone in preferences.setTone(tone, for: item.platform) }
          ModelPickerMenu(kind: .text, purpose: .rewrite, current: item.model) {
            item.model = $0
            preferences.remember($0, for: .rewrite)
          }
          StatusLine(status: status)
          if let note = item.note {
            Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.orange)
          }
          OutputEditor(text: $item.output, limit: item.platform.characterLimit)
        }
        .padding(14)
        Divider()
        ActionBar(status: status, hasOutput: !item.output.isEmpty, runTitle: item.output.isEmpty ? "Rewrite" : "Regenerate",
                  onRun: { workspace.run(item) }, onStop: { workspace.stop(id) }, onCopy: { workspace.copy(item.output) })
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
        PageHeader(title: "\(item.language.name) Translation") {
          DeleteButton(title: "Remove this translation?") { workspace.remove(item, id: id) }
        }
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          Picker("Language", selection: $item.language) {
            ForEach(Language.all) { Text($0.name).tag($0) }
          }
          Picker("From", selection: $item.sourceRewriteID) {
            Text("Original").tag(UUID?.none)
            ForEach(workspace.session.sortedRewrites) { rewrite in
              Text("\(rewrite.platform.title) · \(rewrite.tone.title)").tag(UUID?.some(rewrite.id))
            }
          }
          ModelPickerMenu(kind: .text, purpose: .translate, current: item.model) {
            item.model = $0
            preferences.remember($0, for: .translate)
          }
          StatusLine(status: status)
          OutputEditor(text: $item.output)
        }
        .padding(14)
        Divider()
        ActionBar(status: status, hasOutput: !item.output.isEmpty, runTitle: item.output.isEmpty ? "Translate" : "Retranslate",
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

  var body: some View {
    if let item = workspace.session.images.first(where: { $0.id == id }) {
      @Bindable var item = item
      let status = workspace.status(id)
      VStack(spacing: 0) {
        PageHeader(title: "Image") {
          DeleteButton(title: "Remove this image?") { workspace.remove(item, id: id) }
        }
        Divider()
        VStack(alignment: .leading, spacing: 10) {
          ModelPickerMenu(kind: .image, purpose: .image, current: item.model) {
            item.model = $0
            preferences.remember($0, for: .image)
          }
          Picker("Size", selection: $item.size) {
            ForEach(ImageSize.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          TextField("Art direction (optional), e.g. flat illustration, warm colors", text: $item.instruction, axis: .vertical)
            .lineLimit(2...4)
            .textFieldStyle(.roundedBorder)
          StatusLine(status: status)
          ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.background.secondary)
            if let data = item.imageData, let image = NSImage(data: data) {
              Image(nsImage: image).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8)).padding(6)
                .draggable(Image(nsImage: image))
            } else if status.isRunning {
              ProgressView("Generating…")
            } else {
              Label("The image is based on your original post.", systemImage: "photo")
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
              Button("Save to Pictures/FineText") { workspace.saveImageToPictures(item) }
              Button("Save As…") { workspace.saveImageAs(item) }
            } label: {
              Label("Save", systemImage: "square.and.arrow.down")
            }
            .fixedSize()
            Button { workspace.copyImage(item) } label: { Label("Copy", systemImage: "doc.on.doc") }
          }
          Spacer()
          if status.isRunning {
            Button("Stop", role: .cancel) { workspace.stop(id) }
          } else {
            Button { workspace.run(item) } label: {
              Label(item.imageData == nil ? "Generate" : "Regenerate", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }
    } else {
      MissingItemView()
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
      Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
        .disabled(!hasOutput)
        .keyboardShortcut("c", modifiers: [.command, .shift])
      Spacer()
      if status.isRunning {
        Button("Stop", role: .cancel, action: onStop)
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
      PageHeader(title: "Not found") { EmptyView() }
      Divider()
      ContentUnavailableView("This item was removed", systemImage: "questionmark.square.dashed")
    }
  }
}

// MARK: - History

struct HistoryView: View {
  @Environment(Workspace.self) private var workspace
  @Query(sort: \RefinementSession.updatedAt, order: .reverse) private var sessions: [RefinementSession]
  @State private var pendingDelete: RefinementSession?

  var body: some View {
    VStack(spacing: 0) {
      PageHeader(title: "History") { EmptyView() }
      Divider()
      let visible = sessions.filter { !$0.isEmpty }
      if visible.isEmpty {
        ContentUnavailableView("No sessions yet", systemImage: "clock", description: Text("Your refinements are saved here automatically."))
      } else {
        List(visible) { session in
          Button {
            workspace.open(session)
          } label: {
            VStack(alignment: .leading, spacing: 3) {
              HStack {
                Text(session.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if session.id == workspace.session.id {
                  Text("Current").font(.caption2.weight(.semibold)).padding(.horizontal, 6).padding(.vertical, 1)
                    .background(.tint.opacity(0.2), in: Capsule())
                }
              }
              Text("\(session.rewrites.count) rewrites · \(session.translations.count) translations · \(session.images.count) images")
                .font(.caption).foregroundStyle(.secondary)
              Text(session.updatedAt, format: .relative(presentation: .named))
                .font(.caption2).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .contextMenu {
            Button("Delete", role: .destructive) { pendingDelete = session }
          }
          .swipeActions {
            Button("Delete", role: .destructive) { pendingDelete = session }
          }
        }
        .listStyle(.inset)
      }
    }
    .confirmationDialog("Delete this session?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
      Button("Delete", role: .destructive) {
        if let pendingDelete { workspace.deleteSession(pendingDelete) }
        pendingDelete = nil
      }
    } message: {
      Text("Its text, rewrites, translations and images are removed permanently.")
    }
  }
}
