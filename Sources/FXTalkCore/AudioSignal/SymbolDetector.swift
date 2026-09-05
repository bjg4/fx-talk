// Adapted from Tingle, Copyright (c) 2026 Tutor Intelligence, Inc. (MIT).
// See ThirdParty/Tingle-LICENSE.txt. FX Talk transmits full state every 700 ms.
import Foundation

/// Matched-filter decoder for the SymbolSet chirp symbols.
///
/// Pipeline per band (low 17.25k / high 18.75k center):
///   heterodyne to baseband (carrier periods are exactly 64 samples at
///   48k: 23/64 and 25/64 cycles/sample) -> 64-tap lowpass FIR, computed
///   polyphase-style only at decimation instants (48k -> 3k) -> sliding
///   normalized complex correlation against the band's two decimated
///   chirp templates.
///
/// A symbol fires at a correlation peak that clears an absolute
/// normalized threshold AND dominates the sibling template. ~19dB of
/// processing gain (TB = 80) means real symbols sit far above anything
/// noise, speech, or the ting's lo-fi intermod artifacts can produce —
/// no per-window threshold heuristics are needed or present.
///
/// Above detection sits the pilot-acquisition lock (3 periodic
/// level-consistent beacons required before ANY event is emitted;
/// staleness unlocks; single-beacon fast re-lock after sleep) and level
/// self-calibration relative to the pilot's measured output.
public struct SymbolDetector {
    public struct Configuration {
        public var sampleRate: Double = SymbolSet.sampleRate
        /// Normalized correlation (0..1) needed to consider a peak.
        public var corrThreshold = 0.45
        /// Peak must beat the sibling template by this factor.
        public var dominance = 1.6
        /// Refractory per band after a peak (seconds). Symbols arrive
        /// every ~29ms in a word, so this only suppresses double-counting
        /// of one symbol's own correlation cone.
        public var refractory = 0.015
        /// Max age of symbols considered for a word, and the gap bounds
        /// between consecutive symbols of one word.
        public var wordWindow = 0.5
        public var minSymbolGap = 0.015
        public var maxSymbolGap = 0.070
        /// Level gates relative to the pilot EMA (dB).
        public var levelSlackDB = 10.0
        /// Four missed 700 ms heartbeats, with a small scheduling allowance.
        public var staleAfter = 3.0
        /// Absolute plausibility floor for pilot acquisition (dB,
        /// amplitude-estimate units; provisional until live capture).
        public var minPlausibleLevelDB = -60.0
        public init() {}
    }

    public let configuration: Configuration

    // MARK: - DSP state

    private struct BandState {
        let carrierTable: [(re: Double, im: Double)]   // 64-sample period
        let symbols: [Int]                             // template indices
        let templates: [[(re: Double, im: Double)]]    // decimated, 75 taps
        let templateEnergy: [Double]
        var baseband: [(re: Double, im: Double)] = []  // decimated stream ring
        var basebandEnergy: [Double] = []              // running |z|^2 prefix
        var lastPeakAt = -1.0e9                        // seconds
        // rising-peak tracker
        var trackingCorr = 0.0
        var trackingSymbol = -1
        var trackingAt = 0.0
        var trackingLevel = 0.0
    }

    private var bands: [BandState]
    private var rawRing = [Float](repeating: 0, count: 128)
    private var rawIndex = 0            // absolute input sample count
    private static let fir: [Double] = {
        // 64-tap Hamming windowed-sinc lowpass, cutoff 1.3kHz at 48k.
        let n = 64, fc = 1_300.0 / 48_000.0
        var h = [Double](repeating: 0, count: n)
        var sum = 0.0
        for i in 0..<n {
            let m = Double(i) - Double(n - 1) / 2
            let sinc = m == 0 ? 2 * fc : sin(2 * .pi * fc * m) / (.pi * m)
            let w = 0.54 - 0.46 * cos(2 * .pi * Double(i) / Double(n - 1))
            h[i] = sinc * w
            sum += h[i]
        }
        return h.map { $0 / sum }
    }()
    private static let decimation = 16
    private static let templateTaps = SymbolSet.frameCount / decimation   // 75

    // MARK: - Protocol/lock state

