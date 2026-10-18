import AppKit
import SwiftUI
import MarginstoneCore

@main @MainActor
enum MarginstoneMain {
    static func main() {
        let app = NSApplication.shared; let delegate = AppDelegate()
        app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
        withExtendedLifetime(delegate) {}
    }
}
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var panel: FloatingPanel!
    private var shell: CompanionView!
    private var selectionFollower: SelectionFollower?
    private var missionControlParking: MissionControlParking?
    private var collection: NSWindow?
    private var statusItem: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .aqua)
        model = AppModel(); menus(); makeShell()
        selectionFollower = SelectionFollower(view: shell)
        missionControlParking = MissionControlParking(view: shell)
        shell.movesSideToSide = model.movesSideToSide
        model.movementChanged = { [weak self] enabled in
            guard let self else { return }
            self.shell.movesSideToSide = enabled
            self.shell.menu = self.shellMenu()
            self.statusItem?.menu = self.shellMenu()
        }
        model.companionChanged = { [weak self] companion in self?.updateCompanion(companion) }
        model.openCollection = { [weak self] in self?.showCollection() }
        model.captured = { [weak self] in self?.shell.acknowledge() }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.menu = shellMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(constrainShell), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        updateCompanion(model.companion)
        showCollection(); model.restoreConnection()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showCollection(); return true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.busy {
            let alert = NSAlert(); alert.messageText = "Marginstone is saving to Git."
            alert.informativeText = "Your captures are saved locally. Wait for the current repository operation to finish before quitting."
            alert.runModal(); return .terminateCancel
        }
        return .terminateNow
    }
    private func updateCompanion(_ companion: Companion) {
        shell.setCompanion(companion)
        panel.title = companion.name
        collection?.title = "Marginstone"
        if let artwork = companion.image { NSApp.applicationIconImage = SystemIcons.dock(artwork) }
        menus()
        shell.menu = shellMenu()
        statusItem?.menu = shellMenu()
        if let artwork = companion.image { statusItem?.button?.image = SystemIcons.menu(artwork) }
        statusItem?.button?.toolTip = companion.name
        statusItem?.button?.setAccessibilityLabel(companion.name)
    }
    private func menus() {
        let bar = NSMenu(); let appItem = NSMenuItem(); bar.addItem(appItem)
        let app = NSMenu(title: "Marginstone"); appItem.title = "Marginstone"; appItem.submenu = app
        app.addItem(item("Open collection", #selector(showCollection), "o"))
        app.addItem(item("Capture clipboard", #selector(captureClipboard), "n"))
        app.addItem(item("Settings…", #selector(showSettings), ","))
        app.addItem(.separator()); app.addItem(withTitle: "Quit Marginstone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let fileItem = NSMenuItem(); fileItem.title = "File"; bar.addItem(fileItem)
        let fileMenu = NSMenu(title: "File"); fileItem.submenu = fileMenu
        let export = item("Save excerpts to file…", #selector(saveExcerpts), "s")
        export.keyEquivalentModifierMask = [.command, .shift]; fileMenu.addItem(export)
        let editItem = NSMenuItem(); editItem.title = "Edit"; bar.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = bar
    }
    private func item(_ title: String, _ selector: Selector, _ key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: selector, keyEquivalent: key); result.target = self; return result
    }
    private func shellMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item("Capture clipboard", #selector(captureClipboard)))
        menu.addItem(item("Open collection", #selector(showCollection)))
        menu.addItem(item("Settings…", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(item("Show \(model.companion.name)", #selector(showShell)))
        menu.addItem(item("Hide \(model.companion.name)", #selector(hideShell)))
        menu.addItem(.separator()); menu.addItem(withTitle: "Quit Marginstone", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }
    private func makeShell() {
        let area = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        panel = FloatingPanel(contentRect: NSRect(origin: WanderingMotion.home(area: area, size: NSSize(width: 110, height: 110)), size: NSSize(width: 110, height: 110)), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = model.companion.name; panel.isFloatingPanel = true; panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        shell = CompanionView(frame: NSRect(x: 0, y: 0, width: 110, height: 110))
        shell.capture = { [weak self] payload in
            guard let self else { return }
            do { _ = try self.model.receive(payload) }
            catch { self.model.error = error.localizedDescription; throw error }
        }
        shell.readSelection = { application in try await SelectionCapture.read(from: application) }
        shell.captureFailed = { [weak self] error in self?.model.error = error.localizedDescription }
        shell.openCollection = { [weak self] in self?.showCollection() }
        shell.positionChanged = { [weak self] in if let origin = self?.panel.frame.origin { UserDefaults.standard.set(NSStringFromPoint(origin), forKey: "shellOrigin") } }
        shell.menu = shellMenu(); panel.contentView = shell
        constrainShell(); panel.orderFrontRegardless()
    }
    @objc private func constrainShell() {
        guard panel != nil, let area = (NSScreen.screens.first { $0.visibleFrame.intersects(panel.frame) } ?? NSScreen.main)?.visibleFrame else { return }
        panel.setFrameOrigin(WanderingMotion.home(area: area, size: panel.frame.size))
    }
    @objc private func showSettings() { showCollection(); model.showingSettings = true }
    @objc private func toggleMovement() { model.movesSideToSide.toggle() }
    @objc private func showShell() { constrainShell(); panel.orderFrontRegardless() }
    @objc private func hideShell() { panel.orderOut(nil) }
    @objc private func chooseRepo() { showCollection(); model.chooseRepository() }
    @objc private func saveExcerpts() { model.saveToFile(sourcePath: model.activePath) }
    @objc private func captureClipboard() { model.captureClipboard() }
    @objc private func showCollection() {
        if collection == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 930, height: 790), styleMask: [.titled,.closable,.miniaturizable,.resizable], backing: .buffered, defer: false)
            window.title = "Marginstone"; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: LibraryView(model: model, showCompanion: { [weak self] in self?.showShell() }))
            window.minSize = NSSize(width: 830, height: 730); window.center(); collection = window
        }
        NSApp.activate(ignoringOtherApps: true); collection?.makeKeyAndOrderFront(nil)
    }
}
