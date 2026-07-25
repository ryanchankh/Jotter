import Cocoa

// Clipboard history manager with fuzzy search, for the macOS menu bar.
// Click the icon → recent list + search bar. Typing fuzzy-filters the list
// (characters must appear in order: "cbm" matches "ClipboardManager").
// Replace AppDelegate.swift in a macOS App project with this file,
// or run standalone: swiftc ClipboardManagerFuzzy.swift -o clipman && ./clipman

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

        searchField = NSSearchField(frame: NSRect(x: 10, y: 2, width: 220, height: 28))
        searchField.placeholderString = "Fuzzy search…"
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

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(t, forMode: .common)   // keeps firing while menu is open
        timer = t
    }

    // MARK: - Pasteboard polling

    func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

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

    // MARK: - Fuzzy matching

    /// Returns a relevance score if every character of `query` appears in
    /// order within `candidate` (case-insensitive), or nil if no match.
    /// Higher = better. Bonuses for consecutive runs and word-start matches.
    func fuzzyScore(query: String, candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard q.count <= c.count else { return nil }

        var qi = 0
        var score = 0
        var streak = 0
        var lastMatchIndex = -2

        for (i, ch) in c.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                streak = (i == lastMatchIndex + 1) ? streak + 1 : 1
                score += 1 + streak * 2               // reward consecutive runs
                if i == 0 { score += 8 }              // match at very start
                else if !c[i - 1].isLetter && !c[i - 1].isNumber {
                    score += 5                        // match at word boundary
                }
                lastMatchIndex = i
                qi += 1
            }
        }

        guard qi == q.count else { return nil }       // every query char must match
        score -= c.count / 20                         // slight bias toward shorter items
        return score
    }

    /// While searching: matches sorted by score. Otherwise: most recent first.
    var filteredHistory: [String] {
        if query.isEmpty { return history }
        return history
            .compactMap { item in
                fuzzyScore(query: query, candidate: item).map { (item, $0) }
            }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    // MARK: - Search field

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        refreshHistoryItems()
    }

    func menuWillOpen(_ menu: NSMenu) {
        searchField.stringValue = ""
        query = ""
        refreshHistoryItems()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.searchField.window?.makeFirstResponder(self.searchField)
        }
    }

    // MARK: - Menu building

    func refreshHistoryItems() {
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
            menuItem.toolTip = item
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
        lastChangeCount = pb.changeCount
    }

    @objc func clearHistory() {
        history.removeAll()
        refreshHistoryItems()
    }
}
