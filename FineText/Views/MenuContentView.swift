import SwiftUI

struct MenuContentView: View {
  @Environment(Workspace.self) private var workspace

  var body: some View {
    ZStack {
      if let route = workspace.route {
        Group {
          switch route {
          case .rewrite(let id): RewriteDetailView(id: id)
          case .translation(let id): TranslationDetailView(id: id)
          case .image(let id): ImageDetailView(id: id)
          case .history: HistoryView()
          }
        }
        .transition(.move(edge: .trailing))
      } else {
        HomeView().transition(.move(edge: .leading))
      }
    }
    .frame(width: 440, height: 640)
    .background(Color(nsColor: .windowBackgroundColor))
    .animation(.snappy(duration: 0.25), value: workspace.route)
    .overlay(alignment: .bottom) { ToastOverlay() }
  }
}

// MARK: - Home

struct HomeView: View {
  @Environment(Workspace.self) private var workspace
  @Environment(AppUpdater.self) private var updater
  @Environment(\.openSettings) private var openSettings
  @State private var confirmClear = false
  @State private var showCosts = false

  var body: some View {
    @Bindable var workspace = workspace
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Label("FineText", systemImage: "wand.and.sparkles")
          .font(.headline)
        Spacer()
        Button { showCosts = true } label: {
          Label(workspace.sessionCost(workspace.session.id).totalLabel, systemImage: "dollarsign.circle")
            .font(.caption).monospacedDigit()
        }.buttonStyle(.borderless).help(LocalizableKey.usageCosts.string)
        IconButton("clock.arrow.circlepath", help: LocalizableKey.history.string) { workspace.route = .history }
        IconButton("gearshape", help: LocalizableKey.settings.string) {
          NSApp.activate()
          openSettings()
        }
        Menu {
          Button(LocalizableKey.checkForUpdates.string) { updater.checkForUpdates() }
            .disabled(!updater.isConfigured)
          Divider()
          Button(LocalizableKey.quitFinetext.string) { NSApp.terminate(nil) }
        } label: {
          Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          OriginalEditor(confirmClear: $confirmClear)
          Picker("", selection: $workspace.tab) {
            ForEach(WorkTab.allCases) { Text($0.title).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()

          switch workspace.tab {
          case .rewrite: RewriteSection()
          case .translate: TranslateSection()
          case .image: ImageSection()
          }
        }
        .padding(14)
      }

      Divider()

      HStack {
        Text(footerHint).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Button {
          workspace.runAll()
        } label: {
          Label(runTitle, systemImage: "sparkles")
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.return, modifiers: .command)
        .disabled(!workspace.canRunAll)
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
    .confirmationDialog(LocalizableKey.newThread.string, isPresented: $confirmClear) {
      Button(LocalizableKey.newThread.string) { workspace.clear() }
    } message: {
      Text(LocalizableKey.startsANewSessionTheCurrentOneStaysInHistory.string)
    }
    .sheet(isPresented: $showCosts) { CostsSheet() }
  }

  private var runTitle: String {
    switch workspace.tab {
    case .rewrite: LocalizableKey.rewriteAll.string
    case .translate: LocalizableKey.translateAll.string
    case .image: LocalizableKey.generateAll.string
    }
  }

  private var footerHint: String {
    switch workspace.tab {
    case .rewrite: LocalizableKey.platformCount.format(workspace.session.rewrites.count)
    case .translate: LocalizableKey.languageCount.format(workspace.session.translations.count)
    case .image: LocalizableKey.imageCount.format(workspace.session.images.count)
    }
  }
}

struct OriginalEditor: View {
  @Environment(Workspace.self) private var workspace
  @Binding var confirmClear: Bool

  var body: some View {
    @Bindable var workspace = workspace
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(LocalizableKey.originalPost.string).font(.subheadline.weight(.semibold))
        Spacer()
        IconButton("doc.on.clipboard", help: LocalizableKey.paste.string) {
          if let text = NSPasteboard.general.string(forType: .string) {
            workspace.originalText = text
            Haptics.tap()
          }
        }
        IconButton("square.and.pencil", help: LocalizableKey.newThread.string) { confirmClear = true }
          .disabled(workspace.session.isEmpty)
      }
      ZStack(alignment: .topLeading) {
        TextEditor(text: $workspace.originalText)
          .font(.body)
          .scrollContentBackground(.hidden)
          .padding(6)
        if workspace.originalText.isEmpty {
          Text(LocalizableKey.pasteOrTypeThePostYouWantToRefine.string)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .allowsHitTesting(false)
        }
      }
      .frame(height: 130)
      .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
      Text(LocalizableKey.characterCount.format(workspace.originalText.count))
        .font(.caption2).foregroundStyle(.secondary)
    }
  }
}

