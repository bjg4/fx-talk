/// Keeps the user's on/off choice separate from temporary suspension.
/// Resuming never activates a control that was already held.
public struct ControlSession: Equatable {
    public enum Phase: Equatable { case awaitingRelease, ready, sleeping }
    public private(set) var enabled: Bool
    public private(set) var phase: Phase = .awaitingRelease

    public init(enabled: Bool = false) { self.enabled = enabled }

    public mutating func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        requireRelease()
    }

    public mutating func sleep() { phase = .sleeping }
    public mutating func wake() { phase = .awaitingRelease }

    public mutating func requireRelease() {
        if phase != .sleeping { phase = .awaitingRelease }
    }

    /// Feed the released report to the edge routers so the next press works.
    public mutating func observe(paddle: Bool, orange: Bool) -> Bool {
        guard enabled, phase != .sleeping else { return false }
        if phase == .awaitingRelease, !paddle, !orange { phase = .ready }
        return phase == .ready
    }
}
