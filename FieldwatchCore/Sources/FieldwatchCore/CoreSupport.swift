//
//  CoreSupport.swift
//  FieldwatchCore
//
//  أدوات مساعدة منقولة 1:1 من Kotlin، ويحتاجها المحرّك والكتالوج:
//   • MacUtil            ← Models.kt:870  (ملاحظة: نسخة الطرف الآخر كانت تقصّ إلى 12 خانة وتُرجع "" — غير أمينة)
//   • DetectionPolicy    ← Models.kt:647  (نسخة الطرف الآخر كانت حقلًا واحدًا `enabled` — غير أمينة، الأربعة حقول مستعملة في التطبيق)
//   • uuidAliases / uuidShortOrFull ← Models.kt
//   • TrackerMatch       ← Geo.kt:357
//   • CatalogLoader      ← قارئ الكتالوج (الملف الرسمي كما هو)
//

import Foundation

// MARK: - MacUtil (منقولة من Models.kt)

public enum MacUtil {

    /// Kotlin: fun normalize(raw) — لا تقصّ إلى 12 ولا تُفرغ العناوين القصيرة.
    public static func normalize(_ raw: String) -> String {
        let hex = raw.filter { $0.isLetter || $0.isNumber }.uppercased()
        if hex.count < 2 { return raw.uppercased() }
        return stride(from: 0, to: hex.count, by: 2).map { i -> String in
            let start = hex.index(hex.startIndex, offsetBy: i)
            let end = hex.index(start, offsetBy: min(2, hex.count - i))
            return String(hex[start..<end])
        }.joined(separator: ":")
    }

    public static func prefixBytes(_ mac: String, _ n: Int = 3) -> String {
        let parts = normalize(mac).split(separator: ":")
        return parts.prefix(min(n, parts.count)).joined(separator: ":")
    }

    public static func isRandomized(_ mac: String) -> Bool {
        let first = normalize(mac).split(separator: ":").first.map(String.init) ?? ""
        guard let v = Int(first, radix: 16) else { return false }
        return (v & 0x02) != 0 && (v & 0x01) == 0
    }

    /// 24-bit OUI بعد تصفير بت «محلي الإدارة». عناوين الشبكات الافتراضية
    /// (guest/mesh/SSID إضافي) ترفع هذا البت على بادئة المصنّع الأصلية.
    public static func wifiOui24Universal(_ mac: String) -> String? {
        let hex = normalize(mac).replacingOccurrences(of: ":", with: "")
        if hex.count < 6 { return nil }
        let hexChars = Array(hex)
        guard let first = Int(String(hexChars[0...1]), radix: 16) else { return nil }
        if (first & 0x02) == 0 { return nil }
        if (first & 0x01) != 0 { return nil }
        let masked = String(format: "%02X", first & 0xFD)
        return masked + String(hexChars[2..<6])
    }

    public static func matchesPrefix(_ mac: String, _ prefix: String) -> Bool {
        let m = normalize(mac).replacingOccurrences(of: ":", with: "")
        let p = prefix.filter { $0.isLetter || $0.isNumber }.uppercased()
        if p.isEmpty { return false }
        return m.hasPrefix(p)
    }

    public static func last16(_ mac: String) -> Int {
        let hex = normalize(mac).replacingOccurrences(of: ":", with: "")
        if hex.count < 4 { return 0 }
        return Int(String(hex.suffix(4)), radix: 16) ?? 0
    }
}

// MARK: - DetectionPolicy (منقولة من Models.kt:647)

/// Kotlin: data class DetectionPolicy(ssidKeywords, knownOuis, vendorIes, bleRaven) — كلها true افتراضيًا.
public struct DetectionPolicy: Codable, Sendable, Equatable {
    public var ssidKeywords: Bool
    public var knownOuis: Bool
    public var vendorIes: Bool
    public var bleRaven: Bool

    public init(ssidKeywords: Bool = true, knownOuis: Bool = true, vendorIes: Bool = true, bleRaven: Bool = true) {
        self.ssidKeywords = ssidKeywords
        self.knownOuis = knownOuis
        self.vendorIes = vendorIes
        self.bleRaven = bleRaven
    }
}

// MARK: - UUID aliases (منقولة من Models.kt)