// MARK: - Sections

struct RewriteSection: View {
  @Environment(Workspace.self) private var workspace
  @Environment(Preferences.self) private var preferences
  @Environment(ProviderStore.self) private var providers

  @State private var showCustomPlatforms = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Menu {
        if let platform = preferences.lastPlatform, let model = preferences.lastModel(.rewrite), providers.isAvailable(model) {
          Button(LocalizableKey.again.format(platform.title, providers.displayName(model))) {
            workspace.addRewrite(platform: platform, model: model)
          }
          Divider()
        }
        if let platform = preferences.lastCustomPlatform, let model = preferences.lastModel(.rewrite), providers.isAvailable(model) {
          Button(LocalizableKey.again.format(platform.name, providers.displayName(model))) {
            workspace.addRewrite(customPlatform: platform, model: model)
          }
          Divider()
        }
        ForEach(Platform.menuPlatforms) { platform in
          Menu {
            if platform.variants.isEmpty {
              ModelMenuItems(kind: .text, purpose: .rewrite) { workspace.addRewrite(platform: platform, model: $0) }
            } else {
              ForEach(platform.variants) { variant in
                Menu {
                  ModelMenuItems(kind: .text, purpose: .rewrite) { workspace.addRewrite(platform: variant, model: $0) }
                } label: {
                  if variant == preferences.lastPlatform {
                    Label(variant.variantTitle, systemImage: "checkmark")
                  } else {
                    Text(variant.variantTitle)
                  }
                }
              }
            }
          } label: {
            if platform == preferences.lastPlatform || platform.variants.contains(where: { $0 == preferences.lastPlatform }) {
              Label(platform.menuTitle, systemImage: "checkmark")
            } else {
              Text(platform.menuTitle)
            }
          }
        }
        if !preferences.customPlatforms.isEmpty {
          Divider()
          ForEach(preferences.customPlatforms) { platform in
            Menu(platform.name) {
              ModelMenuItems(kind: .text, purpose: .rewrite) {
                workspace.addRewrite(customPlatform: platform, model: $0)
              }
            }
          }
        }
        Divider()
        Button(LocalizableKey.customPlatforms.string, systemImage: "slider.horizontal.3") {
          Haptics.tap()
          showCustomPlatforms = true
        }
      } label: {
        Label(LocalizableKey.addPlatform.string, systemImage: "plus.circle.fill")
      }
      .fixedSize()

      if workspace.session.rewrites.isEmpty {
        EmptyHint(symbol: "text.badge.plus", text: LocalizableKey.addAPlatformPickAModelThenRewrite.string)
      }
      ForEach(workspace.session.sortedRewrites) { item in
        JobCard(
          symbol: item.platformSymbol,
          title: "\(item.platformTitle) · \(item.tone.title)",
          subtitle: providers.displayName(item.model),
          status: workspace.status(item.id),
          preview: item.output,
          cost: workspace.cost(for: item.id),
          onRun: { workspace.run(item) },
          onStop: { workspace.stop(item.id) },
          onCopy: { workspace.copy(item.output) },
          onOpen: { workspace.route = .rewrite(item.id) }
        )
      }
    }
    .sheet(isPresented: $showCustomPlatforms) { CustomPlatformsSheet() }
  }
}

