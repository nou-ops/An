import Foundation

public enum AircraftTrail {
    public static let cap = 40
    public static let minMeters = 8.0
    public static let maxSpeedMps = 120.0
    public static let nearMeters = 2_000.0

    public static func append(_ trail: [PayloadFix], device: Sighting) -> [PayloadFix] {
        guard let lat = device.payloadLat, let lon = device.payloadLon else { return trail }
        return append(trail, fix: PayloadFix(at: device.lastSeen, lat: lat, lon: lon, alt: device.payloadAlt, heading: device.payloadHeading, speed: device.payloadSpeed))
    }
    public static func append(_ trail: [PayloadFix], fix: PayloadFix) -> [PayloadFix] {
        guard PayloadLocation.validCoord(fix.lat, fix.lon) else { return trail }
        if let last = trail.last {
            let d = Geo.meters(last.lat, last.lon, fix.lat, fix.lon)
            if d < minMeters { return trail }
            let dt = fix.at - last.at
            if dt <= 0 { return trail }
            if d / (Double(dt) / 1000) > maxSpeedMps { return trail }
        }
        return Array((trail + [fix]).suffix(cap))
    }
    public static func consolidate(_ fixes: [PayloadFix]) -> [PayloadFix] {
        fixes.sorted { $0.at < $1.at }.reduce(into: []) { $0 = append($0, fix: $1) }
    }
}
