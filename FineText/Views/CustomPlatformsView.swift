import SwiftUI

/// The library stays separate from the editor so each action has its own view.
struct CustomPlatformsSheet: View {
  @Environment(Preferences.self) private var preferences
  @Environment(\.dismiss) private var dismiss
  @State private var editing: CustomPlatform?
  @State private var toast: Toast?

  var body: some View {
    NavigationStack {
      Group {
        if preferences.customPlatforms.isEmpty {
          ContentUnavailableView(LocalizableKey.noCustomPlatforms.string, systemImage: "slider.horizontal.3",
                                 description: Text(LocalizableKey.customPlatformsHint.string))
        } else {
          List {
            ForEach(groups, id: \.folder) { group in
              Section {
                ForEach(group.platforms) { row($0) }
              } header: {
                if let folder = group.folder {
                  Label(CustomPlatform.path(folder).joined(separator: " › "), systemImage: "folder")
                }
              }
            }
          }
        }
      }
      .navigationTitle(LocalizableKey.customPlatforms.string)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(LocalizableKey.done.string) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .primaryAction) {
          Button(LocalizableKey.newCustomPlatform.string, systemImage: "plus") {
            Haptics.tap()
            editing = CustomPlatform(name: "", instruction: "")
          }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(width: 440, height: 540)
    .overlay(alignment: .bottom) {
      if let toast {
        Label(toast.message, systemImage: toast.symbol)
          .padding(12)
          .background(.regularMaterial, in: Capsule())
          .padding()
          .allowsHitTesting(false)
      }
    }
    .task(id: toast?.id) {
      guard toast != nil else { return }
      do {
        try await Task.sleep(for: .seconds(2))
        toast = nil
      } catch {}
    }
    .sheet(item: $editing) { platform in
      CustomPlatformEditorSheet(platform: platform) { message, symbol in
        toast = Toast(message: message, symbol: symbol)
        Haptics.success()
      }
    }
  }

  /// Top-level presets first, then one section per submenu path.
  private var groups: [(folder: String?, platforms: [CustomPlatform])] {
    let platforms = preferences.customPlatforms
    let root = platforms.filter { $0.folder == nil }
    let folders = Set(platforms.compactMap(\.folder)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    return (root.isEmpty ? [] : [(nil, root)]) + folders.map { folder in (folder, platforms.filter { $0.folder == folder }) }
  }

  private func row(_ platform: CustomPlatform) -> some View {
    Button {
      Haptics.tap()
      editing = platform
    } label: {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text(platform.name).font(.headline)
          Text(platform.instruction).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
        Spacer()
        Image(systemName: "chevron.right").foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .padding(.vertical, 4)
  }
}

struct CustomPlatformEditorSheet: View {
  @Environment(Preferences.self) private var preferences
  @Environment(\.dismiss) private var dismiss
  @State private var platform: CustomPlatform
  @State private var confirmDelete = false
  @FocusState private var nameFocused: Bool
  let onComplete: (String, String) -> Void

  init(platform: CustomPlatform, onComplete: @escaping (String, String) -> Void) {
    _platform = State(initialValue: platform)
    self.onComplete = onComplete
  }

  private var isExisting: Bool { preferences.customPlatforms.contains { $0.id == platform.id } }
  private var folder: Binding<String> {
    Binding(get: { platform.folder ?? "" }, set: { platform.folder = $0.isEmpty ? nil : $0 })
  }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Form {
          TextField(LocalizableKey.platformName.string, text: $platform.name)
            .focused($nameFocused)
          HStack {
            TextField(LocalizableKey.customPlatformFolder.string, text: folder,
                      prompt: Text(LocalizableKey.customPlatformFolderPrompt.string))
            let existing = CustomPlatform.folders(in: preferences.customPlatforms)
            if !existing.isEmpty {
              Menu {
                Button(LocalizableKey.topLevel.string) { platform.folder = nil }
                Divider()
                ForEach(existing, id: \.self) { path in
                  Button(CustomPlatform.path(path).joined(separator: " › ")) {
                    Haptics.tap()
                    platform.folder = path
                  }
                }
              } label: {
                Image(systemName: "folder")
              }
              .menuStyle(.borderlessButton)
              .fixedSize()
              .help(LocalizableKey.chooseExistingMenu.string)
            }
          }
          Text(LocalizableKey.customPlatformFolderHint.string).font(.caption).foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 6) {
          Text(LocalizableKey.rewriteInstructions.string).font(.headline)
          Text(LocalizableKey.customInstructionHint.string).font(.callout).foregroundStyle(.secondary)
          TextEditor(text: $platform.instruction)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(6)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .accessibilityLabel(LocalizableKey.rewriteInstructions.string)
        }
        .padding(.horizontal, 20)
        if isExisting {
          Button(LocalizableKey.deleteCustomPlatform.string, role: .destructive) { confirmDelete = true }
            .padding(.horizontal, 20)
        }
      }
      .padding(.bottom, 20)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .navigationTitle(isExisting ? LocalizableKey.editCustomPlatform.string : LocalizableKey.newCustomPlatform.string)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(LocalizableKey.cancel.string, role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(LocalizableKey.save.string) {
            let message = isExisting ? LocalizableKey.customPlatformUpdated.string : LocalizableKey.customPlatformSaved.string
            preferences.saveCustomPlatform(platform)
            onComplete(message, "checkmark.circle")
            dismiss()
          }
          .keyboardShortcut(.defaultAction)
          .disabled(platform.name.trimmed.isEmpty || platform.instruction.trimmed.isEmpty)
        }
      }
    }
    .frame(width: 420, height: 560)
    .onAppear { nameFocused = true }
    .confirmationDialog(LocalizableKey.deleteCustomPlatform.string, isPresented: $confirmDelete) {
      Button(LocalizableKey.delete.string, role: .destructive) {
        preferences.deleteCustomPlatform(platform.id)
        onComplete(LocalizableKey.customPlatformDeleted.string, "trash")
        dismiss()
      }
    } message: {
      Text(LocalizableKey.customPlatformHistoryHint.string)
    }
  }
}
