import SwiftUI
import FXTalkCore

struct SettingsView: View {
    @ObservedObject var model: AppModel
    private let orange = Color(red: 0.94, green: 0.31, blue: 0.08)
    @State private var showDiagnostics = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("FX TALK").font(.system(size: 32, weight: .black, design: .rounded)).tracking(-1)
                        Text("Your mic. Your words. Your agents.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: model.shortcutHeld ? "waveform.circle.fill" : "waveform.circle")
                        .font(.system(size: 48)).foregroundStyle(orange)
                }
                HStack(spacing: 10) {
                    Circle().fill(model.connected ? Color.green : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
                    Text(model.deviceStatus).font(.callout)
                    Spacer()
                    Button("Reconnect") { model.reconnect() }.controlSize(.small)
                }
                section("01", "Connect the mic") {
                    Picker("Connection", selection: $model.preferences.transport) {
                        Text("Audio cable only").tag(ControlTransport.audio)
                        Text("USB controls").tag(ControlTransport.usb)
                    }.pickerStyle(.segmented).labelsHidden()
                    Text(model.preferences.transport == .audio
                        ? "FX-MIC → curly audio cable → USB audio adapter → Mac. After the one-time mic setup, its USB socket stays unplugged. Power the mic with two AAA batteries."
                        : "USB-C from the FX-MIC carries button controls. Its 3.5 mm cable carries voice into your USB audio adapter.")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if model.preferences.transport == .usb && model.ports.count > 1 {
                        Picker("USB controls", selection: $model.selectedPort) {
                            Text("Choose a mic").tag("")
                            ForEach(model.ports) { Text($0.name + " · " + $0.path).tag($0.path) }
                        }
                    }
                    HStack {
                        Picker("Audio input", selection: $model.audioSelection) {
                            ForEach(model.inputs) { Text($0.name + ($0.id == model.defaultInput ? " · current" : "")).tag($0.id) }
                        }
                        Button(model.preferences.transport == .audio ? "Listen on this input" : "Use input") { model.applyInput() }.disabled(model.inputs.isEmpty)
                    }
                    Text("Choose the same input in your dictation app. Audio mode listens locally for the mic’s encoded button signals.")
                        .font(.caption).foregroundStyle(.secondary)
                    if model.preferences.transport == .audio {
                        HStack {
                            Image(systemName: "waveform").foregroundStyle(.secondary)
                            ProgressView(value: min(1, model.audioLevel * 3)).frame(width: 120)
                            Text(model.connected ? "Button signal locked" : "Waiting for button signal").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if !model.audioAllowed { Button("Allow audio…") { model.requestAudioAccess() } }
                        }
                    }
                }
                section("02", "Choose your dictation shortcut") {
                    HStack {
                        Picker("Dictation app", selection: $model.preferences.app) {
                            ForEach(DictationApp.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Button("Open app") { model.openTarget() }.disabled(model.preferences.app == .custom)
                    }
                    HStack(spacing: 18) {
                        Text("Activation")
                        if model.preferences.app == .monologue {
                            Text("Hold to talk").foregroundStyle(.secondary)
                            Spacer()
                        } else {
                            Picker("Activation", selection: $model.preferences.mode) {
                                Text("Hold to talk").tag(ActivationMode.hold)
                                Text("Press to toggle").tag(ActivationMode.toggle)
                            }.pickerStyle(.segmented).labelsHidden()
                        }
                    }
                    HStack {
                        Text("Shortcut")
                        Spacer()
                        ShortcutRecorder(shortcut: $model.preferences.shortcut).frame(width: 180, height: 28)
                        Button("Test in 3 seconds") { model.testShortcut() }.disabled(model.testingButton)
                    }
                    Text(model.preferences.app.instructions).font(.callout).foregroundStyle(.secondary)
                    Text("Set both apps to \(model.preferences.shortcut.label). FX Talk sends this shortcut to the active Mac session; your dictation app handles the speech.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                section("03", "Choose your physical control") {
                    Picker("Control", selection: $model.preferences.control) {
                        Text("Large squeeze paddle").tag(ActivationControl.paddle)
                        Text("Orange side button").tag(ActivationControl.orange)
                    }.pickerStyle(.segmented).labelsHidden()
                    if model.preferences.control == .paddle {
                        Toggle("Orange button presses Enter in any app", isOn: $model.preferences.orangeSubmits)
                        if model.preferences.orangeSubmits {
                            Text("Release the paddle, wait for your words to appear, then tap orange. It presses Enter wherever the cursor is, including chats and terminals.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    HStack(spacing: 12) {
                        sensor("Paddle", active: model.snapshot?.paddle == true)
                        sensor("Orange", active: model.snapshot?.orange == true)
                        Spacer()
                        if model.preferences.transport == .usb, let sample = model.snapshot {
                            Text("Raw \(sample.rawPosition, specifier: "%.1f")").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                        }
                    }
                    if model.preferences.transport == .audio {
                        Text("The mic uses clean speech presets. On batteries it sleeps after five idle minutes; squeeze to wake it.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if model.preferences.control == .orange {
                        Text("The orange side button still changes the mic’s sound effect. Use a clean sound for dictation, or choose the paddle.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if model.calibrationStep == 0 {
                        HStack {
                            Text(model.preferences.calibration == nil ? "Using the built-in paddle switch." : "Using your calibrated paddle range.")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Calibrate…") { model.startCalibration() }.disabled(!model.connected)
                            if model.preferences.calibration != nil { Button("Reset") { model.clearCalibration() } }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.calibrationStep == 1 ? "Let go of the paddle, then capture its resting position." : "Squeeze the paddle fully and keep holding it while you capture.")
                            HStack {
                                Button(model.calibrationStep == 1 ? "Capture resting position" : "Capture squeeze") { model.captureCalibration() }
                                Button("Cancel") { model.cancelCalibration() }
                            }
                        }.padding(12).background(orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: model.trusted ? "checkmark.shield" : "keyboard").foregroundStyle(model.trusted ? .green : orange)
                        Text(model.trusted ? "Keyboard control allowed" : "Allow keyboard control in Accessibility")
                        Spacer()
                        if !model.trusted { Button("Allow…") { model.requestAccessibility() } }
                    }
                    Divider()
                    Toggle(isOn: $model.enabled) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(model.enabled ? "Mic shortcuts enabled" : "Enable mic shortcuts").fontWeight(.semibold)
                            Text(model.shortcutStatus)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.switch).disabled(!model.trusted || (model.preferences.transport == .audio && !model.audioAllowed))
                }.padding(16).background(orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                if !model.notice.isEmpty {
                    Label(model.notice, systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup("Connection diagnostics", isExpanded: $showDiagnostics) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(model.preferences.transport == .audio ? "Audio input: " + model.preferences.audioDeviceUID : model.selectedPort)
                        Text(model.events.suffix(30).joined(separator: "\n")).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                        Button("Copy diagnostics") { model.copyDiagnostics() }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }.font(.caption).foregroundStyle(.secondary)
                Text("FX Talk \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development") · Button decoding stays on your Mac. Your chosen dictation app transcribes the speech.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }.padding(28)
        }.frame(minWidth: 640, minHeight: 700).tint(orange)
            .background(Color(nsColor: .windowBackgroundColor))
    }
    private func section<Content: View>(_ number: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(number).font(.system(.caption, design: .monospaced)).foregroundStyle(orange)
                Text(title).font(.headline)
            }
            content()
        }
    }
    private func sensor(_ name: String, active: Bool) -> some View {
        HStack(spacing: 5) {
            Circle().fill(active ? orange : Color.secondary.opacity(0.25)).frame(width: 7, height: 7)
            Text(name).font(.caption)
        }.padding(.horizontal, 10).padding(.vertical, 6).background(.primary.opacity(0.04), in: Capsule())
    }
}
