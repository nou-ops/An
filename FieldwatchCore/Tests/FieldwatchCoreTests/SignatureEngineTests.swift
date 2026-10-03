//
//  SignatureEngineTests.swift
//  FieldwatchCoreTests
//
//  اختبارات نقل محرّك التواقيع. المدخلات من **الكتالوج الرسمي المدمج في الحزمة**
//  (Resources/fieldwatch-signatures-v2.json · catalogVersion 88 = Fieldwatch 1.1.17):
//   • fleet-actiontec: NAME_GLOB "Actiontec*" + OUI 00:0F:B3 / 00:15:05
//   • fleet-meraki:    NAME_GLOB "Meraki*"    + OUI 00:18:0A / 00:84:1E
//   • fleet-airtag:    NAME_CONTAINS "AirTag" + mfg 0x004C/12 + UUID FD44
//   • fleet-apple-device: mfg 0x004C مع بادئات Continuity (10، 0F، 0B، 05، 0C …)
//   • fleet-ibeacon:   mfg 0x004C بادئة "0215" (وهي نفس بداية بادئة Tesla!)
//  وما لا يوجد في الكتالوج (توقيعات التجميع minPeers/clusterByOui/sequentialMac —
//  صفر منها في v90) يُختبر بتوقيع مُبنى في الاختبار، وهذا مُعلَّم عند كل حالة.
//

import XCTest
@testable import FieldwatchCore

final class SignatureEngineTests: XCTestCase {

    private let engine = SignatureEngine()
    private var fleets: [Fleet] { SignatureCatalog.loadBundledOrEmpty() }

    // MARK: - تحميل الكتالوج (تحقق من صحة Codable مقابل JSON الحقيقي)

    func testBundledRealCatalogLoads() {
        XCTAssertGreaterThan(fleets.count, 200, "الكتالوج الرسمي المدمج يجب أن يُفكّ كاملًا")
        XCTAssertEqual(244, fleets.count)

        let actiontec = try! XCTUnwrap(fleets.first { $0.id == "fleet-actiontec" })
        XCTAssertEqual("ISP", actiontec.kind.rawValue)
        XCTAssertTrue(actiontec.matchAny)
        XCTAssertTrue(actiontec.rules.contains { $0.kind == .nameGlob && $0.text == "Actiontec*" })
        XCTAssertTrue(actiontec.rules.contains { $0.kind == .oui && $0.text == "00:0F:B3" && $0.radio == .wifi })

        let airtag = try! XCTUnwrap(fleets.first { $0.id == "fleet-airtag" })
        XCTAssertEqual(SignatureClass.finder, airtag.kind)
        XCTAssertTrue(airtag.rules.contains {
            $0.kind == .manufacturerData && $0.companyId == 0x004C && $0.dataPrefixHex == "12"
        })
    }

    // MARK: - المطابقة الأساسية

    func testWifiOuiMatchActiontec() {
        var ap = wifi(mac: "00:0F:B3:11:22:33")
        ap.name = ""
        let hits = engine.match([ap], fleets: fleets)
        XCTAssertEqual(["fleet-actiontec"], ids(hits, ap.key))
    }

    func testNameGlobMatchOnRandomMac() {
        // MAC عشوائي (لا OUI) لكن الاسم يطابق Glob — نفس سلوك Kotlin.
        let ap = wifi(mac: "DA:A1:19:44:55:66", name: "Actiontec-MI424WR")
        XCTAssertEqual(["fleet-actiontec"], engine.match([ap], fleets: fleets)[ap.key] ?? [])
    }

    func testVendorIeOuiMatchesMerakiNotBssid() {
        var ap = wifi(mac: "AA:BB:CC:11:22:33")
        ap.vendorIeOuis = ["00:18:0A"]           // OUI من قائمة Meraki
        XCTAssertEqual(["fleet-meraki"], engine.match([ap], fleets: fleets)[ap.key] ?? [])
    }

