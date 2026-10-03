//
//  SignatureEngine.swift
//  FieldwatchCore
//
//  نقل كامل لـ SignatureEngine.kt (647 سطرًا) — قلب Fieldwatch:
//  يطابق كل راديو مع كتالوج التواقيع بنفس منطق أندرويد (فهرسة OUI،
//  القواعد السريعة، قواعد الإسقاط drop*، والتجميع العنقودي clusters).
//
//  PORT-TODO(iOS): suggestFleet(device) — تبني توقيعًا من جهاز (تحتاج
//  SignatureCandidates.nameGlobOf وقوائم SKIP_PREFIX). تُنقل الخطوة E مع
//  SignatureCandidates.swift. ليست لازمة للتعرّف على الأجهزة.
//

import Foundation

public final class SignatureEngine {

    public init() {}

    /// 802.11 WPA (Microsoft) و RSN (IEEE) — ليست علامة منتج.
    static let WIFI_PROTOCOL_IE_OUIS: Set<String> = ["0050F2", "000FAC"]

    // MARK: - Cache (بديل @Volatile cachedFleets/cached)

    private final class Cache: @unchecked Sendable {
        private var key: Int = 0
        private var fleetsCount: Int = -1
        private var compiled: Compiled?
        private let lock = NSLock()

        func get(_ key: Int, _ count: Int) -> Compiled? {
            lock.lock(); defer { lock.unlock() }
            guard let c = compiled, self.key == key, self.fleetsCount == count else { return nil }
            return c
        }

        func put(_ key: Int, _ count: Int, _ c: Compiled) {
            lock.lock(); defer { lock.unlock() }
            self.key = key; self.fleetsCount = count; self.compiled = c
        }
    }

    private let cache = Cache()

    // MARK: - المطابقة الرئيسية

    public func match(
        _ devices: any Collection<Sighting>,
        fleets: [Fleet],
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        policy: DetectionPolicy = DetectionPolicy()
    ) -> [String: Set<String>] {
        let devices = Array(devices)
        let compiled = compiled(fleets)

        var byKey = [String: Set<String>]()
        for device in devices {
            var hits = OrderedHits()
            let ouiHit = compiled.ouiHits(device)
            for idx in compiled.plansFor(device.kind) {
                let plan = compiled.plans[idx]
                if !plan.cluster && fleetHits(device, plan, ouiHit[idx]) {
                    hits.add(plan.id)
                }
            }
            dropProtocolIBeacon(&hits, compiled)
            dropDjiWhenOsmoCamera(&hits)
            dropAirTagsWhenAppleDevice(&hits, device)
            dropCiscoWhenMeraki(&hits)
            byKey[device.key] = hits.set
        }
        applyClusters(devices, compiled, &byKey, now)
        return byKey
    }

    // MARK: - Compile

    private func compiled(_ fleets: [Fleet]) -> Compiled {
        let key = Self.catalogKey(fleets)
        if let hit = cache.get(key, fleets.count) { return hit }
        let next = compile(fleets)
        cache.put(key, fleets.count, next)
        return next
    }

    /// بديل `cachedFleets === fleets` في Kotlin (المصفوفات قيمة في Swift لا مرجع)،
    /// فنبني مفتاحًا من المعرّفات + العدد. أي تغيّر في الكتالوج يغيّر المفتاح.
    private static func catalogKey(_ fleets: [Fleet]) -> Int {
        var h = 5381
        for f in fleets {
            h = (h &* 33) &+ f.id.hashValue
            for r in f.rules {
                h = (h &* 31) &+ r.kind.rawValue.hashValue &+ r.text.hashValue
            }
        }
        return h ^ fleets.count
    }

