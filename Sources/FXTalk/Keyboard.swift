import AppKit
import ApplicationServices
import SwiftUI

struct Shortcut: Codable, Equatable {
    var keyCode: UInt16 = 2  // D
    var modifiers: UInt64 = CGEventFlags.maskControl.union(.maskAlternate).rawValue
    var keyLabel: String = "D"
    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }
    var label: String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s + keyLabel
    }
}

final class KeyboardOutput {
    private var held: Shortcut?
    private let source = CGEventSource(stateID: .privateState)
    var isTrusted: Bool { AXIsProcessTrusted() }
    func requestAccess() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    @discardableResult func press(_ shortcut: Shortcut) -> Bool {
        guard isTrusted else { return false }
        release()
        var flags: CGEventFlags = []
        for (code, flag) in modifierKeys where shortcut.flags.contains(flag) {
            flags.insert(flag); post(code, down: true, flags: flags)
        }
        post(shortcut.keyCode, down: true, flags: shortcut.flags)
        held = shortcut
        return true
    }
    func release() {
        guard let shortcut = held else { return }
        held = nil
        post(shortcut.keyCode, down: false, flags: shortcut.flags)
        var flags = shortcut.flags
        for (code, flag) in modifierKeys.reversed() where flags.contains(flag) {
            flags.remove(flag); post(code, down: false, flags: flags)
        }
    }
    @discardableResult func tap(_ shortcut: Shortcut) -> Bool {
        let sent = press(shortcut); release(); return sent
    }
    /// One physical orange edge sends one unmodified Return to the active app.
    func sendEnter() -> String {
        guard isTrusted else { return "Enter skipped: keyboard access is missing." }
        guard held == nil else { return "Enter skipped: release the paddle and wait for your text." }
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "the active app"
        let shortcut = Shortcut(keyCode: 36, modifiers: 0, keyLabel: "Return")
        return tap(shortcut) ? "Orange button: Enter sent to \(appName)."
            : "Enter skipped: keyboard access is missing."
    }
    private let modifierKeys: [(CGKeyCode, CGEventFlags)] = [
        (59, .maskControl), (58, .maskAlternate), (56, .maskShift), (55, .maskCommand)
    ]
    private func post(_ code: CGKeyCode, down: Bool, flags: CGEventFlags) {
        guard let e = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
        e.flags = flags
        e.setIntegerValueField(.eventSourceUserData, value: 0x465854414C4B)
        e.post(tap: .cghidEventTap)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var shortcut: Shortcut
    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = button; button.action = #selector(RecorderButton.beginRecording)
        button.toolTip = "Record a shortcut with Control, Option, Shift or Command"
        return button
    }
    func updateNSView(_ button: RecorderButton, context: Context) {
        if !button.recording { button.title = shortcut.label }
        button.savedTitle = shortcut.label
        button.onChange = { shortcut = $0 }
    }
}

final class RecorderButton: NSButton {
    var recording = false
    var savedTitle = "⌃⌥D"
    var onChange: ((Shortcut) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    @objc func beginRecording() {
        recording = true; title = "Press shortcut…"; window?.makeFirstResponder(self)
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { finish(); return }
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard !flags.isEmpty else { title = "Include a modifier key"; NSSound.beep(); return }
        let reserved = flags.contains(.command) && [UInt16(12), 13, 48, 49].contains(event.keyCode)
        guard !reserved else { title = "Choose another shortcut"; NSSound.beep(); return }
        let special: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        let label = special[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        let value = Shortcut(keyCode: event.keyCode, modifiers: UInt64(flags.rawValue), keyLabel: label)
        savedTitle = value.label; onChange?(value); finish()
    }
    private func finish() { recording = false; title = savedTitle; window?.makeFirstResponder(nil) }
    override func resignFirstResponder() -> Bool {
        recording = false; title = savedTitle; return true
    }
}
