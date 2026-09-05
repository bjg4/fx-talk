import AppKit
import AVFoundation
import SwiftUI
import FXTalkCore

enum DictationApp: String, Codable, CaseIterable, Identifiable {
    case aqua = "Aqua Voice", wispr = "Wispr Flow", monologue = "Monologue", custom = "Other app"
    var id: String { rawValue }
    var installedURL: URL? {
        let names = self == .wispr ? ["Wispr Flow", "Wispr"] : [rawValue]
        for name in names {
            for root in ["/Applications", NSHomeDirectory() + "/Applications"] {
                let url = URL(fileURLWithPath: root).appendingPathComponent(name + ".app")
                if FileManager.default.fileExists(atPath: url.path) { return url }
            }
        }
        return nil
    }
    var instructions: String {
        switch self {
        case .aqua: return "In Aqua: Settings → Keybindings. Assign this shortcut to the matching activation mode."
        case .wispr: return "In Flow: Settings → General → Shortcuts. Set Push to talk or Hands-free mode to this shortcut."
        case .monologue: return "Use the matching secondary shortcut in Monologue. FX Talk uses Hold to talk; Monologue’s separate hands-free shortcut isn’t mapped."
        case .custom: return "Give your dictation app the same shortcut and activation mode."
        }
    }
}

enum ControlTransport: String, Codable, CaseIterable { case audio, usb }

struct Preferences: Codable {
    var app = DictationApp.monologue
    var shortcut = Shortcut()
    var control = ActivationControl.paddle
    var mode = ActivationMode.hold
    var calibration: PaddleCalibration?
    var transport = ControlTransport.audio
    var audioDeviceUID = ""
    var orangeSubmits = false
    init() {}
    enum CodingKeys: String, CodingKey { case app, shortcut, control, mode, calibration, transport, audioDeviceUID, orangeSubmits }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        app = try c.decodeIfPresent(DictationApp.self, forKey: .app) ?? .monologue
        shortcut = try c.decodeIfPresent(Shortcut.self, forKey: .shortcut) ?? Shortcut()
        control = try c.decodeIfPresent(ActivationControl.self, forKey: .control) ?? .paddle
        mode = try c.decodeIfPresent(ActivationMode.self, forKey: .mode) ?? .hold
        calibration = try c.decodeIfPresent(PaddleCalibration.self, forKey: .calibration)
        transport = try c.decodeIfPresent(ControlTransport.self, forKey: .transport) ?? .audio
        audioDeviceUID = try c.decodeIfPresent(String.self, forKey: .audioDeviceUID) ?? ""
        orangeSubmits = try c.decodeIfPresent(Bool.self, forKey: .orangeSubmits) ?? false
    }
}

final class AppModel: ObservableObject {
    @Published var preferences = Preferences() { didSet { settingsChanged(previous: oldValue) } }
    @Published var enabled = false { didSet { releaseControls(); refreshMenu?() } }
    @Published var ports: [MicPort] = []
    @Published var selectedPort = "" { didSet { if selectedPort != oldValue { reconnect() } } }
    @Published var deviceStatus = "Connect the FX-MIC with a USB-C data cable."
    @Published var connected = false
    @Published var snapshot: DeviceSnapshot?
    @Published var shortcutHeld = false
    @Published var trusted = false
    @Published var audioAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var audioLevel = 0.0
    @Published var inputs: [AudioInput] = []
    @Published var audioSelection: UInt32 = 0
    @Published var defaultInput: UInt32 = 0
    @Published var notice = ""
    @Published var calibrationStep = 0
    @Published var events: [String] = []
    @Published var testingButton = false
    var refreshMenu: (() -> Void)?