    private func compile(_ fleets: [Fleet]) -> Compiled {
        var plans = [FleetPlan]()
        plans.reserveCapacity(fleets.count)
        var bssidWifi = [String: [Int]]()
        var bssidBle = [String: [Int]]()
        var vendorIe = [String: [Int]]()
        var longOui = [LongOui]()
        var wifiPlans = [Int]()
        var blePlans = [Int]()

        for (idx, fleet) in fleets.enumerated() {
            let active = fleet.rules.filter { $0.enabled }
            var other = [FastRule]()
            for rule in active {
                switch rule.kind {
                case .oui:
                    indexOui(rule.text, rule.radio, idx, bssid: true, vendor: true,
                             &bssidWifi, &bssidBle, &vendorIe, &longOui)
                case .macPrefix:
                    indexOui(rule.text, rule.radio, idx, bssid: true, vendor: false,
                             &bssidWifi, &bssidBle, &vendorIe, &longOui)
                case .vendorIeOUI:
                    indexOui(rule.text, rule.radio, idx, bssid: false, vendor: true,
                             &bssidWifi, &bssidBle, &vendorIe, &longOui)
                default:
                    if let fast = compileOther(rule) { other.append(fast) }
                }
            }
            plans.append(FleetPlan(id: fleet.id, fleet: fleet, cluster: needsCluster(fleet),
                                   matchAny: fleet.matchAny, otherRules: other, rawRules: active))
            switch radioScope(active) {
            case .wifi: wifiPlans.append(idx)
            case .ble: blePlans.append(idx)
            case nil:
                wifiPlans.append(idx)
                blePlans.append(idx)
            }
        }

        return Compiled(
            plans: plans,
            wifiPlans: wifiPlans,
            blePlans: blePlans,
            bssidWifi: freeze(bssidWifi),
            bssidBle: freeze(bssidBle),
            vendorIe: freeze(vendorIe),
            longOui: longOui
        )
    }

    private func needsCluster(_ fleet: Fleet) -> Bool {
        fleet.minPeers > 0 || fleet.clusterByOui || fleet.sequentialMac
    }

    private func indexOui(
        _ text: String, _ radio: RadioKind?, _ fleetIdx: Int,
        bssid: Bool, vendor: Bool,
        _ bssidWifi: inout [String: [Int]],
        _ bssidBle: inout [String: [Int]],
        _ vendorIe: inout [String: [Int]],
        _ longOui: inout [LongOui]
    ) {
        let hex = hexOnly(text)
        if hex.isEmpty { return }
        if hex.count != 6 {
            longOui.append(LongOui(hex: hex, radio: radio, bssid: bssid, vendor: vendor, fleetIdx: fleetIdx))
            return
        }
        if bssid {
            if radio != .ble { addIdx(&bssidWifi, hex, fleetIdx) }
            if radio != .wifi { addIdx(&bssidBle, hex, fleetIdx) }
        }
        if vendor && radio != .ble && !Self.WIFI_PROTOCOL_IE_OUIS.contains(hex) {
            addIdx(&vendorIe, hex, fleetIdx)
        }
    }

    private func addIdx(_ map: inout [String: [Int]], _ key: String, _ idx: Int) {
        var list = map[key] ?? []
        if !list.contains(idx) { list.append(idx) }
        map[key] = list
    }

    private func freeze(_ map: [String: [Int]]) -> [String: [Int]] { map }

    /// WIFI = كل القواعد لـ Wi-Fi فقط · BLE = كلها BLE · nil = مختلط أو غير محدد ⇒ يُبحث في الاثنين.
    private func radioScope(_ rules: [MatchRule]) -> RadioKind? {
        var wifi = false
        var ble = false
        var both = false
        for rule in rules {
            switch ruleScope(rule) {
            case .wifi: wifi = true
            case .ble: ble = true
            case nil: both = true
            }
        }
        if both || (wifi && ble) { return nil }
        if wifi { return .wifi }
        if ble { return .ble }
        return nil
    }

    private func ruleScope(_ rule: MatchRule) -> RadioKind? {
        switch rule.kind {
        case .vendorIeOUI, .hiddenSSID: return .wifi
        case .radioKind: return rule.radio
        case .serviceUUID, .serviceData, .manufacturerID, .manufacturerData:
            return rule.radio ?? .ble
        default: return rule.radio
        }
    }

