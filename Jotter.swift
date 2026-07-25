import Cocoa
import SwiftUI
import Combine
import CryptoKit
import ServiceManagement
import Carbon.HIToolbox

// Jotter — clipboard history for your menu bar.
//
// • Click the icon: list opens with fuzzy search focused.
// • Press ⌘⇧V anywhere: keyboard-first list — ↑/↓ + Return, or 1–9.
// • Copied colors (#ff5733, rgb(255,87,51), …) show in their own color.
// • Copied images show a thumbnail; hover for a large preview, click it to copy.
// • ⌘, opens Settings: General (login item, history size, save folder)
//   and History (select + delete saved items).
// • Text history persists to <save folder>/history.json; images to
//   <save folder>/images/*.png.
//
// Best on macOS 13+. Launch-at-login needs a real .app bundle (Xcode build).
// Standalone test run: swiftc -parse-as-library Jotter.swift -o jotter && ./jotter

// MARK: - Model

struct ClipItem: Codable, Hashable, Identifiable {
    enum Kind: String, Codable { case text, image }
    let id: UUID
    let kind: Kind
    var text: String            // content for text items; label like "Image 640×480" for images
    var imageFilename: String?  // PNG file inside <savePath>/images
    var hash: String?           // SHA-256 of image data, used for de-duplication
    var date: Date
    var isFavorite: Bool        // favorites are pinned on top and never evicted

    var dedupKey: String { kind == .text ? "t:\(text)" : "i:\(hash ?? "")" }

    init(id: UUID, kind: Kind, text: String, imageFilename: String?,
         hash: String?, date: Date, isFavorite: Bool = false) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFilename = imageFilename
        self.hash = hash
        self.date = date
        self.isFavorite = isFavorite
    }

    // Custom decoding so history.json files written before favorites
    // existed (no isFavorite key) still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        imageFilename = try c.decodeIfPresent(String.self, forKey: .imageFilename)
        hash = try c.decodeIfPresent(String.self, forKey: .hash)
        date = try c.decode(Date.self, forKey: .date)
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
    }
}

// MARK: - Store: history + settings + persistence

final class ClipboardStore: ObservableObject {

    @Published var history: [ClipItem] = [] {
        didSet { saveHistory() }
    }

    @Published var maxItems: Int {
        didSet {
            UserDefaults.standard.set(maxItems, forKey: "maxItems")
            if history.count > maxItems {
                history = trimmed(history)
            }
        }
    }

