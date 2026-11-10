import AppKit
import SwiftUI

/// A menu entry described as data, so the same tree can back a SwiftUI menu or a lazily built `NSMenu`.
struct MenuEntry {
  enum Kind {
    case action(@MainActor () -> Void)
    case submenu(@MainActor () -> [MenuEntry])
    case header
    case note
    case separator
  }

  var title: String
  var symbol: String?
  var checked = false
  var enabled = true
  var kind: Kind

  static func action(_ title: String, symbol: String? = nil, checked: Bool = false, enabled: Bool = true,
                     perform: @escaping @MainActor () -> Void) -> MenuEntry {
    MenuEntry(title: title, symbol: symbol, checked: checked, enabled: enabled, kind: .action(perform))
  }

  static func submenu(_ title: String, symbol: String? = nil, checked: Bool = false,
                      items: @escaping @MainActor () -> [MenuEntry]) -> MenuEntry {
    MenuEntry(title: title, symbol: symbol, checked: checked, kind: .submenu(items))
  }

  static func header(_ title: String) -> MenuEntry { MenuEntry(title: title, kind: .header) }
  static func note(_ title: String) -> MenuEntry { MenuEntry(title: title, enabled: false, kind: .note) }
  static let separator = MenuEntry(title: "", kind: .separator)
}

/// A pull-down button whose submenus are built only when they open.
///
/// SwiftUI builds a whole `Menu` tree up front. Nesting a model picker (hundreds of models per
/// provider) under every preset and language made the first open create thousands of items and
/// freeze the app; this builds one level at a time instead.
struct LazyPullDownMenu: NSViewRepresentable {
  let title: String
  var symbol: String?
  let items: @MainActor () -> [MenuEntry]

  func makeCoordinator() -> Coordinator { Coordinator() }

  func makeNSView(context: Context) -> LazyPopUpButton {
    let button = LazyPopUpButton(frame: .zero, pullsDown: true)
    button.bezelStyle = .push
    button.setContentHuggingPriority(.required, for: .horizontal)
    let menu = LazyNSMenu()
    menu.delegate = context.coordinator
    menu.addItem(NSMenuItem())
    button.menu = menu
    return button
  }

  func updateNSView(_ button: LazyPopUpButton, context: Context) {
    guard let menu = button.menu as? LazyNSMenu else { return }
    menu.builder = items
    let titleItem = menu.items.first ?? NSMenuItem()
    titleItem.title = title
    titleItem.image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    button.imagePosition = symbol == nil ? .noImage : .imageLeading
    button.isEnabled = context.environment.isEnabled
    button.titleChanged()
  }

  final class LazyPopUpButton: NSPopUpButton {
    private var titleSize: NSSize?

    /// Size the button to its title, not to the widest item of the (temporarily) populated menu.
    func titleChanged() {
      titleSize = nil
      invalidateIntrinsicContentSize()
    }

    override var intrinsicContentSize: NSSize {
      if let titleSize { return titleSize }
      guard let menu, menu.items.count > 1 else { return super.intrinsicContentSize }
      let cell = NSPopUpButtonCell(textCell: "", pullsDown: true)
      cell.bezelStyle = bezelStyle
      cell.font = font
      cell.imagePosition = imagePosition
      let measure = NSMenu()
      if let first = menu.items.first { measure.addItem(first.copy() as! NSMenuItem) }
      cell.menu = measure
      let size = cell.cellSize
      titleSize = size
      return size
    }
  }

  @MainActor final class LazyNSMenu: NSMenu {
    var builder: (@MainActor () -> [MenuEntry])?
    /// Pull-down buttons show their first item as the button title, so it must stay in place.
    var keepsTitleItem = true
  }

  @MainActor final class Coordinator: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
      guard let menu = menu as? LazyNSMenu, let builder = menu.builder else { return }
      let titleItem = menu.keepsTitleItem ? menu.items.first : nil
      menu.removeAllItems()
      if let titleItem { menu.addItem(titleItem) }
      for entry in builder() { menu.addItem(item(for: entry)) }
    }

    private func item(for entry: MenuEntry) -> NSMenuItem {
      switch entry.kind {
      case .separator:
        return .separator()
      case .header:
        return .sectionHeader(title: entry.title)
      case .note:
        let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
      case .action(let perform):
        let item = ActionItem(title: entry.title, perform: perform)
        item.isEnabled = entry.enabled
        decorate(item, entry)
        return item
      case .submenu(let items):
        let item = NSMenuItem(title: entry.title, action: nil, keyEquivalent: "")
        let submenu = LazyNSMenu(title: entry.title)
        submenu.keepsTitleItem = false
        submenu.builder = items
        submenu.delegate = self
        // A placeholder makes AppKit draw the submenu arrow before the submenu is built.
        submenu.addItem(NSMenuItem(title: "…", action: nil, keyEquivalent: ""))
        item.submenu = submenu
        decorate(item, entry)
        return item
      }
    }

    private func decorate(_ item: NSMenuItem, _ entry: MenuEntry) {
      item.state = entry.checked ? .on : .off
      item.image = entry.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    }
  }

  @MainActor final class ActionItem: NSMenuItem {
    private let perform: @MainActor () -> Void

    init(title: String, perform: @escaping @MainActor () -> Void) {
      self.perform = perform
      super.init(title: title, action: #selector(fire), keyEquivalent: "")
      target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func fire() { perform() }
  }
}

/// Renders a small `MenuEntry` tree inside a SwiftUI `Menu`. Use `LazyPullDownMenu` for large trees.
struct MenuEntriesView: View {
  let entries: [MenuEntry]

  var body: some View {
    ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
      switch entry.kind {
      case .separator: Divider()
      case .header: Text(entry.title).font(.caption)
      case .note: Text(entry.title)
      case .action(let perform):
        Button(action: perform) { label(entry) }.disabled(!entry.enabled)
      case .submenu(let items):
        Menu { MenuEntriesView(entries: items()) } label: { label(entry) }
      }
    }
  }

  @ViewBuilder private func label(_ entry: MenuEntry) -> some View {
    if entry.checked { Label(entry.title, systemImage: "checkmark") }
    else if let symbol = entry.symbol { Label(entry.title, systemImage: symbol) }
    else { Text(entry.title) }
  }
}
