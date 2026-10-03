//
//  PayloadLocation.swift
//  FieldwatchCore
//
//  نقل 1:1 لـ PayloadLocation.kt (الحقول + pin() + mergeSticky() + validCoord()).
//  دوال fromDecoded/fromSighting تحتاج Models.swift الكامل (DecodedFieldValue /
//  Sighting) — مُعلَّمة كخطوة تالية في خطة النقل، وليست TODO صامتة.
//

import Foundation

public struct PayloadLocation: Sendable, Equatable {
    public var lat: Double?
    public var lon: Double?
    public var alt: Double?
    public var opLat: Double?
    public var opLon: Double?
    public var uasId: String?
    public var selfId: String?
    public var headingDeg: Double?
    public var speedMps: Double?
    public var vspeedMps: Double?

    public init(
        lat: Double? = nil,
        lon: Double? = nil,
        alt: Double? = nil,
        opLat: Double? = nil,
        opLon: Double? = nil,
        uasId: String? = nil,
        selfId: String? = nil,
        headingDeg: Double? = nil,
        speedMps: Double? = nil,
        vspeedMps: Double? = nil
    ) {
        self.lat = lat
        self.lon = lon
        self.alt = alt
        self.opLat = opLat
        self.opLon = opLon
        self.uasId = uasId
        self.selfId = selfId
        self.headingDeg = headingDeg
        self.speedMps = speedMps
        self.vspeedMps = vspeedMps
    }

    /// Kotlin: pin(): Pair<Double,Double>?
    public func pin() -> (lat: Double, lon: Double)? {
        guard PayloadLocation.validCoord(lat, lon), let lat, let lon else { return nil }
        return (lat, lon)
    }

    /// Kotlin: mergeSticky(prev) — رسائل ASTM تتناوب، فاحتفظ بآخر قيمة صالحة.
    public func mergeSticky(_ prev: PayloadLocation?) -> PayloadLocation {
        let p = prev ?? PayloadLocation()

        let nextLat: Double?
        let nextLon: Double?
        if PayloadLocation.validCoord(lat, lon) {
            nextLat = lat
            nextLon = lon
        } else {
            nextLat = p.lat
            nextLon = p.lon
        }

        let nextOpLat: Double?
        let nextOpLon: Double?
        if PayloadLocation.validCoord(opLat, opLon) {
            nextOpLat = opLat
            nextOpLon = opLon
        } else {
            nextOpLat = p.opLat
            nextOpLon = p.opLon
        }

        let nextAlt = (alt?.isFinite == true) ? alt : p.alt
        let nextUas = (uasId?.isEmpty == false ? uasId : p.uasId)
        let nextSelf = (selfId?.isEmpty == false ? selfId : p.selfId)
        let nextHeading = (headingDeg?.isFinite == true) ? headingDeg : p.headingDeg
        let nextSpeed = (speedMps?.isFinite == true) ? speedMps : p.speedMps
        let nextVSpeed = (vspeedMps?.isFinite == true) ? vspeedMps : p.vspeedMps

        return PayloadLocation(
            lat: nextLat,
            lon: nextLon,
            alt: nextAlt,
            opLat: nextOpLat,
            opLon: nextOpLon,
            uasId: nextUas,
            selfId: nextSelf,
            headingDeg: nextHeading,
            speedMps: nextSpeed,
            vspeedMps: nextVSpeed
        )
    }

    // MARK: - companion object

    public static let LAT = "latitude"
    public static let LON = "longitude"
    public static let OP_LAT = "op_lat"
    public static let OP_LON = "op_lon"

    /// Kotlin: validCoord — نفس الشروط بالحرف.
    public static func validCoord(_ lat: Double?, _ lon: Double?) -> Bool {
        guard let lat, let lon else { return false }
        if !lat.isFinite || !lon.isFinite { return false }
        if lat == 0.0 && lon == 0.0 { return false }
        if !(-90.0...90.0).contains(lat) { return false }
        if !(-180.0...180.0).contains(lon) { return false }
        return true
    }
}
