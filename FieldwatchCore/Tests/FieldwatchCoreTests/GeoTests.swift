//
//  GeoTests.swift
//  FieldwatchCoreTests
//

import XCTest
@testable import FieldwatchCore

final class GeoTests: XCTestCase {

    func testMetersAtEquator() {
        // 0.001° خط طول على خط الاستواء ≈ 111.19 م بنصف قطر 6,371,000
        XCTAssertEqual(111.19, Geo.meters(0, 0, 0, 0.001), accuracy: 0.05)
    }

    func testMetersIsSymmetricAndZeroForSamePoint() {
        let a = Geo.meters(36.19, 5.41, 36.20, 5.42)
        let b = Geo.meters(36.20, 5.42, 36.19, 5.41)
        XCTAssertEqual(a, b, accuracy: 1e-9)
        XCTAssertEqual(0.0, Geo.meters(36.19, 5.41, 36.19, 5.41), accuracy: 1e-9)
    }

    func testPathLengthAndSpan() {
        let samples = [
            GpsSample(at: 1, lat: 36.1900, lon: 5.4100),
            GpsSample(at: 2, lat: 36.1910, lon: 5.4100),
            GpsSample(at: 3, lat: 36.1920, lon: 5.4100),
        ]
        let leg = Geo.meters(36.1900, 5.4100, 36.1910, 5.4100)
        XCTAssertEqual(leg * 2, Geo.pathLengthM(samples), accuracy: 1e-6)
        XCTAssertEqual(leg * 2, Geo.spanM(samples), accuracy: 1e-6)
        XCTAssertEqual(0.0, Geo.pathLengthM([samples[0]]), accuracy: 1e-12)
        XCTAssertEqual(0.0, Geo.spanM([]), accuracy: 1e-12)
    }

    func testCellKeyMatchesLocaleUSFormatting() {
        XCTAssertEqual("40.1235,-74.9877", Geo.cellKey(40.123456, -74.987654))
        XCTAssertEqual("36.1900,5.4100", Geo.cellKey(36.19, 5.41))
    }
}

extension GeoTests {
    func testPathLegsAndScreenRedaction() {
        let samples = [
            GpsSample(at: 1_000, lat: 36.1900, lon: 5.4100),
            GpsSample(at: 21_000, lat: 36.1901, lon: 5.4101),
            GpsSample(at: 81_000, lat: 36.1930, lon: 5.4130)
        ]
        let legs = Geo.legs(samples, stayM: 40, minStayMs: 40_000, now: 81_000)
        XCTAssertFalse(legs.isEmpty)
        XCTAssertEqual(Geo.screenCoord(36.19, 5.41, false), "36.19000, 5.41000")
        XCTAssertEqual(Geo.screenCoord(36.19, 5.41, true), "masked")
        XCTAssertEqual(Geo.redactCoordsIn("at 36.19000, 5.41000 now", true), "at masked now")
    }

    func testHopAndDespawn() {
        let a = GpsSample(at: 1_000, lat: 36.19, lon: 5.41)
        XCTAssertTrue(Geo.hopPlausible(from: a, lat: 36.1901, lon: 5.4101, at: 2_000))
        XCTAssertFalse(Geo.hopPlausible(from: a, lat: 37.19, lon: 6.41, at: 2_000))
        let trail = [a, GpsSample(at: 2_000, lat: 40, lon: 10), GpsSample(at: 3_000, lat: 36.1902, lon: 5.4102)]
        XCTAssertEqual(Geo.despikePath(trail).count, 2)
    }
}
