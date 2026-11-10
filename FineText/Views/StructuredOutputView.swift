import SwiftUI

/// One labelled, editable box per preset field (e.g. an email's subject and body), each with its own copy button.
struct StructuredOutputView: View {
  @Binding var output: String
  let fields: [PresetField]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(fields) { field in
        FieldBox(field: field, text: binding(for: field))
          .frame(maxHeight: field.multiline ? .infinity : nil)
      }
    }
  }

  private func binding(for field: PresetField) -> Binding<String> {
    Binding(
      get: { StructuredOutput.parse(output, fields: fields)?[field.id] ?? "" },
      set: { value in
        var values = StructuredOutput.parse(output, fields: fields) ?? [:]
        values[field.id] = value
        output = StructuredOutput.compose(values, fields: fields)
      }
    )
  }
}

private struct FieldBox: View {
  @Environment(Workspace.self) private var workspace
  let field: PresetField
  @Binding var text: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(field.label.localized).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        Spacer()
        Group {
          if let limit = field.characterLimit {
            Text("\(text.count)/\(limit)").foregroundStyle(text.count > limit ? .red : .secondary)
          } else {
            Text(LocalizableKey.characterCount.format(text.count)).foregroundStyle(.secondary)
          }
        }
        .font(.caption2).monospacedDigit()
        IconButton("doc.on.doc", help: LocalizableKey.copyField.format(field.label.localized)) {
          workspace.copy(text.trimmed)
        }
        .disabled(text.trimmed.isEmpty)
      }
      if field.multiline {
        TextEditor(text: $text)
          .font(.body)
          .scrollContentBackground(.hidden)
          .padding(6)
          .frame(minHeight: 120, maxHeight: .infinity)
          .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
      } else {
        TextField(field.label.localized, text: $text, axis: .vertical)
          .lineLimit(1...3)
          .textFieldStyle(.plain)
          .padding(8)
          .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
          .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
      }
    }
  }
}