    private let keyboard = KeyboardOutput()
    private var router = ControlRouter()
    private var orangeGate = OrangeSubmitGate()
    private var lastDictationRelease = -Double.infinity
    private var resumePaddleOnWake = false
    private var connection: SerialConnection?
    private var audioReceiver: AudioControlReceiver?
    private var audioDeviceID: UInt32 = 0
    private var generation = UUID()
    private var timer: Timer?
    private var failedPorts: Set<String> = []
    private var lastSampleAt: TimeInterval = 0
    private var lastDisplayAt: TimeInterval = 0
    private var restSample: Double?
    private var paddlePressed = false
    private var lastButtonStates: [Bool] = []
    private var loading = true
    private var sleepObserver: NSObjectProtocol?
    private var preferencesFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FX Talk/preferences.json")
    }

    init() {
        if let data = try? Data(contentsOf: preferencesFile),
           let saved = try? JSONDecoder().decode(Preferences.self, from: data) { preferences = saved }
        loading = false
        refreshHardware()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.tick() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                self?.disconnect(); self?.enabled = false
            }
    }
    private var tickCount = 0
    private func tick() {
        tickCount += 1
        let access = keyboard.isTrusted
        if trusted != access { trusted = access; refreshMenu?() }
        if !access && shortcutHeld { releaseControls() }
        let audioAccess = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        if audioAllowed != audioAccess { audioAllowed = audioAccess; if !audioAccess { disconnect() } }
        let timeout = preferences.transport == .audio ? 3.0 : 1.0
        if connected && ProcessInfo.processInfo.systemUptime - lastSampleAt > timeout {
            log("No valid control report for \(String(format: "%.1f", ProcessInfo.processInfo.systemUptime - lastSampleAt)) seconds; releasing shortcut")
            if preferences.transport == .audio { audioSignalLost() }
            else {
                connected = false; releaseControls()
                deviceStatus = "Waiting for the mic to respond…"; refreshMenu?()
            }
        }
        if tickCount % 4 == 0 { refreshHardware() }
    }
    func refreshHardware() {
        let found = MicPort.discover()
        let previous = Set(ports.map(\.path))
        let current = Set(found.map(\.path))
        failedPorts.subtract(previous.subtracting(current))
        if ports != found { ports = found }
        let audio = AudioInputs.list()
        if audio != inputs { inputs = audio }
        let currentDefault = AudioInputs.systemDefault
        if defaultInput != currentDefault { defaultInput = currentDefault }
        if audioSelection == 0 || !inputs.contains(where: { $0.id == audioSelection }) {
            audioSelection = inputs.first(where: { $0.uid == preferences.audioDeviceUID })?.id
                ?? inputs.first(where: { $0.isUSB })?.id ?? defaultInput
        }
        if preferences.transport == .audio {
            if preferences.audioDeviceUID.isEmpty, let input = inputs.first(where: { $0.isUSB }) {
                preferences.audioDeviceUID = input.uid
            }
            guard audioAllowed else {
                deviceStatus = "Allow audio access to hear the mic’s button signals."
                return
            }
            guard let input = inputs.first(where: { $0.uid == preferences.audioDeviceUID }) else {
                if audioReceiver != nil { disconnect() }
                deviceStatus = "Connect the audio adapter or choose an input."
                return
            }
            if audioReceiver == nil || audioDeviceID != input.id {
                disconnect(); connectAudio(input)
            }
            return
        }
        if selectedPort.isEmpty, found.count == 1 { selectedPort = found[0].path }
        if !selectedPort.isEmpty && !current.contains(selectedPort) {
            disconnect(); selectedPort = found.count == 1 ? found[0].path : ""
        }
        if let port = found.first(where: { $0.path == selectedPort }),
           connection == nil, !failedPorts.contains(port.path) { connect(port.path) }
        if found.isEmpty && connection == nil {
            deviceStatus = "Connect the FX-MIC with a USB-C data cable."
        } else if found.count > 1 && selectedPort.isEmpty {
            deviceStatus = "Choose which EP–2350 to use."
        }
    }
    private func connectAudio(_ input: AudioInput) {
        let token = UUID(); generation = token
        let receiver = AudioControlReceiver()
        audioDeviceID = input.id
        router = ControlRouter(debounce: 0) // The mic debounces and the decoder validates each full state frame.
        receiver.onState = { [weak self] event in
            guard let self, self.generation == token else { return }
            self.receive(.init(paddle: event.paddle, orange: event.orange))
        }
        receiver.onStatus = { [weak self] text in
            guard let self, self.generation == token else { return }
            self.deviceStatus = text; self.log(text); self.refreshMenu?()
        }
        receiver.onDiagnostic = { [weak self] text in
            guard let self, self.generation == token else { return }
            // Keep only decoded-word/lock diagnostics; per-symbol correlation
            // would overwhelm the visible log and redraw the UI constantly.
            if !text.hasPrefix("symbol S") { self.log(text) }
        }
        receiver.onLevel = { [weak self] level in
            guard let self, self.generation == token else { return }
            self.audioLevel = level
        }
        receiver.onLost = { [weak self] in
            guard let self, self.generation == token else { return }
            self.audioSignalLost()
        }
        receiver.onRestartNeeded = { [weak self] in
            guard let self, self.generation == token else { return }
            self.disconnect()
            self.deviceStatus = "Reconnecting audio input…"
        }
        audioReceiver = receiver; receiver.start(device: input.id)
    }
    func requestAudioAccess() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self else { return }
                self.audioAllowed = allowed
                if allowed { self.reconnect() }
                else { self.notice = "Enable FX Talk in System Settings → Privacy & Security → Microphone." }
            }
        }
    }
    private func connect(_ path: String) {
        let token = UUID(); generation = token
        router = ControlRouter()
        let link = SerialConnection()
        link.onSnapshot = { [weak self] sample in
            guard let self, self.generation == token else { return }
            self.receive(sample)
        }
        link.onStatus = { [weak self] text in
            guard let self, self.generation == token else { return }
            self.deviceStatus = text; self.log(text); self.refreshMenu?()
        }
        link.onDisconnect = { [weak self] in
            guard let self, self.generation == token else { return }
            self.failedPorts.insert(path); self.connection = nil; self.connected = false
            self.releaseControls(); self.refreshMenu?()
        }
        connection = link; link.start(path: path)
    }
    func reconnect() {
        disconnect(); failedPorts.removeAll(); refreshHardware()
    }
    private func disconnect() {
        generation = UUID(); connection?.stop(); connection = nil
        audioReceiver?.stop(); audioReceiver = nil; audioDeviceID = 0; audioLevel = 0
        connected = false; snapshot = nil; lastButtonStates = []; releaseControls()
    }
    private func audioSignalLost() {
        if connected {
            // A known, released mic that sleeps may wake with the next squeeze.
            // Initial connections and connections lost while held still require
            // release first. Orange is always rearmed separately after release.
            let mayWake = enabled && !shortcutHeld && snapshot?.paddle == false
            connected = false; releaseControls(); resumePaddleOnWake = mayWake
        }
        deviceStatus = "Mic signal paused — squeeze to wake, or check the audio cable."
        refreshMenu?()
    }
    private func receive(_ sample: DeviceSnapshot) {
        let now = ProcessInfo.processInfo.systemUptime
        let first = !connected
        let wakingFromReleased = first && resumePaddleOnWake
        if first { resumePaddleOnWake = false }
        lastSampleAt = now
        if first { connected = true; deviceStatus = preferences.transport == .audio ? "Audio controls connected — USB not needed" : "USB controls connected"; refreshMenu?() }
        let states = [sample.paddle, sample.orange, sample.middle, sample.bottom]
        // Route every sensor reply, but avoid rebuilding the settings view at
        // the serial polling rate. Button edges still update it immediately.
        if states != lastButtonStates || now - lastDisplayAt >= 0.2 {
            if snapshot != sample { snapshot = sample }
            lastDisplayAt = now
        }
        if !lastButtonStates.isEmpty && states != lastButtonStates {
            let labels = ["Paddle", "Orange side button", "Middle button", "Sample button"]
            for i in states.indices where states[i] != lastButtonStates[i] {
                log("\(labels[i]) \(states[i] ? "pressed" : "released")")
            }
        }
        lastButtonStates = states
        if preferences.transport == .usb, let calibration = preferences.calibration {
            paddlePressed = calibration.pressed(raw: sample.rawPosition, wasPressed: paddlePressed)
        } else { paddlePressed = sample.paddle }
        let pressed = preferences.control == .paddle ? paddlePressed : sample.orange
        let canSend = enabled && trusted && calibrationStep == 0 && !testingButton
        if wakingFromReleased && canSend && preferences.control == .paddle && preferences.mode == .hold {
            _ = router.update(pressed: false, at: now, enabled: true, mode: .hold)
            log("Known mic woke from idle; paddle ready")
        }
        for action in router.update(pressed: pressed, at: now, enabled: canSend, mode: preferences.mode) {
            send(action)
        }
        let maySubmit = canSend && !sample.paddle && !shortcutHeld && now - lastDictationRelease >= 0.15
        if orangeGate.update(pressed: sample.orange,
            enabled: canSend && preferences.orangeSubmits && preferences.control == .paddle,
            canSubmit: maySubmit, at: now) {
            let result = keyboard.sendEnter()
            log(result); notice = result
        }

    }
    private func send(_ action: ShortcutAction) {
        switch action {
        case .press:
            guard targetIsRunning else { notice = "Open \(preferences.app.rawValue) before enabling the mic."; return }
            shortcutHeld = keyboard.press(preferences.shortcut)
            if shortcutHeld { log("Shortcut held: \(preferences.shortcut.label)") }
        case .release:
            lastDictationRelease = ProcessInfo.processInfo.systemUptime
            keyboard.release(); shortcutHeld = false; log("Shortcut released")
        case .tap:
            guard targetIsRunning else { notice = "Open \(preferences.app.rawValue) before using the mic."; return }
            if keyboard.tap(preferences.shortcut) { log("Toggle shortcut sent: \(preferences.shortcut.label)") }
        }
        refreshMenu?()
    }
    private var targetIsRunning: Bool {
        guard preferences.app != .custom else { return true }
        guard let url = preferences.app.installedURL,
              let id = Bundle(url: url)?.bundleIdentifier else { return false }
        return !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
    }
    private func releaseControls() {
        resumePaddleOnWake = false
        _ = router.reset(); orangeGate.reset(); keyboard.release(); shortcutHeld = false; paddlePressed = false
    }
    private func settingsChanged(previous: Preferences) {
        guard !loading else { return }
        if preferences.app == .monologue && preferences.mode != .hold {
            preferences.mode = .hold; return
        }
        releaseControls()
        if preferences.transport != previous.transport || preferences.audioDeviceUID != previous.audioDeviceUID {
            DispatchQueue.main.async { [weak self] in self?.reconnect() }
        }
        do {
            try FileManager.default.createDirectory(at: preferencesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(preferences).write(to: preferencesFile, options: .atomic)
        } catch { notice = "Couldn’t save settings: \(error.localizedDescription)" }
    }
    func openTarget() {
        guard let url = preferences.app.installedURL else { notice = "\(preferences.app.rawValue) isn’t installed."; return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }
    func requestAccessibility() { keyboard.requestAccess() }
    func applyInput() {
        if preferences.transport == .audio {
            guard let input = inputs.first(where: { $0.id == audioSelection }) else { return }
            preferences.audioDeviceUID = input.uid
            if audioAllowed { reconnect() } else { requestAudioAccess() }
            notice = "Listening on \(input.name). Use this same input in your dictation app."
            return
        }
        notice = AudioInputs.setDefault(audioSelection)
            ? "Mac input updated. Select System Default or this same input in your dictation app."
            : "Couldn’t select that input. Reconnect the adapter and try again."
        defaultInput = AudioInputs.systemDefault
    }
    func startCalibration() {
        guard connected, preferences.transport == .usb else { notice = "Calibration is available in USB mode. Audio mode debounces the paddle on the mic."; return }
        releaseControls(); restSample = nil; calibrationStep = 1
    }
    func captureCalibration() {
        guard connected, let snapshot else { notice = "The mic disconnected. Reconnect and try again."; return }
        if calibrationStep == 1 { restSample = snapshot.rawPosition; calibrationStep = 2; return }
        guard let restSample, let value = PaddleCalibration(rest: restSample, squeezed: snapshot.rawPosition) else {
            notice = "The handle didn’t move enough. Release it and try calibration again."
            calibrationStep = 1; return
        }
        preferences.calibration = value; calibrationStep = 0
        notice = "Paddle calibrated. Release it before your first dictation."
    }
    func cancelCalibration() { calibrationStep = 0; releaseControls() }
    func clearCalibration() { preferences.calibration = nil; notice = "Using the mic’s built-in paddle switch." }
    func testShortcut() {
        guard trusted else { requestAccessibility(); return }
        guard targetIsRunning else { notice = "Open \(preferences.app.rawValue), then test again."; return }
        testingButton = true; releaseControls(); notice = "Switch to a text field. Testing in 3 seconds…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.testingButton else { return }
            if self.preferences.mode == .toggle {
                self.send(.tap); self.testingButton = false
                self.notice = "Toggle sent. Use your dictation app’s shortcut to stop."
            } else {
                self.send(.press); self.notice = "Test shortcut held for 3 seconds…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                    guard let self else { return }
                    self.send(.release); self.testingButton = false
                    self.notice = "Test finished. If nothing happened, check the app’s matching shortcut."
                }
            }
        }
    }
    func log(_ text: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        events.append("\(timestamp)  \(text)"); if events.count > 100 { events.removeFirst(events.count - 100) }
    }
    func copyDiagnostics() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development"
        let report = "FX Talk \(version)\n\(ProcessInfo.processInfo.operatingSystemVersionString)\nStatus: \(deviceStatus)\nTransport: \(preferences.transport.rawValue)\nAudio UID: \(preferences.audioDeviceUID)\nPort: \(selectedPort)\nTarget: \(preferences.app.rawValue)\nShortcut: \(preferences.shortcut.label)\nMode: \(preferences.mode.rawValue)\nAccessibility: \(trusted)\nInputs: \(inputs.map(\.name).joined(separator: ", "))\n\n" + events.joined(separator: "\n")
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(report, forType: .string)
        notice = "Diagnostics copied. They contain device controls, not audio or transcripts."
    }
    func stop() { testingButton = false; timer?.invalidate(); disconnect() }
}
