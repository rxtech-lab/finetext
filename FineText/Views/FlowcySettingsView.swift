import RxAuthSwift
import RxAuthSwiftUI
import AppKit
import SwiftUI

/// Settings → Flowcy: account status, available models and sign-out. Sign-in opens a sheet with
/// RxAuthSwift's native form.
struct FlowcySettingsView: View {
  @Environment(ProviderStore.self) private var store
  @State private var showSignIn = false
  @State private var confirmSignOut = false
  @State private var signingOut = false
  @State private var status: Toast?

  var body: some View {
    let flowcy = store.flowcy
    Form {
      Section {
        LabeledContent(LocalizableKey.status.string) {
          switch flowcy.isConfigured ? flowcy.manager.authState : .unauthenticated {
          case .unknown:
            ProgressView().controlSize(.small)
          case .authenticated:
            Label(LocalizableKey.flowcySignedInAs.format(Self.accountName(flowcy.user)), systemImage: "checkmark.circle.fill")
              .foregroundStyle(.green)
          case .unauthenticated:
            Label(LocalizableKey.flowcyNotSignedIn.string, systemImage: "person.crop.circle.badge.xmark").foregroundStyle(.secondary)
          }
        }
        if flowcy.isSignedIn {
          if let name = flowcy.user?.name, !name.isEmpty { LabeledContent(LocalizableKey.flowcyName.string, value: name) }
          if let email = flowcy.user?.email, !email.isEmpty { LabeledContent(LocalizableKey.flowcyEmail.string, value: email) }
          Button(LocalizableKey.flowcySignOut.string, role: .destructive) {
            Haptics.tap()
            confirmSignOut = true
          }
        } else {
          Button(LocalizableKey.flowcySignIn.string) {
            Haptics.tap()
            showSignIn = true
          }
          .disabled(!flowcy.isConfigured || flowcy.manager.authState == .unknown)
        }
      } header: {
        Text(LocalizableKey.flowcyAccount.string)
      } footer: {
        Text(flowcy.isConfigured ? LocalizableKey.flowcyDescription.string : LocalizableKey.flowcyNotConfigured.string)
          .font(.caption).foregroundStyle(.secondary)
      }
      if flowcy.isSignedIn {
        Section {
          if flowcy.models.isEmpty {
            Text(flowcy.loadingModels ? LocalizableKey.loadingModels.string : LocalizableKey.flowcyNoModels.string)
              .foregroundStyle(.secondary)
          }
          ForEach(flowcy.models) { model in
            LabeledContent(model.alias) {
              Text(model.modelId).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            }
          }
          Button(LocalizableKey.refreshModels.string) {
            Haptics.tap()
            Task { await flowcy.loadModels() }
          }
          .disabled(flowcy.loadingModels)
        } header: {
          Text(LocalizableKey.flowcyModels.string)
        } footer: {
          if let error = flowcy.modelError { Text(error).font(.caption).foregroundStyle(.red) }
        }
      }
      if flowcy.isSignedIn {
        Section {
          FlowcyUsageView(flowcy: flowcy)
          Button(LocalizableKey.refreshUsage.string) {
            Haptics.tap()
            Task { await flowcy.loadUsage() }
          }
          .disabled(flowcy.loadingUsage)
        } header: {
          Text(LocalizableKey.flowcyUsage.string)
        } footer: {
          Text(LocalizableKey.flowcyUsageHint.string).font(.caption).foregroundStyle(.secondary)
        }
      }
      Section(LocalizableKey.flowcyServer.string) {
        LabeledContent {
          Button(Browser.chromeInstalled ? LocalizableKey.openInChrome.string : LocalizableKey.openInBrowser.string) {
            Haptics.tap()
            Browser.openPreferringChrome(FlowcyAccount.baseURL)
          }
        } label: {
          Text(FlowcyAccount.baseURL.absoluteString).font(.caption.monospaced()).textSelection(.enabled)
        }
      }
    }
    .formStyle(.grouped)
    .task { await flowcy.loadUsage() }
    .sheet(isPresented: $showSignIn) {
      FlowcySignInSheet { show(Toast(message: LocalizableKey.flowcySignedIn.string, symbol: "checkmark.circle")) }
    }
    .confirmationDialog(LocalizableKey.flowcySignOutConfirm.string, isPresented: $confirmSignOut) {
      Button(LocalizableKey.flowcySignOut.string, role: .destructive) { signOut(flowcy) }
    } message: {
      Text(LocalizableKey.flowcySignOutMessage.string)
    }
    .overlay(alignment: .bottom) {
      if signingOut {
        StatusOverlay(Toast(message: LocalizableKey.flowcySigningOut.string, symbol: "rectangle.portrait.and.arrow.right"), progress: true)
      } else if let status {
        StatusOverlay(status).id(status.id)
      }
    }
    .animation(.spring(duration: 0.3), value: status)
    .animation(.spring(duration: 0.3), value: signingOut)
  }

