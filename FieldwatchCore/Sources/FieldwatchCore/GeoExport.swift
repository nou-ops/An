import Foundation

public enum LogExportKind: String, CaseIterable, Sendable { case logCSV, logJSONL, gpx, kml, wigle }
public enum LogExportRadios: Sendable { case both, wifi, ble; func matches(_ kind: RadioKind) -> Bool { self == .both || (self == .wifi && kind == .wifi) || (self == .ble && kind == .ble) } }

public enum GeoExport {
    public enum Format: String, Sendable { case gpx, kml, wigle; public var extensionName: String { rawValue } }
    public static func formatOf(_ kind: LogExportKind) -> Format? { switch kind { case .gpx:return .gpx; case .kml:return .kml; case .wigle:return .wigle; default:return nil } }
    public static func render(_ format: Format, radios: [LogRadio], customNames: [String:String] = [:], track: [GpsSample] = []) -> String {
        let rows = radios.filter { $0.hasPosition }
        switch format {
        case .gpx:
            let pts = rows.compactMap { r -> (Double,Double)? in guard let p=r.position else{return nil};return p }
            let tr = track.map { "<trkpt lat=\"\($0.lat)\" lon=\"\($0.lon)\"></trkpt>" }.joined()
            let wpts = pts.enumerated().map { i,p in "<wpt lat=\"\(p.0)\" lon=\"\(p.1)\"><name>\(xml(customNames[rows[i].key] ?? rows[i].name))</name></wpt>" }.joined()
            return "<?xml version=\"1.0\"?><gpx version=\"1.1\" creator=\"Fieldwatch\">\(wpts)<trk><name>Fieldwatch track</name><trkseg>\(tr)</trkseg></trk></gpx>"
        case .kml:
            let marks = rows.compactMap { r -> String? in guard let p=r.position else{return nil}; return "<Placemark><name>\(xml(customNames[r.key] ?? r.name))</name><Point><coordinates>\(p.1),\(p.0),0</coordinates></Point></Placemark>" }.joined()
            return "<?xml version=\"1.0\"?><kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document>\(marks)</Document></kml>"
        case .wigle:
            var out="WigleWifi-1.4,appRelease=Fieldwatch,\nMAC,SSID,CurrentLatitude,CurrentLongitude,FirstSeen,LastSeen,Type\n"
            for r in rows { guard let p=r.position else {continue}; out += "\(r.mac),\(csv(customNames[r.key] ?? r.name)),\(p.0),\(p.1),\(r.firstSeen),\(r.lastSeen),\(r.kind.rawValue)\n" }
            return out
        }
    }
    private static func xml(_ s:String)->String { s.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;") }
    private static func csv(_ s:String)->String { s.contains(",") ? "\"\(s.replacingOccurrences(of:"\"",with:"\"\""))\"" : s }
}

public extension LogRadio {
    var position: (Double,Double)? { guard let latitude, let longitude else{return nil}; return (latitude, longitude) }
}