    @Published var savePath: String {
        didSet {
            UserDefaults.standard.set(savePath, forKey: "savePath")
            migrateImages(from: oldValue)
            saveHistory()
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private var loaded = false

    init() {
        let defaults = UserDefaults.standard
        maxItems = defaults.object(forKey: "maxItems") as? Int ?? 100

        let appSupport = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Jotter", isDirectory: true)
        savePath = defaults.string(forKey: "savePath") ?? appSupport.path

        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }

        history = loadHistoryFromDisk()
        loaded = true
    }

    var historyFileURL: URL {
        URL(fileURLWithPath: savePath).appendingPathComponent("history.json")
    }

    var imagesDirURL: URL {
        URL(fileURLWithPath: savePath).appendingPathComponent("images", isDirectory: true)
    }

    func imageURL(for item: ClipItem) -> URL? {
        guard let name = item.imageFilename else { return nil }
        return imagesDirURL.appendingPathComponent(name)
    }

    // MARK: Persistence

    private func loadHistoryFromDisk() -> [ClipItem] {
        guard let data = try? Data(contentsOf: historyFileURL) else { return [] }
        if let items = try? JSONDecoder().decode([ClipItem].self, from: data) {
            return trimmed(items)
        }
        // Migrate from the old plain-[String] format.
        if let legacy = try? JSONDecoder().decode([String].self, from: data) {
            return legacy.prefix(maxItems).map {
                ClipItem(id: UUID(), kind: .text, text: $0,
                         imageFilename: nil, hash: nil, date: Date())
            }
        }
        return []
    }

    private func saveHistory() {
        guard loaded else { return }
        do {
            try FileManager.default.createDirectory(
                atPath: savePath, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(history)
            try data.write(to: historyFileURL, options: .atomic)
        } catch {
            NSLog("Jotter: could not save history: \(error)")
        }
        cleanUpOrphanImages()
    }

    /// Delete PNGs no longer referenced by any history item.
    private func cleanUpOrphanImages() {
        let fm = FileManager.default
        let referenced = Set(history.compactMap { $0.imageFilename })
        guard let files = try? fm.contentsOfDirectory(atPath: imagesDirURL.path) else { return }
        for file in files where !referenced.contains(file) {
            try? fm.removeItem(at: imagesDirURL.appendingPathComponent(file))
        }
    }

    /// When the save folder changes, bring referenced images along.
    private func migrateImages(from oldPath: String) {
        guard loaded else { return }
        let fm = FileManager.default
        let oldDir = URL(fileURLWithPath: oldPath).appendingPathComponent("images")
        try? fm.createDirectory(at: imagesDirURL, withIntermediateDirectories: true)
        for item in history where item.kind == .image {
            guard let name = item.imageFilename else { continue }
            let src = oldDir.appendingPathComponent(name)
            let dst = imagesDirURL.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path), !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
    }

    // MARK: Mutations

    /// Keeps every favorite; newest non-favorites fill the remaining slots.
    private func trimmed(_ items: [ClipItem]) -> [ClipItem] {
        var slots = max(maxItems - items.filter(\.isFavorite).count, 0)
        return items.filter { item in
            if item.isFavorite { return true }
            guard slots > 0 else { return false }
            slots -= 1
            return true
        }
    }

    func toggleFavorite(ids: Set<UUID>) {
        var h = history
        for i in h.indices where ids.contains(h[i].id) {
            h[i].isFavorite.toggle()
        }
        history = h
    }

    func addText(_ str: String) {
        var h = history
        let wasFavorite = h.first { $0.dedupKey == "t:\(str)" }?.isFavorite ?? false
        h.removeAll { $0.dedupKey == "t:\(str)" }
        h.insert(ClipItem(id: UUID(), kind: .text, text: str,
                          imageFilename: nil, hash: nil, date: Date(),
                          isFavorite: wasFavorite), at: 0)
        history = trimmed(h)
    }

    func addImage(pngData: Data, pixelWidth: Int, pixelHeight: Int) {
        let hashHex = SHA256.hash(data: pngData)
            .map { String(format: "%02x", $0) }
            .joined()

        // Same image copied again? Just move it to the front.
        if let existing = history.first(where: { $0.dedupKey == "i:\(hashHex)" }) {
            var h = history
            h.removeAll { $0.id == existing.id }
            h.insert(existing, at: 0)
            history = h
            return
        }

        let id = UUID()
        let filename = "\(id.uuidString).png"
        do {
            try FileManager.default.createDirectory(
                at: imagesDirURL, withIntermediateDirectories: true)
            try pngData.write(to: imagesDirURL.appendingPathComponent(filename))
        } catch {
            NSLog("Jotter: could not save image: \(error)")
            return
        }

        var h = history
        h.insert(ClipItem(id: id, kind: .image,
                          text: "Image \(pixelWidth)×\(pixelHeight)",
                          imageFilename: filename, hash: hashHex, date: Date()), at: 0)
        history = trimmed(h)
    }

    func delete(ids: Set<UUID>) {
        history.removeAll { ids.contains($0.id) }
    }

    func clear() {
        history = []
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Jotter: launch-at-login change failed (requires .app bundle): \(error)")
        }
    }
}

// MARK: - Color parsing

enum ColorParser {
    /// Recognizes "#f50", "#ff5733", "ff5733", "#ff5733cc",
    /// "rgb(255, 87, 51)" and "rgba(255, 87, 51, 0.8)".
    static func parse(_ s: String) -> NSColor? {
        let str = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard str.count <= 32 else { return nil }

        // Hex forms
        var hex = str
        let hadHash = hex.hasPrefix("#")
        if hadHash { hex.removeFirst() }
        let isHex = hex.allSatisfy { $0.isHexDigit }
        let hasDigit = hex.contains { $0.isNumber }
        // Bare (no '#') 6/8-char strings must contain a digit, so ordinary
        // words that happen to be hex letters ("decade") don't colorize.
        let lengthOK = (hex.count == 3 && hadHash)
            || ((hex.count == 6 || hex.count == 8) && (hadHash || hasDigit))
        if isHex, lengthOK {
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            var value: UInt64 = 0
            Scanner(string: hex).scanHexInt64(&value)
            if hex.count == 8 {
                return NSColor(srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
                               green: CGFloat((value >> 16) & 0xFF) / 255,
                               blue: CGFloat((value >> 8) & 0xFF) / 255,
                               alpha: CGFloat(value & 0xFF) / 255)
            }
            return NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                           green: CGFloat((value >> 8) & 0xFF) / 255,
                           blue: CGFloat(value & 0xFF) / 255,
                           alpha: 1)
        }

