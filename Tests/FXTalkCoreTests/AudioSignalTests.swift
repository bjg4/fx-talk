import XCTest
@testable import FXTalkCore

final class AudioSignalTests: XCTestCase {
    private func recording(_ words: [(Double, Int)], length: Double, noise: Float = 0) -> [Float] {
        var seed: UInt64 = 123456
        var samples = (0..<Int(length * 48000)).map { _ -> Float in
            seed = seed &* 6364136223846793005 &+ 1
            return (Float((seed >> 32) & 65535) / 32767.5 - 1) * noise
        }
        for (at, word) in words {
            for (index, symbol) in SymbolSet.codebook[word].enumerated() {
                let start = Int((at + Double(index) * 0.04) * 48000)
                for (offset, value) in SymbolSet.samples(symbol: symbol).enumerated() where start + offset < samples.count {
                    samples[start + offset] += Float(value * 0.2)
                }
            }
        }
        return samples
    }
    private func decode(_ samples: [Float], chunk: Int = 997) -> (SymbolDetector, [AudioSignalEvent]) {
        var decoder = SymbolDetector()
        var events: [AudioSignalEvent] = []
        for start in stride(from: 0, to: samples.count, by: chunk) {
            events += decoder.process(samples: Array(samples[start..<min(start + chunk, samples.count)]))
            _ = decoder.drainDiagnostics()
        }
        return (decoder, events)
    }
    func testLocksThenDecodesAllButtonStatesAmidNoise() {
        let words: [(Double, Int)] = [(0.1,0), (0.8,0), (1.5,0), (1.85,1), (2.2,5), (2.55,4), (2.9,0)]
        let (_, events) = decode(recording(words, length: 3.3, noise: 0.015))
        XCTAssertEqual(events, [.init(paddle: false, orange: false), .init(paddle: true, orange: false),
            .init(paddle: true, orange: true), .init(paddle: false, orange: true), .init(paddle: false, orange: false)])
    }
    func testNoOutputBeforeThreePeriodicPilots() {
        let (decoder, events) = decode(recording([(0.1,0), (0.8,0)], length: 1.3))
        XCTAssertFalse(decoder.locked); XCTAssertTrue(events.isEmpty)
    }
    func testLosesLockWhenCableGoesSilent() {
        let (decoder, events) = decode(recording([(0.1,0), (0.8,0), (1.5,0)], length: 4.9))
        XCTAssertFalse(decoder.locked); XCTAssertEqual(events.count, 1)
    }
    func testClippedSignalStillDecodes() {
        let samples = recording([(0.1,0), (0.8,0), (1.5,0), (1.9,1), (2.3,0)], length: 2.7)
            .map { max(-0.06, min(0.06, $0)) }
        let (_, events) = decode(samples, chunk: 512)
        XCTAssertEqual(events.map(\.paddle), [false, true, false])
    }
    func testSpeechBandAndNoiseDoNotTrigger() {
        var samples = recording([], length: 4, noise: 0.08)
        for i in samples.indices {
            let t = Double(i) / 48000
            samples[i] += Float(0.2 * sin(2 * .pi * 700 * t) + 0.12 * sin(2 * .pi * 1800 * t))
        }
        let (decoder, events) = decode(samples)
        XCTAssertFalse(decoder.locked); XCTAssertTrue(events.isEmpty)
    }
    func testChunkBoundariesDoNotChangeDecoding() {
        let samples = recording([(0.1,0), (0.8,0), (1.5,0), (1.9,1), (2.3,0)], length: 2.7)
        XCTAssertEqual(decode(samples, chunk: 333).1, decode(samples, chunk: 4096).1)
    }
    func testAcquiringWhileHeldRequiresReleaseBeforeHotkey() {
        let (_, events) = decode(recording([(0.1,1), (0.8,1), (1.5,1), (1.9,0), (2.3,1)], length: 2.7))
        var router = ControlRouter(debounce: 0)
        let actions = events.enumerated().flatMap { index, event in
            router.update(pressed: event.paddle, at: Double(index), enabled: true, mode: .hold)
        }
        XCTAssertEqual(actions, [.press])
        XCTAssertEqual(router.reset(), [.release])
    }
    func testDamagedFrameNeverBecomesAnOrangePressOrRelease() {
        var samples = recording([(0.1,0), (0.8,0), (1.5,0), (1.9,1), (3.3,1)], length: 3.8)
        // Observed live: a truncated/shifted [0,0,1,1] burst was corrected
        // into orange-held [1,0,1,1], releasing dictation in the process.
        for (index, symbol) in [0,0,1,1].enumerated() {
            let start = Int((2.3 + Double(index) * 0.04) * 48000)
            for (offset, value) in SymbolSet.samples(symbol: symbol).enumerated() {
                samples[start + offset] += Float(value * 0.2)
            }
        }
        let (_, events) = decode(samples)
        XCTAssertEqual(events.map(\.paddle), [false, true, true])
        XCTAssertTrue(events.allSatisfy { !$0.orange })
    }
    func testExtraSymbolInBurstCannotBeShiftedIntoAState() {
        var samples = recording([(0.1,0), (0.8,0), (1.5,0)], length: 2.8)
        for (index, symbol) in [0,1,0,1,1].enumerated() {
            let start = Int((1.9 + Double(index) * 0.04) * 48000)
            for (offset, value) in SymbolSet.samples(symbol: symbol).enumerated() {
                samples[start + offset] += Float(value * 0.2)
            }
        }
        let (_, events) = decode(samples)
        XCTAssertEqual(events, [.init(paddle: false, orange: false)])
    }
    func testLongHoldSurvivesTwoMissingHeartbeatsWithoutRelease() {
        var words: [(Double, Int)] = [(0.1,0), (0.8,0), (1.5,0)]
        for index in 0..<40 where index != 8 && index != 9 {
            words.append((1.9 + Double(index) * 0.7, 1))
        }
        let (decoder, events) = decode(recording(words, length: 29.6, noise: 0.015))
        XCTAssertTrue(decoder.locked)
        XCTAssertEqual(events.count, 39)
        XCTAssertTrue(events.dropFirst().allSatisfy { $0.paddle && !$0.orange })
    }

}
