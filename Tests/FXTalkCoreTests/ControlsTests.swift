import XCTest
@testable import FXTalkCore

final class ControlsTests: XCTestCase {
    func testParseStockResponseAndRejectEcho() throws {
        let sample = try XCTUnwrap(DeviceSnapshot.parse(">>> FXT1 1 0 1 0 324.5 0.8"))
        XCTAssertTrue(sample.paddle); XCTAssertTrue(sample.orange)
        XCTAssertFalse(sample.middle); XCTAssertTrue(sample.bottom)
        XCTAssertEqual(sample.rawPosition, 324.5)
        XCTAssertNil(DeviceSnapshot.parse(DeviceSnapshot.query))
        for invalid in ["FXT1 2 0 0 0 1 0", "FXT1 0 0 0 0 nan 0", "FXT1 0 0 0 0 1 inf",
                        "FXT1 0 0 0 0 1 1.5", "noise FXT1 0 0 0 0 1 0", "FXT1 0 0 0 0 1"] {
            XCTAssertNil(DeviceSnapshot.parse(invalid), invalid)
        }
    }
    func testPhysicalFXMicIdleStateAndSideSwitchPolarity() throws {
        let idle = try XCTUnwrap(DeviceSnapshot.parse("FXT1 0 1 1 1 0.0 0.0"))
        XCTAssertFalse(idle.paddle); XCTAssertFalse(idle.orange)
        XCTAssertFalse(idle.middle); XCTAssertFalse(idle.bottom)
        let orange = try XCTUnwrap(DeviceSnapshot.parse("FXT1 0 0 1 1 0.0 0.0"))
        XCTAssertTrue(orange.orange); XCTAssertFalse(orange.paddle)
    }
    func testSplitReadsCRLFAndBoundedNoise() {
        var decoder = LineDecoder()
        XCTAssertEqual(decoder.append(Data("FXT1 0 1".utf8)), [])
        XCTAssertEqual(decoder.append(Data(" 0 0 200 0.1\r\n>>> ".utf8)), ["FXT1 0 1 0 0 200 0.1"])
        XCTAssertEqual(decoder.append(Data("echo\r\n".utf8)), [">>> echo"])
        XCTAssertEqual(decoder.append(Data(repeating: 65, count: 9000)), [])
        XCTAssertEqual(decoder.append(Data("okay\n".utf8)), ["okay"])
    }
    func testStartupHeldCannotActivate() {
        var router = ControlRouter()
        for time in [0.0, 0.1, 0.2] { XCTAssertEqual(router.update(pressed: true, at: time, enabled: true, mode: .hold), []) }
        XCTAssertEqual(router.update(pressed: false, at: 0.3, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: true, at: 0.4, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: true, at: 0.5, enabled: true, mode: .hold), [.press])
        XCTAssertEqual(router.reset(), [.release])
        XCTAssertEqual(router.reset(), [])
        XCTAssertEqual(router.update(pressed: true, at: 0.7, enabled: true, mode: .hold), [])
    }
    func testDebounceHoldReleaseAndDisable() {
        var router = ControlRouter()
        XCTAssertEqual(router.update(pressed: false, at: 0, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: true, at: 0.1, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: false, at: 0.12, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: true, at: 0.13, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: true, at: 0.2, enabled: true, mode: .hold), [.press])
        XCTAssertEqual(router.update(pressed: true, at: 0.3, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: false, at: 0.4, enabled: true, mode: .hold), [])
        XCTAssertEqual(router.update(pressed: false, at: 0.5, enabled: true, mode: .hold), [.release])
        _ = router.update(pressed: true, at: 0.6, enabled: true, mode: .hold)
        XCTAssertEqual(router.update(pressed: true, at: 0.7, enabled: true, mode: .hold), [.press])
        XCTAssertEqual(router.update(pressed: true, at: 0.8, enabled: false, mode: .hold), [.release])
        XCTAssertEqual(router.update(pressed: true, at: 0.9, enabled: true, mode: .hold), [])
    }
    func testToggleOnlyOnPressAndModeChangeReleases() {
        var router = ControlRouter()
        _ = router.update(pressed: false, at: 0, enabled: true, mode: .toggle)
        _ = router.update(pressed: true, at: 0.1, enabled: true, mode: .toggle)
        XCTAssertEqual(router.update(pressed: true, at: 0.2, enabled: true, mode: .toggle), [.tap])
        XCTAssertEqual(router.update(pressed: true, at: 0.3, enabled: true, mode: .toggle), [])
        _ = router.update(pressed: false, at: 0.4, enabled: true, mode: .toggle)
        XCTAssertEqual(router.update(pressed: false, at: 0.5, enabled: true, mode: .toggle), [])
        _ = router.update(pressed: false, at: 0.6, enabled: true, mode: .hold)
        _ = router.update(pressed: false, at: 0.7, enabled: true, mode: .hold)
        _ = router.update(pressed: true, at: 0.8, enabled: true, mode: .hold)
        XCTAssertEqual(router.update(pressed: true, at: 0.9, enabled: true, mode: .hold), [.press])
        XCTAssertEqual(router.update(pressed: true, at: 1, enabled: true, mode: .toggle), [.release])
    }
    func testCalibrationPolarityAndHysteresis() throws {
        XCTAssertThrowsError(try JSONDecoder().decode(PaddleCalibration.self, from: Data("{\"rest\":1,\"squeezed\":1}".utf8)))
        XCTAssertNil(PaddleCalibration(rest: 1, squeezed: 1))
        XCTAssertNil(PaddleCalibration(rest: .infinity, squeezed: 2))
        for calibration in [PaddleCalibration(rest: 100, squeezed: 200)!, PaddleCalibration(rest: 200, squeezed: 100)!] {
            XCTAssertEqual(calibration.fraction(calibration.rest), 0)
            XCTAssertEqual(calibration.fraction(calibration.squeezed), 1)
            let halfway = (calibration.rest + calibration.squeezed) / 2
            XCTAssertTrue(calibration.pressed(raw: halfway, wasPressed: false))
            let fifth = calibration.rest + (calibration.squeezed - calibration.rest) * 0.2
            XCTAssertFalse(calibration.pressed(raw: fifth, wasPressed: false))
            XCTAssertTrue(calibration.pressed(raw: fifth, wasPressed: true))
            XCTAssertFalse(calibration.pressed(raw: calibration.rest, wasPressed: true))
        }
    }
}