        // rgb()/rgba()
        if str.hasPrefix("rgb") {
            let inner = String(str.drop(while: { $0 != "(" }))
                .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
            let nums = inner
                .split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" })
                .compactMap { Double($0.replacingOccurrences(of: "%", with: "")) }
            if nums.count >= 3, nums[0] <= 255, nums[1] <= 255, nums[2] <= 255 {
                var alpha = nums.count >= 4 ? nums[3] : 1
                if alpha > 1 { alpha /= 100 }   // "80%" style
                return NSColor(srgbRed: nums[0] / 255, green: nums[1] / 255,
                               blue: nums[2] / 255, alpha: alpha)
            }
        }
        return nil
    }

    static func swatch(_ color: NSColor, size: CGFloat = 14) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1),
                                    xRadius: 3, yRadius: 3)
            color.setFill()
            path.fill()
            NSColor.gray.withAlphaComponent(0.5).setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
    }
}

// MARK: - Settings UI (SwiftUI)

/// Builds the Settings window with native toolbar-style tabs
/// (the same look as System Settings), sized per tab.
func makeSettingsWindow(store: ClipboardStore) -> NSWindow {
    let tabs = NSTabViewController()
    tabs.tabStyle = .toolbar

    let generalVC = NSHostingController(
        rootView: GeneralTab(store: store).frame(width: 480, height: 420))
    generalVC.title = "General"        // becomes the window title for this tab
    let general = NSTabViewItem(viewController: generalVC)
    general.label = "General"
    general.image = NSImage(systemSymbolName: "gearshape",
                            accessibilityDescription: nil)
    tabs.addTabViewItem(general)

    let historyVC = NSHostingController(
        rootView: HistoryTab(store: store).frame(width: 480, height: 420))
    historyVC.title = "History"
    let history = NSTabViewItem(viewController: historyVC)
    history.label = "History"
    history.image = NSImage(systemSymbolName: "clock.arrow.circlepath",
                            accessibilityDescription: nil)
    tabs.addTabViewItem(history)

    let aboutVC = NSHostingController(
        rootView: AboutTab().frame(width: 480, height: 420))
    aboutVC.title = "About"
    let about = NSTabViewItem(viewController: aboutVC)
    about.label = "About"
    about.image = NSImage(systemSymbolName: "info.circle",
                          accessibilityDescription: nil)
    tabs.addTabViewItem(about)

    let window = NSWindow(contentViewController: tabs)
    window.title = "Jotter Settings"
    window.styleMask = [.titled, .closable, .miniaturizable]
    window.isReleasedWhenClosed = false
    // The tab controller's fitting size reserves room for an in-content tab
    // picker even in toolbar style; pin the content to the tabs' real size.
    window.setContentSize(NSSize(width: 480, height: 420))
    window.center()
    return window
}

struct GeneralTab: View {
    @ObservedObject var store: ClipboardStore