  static func accountName(_ user: User?) -> String {
    user?.email ?? user?.name ?? user?.id ?? ""
  }

  private func signOut(_ flowcy: FlowcyAccount) {
    signingOut = true
    Task {
      await flowcy.signOut()
      signingOut = false
      Haptics.success()
      show(Toast(message: LocalizableKey.flowcySignedOut.string, symbol: "checkmark.circle"))
    }
  }

  private func show(_ toast: Toast) {
    status = toast
    Task {
      try? await Task.sleep(for: .seconds(2.5))
      if status == toast { status = nil }
    }
  }
}

/// RxAuthSwift's native email/password (and, when entitled, passkey) form.
struct FlowcySignInSheet: View {
  @Environment(ProviderStore.self) private var store
  @Environment(\.dismiss) private var dismiss
  let onSignedIn: () -> Void

  var body: some View {
    let flowcy = store.flowcy
    RxSignInView(
      manager: flowcy.manager,
      appearance: RxSignInAppearance(
        icon: .systemImage("wand.and.sparkles"),
        title: LocalizedStringKey(LocalizableKey.flowcySignInTitle.string),
        subtitle: LocalizedStringKey(LocalizableKey.flowcySignInSubtitle.string),
        accentColor: .accentColor
      ),
      onAuthSuccess: {
        Haptics.success()
        flowcy.didSignIn()
        onSignedIn()
        dismiss()
      },
      onAuthFailed: { _ in Haptics.failure() }
    )
    .overlay(alignment: .topTrailing) {
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.cancelAction)
      .help(LocalizableKey.close.string)
      .padding(12)
    }
    .frame(width: 520)
    .frame(minHeight: 600, maxHeight: .infinity)
  }
}

/// Flowcy plan spend windows (5 hours, 7 days, 30 days) as usage bars.
struct FlowcyUsageView: View {
  let flowcy: FlowcyAccount

  var body: some View {
    if flowcy.usage.isEmpty {
      HStack {
        if flowcy.loadingUsage { ProgressView().controlSize(.small) }
        Text(flowcy.loadingUsage ? LocalizableKey.flowcyUsageLoading.string : (flowcy.usageError ?? LocalizableKey.flowcyUsageEmpty.string))
          .foregroundStyle(flowcy.usageError == nil ? Color.secondary : Color.red)
      }
    } else {
      ForEach(flowcy.usage) { meter in
        VStack(alignment: .leading, spacing: 4) {
          HStack {
            Text(Self.title(meter.key))
            Spacer()
            if let fraction = meter.fraction {
              Text(fraction, format: .percent.precision(.fractionLength(0)))
                .monospacedDigit().foregroundStyle(.secondary)
            }
          }
          if let fraction = meter.fraction {
            ProgressView(value: fraction).tint(fraction >= 0.9 ? .red : fraction >= 0.7 ? .orange : .accentColor)
          }
          if let resets = meter.resetsAt {
            Text(LocalizableKey.flowcyUsageResets.format(resets.formatted(.relative(presentation: .named))))
              .font(.caption).foregroundStyle(.secondary)
          }
        }
        .padding(.vertical, 2)
      }
      if let error = flowcy.usageError {
        Text(error).font(.caption).foregroundStyle(.red)
      }
    }
  }

  static func title(_ key: String) -> String {
    switch key {
    case "agent_cost_5h": LocalizableKey.flowcyUsage5h.string
    case "agent_cost_7d": LocalizableKey.flowcyUsage7d.string
    case "agent_cost_30d": LocalizableKey.flowcyUsage30d.string
    default: key
    }
  }
}

enum Browser {
  private static let chromeID = "com.google.Chrome"
  static var chromeInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) != nil }

  /// Opens the URL in Google Chrome, or the default browser when Chrome is not installed.
  static func openPreferringChrome(_ url: URL) {
    guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeID) else {
      NSWorkspace.shared.open(url)
      return
    }
    NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
  }
}