/// Kotlin: fun uuidAliases(raw): نسخة البادئة 16-bit ومعرّفات Bluetooth SIG القاعدة.
public func uuidAliases(_ raw: String) -> Set<String> {
    let hex = raw.filter { $0.isLetter || $0.isNumber }.uppercased()
    var out: Set<String> = [raw.uppercased(), hex]
    if hex.count == 4 {
        out.insert("0x" + hex)
        out.insert("0000\(hex)-0000-1000-8000-00805F9B34FB")
        out.insert("0000\(hex)00001000800000805F9B34FB")
        return out
    }
    if hex.count == 32, hex.hasPrefix("0000"), hex.hasSuffix("00001000800000805F9B34FB") {
        let start = hex.index(hex.startIndex, offsetBy: 4)
        let end = hex.index(start, offsetBy: 4)
        let short = String(hex[start..<end])
        out.insert(short)
        out.insert("0x" + short)
        out.insert("0000\(short)-0000-1000-8000-00805F9B34FB")
    }
    return out
}

/// Kotlin: fun uuidShortOrFull(raw)
public func uuidShortOrFull(_ raw: String) -> String {
    let hex = raw.filter { $0.isLetter || $0.isNumber }.uppercased()
    if hex.count == 4 { return "0000\(hex)-0000-1000-8000-00805F9B34FB" }
    return raw.uppercased()
}

/// Kotlin: private fun hexOnly(raw) — يزيل كل ما ليس حرفًا/رقمًا ويرفع الحالة.
public func hexOnly(_ raw: String) -> String {
    if raw.isEmpty { return raw }
    let needsClean = raw.contains { !($0.isLetter || $0.isNumber) }
    if !needsClean { return raw.uppercased() }
    return raw.filter { $0.isLetter || $0.isNumber }.uppercased()
}

/// Kotlin: private fun reverseHexBytes(hex)
func reverseHexBytes(_ hex: String) -> String {
    let h = hexOnly(hex)
    guard h.count >= 2, h.count % 2 == 0 else { return "" }
    let chars = Array(h)
    var out = ""
    var i = chars.count
    while i >= 2 {
        i -= 2
        out.append(contentsOf: [chars[i], chars[i + 1]])
    }
    return out
}

// MARK: - TrackerMatch (منقولة من Geo.kt:357)

public enum TrackerMatch {

    public enum Kind: String, Sendable { case finder = "FINDER", beacon = "BEACON", wearable = "WEARABLE" }

    static let finderTokens = [
        "airtag", "smarttag", "tile", "chipolo", "pebblebee", "moto tag", "find my",
        "find hub", "dult",
    ]
    static let beaconTokens = ["ibeacon", "minew", "estimote", "kontakt"]
    static let wearableTokens = ["garmin", "fitbit", "oura"]

    /// Apple Continuity / pairing types — وليس Offline Finding 0x12.
    static let appleContinuityPrefixes: Set<String> = [
        "05", "07", "08", "09", "0A", "0B", "0C", "0D", "0E", "0F", "10",
    ]

    public static func isTrackerFleet(_ name: String) -> Bool {
        let n = name.lowercased()
        return finderTokens.contains { n.contains($0) }
    }

    static func mfgPrefix(_ rec: MfgRecord) -> String {
        String(hexOnly(rec.dataHex).prefix(2))
    }

    public static func isFindMyPayload(_ device: Sighting) -> Bool {
        if isAppleContinuity(device) { return false }
        if device.facts.mfgRecords.contains(where: { $0.companyId == 0x004C && mfgPrefix($0) == "12" }) {
            return true
        }
        let hex = device.manufacturerDataHex.filter { $0.isLetter || $0.isNumber }.uppercased()
        return device.manufacturerId == 0x004C && String(hex.prefix(2)) == "12"
    }

    /// Nearby Info / Handoff / AirDrop / AirPods … — هاتف أو ماك أو سماعات، لا وسم.
    public static func isAppleContinuity(_ device: Sighting) -> Bool {
        var recs = device.facts.mfgRecords
        if recs.isEmpty {
            guard let id = device.manufacturerId else { return false }
            recs = [MfgRecord(companyId: id, dataHex: device.manufacturerDataHex)]
        }
        return recs.contains { rec in
            rec.companyId == 0x004C && appleContinuityPrefixes.contains(mfgPrefix(rec))
        }
    }
}

// MARK: - كتالوج التواقيع: قارئ الملف

public enum CatalogLoader {

    /// يحمّل كتالوجًا من ملف JSON. يُقبل ملف Fieldwatch الأصلي كما هو.
    public static func load(from data: Data) throws -> SignatureCatalogDocument {
        try JSONDecoder().decode(SignatureCatalogDocument.self, from: data)
    }

    public static func load(from url: URL) throws -> SignatureCatalogDocument {
        try load(from: Data(contentsOf: url))
    }
}
