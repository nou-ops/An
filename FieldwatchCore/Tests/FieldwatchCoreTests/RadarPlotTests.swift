//
//  RadarPlotTests.swift
//  FieldwatchCoreTests
//
//  منقول من app/src/test/java/app/fieldwatch/domain/RadarPlotTest.kt (3 اختبارات).
//

import XCTest
@testable import FieldwatchCore

final class RadarPlotTests: XCTestCase {

    private let maxR: Float = 1000

    func testLoudSitsNearCenter() {
        let r30 = RadarPlot.radius(-30, maxR: maxR)
        let r100 = RadarPlot.radius(-100, maxR: maxR)
        XCTAssertEqual(120, r30, accuracy: 0.5)
        XCTAssertEqual(1000, r100, accuracy: 0.5)
        XCTAssertTrue(r30 < RadarPlot.radius(-40, maxR: maxR))
        XCTAssertTrue(RadarPlot.radius(-60, maxR: maxR) < r100)
    }

    func testZoomSpreadsInnerRadiosAndPushesWeakOffDisc() {
        let inner = RadarPlot.radius(-40, maxR: maxR, zoom: 1)
        let innerZ = RadarPlot.radius(-40, maxR: maxR, zoom: 2)
        XCTAssertEqual(inner * 2, innerZ, accuracy: 0.5)
        XCTAssertTrue(RadarPlot.onDisc(-100, maxR: maxR, zoom: 1))
        XCTAssertFalse(RadarPlot.onDisc(-100, maxR: maxR, zoom: 2))
        XCTAssertTrue(RadarPlot.onDisc(-40, maxR: maxR, zoom: 2))
    }

    func testZoomIsClamped() {
        XCTAssertEqual(RadarPlot.radius(-50, maxR: maxR, zoom: 1),
                       RadarPlot.radius(-50, maxR: maxR, zoom: 0.2), accuracy: 0.01)
        XCTAssertEqual(RadarPlot.radius(-50, maxR: maxR, zoom: 4),
                       RadarPlot.radius(-50, maxR: maxR, zoom: 9), accuracy: 0.01)
    }
}
