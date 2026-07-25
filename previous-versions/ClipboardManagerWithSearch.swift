import Cocoa

// Clipboard history manager with live search, for the macOS menu bar.
// Replace AppDelegate.swift in a macOS App project with this file,
// or run standalone: swiftc ClipboardManagerWithSearch.swift -o clipman && ./clipman

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var searchItem: NSMenuItem!
    var searchField: NSSearchField!
    var timer: Timer?
    var lastChangeCount = NSPasteboard.general.changeCount
    var history: [String] = []
    var query = ""
    let maxItems = 100

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clipboard History")

        // Search field embedded in the first menu item.
        searchField = NSSearchField(frame: NSRect(x: 10, y: 2, width: 220, height: 28))
        searchField.placeholderString = "Search clipboard…"
        searchField.delegate = self
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 32))
        container.addSubview(searchField)
        searchItem = NSMenuItem()
        searchItem.view = container

        menu = NSMenu()
        menu.delegate = self
        menu.addItem(searchItem)
        statusItem.menu = menu
        refreshHistoryItems()

        // .common mode keeps the timer firing even while the menu is open.
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Pasteboard polling

    func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Skip data marked concealed (password managers etc.)
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard pb.data(forType: concealed) == nil else { return }

        guard let str = pb.string(forType: .string),
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        history.removeAll { $0 == str }
        history.insert(str, at: 0)
        if history.count > maxItems { history.removeLast() }
        refreshHistoryItems()
    }

    // MARK: - Search

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        refreshHistoryItems()
    }

    func menuWillOpen(_ menu: NSMenu) {
        // Start fresh and focus the field so the user can type right away.
        searchField.stringValue = ""
        query = ""
        refreshHistoryItems()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.searchField.window?.makeFirstResponder(self.searchField)
        }
    }

    // MARK: - Menu building

    var filteredHistory: [String] {
        query.isEmpty
            ? history
            : history.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    func refreshHistoryItems() {
        // Keep the search item at index 0; rebuild everything below it.
        while menu.items.count > 1 { menu.removeItem(at: 1) }

        let items = filteredHistory
        if items.isEmpty {
            let empty = NSMenuItem(
                title: query.isEmpty ? "No items yet" : "No matches",
                action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for (index, item) in items.enumerated() {
            let oneLine = item.replacingOccurrences(of: "\n", with: " ")
            let title = oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine
            let menuItem = NSMenuItem(title: title,
                                      action: #selector(copyItem(_:)),
                                      keyEquivalent: "")
            menuItem.tag = index
            menuItem.target = self
            menuItem.toolTip = item   // hover to see the full text
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    // MARK: - Actions

    @objc func copyItem(_ sender: NSMenuItem) {
        let items = filteredHistory
        guard items.indices.contains(sender.tag) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(items[sender.tag], forType: .string)
        lastChangeCount = pb.changeCount   // don't re-add our own write
    }

    @objc func clearHistory() {
        history.removeAll()
        refreshHistoryItems()
    }
}
