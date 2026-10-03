import XCTest
@testable import FieldwatchCore

final class SitTests: XCTestCase {
    private func sighting(_ key:String, rssi:Int = -50, first:Int64 = 1000, last:Int64 = 1000) -> Sighting {
        Sighting(key:key, kind:.ble, mac:key, name:"", rssi:rssi, rssiMin:rssi, rssiMax:rssi, firstSeen:first, lastSeen:last)
    }
    func testStartSeedsAndEndCreatesFile() {
        let s = SitSession.start(name:" parking ", now:10_000, heard:[sighting("A")], fleets:[])
        XCTAssertEqual(s.summary.name,"parking")
        XCTAssertEqual(s.radioCount,1)
        let file = s.end(now:20_000, fleets:[])
        XCTAssertEqual(file.summary.endAt,20_000)
        XCTAssertEqual(file.radios.count,1)
        XCTAssertEqual(file.format,SitConstants.format)
    }
    func testRenameAndPathAreBounded() {
        let s = SitSession.start(name:"x", now:1, heard:[], fleets:[])
        XCTAssertTrue(s.rename("new name"))
        XCTAssertTrue(s.recordPath(lat:40,lon:-74,at:1_000))
        XCTAssertTrue(s.recordPath(lat:40.00001,lon:-74.00001,at:2_000))
        XCTAssertFalse(s.sightings().count > SitConstants.radioCap)
    }
    func testIngestMergesExistingRadio() {
        let s = SitSession.start(name:"x", now:1, heard:[], fleets:[])
        XCTAssertTrue(s.ingest(sighting("A",rssi:-70,first:2,last:2), fleets:[], watchDeviceKeys:[], watchedFleetIds:[]))
        XCTAssertTrue(s.ingest(sighting("A",rssi:-40,first:1,last:4), fleets:[], watchDeviceKeys:[], watchedFleetIds:[]))
        let d = s.sightings()[0]
        XCTAssertEqual(d.firstSeen,1); XCTAssertEqual(d.lastSeen,4); XCTAssertEqual(d.rssi,-40)
    }
    func testCSVContainsHeaderAndEscapesNames() {
        let d = sighting("AA", rssi:-42)
        let csv = SitExport.csv([d])
        XCTAssertTrue(csv.hasPrefix(SitExport.csvHeader))
        XCTAssertTrue(csv.contains("AA"))
    }
}