    var body: some View {
        Form {
            Section {
                Toggle("Start Jotter at login", isOn: $store.launchAtLogin)
            } footer: {
                Text("Requires the app to be built as an .app bundle.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper(value: $store.maxItems, in: 5...1000, step: 5) {
                    Text("Save up to \(store.maxItems) copies")
                }
            }

            Section {
                LabeledContent("Save history to") {
                    HStack(spacing: 8) {
                        Text(store.savePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…") { pickFolder() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            store.savePath = url.path
        }
    }
}

struct HistoryTab: View {
    @ObservedObject var store: ClipboardStore
    @State private var selection = Set<UUID>()

    private var allSelectedAreFavorites: Bool {
        !selection.isEmpty && store.history
            .filter { selection.contains($0.id) }
            .allSatisfy(\.isFavorite)
    }

    var body: some View {
        VStack(spacing: 0) {
            if store.history.isEmpty {
                Spacer()
                Text("No saved items")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                List(selection: $selection) {
                    ForEach(store.history) { item in
                        HStack(spacing: 8) {
                            if item.kind == .image,
                               let url = store.imageURL(for: item),
                               let nsImage = NSImage(contentsOf: url) {
                                Image(nsImage: nsImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .cornerRadius(4)
                            } else if let color = ColorParser.parse(item.text) {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color(nsColor: color))
                                    .frame(width: 14, height: 14)
                            }
                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.yellow)
                            }
                            Text(item.text.replacingOccurrences(of: "\n", with: " "))
                                .lineLimit(1)

                            Spacer(minLength: 12)

                            VStack(alignment: .trailing, spacing: 1) {
                                Text(item.date,
                                     format: .dateTime.month(.abbreviated).day()
                                         .hour().minute())
                                if item.kind == .text {
                                    Text("\(item.text.count) chars")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize()
                        }
                        .padding(.vertical, 2)
                        .help(item.text)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()

            HStack {
                Button("Delete Selected") {
                    store.delete(ids: selection)
                    selection.removeAll()
                }
                .disabled(selection.isEmpty)

                Button(allSelectedAreFavorites ? "★ Unfavorite" : "★ Favorite") {
                    store.toggleFavorite(ids: selection)
                }
                .disabled(selection.isEmpty)

                Spacer()

                Text(selection.isEmpty
                     ? "\(store.history.count) items"
                     : "\(selection.count) of \(store.history.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Delete All", role: .destructive) {
                    store.clear()
                    selection.removeAll()
                }
                .disabled(store.history.isEmpty)
            }
            .padding(12)
        }
    }
}

struct AboutTab: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String ?? "1.0"
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 76, height: 76)
                .padding(.top, 14)
            Text("Jotter")
                .font(.title2.bold())
            Text("Version \(version)")
                .font(.callout)
                .foregroundStyle(.secondary)

            Form {
                Section {
                    LabeledContent("Support") {
                        // Pre-fills the subject line with "[Jotter Support] "
                        Link("ryanchankwanho@gmail.com",
                             destination: URL(string: "mailto:ryanchankwanho@gmail.com"
                                 + "?subject=%5BJotter%20Support%5D%20")!)
                    }
                }
                Section("Privacy") {
                    Text("Jotter runs entirely on this Mac. Clipboard history is "
                         + "stored locally — as plain JSON and PNG files in the "
                         + "folder chosen in General — and never leaves your "
                         + "computer. Items marked as concealed by password "
                         + "managers are never recorded. Anything sensitive you "
                         + "copy stays in the history files until you delete it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Text("© 2026 Ryan Chan Kwan Ho. All rights reserved.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)
        }
    }
}

// MARK: - App

@main
class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSSearchFieldDelegate {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    let store = ClipboardStore()
    var cancellables = Set<AnyCancellable>()
    var thumbCache: [UUID: NSImage] = [:]
    var previewCache: [UUID: NSImage] = [:]

    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var searchItem: NSMenuItem!
    var searchField: NSSearchField!
    var settingsWindow: NSWindow?
    var timer: Timer?
    var hotKeyRef: EventHotKeyRef?
    var openedViaHotkey = false
    var lastChangeCount = NSPasteboard.general.changeCount
    var query = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "doc.on.clipboard",
            accessibilityDescription: "Jotter")

        searchField = NSSearchField(frame: NSRect(x: 12, y: 3, width: 220, height: 26))
        searchField.placeholderString = "Fuzzy search…"
        searchField.delegate = self
        // Stretch with the menu: the container is resized to the menu's final
        // width, and the field follows it, keeping the 12pt side margins.
        searchField.autoresizingMask = [.width]
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 244, height: 32))
        container.autoresizingMask = [.width]
        container.addSubview(searchField)
        searchItem = NSMenuItem()
        searchItem.view = container

        menu = NSMenu()
        menu.delegate = self
        menu.addItem(searchItem)
        statusItem.menu = menu
        refreshHistoryItems()

        store.$history
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshHistoryItems() }
            .store(in: &cancellables)

        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkPasteboard()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        registerHotKey()
    }

