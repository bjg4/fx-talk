import Foundation

/// Read-only telemetry from the EP-2350's stock MicroPython console.
/// No callbacks are replaced, and no files, samples or firmware are written.
public struct DeviceSnapshot: Equatable {
    public let paddle: Bool
    public let orange: Bool
    public let middle: Bool
    public let bottom: Bool
    public let rawPosition: Double
    public let position: Double
    public init(paddle: Bool, orange: Bool, middle: Bool = false, bottom: Bool = false,
                rawPosition: Double = 0, position: Double = 0) {
        self.paddle = paddle; self.orange = orange; self.middle = middle; self.bottom = bottom
        self.rawPosition = rawPosition; self.position = position
    }

    public static let query = "import ui;print('FXT1',int(ui.sw(4)),int(ui.sw(2)),int(ui.sw(1)),int(ui.sw(0)),ui.handle_raw(),ui.handle())\r"

    public static func parse(_ raw: String) -> DeviceSnapshot? {
        // The console echoes commands. An echoed print must never become an event.
        var line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if line.hasPrefix(">>> ") { line = String(line.dropFirst(4)) }
        let t = line.split(whereSeparator: { $0.isWhitespace })
        guard t.count == 7, t[0] == "FXT1",
              t[1...4].allSatisfy({ $0 == "0" || $0 == "1" }),
              let rawPosition = Double(t[5]), rawPosition.isFinite,
              let position = Double(t[6]), position.isFinite,
              (0...1).contains(position) else { return nil }
        // Stock firmware reports the three side switches active-low, while
        // the handle's virtual switch is active-high. Confirmed on FX 1.0.9:
        // released state is `0 1 1 1`, not `0 0 0 0`.
        return DeviceSnapshot(paddle: t[1] == "1", orange: t[2] == "0",
                              middle: t[3] == "0", bottom: t[4] == "0",
                              rawPosition: rawPosition, position: position)
    }
}

public struct LineDecoder {
    private var buffer = Data()
    public init() {}
    public mutating func append(_ data: Data) -> [String] {
        buffer.append(data)
        var lines: [String] = []
        while let i = buffer.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            if let text = String(data: buffer[..<i], encoding: .utf8), !text.isEmpty {
                lines.append(text)
            }
            buffer.removeSubrange(...i)
        }
        if buffer.count > 8192 { buffer.removeAll() }
        return lines
    }
}

public enum ActivationMode: String, Codable, CaseIterable {
    case hold, toggle
}

public enum ActivationControl: String, Codable, CaseIterable {
    case paddle, orange
}

public enum ShortcutAction: Equatable {
    case press, release, tap
}

/// Debounced edges; connecting with a squeezed mic never sends a shortcut.
/// Stale input, disabling and reconnecting always release any key we own.
public struct ControlRouter {
    public private(set) var held = false
    private var sawRelease = false
    private var candidate = false
    private var candidateSince: TimeInterval = 0
    private var stable = false
    private var previousMode: ActivationMode?
    public let debounce: TimeInterval

    public init(debounce: TimeInterval = 0.04) { self.debounce = debounce }

    public mutating func reset() -> [ShortcutAction] {
        let actions: [ShortcutAction] = held ? [.release] : []
        held = false; sawRelease = false; stable = false; candidate = false
        candidateSince = 0; previousMode = nil
        return actions
    }

    public mutating func update(pressed: Bool, at now: TimeInterval,
                                enabled: Bool, mode: ActivationMode) -> [ShortcutAction] {
        guard enabled else { return reset() }
        if let old = previousMode, old != mode {
            let actions = reset()
            previousMode = mode
            return actions
        }
        previousMode = mode
        if !sawRelease {
            if !pressed { sawRelease = true; candidateSince = now }
            return []
        }
        if pressed != candidate { candidate = pressed; candidateSince = now }
        guard candidate != stable, now - candidateSince >= debounce else { return [] }
        stable = candidate
        if mode == .toggle { return stable ? [.tap] : [] }
        held = stable
        return stable ? [.press] : [.release]
    }
}

public struct PaddleCalibration: Codable, Equatable {
    public let rest: Double
    public let squeezed: Double
    public init?(rest: Double, squeezed: Double) {
        guard rest.isFinite, squeezed.isFinite, abs(rest - squeezed) > 0.01 else { return nil }
        self.rest = rest; self.squeezed = squeezed
    }
    private enum CodingKeys: String, CodingKey { case rest, squeezed }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let rest = try values.decode(Double.self, forKey: .rest)
        let squeezed = try values.decode(Double.self, forKey: .squeezed)
        guard let value = Self(rest: rest, squeezed: squeezed) else {
            throw DecodingError.dataCorruptedError(forKey: .squeezed, in: values, debugDescription: "Invalid paddle range")
        }
        self = value
    }
    public func fraction(_ raw: Double) -> Double {
        min(1, max(0, (raw - rest) / (squeezed - rest)))
    }
    public func pressed(raw: Double, wasPressed: Bool) -> Bool {
        fraction(raw) >= (wasPressed ? 0.15 : 0.35)
    }
}
