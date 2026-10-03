//
//  CoTravel.swift
//  FieldwatchCore
//
//  نقل 1:1 لـ CoTravel من Geo.kt.
//
//  المرافقة الحية، BLE فقط. GPS الهاتف يُوسم وقت السماع. حقيبة/وسم سيارة
//  يبقى عاليًا على طول المسار. نقاط وصول Wi-Fi مستثناة: AP عالٍ تمرّ به
//  يرسم مئات الأمتار من مسارك فيبدو كأنه تحرّك معك.
//  الرفض الرخيص أولًا (RSSI عالٍ) حتى لا تصبح القائمة O(n²) على GPS كل راديو.
//

import Foundation

public enum CoTravel {

    public static let MOVE_M = 45.0
    public static let NEAR_M = 50.0
    public static let HEARD_MS: Int64 = 90_000
    public static let LOUD_DBM = -70
    public static let TRAIL_LOUD_DBM = -75

    public struct Ctx: Sendable, Equatable {
        public var pathLengthM: Double
        public var durationMs: Int64
        public var here: GpsSample?
        public var ready: Bool

        public init(pathLengthM: Double, durationMs: Int64, here: GpsSample?, ready: Bool) {
            self.pathLengthM = pathLengthM
            self.durationMs = durationMs
            self.here = here
            self.ready = ready
        }

        public static let none = Ctx(pathLengthM: 0, durationMs: 0, here: nil, ready: false)

        /// Kotlin: Ctx.of(path)
        public static func of(_ path: [GpsSample]) -> Ctx {
            if path.count < 2 { return .none }
            let len = Geo.pathLengthM(path)
            let dur = max(path[path.count - 1].at - path[0].at, 0)
            return Ctx(pathLengthM: len, durationMs: dur, here: path.last, ready: len >= MOVE_M)
        }
    }

    private struct TrailGeom: Sendable, Equatable {
        var n: Int
        var at: Int64
        var lat: Double
        var lon: Double
        var len: Double
        var bbox: Double
    }

    /// الكاش في Kotlin هو ConcurrentHashMap؛ هنا صف محمي بقفل بنفس الدلالة
    /// (يُفرَّغ عند تجاوز 1024 مدخلًا). الصف `@unchecked Sendable` لأن القفل هو
    /// ما يضمن السلامة — وهذا يجعل الملف يُصرَّف بلا تحذيرات تحت Swift 6 أيضًا.
    private final class GeomCache: @unchecked Sendable {
        private var store: [String: TrailGeom] = [:]
        private let lock = NSLock()

        func get(_ key: String) -> TrailGeom? {
            lock.lock(); defer { lock.unlock() }
            return store[key]
        }

        func put(_ key: String, _ value: TrailGeom) {
            lock.lock(); defer { lock.unlock() }
            if store.count > 1024 { store.removeAll(keepingCapacity: true) }
            store[key] = value
        }
    }

    private static let cache = GeomCache()

    public static func withYou(
        _ device: Sighting,
        _ ctx: Ctx,
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) -> Bool {
        if device.kind == .wifi { return false }
        guard ctx.ready, let here = ctx.here else { return false }
        if now - device.lastSeen > HEARD_MS { return false }
        // آخر حزمة قد تهبط على طريق سريع؛ الرفض الرخيص هو أرضية المسار لا −70 اللحظية.
        if device.rssi < TRAIL_LOUD_DBM { return false }
        let trail = device.gpsTrail
        if trail.count < 2 { return false }
        guard let geom = geomFor(device.key, trail) else { return false }
        if geom.bbox < MOVE_M * 0.6 { return false }
        var loud = 0
        for s in trail where s.rssi >= TRAIL_LOUD_DBM { loud += 1 }
        if loud < (trail.count * 2 + 2) / 3 { return false }
        if geom.len < MOVE_M * 0.6 { return false }
        guard let last = trail.last else { return false }
        let moved = Geo.meters(here.lat, here.lon, last.lat, last.lon)
        // آخر وسم GPS هو الهاتف وقت السماع. 50 م قيادة ≈ 2 ث على طريق سريع،
        // لذا وسم يعلن كل ثوانٍ يومض بلا هامش يراعي السرعة.
        let seconds = max(Double(ctx.durationMs) / 1000.0, 1.0)
        let speed = min(max(ctx.pathLengthM / seconds, 0), 40)
        let allowM = max(NEAR_M, speed * 15.0) + 25.0
        return moved <= allowM
    }

    private static func geomFor(_ key: String, _ trail: [GpsSample]) -> TrailGeom? {
        guard let last = trail.last else { return nil }

        if let hit = cache.get(key),
           hit.n == trail.count, hit.at == last.at,
           hit.lat == last.lat, hit.lon == last.lon {
            return hit
        }

        let next = TrailGeom(
            n: trail.count,
            at: last.at,
            lat: last.lat,
            lon: last.lon,
            len: Geo.pathLengthM(trail),
            bbox: bboxSpanM(trail)
        )
        cache.put(key, next)
        return next
    }

    /// Kotlin: bboxSpanM — مسافة قطر الصندوق المحيط.
    private static func bboxSpanM(_ samples: [GpsSample]) -> Double {
        guard let first = samples.first else { return 0 }
        var minLat = first.lat
        var maxLat = first.lat
        var minLon = first.lon
        var maxLon = first.lon
        for i in 1..<samples.count {
            let s = samples[i]
            if s.lat < minLat { minLat = s.lat }
            if s.lat > maxLat { maxLat = s.lat }
            if s.lon < minLon { minLon = s.lon }
            if s.lon > maxLon { maxLon = s.lon }
        }
        return Geo.meters(minLat, minLon, maxLat, maxLon)
    }
}
