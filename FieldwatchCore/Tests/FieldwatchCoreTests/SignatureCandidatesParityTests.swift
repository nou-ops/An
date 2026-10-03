//
//  SignatureCandidatesParityTests.swift
//  FieldwatchCoreTests
//
//  توقّعات مأخوذة **حرفيًا** من SignatureCandidatesTest.kt (321 سطرًا):
//  nameGlobHexRunBecomesQuestionMarks · houseLikeNames · isOverbroadCreateName.
//  أهم ما تثبته هذه الحزمة: أن نسخة الطرف الآخر من nameGlobOf/isHouseLikeName
//  كانت مختلفة جوهريًا عن Kotlin (كانت تقبل أسماءً يرفضها Kotlin، وتستخدم
//  قائمة كلمات داخل الاسم كله بدل الرمز الأول + قاعدة «المنتَج»).
//

import XCTest
@testable import FieldwatchCore

final class SignatureCandidatesParityTests: XCTestCase {

    // MARK: - nameGlobOf (نفس حالات اختبار Kotlin)

    func testNameGlobHexRunBecomesQuestionMarks() {
        XCTAssertEqual("H2O-????????????", SignatureCandidates.nameGlobOf("H2O-047bcbd11400"))
        XCTAssertEqual("H2O-????????????", SignatureCandidates.nameGlobOf("H2O-0a1c8e22b400"))
        XCTAssertEqual("RG3100*", SignatureCandidates.nameGlobOf("RG3100-7A21"))
        XCTAssertEqual("RG3100*", SignatureCandidates.nameGlobOf("RG3100-8434 guest"))
        XCTAssertEqual("[fridge]*", SignatureCandidates.nameGlobOf("[fridge]_E30AJT5133207Z SJIT"))
        XCTAssertNil(SignatureCandidates.nameGlobOf("IonCannon"))
        XCTAssertNil(SignatureCandidates.nameGlobOf("Jameson"))
        XCTAssertNil(SignatureCandidates.nameGlobOf("DIRECT-roku-living"))
        XCTAssertNil(SignatureCandidates.nameGlobOf("LOB_Guest_wifi"))
    }

    func testHouseLikeNames() {
        XCTAssertTrue(SignatureCandidates.isHouseLikeName("IonCannon"))
        XCTAssertTrue(SignatureCandidates.isHouseLikeName("Jameson"))
        XCTAssertTrue(SignatureCandidates.isHouseLikeName("LOB_Guest"))
        XCTAssertTrue(SignatureCandidates.isHouseLikeName("ATT-GUEST-lobby"))
        XCTAssertFalse(SignatureCandidates.isHouseLikeName("H2O-047bcbd11400"))
        XCTAssertFalse(SignatureCandidates.isHouseLikeName("RG3100-7A21"))
        XCTAssertFalse(SignatureCandidates.isHouseLikeName("[fridge]_E30AJT5133207Z"))
    }

    func testOverbroadCreateName() {
        XCTAssertTrue(SignatureCandidates.isOverbroadCreateName("DIRECT-"))
        XCTAssertTrue(SignatureCandidates.isOverbroadCreateName("ANDROID*"))
        XCTAssertFalse(SignatureCandidates.isOverbroadCreateName("H2O*"))
    }

    func testProtocolIeAndChipVendor() {
        XCTAssertTrue(SignatureCandidates.isProtocolIe("00:50:F2"))
        XCTAssertTrue(SignatureCandidates.isProtocolIe("00:0F:AC"))
        XCTAssertFalse(SignatureCandidates.isProtocolIe("00:18:0A"))
        XCTAssertTrue(SignatureCandidates.isChipModuleVendor("Espressif Inc."))
        XCTAssertFalse(SignatureCandidates.isChipModuleVendor("Ubiquiti"))
    }

    // MARK: - analyze

    func testAnalyzeClustersSharedGlobFamily() {
        let radios = [
            LogRadio(kind: .wifi, mac: "AA:BB:CC:00:00:01", name: "H2O-047bcbd11400"),
            LogRadio(kind: .wifi, mac: "AA:BB:CC:00:00:02", name: "H2O-0a1c8e22b400"),
        ]
        let report = SignatureCandidates.analyze(radios, fleets: [])
        XCTAssertEqual(2, report.uniqueRadios)
        XCTAssertEqual(2, report.unmatchedRadios)
        XCTAssertEqual(1, report.families.count)
        guard let fam = report.families.first else { return XCTFail("لا عائلة") }
        XCTAssertEqual("H2O-????????????", fam.rules.first?.text)
        XCTAssertEqual(2, fam.distinctRadios)
    }

