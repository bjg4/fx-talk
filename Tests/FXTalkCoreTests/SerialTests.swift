import XCTest
import Darwin
@testable import FXTalkCore

private final class SimulatedMic {
    let master: Int32
    let slave: Int32
    let path: String
    let queue = DispatchQueue(label: "fxtalk.test.mic")
    var timer: DispatchSourceTimer?
    private var buffer = Data()
    private(set) var commands: [String] = []
    init(reply: String?) throws {
        var m: Int32 = -1, s: Int32 = -1
        var name = [CChar](repeating: 0, count: 256)
        guard openpty(&m, &s, &name, nil, nil) == 0 else { throw NSError(domain: "openpty", code: Int(errno)) }
        master = m; slave = s; path = String(cString: name)
        _ = fcntl(master, F_SETFL, O_NONBLOCK)
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 0.005)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var bytes = [UInt8](repeating: 0, count: 4096)
            let n = Darwin.read(self.master, &bytes, bytes.count)
            if n > 0 { self.buffer.append(contentsOf: bytes.prefix(n)) }
            while let index = self.buffer.firstIndex(of: 13) {
                let command = String(decoding: self.buffer[..<index], as: UTF8.self)
                self.buffer.removeSubrange(...index)
                self.commands.append(command)
                if let reply {
                    let response = Array((command + "\r\n" + reply + "\r\n>>> ").utf8)
                    _ = response.withUnsafeBytes { Darwin.write(self.master, $0.baseAddress, response.count) }
                }
            }
        }
        self.timer = timer; timer.resume()
    }
    func stop() -> [String] {
        queue.sync {
            timer?.cancel(); timer = nil
            Darwin.close(master); Darwin.close(slave)
            return commands
        }
    }
}

final class SerialTests: XCTestCase {
    func testRealSerialIOPollsOnlyReadOnlyCommand() throws {
        let mic = try SimulatedMic(reply: "FXT1 1 1 1 1 4095 0.8")
        let link = SerialConnection()
        let received = expectation(description: "Three sensor replies")
        received.expectedFulfillmentCount = 3
        var count = 0
        link.onSnapshot = { sample in
            XCTAssertTrue(sample.paddle); XCTAssertFalse(sample.orange)
            XCTAssertEqual(sample.rawPosition, 4095)
            count += 1
            if count <= 3 { received.fulfill() }
        }
        link.start(path: mic.path)
        wait(for: [received], timeout: 3)
        link.stop()
        let commands = mic.stop()
        XCTAssertGreaterThanOrEqual(commands.count, 3)
        XCTAssertTrue(commands.allSatisfy { $0 + "\r" == DeviceSnapshot.query })
        XCTAssertFalse(commands.contains { $0.contains("\u{03}") || $0.contains("\u{04}") || $0.contains("callback") })
    }
    func testSilentFirmwareStopsAfterThreeQueries() throws {
        let mic = try SimulatedMic(reply: nil)
        let link = SerialConnection()
        let stopped = expectation(description: "Timed out")
        link.onDisconnect = { stopped.fulfill() }
        link.onSnapshot = { _ in XCTFail("Silent device must not fabricate a state") }
        link.start(path: mic.path)
        wait(for: [stopped], timeout: 5)
        XCTAssertEqual(mic.stop().count, 3)
    }
    func testUnsupportedFirmwareStopsImmediately() throws {
        let mic = try SimulatedMic(reply: "AttributeError: module has no attribute 'handle_raw'")
        let link = SerialConnection()
        let stopped = expectation(description: "Unsupported firmware")
        link.onDisconnect = { stopped.fulfill() }
        link.start(path: mic.path)
        wait(for: [stopped], timeout: 3)
        XCTAssertEqual(mic.stop().count, 1)
    }
    func testUnplugSignalsDisconnect() throws {
        let mic = try SimulatedMic(reply: "FXT1 0 1 1 1 100 0")
        let link = SerialConnection()
        let received = expectation(description: "First sample")
        let stopped = expectation(description: "Unplug detected")
        var first = true
        link.onSnapshot = { _ in if first { first = false; received.fulfill() } }
        link.onDisconnect = { stopped.fulfill() }
        link.start(path: mic.path)
        wait(for: [received], timeout: 3)
        _ = mic.stop()
        wait(for: [stopped], timeout: 4)
    }
}