    private func compileOther(_ rule: MatchRule) -> FastRule? {
        switch rule.kind {
        case .nameContains:
            return rule.text.isBlankSwift ? nil : .contains(rule.text, rule.radio)
        case .nameGlob:
            guard !rule.text.isBlankSwift else { return nil }
            guard let re = Self.compileGlob(rule.text) else { return nil }
            return .glob(re, rule.radio)
        case .serviceUUID:
            return rule.text.isBlankSwift ? nil : .uuid(uuidAliases(rule.text), rule.radio)
        case .manufacturerID:
            return .mfgId(rule.companyId, rule.radio)
        case .manufacturerData:
            let prefix = hexOnly(rule.dataPrefixHex)
            return prefix.isEmpty ? nil : .mfgData(rule.companyId, prefix, rule.radio)
        case .serviceData:
            let prefix = hexOnly(rule.dataPrefixHex)
            let aliases = Set(uuidAliases(rule.text).filter { !$0.isBlankSwift })
            if prefix.isEmpty && aliases.isEmpty { return nil }
            return .svcData(aliases, prefix, rule.radio,
                            rule.text.isBlankSwift && !prefix.isEmpty)
        case .radioKind:
            return .radio(rule.radio)
        case .hiddenSSID:
            return .hidden
        case .oui, .macPrefix, .vendorIeOUI:
            return nil
        }
    }

