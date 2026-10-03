//
//  OpenDroneIdTests.swift
//  FieldwatchCoreTests
//
//  منقول من app/src/test/java/app/fieldwatch/domain/OpenDroneIdTest.kt (4 اختبارات)
//  + حالة DJI الحقيقية من حزمة FA:0B:BC type 13 بتاريخ 28 Sep 2026.
//

import XCTest
@testable import FieldwatchCore

final class OpenDroneIdTests: XCTestCase {

    func testBleLocationHeadingSpeedAndEw() {
        let loc = OpenDroneId.fromFacts(
            RadioFacts(serviceData: [
                ServiceDataRecord(uuid: "FFFA", dataHex: bleWrap(locationMsg(dir: 90, ew: false, speed: 40)))
            ])
        )
        XCTAssertEqual(40.0, loc.lat!, accuracy: 1e-6)
        XCTAssertEqual(-74.0, loc.lon!, accuracy: 1e-6)
        XCTAssertEqual(90.0, loc.headingDeg!, accuracy: 1e-6)
        XCTAssertEqual(10.0, loc.speedMps!, accuracy: 1e-6)
        XCTAssertEqual(2.0, loc.vspeedMps!, accuracy: 1e-6)

        let west = OpenDroneId.fromFacts(
            RadioFacts(serviceData: [
                ServiceDataRecord(uuid: "FFFA", dataHex: bleWrap(locationMsg(dir: 90, ew: true, speed: 40)))
            ])
        )
        XCTAssertEqual(270.0, west.headingDeg!, accuracy: 1e-6)
    }

    func testWifiVendorIeLocation() {
        let ie = VendorIeRecord(
            oui: "FA:0B:BC",
            type: 0x0D,
            dataHex: "00" + toHexUpper(locationMsg(dir: 45, ew: false, speed: 8))
        )
        let loc = OpenDroneId.fromFacts(RadioFacts(vendorIes: [ie]))
        XCTAssertEqual(40.0, loc.lat!, accuracy: 1e-6)
        XCTAssertEqual(45.0, loc.headingDeg!, accuracy: 1e-6)
        XCTAssertEqual(2.0, loc.speedMps!, accuracy: 1e-6)
    }

    func testUnknownDirectionIsNull() {
        let loc = OpenDroneId.parseMessages([locationMsg(dir: 255, ew: false, speed: 40)])
        XCTAssertNil(loc.headingDeg)
    }

    func testWifiMessagePackDecodesIdLocationAndOperator() {
        // DJI RID-1581F3… FA:0B:BC type 13 pack from A54 28 Sep 2026.
        let hex = "D9F2190302123135383146335954444A3144303033315A353330000000" +
                  "1220820A00864228110CFF80CF0000F508B2083A022E310A00" +
                  "420176E42711B5FF81CF010000000000000005088B02900E00"
        let loc = OpenDroneId.fromFacts(
            RadioFacts(vendorIes: [VendorIeRecord(oui: "FA:0B:BC", type: 0x0D, dataHex: hex)])
        )
        XCTAssertEqual("1581F3YTDJ1D0031Z530", loc.uasId)
        XCTAssertEqual(28.7851142, loc.lat!, accuracy: 1e-6)
        XCTAssertEqual(-81.3629684, loc.lon!, accuracy: 1e-6)
        XCTAssertEqual(130.0, loc.headingDeg!, accuracy: 1e-6)
        XCTAssertEqual(2.5, loc.speedMps!, accuracy: 1e-6)
        XCTAssertEqual(28.7827062, loc.opLat!, accuracy: 1e-6)
        XCTAssertEqual(-81.3563979, loc.opLon!, accuracy: 1e-6)
    }

    // MARK: - Fixtures (مطابقة لدوال Kotlin الخاصة بالاختبار)

    private func bleWrap(_ msg: [UInt8]) -> String {
        "0D00" + toHexUpper(msg)
    }

    private func locationMsg(dir: Int, ew: Bool, speed: Int) -> [UInt8] {
        let flags = 0x20 | (ew ? 0x02 : 0)
        let lat = le32(400_000_000)
        let lon = le32(-740_000_000)
        let geo = le16(2200)
        let height = le16(2100)
        var out: [UInt8] = [0x12, UInt8(flags), UInt8(dir), UInt8(speed), 4]
        out += lat
        out += lon
        out += le16(0)
        out += geo
        out += height
        out += [UInt8](repeating: 0, count: 6)
        return out
    }

    private func le32(_ n: Int) -> [UInt8] {
        [
            UInt8(n & 0xFF),
            UInt8((n >> 8) & 0xFF),
            UInt8((n >> 16) & 0xFF),
            UInt8((n >> 24) & 0xFF),
        ]
    }

    private func le16(_ n: Int) -> [UInt8] {
        [UInt8(n & 0xFF), UInt8((n >> 8) & 0xFF)]
    }
}
