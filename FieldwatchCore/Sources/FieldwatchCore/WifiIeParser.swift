//
//  WifiIeParser.swift
//  FieldwatchCore
//
//  نقل 1:1 للدالة النقية parseIes من WifiIeParser.kt (مع كل دوالها المساعدة:
//  decodeRates / rsnSummary / wpaSummary / cipherSuite / akmSuite / ouiType).
//
//  هذا الملف هو المفتاح لنسخة iOS على جهاز Jailbreak: نتحصل على الـ IE blob
//  الخام من الـ private API، وهنا نحوّله إلى نفس ما كان ينتجه أندرويد من
//  ScanResult.informationElements — ثم يدخل مباشرة إلى مسار OpenDroneId
//  عبر vendor IE FA:0B:BC type 0x0D.
//
//  ملاحظة: بارامترات ScanResult الخاصة بإصدار النظام (wifiStandard /
//  channelWidth) موجودة في Kotlin فقط لأن أندرويد يعطيها جاهزة؛ على iOS
//  تأتي من مفاتيح الـ scan dictionary الخاصة (انظر WiFiBackendJailbreak.swift).
//

import Foundation

public enum WifiIeParser {

    public struct Parsed: Sendable, Equatable {
        public var rates: String?
        public var security: String?
        public var vendorIes: [VendorIeRecord]
        public var channelFromDs: Int?

        public init(
            rates: String? = nil,
            security: String? = nil,
            vendorIes: [VendorIeRecord] = [],
            channelFromDs: Int? = nil
        ) {
            self.rates = rates
            self.security = security
            self.vendorIes = vendorIes
            self.channelFromDs = channelFromDs
        }
    }

    /// عنصر معلومات واحد خام: رقم العنصر + حمولته.
    public struct Ie: Sendable, Equatable {
        public let id: Int
        public let bytes: [UInt8]

        public init(id: Int, bytes: [UInt8]) {
            self.id = id
            self.bytes = bytes
        }
    }

    /// فك مجموعة IEs ملتقطة — الاختبارات تُغذّي إطارات بلا ScanResult.
    public static func parseIes(_ ies: [Ie], capabilities: String?) -> Parsed {
        var rates = [String]()
        rates.reserveCapacity(16)
        var vendor = [VendorIeRecord]()
        vendor.reserveCapacity(4)
        var sec = [String]()
        sec.reserveCapacity(4)
        var ds: Int?

        for ie in ies {
            let bytes = ie.bytes
            switch ie.id {
            case 1, 50:
                rates.append(contentsOf: decodeRates(bytes))

            case 3:
                if !bytes.isEmpty { ds = Int(bytes[0]) }

            case 48:
                if let s = rsnSummary(bytes) { sec.append(s) }

            case 221:
                if bytes.count >= 3 {
                    let oui = String(
                        format: "%02X:%02X:%02X",
                        Int(bytes[0]), Int(bytes[1]), Int(bytes[2])
                    )
                    let type = bytes.count > 3 ? Int(bytes[3]) : 0
                    let payload: [UInt8] = bytes.count > 4
                        ? Array(bytes[4..<min(bytes.count, 4 + 200)])
                        : []
                    vendor.append(VendorIeRecord(oui: oui, type: type, dataHex: toHexUpper(payload)))
                    if oui == "00:50:F2" && type == 1 {
                        if let s = wpaSummary(bytes) { sec.append(s) }
                    }
                }

            default:
                break
            }
        }

        let cap = capabilities ?? ""
        if sec.isEmpty && !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sec.append(cap)
        }

        let ratesJoined = distinct(rates).joined(separator: " ")
        let secJoined = distinct(sec).joined(separator: " · ")

