import Foundation

/// One physical press can request one submission. Connecting while held,
/// repeated heartbeats and switching apps while held never send a message.
public struct OrangeSubmitGate {
    private var armed = false
    private var wasPressed = false
    private var lastRequest = -Double.infinity
    public init() {}
    public mutating func reset() { armed = false; wasPressed = false }
    public mutating func update(pressed: Bool, enabled: Bool, canSubmit: Bool, at now: TimeInterval) -> Bool {
        guard enabled else { reset(); return false }
        if !pressed { armed = true; wasPressed = false; return false }
        let edge = armed && !wasPressed
        wasPressed = true
        guard edge, canSubmit, now - lastRequest >= 0.8 else { return false }
        lastRequest = now
        return true
    }
}
