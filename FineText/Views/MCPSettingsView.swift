import AppKit
import SwiftUI

/// Settings → MCP: the local MCP server that lets other apps (such as vc-email) rewrite and humanize with FineText.
struct MCPSettingsView: View {
  @Environment(MCPServer.self) private var server
  @State private var portText = ""
  @State private var showLog = false
  @State private var status: Toast?

  var body: some View {
    @Bindable var server = server
    Form {
      Section {
        Toggle(LocalizableKey.mcpEnableServer.string, isOn: $server.isEnabled)
        LabeledContent(LocalizableKey.mcpStatus.string) { stateLabel }
        LabeledContent(LocalizableKey.mcpURL.string) {
          HStack(spacing: 6) {
            Text(server.url).font(.callout.monospaced()).textSelection(.enabled)
            Button(LocalizableKey.copy.string, systemImage: "doc.on.doc") { copy(server.url) }
              .labelStyle(.iconOnly).buttonStyle(.borderless)
          }
        }
        LabeledContent(LocalizableKey.mcpPort.string) {
          HStack(spacing: 6) {
            TextField("", text: $portText, prompt: Text(String(MCPServer.defaultPort)))
              .frame(width: 80).multilineTextAlignment(.trailing)
              .onSubmit(applyPort)
            Button(LocalizableKey.mcpApplyPort.string, action: applyPort)
              .disabled(Int(portText) == server.port || !(1024...65535).contains(Int(portText) ?? 0))
          }
        }
      } header: {
        Text(LocalizableKey.mcpServer.string)
      } footer: {
        Text(LocalizableKey.mcpDescription.string).font(.caption).foregroundStyle(.secondary)
      }

      Section(LocalizableKey.mcpConnect.string) {
        snippet("claude mcp add --transport http finetext \(server.url)")
        snippet("vc-email -mcp \(server.url)")
      }

      Section(LocalizableKey.mcpTools.string) {
        ForEach(MCPTools.definitions.indices, id: \.self) { index in
          let tool = MCPTools.definitions[index]
          VStack(alignment: .leading, spacing: 2) {
            Text(tool["name"] as? String ?? "").font(.callout.monospaced())
            Text(tool["description"] as? String ?? "").font(.caption).foregroundStyle(.secondary)
          }
        }
      }

      Section(LocalizableKey.mcpRequests.string) {
        LabeledContent(LocalizableKey.mcpRecentRequests.string, value: "\(server.log.count)")
        if server.runningCount > 0 {
          LabeledContent(LocalizableKey.mcpRunningRequests.string, value: "\(server.runningCount)")
        }
        Button(LocalizableKey.mcpViewRequestLog.string) {
          Haptics.tap()
          showLog = true
        }
      }
    }
    .formStyle(.grouped)
    .onAppear { portText = String(server.port) }
    .sheet(isPresented: $showLog) { MCPRequestLogSheet() }
    .overlay(alignment: .bottom) {
      if let status { StatusOverlay(status).id(status.id) }
    }
    .animation(.spring(duration: 0.3), value: status)
  }

  @ViewBuilder private var stateLabel: some View {
    switch server.state {
    case .running: Label(LocalizableKey.mcpRunning.string, systemImage: "circle.fill").foregroundStyle(.green)
    case .starting: Label(LocalizableKey.mcpStarting.string, systemImage: "circle.dotted").foregroundStyle(.secondary)
    case .stopped: Label(LocalizableKey.mcpStopped.string, systemImage: "circle").foregroundStyle(.secondary)
    case .failed(let message): Label(LocalizableKey.mcpFailed.format(message), systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
    }
  }

  private func snippet(_ command: String) -> some View {
    HStack {
      Text(command).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
      Spacer()
      Button(LocalizableKey.copy.string, systemImage: "doc.on.doc") { copy(command) }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
    }
  }

  private func applyPort() {
    guard let value = Int(portText), (1024...65535).contains(value) else {
      Haptics.failure()
      return show(Toast(message: LocalizableKey.mcpInvalidPort.string, symbol: "xmark.octagon", isError: true))
    }
    server.setPort(value)
    Haptics.success()
    show(Toast(message: LocalizableKey.mcpPortUpdated.format(value), symbol: "checkmark.circle"))
  }

  private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    Haptics.success()
    show(Toast(message: LocalizableKey.copiedToClipboard.string, symbol: "doc.on.doc"))
  }

  private func show(_ toast: Toast) {
    status = toast
    Task {
      try? await Task.sleep(for: .seconds(2))
      if status == toast { status = nil }
    }
  }
}

// MARK: - Request log

/// Every MCP request the server answered, newest first, with live progress for running tool calls.
struct MCPRequestLogSheet: View {
  @Environment(MCPServer.self) private var server
  @Environment(\.dismiss) private var dismiss
  @State private var confirmClear = false
  @State private var status: Toast?

