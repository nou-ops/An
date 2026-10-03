import XCTest
@testable import FieldwatchCore

final class AdvPayloadDecoderTests: XCTestCase {
    func testAppleIBeacon() {
        let m="0215E2C56DB5DFFB48D2B060D0F5A71096E000010002C5"
        let f=AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId:0x004C,dataHex:m)); let d=Dictionary(uniqueKeysWithValues:f.map{($0.label,$0.value)})
        XCTAssertEqual(d["Apple Continuity type"],"0x02 · iBeacon"); XCTAssertEqual(d["iBeacon UUID"],"e2c56db5-dffb-48d2-b060-d0f5a71096e0"); XCTAssertEqual(d["iBeacon major / minor"],"1 / 2"); XCTAssertTrue(d["iBeacon calibrated TX"]?.hasPrefix("-59") == true)
    }
    func testAirPodsFindMyAndUnknown() {
        let m="0707010F2051981100"; let f=AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId:0x004C,dataHex:m)); let d=Dictionary(uniqueKeysWithValues:f.map{($0.label,$0.value)}); XCTAssertEqual(d["Product"],"AirPods (2nd generation)"); XCTAssertTrue(d["Battery (left / right)"] != nil); XCTAssertTrue(d["Case battery"] != nil); XCTAssertEqual(d["Charging"],"case")
        XCTAssertTrue(AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId:0x004C,dataHex:"120A"+String(repeating:"00",count:10))).contains{ $0.label=="Find My / Offline Finding" }); XCTAssertTrue(AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId:0x9999,dataHex:"AABB")).isEmpty)
    }
    func testFastPairAndEddystone() {
        let f=AdvPayloadDecoder.decodeService(ServiceDataRecord(uuid:"FE2C",dataHex:"000006")); let d=Dictionary(uniqueKeysWithValues:f.map{($0.label,$0.value)}); XCTAssertTrue(d["Google Fast Pair"]?.contains("pairing mode") == true); XCTAssertEqual(d["Model ID"],"Google Pixel Buds  (0x000006)")
        let u=AdvPayloadDecoder.decodeService(ServiceDataRecord(uuid:"FEAA",dataHex:"00C500112233445566778899AABBCCDDEEFF0000")); let ud=Dictionary(uniqueKeysWithValues:u.map{($0.label,$0.value)}); XCTAssertEqual(ud["Eddystone-UID namespace"],"00112233445566778899"); XCTAssertEqual(ud["Eddystone-UID instance"],"AABBCCDDEEFF")
        let h=AdvPayloadDecoder.decodeService(ServiceDataRecord(uuid:"FEAA",dataHex:"41"+String(repeating:"11",count:20)+"00")); XCTAssertEqual(h.first?.value,"separated (unwanted-tracking mode)"); XCTAssertTrue(h.allSatisfy{!$0.label.hasPrefix("Eddystone")})
    }
}

extension AdvPayloadDecoderTests {
    func testAppleContinuityParityCases() {
        let airDrop = AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId: 0x004C, dataHex: "05" + "12" + String(repeating: "00", count: 18)))
        XCTAssertTrue(airDrop.contains { $0.label == "AirDrop" })
        let siri = AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId: 0x004C, dataHex: "08" + "06" + "000000000009"))
        XCTAssertTrue(siri.contains { $0.label == "Hey Siri" && $0.value.contains("Mac") })
        let alt = AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId: 0x0157, dataHex: "BEAC" + String(repeating: "11", count: 20)))
        XCTAssertEqual(alt.count, 2)
    }

    func testEddystoneAndMicrosoftFrames() {
        let tlm = AdvPayloadDecoder.decodeService(ServiceDataRecord(uuid: "FEAA", dataHex: "20" + String(repeating: "00", count: 10)))
        XCTAssertEqual(tlm.first?.label, "Eddystone-TLM")
        let ms = AdvPayloadDecoder.decodeManufacturer(MfgRecord(companyId: 0x0006, dataHex: "0106AABB"))
        XCTAssertTrue(ms.first?.value.contains("iPhone") == true)
    }
}
