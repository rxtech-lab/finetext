import SwiftUI

enum SettingsTab: String {
  case general, platforms, providers, agents, flowcy, local, humanizer, mcp
}

struct SettingsView: View {
  @AppStorage(DefaultsKey.settingsTab) private var tab = SettingsTab.general

  var body: some View {
    TabView(selection: $tab) {
      Tab(LocalizableKey.general.string, systemImage: "gearshape", value: .general) { GeneralSettingsView() }
      Tab(LocalizableKey.platforms.string, systemImage: "square.grid.2x2", value: .platforms) { PlatformsSettingsView() }
      Tab(LocalizableKey.providers.string, systemImage: "server.rack", value: .providers) { ProvidersSettingsView() }
      Tab(LocalizableKey.codingAgents.string, systemImage: "terminal", value: .agents) { CodingAgentsSettingsView() }
      Tab("Flowcy", systemImage: "cloud", value: .flowcy) { FlowcySettingsView() }
      Tab(LocalizableKey.localModels.string, systemImage: "cpu", value: .local) { LocalModelsSettingsView() }
      Tab(LocalizableKey.humanizer.string, systemImage: "character.bubble", value: .humanizer) { HumanizerSettingsView() }
      Tab("MCP", systemImage: "point.3.connected.trianglepath.dotted", value: .mcp) { MCPSettingsView() }
    }
    .frame(width: 700, height: 520)
    .modelDownloadOverlay()
    .onAppear { AppAnalytics.screen("settings_\(tab.rawValue)") }
    .onChange(of: tab) { AppAnalytics.screen("settings_\(tab.rawValue)") }
  }
}

// MARK: - General

struct GeneralSettingsView: View {
  @Environment(AppUpdater.self) private var updater
  @AppStorage(DefaultsKey.analyticsEnabled) private var analyticsEnabled = true