        let security: String?
        if !secJoined.isEmpty {
            security = secJoined
        } else if !cap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            security = cap
        } else {
            security = nil
        }

        var seen = Set<String>()
        var vendorUnique = [VendorIeRecord]()
        for v in vendor {
            let key = "\(v.oui)#\(v.type)"
            if seen.insert(key).inserted { vendorUnique.append(v) }
        }

        return Parsed(
            rates: ratesJoined.isEmpty ? nil : ratesJoined,
            security: security,
            vendorIes: Array(vendorUnique.prefix(12)),
            channelFromDs: ds
        )
    }

    // MARK: - Private (مطابقة للدوال الخاصة في Kotlin)

    private static func decodeRates(_ bytes: [UInt8]) -> [String] {
        bytes.map { b in
            let raw = Int(b)
            let basic = (raw & 0x80) != 0
            let mbps = Double(raw & 0x7F) / 2.0
            let label = (mbps == mbps.rounded()) ? String(Int(mbps)) : String(mbps)
            return basic ? "\(label)*" : label
        }
    }

    private static func rsnSummary(_ bytes: [UInt8]) -> String? {
        if bytes.count < 8 { return nil }
        var o = 0
        let ver = u16(bytes, o); o += 2
        if ver != 1 { return "RSN v\(ver)" }
        let group = cipherSuite(bytes, o); o += 4
        if o + 2 > bytes.count { return "RSN \(group)" }

        let pc = u16(bytes, o); o += 2
        var pairwise = [String]()
        pairwise.reserveCapacity(pc)
        for _ in 0..<pc {
            if o + 4 > bytes.count { continue }   // Kotlin: return@repeat == continue
            pairwise.append(cipherSuite(bytes, o)); o += 4
        }
        if o + 2 > bytes.count {
            return "RSN \(group) / \(pairwise.joined(separator: ","))"
        }

        let ac = u16(bytes, o); o += 2
        var akm = [String]()
        akm.reserveCapacity(ac)
        for _ in 0..<ac {
            if o + 4 > bytes.count { continue }
            akm.append(akmSuite(bytes, o)); o += 4
        }

        let akmJoined = akm.joined(separator: "/")
        let pairJoined = pairwise.joined(separator: "/")
        var out = "RSN "
        out += akmJoined.isEmpty ? "AKM?" : akmJoined
        out += " "
        out += pairJoined.isEmpty ? group : pairJoined
        if !group.isEmpty { out += " (group \(group))" }
        return out
    }

    private static func wpaSummary(_ bytes: [UInt8]) -> String? {
        if bytes.count < 10 { return "WPA" }
        var o = 4
        let ver = u16(bytes, o); o += 2
        if ver != 1 { return "WPA v\(ver)" }
        let group = cipherSuite(bytes, o); o += 4
        if o + 2 > bytes.count { return "WPA \(group)" }

        let pc = u16(bytes, o); o += 2
        var pairwise = [String]()
        pairwise.reserveCapacity(pc)
        for _ in 0..<pc {
            if o + 4 > bytes.count { continue }
            pairwise.append(cipherSuite(bytes, o)); o += 4
        }
        let joined = pairwise.joined(separator: "/")
        return "WPA \(joined.isEmpty ? group : joined)"
    }

    private static func cipherSuite(_ bytes: [UInt8], _ offset: Int) -> String {
        guard let (oui, type) = ouiType(bytes, offset) else { return "?" }
        if oui == "000FAC" || oui == "0050F2" {
            switch type {
            case 0: return "Group"
            case 1: return "WEP-40"
            case 2: return "TKIP"
            case 4: return "CCMP"
            case 5: return "WEP-104"
            case 6: return "BIP"
            case 8: return "GCMP"
            case 9: return "GCMP-256"
            case 10: return "CCMP-256"
            default: return "cipher \(type)"
            }
        }
        return "\(oui)/\(type)"
    }

    private static func akmSuite(_ bytes: [UInt8], _ offset: Int) -> String {
        guard let (oui, type) = ouiType(bytes, offset) else { return "?" }
        if oui == "000FAC" {
            switch type {
            case 1: return "802.1X"
            case 2: return "PSK"
            case 3: return "FT-802.1X"
            case 4: return "FT-PSK"
            case 5: return "802.1X-SHA256"
            case 6: return "PSK-SHA256"
            case 8: return "SAE"
            case 9: return "FT-SAE"
            case 11: return "SUITE-B"
            case 12: return "SUITE-B-192"
            case 18: return "OWE"
            default: return "AKM \(type)"
            }
        }
        return "\(oui)/\(type)"
    }

    private static func ouiType(_ bytes: [UInt8], _ offset: Int) -> (String, Int)? {
        if offset + 4 > bytes.count { return nil }
        let oui = String(
            format: "%02X%02X%02X",
            Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2])
        )
        return (oui, Int(bytes[offset + 3]))
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) -> Int {
        if offset + 1 >= bytes.count { return 0 }
        return Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
    }

    private static func distinct<T: Hashable>(_ arr: [T]) -> [T] {
        var seen = Set<T>()
        var out = [T]()
        for v in arr where seen.insert(v).inserted { out.append(v) }
        return out
    }
}
