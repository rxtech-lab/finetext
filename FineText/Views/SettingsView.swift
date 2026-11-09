import SwiftUI

struct SettingsView: View {
  var body: some View {
    TabView {
      Tab("General", systemImage: "gearshape") { GeneralSettingsView() }
      Tab("Providers", systemImage: "server.rack") { ProvidersSettingsView() }
      Tab("Humanizer", systemImage: "character.bubble") { HumanizerSettingsView() }
    }
    .frame(width: 580, height: 460)
  }
}

// MARK: - General

struct GeneralSettingsView: View {
  @Environment(AppUpdater.self) private var updater
  @Environment(Preferences.self) private var preferences

  var body: some View {
    @Bindable var updater = updater
    Form {
      Section("Default tone per platform") {
        ForEach(Platform.allCases) { platform in
          Picker(platform.title, selection: Binding(get: { preferences.tone(for: platform) }, set: { preferences.setTone($0, for: platform) })) {
            ForEach(Tone.allCases) { Text($0.title).tag($0) }
          }
        }
      }
      Section("Images") {
        LabeledContent("Quick save folder") {
          Button("~/Pictures/FineText") {
            try? FileManager.default.createDirectory(at: Workspace.picturesFolder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Workspace.picturesFolder)
          }
          .buttonStyle(.link)
        }
      }
      Section("Updates") {
        Toggle("Automatically check for updates", isOn: $updater.automaticallyChecks)
          .disabled(!updater.isConfigured)
        LabeledContent("Version", value: AppUpdater.versionString)
        Button("Check for Updates…") { updater.checkForUpdates() }
          .disabled(!updater.isConfigured)
        if !updater.isConfigured {
          Text("Updates are available in release builds only.").font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .formStyle(.grouped)
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
          Label("No providers", systemImage: "server.rack")
        } description: {
          Text("Add an OpenAI-compatible endpoint with its URL and API key to start rewriting.")
        } actions: {
          Button("Add Provider…") { editing = ProviderDraft() }.buttonStyle(.borderedProminent)
        }
      } else {
        List(selection: $selection) {
          ForEach(store.providers) { provider in
            ProviderRow(provider: provider)
              .tag(provider.id)
              .contextMenu {
                Button("Edit…") { edit(provider) }
                Button("Refresh Models") { Task { await store.refresh(provider.id) } }
                Divider()
                Button("Delete", role: .destructive) { pendingDelete = provider }
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
          .help("Add provider")
        Button {
          pendingDelete = selection.flatMap(store.provider)
        } label: { Image(systemName: "minus") }
          .disabled(selection == nil)
          .help("Delete provider")
        Spacer()
        Button("Edit…") { if let provider = selection.flatMap(store.provider) { edit(provider) } }
          .disabled(selection == nil)
        Button("Refresh All") { Task { await store.refreshAll() } }
          .disabled(store.providers.isEmpty)
      }
      .buttonStyle(.borderless)
      .padding(8)
    }
    .sheet(item: $editing) { draft in
      ProviderEditorSheet(draft: draft)
    }
    .confirmationDialog("Delete \(pendingDelete?.name ?? "provider")?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
      Button("Delete", role: .destructive) {
        if let pendingDelete { store.delete(pendingDelete) }
        selection = nil
        pendingDelete = nil
      }
    } message: {
      Text("Its API key is removed from the Keychain.")
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
          Text("\(store.models(for: provider.id, kind: .text).count) text").font(.caption)
          Text("\(store.models(for: provider.id, kind: .image).count) image").font(.caption)
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
            Picker("Preset", selection: Binding(get: { "" }, set: { name in
              if let preset = ProviderStore.presets.first(where: { $0.name == name }) {
                draft.provider.name = preset.name
                draft.provider.baseURL = preset.baseURL
              }
            })) {
              Text("Custom").tag("")
              ForEach(ProviderStore.presets, id: \.name) { Text($0.name).tag($0.name) }
            }
          }
          TextField("Name", text: $draft.provider.name, prompt: Text("My Provider"))
          TextField("Base URL", text: $draft.provider.baseURL, prompt: Text("https://api.openai.com/v1"))
          SecureField("API Key", text: $draft.apiKey, prompt: Text("sk-…  (leave empty for local servers)"))
        } footer: {
          Text("Any OpenAI-compatible endpoint. Models are listed from GET /models and filtered by capability; the key is stored in your Keychain.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Section {
          HStack {
            Button("Test Connection", action: test).disabled(!isValid || testState == .testing)
            Spacer()
            switch testState {
            case .idle: EmptyView()
            case .testing: ProgressView().controlSize(.small)
            case .success(let text, let image):
              Label("\(text) text · \(image) image models", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
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
        Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        Button(draft.isNew ? "Add" : "Save") {
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
  @Environment(TranslateGemmaManager.self) private var gemma
  @AppStorage(DefaultsKey.humanizeRounds) private var rounds = 3
  @AppStorage(DefaultsKey.pivotLanguage) private var pivot = Language.japanese.code
  @AppStorage(DefaultsKey.ollamaURL) private var ollamaURL = "http://localhost:11434"
  @AppStorage(DefaultsKey.gemmaModel) private var model = TranslateGemmaClient.availableModels[0]

  var body: some View {
    Form {
      Section {
        Stepper(value: $rounds, in: 0...5) {
          LabeledContent("Round trips", value: rounds == 0 ? "Off" : "\(rounds)")
        }
        Picker("Pivot language", selection: $pivot) {
          ForEach(Language.all) { Text($0.name).tag($0.code) }
        }
        .disabled(rounds == 0)
      } header: {
        Text("Reduce the AI feel")
      } footer: {
        Text("After each rewrite, TranslateGemma translates the text to the pivot language and back this many times. 0 turns it off and no translation model is used.")
          .font(.caption).foregroundStyle(.secondary)
      }

      Section {
        TextField("Ollama URL", text: $ollamaURL)
          .onSubmit { gemma.refresh() }
        Picker("Model", selection: $model) {
          ForEach(TranslateGemmaClient.availableModels, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: model) { gemma.refresh() }
        statusRow
      } header: {
        Text("TranslateGemma")
      } footer: {
        Text("TranslateGemma is an open translation model from Google. It runs locally through Ollama and is downloaded separately (4B ≈ 3 GB).")
          .font(.caption).foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onAppear { gemma.refresh() }
  }

  @ViewBuilder private var statusRow: some View {
    switch gemma.state {
    case .unknown, .checking:
      LabeledContent("Status") { ProgressView().controlSize(.small) }
    case .serverUnavailable:
      LabeledContent("Status") {
        Label("Ollama is not running", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
      }
      HStack {
        Link("Install Ollama…", destination: TranslateGemmaClient.ollamaDownloadURL)
        Spacer()
        Button("Check Again") { gemma.refresh() }
      }
    case .notInstalled:
      LabeledContent("Status") { Text("Not downloaded").foregroundStyle(.secondary) }
      HStack {
        Spacer()
        Button("Download \(model)") { gemma.download() }.buttonStyle(.borderedProminent)
      }
    case .installed:
      LabeledContent("Status") { Label("Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
      HStack {
        Spacer()
        RemoveModelButton { gemma.remove() }
      }
    case .downloading(let status, let fraction):
      VStack(alignment: .leading, spacing: 6) {
        if let fraction {
          ProgressView(value: fraction) { Text(status) } currentValueLabel: { Text(fraction, format: .percent.precision(.fractionLength(0))) }
        } else {
          ProgressView { Text(status) }
        }
        HStack {
          Spacer()
          Button("Cancel") { gemma.cancel() }
        }
      }
    case .failed(let message):
      LabeledContent("Status") {
        Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red).lineLimit(2)
      }
      HStack {
        Spacer()
        Button("Retry") { gemma.refresh() }
      }
    }
  }
}

struct RemoveModelButton: View {
  let action: () -> Void
  @State private var confirm = false

  var body: some View {
    Button("Remove Model…", role: .destructive) { confirm = true }
      .confirmationDialog("Remove TranslateGemma from Ollama?", isPresented: $confirm) {
        Button("Remove", role: .destructive, action: action)
      } message: {
        Text("You can download it again at any time.")
      }
  }
}
