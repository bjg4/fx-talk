import AppKit
import SwiftUI

@main
enum FXTalkApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel!
    private var window: NSWindow!
    private var item: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "FX Talk"
        window.minSize = NSSize(width: 640, height: 600)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.center()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        model.refreshMenu = { [weak self] in self?.refreshMenu() }
        refreshMenu()
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Quit FX Talk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: ""); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        for (title, selector, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        NSApp.mainMenu = main
        showWindow()
    }
    private func refreshMenu() {
        let symbol = model.shortcutHeld ? "waveform.circle.fill" : "waveform"
        item.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "FX Talk")
        item.button?.toolTip = "FX Talk — " + model.shortcutStatus
        let menu = NSMenu()
        let status = menu.addItem(withTitle: model.deviceStatus, action: nil, keyEquivalent: "")
        status.isEnabled = false
        let shortcuts = menu.addItem(withTitle: model.shortcutStatus, action: nil, keyEquivalent: "")
        shortcuts.isEnabled = false
        menu.addItem(.separator())
        let toggle = menu.addItem(withTitle: model.enabled ? "Disable mic shortcuts" : "Enable mic shortcuts", action: #selector(toggleEnabled), keyEquivalent: "")
        toggle.target = self; toggle.isEnabled = model.trusted
        let settings = menu.addItem(withTitle: "Open FX Talk…", action: #selector(showWindow), keyEquivalent: ",")
        settings.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit FX Talk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }
    @objc private func toggleEnabled() { model.enabled.toggle() }
    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); return true
    }
    func applicationWillTerminate(_ notification: Notification) { model.stop() }
}
