//
//  SignatureFieldDecoder.swift
//  FieldwatchCore
//
//  نقل 1:1 من SignatureFieldDecoder.kt (450 سطرًا).
//  أُصلح في هذا الملف — بعد مراجعة السطر بالسطر مقابل Kotlin — سبعة انحرافات كانت في نسخة
//  الطرف الآخر (معلَّمة بـ FIX-NN أدناه):
//   FIX-01  MANUFACTURER_DATA لا يُفكّ إلا لأجهزة BLE (Kotlin: `if (device.kind != RadioKind.BLE) emptyList()`)
//   FIX-02  SERVICE_DATA يتطلب decode.serviceUuid غير فارغ ومطابقة uuidKey تامة (لا «أي UUID»)
//   FIX-03  stripIntelliRocks على كل حمولة (Govee تلصق "INTELLI_ROCKS")
//   FIX-04  BITS: قراءة كل بايتات الشريحة + عرض حتى 32 بتة (كان بايتًا واحدًا و31 بتة)
//   FIX-05  HEX بعرض مفصول بمسافات · BOOL = yes/no · MAC يتطلب 6 بايتات
//   FIX-06  enumLabels بمفاتيح 0x/عشرية (normalizeEnumKey) وenumNotes بنفس التطبيع
//   FIX-07  resolvedLength: bits = ceil((bitOffset+bitWidth)/8) · mac = 6 · apply الفكّ المُخزَّن مؤقتًا
//

import Foundation

public struct DecodedFieldValue: Sendable, Equatable {
    public let fleetId: String
    public let fleetName: String
    public let id: String
    public let label: String
    public let display: String
    public let offset: Int
    public let length: Int
    public let number: Double?
    public let note: String
    public let live: Bool
    public let emphasis: Bool

    public init(fleetId: String, fleetName: String, id: String, label: String, display: String,
                offset: Int, length: Int, number: Double?, note: String, live: Bool, emphasis: Bool) {
        self.fleetId = fleetId; self.fleetName = fleetName; self.id = id; self.label = label
        self.display = display; self.offset = offset; self.length = length; self.number = number
        self.note = note; self.live = live; self.emphasis = emphasis
    }
}

public enum SignatureFieldDecoder {

    // MARK: الواجهة العامة

    public static func decodeSighting(_ device: Sighting, fleets: [Fleet]) -> [DecodedFieldValue] {
        guard !device.fleetIds.isEmpty else { return [] }
        var out: [DecodedFieldValue] = []
        for id in device.fleetIds {
            guard let fleet = fleets.first(where: { $0.id == id }), let decode = fleet.decode,
                  !decode.fields.isEmpty else { continue }
            out += decodeFleet(fleet, decode, device)
        }
        return out
    }