  var body: some View {
    @Bindable var updater = updater
    Form {
      Section(LocalizableKey.images.string) {
        LabeledContent(LocalizableKey.quickSaveFolder.string) {
          Button("~/Pictures/FineText") {
            try? FileManager.default.createDirectory(at: Workspace.picturesFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Workspace.picturesFolder)
          }
          .buttonStyle(.link)
        }
      }
      Section(LocalizableKey.updates.string) {
        Toggle(LocalizableKey.automaticallyCheckForUpdates.string, isOn: $updater.automaticallyChecks)
          .disabled(!updater.isConfigured)
        LabeledContent(LocalizableKey.version.string, value: AppUpdater.versionString)
        Button(LocalizableKey.checkForUpdates.string) { updater.checkForUpdates() }
          .disabled(!updater.isConfigured)
        if !updater.isConfigured {
          Text(LocalizableKey.updatesAreAvailableInReleaseBuildsOnly.string).font(.caption).foregroundStyle(.secondary)
        }
      }
      Section(LocalizableKey.privacy.string) {
        Toggle(LocalizableKey.shareAnonymousUsageAnalytics.string, isOn: $analyticsEnabled)
          .onChange(of: analyticsEnabled) { AppAnalytics.setEnabled(analyticsEnabled) }
        Text(LocalizableKey.analyticsDescription.string).font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}

// MARK: - Platforms

/// Writing platforms: the preset catalog and each platform's default tone.
struct PlatformsSettingsView: View {
  @Environment(Preferences.self) private var preferences
  @Environment(PresetStore.self) private var presets
  @State private var presetStatus: Toast?

  var body: some View {
    Form {
      Section(LocalizableKey.presets.string) {
        LabeledContent(LocalizableKey.presetsVersion.string, value: presets.catalog.version)
        LabeledContent(LocalizableKey.presetsLastChecked.string) {
          if let date = presets.lastChecked {
            Text(date, format: .relative(presentation: .named))
          } else {
            Text(LocalizableKey.never.string)
          }
        }
        Button(LocalizableKey.updateNow.string, action: updatePresets)
          .disabled(presets.isRefreshing || PresetStore.configuredURL == nil)
        Text(LocalizableKey.presetsDescription.string).font(.caption).foregroundStyle(.secondary)
      }
      Section(LocalizableKey.defaultTonePerPlatform.string) {
        ForEach(presets.entries) { entry in
          Picker(entry.title, selection: Binding(get: { preferences.tone(for: entry.preset) }, set: { preferences.setTone($0, for: entry.preset) })) {
            ForEach(Tone.allCases) { Text($0.title).tag($0) }
          }
        }
      }
    }
    .formStyle(.grouped)
    .overlay(alignment: .bottom) {
      if presets.isRefreshing {
        StatusOverlay(Toast(message: LocalizableKey.updatingPresets.string, symbol: "arrow.triangle.2.circlepath"), progress: true)
      } else if let presetStatus {
        StatusOverlay(presetStatus).id(presetStatus.id)
      }
    }
    .animation(.spring(duration: 0.3), value: presets.isRefreshing)
    .animation(.spring(duration: 0.3), value: presetStatus)
  }

  private func updatePresets() {
    Haptics.tap()
    presetStatus = nil
    Task {
      let changed = await presets.refresh()
      let status: Toast
      if let error = presets.lastError {
        status = Toast(message: LocalizableKey.presetsUpdateFailed.format(error), symbol: "xmark.octagon", isError: true)
        Haptics.failure()
      } else {
        status = Toast(message: changed ? LocalizableKey.presetsUpdated.string : LocalizableKey.presetsUpToDate.string, symbol: "checkmark.circle")
        Haptics.success()
      }
      presetStatus = status
      try? await Task.sleep(for: .seconds(2.5))
      if presetStatus == status { presetStatus = nil }
    }
  }
}

/// A transient status capsule shown over the Settings form.
struct StatusOverlay: View {
  let toast: Toast
  var progress = false

  init(_ toast: Toast, progress: Bool = false) {
    self.toast = toast
    self.progress = progress
  }

  var body: some View {
    HStack(spacing: 8) {
      if progress { ProgressView().controlSize(.small) } else { Image(systemName: toast.symbol) }
      Text(toast.message).lineLimit(2)
    }
    .font(.callout)
    .foregroundStyle(toast.isError ? .red : .primary)
    .padding(.horizontal, 14)
    .padding(.vertical, 8)
    .background(.regularMaterial, in: Capsule())
    .shadow(radius: 6, y: 2)
    .padding(.bottom, 16)
    .transition(.move(edge: .bottom).combined(with: .opacity))
  }
}

// MARK: - Claude Code

/// Codex and Claude Code: local CLIs that FineText drives with your existing sign-ins.
struct CodingAgentsSettingsView: View {
  var body: some View {
    Form {
      CodexSettingsSection()
      ClaudeCodeSettingsSection()
    }
    .formStyle(.grouped)
  }
}

struct ClaudeCodeSettingsSection: View {
  @Environment(ProviderStore.self) private var store

  var body: some View {
    Section {
      LabeledContent(LocalizableKey.status.string) {
        if store.detectingClaudeCode {
          ProgressView().controlSize(.small)
        } else if let install = store.claudeCode {
          Label(LocalizableKey.installedVersion.format(install.version), systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        } else {
          Label(LocalizableKey.notFound.string, systemImage: "xmark.circle").foregroundStyle(.secondary)
        }
      }
      if let install = store.claudeCode {
        LabeledContent(LocalizableKey.location.string) {
          Text(install.executable.path).font(.caption.monospaced()).textSelection(.enabled)
            .lineLimit(1).truncationMode(.middle)
        }
      }
      Button(LocalizableKey.detectAgain.string) {
        Haptics.tap()
        Task { await store.detectClaudeCode() }
      }
      .disabled(store.detectingClaudeCode)
    } header: {
      Text("Claude Code")
    } footer: {
      Text(LocalizableKey.claudeCodeSetup.string).font(.caption).foregroundStyle(.secondary)
    }
  }
}

// MARK: - Codex

struct CodexSettingsSection: View {
  @Environment(ProviderStore.self) private var store

  var body: some View {
    Section {
      LabeledContent(LocalizableKey.status.string) {
        if store.detectingCodex {
          ProgressView().controlSize(.small)
        } else if let codex = store.codex {
          Label(LocalizableKey.installedVersion.format(codex.version), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        } else {
          Label(LocalizableKey.notFound.string, systemImage: "xmark.circle").foregroundStyle(.secondary)
        }
      }
      if let codex = store.codex {
        LabeledContent(LocalizableKey.location.string) {
          Text(codex.executable.path).font(.caption.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
        }
      }
      Button(LocalizableKey.detectAgain.string) {
        Haptics.tap()
        Task { await store.detectCodex() }
      }
      .disabled(store.detectingCodex)
    } header: {
      Text("Codex")
    } footer: {
      Text(store.codex == nil
        ? LocalizableKey.installTheCodexCliToRewriteAndGenerateImagesWithYourChatgptPlan.string
        : LocalizableKey.chooseCodexToRewriteTranslateAndGenerateImagesWithYourCodexSignIn.string)
        .font(.caption).foregroundStyle(.secondary)
    }
  }
}

// MARK: - Providers

struct ProvidersSettingsView: View {
  @Environment(ProviderStore.self) private var store
  @State private var editing: ProviderDraft?
  @State private var selection: UUID?
  @State private var pendingDelete: Provider?

  var body: some View {
    VStack(spacing: 0) {
      if store.providers.isEmpty {
        ContentUnavailableView {
          Label(LocalizableKey.noProviders.string, systemImage: "server.rack")
        } description: {
          Text(LocalizableKey.addAnOpenaiCompatibleEndpointWithItsUrlAndApiKeyToStartRewriting.string)
        } actions: {
          Button(LocalizableKey.addProvider.string) { editing = ProviderDraft() }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(selection: $selection) {
          ForEach(store.providers) { provider in
            ProviderRow(provider: provider)
              .tag(provider.id)
              .contextMenu {
                Button(LocalizableKey.edit.string) { edit(provider) }
                Button(LocalizableKey.refreshModels.string) { Task { await store.refresh(provider.id) } }
                Divider()
                Button(LocalizableKey.delete.string, role: .destructive) { pendingDelete = provider }
              }
          }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: UUID.self) { _ in } primaryAction: { ids in
          if let id = ids.first, let provider = store.provider(id) { edit(provider) }
        }
      }
      Divider()
      HStack(spacing: 6) {
        Button { editing = ProviderDraft() } label: { Image(systemName: "plus") }
          .help(LocalizableKey.addProviderHelp.string)
        Button {
          pendingDelete = selection.flatMap(store.provider)
        } label: { Image(systemName: "minus") }
          .disabled(selection == nil)
          .help(LocalizableKey.deleteProvider.string)
        Spacer()
        Button(LocalizableKey.edit.string) { if let provider = selection.flatMap(store.provider) { edit(provider) } }
          .disabled(selection == nil)
        Button(LocalizableKey.refreshAll.string) { Task { await store.refreshAll() } }
          .disabled(store.providers.isEmpty)
      }
      .buttonStyle(.borderless)
      .padding(8)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .sheet(item: $editing) { draft in
      ProviderEditorSheet(draft: draft)
    }
    .confirmationDialog(LocalizableKey.deleteProviderConfirmation.format(pendingDelete?.name ?? LocalizableKey.provider.string), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
      Button(LocalizableKey.delete.string, role: .destructive) {
        if let pendingDelete { store.delete(pendingDelete) }
        selection = nil
        pendingDelete = nil
      }
    } message: {
      Text(LocalizableKey.itsApiKeyIsRemovedFromTheKeychain.string)
    }
  }

  private func edit(_ provider: Provider) {
    editing = ProviderDraft(provider: provider, apiKey: store.apiKey(for: provider.id))
  }
}

struct ProviderRow: View {
  @Environment(ProviderStore.self) private var store
  let provider: Provider

  var body: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text(provider.name).font(.headline)
        Text(provider.baseURL).font(.caption).foregroundStyle(.secondary)
        if let error = store.errors[provider.id] {
          Label(error, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.red).lineLimit(2)
        }
      }
      Spacer()
      if store.loading.contains(provider.id) {
        ProgressView().controlSize(.small)
      } else {
        VStack(alignment: .trailing, spacing: 2) {
          Text(LocalizableKey.textModelCount.format(store.models(for: provider.id, kind: .text).count)).font(.caption)
          Text(LocalizableKey.imageModelCount.format(store.models(for: provider.id, kind: .image).count)).font(.caption)
        }
        .foregroundStyle(.secondary)
      }
    }
    .padding(.vertical, 4)
  }
}

struct ProviderDraft: Identifiable {
  var id = UUID()
  var provider = Provider(name: "", baseURL: "")
  var apiKey = ""
  var isNew = true

  init() {}
  init(provider: Provider, apiKey: String) {
    self.provider = provider
    self.apiKey = apiKey
    isNew = false
  }
}

struct ProviderEditorSheet: View {
  @Environment(ProviderStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  @State private var draft: ProviderDraft
  @State private var testState: TestState = .idle

  enum TestState: Equatable {
    case idle, testing, success(Int, Int), failure(String)
  }

  init(draft: ProviderDraft) { _draft = State(initialValue: draft) }

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          if draft.isNew {
            Picker(LocalizableKey.preset.string, selection: Binding(get: { "" }, set: { name in
              if let preset = ProviderStore.presets.first(where: { $0.name == name }) {
                draft.provider.name = preset.name
                draft.provider.baseURL = preset.baseURL
              }
            })) {
              Text(LocalizableKey.custom.string).tag("")
              ForEach(ProviderStore.presets, id: \.name) { Text($0.name).tag($0.name) }
            }
          }
          TextField(LocalizableKey.name.string, text: $draft.provider.name, prompt: Text(LocalizableKey.myProvider.string))
          TextField(LocalizableKey.baseUrl.string, text: $draft.provider.baseURL, prompt: Text("https://api.openai.com/v1"))
          SecureField(LocalizableKey.apiKey.string, text: $draft.apiKey, prompt: Text(LocalizableKey.skLeaveEmptyForLocalServers.string))
        } footer: {
          Text(LocalizableKey.anyOpenaiCompatibleEndpointModelsAreListedFromGetModelsAndFilteredByCapabilityTheKeyIsStoredInYourKeychain.string)
            .font(.caption).foregroundStyle(.secondary)
        }
        Section {
          HStack {
            Button(LocalizableKey.testConnection.string, action: test).disabled(!isValid || testState == .testing)
            Spacer()
            switch testState {
            case .idle: EmptyView()
            case .testing: ProgressView().controlSize(.small)
            case .success(let text, let image):
              Label(LocalizableKey.modelCounts.format(text, image), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .failure(let message):
              Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
            }
          }
        }
      }
      .formStyle(.grouped)
      Divider()
      HStack {
        Spacer()
        Button(LocalizableKey.cancel.string, role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button(draft.isNew ? LocalizableKey.add.string : LocalizableKey.save.string) {
          var provider = draft.provider
          provider.name = provider.name.trimmed
          provider.baseURL = provider.baseURL.trimmed
          store.save(provider, apiKey: draft.apiKey.trimmed)
          Haptics.success()
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(!isValid)
      }
      .padding(12)
    }
    .frame(width: 480)
    .frame(minHeight: 400, maxHeight: .infinity)
  }

  private var isValid: Bool {
    !draft.provider.name.trimmed.isEmpty && URL(string: draft.provider.baseURL.trimmed)?.scheme?.hasPrefix("http") == true
  }

  private func test() {
    testState = .testing
    let baseURL = draft.provider.baseURL
    let key = draft.apiKey
    Task {
      do {
        let models = try await OpenAIClient(baseURL: baseURL, apiKey: key).listModels()
        testState = .success(models.filter(\.generatesText).count, models.filter(\.generatesImages).count)
        Haptics.success()
      } catch {
        testState = .failure(error.localizedDescription)
        Haptics.failure()
      }
    }
  }
}

// MARK: - Humanizer

struct HumanizerSettingsView: View {
  @Environment(TranslationModelManager.self) private var gemma
  @AppStorage(DefaultsKey.humanizationMode) private var mode = ""
  @AppStorage(DefaultsKey.humanizationEngine) private var engine = HumanizationEngine.translateGemma
  @AppStorage(DefaultsKey.targetAIScore) private var target = 20.0
  @AppStorage(DefaultsKey.humanizeRounds) private var rounds = 3
  @AppStorage(DefaultsKey.pivotLanguage) private var pivot = Language.japanese.code
  @AppStorage(DefaultsKey.gemmaModel) private var model = TranslationModel.default.id
  @State private var showDownload = false
  @State private var showDetector = false

  private var selectedMode: HumanizationMode {
    HumanizationMode(rawValue: mode) ?? (rounds > 0 ? .manual : .off)
  }

  var body: some View {
    Form {
      Section {
        Picker(LocalizableKey.humanizationMode.string, selection: Binding(get: { selectedMode }, set: {
          mode = $0.rawValue
          if $0 == .manual { rounds = max(1, rounds) }
        })) {
          Text(LocalizableKey.off.string).tag(HumanizationMode.off)
          Text(LocalizableKey.manualRounds.string).tag(HumanizationMode.manual)
          Text(LocalizableKey.automaticRounds.string).tag(HumanizationMode.automatic)
        }
        if selectedMode == .manual {
          Stepper(value: $rounds, in: 1...Int.max) {
            LabeledContent(LocalizableKey.roundTrips.string, value: "\(max(1, rounds))")
          }
        }
        if selectedMode == .automatic {
          LabeledContent(LocalizableKey.targetAIScore.string, value: "\(Int(target))/100")
          Slider(value: $target, in: 0...100, step: 1) { Text(LocalizableKey.targetAIScore.string) }
        }
        if selectedMode != .off {
          Picker(LocalizableKey.humanizationEngine.string, selection: $engine) {
            Text(LocalizableKey.translationRoundTrip.string).tag(HumanizationEngine.translateGemma)
            Text(LocalizableKey.selectedRewriteModel.string).tag(HumanizationEngine.rewriteModel)
          }
          if engine == .translateGemma {
            Picker(LocalizableKey.pivotLanguage.string, selection: $pivot) {
              ForEach(Language.all) { Text($0.localizedName).tag($0.code) }
            }
          }
        }
      } header: {
        Text(LocalizableKey.reduceTheAiFeel.string)
      } footer: {
        Text(selectedMode == .automatic ? LocalizableKey.automaticRoundsHelp.string : LocalizableKey.manualRoundsHelp.string)
          .font(.caption).foregroundStyle(.secondary)
      }

      Section {
        Button { showDetector = true; Haptics.tap() } label: {
          LabeledContent(LocalizableKey.aiDetector.string, value: AIDetectorEngine.selected.name)
        }
        .buttonStyle(.plain)
      } footer: {
        Text(LocalizableKey.detectorScoreHelp.string).font(.caption).foregroundStyle(.secondary)
      }

      if engine == .translateGemma {
        Section {
          Picker(LocalizableKey.model.string, selection: $model) {
            ForEach(TranslationModel.all) { Text("\($0.name) (\($0.size))").tag($0.id) }
          }
          .disabled(gemma.isDownloading || gemma.isRemoving)
          .onChange(of: model) { gemma.refresh() }
          statusRow
        } header: {
          Text(LocalizableKey.translationModel.string)
        } footer: {
          Text(TranslationModel.named(model).isNLLB ? LocalizableKey.nllbDescription.string : LocalizableKey.translategemmaIsAnOpenTranslationModelFromGoogleItRunsOnThisMacWithMlxOnAppleSiliconAndIsDownloadedSeparatelyFromHuggingFace.string)
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
    .overlay(alignment: .bottom) { SettingsToast(toast: gemma.toast) }
    .onAppear { gemma.refresh() }
    .sheet(isPresented: $showDownload) {
      ModelDownloadSheet(model: TranslationModel.named(model))
    }
    .sheet(isPresented: $showDetector) { AIDetectorSettingsSheet() }
    .onChange(of: mode) { AppAnalytics.log(.settingChanged, ["setting": "humanization_mode", "value": mode]) }
    .onChange(of: engine) { AppAnalytics.log(.settingChanged, ["setting": "humanization_engine", "value": engine.rawValue]) }
    .onChange(of: model) { AppAnalytics.log(.settingChanged, ["setting": "translation_model", "value": model]) }
    .onChange(of: pivot) { AppAnalytics.log(.settingChanged, ["setting": "pivot_language", "value": pivot]) }
  }

  @ViewBuilder private var statusRow: some View {
    switch gemma.state {
    case .unknown, .checking:
      LabeledContent(LocalizableKey.status.string) { ProgressView().controlSize(.small) }
    case .notInstalled:
      LabeledContent(LocalizableKey.status.string) { Text(LocalizableKey.notDownloaded.string).foregroundStyle(.secondary) }
      HStack {
        Spacer()
        Button(LocalizableKey.downloadAction.string) { showDownload = true }.buttonStyle(.borderedProminent)
      }
    case .installed:
      LabeledContent(LocalizableKey.status.string) { Label(LocalizableKey.ready.string, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
      HStack {
        Spacer()
        RemoveModelButton { gemma.remove() }
      }
    case .downloading(let progress):
      LabeledContent(LocalizableKey.status.string) {
        if let fraction = progress.fraction {
          Text(LocalizableKey.downloadingPercent.format(fraction.formatted(.percent.precision(.fractionLength(0))))).monospacedDigit()
        } else {
          Text(LocalizableKey.startingDownload.string)
        }
      }
      HStack {
        Spacer()
        Button(LocalizableKey.showDownload.string) { showDownload = true }
      }
    case .failed(let message):
      LabeledContent(LocalizableKey.status.string) {
        Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
      }
      HStack {
        Spacer()
        Button(LocalizableKey.checkAgain.string) { gemma.refresh() }
        Button(LocalizableKey.downloadAction.string) { showDownload = true }
      }
    }
  }
}

/// Downloads the selected translation model, with progress, size, speed and cancel.
struct ModelDownloadSheet: View {
  @Environment(TranslationModelManager.self) private var gemma
  @Environment(\.dismiss) private var dismiss
  let model: TranslationModel

  var body: some View {
    VStack(spacing: 0) {
      Form {
        Section {
          HStack(spacing: 12) {
            Image(systemName: "character.bubble.fill")
              .font(.system(size: 28))
              .foregroundStyle(.tint)
              .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
              Text(model.name).font(.headline)
              Text("\(model.size) · \(model.id)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
          }
          .padding(.vertical, 4)
        } footer: {
          Text(model.isNLLB ? LocalizableKey.nllbDownloadDescription.string : LocalizableKey.downloadedFromHuggingFaceItRunsOnThisMacWithMlxAndNeverLeavesYourDevice.string)
            .font(.caption).foregroundStyle(.secondary)
        }

        Section(LocalizableKey.progress.string) { progressContent }
      }
      .formStyle(.grouped)
      Divider()
      HStack { buttons }.padding(12)
    }
    .frame(width: 460)
    .frame(minHeight: 340, maxHeight: .infinity)
    .modelDownloadOverlay()
    .onChange(of: gemma.state) { _, state in
      guard state == .installed else { return }
      Task {
        try? await Task.sleep(for: .seconds(1))
        dismiss()
      }
    }
  }

  @ViewBuilder private var progressContent: some View {
    switch gemma.state {
    case .downloading(let progress):
      VStack(alignment: .leading, spacing: 8) {
        if let fraction = progress.fraction {
          HStack {
            Text(LocalizableKey.downloading.string)
            Spacer()
            Text(fraction, format: .percent.precision(.fractionLength(0))).monospacedDigit()
          }
          ProgressView(value: fraction)
          HStack {
            Text(LocalizableKey.downloadBytes.format(progress.completedBytes.formatted(.byteCount(style: .file)), progress.totalBytes.formatted(.byteCount(style: .file))))
            Spacer()
            Text(progress.bytesPerSecond.map { LocalizableKey.downloadSpeed.format(Int64($0).formatted(.byteCount(style: .file))) } ?? "—")
          }
          .font(.callout).foregroundStyle(.secondary).monospacedDigit()
        } else {
          HStack {
            Text(LocalizableKey.preparingDownload.string)
            Spacer()
            ProgressView().controlSize(.small)
          }
        }
      }
      .padding(.vertical, 4)
    case .installed:
      Label(LocalizableKey.downloadedAndReady.string, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
    case .failed(let message):
      Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(3)
    case .unknown, .checking:
      HStack { Text(LocalizableKey.checking.string); Spacer(); ProgressView().controlSize(.small) }
    case .notInstalled:
      Text(LocalizableKey.readyToDownload.string).foregroundStyle(.secondary)
    }
  }

  @ViewBuilder private var buttons: some View {
    switch gemma.state {
    case .downloading:
      Button(LocalizableKey.hide.string) { dismiss() }
      Spacer()
      Button(LocalizableKey.cancelDownload.string, role: .destructive) {
        gemma.cancel()
        Haptics.tap()
        dismiss()
      }
      .keyboardShortcut(.cancelAction)
    case .installed:
      Spacer()
      Button(LocalizableKey.done.string) { dismiss() }.keyboardShortcut(.defaultAction)
    case .failed:
      Spacer()
      Button(LocalizableKey.close.string, role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
      Button(LocalizableKey.retry.string) { gemma.download() }.keyboardShortcut(.defaultAction)
    case .unknown, .checking, .notInstalled:
      Spacer()
      Button(LocalizableKey.cancel.string, role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
      Button(LocalizableKey.downloadAction.string) {
        Haptics.tap()
        gemma.download()
      }
      .keyboardShortcut(.defaultAction)
      .disabled(gemma.state != .notInstalled)
    }
  }
}

struct RemoveModelButton: View {
  let action: () -> Void
  @State private var confirm = false

  var body: some View {
    Button(LocalizableKey.removeModel.string, role: .destructive) { confirm = true }
      .confirmationDialog(LocalizableKey.removeTheDownloadedTranslategemmaModel.string, isPresented: $confirm) {
        Button(LocalizableKey.remove.string, role: .destructive, action: action)
      } message: {
        Text(LocalizableKey.youCanDownloadItAgainAtAnyTime.string)
      }
  }
}
