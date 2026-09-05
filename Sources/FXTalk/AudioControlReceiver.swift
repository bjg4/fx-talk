import AVFoundation
import CoreAudio
import FXTalkCore

/// Reads only the explicitly selected input. No audio is saved or transmitted.
/// All engine work runs off the main thread; detector work has a bounded queue.
final class AudioControlReceiver {
    var onState: ((AudioSignalEvent) -> Void)?
    var onStatus: ((String) -> Void)?
    var onDiagnostic: ((String) -> Void)?
    var onLevel: ((Double) -> Void)?
    var onLost: (() -> Void)?
    var onRestartNeeded: (() -> Void)?
    private static let engineQueue = DispatchQueue(label: "local.fxtalk.audio.engine")
    private let dspQueue = DispatchQueue(label: "local.fxtalk.audio.decode", qos: .userInitiated)
    private let lock = NSLock()
    private var stopped = false
    private var pending = 0
    private var overrun = false
    private var engine: AVAudioEngine?
    private var detector = SymbolDetector()
    private var lastDisplay = 0.0
    private var configObserver: NSObjectProtocol?
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    func start(device: AudioDeviceID) {
        Self.engineQueue.async { [self] in
            guard !isStopped else { return }
            let engine = AVAudioEngine()
            guard let unit = engine.inputNode.audioUnit else { report("Audio input is unavailable."); return }
            var id = device
            guard AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global, 0, &id, UInt32(MemoryLayout<AudioDeviceID>.size)) == noErr else {
                report("Couldn’t open the selected audio input. Reconnect the adapter."); return
            }
            let format = engine.inputNode.inputFormat(forBus: 0)
            guard format.sampleRate == 48000, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
                report("Audio controls need a 48 kHz input. Set this adapter to 48,000 Hz in Audio MIDI Setup."); return
            }
            self.engine = engine
            engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
                guard let self, let channel = buffer.floatChannelData?[0] else { return }
                self.lock.lock()
                let accept = !self.stopped && self.pending < 4
                if accept { self.pending += 1 } else if !self.stopped { self.overrun = true }
                self.lock.unlock()
                guard accept else { return }
                let samples = (0..<Int(buffer.frameLength)).map { channel[$0 * Int(buffer.stride)] }
                self.dspQueue.async { [self] in
                    defer { self.lock.lock(); self.pending -= 1; self.lock.unlock() }
                    guard !self.isStopped else { return }
                    self.lock.lock(); let discontinuity = self.overrun; self.overrun = false; self.lock.unlock()
                    if discontinuity {
                        self.detector = SymbolDetector()
                        DispatchQueue.main.async { [weak self] in
                            self?.onDiagnostic?("Audio processing fell behind; reacquiring the button signal")
                            self?.onLost?()
                        }
                    }
                    let wasLocked = self.detector.locked
                    let events = self.detector.process(samples: samples)
                    let diagnostics = self.detector.drainDiagnostics()
                    let now = ProcessInfo.processInfo.systemUptime
                    if now - self.lastDisplay >= 0.25 {
                        self.lastDisplay = now
                        let peak = Double(samples.map { abs($0) }.max() ?? 0)
                        DispatchQueue.main.async { [weak self] in self?.onLevel?(peak) }
                    }
                    if wasLocked && !self.detector.locked {
                        DispatchQueue.main.async { [weak self] in self?.onLost?() }
                    }
                    if !diagnostics.isEmpty {
                        DispatchQueue.main.async { [weak self] in
                            for line in diagnostics { self?.onDiagnostic?(line) }
                        }
                    }
                    for event in events {
                        DispatchQueue.main.async { [weak self] in
                            guard let self, !self.isStopped else { return }
                            self.onState?(event)
                        }
                    }
                }
            }
            do { try engine.start() }
            catch { report("Couldn’t start audio input: \(error.localizedDescription)"); teardown(); return }
            report("Listening for the mic’s audio signal…")
            // A pinned engine can emit a harmless post-start notification.
            // The format/running check is performed away from the UI thread.
            configObserver = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                object: engine, queue: nil) { [weak self, weak engine] _ in
                Self.engineQueue.async {
                    guard let self, let engine, !self.isStopped else { return }
                    var healthy = false
                    let responsive = Self.bounded {
                        let current = engine.inputNode.inputFormat(forBus: 0)
                        healthy = engine.isRunning && current.sampleRate == format.sampleRate && current.channelCount == format.channelCount
                    }
                    if !responsive || !healthy {
                        self.report("Audio input changed. Reconnect to resume.")
                        self.teardown()
                        DispatchQueue.main.async { [weak self] in self?.onRestartNeeded?() }
                    }
                }
            }
        }
    }
    private func report(_ message: String) { DispatchQueue.main.async { [weak self] in self?.onStatus?(message) } }
    func stop() {
        lock.lock(); stopped = true; lock.unlock()
        Self.engineQueue.async { [self] in teardown() }
    }
    private func teardown() {
        if let observer = configObserver { NotificationCenter.default.removeObserver(observer); configObserver = nil }
        guard let old = engine else { return }
        engine = nil
        Self.bounded { old.inputNode.removeTap(onBus: 0); old.stop() }
    }
    @discardableResult private static func bounded(_ work: @escaping () -> Void) -> Bool {
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread { work(); finished.signal() }
        return finished.wait(timeout: .now() + 1) == .success
    }
}
