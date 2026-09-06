import XCTest
@testable import FXTalkCore

final class ControlSessionTests: XCTestCase {
    func testSleepPreservesEnabledChoiceAndIgnoresReportsUntilWake() {
        var session = ControlSession(enabled: true)
        XCTAssertTrue(session.observe(paddle: false, orange: false))
        session.sleep()
        XCTAssertTrue(session.enabled)
        XCTAssertFalse(session.observe(paddle: false, orange: false))
        XCTAssertFalse(session.observe(paddle: true, orange: true))
        session.requireRelease() // Disconnect cleanup must not end suspension.
        XCTAssertEqual(session.phase, .sleeping)
        session.wake()
        XCTAssertTrue(session.enabled)
        XCTAssertEqual(session.phase, .awaitingRelease)
    }

    func testWakeRequiresBothControlsReleasedThenNextPressWorksOnce() {
        var session = ControlSession(enabled: true)
        var paddle = ControlRouter(debounce: 0)
        var orange = OrangeSubmitGate()
        _ = session.observe(paddle: false, orange: false)
        _ = paddle.update(pressed: false, at: 0, enabled: true, mode: .hold)
        XCTAssertEqual(paddle.update(pressed: true, at: 1, enabled: true, mode: .hold), [.press])
        session.sleep()
        XCTAssertEqual(paddle.reset(), [.release])
        orange.reset()
        session.wake()

        for (time, p, o) in [(2.0, true, true), (3.0, false, true), (4.0, true, false)] {
            let ready = session.observe(paddle: p, orange: o)
            XCTAssertFalse(ready)
            XCTAssertEqual(paddle.update(pressed: p, at: time, enabled: ready, mode: .hold), [])
            XCTAssertFalse(orange.update(pressed: o, enabled: ready, canSubmit: !p, at: time))
        }
        let ready = session.observe(paddle: false, orange: false)
        XCTAssertTrue(ready)
        XCTAssertEqual(paddle.update(pressed: false, at: 5, enabled: ready, mode: .hold), [])
        XCTAssertFalse(orange.update(pressed: false, enabled: ready, canSubmit: true, at: 5))
        XCTAssertEqual(paddle.update(pressed: true, at: 6, enabled: ready, mode: .hold), [.press])
        XCTAssertEqual(paddle.update(pressed: false, at: 7, enabled: ready, mode: .hold), [.release])
        XCTAssertTrue(orange.update(pressed: true, enabled: ready, canSubmit: true, at: 8))
        XCTAssertFalse(orange.update(pressed: true, enabled: ready, canSubmit: true, at: 9))
    }

    func testDisabledChoiceSurvivesRepeatedSleepAndWake() {
        var session = ControlSession()
        for _ in 0..<3 {
            session.sleep()
            session.wake()
            XCTAssertFalse(session.enabled)
            XCTAssertFalse(session.observe(paddle: false, orange: false))
            XCTAssertFalse(session.observe(paddle: true, orange: true))
        }
    }

    func testTurningOffWhileSuspendedIsRespectedAfterWake() {
        var session = ControlSession(enabled: true)
        session.sleep()
        session.setEnabled(false)
        XCTAssertEqual(session.phase, .sleeping)
        session.wake()
        XCTAssertFalse(session.observe(paddle: false, orange: false))
        session.setEnabled(true)
        XCTAssertFalse(session.observe(paddle: true, orange: false))
        XCTAssertTrue(session.observe(paddle: false, orange: false))
    }

    func testRestoredOnChoiceCannotActivateStartupHeldControls() {
        var session = ControlSession(enabled: true)
        XCTAssertFalse(session.observe(paddle: true, orange: false))
        XCTAssertFalse(session.observe(paddle: false, orange: true))
        XCTAssertTrue(session.observe(paddle: false, orange: false))
        XCTAssertTrue(session.observe(paddle: true, orange: false))
    }

    func testAdapterReturningLateStillRequiresFreshReleasedReport() {
        var session = ControlSession(enabled: true)
        session.sleep()
        session.wake()
        // Repeated disconnect/retry cycles while the adapter is absent.
        for _ in 0..<3 { session.requireRelease() }
        XCTAssertTrue(session.enabled)
        XCTAssertFalse(session.observe(paddle: false, orange: true))
        XCTAssertTrue(session.observe(paddle: false, orange: false))
        session.requireRelease()
        XCTAssertFalse(session.observe(paddle: true, orange: true))
    }

    func testEveryWakeRequiresReleaseEvenIfPreviousSessionWasReady() {
        var session = ControlSession(enabled: true)
        for _ in 0..<3 {
            XCTAssertTrue(session.observe(paddle: false, orange: false))
            session.sleep()
            session.wake()
            XCTAssertFalse(session.observe(paddle: true, orange: false))
        }
    }
}