struct TranslateSection: View {
  @Environment(Workspace.self) private var workspace
  @Environment(Preferences.self) private var preferences
  @Environment(ProviderStore.self) private var providers
  @State private var source: UUID?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        Menu {
          if let language = preferences.lastLanguage, let model = preferences.lastModel(.translate), providers.isAvailable(model) {
            Button(LocalizableKey.again.format(language.localizedName, providers.displayName(model))) {
              workspace.addTranslation(language: language, model: model, source: validSource)
            }
            Divider()
          }
          ForEach(Language.all) { language in
            Menu {
              ModelMenuItems(kind: .text, purpose: .translate) {
                workspace.addTranslation(language: language, model: $0, source: validSource)
              }
            } label: {
              if language == preferences.lastLanguage {
                Label(language.localizedName, systemImage: "checkmark")
              } else {
                Text(language.localizedName)
              }
            }
          }
        } label: {
          Label(LocalizableKey.addLanguage.string, systemImage: "plus.circle.fill")
        }
        .fixedSize()
        Spacer()
        Picker(LocalizableKey.from.string, selection: $source) {
          Text(LocalizableKey.original.string).tag(UUID?.none)
          ForEach(workspace.session.sortedRewrites.filter { !$0.output.isEmpty }) { rewrite in
            Text("\(rewrite.platformTitle) · \(rewrite.tone.title)").tag(UUID?.some(rewrite.id))
          }
        }
        .fixedSize()
      }

      if workspace.session.translations.isEmpty {
        EmptyHint(symbol: "globe", text: LocalizableKey.addALanguageToTranslateTheOriginalOrARewrite.string)
      }
      ForEach(workspace.session.sortedTranslations) { item in
        JobCard(
          symbol: "globe",
          title: LocalizableKey.translationSource.format(item.language.localizedName, workspace.sourceTitle(for: item)),
          subtitle: providers.displayName(item.model),
          status: workspace.status(item.id),
          preview: item.output,
          cost: workspace.cost(for: item.id),
          onRun: { workspace.run(item) },
          onStop: { workspace.stop(item.id) },
          onCopy: { workspace.copy(item.output) },
          onOpen: { workspace.route = .translation(item.id) }
        )
      }
    }
  }

  private var validSource: UUID? {
    guard let source, workspace.session.rewrites.contains(where: { $0.id == source }) else { return nil }
    return source
  }
}

struct ImageSection: View {
  @Environment(Workspace.self) private var workspace
  @Environment(ProviderStore.self) private var providers

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Menu {
        ModelMenuItems(kind: .image, purpose: .image) { model in
          let item = workspace.addImage(model: model)
          workspace.route = .image(item.id)
        }
      } label: {
        Label(LocalizableKey.addImage.string, systemImage: "plus.circle.fill")
      }
      .fixedSize()

      if workspace.session.images.isEmpty {
        EmptyHint(symbol: "photo.badge.plus", text: LocalizableKey.pickAnImageModelAddOptionalArtDirectionThenGenerate.string)
      }
      ForEach(workspace.session.sortedImages) { item in
        ImageCard(item: item)
      }
    }
  }
}

struct ImageCard: View {
  @Environment(Workspace.self) private var workspace
  @Environment(ProviderStore.self) private var providers
  let item: ImageItem

