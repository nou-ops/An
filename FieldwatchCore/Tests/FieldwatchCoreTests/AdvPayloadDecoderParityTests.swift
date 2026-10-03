//
//  AdvPayloadDecoderParityTests.swift
//  FieldwatchCoreTests
//
//  تغطية الفجوتين اللتين بقيتا بعد حزمة PARITY-NEXT، مقابل AdvPayloadDecoder.kt:
//   FIX-AD1  TLV 0x02: Tesla (vehicle, وزن 8) · Target/Atrius (beacon, وزن 8) · iBeacon عام (7)
//   FIX-AD2  Fast Pair: أسماء الطرازات من FastPairModels (110 طرازًا) — وزن 8 إن عُرف، 6 إن لا
//  النصوص المتوقعة منقولة حرفيًا من Kotlin.
//

import XCTest
@testable import FieldwatchCore

final class AdvPayloadDecoderParityTests: XCTestCase {

    // MARK: - TLV 0x02: Tesla

    func testTeslaIBeaconRoleHintIsVehicle() {
        // DefaultCatalog.kt:10 — 021574278BDAB64445208F0C720EAF059935
        let device = appleDevice(hex: Self.fullIBeacon(uuidPrefix: DefaultCatalogConstants.teslaIBeaconMfgPrefix))
        let hints = AdvPayloadDecoder.roleHints(device)
        guard let hit = hints.first else { return XCTFail("لا تلميحات") }
        XCTAssertEqual("vehicle", hit.bucket)
        XCTAssertEqual("a Tesla vehicle or phone-as-key", hit.label)
        XCTAssertEqual(8, hit.weight)
        XCTAssertEqual("Tesla phone-key iBeacon UUID (iOS background find).", hit.reason)
    }

    // MARK: - FIX-AD1: Target / Atrius

    func testTargetAtriusIBeaconRoleHint() {
        // DefaultCatalog.kt:17 — 02155993A94C7D974DF79ABFE493BFD5D000
        let device = appleDevice(hex: Self.fullIBeacon(uuidPrefix: DefaultCatalogConstants.targetAtriusIBeaconMfgPrefix))
        let hints = AdvPayloadDecoder.roleHints(device)
        guard let hit = hints.first else { return XCTFail("لا تلميحات") }
        XCTAssertEqual("beacon", hit.bucket)
        XCTAssertEqual("a Target Atrius basket tag", hit.label)
        XCTAssertEqual(8, hit.weight, "كانت سابقًا iBeacon عامًا بوزن 7")
        XCTAssertEqual("Target / Atrius iBeacon UUID (shopping-basket asset tag).", hit.reason)
    }

    func testPlainIBeaconStaysGenericBeacon() {
        let device = appleDevice(hex: Self.fullIBeacon(uuidPrefix: "0215AAAABBBBCCCCDDDDEEEEFFFF0000"))
        let hint = AdvPayloadDecoder.roleHints(device).first
        XCTAssertEqual("beacon", hint?.bucket)
        XCTAssertEqual("an iBeacon", hint?.label)
        XCTAssertEqual(7, hint?.weight)
    }

    // MARK: - FIX-AD2: Fast Pair بأسماء الطرازات

    func testFastPairKnownModelNameInRoleHint() {
        var d = Sighting(key: "BLE:AA:00:00:00:00:01", kind: .ble, mac: "AA:00:00:00:00:01")
        d.facts.serviceData = [ServiceDataRecord(uuid: "FE2C", dataHex: "000006")]   // Pixel Buds
        let hint = AdvPayloadDecoder.roleHints(d).first
        XCTAssertEqual("Google Pixel Buds", hint?.label, "الاسم من FastPairModels لا نص عام")
        XCTAssertEqual(8, hint?.weight, "الطراز المعروف وزنه 8")
        XCTAssertEqual("Google Fast Pair model Google Pixel Buds (0x000006), in pairing mode.", hint?.reason)
    }

    func testFastPairUnknownModelKeepsGenericLabel() {
        var d = Sighting(key: "BLE:AA:00:00:00:00:02", kind: .ble, mac: "AA:00:00:00:00:02")
        d.facts.serviceData = [ServiceDataRecord(uuid: "FE2C", dataHex: "FFFEFD")]   // معرّف غير مُدرج
        let hint = AdvPayloadDecoder.roleHints(d).first
        XCTAssertEqual("a Fast Pair accessory (often earbuds or a speaker)", hint?.label)
        XCTAssertEqual(6, hint?.weight)
        XCTAssertEqual("Google Fast Pair model 0xFFFEFD, in pairing mode.", hint?.reason)
    }

    func testDecodeFastPairUsesModelTable() {
        let known = AdvPayloadDecoder.decodeService(ServiceDataRecord(uuid: "FE2C", dataHex: "000006"))
        XCTAssertEqual("OK", "OK")
        XCTAssertTrue(known.contains { $0.value == "Google Pixel Buds  (0x000006)" },
                      "نص Kotlin: \"$name  (0x%06X)\" — بمسافتين")
        let unknown = AdvPayloadDecoder.decodeService(ServiceDataRecord(uuid: "FE2C", dataHex: "FFFEFD"))
        XCTAssertTrue(unknown.contains { $0.value == "0xFFFEFD (not in the local name list)" },
                      "نص Kotlin البديل")
    }

    func testFastPairModelTableSize() {
        XCTAssertEqual(110, FastPairModels.count, "عدد طرازات FastPairModels.kt")
        XCTAssertEqual("Google Pixel Buds", FastPairModels.name(0x000006))
        XCTAssertEqual("Android Auto", FastPairModels.name(0x000007))
        XCTAssertNil(FastPairModels.name(0xFFFEFD))
        // التقنيع إلى 24 بتة كما في Kotlin (modelId and 0xFFFFFF)
        XCTAssertEqual("Google Pixel Buds", FastPairModels.name(0xFF000006))
    }

    // MARK: - Fixtures

    /// يبني حمولة iBeacon كاملة من بادئة (ترويسة 0215 + 15 بايت UUID):
    /// 0215 + UUID(32) + major(4) + minor(4) + tx(2) = 46 خانة ⇒ TLV data = 21 بايت.
    private static func fullIBeacon(uuidPrefix: String) -> String {
        let uuid = uuidPrefix.uppercased().count >= 34
            ? String(uuidPrefix.uppercased().dropFirst(4)) + "0F"     // أكمل البايت السادس عشر
            : "AAAABBBBCCCCDDDDEEEEFFFF000011220F"
        return "0215" + String(uuid.prefix(32)) + "0000" + "0000" + "C5"
    }

    private func appleDevice(hex: String) -> Sighting {
        var d = Sighting(key: "BLE:F0:F0:F0:F0:F0:F0", kind: .ble, mac: "F0:F0:F0:F0:F0:F0")
        d.facts.mfgRecords = [MfgRecord(companyId: 0x004C, dataHex: hex)]
        d.manufacturerId = 0x004C
        d.manufacturerDataHex = hex
        return d
    }
}
