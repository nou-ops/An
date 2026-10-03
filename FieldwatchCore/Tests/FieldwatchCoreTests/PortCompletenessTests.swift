import XCTest
@testable import FieldwatchCore

final class PortCompletenessTests: XCTestCase {
    func testAircraftTrailRejectsTeleportAndCaps() {
        let base = PayloadFix(at: 1_000, lat: 35, lon: 10)
        var trail = [base]
        trail = AircraftTrail.append(trail, fix: PayloadFix(at: 2_000, lat: 35.0002, lon: 10.0002))
        XCTAssertEqual(trail.count, 2)
        trail = AircraftTrail.append(trail, fix: PayloadFix(at: 3_000, lat: 45, lon: 20))
        XCTAssertEqual(trail.count, 2)
    }

    func testClassOutlineGroupsBySignatureClass() {
        let fleet = Fleet(id: "f", name: "Test", kind: .drone)
        var d = Sighting(key: "b", kind: .ble, mac: "AA", name: "Drone")
        d.fleetIds = [fleet.id]
        let out = ClassOutline.of([d], classByFleetId: [fleet.id: fleet.kind], nameByFleetId: [fleet.id: fleet.name])
        XCTAssertTrue(out.contains { $0.kind == .drone && $0.radios.count == 1 })
    }

    func testRadioBookmarksToggle() {
        var keys = Set<String>()
        keys = RadioBookmarks.toggle("x", in: keys)
        XCTAssertTrue(keys.contains("x"))
        keys = RadioBookmarks.toggle("x", in: keys)
        XCTAssertFalse(keys.contains("x"))
    }

    func testHuntCue() {
        XCTAssertEqual(Hunt.cue(previous: -80, current: -70), .stronger)
        XCTAssertEqual(Hunt.cue(previous: -60, current: -70), .weaker)
        XCTAssertEqual(Hunt.cue(previous: -70, current: -70), .stable)
    }

    func testSettingsExchangeRoundTrip() throws {
        let filter = FilterState(showBle: false, rssiMin: -70, nameQuery: "test")
        let pack = SettingsPack(filter: filter, watchedKeys: ["a"], customNames: ["a":"Alpha"])
        let decoded = try SettingsExchange.decode(SettingsExchange.encode(pack))
        XCTAssertEqual(decoded.filter, filter)
        XCTAssertEqual(decoded.watchedKeys, ["a"])
        XCTAssertEqual(decoded.customNames["a"], "Alpha")
    }

    func testSignatureExchangeRoundTrip() throws {
        let fleet = Fleet(id: "f", name: "Test", kind: .beacon)
        let pack = SignatureExchange.pack([fleet])
        let decoded = try SignatureExchange.parse(SignatureExchange.encode(pack))
        XCTAssertEqual(decoded.fleets, [fleet])
    }

    func testGeoExportProducesGPX() {
        let r = LogRadio(kind: .wifi, mac: "AA", name: "AP", latitude: 35, longitude: 10)
        let gpx = GeoExport.render(.gpx, radios: [r])
        XCTAssertTrue(gpx.contains("<gpx"))
        XCTAssertTrue(gpx.contains("35.0"))
    }

    func testSitDiff() {
        let a = SitDiff.Radio(key: "a", kind: .ble, mac: "a", name: "A", fleetNames: [])
        let b = SitDiff.Radio(key: "b", kind: .ble, mac: "b", name: "B", fleetNames: [])
        let c = SitDiff.compare(SitDiff.Side(name: "1", radios: [a]), SitDiff.Side(name: "2", radios: [a,b]))
        XCTAssertEqual(c.onlyLeft.count, 0)
        XCTAssertEqual(c.onlyRight.count, 1)
        XCTAssertEqual(c.common.count, 1)
    }
}