    func testProtocolVendorIeOuisAreIgnored() {
        // 00:50:F2 (WPA) و 00:0F:AC (RSN) وسوم بروتوكول: تُتجاهل في مسار vendor IE
        // حتى لو وُجدت في الكتالوج (هنا توقيع مُبنى يحملها لاختبار الحاجز نفسه).
        let protocolFleet = Fleet(
            id: "test-protocol", name: "Protocol OUI",
            rules: [MatchRule(kind: .vendorIeOUI, text: "00:50:F2", radio: .wifi)],
            kind: .other
        )
        var ap = wifi(mac: "AA:BB:CC:11:22:33")
        ap.vendorIeOuis = ["00:50:F2", "00:0F:AC"]
        let hits = engine.match([ap], fleets: [protocolFleet])
        XCTAssertTrue(ids(hits, ap.key).isEmpty)
    }

    func testRadioScopeKeepsWifiOnlyFleetOffBleDevice() {
        var bleDev = ble(mac: "00:0F:B3:11:22:33")   // نفس OUI لكن BLE
        bleDev.name = ""
        let hits = engine.match([bleDev], fleets: fleets)
        XCTAssertFalse((hits[bleDev.key] ?? []).contains("fleet-actiontec"))
    }

    // MARK: - Apple: قواعد الإسقاط

    func testFindMyOnlyPayloadStaysAirTag() {
        var tag = ble(mac: "F1:22:33:44:55:66")
        tag.facts.mfgRecords = [MfgRecord(companyId: 0x004C, dataHex: "12ABCD")]
        let hits = engine.match([tag], fleets: fleets)
        XCTAssertTrue((hits[tag.key] ?? []).contains("fleet-airtag"))
        XCTAssertFalse((hits[tag.key] ?? []).contains("fleet-apple-device"))
    }

    func testAirTagDroppedWhenAppleContinuityAlsoMatches() {
        // نفس الراديو يحمل مفتاح 0x12 (Find My) وبادئة Continuity 0x10 معًا.
        var phone = ble(mac: "F2:22:33:44:55:66")
        phone.facts.mfgRecords = [
            MfgRecord(companyId: 0x004C, dataHex: "12ABCD"),
            MfgRecord(companyId: 0x004C, dataHex: "10EF01"),
        ]
        let hits = engine.match([phone], fleets: fleets)[phone.key] ?? []
        XCTAssertTrue(hits.contains("fleet-apple-device"))
        XCTAssertFalse(hits.contains("fleet-airtag"), "AirTag يجب أن يُسقط عند وجود منتج آبل آخر")
    }

    func testAirTagKeptWhenAdvertisedNameSaysAirTag() {
        var tag = ble(mac: "F3:22:33:44:55:66")
        tag.name = "My AirTag"
        tag.facts.mfgRecords = [
            MfgRecord(companyId: 0x004C, dataHex: "12ABCD"),
            MfgRecord(companyId: 0x004C, dataHex: "10EF01"),
        ]
        let hits = engine.match([tag], fleets: fleets)[tag.key] ?? []
        XCTAssertTrue(hits.contains("fleet-airtag"), "الاسم المُعلن AirTag يمنع الإسقاط")
    }

    func testAirTagKeptWhenFindMyAccessoryUuidPresent() {
        var tag = ble(mac: "F4:22:33:44:55:66")
        tag.serviceUuids = ["0000FD44-0000-1000-8000-00805F9B34FB"]
        tag.facts.mfgRecords = [
            MfgRecord(companyId: 0x004C, dataHex: "12ABCD"),
            MfgRecord(companyId: 0x004C, dataHex: "10EF01"),
        ]
        let hits = engine.match([tag], fleets: fleets)[tag.key] ?? []
        XCTAssertTrue(hits.contains("fleet-airtag"))
    }

    func testFindMyAccessoryUuidRuleMatchesByItself() {
        // تحكّم إيجابي: قاعدة SERVICE_UUID "FD44" في fleet-airtag يجب أن تطابق وحدها
        // (بلا أي سجل Find My) — هذا ما يثبت أن مسار UUID في المحرّك يعمل فعلًا.
        var accessory = ble(mac: "F7:22:33:44:55:66")
        accessory.serviceUuids = ["0000FD44-0000-1000-8000-00805F9B34FB"]
        let hits = engine.match([accessory], fleets: fleets)[accessory.key] ?? []
        XCTAssertTrue(hits.contains("fleet-airtag"), "UUID FD44 وحده يكفي لقاعدة Find My accessory")
    }

