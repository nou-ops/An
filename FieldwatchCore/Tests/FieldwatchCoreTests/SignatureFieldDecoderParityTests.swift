//
//  SignatureFieldDecoderParityTests.swift
//  FieldwatchCoreTests
//
//  توقّعات مأخوذة حرفيًا من SignatureFieldDecoderTest.kt (902 سطرًا)،
//  زائد اختبارات لكل إصلاح من الإصلاحات السبعة (FIX-01…FIX-07) التي كانت
//  في نسخة الطرف الآخر وانحرافها عن Kotlin.
//

import XCTest
@testable import FieldwatchCore

final class SignatureFieldDecoderParityTests: XCTestCase {

    // MARK: - 1) Ruuvi Raw V2: مثال من وثائق Ruuvi (نفس اختبار Kotlin)

    func testRuuviRawV2TemperatureHumidity() {
        let payload = "0512FC5394C37C0004FFFC040CAC364200CDCBB8334C884F"
        let fleet = Fleet(
            id: "fleet-ruuvi", name: "Ruuvi",
            decode: FleetDecode(
                source: .manufacturerData, companyId: 0x0499,
                fields: [
                    DecodeField(id: "format", label: "Format", offset: 0, type: .u8,
                                when: DecodeWhen(offset: 0, op: .eq, valueHex: "05")),
                    DecodeField(id: "temperature", label: "Temperature", offset: 1, type: .i16,
                                endian: .be, scale: 0.005, unit: "°C"),
                    DecodeField(id: "humidity", label: "Humidity", offset: 3, type: .u16,
                                endian: .be, scale: 0.0025, unit: "%"),
                ]))
        let device = ble(companyId: 0x0499, hex: payload, fleetId: fleet.id)
        let rows = SignatureFieldDecoder.decodeSighting(device, fleets: [fleet])
        XCTAssertEqual("5", rows.first { $0.id == "format" }?.display)
        XCTAssertEqual("24.3 °C", rows.first { $0.id == "temperature" }?.display)
        XCTAssertEqual("53.49 %", rows.first { $0.id == "humidity" }?.display)
    }

    // MARK: - 2) scale ثم offsetAdd (نفس اختبار Kotlin)

