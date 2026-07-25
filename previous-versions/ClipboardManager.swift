import Cocoa

// Minimal clipboard history manager for the macOS menu bar.
// Replace the default AppDelegate.swift in a new macOS App (Xcode) project
// with this file, or run standalone: swiftc ClipboardManager.swift -o clipman && ./clipman
// Tip: set LSUIElement = YES in Info.plist to hide the Dock icon.

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    var statusItem: NSStatusItem!
    var timer: Timer?
    var lastChangeCount = NSPasteboard.general.changeCount
    var history: [String] = []
    let maxItems = 25

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Clipboard History")
        rebuildMenu()

        // Poll the pasteboard — macOS offers no change notification API.
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
    }

    func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        // Respect apps (e.g. password managers) that mark data as concealed.
        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard pb.data(forType: concealed) == nil else { return }

        guard let str = pb.string(forType: .string),
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        history.removeAll { $0 == str }   // de-duplicate
        history.insert(str, at: 0)        // newest first
        if history.count > maxItems { history.removeLast() }
        rebuildMenu()
    }

    func rebuildMenu() {
        let menu = NSMenu()

        if history.isEmpty {
            let empty = NSMenuItem(title: "No items yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for (index, item) in history.enumerated() {
            let oneLine = item.replacingOccurrences(of: "\n", with: " ")
            let title = oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine
            let menuItem = NSMenuItem(title: title,
                                      action: #selector(copyItem(_:)),
                                      keyEquivalent: index < 9 ? "\(index + 1)" : "")
            menuItem.tag = index
            menuItem.target = self
            menu.addItem(menuItem)
        }

        menu.addItem(.separator())

        let clear = NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(NSMenuItem(title: "Quit",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))

        statusItem.menu = menu
    }

    @objc func copyItem(_ sender: NSMenuItem) {
        guard history.indices.contains(sender.tag) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(history[sender.tag], forType: .string)
        // Our own write bumps changeCount; sync so we don't re-add it.
        lastChangeCount = pb.changeCount
    }

    @objc func clearHistory() {
        history.removeAll()
        rebuildMenu()
    }
}