    // MARK: - Tesla phone key × iBeacon (قاعدة حقيقية في الكتالوج)

    func testTeslaPhoneKeyDoesNotChipAsIBeacon() {
        var car = ble(mac: "F5:22:33:44:55:66")
        // بادئة Tesla الرسمية تبدأ بـ 0215 — وهي نفس بادئة قاعدة iBeacon في الكتالوج.
        car.facts.mfgRecords = [
            MfgRecord(companyId: 0x004C, dataHex: DefaultCatalogConstants.teslaIBeaconMfgPrefix)
        ]
        let hits = engine.match([car], fleets: fleets)[car.key] ?? []
        XCTAssertFalse(hits.contains("fleet-ibeacon"), "مفتاح هاتف Tesla ليس iBeacon")
    }

    func testRealIBeaconStillMatches() {
        var beacon = ble(mac: "F6:22:33:44:55:66")
        beacon.facts.mfgRecords = [MfgRecord(companyId: 0x004C, dataHex: "0215AABBCC")]
        let hits = engine.match([beacon], fleets: fleets)[beacon.key] ?? []
        XCTAssertTrue(hits.contains("fleet-ibeacon"))
    }

    // MARK: - إسقاطات Cross-brand (توقيعات مُبنىة: الكتالوج v90 لا يتقاطع فيها)

    func testMerakiDropsCisco() {
        let meraki = Fleet(id: "fleet-meraki", name: "Meraki", rules: [MatchRule(kind: .oui, text: "00:18:0A", radio: .wifi)])
        let cisco = Fleet(id: "fleet-cisco", name: "Cisco", rules: [MatchRule(kind: .oui, text: "00:18:0A", radio: .wifi)])
        let ap = wifi(mac: "00:18:0A:11:22:33")
        let hits = engine.match([ap], fleets: [meraki, cisco])[ap.key] ?? []
        XCTAssertTrue(hits.contains("fleet-meraki"))
        XCTAssertFalse(hits.contains("fleet-cisco"))
    }

    func testOsmoDropsDji() {
        let osmo = Fleet(id: "fleet-osmo", name: "Osmo", rules: [MatchRule(kind: .nameGlob, text: "Osmo*", radio: .ble)])
        let dji = Fleet(id: "fleet-dji", name: "DJI", rules: [MatchRule(kind: .manufacturerID, companyId: 0x08AA, radio: .ble)])
        let drone = ble(mac: "C1:22:33:44:55:66", name: "Osmo Pocket 3")
        var d = drone
        d.facts.mfgRecords = [MfgRecord(companyId: 0x08AA, dataHex: "AABB")]
        let hits = engine.match([d], fleets: [osmo, dji])[d.key] ?? []
        XCTAssertTrue(hits.contains("fleet-osmo"))
        XCTAssertFalse(hits.contains("fleet-dji"))
    }

    // MARK: - matchAny = false (يجب مطابقة كل القواعد)

    func testMatchAllWhenMatchAnyIsFalse() {
        let strict = Fleet(
            id: "test-strict", name: "Strict", matchAny: false,
            rules: [
                MatchRule(kind: .nameContains, text: "Camera", radio: .wifi),
                MatchRule(kind: .oui, text: "00:0F:B3", radio: .wifi),
            ],
            kind: .camera
        )
        let onlyName = wifi(mac: "DE:AD:BE:11:22:33", name: "Store Camera")
        XCTAssertEqual([], engine.match([onlyName], fleets: [strict])[onlyName.key] ?? [])

        let both = wifi(mac: "00:0F:B3:11:22:33", name: "Store Camera")
        XCTAssertEqual(["test-strict"], engine.match([both], fleets: [strict])[both.key] ?? [])
    }

    // MARK: - Clusters (لا توجد توقيعات cluster في v90 — توقيع مُبنى)

