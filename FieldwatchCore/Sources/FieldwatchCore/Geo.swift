import Foundation

public enum Geo {
    public static func meters(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180.0
        let p2 = lat2 * .pi / 180.0
        let dp = (lat2 - lat1) * .pi / 180.0
        let dl = (lon2 - lon1) * .pi / 180.0
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(max(0, 1 - a)))
    }

    public static func pathLengthM(_ samples: [GpsSample]) -> Double {
        guard samples.count > 1 else { return 0 }
        var sum = 0.0
        for i in 1..<samples.count { sum += meters(samples[i-1].lat, samples[i-1].lon, samples[i].lat, samples[i].lon) }
        return sum
    }

    public static func spanM(_ samples: [GpsSample]) -> Double {
        guard samples.count > 1 else { return 0 }
        var best = 0.0
        for i in samples.indices { for j in (i+1)..<samples.count { best = max(best, meters(samples[i].lat,samples[i].lon,samples[j].lat,samples[j].lon)) } }
        return best
    }

    public struct PathLeg: Sendable, Equatable {
        public let stay: Bool
        public let startAt: Int64
        public let endAt: Int64
        public let lat: Double
        public let lon: Double
        public let endLat: Double
        public let endLon: Double
        public let samples: Int
        public let pathM: Double
        public var durationMs: Int64 { max(0, endAt - startAt) }
        public func cellKey() -> String { Geo.cellKey(lat, lon) }
    }

    public static func cellKey(_ lat: Double, _ lon: Double) -> String { String(format: "%.4f,%.4f", lat, lon) }

    public static func screenCoord(_ lat: Double?, _ lon: Double?, _ demo: Bool) -> String? {
        guard let lat, let lon else { return nil }
        if demo { return "masked" }
        return String(format: "%.5f, %.5f", lat, lon)
    }

    public static func redactCoordsIn(_ text: String, _ demo: Bool) -> String {
        guard demo, !text.isEmpty else { return text }
        guard let re = try? NSRegularExpression(pattern: #"-?\d{1,3}\.\d{3,8}\s*,\s*-?\d{1,3}\.\d{3,8}"#) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return re.stringByReplacingMatches(in: text, range: range, withTemplate: "masked")
    }

    public static func legs(_ samples: [GpsSample], stayM: Double = 40.0, minStayMs: Int64 = 40_000, now: Int64? = nil) -> [PathLeg] {
        guard !samples.isEmpty else { return [] }
        let effectiveNow = now ?? samples.last!.at
        var clusters = [[GpsSample]]()
        var cur = [samples[0]]
        var cLat = samples[0].lat, cLon = samples[0].lon
        for s in samples.dropFirst() {
            if meters(cLat,cLon,s.lat,s.lon) <= stayM {
                cur.append(s)
                cLat = cur.reduce(0.0) { $0 + $1.lat } / Double(cur.count)
                cLon = cur.reduce(0.0) { $0 + $1.lon } / Double(cur.count)
            } else {
                clusters.append(cur); cur=[s]; cLat=s.lat; cLon=s.lon
            }
        }
        clusters.append(cur)
        var classified=[PathLeg]()
        for i in clusters.indices {
            let cluster=clusters[i], first=cluster[0], last=cluster[cluster.count-1]
            let nextStart=clusters.indices.contains(i+1) ? clusters[i+1][0].at : nil
            let endAt=max(last.at,nextStart ?? effectiveNow)
            let lat=cluster.reduce(0.0){$0+$1.lat}/Double(cluster.count)
            let lon=cluster.reduce(0.0){$0+$1.lon}/Double(cluster.count)
            let dur=max(0,endAt-first.at)
            let stay=clusters.count == 1 || dur >= minStayMs || spanM(cluster) <= 25.0
            classified.append(PathLeg(stay:stay,startAt:first.at,endAt:endAt,lat:lat,lon:lon,endLat:last.lat,endLon:last.lon,samples:cluster.count,pathM:pathLengthM(cluster)))
        }
        var merged=[PathLeg]()
        for leg in classified {
            if let last=merged.last, !last.stay && !leg.stay {
                merged[merged.count-1]=PathLeg(stay:false,startAt:last.startAt,endAt:leg.endAt,lat:last.lat,lon:last.lon,endLat:leg.endLat,endLon:leg.endLon,samples:last.samples+leg.samples,pathM:last.pathM + meters(last.endLat,last.endLon,leg.lat,leg.lon)+leg.pathM)
            } else { merged.append(leg) }
        }
        return Array(merged.prefix(10))
    }

    public static let SPIKE_MAX_SPEED_MPS = 42.0
    public static let SPIKE_MIN_HOP_M = 40.0
    public static let SPIKE_MIN_DT_MS: Int64 = 800

    public static func hopPlausible(from: GpsSample, lat: Double, lon: Double, at: Int64, maxSpeedMps: Double = SPIKE_MAX_SPEED_MPS) -> Bool {
        let d=meters(from.lat,from.lon,lat,lon), dt=at-from.at
        if d <= SPIKE_MIN_HOP_M || dt < SPIKE_MIN_DT_MS { return true }
        return d / (Double(max(dt,1))/1000.0) <= maxSpeedMps
    }

    public static func despikePath(_ samples: [GpsSample]) -> [GpsSample] {
        guard samples.count >= 2 else { return samples }
        var cur=samples
        for _ in 0..<4 {
            let next=despikeOnce(cur)
            if next.count == cur.count { return next }
            cur=next; if cur.count < 2 { return cur }
        }
        return cur
    }

    private static func despikeOnce(_ samples: [GpsSample]) -> [GpsSample] {
        guard samples.count >= 2 else { return samples }
        var out=[samples[0]], i=1
        while i < samples.count {
            let prev=out.last!, cur=samples[i], next=i+1<samples.count ? samples[i+1] : nil
            if let next {
                let dAb=meters(prev.lat,prev.lon,cur.lat,cur.lon), dBc=meters(cur.lat,cur.lon,next.lat,next.lon), dAc=meters(prev.lat,prev.lon,next.lat,next.lon)
                if dAb > SPIKE_MIN_HOP_M && dBc > SPIKE_MIN_HOP_M && dAc < dAb*0.4 && dAc < dBc*0.4 { i += 1; continue }
            }
            if !hopPlausible(from:prev,lat:cur.lat,lon:cur.lon,at:cur.at) { i += 1; continue }
            out.append(cur); i += 1
        }
        return out.count >= 2 ? out : [samples.first!,samples.last!]
    }

    public static func append(_ trail: [GpsSample], at: Int64, lat: Double, lon: Double, rssi: Int, cap: Int = 48) -> [GpsSample] {
        if let last=trail.last {
            let d=meters(last.lat,last.lon,lat,lon)
            if d < 8 { return trail }
            if d < 18 && at-last.at < 30_000 { return trail }
        }
        return capSpread(trail + [GpsSample(at:at,lat:lat,lon:lon,rssi:rssi)], cap:cap)
    }

    public static func capSpread(_ samples: [GpsSample], cap: Int) -> [GpsSample] {
        if samples.count <= cap { return samples }
        if cap <= 1 { return [samples.last!] }
        if cap == 2 { return [samples.first!,samples.last!] }
        let lastIndex=samples.count-1
        var out=[GpsSample]()
        for i in 0..<cap {
            let idx=(i*lastIndex)/(cap-1), s=samples[idx]
            if out.last?.at != s.at { out.append(s) }
        }
        if out.last?.at != samples.last?.at { out.append(samples.last!) }
        return out
    }
}
