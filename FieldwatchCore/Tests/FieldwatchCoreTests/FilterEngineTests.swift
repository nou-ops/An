//
//  FilterEngineTests.swift
//  FieldwatchCoreTests
//
//  منقول من app/src/test/java/app/fieldwatch/domain/FilterEngineTest.kt (9 اختبارات).
//  ملاحظة النقل: Kotlin يستعمل data class copy(...) لتغيير حقول؛ في Swift نستعمل
//  نسخة var ونعدّل الحقل — نفس المعنى بلا تغيير في السلوك المختبَر.
//

import XCTest
@testable import FieldwatchCore

final class FilterEngineTests: XCTestCase {

    private let engine = FilterEngine()
    private var labeled: Sighting { Self.ble("BLE:AA:BB:CC:DD:EE:FF") }
    private var other: Sighting { Self.ble("BLE:11:22:33:44:55:66") }

    private var signed: Sighting {
        var s = labeled
        s.fleetIds = ["fleet-airtag"]
        return s
    }

    func testStockPresetsMatchShortSetWithWatchedOnly() {
        let presets = engine.defaultPresets()
        XCTAssertEqual(["all", "wifi", "ble", "strong", "with-you", "watched"],
                       presets.map { $0.id })
        let watched = presets.first { $0.id == "watched" }!
        XCTAssertEqual("Watched only", watched.name)
        XCTAssertTrue(watched.filter.watchedOnly)
        XCTAssertTrue(watched.filter.showWifi)
        XCTAssertTrue(watched.filter.showBle)
        XCTAssertEqual(-100, watched.filter.rssiMin)
        XCTAssertTrue(watched.isBuiltIn())
        XCTAssertTrue(FilterPreset(id: "trackers", name: "Trackers", filter: FilterState()).isBuiltIn())
    }

    func testCustomNamesOnlyKeepsLabeledKeys() {
        let filter = FilterState(customNamesOnly: true)
        let keys: Set<String> = [labeled.key]
        XCTAssertTrue(engine.pass(labeled, filter, namedRadioKeys: keys))
        XCTAssertFalse(engine.pass(other, filter, namedRadioKeys: keys))
        XCTAssertFalse(engine.pass(labeled, filter, namedRadioKeys: []))
    }

    func testCustomNamesOnlyOffDoesNotHide() {
        XCTAssertTrue(engine.pass(other, FilterState(), namedRadioKeys: [labeled.key]))
    }

    func testHideFastPairAccountKeyDropsPlazaChipsKeepsPairingAndDual() {
        let hide = FilterState(hideFastPairAccountKey: true)

        var account = labeled
        account.fleetIds = ["fleet-fast-pair"]
        account.fastPairPairing = false

        var pairing = labeled
        pairing.fleetIds = ["fleet-fast-pair"]
        pairing.fastPairPairing = true

        var dual = labeled
        dual.fleetIds = ["fleet-fast-pair", "fleet-google"]
        dual.fastPairPairing = false

        XCTAssertFalse(engine.pass(account, hide))
        XCTAssertTrue(engine.pass(pairing, hide))
        XCTAssertTrue(engine.pass(dual, hide))
        XCTAssertTrue(engine.pass(account, FilterState()))
    }

    func testWatchedOnlyKeepsBookmarkedSignature() {
        let filter = FilterState(watchedOnly: true)
        XCTAssertTrue(engine.pass(signed, filter, watchedFleetIds: ["fleet-airtag"]))
        XCTAssertFalse(engine.pass(signed, filter, watchedFleetIds: []))
        XCTAssertFalse(engine.pass(other, filter, watchedFleetIds: ["fleet-airtag"]))
    }

    func testWatchedOnlyKeepsAlertNamedRadioNotLabelOnly() {
        let filter = FilterState(watchedOnly: true)
        XCTAssertTrue(engine.pass(labeled, filter, alertDeviceKeys: [labeled.key]))
        XCTAssertFalse(engine.pass(labeled, filter, namedRadioKeys: [labeled.key]))
    }

    func testWatchedOnlyAndHideSurveillanceStillHidesCameras() {
        let filter = FilterState(
            watchedOnly: true,
            useClassFilter: true,
            excludeClasses: true,
            classes: [.surveillance]
        )

        var flock = signed
        flock.fleetIds = ["fleet-flock"]
        var axon = other
        axon.fleetIds = ["fleet-axon"]

        let byClass: [String: SignatureClass] = [
            "fleet-flock": .surveillance,
            "fleet-axon": .lawEnforcement,
        ]
        let watched: Set<String> = ["fleet-flock", "fleet-axon"]

        XCTAssertFalse(engine.pass(flock, filter, classByFleetId: byClass, watchedFleetIds: watched))
        XCTAssertTrue(engine.pass(axon, filter, classByFleetId: byClass, watchedFleetIds: watched))
    }

    func testWatchedOnlyStaysAndInOrLogic() {
        let filter = FilterState(watchedOnly: true, nameQuery: "anything", logic: .or)

        var namedUnwatched = labeled
        namedUnwatched.name = "anything"
        var signedNamed = signed
        signedNamed.name = "anything"

        XCTAssertFalse(engine.pass(namedUnwatched, filter, watchedFleetIds: ["fleet-airtag"]))
        XCTAssertTrue(engine.pass(signedNamed, filter, watchedFleetIds: ["fleet-airtag"]))
    }

    func testSignaturesOnlyAndCustomNamesStack() {
        let both = FilterState(namedOnly: true, customNamesOnly: true)
        let keys: Set<String> = [labeled.key, other.key]

        XCTAssertTrue(engine.pass(signed, both, namedRadioKeys: keys))
        XCTAssertFalse(engine.pass(labeled, both, namedRadioKeys: keys))

        var signedWithOtherKey = signed
        signedWithOtherKey.key = other.key
        XCTAssertFalse(engine.pass(signedWithOtherKey, both, namedRadioKeys: [labeled.key]))
    }

    // MARK: - Fixture (نظير ble(key) في Kotlin)

    private static func ble(_ key: String) -> Sighting {
        Sighting(
            key: key,
            kind: .ble,
            mac: String(key.drop(while: { $0 != ":" }).dropFirst()),
            name: "",
            rssi: -50,
            rssiMin: -50,
            rssiMax: -50,
            channel: 0,
            frequencyMhz: 0,
            vendor: nil,
            randomized: true,
            hiddenSsid: false,
            serviceUuids: [],
            manufacturerId: nil,
            manufacturerDataHex: "",
            rawHex: "",
            extras: "",
            firstSeen: 1,
            lastSeen: 1,
            hitCount: 1,
            fleetIds: [],
            rssiHistory: [],
            presence: []
        )
    }
}