    func testAnalyzeSkipsHouseLikeAndCountsThem() {
        let radios = [
            LogRadio(kind: .wifi, mac: "AA:BB:CC:00:00:01", name: "LOB_Guest_wifi"),
            LogRadio(kind: .wifi, mac: "AA:BB:CC:00:00:02", name: "IonCannon"),
        ]
        let report = SignatureCandidates.analyze(radios, fleets: [])
        XCTAssertTrue(report.families.isEmpty)
        XCTAssertEqual(2, report.skippedHouseLike)
    }

    func testAnalyzeIgnoresSingleMemberFamilies() {
        let radios = [LogRadio(kind: .wifi, mac: "AA:BB:CC:00:00:01", name: "H2O-047bcbd11400")]
        let report = SignatureCandidates.analyze(radios, fleets: [])
        XCTAssertTrue(report.families.isEmpty, "MIN_RADIOS = 2")
        XCTAssertEqual(1, report.skippedOther)
    }

    // MARK: - assessFamily

    func testAssessFamilyVerdicts() {
        var tagged = Sighting(key: "BLE:01:02:03:04:05:06", kind: .ble, mac: "01:02:03:04:05:06")
        tagged.fleetIds = ["fleet-airtag"]
        XCTAssertEqual(.tagged, SignatureCandidates.assessFamily(tagged, live: [], log: [], fleets: []).verdict)

        // بلا معرف فريد (اسم بيتي) ⇒ هذا الراديو وحده.
        let lonely = Sighting(key: "WIFI:AA:BB:CC:00:00:01", kind: .wifi, mac: "AA:BB:CC:00:00:01", name: "IonCannon")
        XCTAssertEqual(.single, SignatureCandidates.assessFamily(lonely, live: [], log: [], fleets: []).verdict)

        // راديوان بنفس عائلة الاسم ⇒ عائلة «محتملة» (أقل من 8).
        let device = Sighting(key: "WIFI:AA:BB:CC:00:00:03", kind: .wifi, mac: "AA:BB:CC:00:00:03", name: "H2O-047bcbd11400")
        let live = [
            Sighting(key: "WIFI:AA:BB:CC:00:00:04", kind: .wifi, mac: "AA:BB:CC:00:00:04", name: "H2O-0a1c8e22b400"),
            Sighting(key: "WIFI:AA:BB:CC:00:00:05", kind: .wifi, mac: "AA:BB:CC:00:00:05", name: "H2O-0b1d9f33c500"),
        ]
        let hint = SignatureCandidates.assessFamily(device, live: live, log: [], fleets: [])
        XCTAssertEqual(.possible, hint.verdict, "MIN_RADIOS = 2 ⇒ عائلة محتملة")
        XCTAssertEqual("H2O-????????????", hint.ruleLabel)
        XCTAssertEqual(2, hint.liveCount)
    }

    // MARK: - suggestFleet

    func testSuggestFleetFromCandidate() {
        let radios = [
            LogRadio(kind: .wifi, mac: "AA:BB:CC:00:00:01", name: "H2O-047bcbd11400"),
            LogRadio(kind: .wifi, mac: "AA:BB:CC:00:00:02", name: "H2O-0a1c8e22b400"),
        ]
        let report = SignatureCandidates.analyze(radios, fleets: [])
        guard let fam = report.families.first else { return XCTFail("لا عائلة") }
        let fleet = SignatureCandidates.suggestFleet(fam)
        XCTAssertEqual(.nameGlob, fleet.rules.first?.kind)
        XCTAssertTrue(fleet.builtIn == false)
        XCTAssertEqual(.home, fleet.kind)

        // الأسطول المقترح يجب أن يُطابق الراديو نفسه عند تمريره على المحرّك.
        let engine = SignatureEngine()
        let sighting = radios[0].toSighting()
        XCTAssertEqual([fleet.id], Array(engine.match([sighting], fleets: [fleet])[sighting.key] ?? []))
    }
}