    /// وسوم الحقول المعلَّمة حيًّا. بدون تكرار وبنفس ترتيب الأولوية.
    public static func liveChips(_ device: Sighting, fleets: [Fleet]) -> [LiveDecodeChip] {
        guard !device.fleetIds.isEmpty else { return [] }
        var seen = Set<String>()
        var out: [LiveDecodeChip] = []
        for row in decodeSighting(device, fleets: fleets) {
            guard row.live else { continue }
            let text = row.display.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty || !seen.insert(text.lowercased()).inserted { continue }
            out.append(LiveDecodeChip(text: text, emphasis: row.emphasis,
                                      note: row.note.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        return out
    }

    public static func payloadHex(_ decode: FleetDecode, device: Sighting) -> String? {
        payloads(decode, device).first?.1
    }

    public static func decodeFleet(_ fleet: Fleet, _ decode: FleetDecode, _ device: Sighting) -> [DecodedFieldValue] {
        var out: [DecodedFieldValue] = []
        var seen = Set<String>()
        for (bytes, hex) in payloads(decode, device) {
            let parsed = cachedParse(fleetId: fleet.id, decode: decode, hex: hex, bytes: bytes)
            for row in parsed where seen.insert(row.id).inserted { out.append(row) }
        }
        return out
    }

    // MARK: الحمولات

    private static func payloads(_ decode: FleetDecode, _ device: Sighting) -> [([UInt8], String)] {
        var hexes: [String] = []
        switch decode.source {
        case .manufacturerData:
            // FIX-01: مقتصر على BLE — نفس شرط Kotlin.
            guard device.kind == .ble else { return [] }
            let records = device.facts.mfgRecords.isEmpty
                ? (device.manufacturerId.map { [MfgRecord(companyId: $0, dataHex: device.manufacturerDataHex)] } ?? [])
                : device.facts.mfgRecords
            let want = (decode.companyId == 0) ? nil : decode.companyId
            let chosen = want == nil ? records : records.filter { $0.companyId == want }
            hexes = chosen.map { rec in
                decode.includeCompanyId ? companyIdPrefix(rec.companyId) + rec.dataHex : rec.dataHex
            }
        case .serviceData:
            // FIX-02: serviceUuid إلزامي، والمقارنة بـ uuidKey تامة.
            guard let raw = decode.serviceUuid, !raw.isEmpty else { return [] }
            let want = uuidKey(raw)
            var ads = device.facts.serviceData.filter { uuidKey($0.uuid) == want }.map { $0.dataHex }
            if want == "FFFA" { ads += OpenDroneId.wifiFffaPayloads(device.facts) }
            hexes = ads
        case .unsupported:
            hexes = []
        }

        var out: [([UInt8], String)] = []
        for hex in hexes {
            guard let raw = hexToBytes(hex) else { continue }
            let bytes = stripIntelliRocks(raw)                       // FIX-03
            if bytes.isEmpty { continue }
            out.append((bytes, bytes.map { String(format: "%02X", $0) }.joined()))
        }
        return out
    }

    /// Kotlin: companyIdPrefix — ترتيب Kotlin الأصلي: البايت الأدنى أولًا.
    private static func companyIdPrefix(_ companyId: Int) -> String {
        String(format: "%02X%02X", companyId & 0xFF, (companyId >> 8) & 0xFF)
    }

    private static func hexToBytes(_ hex: String) -> [UInt8]? {
        let h = hex.filter { $0.isLetter || $0.isNumber }
        if h.isEmpty || h.count % 2 != 0 { return nil }
        let chars = Array(h.uppercased())
        var out: [UInt8] = []
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let b = UInt8(String(chars[i...i + 1]), radix: 16) else { return nil }
            out.append(b)
            i += 2
        }
        return out
    }

    /// Govee تلصق "INTELLI_ROCKS" بنهاية الحمولة أحيانًا. إزالتها تُبقي بوّابات الطول تعمل.
    private static let intelliRocks: [UInt8] = Array("INTELLI_ROCKS".utf8)
    private static func stripIntelliRocks(_ bytes: [UInt8]) -> [UInt8] {
        guard bytes.count > intelliRocks.count else { return bytes }
        let idx = indexOfSlice(bytes, intelliRocks)
        guard idx >= 0 else { return bytes }
        return idx == 0 ? [] : Array(bytes[0..<idx])
    }

    private static func indexOfSlice(_ hay: [UInt8], _ needle: [UInt8]) -> Int {
        let last = hay.count - needle.count
        if last < 0 { return -1 }
        outer: for i in 0...last {
            for j in needle.indices where hay[i + j] != needle[j] { continue outer }
            return i
        }
        return -1
    }

    // MARK: كاش الفكّ (Kotlin: cacheKey + cache)

    private static let cacheLock = NSLock()
    private static var cache: [String: [DecodedFieldValue]] = [:]

    private static func cachedParse(fleetId: String, decode: FleetDecode, hex: String, bytes: [UInt8]) -> [DecodedFieldValue] {
        let fp = decode.fields.map {
            "\($0.id):\($0.offset):\($0.type.rawValue):\($0.resolvedLength()):\($0.live):\($0.liveEmphasis):\($0.enumNotes ?? [:])"
        }.joined(separator: ",")
        let key = "\(fleetId)|\(decode.source.rawValue)|\(hex)|\(fp)"
        cacheLock.lock()
        if let hit = cache[key] { cacheLock.unlock(); return hit }
        cacheLock.unlock()

        var out: [DecodedFieldValue] = []
        for field in decode.fields {
            guard gateOk(field.when, bytes) else { continue }
            let len = field.resolvedLength()
            guard field.offset >= 0, len >= 1, field.offset + len <= bytes.count else { continue }
            guard let parsed = formatField(field, bytes) else { continue }
            out.append(DecodedFieldValue(
                fleetId: fleetId, fleetName: fleetId, id: field.id, label: field.label,
                display: parsed.display, offset: field.offset, length: len,
                number: parsed.number, note: enumNoteFor(field, parsed.rawKey),
                live: field.live, emphasis: isEmphasized(field, parsed.rawKey)))
        }
        cacheLock.lock(); cache[key] = out; cacheLock.unlock()
        return out
    }

    // MARK: البوّابات

    private static func gateOk(_ gate: DecodeWhen?, _ payload: [UInt8]) -> Bool {
        guard let gate else { return true }
        return gateOkOnce(gate, payload) && gateOk(gate.and, payload)
    }

    private static func gateOkOnce(_ gate: DecodeWhen, _ payload: [UInt8]) -> Bool {
        if gate.op == .len { return payload.count == max(1, gate.length) }
        guard let want = hexToBytes(gate.valueHex) else { return false }
        let len = max(1, want.count)
        guard gate.offset >= 0, gate.offset + len <= payload.count else { return false }
        let got = Array(payload[gate.offset..<gate.offset + len])
        switch gate.op {
        case .eq: return got == want
        case .neq: return got != want
        case .mask: return zip(got, want).allSatisfy { ($0.0 & $0.1) == $0.1 }
        case .nmask: return zip(got, want).allSatisfy { ($0.0 & $0.1) == 0 }
        case .len: return payload.count == max(1, gate.length)
        }
    }

    // MARK: الفكّ

    private struct ParsedField { let display: String; let number: Double?; let rawKey: String }

    private static func formatField(_ field: DecodeField, _ payload: [UInt8]) -> ParsedField? {
        let len = field.resolvedLength()
        let slice = Array(payload[field.offset..<field.offset + len])
        let le = field.endian != .be
        let unit = (field.unit ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        var rawNum: Double? = nil
        var rawKey = ""
        var text: String

        switch field.type {
        case .utf8:
            let s = String(decoding: slice, as: UTF8.self).trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\u{0000}", with: "")
            rawKey = s
            if s.isEmpty { return nil }
            text = s
        case .hex:
            let h = slice.map { String(format: "%02X", $0) }.joined()
            rawKey = h
            text = stride(from: 0, to: h.count, by: 2).map { i -> String in
                let a = h.index(h.startIndex, offsetBy: i)
                let b = h.index(a, offsetBy: 2)
                return String(h[a..<b])
            }.joined(separator: " ")
        case .mac:
            if slice.count < 6 { return nil }
            let mac = slice.prefix(6).map { String(format: "%02X", $0) }.joined(separator: ":")
            rawKey = mac
            text = mac
        case .bool:
            let on = slice.contains { $0 != 0 }
            rawNum = on ? 1.0 : 0.0
            rawKey = on ? "1" : "0"
            text = on ? "yes" : "no"
        case .bits:
            // FIX-04: عرض يصل 32 بتة على كل بايتات الشريحة.
            let width = min(max(field.bitWidth ?? 1, 1), 32)
            let bitStart = field.bitOffset ?? 0
            let word = readU(slice, 0, slice.count, le)
            let value = (word >> UInt64(bitStart)) & ((1 << UInt64(width)) - 1)
            rawNum = Double(value)
            rawKey = String(value)
            text = String(value)
        case .f32:
            if slice.count < 4 { return nil }
            let bits = UInt32(truncatingIfNeeded: readU(slice, 0, 4, le))
            let f = Double(Float(bitPattern: bits))
            rawNum = f
            rawKey = String(f)
            text = formatNumber(f)
        case .u8, .u16, .u24, .u32:
            let v = readU(slice, 0, slice.count, le)
            rawNum = Double(v)
            rawKey = String(v)
            text = String(v)
        case .i8, .i16, .i32:
            let bits = slice.count * 8
            let v = signExtend(readU(slice, 0, slice.count, le), bits: bits)
            rawNum = Double(v)
            rawKey = String(v)
            text = String(v)
        }

        let scaled: Double? = rawNum.map { raw in
            var n = raw
            if field.scale != nil || field.offsetAdd != nil || field.modulo != nil {
                if let m = field.modulo, m != 0 { n = n.truncatingRemainder(dividingBy: m) }
                if let s = field.scale { n *= s }
                if let a = field.offsetAdd { n += a }
            }
            return n
        }
        let shown: String = (rawNum != nil && (field.scale != nil || field.offsetAdd != nil || field.modulo != nil))
            ? formatNumber(scaled!) : text

        // FIX-06: مفاتيح enum قد تكون "0x1F" أو "31" — نطبّعها أولًا.
        let mapped = enumLabel(field.enumLabels, rawKey: rawKey, numeric: rawNum)
        let display = mapped ?? shown
        let final = unit.isEmpty ? display : "\(display) \(unit)"
        guard !final.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return ParsedField(display: final,
                           number: (scaled?.isFinite ?? false) ? scaled : nil,
                           rawKey: rawKey)
    }

    private static func enumLabel(_ labels: [String: String]?, rawKey: String, numeric: Double?) -> String? {
        guard let labels, !labels.isEmpty else { return nil }
        if let l = labels[rawKey] { return l }
        if let l = labels["0x" + rawKey.uppercased()] { return l }
        if let n = numeric?.rounded(.towardZero) {
            let asLong = Int64(n)
            if let l = labels[String(asLong)] { return l }
            if let l = labels[String(format: "0x%X", asLong)] { return l }
        }
        let norm = normalizeEnumKey(rawKey)
        if let l = labels[norm] { return l }
        return labels.first { normalizeEnumKey($0.key) == norm }?.value
    }

    private static func enumNoteFor(_ field: DecodeField, _ rawKey: String) -> String {
        guard let notes = field.enumNotes, !notes.isEmpty, !rawKey.isEmpty else { return "" }
        if let n = notes[rawKey] { return n.trimmingCharacters(in: .whitespacesAndNewlines) }
        let key = normalizeEnumKey(rawKey)
        if let n = notes[key] { return n.trimmingCharacters(in: .whitespacesAndNewlines) }
        return notes.first { normalizeEnumKey($0.key) == key }?.value.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func isEmphasized(_ field: DecodeField, _ rawKey: String) -> Bool {
        if field.liveEmphasis.isEmpty || rawKey.isEmpty { return false }
        let want = Set(field.liveEmphasis.map(normalizeEnumKey))
        return want.contains(normalizeEnumKey(rawKey)) || field.liveEmphasis.contains(rawKey)
    }

    // MARK: قراءة الأعداد

    private static func readU(_ bytes: [UInt8], _ offset: Int, _ len: Int, _ le: Bool) -> UInt64 {
        var v: UInt64 = 0
        if le {
            for i in 0..<len { v |= UInt64(bytes[offset + i]) << UInt64(8 * i) }
        } else {
            for i in 0..<len { v = (v << 8) | UInt64(bytes[offset + i]) }
        }
        return v
    }

    private static func signExtend(_ v: UInt64, bits: Int) -> Int64 {
        let shift = 64 - bits
        return Int64(bitPattern: v << UInt64(shift)) >> UInt64(shift)
    }

    private static func formatNumber(_ n: Double) -> String {
        if !n.isFinite { return String(n) }
        if n == Double(Int64(n)) { return String(Int64(n)) }
        var s = String(format: "%.6f", n)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

/// Kotlin: fun normalizeEnumKey(raw) — 0x05 و05 و5 كلها تصير "5".
public func normalizeEnumKey(_ raw: String) -> String {
    let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return t }
    if t.lowercased().hasPrefix("0x") {
        let body = String(t.dropFirst(2))
        if let v = Int64(body, radix: 16) { return String(v) }
        return t
    }
    if let v = Int64(t) { return String(v) }
    let hex = t.filter { $0.isLetter || $0.isNumber }
    if hex.contains(where: { "abcdefABCDEF".contains($0) }) {
        if let v = Int64(hex, radix: 16) { return String(v) }
    }
    return t
}

/// Kotlin: fun Sighting.withLiveDecode(fleets) — نفس النسخة إن لم يتغيّر شيء.
public extension Sighting {
    func withLiveDecode(_ fleets: [Fleet]) -> Sighting {
        let chips = SignatureFieldDecoder.liveChips(self, fleets: fleets)
        if chips == liveDecode { return self }
        var copy = self
        copy.liveDecode = chips
        return copy
    }
}

/// Kotlin: private fun uuidKey(uuid) — 4 خانات تبقى كما هي، و128-بتة القاعدية تُختصر إلى 4.
private func uuidKey(_ uuid: String) -> String {
    let hex = uuid.filter { $0.isLetter || $0.isNumber }.uppercased()
    if hex.count == 4 { return hex }
    if hex.count == 32, hex.hasPrefix("0000"), hex.hasSuffix("00001000800000805F9B34FB") {
        let a = hex.index(hex.startIndex, offsetBy: 4)
        let b = hex.index(a, offsetBy: 4)
        return String(hex[a..<b])
    }
    return hex
}
