//
//  SignatureCandidates.swift
//  FieldwatchCore
//
//  نقل من SignatureCandidates.kt (692 سطرًا) — البنية العامة من نسخة الطرف الآخر،
//  لكن الدوال الحاكمة أُعيدت كتابتها نقلًا حرفيًا من Kotlin لأن نسختهم كانت مختلفة جوهريًا:
//   • nameGlobOf      : Kotlin يرفض الاسم الشبيه بالمنازل أولًا، ويشترط قوسًا مُرسىً (matchEntire)،
//                       وبادئة غير مُتجاهَلة، ولاحقة ست عشرية بطول ≥ 6 — نسختهم كانت أقرب إلى التسامح.
//   • isHouseLikeName : Kotlin يعمل على **الرمز الأول** (HOUSE_WORDS بعد فصل بالمسافات/-/_) مع
//                       قاعدة guest «المنتَج» — نسختهم كانت تبحث عن الكلمة داخل الاسم كله.
//   • isOverbroadCreateName + isSkippedPrefix: كانتا ناقصتين تمامًا.
//  كل ما تغيّر معلَّم بـ FIX-C في التعليقات.
//

import Foundation

public struct SignatureCandidate: Sendable, Equatable {
    public let id: String
    public let proposedName: String
    public let kind: SignatureClass
    public let radioKind: RadioKind
    public let distinctRadios: Int
    public let rules: [MatchRule]
    public let why: String
    public let examples: [String]
    public let extraCount: Int
    public let notes: String
    public let colorIndex: Int

    public var ruleLabel: String { rules.map(ruleShortLabel).joined(separator: "  ·  ") }

    public init(id: String, proposedName: String, kind: SignatureClass, radioKind: RadioKind,
                distinctRadios: Int, rules: [MatchRule], why: String, examples: [String],
                extraCount: Int, notes: String, colorIndex: Int) {
        self.id = id; self.proposedName = proposedName; self.kind = kind; self.radioKind = radioKind
        self.distinctRadios = distinctRadios; self.rules = rules; self.why = why; self.examples = examples
        self.extraCount = extraCount; self.notes = notes; self.colorIndex = colorIndex
    }
}

public struct CandidateReport: Sendable, Equatable {
    public let families: [SignatureCandidate]
    public let uniqueRadios: Int
    public let unmatchedRadios: Int
    public let skippedRandomized: Int
    public let skippedHouseLike: Int
    public let skippedOther: Int
    public let sourceLabel: String
}

public enum FamilyVerdict: String, Sendable {
    case strong = "STRONG", possible = "POSSIBLE", single = "SINGLE", tagged = "TAGGED"
}

public struct SignatureFamilyHint: Sendable, Equatable {
    public let verdict: FamilyVerdict
    public let title: String
    public let body: String
    public let logCount: Int
    public let liveCount: Int
    public let displayCount: Int
    public let ruleLabel: String?
    public let radioKind: RadioKind
}

public enum SignatureCandidates {

    public static let maxFamilies = 20
    public static let minRadios = 2
    public static let strongMinRadios = 8

    // MARK: - التحليل