    func testClusterByOuiNeedsMinPeers() {
        let cluster = Fleet(
            id: "test-cluster", name: "Cluster", minPeers: 3, peerWindowSec: 60, clusterByOui: true,
            kind: .camera
        )
        let now: Int64 = 1_000_000
        var a = wifi(mac: "00:18:0A:00:00:01"); a.lastSeen = now
        var b = wifi(mac: "00:18:0A:00:00:02"); b.lastSeen = now
        var c = wifi(mac: "00:18:0A:00:00:03"); c.lastSeen = now
        var other = wifi(mac: "00:18:0B:00:00:04"); other.lastSeen = now

        let hits = engine.match([a, b, c, other], fleets: [cluster], now: now)
        XCTAssertEqual(["test-cluster"], ids(hits, a.key))
        XCTAssertEqual(["test-cluster"], ids(hits, b.key))
        XCTAssertEqual(["test-cluster"], ids(hits, c.key))
        XCTAssertTrue(ids(hits, other.key).isEmpty, "OUI مختلف لا يدخل العنقود")
    }

    func testClusterNotAppliedUnderMinPeers() {
        let cluster = Fleet(id: "test-cluster", name: "Cluster", minPeers: 3, peerWindowSec: 60, clusterByOui: true, kind: .camera)
        let now: Int64 = 1_000_000
        var a = wifi(mac: "00:18:0A:00:00:01"); a.lastSeen = now
        var b = wifi(mac: "00:18:0A:00:00:02"); b.lastSeen = now
        let hits = engine.match([a, b], fleets: [cluster], now: now)
        XCTAssertTrue(ids(hits, a.key).isEmpty)
    }

    func testClusterSkipsStaleDevices() {
        let cluster = Fleet(id: "test-cluster", name: "Cluster", minPeers: 2, peerWindowSec: 60, clusterByOui: true, kind: .camera)
        let now: Int64 = 1_000_000
        var fresh = wifi(mac: "00:18:0A:00:00:01"); fresh.lastSeen = now
        var stale = wifi(mac: "00:18:0A:00:00:02"); stale.lastSeen = now - 120_000   // أقدم من النافذة
        let hits = engine.match([fresh, stale], fleets: [cluster], now: now)
        XCTAssertTrue(ids(hits, fresh.key).isEmpty, "الجهاز القديم لا يُحتسب peer")
    }

    func testSequentialMacCluster() {
        let seq = Fleet(id: "test-seq", name: "Sequential", minPeers: 2, peerWindowSec: 60, sequentialMac: true, kind: .camera)
        let now: Int64 = 1_000_000
        var a = wifi(mac: "AA:BB:CC:00:10:00"); a.lastSeen = now
        var b = wifi(mac: "AA:BB:CC:00:10:20"); b.lastSeen = now   // فرق 0x20 = 32 ≤ 64
        var far = wifi(mac: "AA:BB:CC:00:20:00"); far.lastSeen = now // فرق 0x1000 > 64
        let hits = engine.match([a, b, far], fleets: [seq], now: now)
        XCTAssertEqual(["test-seq"], ids(hits, a.key))
    }

    // MARK: - Fixtures

    private func wifi(mac: String, name: String = "") -> Sighting {
        base(key: "WIFI:\(mac)", kind: .wifi, mac: mac, name: name)
    }

    private func ble(mac: String, name: String = "") -> Sighting {
        base(key: "BLE:\(mac)", kind: .ble, mac: mac, name: name)
    }

    private func base(key: String, kind: RadioKind, mac: String, name: String) -> Sighting {
        Sighting(
            key: key, kind: kind, mac: mac, name: name,
            rssi: -60, rssiMin: -60, rssiMax: -60, channel: 0, frequencyMhz: 0,
            vendor: nil, randomized: true, hiddenSsid: false, serviceUuids: [],
            manufacturerId: nil, manufacturerDataHex: "", rawHex: "", extras: "",
            firstSeen: 1, lastSeen: 1, hitCount: 1, fleetIds: [], rssiHistory: [], presence: []
        )
    }

    /// ترتيب معرّفات التوقيعات المطابقة كي تكون المقارنة حتمية (Set → [String] مصفوفة مرتبة).
    private func ids(_ hits: [String: Set<String>], _ key: String) -> [String] {
        (hits[key] ?? []).sorted()
    }
}
