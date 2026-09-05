import XCTest
@testable import FXTalkCore

final class OrangeSubmitTests: XCTestCase {
    func testRequiresReleaseAndSendsOncePerPress() {
        var gate = OrangeSubmitGate()
        XCTAssertFalse(gate.update(pressed: true, enabled: true, canSubmit: true, at: 0))
        XCTAssertFalse(gate.update(pressed: false, enabled: true, canSubmit: true, at: 1))
        XCTAssertTrue(gate.update(pressed: true, enabled: true, canSubmit: true, at: 2))
        XCTAssertFalse(gate.update(pressed: true, enabled: true, canSubmit: true, at: 3))
        XCTAssertFalse(gate.update(pressed: false, enabled: true, canSubmit: true, at: 4))
        XCTAssertTrue(gate.update(pressed: true, enabled: true, canSubmit: true, at: 5))
    }
    func testBlockedPressIsNotDeferredUntilFocusOrDictationChanges() {
        var gate = OrangeSubmitGate()
        _ = gate.update(pressed: false, enabled: true, canSubmit: true, at: 0)
        XCTAssertFalse(gate.update(pressed: true, enabled: true, canSubmit: false, at: 1))
        XCTAssertFalse(gate.update(pressed: true, enabled: true, canSubmit: true, at: 2))
    }
    func testDisconnectionAndDisablingRearmOnlyAfterRelease() {
        var gate = OrangeSubmitGate()
        _ = gate.update(pressed: false, enabled: true, canSubmit: true, at: 0)
        gate.reset()
        XCTAssertFalse(gate.update(pressed: true, enabled: true, canSubmit: true, at: 1))
        _ = gate.update(pressed: false, enabled: true, canSubmit: true, at: 2)
        _ = gate.update(pressed: false, enabled: false, canSubmit: true, at: 3)
        XCTAssertFalse(gate.update(pressed: true, enabled: true, canSubmit: true, at: 4))
    }
}
