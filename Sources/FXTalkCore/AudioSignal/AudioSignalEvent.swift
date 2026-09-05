import Foundation

public struct AudioSignalEvent: Equatable {
    public let paddle: Bool
    public let orange: Bool
    public var logDescription: String { "Audio state: paddle \(paddle ? "down" : "up"), orange \(orange ? "down" : "up")" }
    public init(paddle: Bool, orange: Bool) { self.paddle = paddle; self.orange = orange }
}