  var body: some View {
    let status = workspace.status(item.id)
    HStack(alignment: .top, spacing: 10) {
      Group {
        if let data = item.imageData, let image = NSImage(data: data) {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          ZStack {
            Rectangle().fill(.quaternary)
            if status.isRunning { ProgressView().controlSize(.small) } else { Image(systemName: "photo").foregroundStyle(.secondary) }
          }
        }
      }
      .frame(width: 64, height: 64)
      .clipShape(RoundedRectangle(cornerRadius: 6))

      VStack(alignment: .leading, spacing: 4) {
        Text(providers.displayName(item.model)).font(.subheadline.weight(.semibold)).lineLimit(1)
        Text(item.instruction.isEmpty ? LocalizableKey.noArtDirection.format(item.size.title) : item.instruction)
          .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        if item.transparentBackground {
          Label(LocalizableKey.transparent.string, systemImage: "checkerboard.rectangle")
            .font(.caption2).foregroundStyle(.secondary)
        }
        CostLabel(summary: workspace.cost(for: item.id))
        StatusLine(status: status)
      }
      Spacer(minLength: 0)
      VStack(spacing: 6) {
        if status.isRunning {
          IconButton("stop.circle", help: LocalizableKey.stop.string) { workspace.stop(item.id) }
        } else {
          IconButton("sparkles", help: LocalizableKey.generate.string) { workspace.run(item) }
        }
        if item.imageData != nil {
          IconButton("doc.on.doc", help: LocalizableKey.copyImage.string) { workspace.copyImage(item) }
        }
      }
    }
    .padding(10)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .contentShape(Rectangle())
    .onTapGesture { workspace.route = .image(item.id) }
  }
}

// MARK: - Shared components

struct JobCard: View {
  let symbol: String
  let title: String
  let subtitle: String
  let status: JobStatus
  let preview: String
  var cost: CostSummary
  let onRun: () -> Void
  let onStop: () -> Void
  let onCopy: () -> Void
  let onOpen: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Image(systemName: symbol).frame(width: 18).foregroundStyle(.tint)
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
          Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
          CostLabel(summary: cost)
        }
        Spacer()
        if status.isRunning {
          IconButton("stop.circle", help: LocalizableKey.stop.string, action: onStop)
        } else {
          IconButton(preview.isEmpty ? "sparkles" : "arrow.clockwise", help: preview.isEmpty ? LocalizableKey.run.string : LocalizableKey.regenerate.string, action: onRun)
        }
        IconButton("doc.on.doc", help: LocalizableKey.copy.string, action: onCopy).disabled(preview.isEmpty)
        IconButton("chevron.right", help: LocalizableKey.open.string, action: onOpen)
      }
      StatusLine(status: status)
      if !preview.isEmpty {
        Text(preview).font(.callout).lineLimit(4).foregroundStyle(.primary.opacity(0.85))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(10)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    .contentShape(Rectangle())
    .onTapGesture(perform: onOpen)
  }
}

struct StatusLine: View {
  let status: JobStatus

  var body: some View {
    switch status {
    case .idle, .done: EmptyView()
    case .running(let message):
      HStack(spacing: 6) {
        ProgressView().controlSize(.mini)
        Text(message).font(.caption).foregroundStyle(.secondary)
      }
    case .failed(let message):
      Label(message, systemImage: "exclamationmark.triangle.fill")
        .font(.caption).foregroundStyle(.red).lineLimit(3)
    }
  }
}

struct IconButton: View {
  let symbol: String
  let help: String
  let action: () -> Void

  init(_ symbol: String, help: String, action: @escaping () -> Void) {
    self.symbol = symbol
    self.help = help
    self.action = action
  }

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).frame(width: 20, height: 20).contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .help(help)
    .accessibilityLabel(help)
  }
}

struct EmptyHint: View {
  let symbol: String
  let text: String

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: symbol).font(.title3).foregroundStyle(.secondary)
      Text(text).font(.callout).foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, style: StrokeStyle(lineWidth: 1, dash: [4])))
  }
}

struct ToastOverlay: View {
  @Environment(Workspace.self) private var workspace

