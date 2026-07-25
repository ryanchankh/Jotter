import Cocoa
import Carbon.HIToolbox

// Clipboard history manager — menu bar app with fuzzy search + global hotkey.
//
// • Click the icon: list opens with the search field focused (fuzzy search).
// • Press ⌘⇧V anywhere: list opens keyboard-first — use ↑/↓ + Return,
//   or press 1–9 to grab an item instantly. Esc closes.
// • Selecting an item puts it back on the clipboard (then ⌘V to paste).
//
// Replace AppDelegate.swift in a macOS App project with this file,
// or run standalone: swiftc ClipboardManagerHotkey.swift -o clipman && ./clipman

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var searchItem: NSMenuItem!
    var searchField: NSSearchField!
    var timer: Timer?
    var hotKeyRef: EventHotKeyRef?
    var openedViaHotkey = false
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
        RunLoop.main.add(t, forMode: .common)
        timer = t

        registerHotKey()
    }

    // MARK: - Global hotkey (⌘⇧V) — Carbon, no Accessibility permission needed

    func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

        // C-style callback: recover `self` from userData and open the menu.
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.openMenuFromHotkey() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), nil)

        let hotKeyID = EventHotKeyID(signature: OSType(0x434C_4950), id: 1) // 'CLIP'
        RegisterEventHotKey(UInt32(kVK_ANSI_V),
                            UInt32(cmdKey | shiftKey),
                            hotKeyID,
                            GetApplicationEventTarget(),
                            0,
                            &hotKeyRef)
    }

    func openMenuFromHotkey() {
        openedViaHotkey = true
        statusItem.button?.performClick(nil)   // pops the menu open
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

    func fuzzyScore(query: String, candidate: String) -> Int? {
        if query.isEmpty { return 0 }
        let q = Array(query.lowercased())
        let c = Array(candidate.lowercased())
        guard q.count <= c.count else { return nil }

        var qi = 0, score = 0, streak = 0, lastMatchIndex = -2
        for (i, ch) in c.enumerated() {
            guard qi < q.count else { break }
            if ch == q[qi] {
                streak = (i == lastMatchIndex + 1) ? streak + 1 : 1
                score += 1 + streak * 2
                if i == 0 { score += 8 }
                else if !c[i - 1].isLetter && !c[i - 1].isNumber { score += 5 }
                lastMatchIndex = i
                qi += 1
            }
        }
        guard qi == q.count else { return nil }
        return score - c.count / 20
    }

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

        // Mouse-open: focus search so you can type immediately.
        // Hotkey-open: leave focus on the menu so ↑/↓ and 1–9 work.
        if !openedViaHotkey {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.searchField.window?.makeFirstResponder(self.searchField)
            }
        }
        openedViaHotkey = false
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
            if index < 9 {
                // Plain 1–9 shortcuts, shown in the menu. They fire when the
                // search field isn't focused (i.e. when opened via ⌘⇧V).
                menuItem.keyEquivalent = "\(index + 1)"
                menuItem.keyEquivalentModifierMask = []
            }
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