    private(set) public var locked = false
    /// True while provisional beacons are actively arriving (pilot
    /// acquisition in progress) — the beacon scanner extends its dwell.
    public private(set) var acquiring = false
    private var provisionalBeacons: [(at: Double, levelDB: Double)] = []
    private var rememberedLevelDB: Double?
    private var beaconLevelEMA: Double?
    private var lastBeaconAt: Double?
    private var beaconInterval: Double?
    public private(set) var signalMarginDB: Double?
    private var diagnosticsBuffer: [String] = []

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
        func carrier(_ cyclesPer64: Int) -> [(re: Double, im: Double)] {
            (0..<64).map { m in
                let a = -2.0 * .pi * Double(cyclesPer64) * Double(m) / 64.0
                return (cos(a), sin(a))
            }
        }
        func decimatedTemplate(_ symbol: Int, table: [(re: Double, im: Double)]) -> [(re: Double, im: Double)] {
            let raw = SymbolSet.samples(symbol: symbol)
            var out: [(re: Double, im: Double)] = []
            var i = Self.decimation - 1
            // Same polyphase path the live signal takes (FIR + heterodyne),
            // so template and signal share filter transients exactly.
            while i < raw.count {
                var re = 0.0, im = 0.0
                for k in 0..<Self.fir.count where i - k >= 0 {
                    let x = raw[i - k]
                    let c = table[(i - k) & 63]
                    re += Self.fir[k] * x * c.re
                    im += Self.fir[k] * x * c.im
                }
                out.append((re, im))
                i += Self.decimation
            }
            return out
        }
        let lowTable = carrier(23)    // 17.25 kHz
        let highTable = carrier(25)   // 18.75 kHz
        func make(_ table: [(re: Double, im: Double)], _ symbols: [Int]) -> BandState {
            let templates = symbols.map { decimatedTemplate($0, table: table) }
            let energies = templates.map { $0.reduce(0.0) { $0 + $1.re * $1.re + $1.im * $1.im } }
            return BandState(carrierTable: table, symbols: symbols, templates: templates, templateEnergy: energies)
        }
        bands = [make(lowTable, [0, 1]), make(highTable, [2, 3])]
    }

    public mutating func drainDiagnostics() -> [String] {
        defer { diagnosticsBuffer.removeAll(keepingCapacity: true) }
        return diagnosticsBuffer
    }

    // MARK: - Streaming

    public mutating func process(samples: [Float]) -> [AudioSignalEvent] {
        var events: [AudioSignalEvent] = []
        for sample in samples {
            rawRing[rawIndex & 127] = sample
            rawIndex += 1
            if rawIndex % Self.decimation == 0, rawIndex >= Self.fir.count {
                for bandIndex in bands.indices {
                    events.append(contentsOf: advanceBand(bandIndex))
                }
            }
        }
        // Lone-symbol resolution + staleness are time-driven.
        events.append(contentsOf: tick(now: now))
        if !locked, !events.isEmpty {
            diagnosticsBuffer.append("unlocked — suppressed: \(events.map(\.logDescription).joined(separator: ","))")
            events = []
        }
        return events
    }

    private var now: Double { Double(rawIndex) / configuration.sampleRate }

    /// One decimated baseband sample for one band, plus correlation.
    private mutating func advanceBand(_ bandIndex: Int) -> [AudioSignalEvent] {
        var band = bands[bandIndex]
        defer { bands[bandIndex] = band }

        var re = 0.0, im = 0.0
        for k in 0..<Self.fir.count {
            let idx = rawIndex - 1 - k
            let x = Double(rawRing[idx & 127])
            let c = band.carrierTable[idx & 63]
            re += Self.fir[k] * x * c.re
            im += Self.fir[k] * x * c.im
        }
        band.baseband.append((re, im))
        let prev = band.basebandEnergy.last ?? 0
        band.basebandEnergy.append(prev + re * re + im * im)
        // Bound memory: keep 2x template length.
        if band.baseband.count > Self.templateTaps * 2 {
            band.baseband.removeFirst(Self.templateTaps)
            band.basebandEnergy.removeFirst(Self.templateTaps)
        }
        guard band.baseband.count >= Self.templateTaps else { return [] }
        guard now - band.lastPeakAt >= configuration.refractory else { return [] }

        // Correlate both templates at the current alignment.
        let n = band.baseband.count
        let windowEnergy = (band.basebandEnergy.last ?? 0)
            - (n > Self.templateTaps ? band.basebandEnergy[n - Self.templateTaps - 1] : 0)
        guard windowEnergy > 0 else { return [] }
        var best = (corr: 0.0, symbol: -1, sibling: 0.0, level: -200.0)
        for (t, template) in band.templates.enumerated() {
            var cre = 0.0, cim = 0.0
            for m in 0..<Self.templateTaps {
                let z = band.baseband[n - Self.templateTaps + m]
                let w = template[m]
                // conj(template) * signal
                cre += w.re * z.re + w.im * z.im
                cim += w.re * z.im - w.im * z.re
            }
            let mag = (cre * cre + cim * cim).squareRoot()
            let norm = mag / (windowEnergy * band.templateEnergy[t]).squareRoot()
            if norm > best.corr {
                let sibling = best.symbol == -1 ? 0 : best.corr
                best = (norm, band.symbols[t], max(sibling, best.sibling),
                        20 * log10(max(mag / band.templateEnergy[t].squareRoot(), 1e-10)))
            } else {
                best.sibling = max(best.sibling, norm)
            }
        }

        // Peak tracking with PEAK-DROP emission: in a word, the next
        // symbol of the same band arrives ~29ms later and the correlation
        // dip between them may not fall below the absolute threshold —
        // emit as soon as the tracked peak has decayed by 25%.
        if best.corr >= configuration.corrThreshold,
           best.corr >= best.sibling * configuration.dominance,
           best.corr >= band.trackingCorr * 0.75 || band.trackingSymbol < 0 {
            if best.corr > band.trackingCorr {
                band.trackingCorr = best.corr
                band.trackingSymbol = best.symbol
                band.trackingAt = now
                band.trackingLevel = best.level
            }
            return []
        }
        if band.trackingSymbol >= 0 {
            let symbol = band.trackingSymbol
            let level = band.trackingLevel
            let at = band.trackingAt
            let corr = band.trackingCorr
            band.trackingSymbol = -1
            band.trackingCorr = 0
            band.lastPeakAt = at
            diagnosticsBuffer.append(String(format: "symbol S%d corr %.2f level %.1fdB", symbol, corr, level))
            signalMarginDB = 0.9 * (signalMarginDB ?? corr * 40) + 0.1 * corr * 40
            return handleSymbol(symbol, at: at, levelDB: level)
        }
        return []
    }

    // MARK: - Codeword protocol + pilot lock

    /// Recent symbol detections awaiting word assembly.
    private var symbolStream: [(symbol: Int, at: Double, levelDB: Double)] = []

    private mutating func handleSymbol(_ symbol: Int, at: Double, levelDB: Double) -> [AudioSignalEvent] {
        var events: [AudioSignalEvent] = []
        if let last = symbolStream.last, at - last.at > configuration.maxSymbolGap {
            events = finishFrame()
        }
        // Bound corrupt bursts, while retaining their last arrival timestamp.
        if symbolStream.count >= 16 { symbolStream.removeFirst() }
        symbolStream.append((symbol, at, levelDB))
        return events
    }

    private mutating func finishFrame() -> [AudioSignalEvent] {
        let word = symbolStream
        symbolStream.removeAll(keepingCapacity: true)
        guard word.count == 4 else {
            if !word.isEmpty { diagnosticsBuffer.append("Incomplete signal burst (\(word.count) symbols) ignored") }
            return []
        }
        for index in 1..<word.count {
            let gap = word[index].at - word[index - 1].at
            guard gap >= configuration.minSymbolGap, gap <= configuration.maxSymbolGap else { return [] }
        }
        let received = word.map(\.symbol)
        // An incomplete or shifted burst can resemble a different codeword
        // after error correction. Require an exact full word and quiet framing,
        // particularly because orange now sends a user message.
        guard let message = SymbolSet.codebook.firstIndex(of: received),
              let state = SymbolSet.Message(rawValue: message) else {
            diagnosticsBuffer.append("Damaged signal frame \(received) ignored")
            return []
        }
        let level = word.map(\.levelDB).reduce(0, +) / 4
        let at = word.last!.at
        switch state {
        case .released: return acquireAndEmit(.init(paddle: false, orange: false), level: level, at: at)
        case .paddleHeld: return acquireAndEmit(.init(paddle: true, orange: false), level: level, at: at)
        case .orangeHeld: return acquireAndEmit(.init(paddle: false, orange: true), level: level, at: at)
        case .bothHeld: return acquireAndEmit(.init(paddle: true, orange: true), level: level, at: at)
        }
    }

    /// Resolve only complete, quiet-delimited bursts. A repeated state report
    /// keeps a long dictation alive; there is no maximum dictation duration.
    private mutating func tick(now: Double) -> [AudioSignalEvent] {
        var events: [AudioSignalEvent] = []
        if let last = symbolStream.last, now - last.at > configuration.maxSymbolGap {
            events = finishFrame()
        }
        if locked, let last = lastBeaconAt, now - last > configuration.staleAfter {
            locked = false
            rememberedLevelDB = beaconLevelEMA
            provisionalBeacons.removeAll()
            acquiring = false
            diagnosticsBuffer.append("No valid button report for 3 seconds — decoder unlocked")
        }
        if acquiring, let lastProvisional = provisionalBeacons.last?.at, now - lastProvisional > 2.0 {
            acquiring = false
        }
        return events
    }

    /// The level a lock (or a lost lock) settled at — survives the detector
    /// by being re-seeded into the next instance, so wake-from-sleep can
    /// fast re-lock on a SINGLE beacon instead of the full 3-beacon
    /// acquisition (device switches used to discard this memory).
    public var levelMemoryDB: Double? { beaconLevelEMA ?? rememberedLevelDB }

    public mutating func seedRememberedLevel(_ levelDB: Double) {
        if rememberedLevelDB == nil { rememberedLevelDB = levelDB }
    }

    private mutating func userEvent(_ event: AudioSignalEvent, level: Double) -> [AudioSignalEvent] {
        guard levelCredible(level) else {
            diagnosticsBuffer.append("\(event.logDescription) level \(String(format: "%.1f", level))dB not credible — dropped")
            return []
        }
        return [event]
    }

    private func levelCredible(_ level: Double) -> Bool {
        guard let reference = beaconLevelEMA ?? rememberedLevelDB ?? provisionalBeacons.last?.levelDB else { return true }
        return level >= reference - configuration.levelSlackDB
    }

    private mutating func acquireAndEmit(_ event: AudioSignalEvent, level: Double, at: Double) -> [AudioSignalEvent] {
        guard level >= configuration.minPlausibleLevelDB else {
            diagnosticsBuffer.append("beacon-shaped pair at \(String(format: "%.1f", level))dB below plausibility floor — ignored")
            return []
        }
        if locked {
            guard levelCredible(level) else { return [] }
            beaconLevelEMA = beaconLevelEMA.map { 0.8 * $0 + 0.2 * level } ?? level
            noteBeacon(at: at)
            return [event]
        }
        if let remembered = rememberedLevelDB, abs(level - remembered) <= 6 {
            locked = true
            beaconLevelEMA = remembered
            noteBeacon(at: at)
            diagnosticsBuffer.append("fast re-lock at \(String(format: "%.1f", level))dB")
            return [event]
        }
        provisionalBeacons = provisionalBeacons.filter { abs(level - $0.levelDB) <= 6 && at - $0.at < 4.0 }
        provisionalBeacons.append((at, level))
        acquiring = true
        if provisionalBeacons.count >= 3 {
            let last3 = provisionalBeacons.suffix(3).map(\.at)
            let i1 = last3[1] - last3[0], i2 = last3[2] - last3[1]
            if i1 > 0.35, i1 < 1.5, i2 > 0.35, i2 < 1.5, abs(i1 - i2) <= 0.25 * max(i1, i2) {
                locked = true
                beaconLevelEMA = provisionalBeacons.suffix(3).map(\.levelDB).reduce(0, +) / 3
                provisionalBeacons.removeAll()
                acquiring = false
                noteBeacon(at: at)
                diagnosticsBuffer.append("beacon pilot locked at \(String(format: "%.1f", beaconLevelEMA!))dB (periodic x3)")
                return [event]
            }
        }
        diagnosticsBuffer.append("provisional beacon at \(String(format: "%.1f", level))dB (\(provisionalBeacons.count) seen) — not locked yet")
        return []
    }

    private mutating func noteBeacon(at: Double) {
        if let last = lastBeaconAt {
            let interval = at - last
            if interval > 0.35, interval < 1.5 {
                beaconInterval = beaconInterval.map { 0.7 * $0 + 0.3 * interval } ?? interval
            }
        }
        lastBeaconAt = at
    }

}