    public static func analyze(
        _ radios: [LogRadio],
        fleets: [Fleet],
        engine: SignatureEngine = SignatureEngine(),
        sourceLabel: String = "Rotating log"
    ) -> CandidateReport {
        let sightings = radios.map { $0.toSighting() }
        let hits = sightings.isEmpty ? [:] : engine.match(sightings, fleets: fleets)
        let unmatched = radios.filter { (hits[$0.key] ?? []).isEmpty }

        var skippedRandomized = 0
        var skippedHouseLike = 0
        var skippedOther = 0

        // ترتيب الفحص كما في Kotlin: المعرف المُهيكل أولًا (يُدخل الراديو في «usable»
        // حتى لو كان عنوانه عشوائيًا)، ثم العشوائي، ثم الشبيه بالمنازل.
        var usable: [LogRadio] = []
        for radio in unmatched {
            if radio.hasStructuredId { usable.append(radio); continue }
            if radio.randomized { skippedRandomized += 1; continue }
            if isHouseLikeName(radio.name) { skippedHouseLike += 1; continue }
            skippedOther += 1
        }

        // PORT-TODO(iOS): Kotlin يبني «عائلات» من **بصمات متعددة** لكل راديو
        // (glob الاسم، vendor IE، UUID، معرّف الشركة) عبر buildClusters + mergeOverlapping
        // مع إسقاط idViable. هذه النسخة تُجمّع على glob الاسم ثم vendor IE فقط.
        var groups: [String: [LogRadio]] = [:]
        for radio in usable {
            if let glob = nameGlobOf(radio.name) {
                groups["glob:\(radio.kind.rawValue):\(glob)", default: []].append(radio)
            } else if let ie = radio.vendorIeOuis
                .map({ MacUtil.normalize($0) })
                .first(where: { isUsableVendorIe($0) }) {
                groups["ie:\(ie)", default: []].append(radio)
            } else {
                skippedOther += 1
            }
        }

        let viable = groups.filter { $0.value.count >= minRadios }
        let clusteredKeys = Set(viable.flatMap { $0.value.map { $0.key } })
        // Swift < 6 لا يملك count(where:) — نستخدم filter().count لتعمل على كل الإصدارات.
        skippedOther += usable.filter { !clusteredKeys.contains($0.key) }.count   // نفس محاسبة Kotlin

        let families: [SignatureCandidate] = viable
            .sorted { a, b in
                if a.value.count != b.value.count { return a.value.count > b.value.count }
                if kindRank(a.value[0].kind) != kindRank(b.value[0].kind) { return kindRank(a.value[0].kind) < kindRank(b.value[0].kind) }
                return a.key < b.key
            }
            .prefix(maxFamilies)
            .map { key, rs -> SignatureCandidate in
                let first = rs[0]
                let rule: MatchRule
                let name: String
                if key.hasPrefix("glob:") {
                    let glob = nameGlobOf(first.name) ?? ""
                    rule = MatchRule(kind: .nameGlob, text: glob, radio: first.kind)
                    name = glob
                } else {
                    let ie = MacUtil.normalize(first.vendorIeOuis.first ?? "")
                    rule = MatchRule(kind: .vendorIeOUI, text: ie, radio: .wifi)
                    name = ie
                }
                let clean = name.replacingOccurrences(of: "?", with: "")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "*-_ "))
                return SignatureCandidate(
                    id: key,
                    proposedName: String(clean.prefix(22)),
                    kind: first.kind == .wifi ? .home : .other,
                    radioKind: first.kind,
                    distinctRadios: rs.count,
                    rules: [rule],
                    why: "Shared stable on-air identifier across multiple radios; not a house-only name.",
                    examples: Array(rs.prefix(2).map { $0.name.isEmpty ? $0.mac : $0.name }),
                    extraCount: max(0, rs.count - 2),
                    notes: "\(rs.count) radios matched \(ruleShortLabel(rule)).",
                    colorIndex: first.kind == .ble ? 3 : 0)
            }

        return CandidateReport(
            families: families,
            uniqueRadios: radios.count,
            unmatchedRadios: unmatched.count,
            skippedRandomized: skippedRandomized,
            skippedHouseLike: skippedHouseLike,
            skippedOther: skippedOther,
            sourceLabel: sourceLabel)
    }

    public static func suggestFleet(_ candidate: SignatureCandidate) -> Fleet {
        Fleet(id: UUID().uuidString, name: candidate.proposedName, enabled: true, matchAny: true,
              colorIndex: candidate.colorIndex, rules: candidate.rules, notes: candidate.notes,
              builtIn: false, kind: candidate.kind)
    }

    /// Kotlin: الذي كان يُنشئ DIRECT* / ANDROID* — بادئات تُطابق كل نقطة Direct.
    public static func isOverbroadCreateName(_ text: String) -> Bool {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        while t.hasSuffix("*") || t.hasSuffix("-") || t.hasSuffix("_") { t.removeLast() }
        return !t.isEmpty && skipPrefix.contains(t)
    }

    // MARK: - التلميح (assessFamily)

    public static func assessFamily(_ device: Sighting, live: [Sighting], log: [LogRadio], fleets: [Fleet]) -> SignatureFamilyHint {
        if !device.fleetIds.isEmpty {
            return SignatureFamilyHint(
                verdict: .tagged, title: "Already tagged",
                body: "Matched a catalog signature. A second signature can still dual-label this radio.",
                logCount: 0, liveCount: 0, displayCount: 0, ruleLabel: nil, radioKind: device.kind)
        }
        // PORT-TODO(iOS): Kotlin يجرّب **بصمات متعددة** (glob، vendor IE، UUID، company)
        // ويسجّل أعلى تطابق عبر idViable؛ هذه النسخة تقتصر على glob الاسم.
        guard let key = nameGlobOf(device.name) else {
            return SignatureFamilyHint(
                verdict: .single, title: "This radio only",
                body: "No unique on-air ID to cluster on. Randomized addresses, house-like names, and generic chips are skipped.",
                logCount: 0, liveCount: 0, displayCount: 0, ruleLabel: nil, radioKind: device.kind)
        }
        let logKeys = Set(log.filter { nameGlobOf($0.name) == key }.map { $0.key })
        let liveKeys = Set(live.filter { nameGlobOf($0.name) == key }.map { $0.key })
        let n = max(logKeys.count, liveKeys.count)
        guard n >= minRadios else {
            return SignatureFamilyHint(
                verdict: .single, title: "This radio only",
                body: "No other MAC shares this name family; a signature would mostly tag this address.",
                logCount: logKeys.count, liveCount: liveKeys.count, displayCount: 0,
                ruleLabel: key, radioKind: device.kind)
        }
        let strong = n >= strongMinRadios
        let clause: String
        if logKeys.count > 0 && liveKeys.count > 0 { clause = "\(logKeys.count) in the log (\(liveKeys.count) on the air now)" }
        else if logKeys.count > 0 { clause = "\(logKeys.count) in the log" }
        else { clause = "\(liveKeys.count) on the air now" }
        return SignatureFamilyHint(
            verdict: strong ? .strong : .possible,
            title: strong ? "Strong family" : "Possible family",
            body: "Same name glob on \(clause). That is a catalog pattern, not this MAC.",
            logCount: logKeys.count, liveCount: liveKeys.count,
            displayCount: logKeys.count > 0 ? logKeys.count : liveKeys.count,
            ruleLabel: key, radioKind: device.kind)
    }

    // MARK: - الدوال الحاكمة (نقل حرفي من Kotlin)

    /// Kotlin: internal fun nameGlobOf(name): String?
    public static func nameGlobOf(_ name: String) -> String? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.hasPrefix("<") || isHouseLikeName(n) { return nil }   // FIX-C1

        if let token = bracketToken(n) {                                        // FIX-C2: قوس مُرسى
            if token.count >= 3 && !isSkippedPrefix(token) { return "[\(token)]*" }
        }

        guard let sepIdx = n.firstIndex(where: { $0 == "-" || $0 == "_" }) else { return nil }
        let sepAt = n.distance(from: n.startIndex, to: sepIdx)
        if sepAt < 3 { return nil }
        let prefix = String(n[n.startIndex..<sepIdx])
        if isSkippedPrefix(prefix) || isHouseLikeName(prefix) { return nil }
        if prefix.count < 3 { return nil }

        let sep = n[sepIdx]
        let after = n[n.index(after: sepIdx)...]
        let suffix = String(after.prefix { $0 != " " })
        let hex = suffix.filter { $0.isLetter || $0.isNumber }
        let isHexOnly = !hex.isEmpty && hex.count == suffix.count && hex.allSatisfy { $0.isNumber || "abcdefABCDEF".contains($0) }
        if isHexOnly && hex.count >= 6 {
            return "\(prefix)\(sep)\(String(repeating: "?", count: hex.count))"
        }
        return "\(prefix)*"
    }

    /// Kotlin: Regex("""\[([A-Za-z][A-Za-z0-9 ]{2,20})\].*""") مع matchEntire على الاسم.
    private static func bracketToken(_ n: String) -> String? {
        guard n.hasPrefix("[") else { return nil }
        guard let close = n.firstIndex(of: "]") else { return nil }
        let inner = String(n[n.index(after: n.startIndex)..<close])
        // groupValues[1] = [A-Za-z][A-Za-z0-9 ]{2,20}
        guard inner.count >= 3, inner.count <= 21 else { return nil }
        let chars = Array(inner)
        guard let first = chars.first, first.isLetter, first.isASCII else { return nil }
        guard chars.allSatisfy({ ($0.isLetter && $0.isASCII) || $0.isNumber || $0 == " " }) else { return nil }
        return inner
    }

    /// Kotlin: internal fun isHouseLikeName(name) — يعتمد على الرمز الأول وقاعدة guest «المنتَج».
    public static func isHouseLikeName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return true }
        let tokens = n.lowercased()
            .components(separatedBy: CharacterSet(charactersIn: " \t-_"))
            .filter { !$0.isEmpty }
        if tokens.isEmpty { return true }
        let first = tokens[0]
        if houseWords.contains(where: { first == $0 || first.hasPrefix($0) }) { return true }   // FIX-C3
        if tokens.contains(where: { $0 == "guest" || $0.hasPrefix("guest") }) {
            let product = first.contains { $0.isNumber } || (first == first.uppercased() && first.count >= 4)
            if !product { return true }
        }
        let token = String(n.prefix { $0 != " " })
        let noSep = !token.contains("-") && !token.contains("_")
        let allLetters = token.allSatisfy { $0.isLetter }
        let titleOrLower = token != token.uppercased()
        return noSep && allLetters && titleOrLower && token.count >= 3 && token.count <= 18
            && !token.contains { $0.isNumber }
    }

    static let skipPrefix: Set<String> = [
        "DIRECT", "GUEST", "HOME", "WIFI", "WIRELESS", "SETUP", "NETGEAR", "LINKSYS",
        "DLINK", "TP-LINK", "TPLINK", "ATT", "XFINITY", "HILTON", "TOAST", "IPHONE",
        "IPAD", "ANDROID", "MYWIFI", "DEFAULT", "TY",
    ]

    static let houseWords: [String] = [
        "guest", "xfinity", "xfinitywifi", "hilton", "toast", "attwifi",
        "androidap", "iphone", "ipad", "myspectrum",
    ]

    static let chipVendor: [String] = [
        "espressif", "mediatek", "ampak", "qualcomm", "universal global scientific", "realtek",
    ]

    static let protocolIe: Set<String> = ["0050F2", "000FAC", "506F9A", "8CFDF0"]

    public static func isSkippedPrefix(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return skipPrefix.contains(t) || t.count < 3
    }

    public static func isChipModuleVendor(_ vendor: String?) -> Bool {
        guard let v = vendor?.lowercased() else { return false }
        return chipVendor.contains { v.contains($0) }
    }

    public static func isProtocolIe(_ oui: String) -> Bool {
        let hex = oui.filter { $0.isLetter || $0.isNumber }.uppercased()
        return protocolIe.contains(String(hex.prefix(6)))
    }

    private static func isUsableVendorIe(_ normalized: String) -> Bool {
        let h = normalized.replacingOccurrences(of: ":", with: "")
        return h.count >= 6 && !isProtocolIe(h)
    }

    private static func kindRank(_ kind: RadioKind) -> Int { kind == .wifi ? 0 : 1 }
}

/// Kotlin: ruleShortLabel — نص مختصر لقاعدة داخل البطاقة.
func ruleShortLabel(_ r: MatchRule) -> String {
    switch r.kind {
    case .nameGlob, .nameContains: return r.text
    case .vendorIeOUI: return "vendor IE \(r.text)"
    case .oui, .macPrefix: return "OUI \(r.text)"
    case .serviceUUID: return "UUID \(r.text)"
    case .serviceData: return r.text.isEmpty ? "svc contains \(r.dataPrefixHex)" : "UUID \(r.text) \(r.dataPrefixHex)"
    case .manufacturerData: return String(format: "mfg 0x%04X %@", r.companyId, r.dataPrefixHex)
    case .manufacturerID: return String(format: "mfg 0x%04X", r.companyId)
    default: return r.kind.rawValue
    }
}
