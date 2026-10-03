//
//  WifiIeParserTests.swift
//  FieldwatchCoreTests
//
//  منقول من app/src/test/java/app/fieldwatch/radio/WifiIeParserTest.kt (10 اختبارات).
//

import XCTest
@testable import FieldwatchCore

final class WifiIeParserTests: XCTestCase {

    private func ie(_ id: Int, _ data: Int...) -> WifiIeParser.Ie {
        WifiIeParser.Ie(id: id, bytes: data.map { UInt8(truncatingIfNeeded: $0) })
    }

    private var wpa2CcmpPsk: WifiIeParser.Ie {
        ie(48,
           0x01, 0x00,                    // version 1
           0x00, 0x0F, 0xAC, 0x04,        // group CCMP
           0x01, 0x00,                    // 1 pairwise
           0x00, 0x0F, 0xAC, 0x04,        // CCMP
           0x01, 0x00,                    // 1 AKM
           0x00, 0x0F, 0xAC, 0x02)        // PSK
    }

    func testRsnWpa2PskCcmp() {
        let p = WifiIeParser.parseIes([wpa2CcmpPsk], capabilities: "[WPA2-PSK-CCMP][ESS]")
        XCTAssertEqual("RSN PSK CCMP (group CCMP)", p.security)
    }

    func testRsnWpa3Sae() {
        let frame = ie(48,
                       0x01, 0x00,
                       0x00, 0x0F, 0xAC, 0x04,
                       0x01, 0x00,
                       0x00, 0x0F, 0xAC, 0x04,
                       0x01, 0x00,
                       0x00, 0x0F, 0xAC, 0x08)   // SAE
        XCTAssertEqual("RSN SAE CCMP (group CCMP)",
                       WifiIeParser.parseIes([frame], capabilities: "").security)
    }

    func testRsnTransitionModeListsBothAkms() {
        let frame = ie(48,
                       0x01, 0x00,
                       0x00, 0x0F, 0xAC, 0x04,
                       0x01, 0x00,
                       0x00, 0x0F, 0xAC, 0x04,
                       0x02, 0x00,
                       0x00, 0x0F, 0xAC, 0x02,   // PSK
                       0x00, 0x0F, 0xAC, 0x08)   // SAE
        XCTAssertEqual("RSN PSK/SAE CCMP (group CCMP)",
                       WifiIeParser.parseIes([frame], capabilities: "").security)
    }

    func testWpa1VendorIeSummaryAndOui() {
        let wpa = ie(221,
                     0x00, 0x50, 0xF2, 0x01,   // Microsoft OUI, WPA type
                     0x01, 0x00,
                     0x00, 0x50, 0xF2, 0x02,   // group TKIP
                     0x01, 0x00,
                     0x00, 0x50, 0xF2, 0x02,   // pairwise TKIP
                     0x01, 0x00,
                     0x00, 0x50, 0xF2, 0x02)   // akm
        let p = WifiIeParser.parseIes([wpa], capabilities: "")
        XCTAssertEqual("WPA TKIP", p.security)
        XCTAssertTrue(p.vendorIes.contains { $0.oui == "00:50:F2" && $0.type == 1 })
    }

    func testVendorIeExtractsOuiTypeAndPayload() {
        let p = WifiIeParser.parseIes([ie(221, 0x00, 0x17, 0xF2, 0x0A, 0x01, 0x02)], capabilities: "")
        XCTAssertEqual(1, p.vendorIes.count)
        XCTAssertEqual("00:17:F2", p.vendorIes[0].oui)
        XCTAssertEqual(0x0A, p.vendorIes[0].type)
        XCTAssertEqual("0102", p.vendorIes[0].dataHex)
    }

    func testRatesDecodeBasicFlagAndHalfMbps() {
        let p = WifiIeParser.parseIes(
            [ie(1, 0x82, 0x84, 0x8B, 0x96, 0x0C, 0x12, 0x18, 0x24)],
            capabilities: ""
        )
        XCTAssertEqual("1* 2* 5.5* 11* 6 9 12 18", p.rates)
    }

    func testDsParameterSetsChannel() {
        let p = WifiIeParser.parseIes([ie(3, 0x06)], capabilities: "")
        XCTAssertEqual(6, p.channelFromDs)
    }

    func testCapabilitiesFallbackWhenNoSecurityIe() {
        XCTAssertEqual("[WPA2-PSK-CCMP][ESS]",
                       WifiIeParser.parseIes([], capabilities: "[WPA2-PSK-CCMP][ESS]").security)
        // جسم RSN مبتور يجب ألا يحجب نص القدرات.
        let short = ie(48, 0x01, 0x00, 0x00, 0x0F)
        XCTAssertEqual("[WPA2-PSK-CCMP][ESS]",
                       WifiIeParser.parseIes([short], capabilities: "[WPA2-PSK-CCMP][ESS]").security)
    }

    func testVendorIeKeepsOpenDroneIdSizedPayload() {
        var frame = ie(221, 0xFA, 0x0B, 0xBC, 0x0D)
        frame = WifiIeParser.Ie(id: frame.id, bytes: frame.bytes + (0..<30).map { UInt8($0) })
        let p = WifiIeParser.parseIes([frame], capabilities: "")
        XCTAssertEqual("FA:0B:BC", p.vendorIes.single!.oui)
        XCTAssertEqual(0x0D, p.vendorIes.single!.type)
        XCTAssertEqual(60, p.vendorIes.single!.dataHex.count)
    }

    func testNoIesNoCapabilitiesGivesNullSecurity() {
        XCTAssertNil(WifiIeParser.parseIes([], capabilities: nil).security)
        XCTAssertNil(WifiIeParser.parseIes([], capabilities: "").security)
    }

    /// اختبار إضافي (ليس في Kotlin): النهاية إلى النهاية على جهاز Jailbreak —
    /// IE خام FA:0B:BC نوع 13 ⇒ OpenDroneId يخرج latitude/longitude.
    func testWifiIeToOpenDroneIdEndToEnd() {
        let msg: [UInt8] = [
            0x12, 0x20, 45, 8, 4,
            0x00, 0x84, 0xD7, 0x17,     // lat = 400_000_000 LE
            0x00, 0x7F, 0xE4, 0xD3,     // lon = -740_000_000 LE
            0x00, 0x00,
            0x98, 0x08,                 // geo = 2200
            0x34, 0x08,                 // height = 2100
            0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        ]
        XCTAssertEqual(25, msg.count)
        var ieBytes: [UInt8] = [0xFA, 0x0B, 0xBC, 0x0D]
        ieBytes += [0x00]                       // counter (ASTM)
        ieBytes += msg
        let parsed = WifiIeParser.parseIes([WifiIeParser.Ie(id: 221, bytes: ieBytes)], capabilities: "")
        let loc = OpenDroneId.fromFacts(RadioFacts(vendorIes: parsed.vendorIes))
        XCTAssertEqual(40.0, loc.lat!, accuracy: 1e-6)
        XCTAssertEqual(-74.0, loc.lon!, accuracy: 1e-6)
        XCTAssertEqual(45.0, loc.headingDeg!, accuracy: 1e-6)
        XCTAssertEqual(2.0, loc.speedMps!, accuracy: 1e-6)
    }
}

private extension Array {
    var single: Element? { count == 1 ? self[0] : nil }
}
