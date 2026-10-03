//
//  RssiTests.swift
//  FieldwatchCoreTests
//
//  تغطية Rssi.kt: 127 = "غير متاح" في BLE.
//

import XCTest
@testable import FieldwatchCore

final class RssiTests: XCTestCase {

    func testMeasuredRange() {
        XCTAssertTrue(Rssi.measured(-127))
        XCTAssertTrue(Rssi.measured(0))
        XCTAssertTrue(Rssi.measured(126))
        XCTAssertFalse(Rssi.measured(127))
        XCTAssertFalse(Rssi.measured(-128))
    }

    func testSessionRangeNotAvailable() {
        XCTAssertEqual("Not available", Rssi.sessionRange(min: 127, max: 127))
    }

    func testSessionRangeSingleValue() {
        XCTAssertEqual("-60 dBm", Rssi.sessionRange(min: -60, max: -60))
    }

    func testSessionRangeSpanIncludesHistory() {
        let history = [
            RssiSample(at: 1, rssi: -71),
            RssiSample(at: 2, rssi: -55),
            RssiSample(at: 3, rssi: 127), // غير مقيس: يُتجاهل
        ]
        XCTAssertEqual("-71 to -55 dBm", Rssi.sessionRange(min: -70, max: -70, history: history))
    }

    func testLastMeasuredFallsBackToHistory() {
        let history = [
            RssiSample(at: 1, rssi: 127),
            RssiSample(at: 2, rssi: -80),
            RssiSample(at: 3, rssi: 127),
        ]
        XCTAssertEqual(-80, Rssi.lastMeasured(rssi: 127, history: history))
        XCTAssertEqual(-42, Rssi.lastMeasured(rssi: -42, history: history))
        XCTAssertNil(Rssi.lastMeasured(rssi: 127, history: []))
    }
}
