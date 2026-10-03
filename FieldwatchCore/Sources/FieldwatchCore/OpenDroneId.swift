//
//  OpenDroneId.swift
//  FieldwatchCore
//
//  نقل حرفي لـ OpenDroneId.kt (ASTM F3411 / OpenDroneID) من Fieldwatch 1.1.17:
//  BLE service data FFFA، و Wi-Fi vendor IE FA:0B:BC type 0x0D، وإطار الـ
//  message pack (nibble 0xF)، وإعادة التأطير بشكل BLE FFFA حتى تستعمل حقول
//  Remote ID نفسها في كلا الراديوين.
//
//  الاتجاه (heading) يتبع opendroneid.c: بايت الاتجاه + علم east/west
//  (لا مقياس ×2 الموجود في الكتالوج).
//

import Foundation

public enum OpenDroneId {

    public static let BLE_UUID = "FFFA"
    public static let WIFI_OUI = "FA:0B:BC"
    public static let WIFI_TYPE = 0x0D

    private static let MSG = 25
    private static let INV_DIR = 255
    private static let INV_SPEED = 255

    // MARK: - Public API

    /// Kotlin: fromFacts(facts): يمشي على service data (FFFA) و vendor IEs (FA:0B:BC/13).
    public static func fromFacts(_ facts: RadioFacts) -> PayloadLocation {
        var acc = PayloadLocation()

        for sd in facts.serviceData {
            guard uuid16(sd.uuid) == 0xFFFA else { continue }
            acc = parseMessages(messagesBle(sd.dataHex)).mergeSticky(acc)
        }

        for ie in facts.vendorIes {
            guard ie.oui.uppercased() == WIFI_OUI, ie.type == WIFI_TYPE else { continue }
            acc = parseMessages(messagesWifi(ie.dataHex)).mergeSticky(acc)
        }

        return acc
    }

    /// Kotlin: wifiFffaPayloads — Wi-Fi Remote ID مأطَّر كأنه BLE FFFA
    /// (`0x0D` + counter + كل رسالة 25 بايت) لتُطابق حقول Decode في الكتالوج.
    public static func wifiFffaPayloads(_ facts: RadioFacts) -> [String] {
        var out = [String]()
        for ie in facts.vendorIes {
            guard ie.oui.uppercased() == WIFI_OUI, ie.type == WIFI_TYPE else { continue }
            out.append(contentsOf: wrapWifiAsFffa(ie.dataHex))
        }
        return out
    }

    // MARK: - Framing (internal — كي تُختبر كما في Kotlin)

    static func wrapWifiAsFffa(_ dataHex: String) -> [String] {
        guard let b = hexBytes(dataHex), !b.isEmpty else { return [] }
        let bleShaped = b.count >= 2 + MSG && b[0] == 0x0D
        let start = bleShaped ? 2 : 1
        if start > b.count { return [] }
        let counter = bleShaped ? Int(b[1]) : Int(b[0])
        return framedMessages(b, start: start).map { msg in
            var s = String(format: "0D%02X", counter)
            for byte in msg { s += String(format: "%02X", Int(byte)) }
            return s
        }
    }

    static func messagesBle(_ dataHex: String) -> [[UInt8]] {
        guard let b = hexBytes(dataHex), !b.isEmpty else { return [] }
        let start = (b.count >= 2 + MSG && b[0] == 0x0D) ? 2 : 0
        return framedMessages(b, start: start)
    }

    static func messagesWifi(_ dataHex: String) -> [[UInt8]] {
        guard let b = hexBytes(dataHex), !b.isEmpty else { return [] }
        // BLE-shaped [0x0D][counter][msgs] أو ASTM [counter][msgs].
        let start = (b.count >= 2 + MSG && b[0] == 0x0D) ? 2 : 1
        return framedMessages(b, start: start)
    }

    /// رسائل 25 بايت مفردة، أو message pack (type nibble 0xF).
    private static func framedMessages(_ b: [UInt8], start: Int) -> [[UInt8]] {
        guard start < b.count else { return [] }
        let head = Int(b[start])
        if head >> 4 == 0xF && start + 3 <= b.count {
            let size = max(Int(b[start + 1]), MSG)
            let count = Int(b[start + 2])
            var out = [[UInt8]]()
            out.reserveCapacity(count)
            var i = start + 3
            for _ in 0..<count {
                if i + MSG > b.count { continue } // Kotlin: return@repeat == continue
                out.append(Array(b[i..<(i + MSG)]))
                i += size
            }
            return out
        }
        return chunks(b, start: start)
    }

