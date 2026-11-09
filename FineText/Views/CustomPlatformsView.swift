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
          List(preferences.customPlatforms) { platform in
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

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Form {
          TextField(LocalizableKey.platformName.string, text: $platform.name)
            .focused($nameFocused)
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
    .frame(width: 420, height: 500)
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