  var body: some View {
    Group {
      if let toast = workspace.toast {
        Label(toast.message, systemImage: toast.symbol)
          .font(.callout.weight(.medium))
          .foregroundStyle(toast.isError ? .red : .primary)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.regularMaterial, in: Capsule())
          .shadow(radius: 6, y: 2)
          .padding(.bottom, 60)
          .transition(.move(edge: .bottom).combined(with: .opacity))
          .id(toast.id)
      }
    }
    .animation(.spring(duration: 0.3), value: workspace.toast)
  }
}

/// Model picker shared by every "Add …" menu: recent picks first, then each provider's models
/// filtered by capability (text vs image).
struct ModelMenuItems: View {
  @Environment(ProviderStore.self) private var providers
  @Environment(Preferences.self) private var preferences
  @Environment(\.openSettings) private var openSettings
  let kind: ModelKind
  let purpose: Preferences.Purpose
  let onPick: (ModelRef) -> Void

  var body: some View {
    if !providers.hasSources(for: kind) {
      Button(LocalizableKey.addAProviderInSettings.string) {
        NSApp.activate()
        openSettings()
      }
      if kind == .text {
        Button(LocalizableKey.downloadModelFromHub.string, action: openLocalModels)
      }
    } else {
      let last = preferences.lastModel(purpose)
      let recent = preferences.recentModels(purpose).filter { ref in
        providers.models(for: ref.providerID, kind: kind).contains { $0.id == ref.modelID }
      }
      if !recent.isEmpty {
        Section(LocalizableKey.recent.string) {
          ForEach(recent, id: \.self) { ref in
            pickButton(providers.displayName(ref), ref: ref, selected: ref == last)
          }
        }
      }
      if providers.codex != nil {
        cliMenu(ProviderStore.codexProvider, last: last)
      }
      if kind == .text, providers.claudeCode != nil {
        cliMenu(ProviderStore.claudeCodeProvider, last: last)
      }
      if kind == .text {
        let local = providers.models(for: Provider.localID, kind: .text)
        Menu(Provider.localName) {
          ForEach(local) { model in
            let ref = ModelRef(providerID: Provider.localID, modelID: model.id)
            pickButton(model.id, ref: ref, selected: ref == last)
          }
          if !local.isEmpty { Divider() }
          Button(LocalizableKey.downloadFromHub.string, action: openLocalModels)
        }
      }
      ForEach(providers.providers) { provider in
        let models = providers.models(for: provider.id, kind: kind)
        Menu(provider.name) {
          if models.isEmpty {
            Text(providers.loading.contains(provider.id) ? LocalizableKey.loadingModels.string : LocalizableKey.noModels.format(kind == .text ? LocalizableKey.textModels.string : LocalizableKey.imageModels.string))
            Button(LocalizableKey.refreshModels.string) { Task { await providers.refresh(provider.id) } }
          }
          ForEach(models) { model in
            let ref = ModelRef(providerID: provider.id, modelID: model.id)
            pickButton(model.id, ref: ref, selected: ref == last)
          }
        }
      }
    }
  }

  private func cliMenu(_ provider: Provider, last: ModelRef?) -> some View {
    Menu(provider.name) {
      ForEach(providers.models(for: provider.id, kind: kind)) { model in
        let ref = ModelRef(providerID: provider.id, modelID: model.id)
        pickButton(providers.modelName(ref), ref: ref, selected: ref == last)
      }
      if kind == .text {
        Divider()
        Button(LocalizableKey.refreshModels.string) {
          Haptics.tap()
          Task { await providers.refreshCLIModels(provider.id) }
        }
        .disabled(providers.loading.contains(provider.id))
      }
    }
  }

  /// Opens Settings on the Local Models tab.
  private func openLocalModels() {
    UserDefaults.standard.set(SettingsTab.local.rawValue, forKey: DefaultsKey.settingsTab)
    NSApp.activate()
    openSettings()
  }

  @ViewBuilder private func pickButton(_ title: String, ref: ModelRef, selected: Bool) -> some View {
    Button {
      onPick(ref)
    } label: {
      if selected { Label(title, systemImage: "checkmark") } else { Text(title) }
    }
  }
}