    static func compileGlob(_ pattern: String) -> NSRegularExpression? {
        var body = "^"
        for ch in pattern {
            switch ch {
            case "*": body += ".*"
            case "?": body += "."
            default: body += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        body += "$"
        return try? NSRegularExpression(pattern: body, options: [.caseInsensitive])
    }

    // MARK: - قواعد الإسقاط

    private func fleetHits(_ device: Sighting, _ plan: FleetPlan, _ ouiHit: Bool) -> Bool {
        if plan.id == "fleet-ibeacon" && isTeslaPhoneKeyIBeacon(device) { return false }
        if plan.rawRules.isEmpty { return false }
        if !plan.matchAny {
            return plan.rawRules.allSatisfy { ruleHits(device, $0) }
        }
        if ouiHit { return true }
        if plan.otherRules.isEmpty { return false }
        return plan.otherRules.contains { $0.hits(device) }
    }

    /// iBeacon تخطيط حمولة لا منتج. إن طابق الراديو توقيعًا غير beacon فأسقط وسم iBeacon.
    private func dropProtocolIBeacon(_ hits: inout OrderedHits, _ compiled: Compiled) {
        guard hits.contains("fleet-ibeacon") else { return }
        let otherProduct = hits.list.contains { id in
            guard id != "fleet-ibeacon" else { return false }
            return compiled.plans.contains { $0.id == id && $0.fleet.kind != .beacon }
        }
        if otherProduct { hits.remove("fleet-ibeacon") }
    }

    /// كاميرات Osmo تشترك في شركة DJI 0x08AA — فضّل صف Osmo على DJI.
    private func dropDjiWhenOsmoCamera(_ hits: inout OrderedHits) {
        if hits.contains("fleet-osmo") { hits.remove("fleet-dji") }
    }

    /// نقاط Meraki مملوكة لـ Cisco وتُدرج vendor IE 00:00:0C — لا تُوسم Cisco أيضًا.
    private func dropCiscoWhenMeraki(_ hits: inout OrderedHits) {
        if hits.contains("fleet-meraki") { hits.remove("fleet-cisco") }
    }

    /// Offline Finding (0x12) بروتوكول شبكة Find My لا هوية AirTag.
    private func dropAirTagsWhenAppleDevice(_ hits: inout OrderedHits, _ device: Sighting) {
        guard hits.contains("fleet-airtag") else { return }
        if device.name.range(of: "AirTag", options: .caseInsensitive) != nil { return }
        if hasFindMyAccessoryUuid(device) { return }
        let appleProduct = hits.contains("fleet-apple-device") || hits.contains("fleet-apple-audio")
        if appleProduct || TrackerMatch.isAppleContinuity(device) {
            hits.remove("fleet-airtag")
        }
    }

    private func hasFindMyAccessoryUuid(_ device: Sighting) -> Bool {
        let want = uuidAliases("FD44")
        let have = device.serviceUuids + device.facts.serviceData.map { $0.uuid }
        return have.contains { uuid in !uuidAliases(uuid).isDisjoint(with: want) }
    }

    /// إعلانات مفتاح هاتف Tesla تستعمل iBeacon من آبل — الوسم Tesla لا iBeacon.
    private func isTeslaPhoneKeyIBeacon(_ device: Sighting) -> Bool {
        let prefix = DefaultCatalogConstants.teslaIBeaconMfgPrefix
        return Self.mfgRecords(device).contains { rec in
            rec.companyId == 0x004C && hexOnly(rec.dataHex).hasPrefix(prefix)
        }
    }

    // MARK: - ruleHits (المسار غير المفهرس)

    private func ruleHits(_ device: Sighting, _ rule: MatchRule) -> Bool {
        if rule.kind != .radioKind, let r = rule.radio, device.kind != r { return false }
        switch rule.kind {
        case .oui, .macPrefix:
            if MacUtil.matchesPrefix(device.mac, rule.text) { return true }
            if rule.kind == .oui && wifiVendorIeHitsOui(device, rule.text) { return true }
            if rule.kind == .oui && recoveredWifiOuiHits(device, rule.text) { return true }
            return false

        case .nameContains:
            return !device.name.isBlankSwift && TextMatch.contains(device.name, rule.text)

        case .nameGlob:
            guard !device.name.isBlankSwift, let re = Self.compileGlob(rule.text) else { return false }
            let range = NSRange(device.name.startIndex..., in: device.name)
            return re.firstMatch(in: device.name, options: [], range: range) != nil

        case .serviceUUID:
            let want = uuidAliases(rule.text)
            let have = device.serviceUuids + device.facts.serviceData.map { $0.uuid }
            return have.contains { uuid in !uuidAliases(uuid).isDisjoint(with: want) }

        case .manufacturerID:
            return Self.mfgRecords(device).contains { $0.companyId == rule.companyId }

        case .manufacturerData:
            let prefix = hexOnly(rule.dataPrefixHex)
            guard !prefix.isEmpty else { return false }
            return Self.mfgRecords(device).contains { rec in
                (rule.companyId == 0 || rec.companyId == rule.companyId)
                    && hexOnly(rec.dataHex).hasPrefix(prefix)
            }

        case .serviceData:
            let prefix = hexOnly(rule.dataPrefixHex)
            let aliases = Set(uuidAliases(rule.text).filter { !$0.isBlankSwift })
            if prefix.isEmpty && aliases.isEmpty { return false }
            return serviceDataHits(device, aliases, prefix,
                                   contains: rule.text.isBlankSwift && !prefix.isEmpty)

        case .radioKind:
            return rule.radio == nil || device.kind == rule.radio

        case .hiddenSSID:
            return device.hiddenSsid

        case .vendorIeOUI:
            return wifiVendorIeHitsOui(device, rule.text)
        }
    }

    /// BSSID افتراضي: شبكات guest/mesh ترفع البت المحلي على OUI مصنّع محروق.
    private func recoveredWifiOuiHits(_ device: Sighting, _ prefix: String) -> Bool {
        guard device.kind == .wifi else { return false }
        guard let univ = MacUtil.wifiOui24Universal(device.mac) else { return false }
        let want = prefix.filter { $0.isLetter || $0.isNumber }.uppercased()
        return want.count == 6 && univ == want
    }

    /// vendor IEs لـ Wi-Fi (قائمة «Vendor OUI» في التفاصيل) لا BSSID.
    /// تُتجاهل WPA (00:50:F2) و RSN (00:0F:AC) — وسوم بروتوكول لا منتج.
    private func wifiVendorIeHitsOui(_ device: Sighting, _ prefix: String) -> Bool {
        guard device.kind == .wifi else { return false }
        let want = hexOnly(prefix)
        if want.isEmpty || Self.WIFI_PROTOCOL_IE_OUIS.contains(String(want.prefix(6))) { return false }
        return device.vendorIeOuis.contains { ie in
            let hex = hexOnly(ie)
            if Self.WIFI_PROTOCOL_IE_OUIS.contains(String(hex.prefix(6))) { return false }
            return hex.hasPrefix(want)
        }
    }

    static func mfgRecords(_ device: Sighting) -> [MfgRecord] {
        if !device.facts.mfgRecords.isEmpty { return device.facts.mfgRecords }
        guard let id = device.manufacturerId else { return [] }
        return [MfgRecord(companyId: id, dataHex: device.manufacturerDataHex)]
    }

    // MARK: - Clusters

    private func applyClusters(
        _ devices: [Sighting], _ compiled: Compiled,
        _ byKey: inout [String: Set<String>], _ now: Int64
    ) {
        for (idx, plan) in compiled.plans.enumerated() {
            if !plan.cluster { continue }
            let fleet = plan.fleet
            let windowMs = Int64(fleet.peerWindowSec <= 0 ? 60 : fleet.peerWindowSec) * 1000
            let live = devices.filter { now - $0.lastSeen <= windowMs }

            for a in live {
                let aOui = compiled.ouiHits(a)
                let aEligible: Bool
                if plan.rawRules.isEmpty {
                    aEligible = true
                } else if fleetHits(a, plan, aOui[idx]) {
                    aEligible = true
                } else if fleet.clusterByOui && (a.name.isBlankSwift || a.randomized) {
                    aEligible = true
                } else {
                    aEligible = false
                }
                if !aEligible { continue }

                var peers = 1
                for b in live {
                    if b.key == a.key { continue }
                    if fleet.clusterByOui && a.oui != b.oui { continue }
                    if fleet.sequentialMac {
                        let diff = abs(MacUtil.last16(a.mac) - MacUtil.last16(b.mac))
                        if diff > 64 { continue }
                    }
                    if !plan.rawRules.isEmpty && !fleet.clusterByOui {
                        let bOui = compiled.ouiHits(b)
                        if !fleetHits(b, plan, bOui[idx]) { continue }
                    }
                    peers += 1
                }
                let need = fleet.minPeers <= 0 ? 3 : fleet.minPeers
                if peers >= need {
                    var set = byKey[a.key] ?? []
                    set.insert(plan.id)
                    byKey[a.key] = set
                }
            }
        }
    }

    // MARK: - أنواع داخلية

    private struct LongOui {
        var hex: String
        var radio: RadioKind?
        var bssid: Bool
        var vendor: Bool
        var fleetIdx: Int
    }

    private struct FleetPlan {
        var id: String
        var fleet: Fleet
        var cluster: Bool
        var matchAny: Bool
        var otherRules: [FastRule]
        var rawRules: [MatchRule]
    }

    private final class Compiled {
        let plans: [FleetPlan]
        let wifiPlans: [Int]
        let blePlans: [Int]
        let bssidWifi: [String: [Int]]
        let bssidBle: [String: [Int]]
        let vendorIe: [String: [Int]]
        let longOui: [LongOui]

        init(plans: [FleetPlan], wifiPlans: [Int], blePlans: [Int],
             bssidWifi: [String: [Int]], bssidBle: [String: [Int]],
             vendorIe: [String: [Int]], longOui: [LongOui]) {
            self.plans = plans
            self.wifiPlans = wifiPlans
            self.blePlans = blePlans
            self.bssidWifi = bssidWifi
            self.bssidBle = bssidBle
            self.vendorIe = vendorIe
            self.longOui = longOui
        }

        func plansFor(_ kind: RadioKind) -> [Int] {
            kind == .wifi ? wifiPlans : blePlans
        }

        func ouiHits(_ device: Sighting) -> [Bool] {
            var hits = [Bool](repeating: false, count: plans.count)
            let macHex = hexOnly(device.mac)
            let oui6 = macHex.count >= 6 ? String(macHex.prefix(6)) : macHex
            let bssidMap = device.kind == .wifi ? bssidWifi : bssidBle
            mark(&hits, bssidMap[oui6])

            if device.kind == .wifi {
                if let univ = MacUtil.wifiOui24Universal(device.mac) {
                    mark(&hits, bssidMap[univ])
                }
                for ie in device.vendorIeOuis {
                    let hex = hexOnly(ie)
                    if hex.count < 6 { continue }
                    let ie6 = String(hex.prefix(6))
                    if SignatureEngine.WIFI_PROTOCOL_IE_OUIS.contains(ie6) { continue }
                    mark(&hits, vendorIe[ie6])
                }
            }

            if !longOui.isEmpty && !macHex.isEmpty {
                for rule in longOui {
                    if let r = rule.radio, r != device.kind { continue }
                    if rule.bssid && macHex.hasPrefix(rule.hex) {
                        hits[rule.fleetIdx] = true
                    }
                    if rule.vendor && device.kind == .wifi {
                        for ie in device.vendorIeOuis {
                            let hex = hexOnly(ie)
                            if SignatureEngine.WIFI_PROTOCOL_IE_OUIS.contains(String(hex.prefix(6))) { continue }
                            if hex.hasPrefix(rule.hex) { hits[rule.fleetIdx] = true }
                        }
                    }
                }
            }
            return hits
        }

        private func mark(_ hits: inout [Bool], _ idxs: [Int]?) {
            guard let idxs else { return }
            for i in idxs where i < hits.count { hits[i] = true }
        }
    }

    private enum FastRule {
        case contains(String, RadioKind?)
        case glob(NSRegularExpression, RadioKind?)
        case uuid(Set<String>, RadioKind?)
        case mfgId(Int, RadioKind?)
        case mfgData(Int, String, RadioKind?)
        case svcData(Set<String>, String, RadioKind?, Bool)
        case radio(RadioKind?)
        case hidden

        func hits(_ device: Sighting) -> Bool {
            switch self {
            case let .contains(needle, radio):
                guard radioOk(device, radio) else { return false }
                return !device.name.isBlankSwift && TextMatch.contains(device.name, needle)

            case let .glob(re, radio):
                guard radioOk(device, radio), !device.name.isBlankSwift else { return false }
                let range = NSRange(device.name.startIndex..., in: device.name)
                return re.firstMatch(in: device.name, options: [], range: range) != nil

            case let .uuid(aliases, radio):
                guard radioOk(device, radio) else { return false }
                let have = device.serviceUuids + device.facts.serviceData.map { $0.uuid }
                return have.contains { uuid in !uuidAliases(uuid).isDisjoint(with: aliases) }

            case let .mfgId(id, radio):
                guard radioOk(device, radio) else { return false }
                return SignatureEngine.mfgRecords(device).contains { $0.companyId == id }

            case let .mfgData(id, prefix, radio):
                guard radioOk(device, radio) else { return false }
                return SignatureEngine.mfgRecords(device).contains { rec in
                    (id == 0 || rec.companyId == id) && hexOnly(rec.dataHex).hasPrefix(prefix)
                }

            case let .svcData(aliases, prefix, radio, contains):
                guard radioOk(device, radio) else { return false }
                return serviceDataHits(device, aliases, prefix, contains: contains)

            case let .radio(kind):
                return kind == nil || device.kind == kind

            case .hidden:
                return device.hiddenSsid
            }
        }

        private func radioOk(_ device: Sighting, _ radio: RadioKind?) -> Bool {
            radio == nil || device.kind == radio
        }
    }

    /// مجموعة مرتبة بسيطة — نظير LinkedHashSet في Kotlin.
    private struct OrderedHits {
        private(set) var list: [String] = []
        private var seen = Set<String>()

        mutating func add(_ id: String) {
            if seen.insert(id).inserted { list.append(id) }
        }
        mutating func remove(_ id: String) {
            if seen.remove(id) != nil { list.removeAll { $0 == id } }
        }
        func contains(_ id: String) -> Bool { seen.contains(id) }
        var set: Set<String> { seen }
    }
}

// MARK: - دوال ملف-خاصة (نظير private في Kotlin)

func serviceDataHits(
    _ device: Sighting,
    _ aliases: Set<String>,
    _ prefix: String,
    contains: Bool
) -> Bool {
    let needles: [String]
    if contains {
        let rev = reverseHexBytes(prefix)
        needles = (rev.isEmpty || rev == prefix) ? [prefix] : [prefix, rev]
    } else {
        needles = [prefix]
    }
    return device.facts.serviceData.contains { rec in
        if !aliases.isEmpty && uuidAliases(rec.uuid).isDisjoint(with: aliases) { return false }
        let data = hexOnly(rec.dataHex)
        if contains { return needles.contains { data.contains($0) } }
        return data.hasPrefix(prefix)
    }
}

/// ثوابت من DefaultCatalog.kt تُستعمل في المطابقة (بلا جدول الكتالوج الكامل).
public enum DefaultCatalogConstants {
    /// Kotlin: DefaultCatalog.TESLA_IBEACON_MFG_PREFIX
    public static let teslaIBeaconMfgPrefix = "021574278BDAB64445208F0C720EAF059935"
    /// DefaultCatalog.kt:17 — وسم Target/Atrius لسلال التسوّق (iBeacon بنفس بادئة آبل).
    public static let targetAtriusIBeaconMfgPrefix = "02155993A94C7D974DF79ABFE493BFD5D000"
}

extension String {
    var isBlankSwift: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