    private static func chunks(_ b: [UInt8], start: Int) -> [[UInt8]] {
        guard start + MSG <= b.count else { return [] }
        var out = [[UInt8]]()
        out.reserveCapacity((b.count - start) / MSG)
        var i = start
        while i + MSG <= b.count {
            out.append(Array(b[i..<(i + MSG)]))
            i += MSG
        }
        return out
    }

    static func parseMessages(_ msgs: [[UInt8]]) -> PayloadLocation {
        var acc = PayloadLocation()
        for m in msgs where m.count >= MSG {
            acc = parseOne(m).mergeSticky(acc)
        }
        return acc
    }

    private static func parseOne(_ m: [UInt8]) -> PayloadLocation {
        switch Int(m[0]) >> 4 {
        case 0: return basicId(m)
        case 1: return location(m)
        case 3: return selfId(m)
        case 4: return systemMsg(m)
        default: return PayloadLocation()
        }
    }

    // MARK: - Message bodies

    private static func location(_ m: [UInt8]) -> PayloadLocation {
        let flags = Int(m[1])
        let ew = (flags >> 1) & 1
        let speedMult = flags & 1

        let dirRaw = Int(m[2])
        let heading: Double?
        if dirRaw == INV_DIR {
            heading = nil
        } else {
            heading = Double((dirRaw + (ew == 1 ? 180 : 0)) % 360)
        }

        let sh = Int(m[3])
        let speed: Double?
        if sh == INV_SPEED {
            speed = nil
        } else if speedMult == 0 {
            speed = Double(sh) * 0.25
        } else {
            speed = Double(sh) * 0.75 + 255 * 0.25
        }

        let vspeed = Double(Int8(bitPattern: m[4])) * 0.5
        let lat = Double(i32le(m, 5)) * 1e-7
        let lon = Double(i32le(m, 9)) * 1e-7
        let altGeo = Double(u16le(m, 15)) * 0.5 - 1000.0

        return PayloadLocation(
            lat: lat,
            lon: lon,
            alt: altGeo,
            headingDeg: heading,
            speedMps: speed,
            vspeedMps: vspeed
        )
    }

    private static func basicId(_ m: [UInt8]) -> PayloadLocation {
        let id = ascii(m[2..<22])
        return PayloadLocation(uasId: id.isEmpty ? nil : id)
    }

    private static func selfId(_ m: [UInt8]) -> PayloadLocation {
        let text = ascii(m[2..<25])
        return PayloadLocation(selfId: text.isEmpty ? nil : text)
    }

    private static func systemMsg(_ m: [UInt8]) -> PayloadLocation {
        let lat = Double(i32le(m, 2)) * 1e-7
        let lon = Double(i32le(m, 6)) * 1e-7
        return PayloadLocation(opLat: lat, opLon: lon)
    }

    // MARK: - Byte helpers

    private static func ascii(_ bytes: ArraySlice<UInt8>) -> String {
        // Kotlin: toString(Charsets.US_ASCII).trim('\u0000', ' ')
        let s = String(decoding: bytes, as: UTF8.self)
        return s.trimmingCharacters(in: CharacterSet(charactersIn: "\u{0} "))
    }

    private static func i32le(_ m: [UInt8], _ at: Int) -> Int32 {
        let v = UInt32(m[at])
            | (UInt32(m[at + 1]) << 8)
            | (UInt32(m[at + 2]) << 16)
            | (UInt32(m[at + 3]) << 24)
        return Int32(bitPattern: v)
    }

    private static func u16le(_ m: [UInt8], _ at: Int) -> Int {
        Int(m[at]) | (Int(m[at + 1]) << 8)
    }

    private static func uuid16(_ uuid: String) -> Int? {
        let hex = uuid.filter { $0.isLetter || $0.isNumber }
        if hex.count == 4 { return Int(hex, radix: 16) }
        if hex.count >= 8 && hex.lowercased().hasPrefix("0000") {
            let s = hex.dropFirst(4).prefix(4)
            return Int(s, radix: 16)
        }
        return Int(hex.prefix(4), radix: 16)
    }
}