  var body: some View {
    NavigationStack {
      Group {
        if server.log.isEmpty {
          ContentUnavailableView(LocalizableKey.mcpNoRequests.string, systemImage: "point.3.connected.trianglepath.dotted",
                                 description: Text(LocalizableKey.mcpNoRequestsHint.string))
        } else {
          List(server.log) { entry in
            NavigationLink { MCPRequestDetailView(entry: entry) } label: { MCPRequestRow(entry: entry) }
          }
        }
      }
      .navigationTitle(LocalizableKey.mcpRequestLog.string)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(LocalizableKey.done.string) { dismiss() }
        }
        ToolbarItem(placement: .destructiveAction) {
          Button(LocalizableKey.mcpClearLog.string, role: .destructive) { confirmClear = true }
            .disabled(server.log.allSatisfy { $0.status == .running })
        }
      }
      .confirmationDialog(LocalizableKey.mcpClearLogConfirm.string, isPresented: $confirmClear) {
        Button(LocalizableKey.mcpClearLog.string, role: .destructive) {
          server.clearLog()
          Haptics.success()
          status = Toast(message: LocalizableKey.mcpLogCleared.string, symbol: "trash")
          Task {
            try? await Task.sleep(for: .seconds(1.6))
            status = nil
          }
        }
      } message: {
        Text(LocalizableKey.mcpClearLogMessage.string)
      }
    }
    .frame(minWidth: 620, idealWidth: 680, maxWidth: .infinity, minHeight: 520, idealHeight: 600, maxHeight: .infinity)
    .overlay(alignment: .bottom) {
      if let status { StatusOverlay(status).id(status.id) }
    }
    .animation(.spring(duration: 0.3), value: status)
  }
}

private struct MCPRequestRow: View {
  let entry: MCPLogEntry

  var body: some View {
    HStack(spacing: 10) {
      MCPStatusIcon(status: entry.status)
      VStack(alignment: .leading, spacing: 2) {
        Text(entry.title).font(.body.monospaced())
        Text(entry.progress.last ?? entry.client).font(.caption).foregroundStyle(.secondary).lineLimit(1)
      }
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(entry.date, style: .time).font(.caption)
        if let duration = entry.duration {
          Text(Duration.seconds(duration).formatted(.units(allowed: [.minutes, .seconds, .milliseconds], width: .narrow, maximumUnitCount: 2)))
            .font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }
}

private struct MCPStatusIcon: View {
  let status: MCPLogEntry.Status

  var body: some View {
    switch status {
    case .running: ProgressView().controlSize(.small)
    case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .failed: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
    case .cancelled: Image(systemName: "stop.circle.fill").foregroundStyle(.orange)
    }
  }
}

private struct MCPRequestDetailView: View {
  let entry: MCPLogEntry
  @State private var copied: Toast?

  var body: some View {
    Form {
      Section {
        LabeledContent(LocalizableKey.mcpMethod.string, value: entry.method)
        if let tool = entry.tool { LabeledContent(LocalizableKey.mcpTool.string, value: tool) }
        LabeledContent(LocalizableKey.mcpClient.string, value: entry.client)
        LabeledContent(LocalizableKey.mcpStatus.string) {
          HStack(spacing: 6) {
            MCPStatusIcon(status: entry.status)
            Text(statusText)
          }
        }
        LabeledContent(LocalizableKey.mcpReceived.string) { Text(entry.date, format: .dateTime) }
      }
      if !entry.progress.isEmpty {
        Section(LocalizableKey.mcpProgress.string) {
          ForEach(Array(entry.progress.enumerated()), id: \.offset) { _, step in
            Text(step).font(.callout)
          }
        }
      }
      payload(LocalizableKey.mcpRequest.string, entry.request)
      if !entry.response.isEmpty { payload(LocalizableKey.mcpResponse.string, entry.response) }
    }
    .formStyle(.grouped)
    .navigationTitle(entry.title)
    .overlay(alignment: .bottom) {
      if let copied { StatusOverlay(copied).id(copied.id) }
    }
    .animation(.spring(duration: 0.3), value: copied)
  }

  private var statusText: String {
    switch entry.status {
    case .running: LocalizableKey.mcpRunning.string
    case .succeeded: LocalizableKey.mcpSucceeded.string
    case .failed(let message): LocalizableKey.mcpFailed.format(message)
    case .cancelled: LocalizableKey.mcpCancelled.string
    }
  }

  private func payload(_ title: String, _ text: String) -> some View {
    Section {
      ScrollView(.horizontal) {
        Text(text).font(.caption.monospaced()).textSelection(.enabled).fixedSize()
      }
    } header: {
      HStack {
        Text(title)
        Spacer()
        Button(LocalizableKey.copy.string, systemImage: "doc.on.doc") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(text, forType: .string)
          Haptics.success()
          let toast = Toast(message: LocalizableKey.copiedToClipboard.string, symbol: "doc.on.doc")
          copied = toast
          Task {
            try? await Task.sleep(for: .seconds(1.6))
            if copied == toast { copied = nil }
          }
        }
        .labelStyle(.iconOnly).buttonStyle(.borderless)
      }
    }
  }
}