    func testScaleThenOffsetAdd() {
        let fleet = Fleet(
            id: "f", name: "P",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "pressure", label: "Pressure", offset: 0, type: .u16,
                            endian: .be, scale: 1.0, offsetAdd: 50000.0, unit: "Pa"),
            ]))
        let device = ble(companyId: 1, hex: "C37C", fleetId: fleet.id)   // 0xC37C = 50044
        let rows = SignatureFieldDecoder.decodeSighting(device, fleets: [fleet])
        XCTAssertEqual(1, rows.count)
        XCTAssertEqual("100044 Pa", rows.first?.display)
    }

    // MARK: - 3) البوّابة لا تُطابق ⇒ لا صفوف

    func testWhenMismatchSkipsField() {
        let fleet = Fleet(
            id: "f", name: "P",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "v", label: "V", offset: 0, type: .u8,
                            when: DecodeWhen(offset: 0, op: .eq, valueHex: "FF")),
            ]))
        let device = ble(companyId: 1, hex: "01", fleetId: fleet.id)
        XCTAssertTrue(SignatureFieldDecoder.decodeSighting(device, fleets: [fleet]).isEmpty)
    }

    // MARK: - 4) FIX-04: bits على أكثر من بايت وعرض أكبر

    func testBitsMultiByte() {
        let fleet = Fleet(
            id: "f", name: "P",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "flag", label: "Flag", offset: 0, type: .bits, bitOffset: 4, bitWidth: 8),
            ]))
        // 34 12 (LE) = 0x1234 ⇒ >> 4 = 0x123، & 0xFF = 0x23 = 35
        let device = ble(companyId: 1, hex: "3412", fleetId: fleet.id)
        let rows = SignatureFieldDecoder.decodeSighting(device, fleets: [fleet])
        XCTAssertEqual(1, rows.count)
        XCTAssertEqual("35", rows.first?.display)
        XCTAssertEqual(2, rows.first?.length, "resolvedLength للبتات = ceil((4+8)/8) = 2")
    }

    // MARK: - 5) FIX-05: BOOL = yes/no · HEX = بايتات متباعدة · MAC يتطلب 6

    func testBoolHexMacDisplays() {
        let fleet = Fleet(
            id: "f", name: "P",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "on", label: "On", offset: 0, type: .bool),
                DecodeField(id: "raw", label: "Raw", offset: 1, length: 3, type: .hex),
                DecodeField(id: "mac", label: "MAC", offset: 4, type: .mac),
            ]))
        let device = ble(companyId: 1, hex: "010102FE010203040506", fleetId: fleet.id)
        let rows = SignatureFieldDecoder.decodeSighting(device, fleets: [fleet])
        XCTAssertEqual("yes", rows.first { $0.id == "on" }?.display)
        XCTAssertEqual("01 02 FE", rows.first { $0.id == "raw" }?.display)
        XCTAssertEqual("01:02:03:04:05:06", rows.first { $0.id == "mac" }?.display)
    }

    // MARK: - 6) FIX-01: لا فكّ لبيانات المصنّع على Wi-Fi

    func testManufacturerDecodeIsBleOnly() {
        let fleet = Fleet(
            id: "f", name: "P",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "v", label: "V", offset: 0, type: .u8),
            ]))
        var ap = Sighting(key: "WIFI:AA:BB:CC:11:22:33", kind: .wifi, mac: "AA:BB:CC:11:22:33")
        ap.facts.mfgRecords = [MfgRecord(companyId: 1, dataHex: "2A")]
        ap.fleetIds = [fleet.id]
        XCTAssertTrue(SignatureFieldDecoder.decodeSighting(ap, fleets: [fleet]).isEmpty,
                      "Kotlin: MANUFACTURER_DATA مقتصر على BLE")
    }

    // MARK: - 7) FIX-02: SERVICE_DATA يتطلب UUID صريحًا

    func testServiceDataNeedsExplicitUuid() {
        let noUuid = Fleet(
            id: "f", name: "P",
            decode: FleetDecode(source: .serviceData, serviceUuid: nil, fields: [
                DecodeField(id: "v", label: "V", offset: 0, type: .u8),
            ]))
        let withUuid = Fleet(
            id: "g", name: "Q",
            decode: FleetDecode(source: .serviceData, serviceUuid: "FFFF", fields: [
                DecodeField(id: "v", label: "V", offset: 0, type: .u8),
            ]))
        var d = Sighting(key: "BLE:11:22:33:44:55:66", kind: .ble, mac: "11:22:33:44:55:66")
        d.facts.serviceData = [ServiceDataRecord(uuid: "FE2C", dataHex: "2A")]
        d.fleetIds = [noUuid.id, withUuid.id]
        XCTAssertTrue(SignatureFieldDecoder.decodeFleet(noUuid, noUuid.decode!, d).isEmpty,
                      "بلا serviceUuid: لا حمولة (Kotlin يُرجع قائمة فارغة)")
        XCTAssertTrue(SignatureFieldDecoder.decodeFleet(withUuid, withUuid.decode!, d).isEmpty,
                      "UUID غير مطابق FFFF ≠ FE2C: لا حمولة")
    }

    // MARK: - 8) FIX-03: إزالة لاصقة Govee "INTELLI_ROCKS"

    func testIntelliRocksSuffixIsStripped() {
        // بوّابة على الطول: خريطة H510x تعمل فقط إن كانت الحمولة 3 بايتات.
        // Govee تلصق ASCII "INTELLI_ROCKS" (13 بايت) فيصير الطول 16 ⇒ البوّابة تفشل بلا إزالة.
        let gated = Fleet(
            id: "f", name: "Govee",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "temp", label: "Temp", offset: 0, type: .u16, endian: .be,
                            when: DecodeWhen(offset: 0, length: 3, op: .len, valueHex: "")),
            ]))
        let ascii = "INTELLI_ROCKS".utf8.map { String(format: "%02X", $0) }.joined()
        let device = ble(companyId: 0xEC88, hex: "EC77EC" + ascii, fleetId: gated.id)
        let rows = SignatureFieldDecoder.decodeSighting(device, fleets: [gated])
        XCTAssertEqual(1, rows.count, "بعد إزالة اللاصقة يبقى EC 77 EC (3 بايتات) فتنجح بوّابة len=3")
        XCTAssertEqual("60535", rows.first?.display, "0xEC77 = 60535")

        // وشاهد مضاد: حمولة 3 بايتات **بلا** لاصقة + بوّابة len=4 ⇒ لا صفوف (البوّابة تعمل فعلًا).
        let gated4 = Fleet(
            id: "g", name: "Govee4",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "temp", label: "Temp", offset: 0, type: .u16, endian: .be,
                            when: DecodeWhen(offset: 0, length: 4, op: .len, valueHex: "")),
            ]))
        let plain = ble(companyId: 0xEC88, hex: "EC77EC", fleetId: gated4.id)
        XCTAssertTrue(SignatureFieldDecoder.decodeSighting(plain, fleets: [gated4]).isEmpty)
    }

    // MARK: - 9) FIX-06: مفاتيح enum بصيغة 0x / عشرية

    func testEnumLabelKeyNormalization() {
        let fleet = Fleet(
            id: "f", name: "P",
            decode: FleetDecode(source: .manufacturerData, fields: [
                DecodeField(id: "mode", label: "Mode", offset: 0, type: .u8,
                            enumLabels: ["0x1F": "Boosted", "7": "Idle"], live: true,
                            liveEmphasis: ["0x1F"], enumNotes: ["0x1F": "مروحة كاملة"]),
            ]))
        let device = ble(companyId: 1, hex: "1F", fleetId: fleet.id)
        let rows = SignatureFieldDecoder.decodeSighting(device, fleets: [fleet])
        XCTAssertEqual(1, rows.count)
        XCTAssertEqual("Boosted", rows.first?.display)
        XCTAssertEqual("مروحة كاملة", rows.first?.note)
        XCTAssertEqual(true, rows.first?.emphasis)
        XCTAssertEqual("Boosted", SignatureFieldDecoder.liveChips(device, fleets: [fleet]).first?.text)
    }

    // MARK: - 10) FIX-07: الأطوال الافتراضية

    func testResolvedLengthDefaults() {
        XCTAssertEqual(6, DecodeField(id: "m", label: "M", offset: 0, type: .mac).resolvedLength())
        XCTAssertEqual(2, DecodeField(id: "b", label: "B", offset: 0, type: .bits, bitOffset: 4, bitWidth: 8).resolvedLength())
        XCTAssertEqual(3, DecodeField(id: "u", label: "U", offset: 0, type: .u24).resolvedLength())
        XCTAssertEqual(5, DecodeField(id: "h", label: "H", offset: 1, length: 5, type: .hex).resolvedLength())
    }

    // MARK: - 11) الكتالوج الحقيقي: فكّ توقيع TPMS من الأسطول المدمج

    func testRealCatalogTpmsDecode() {
        let fleets = SignatureCatalog.loadBundledOrEmpty()
        guard let tpms = fleets.first(where: { $0.id == "fleet-tpms-ble" }), let decode = tpms.decode else {
            return XCTFail("fleet-tpms-ble بتعريف decode غير موجود في الكتالوج المدمج")
        }
        // بوّابة الحقل الأساسي: len == 16 ⇒ الحمولة 16 بايت.
        let device = ble(companyId: decode.companyId ?? 0,
                         hex: "80AABBCCDDEE0102030405060708090A", fleetId: tpms.id)
        let rows = SignatureFieldDecoder.decodeFleet(tpms, decode, device)
        XCTAssertFalse(rows.isEmpty, "حقول TPMS يجب أن تُفكّ")
        XCTAssertEqual("1", rows.first { $0.id == "wheel" }?.display, "enum 128 ⇒ العجلة 1")
    }

    // MARK: - Fixtures

    private func ble(companyId: Int, hex: String, fleetId: String) -> Sighting {
        var d = Sighting(key: "BLE:F0:11:22:33:44:55", kind: .ble, mac: "F0:11:22:33:44:55")
        d.facts.mfgRecords = [MfgRecord(companyId: companyId, dataHex: hex)]
        d.manufacturerId = companyId
        d.manufacturerDataHex = hex
        d.fleetIds = [fleetId]
        return d
    }
}