    // MARK: Global hotkey (⌘⇧V)

    func registerHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))

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
        // A crowded menu bar (esp. behind a MacBook notch) can leave the
        // status item without a window; fall back to a menu at the cursor.
        if let window = statusItem.button?.window, window.isVisible {
            statusItem.button?.performClick(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        }
    }

    /// Re-opening the app (e.g. double-click in Finder) shows the menu,
    /// so Jotter stays usable even when its icon doesn't fit in the menu bar.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        openMenuFromHotkey()
        return false
    }

    // MARK: Pasteboard polling

    func checkPasteboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount

        let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
        guard pb.data(forType: concealed) == nil else { return }

        // Images win over text, because browser "Copy Image" often includes a
        // URL string alongside the pixels. (Flip the order if you copy from
        // spreadsheets a lot — those put a picture of the cells on the board.)
        if let png = pngData(from: pb), let rep = NSBitmapImageRep(data: png) {
            store.addImage(pngData: png,
                           pixelWidth: rep.pixelsWide,
                           pixelHeight: rep.pixelsHigh)
            return
        }

        guard let str = pb.string(forType: .string),
              !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }

        store.addText(str)
    }

    private func pngData(from pb: NSPasteboard) -> Data? {
        if let png = pb.data(forType: .png) { return png }
        guard let tiff = pb.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Fuzzy matching

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

    /// Fuzzy-matches item labels — so typing "image" also finds pictures.
    /// Favorites always come first, in their own order.
    var filteredHistory: [ClipItem] {
        let base: [ClipItem]
        if query.isEmpty {
            base = store.history
        } else {
            base = store.history
                .compactMap { item in
                    fuzzyScore(query: query, candidate: item.text).map { (item, $0) }
                }
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
        }
        return base.filter(\.isFavorite) + base.filter { !$0.isFavorite }
    }

    // MARK: Search field

    func controlTextDidChange(_ obj: Notification) {
        query = searchField.stringValue
        refreshHistoryItems()
    }

    func menuWillOpen(_ menu: NSMenu) {
        searchField.stringValue = ""
        query = ""
        refreshHistoryItems()

        if !openedViaHotkey {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.searchField.window?.makeFirstResponder(self.searchField)
            }
        }
        openedViaHotkey = false
    }

    // MARK: Images

    func fullImage(for item: ClipItem) -> NSImage? {
        guard let url = store.imageURL(for: item) else { return nil }
        return NSImage(contentsOf: url)
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        if let cached = thumbCache[item.id] { return cached }
        guard let img = fullImage(for: item) else { return nil }
        let thumb = resized(img, maxDimension: 24)
        thumbCache[item.id] = thumb
        return thumb
    }

    func preview(for item: ClipItem) -> NSImage? {
        if let cached = previewCache[item.id] { return cached }
        guard let img = fullImage(for: item) else { return nil }
        let p = resized(img, maxDimension: 320)
        previewCache[item.id] = p
        return p
    }

    func resized(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }
        let scale = min(maxDimension / max(size.width, size.height), 1)
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        return NSImage(size: newSize, flipped: false) { rect in
            image.draw(in: rect)
            return true
        }
    }

    // MARK: Menu building

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

        let favoriteCount = items.filter(\.isFavorite).count

        for (index, item) in items.enumerated() {
            // Favorites sit in their own block above a separator.
            if index == favoriteCount, favoriteCount > 0 {
                menu.addItem(.separator())
            }

            let menuItem: NSMenuItem
            let star = item.isFavorite ? "★ " : ""

            switch item.kind {
            case .text:
                let oneLine = item.text.replacingOccurrences(of: "\n", with: " ")
                let title = star
                    + (oneLine.count > 40 ? String(oneLine.prefix(40)) + "…" : oneLine)
                menuItem = NSMenuItem(title: title,
                                      action: #selector(copyItem(_:)),
                                      keyEquivalent: "")
                menuItem.target = self
                if index < 9 {
                    menuItem.keyEquivalent = "\(index + 1)"
                    menuItem.keyEquivalentModifierMask = []
                }
                // Copied colors render in their own color, with a swatch.
                if let color = ColorParser.parse(item.text) {
                    menuItem.attributedTitle = NSAttributedString(
                        string: title,
                        attributes: [.foregroundColor: color,
                                     .font: NSFont.menuFont(ofSize: 0)])
                    menuItem.image = ColorParser.swatch(color)
                }
                menuItem.toolTip = item.text

            case .image:
                // Hover opens a submenu with a large preview.
                // Items with submenus can't take a click action themselves,
                // so the preview (and a "Copy Image" row) do the copying.
                menuItem = NSMenuItem(title: star + item.text,
                                      action: nil, keyEquivalent: "")
                menuItem.image = thumbnail(for: item)

                let sub = NSMenu()
                let previewItem = NSMenuItem(title: "",
                                             action: #selector(copyItem(_:)),
                                             keyEquivalent: "")
                previewItem.target = self
                previewItem.tag = index
                previewItem.image = preview(for: item)
                sub.addItem(previewItem)
                sub.addItem(.separator())

                let copy = NSMenuItem(title: "Copy Image",
                                      action: #selector(copyItem(_:)),
                                      keyEquivalent: "")
                copy.target = self
                copy.tag = index
                sub.addItem(copy)

                menuItem.submenu = sub
            }

            menuItem.tag = index
            menu.addItem(menuItem)

            // Hold ⌥ and the row becomes a favorite toggle (so does ⌥1–⌥9).
            let alt = NSMenuItem(title: item.isFavorite ? "☆ Unfavorite" : "★ Favorite",
                                 action: #selector(toggleFavorite(_:)),
                                 keyEquivalent: menuItem.keyEquivalent)
            alt.target = self
            alt.tag = index
            alt.keyEquivalentModifierMask = [.option]
            alt.isAlternate = true
            alt.image = menuItem.image
            menu.addItem(alt)
        }

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettings),
                                  keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        let clear = NSMenuItem(title: "Clear History",
                               action: #selector(clearHistory),
                               keyEquivalent: "")
        clear.target = self
        menu.addItem(clear)

        menu.addItem(NSMenuItem(title: "Quit Jotter",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
    }

    // MARK: Actions

    @objc func copyItem(_ sender: NSMenuItem) {
        let items = filteredHistory
        guard items.indices.contains(sender.tag) else { return }
        let item = items[sender.tag]

        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text, forType: .string)
        case .image:
            if let url = store.imageURL(for: item),
               let data = try? Data(contentsOf: url) {
                pb.setData(data, forType: .png)
            }
        }
        lastChangeCount = pb.changeCount   // don't re-add our own write
    }

    @objc func toggleFavorite(_ sender: NSMenuItem) {
        let items = filteredHistory
        guard items.indices.contains(sender.tag) else { return }
        store.toggleFavorite(ids: [items[sender.tag].id])
    }

    @objc func clearHistory() {
        store.clear()
    }

    @objc func openSettings() {
        if settingsWindow == nil {
            settingsWindow = makeSettingsWindow(store: store)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
