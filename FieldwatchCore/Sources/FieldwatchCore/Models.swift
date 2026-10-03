//
//  Models.swift
//  FieldwatchCore
//
//  نقل Swift من Models.kt (الطبعة المطلوبة في الخطوة A) — الأسماء والقيم مطابقة
//  للأصل حتى تُقارن الاختبارات مع Kotlin، وحتى يبقى JSON الإعدادات متوافقًا.
//
//  ما لم يُنقل بعد (معلَّم صراحة، لا TODO صامت):
//    • ListLine / listTitle / listLineText — يحتاجان DeviceExplain.listLabel
//    • Sighting.key helpers المرتبطة بالكتالوج (signatureNames)
//    • Fleet / FilterPreset المرتبطة بالكتالوج (تُنقل مع الخطوة E)
//

import Foundation

// MARK: - Enums

/// RadioKind: WIFI / BLE — نفس قيم JSON في config.json الأصلي.
public enum RadioKind: String, Codable, Sendable, CaseIterable {
    case wifi = "WIFI"
    case ble = "BLE"
}

extension RadioKind {
    /// Kotlin: fun RadioKind.label()
    public func label() -> String { self == .wifi ? "Wi-Fi" : "BLE" }
}

public enum FilterLogic: String, Codable, Sendable, CaseIterable {
    case and = "AND"
    case or = "OR"
}

/// SignatureClass — كل القيم كما في Models.kt (BODYWORN يبقى لفك ملفات قديمة).
public enum SignatureClass: String, Codable, Sendable, CaseIterable {
    case finder = "FINDER"
    case beacon = "BEACON"
    case signage = "SIGNAGE"
    case wearable = "WEARABLE"
    case surveillance = "SURVEILLANCE"
    case drone = "DRONE"
    case hacking = "HACKING"
    case bodyworn = "BODYWORN"
    case lawEnforcement = "LAW_ENFORCEMENT"
    case vehicle = "VEHICLE"
    case glasses = "GLASSES"
    case audio = "AUDIO"
    case camera = "CAMERA"
    case thermostat = "THERMOSTAT"
    case lock = "LOCK"
    case health = "HEALTH"
    case home = "HOME"
    case isp = "ISP"
    case mesh = "MESH"
    case phone = "PHONE"
    case other = "OTHER"

    public func label() -> String {
        switch self {
        case .finder: return "Finder tags"
        case .beacon: return "Retail beacons"
        case .signage: return "Signage"
        case .wearable: return "Wearables"
        case .surveillance: return "Surveillance"
        case .drone: return "Drones"
        case .hacking: return "Pentest"
        case .bodyworn: return "Body-worn"
        case .lawEnforcement: return "Public safety"
        case .vehicle: return "Vehicle"
        case .glasses: return "Glasses"
        case .audio: return "Audio"
        case .camera: return "Cameras"
        case .thermostat: return "Thermostats"
        case .lock: return "Access control"
        case .health: return "Health"
        case .home: return "Home IoT"
        case .isp: return "ISP / routers"
        case .mesh: return "Mesh"
        case .phone: return "Phones / PCs"
        case .other: return "Other"
        }
    }

    /// الشكل المنطوق المختصر لقائمة المراقبة الصوتية.
    public func speechLabel() -> String {
        switch self {
        case .finder: return "finder tags"
        case .beacon: return "retail beacons"
        case .signage: return "signage"
        case .wearable: return "wearables"
        case .surveillance: return "surveillance"
        case .drone: return "drones"
        case .hacking: return "pentest"
        case .bodyworn: return "body worn"
        case .lawEnforcement: return "public safety"
        case .vehicle: return "vehicle"
        case .glasses: return "glasses"
        case .audio: return "audio"
        case .camera: return "cameras"
        case .thermostat: return "thermostats"
        case .lock: return "access control"
        case .health: return "health"
        case .home: return "home I O T"
        case .isp: return "I S P routers"
        case .mesh: return "mesh"
        case .phone: return "phones"
        case .other: return "other"
        }
    }

    /// BODYWORN كان دلوًا قديمًا (Axon / WatchGuard انتقلا إلى Public safety).
    /// يُطوى إلى WEARABLE كي تعرض الفلاتر/الفئات فئة واحدة، مع بقاء القيمة
    /// لتفكيك config.json وحِزم التواقيع القديمة.
    public func folded() -> SignatureClass { self == .bodyworn ? .wearable : self }
}

// MARK: - Samples

public struct RssiSample: Codable, Sendable, Equatable {
    public var at: Int64
    public var rssi: Int
    public init(at: Int64, rssi: Int) { self.at = at; self.rssi = rssi }
}

public struct GpsSample: Codable, Sendable, Equatable {
    public var at: Int64
    public var lat: Double
    public var lon: Double
    public var rssi: Int
    public init(at: Int64, lat: Double, lon: Double, rssi: Int = 0) {
        self.at = at; self.lat = lat; self.lon = lon; self.rssi = rssi
    }
}

public struct PresenceSpan: Sendable, Equatable {
    public var start: Int64
    public var end: Int64?
    public init(start: Int64, end: Int64? = nil) { self.start = start; self.end = end }
}

/// PayloadFix — موقع مُعلن مخزَّن في الـ sit (ليس GPS الهاتف).
public struct PayloadFix: Codable, Sendable, Equatable {
    public var at: Int64
    public var lat: Double
    public var lon: Double
    public var alt: Double?
    public var heading: Double?
    public var speed: Double?
    public init(at: Int64, lat: Double, lon: Double,
                alt: Double? = nil, heading: Double? = nil, speed: Double? = nil) {
        self.at = at; self.lat = lat; self.lon = lon
        self.alt = alt; self.heading = heading; self.speed = speed
    }
}

/// LiveDecodeChip — وسم مفكوك يُرسم بجانب اسم التوقيع. النص من الكتالوج نفسه.
public struct LiveDecodeChip: Codable, Sendable, Equatable {
    public var text: String
    public var emphasis: Bool
    public var note: String
    public init(text: String, emphasis: Bool, note: String = "") {
        self.text = text; self.emphasis = emphasis; self.note = note
    }

    /// Title-case للتقارير والوسم: نص الكتالوج مخزَّن بحروف صغيرة.
    public func reportLabel() -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return trimmed }
        let head = first.isLowercase ? String(first).uppercased() : String(first)
        return head + trimmed.dropFirst()
    }
}

// MARK: - Radio facts

public struct MfgRecord: Codable, Sendable, Equatable {
    public var companyId: Int
    public var dataHex: String
    public init(companyId: Int, dataHex: String) { self.companyId = companyId; self.dataHex = dataHex }
}

public struct VendorIeRecord: Codable, Sendable, Equatable {
    public var oui: String
    public var type: Int
    public var dataHex: String
    public init(oui: String, type: Int, dataHex: String) {
        self.oui = oui; self.type = type; self.dataHex = dataHex
    }
}

public struct ServiceDataRecord: Codable, Sendable, Equatable {
    public var uuid: String
    public var dataHex: String
    public init(uuid: String, dataHex: String) { self.uuid = uuid; self.dataHex = dataHex }
}

/// RadioFacts — يبنيها الراديو من ScanResult على أندرويد، ومن CBAdvertisementData على iOS.
public struct RadioFacts: Sendable, Equatable {
    public var txPowerDbm: Int?
    public var advFlags: Int?
    public var appearance: Int?
    public var addressType: String?
    public var connectable: Bool?
    public var deviceClass: Int?
    public var security: String?
    public var supportedRates: String?
    public var capabilities: String?
    public var mfgRecords: [MfgRecord]
    public var vendorIes: [VendorIeRecord]
    public var serviceData: [ServiceDataRecord]

    public init(
        txPowerDbm: Int? = nil,
        advFlags: Int? = nil,
        appearance: Int? = nil,
        addressType: String? = nil,
        connectable: Bool? = nil,
        deviceClass: Int? = nil,
        security: String? = nil,
        supportedRates: String? = nil,
        capabilities: String? = nil,
        mfgRecords: [MfgRecord] = [],
        vendorIes: [VendorIeRecord] = [],
        serviceData: [ServiceDataRecord] = []
    ) {
        self.txPowerDbm = txPowerDbm
        self.advFlags = advFlags
        self.appearance = appearance
        self.addressType = addressType
        self.connectable = connectable
        self.deviceClass = deviceClass
        self.security = security
        self.supportedRates = supportedRates
        self.capabilities = capabilities
        self.mfgRecords = mfgRecords
        self.vendorIes = vendorIes
        self.serviceData = serviceData
    }

    /// Kotlin: RadioFacts.Empty
    public static let Empty = RadioFacts()

    /// Kotlin: facts.mfg (أول سجل manufacturer).
    public var mfg: MfgRecord? { mfgRecords.first }
}

// MARK: - Sighting

/// Sighting — الصف الحي. نفس ترتيب وقيم Models.kt (الحقول بعد presence لها قيم افتراضية).
public struct Sighting: Sendable, Equatable {
    public init(key:String, kind:RadioKind, mac:String, name:String = "", rssi:Int = -60, rssiMin:Int = -60, rssiMax:Int = -60, channel:Int = 0, frequencyMhz:Int = 0, vendor:String? = nil, randomized:Bool = false, hiddenSsid:Bool = false, serviceUuids:[String] = [], manufacturerId:Int? = nil, manufacturerDataHex:String = "", rawHex:String = "", extras:String = "", firstSeen:Int64 = 0, lastSeen:Int64 = 0, hitCount:Int = 1, fleetIds:Set<String> = [], rssiHistory:[RssiSample] = [], presence:[PresenceSpan] = [], latitude:Double? = nil, longitude:Double? = nil, gone:Bool = false, vendorIeOuis:[String] = [], facts:RadioFacts = .Empty, gpsTrail:[GpsSample] = [], fastPairPairing:Bool = false, payloadLat:Double? = nil, payloadLon:Double? = nil, payloadAlt:Double? = nil, payloadOpLat:Double? = nil, payloadOpLon:Double? = nil, payloadUasId:String? = nil, payloadSelfId:String? = nil, payloadHeading:Double? = nil, payloadSpeed:Double? = nil, payloadVspeed:Double? = nil, payloadTrail:[PayloadFix] = [], liveDecode:[LiveDecodeChip] = []) {
        self.key=key; self.kind=kind; self.mac=mac; self.name=name; self.rssi=rssi; self.rssiMin=rssiMin; self.rssiMax=rssiMax; self.channel=channel; self.frequencyMhz=frequencyMhz; self.vendor=vendor; self.randomized=randomized; self.hiddenSsid=hiddenSsid; self.serviceUuids=serviceUuids; self.manufacturerId=manufacturerId; self.manufacturerDataHex=manufacturerDataHex; self.rawHex=rawHex; self.extras=extras; self.firstSeen=firstSeen; self.lastSeen=lastSeen; self.hitCount=hitCount; self.fleetIds=fleetIds; self.rssiHistory=rssiHistory; self.presence=presence; self.latitude=latitude; self.longitude=longitude; self.gone=gone; self.vendorIeOuis=vendorIeOuis; self.facts=facts; self.gpsTrail=gpsTrail; self.fastPairPairing=fastPairPairing; self.payloadLat=payloadLat; self.payloadLon=payloadLon; self.payloadAlt=payloadAlt; self.payloadOpLat=payloadOpLat; self.payloadOpLon=payloadOpLon; self.payloadUasId=payloadUasId; self.payloadSelfId=payloadSelfId; self.payloadHeading=payloadHeading; self.payloadSpeed=payloadSpeed; self.payloadVspeed=payloadVspeed; self.payloadTrail=payloadTrail; self.liveDecode=liveDecode
    }
    public var key: String
    public var kind: RadioKind
    public var mac: String
    public var name: String
    public var rssi: Int
    public var rssiMin: Int
    public var rssiMax: Int
    public var channel: Int
    public var frequencyMhz: Int
    public var vendor: String?
    public var randomized: Bool
    public var hiddenSsid: Bool
    public var serviceUuids: [String]
    public var manufacturerId: Int?
    public var manufacturerDataHex: String
    public var rawHex: String
    public var extras: String
    public var firstSeen: Int64
    public var lastSeen: Int64
    public var hitCount: Int
    public var fleetIds: Set<String>
    public var rssiHistory: [RssiSample]
    public var presence: [PresenceSpan]
    public var latitude: Double? = nil
    public var longitude: Double? = nil
    public var gone: Bool = false
    public var vendorIeOuis: [String] = []
    public var facts: RadioFacts = RadioFacts.Empty
    public var gpsTrail: [GpsSample] = []
    /// معرّف Fast Pair بثلاثة بايتات شوهد في هذه الجلسة. يبقى إن طالت الحمولة لاحقًا.
    public var fastPairPairing: Bool = false
    /// موقع WGS84 لاصق من حقول الفك latitude/longitude.
    public var payloadLat: Double? = nil
    public var payloadLon: Double? = nil
    public var payloadAlt: Double? = nil
    /// موقع مشغّل Remote ID (الطيّار). ليس دبوس الطائرة.
    public var payloadOpLat: Double? = nil
    public var payloadOpLon: Double? = nil
    /// Basic ID / Self ID لاصق. TAK يفتح الطائرة على uas_id إن وُجد.
    public var payloadUasId: String? = nil
    public var payloadSelfId: String? = nil
    public var payloadHeading: Double? = nil
    public var payloadSpeed: Double? = nil
    public var payloadVspeed: Double? = nil
    /// المواقع المُعلنة التي يحفظها الـ sit. فارغة على راديو حي لم يُحفظ بعد.
    public var payloadTrail: [PayloadFix] = []
    /// وسوم مفكوكة طلب توقيع عرضها على الصف الحي. فارغة لكل راديو آخر.
    public var liveDecode: [LiveDecodeChip] = []

    // MARK: المشتقات

    public var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (hiddenSsid ? "<hidden>" : mac)
            : name
    }

    /// الاسم المخصص من Named radios، وإلا المُعلن / المخفي / MAC.
    public func reportName(customNames: [String: String]) -> String {
        if let custom = customNames[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !custom.isEmpty {
            return custom
        }
        return displayName
    }

    /// SSID أو اسم BLE المحلي؛ بدائل إن كان فارغًا.
    public func advertisedName() -> String {
        let advertised = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !advertised.isEmpty && advertised.lowercased() != mac.lowercased() {
            return advertised
        }
        if kind == .wifi { return hiddenSsid ? "<hidden>" : mac }
        return "unnamed LE"
    }

    public func radioKindTag() -> String { kind == .wifi ? "AP" : "LE" }

    /// Kotlin: statusCrumbs()
    public func statusCrumbs() -> String {
        var out = ""
        if randomized { out += "rand" }
        if fastPairPairing {
            if !out.isEmpty { out += "  " }
            out += "pair"
        }
        if gone {
            if !out.isEmpty { out += "  " }
            out += "gone"
        }
        return out
    }

    /// أول 8 محارف من MAC — البادئة.
    public var oui: String { String(mac.prefix(8)) }

    // PORT-TODO(iOS): listTitle(signatureNames:) وlistLineText(line:...) يحتاجان
    // DeviceExplain.listLabel + ListLine من DeviceExplain.kt — تُنقلان في الخطوة G.
}

/// SwiftUI: `.sheet(item:)` و`.id` يحتاجان Identifiable.
/// المفتاح الفريد هو `key` نفسه المستخدم في Kotlin: "KIND:MAC".
/// موضعه هنا (مع تعريف النوع) لا في طبقة التطبيق: مطابقة بروتوكول خارجي على
/// نوع خارجي تُنتج تحذير retroactive conformance — وهذا يزيله من جذره.
extension Sighting: Identifiable {
    public var id: String { key }
}

// MARK: - Filters

public struct FilterState: Sendable, Equatable, Codable {
    public var namedOnly: Bool = false
    /// إدراج حي: الراديوهات ذات الاسم المخصص فقط (Settings → Named radios).
    public var customNamesOnly: Bool = false
    /// إدراج حي: التواقيع المُعلَّمة أو Named radios مع Alert مفتوح.
    public var watchedOnly: Bool = false
    public var useFleetFilter: Bool = false
    public var excludeSignatures: Bool = false
    public var fleetIds: Set<String> = []
    /// إدراج حي: الراديوهات المطابقة لهذه المعرّفات فقط. مجموعة فارغة = بلا بوابة إدراج.
    public var includeSignatures: Bool = false
    public var includeFleetIds: Set<String> = []
    public var showWifi: Bool = true
    public var showBle: Bool = true
    public var rssiMin: Int = -100
    public var nameQuery: String = ""
    public var ouiQuery: String = ""
    public var logic: FilterLogic = .and
    public var movingWithYou: Bool = false
    /// إخفاء الراديوهات المشاهَدة سابقًا؛ Mark seen / Reset seen يعملان مع هذا المفتاح.
    public var arrivalsOnly: Bool = false
    /// إخفاء Fast Pair ذي مفتاح الحساب فقط (ضجيج الساحات). وضع الإقران
    /// والشرائح المزدوجة تبقى.
    public var hideFastPairAccountKey: Bool = false
    /// إظهار/إخفاء صفوف Live حسب فئة التوقيع. مستقل عن تشغيل مطابقة التواقيع.
    public var useClassFilter: Bool = false
    public var excludeClasses: Bool = false
    public var classes: Set<SignatureClass> = []

    public init() {}

    /// عرض فقط = تضييق Live إلى فئة واحدة مختارة على الأقل. فارغة = لا تُخفي غير المطابق.
    public func classIncludeActive() -> Bool {
        useClassFilter && !excludeClasses && !classes.isEmpty
    }

    public func signatureIncludeActive() -> Bool {
        includeSignatures && !includeFleetIds.isEmpty
    }

    public func namedOnlyImplied() -> Bool {
        classIncludeActive() || signatureIncludeActive()
    }
}

public struct FilterPreset: Sendable, Equatable {
    public var id: String
    public var name: String
    public var filter: FilterState
    public init(id: String, name: String, filter: FilterState) {
        self.id = id; self.name = name; self.filter = filter
    }
    public func isBuiltIn() -> Bool { FilterPresets.builtInIds.contains(id) }
}

public enum FilterPresets {
    /// Kotlin: private val BuiltInPresetIds — شرائح مخزَّنة متقاعدة تبقى هنا
    /// كي لا تُعتبر مخصصة عند الترقية.
    public static let builtInIds: Set<String> = [
        "all", "wifi", "ble", "strong", "with-you", "watched",
        "trackers", "hide-trackers", "hide-phones", "named",
        "surveillance", "drones", "beacons", "signage", "wearables", "pentest",
    ]
}

// MARK: - Text helpers

public enum TextMatch {
    /// Kotlin: contains(hay, needle) — حساسية حالة الأحرف مُهمَلة، والفراغ = false.
    public static func contains(_ hay: String, _ needle: String) -> Bool {
        let n = needle.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty { return false }
        return hay.range(of: needle, options: .caseInsensitive) != nil
    }

    /// Kotlin: glob(text, pattern) — `*` و`?` فقط، والباقي مُهرَّب.
    public static func glob(_ text: String, _ pattern: String) -> Bool {
        if pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        var regex = "^"
        for ch in pattern {
            switch ch {
            case "*": regex += ".*"
            case "?": regex += "."
            default: regex += NSRegularExpression.escapedPattern(for: String(ch))
            }
        }
        regex += "$"
        return text.range(of: regex, options: [.regularExpression, .caseInsensitive]) != nil
    }
}

// MARK: - Hex helpers

/// toHexUpper — نفس دلالة Kotlin: بايتان لكل بايت، أحرف كبيرة.
public func toHexUpper(_ bytes: [UInt8]) -> String {
    var out = String()
    out.reserveCapacity(bytes.count * 2)
    for b in bytes { out += String(format: "%02X", Int(b)) }
    return out
}

public extension Data {
    var fieldwatchHexUpper: String { toHexUpper([UInt8](self)) }
}

/// فك سلسلة hex كما يفعل OpenDroneId.hex: يتجاهل ما ليس حرفًا/رقمًا ويرفض الطول الفردي.
public func hexBytes(_ s: String) -> [UInt8]? {
    let h = s.filter { $0.isLetter || $0.isNumber }
    if h.isEmpty || h.count % 2 != 0 { return nil }
    var out = [UInt8]()
    out.reserveCapacity(h.count / 2)
    var idx = h.startIndex
    while idx < h.endIndex {
        let next = h.index(idx, offsetBy: 2)
        guard let v = UInt8(h[idx..<next], radix: 16) else { return nil }
        out.append(v)
        idx = next
    }
    return out
}

// MARK: - Signature catalog models (portable equivalent of Models.kt)

public enum RuleKind: String, Codable, Sendable, CaseIterable {
    case oui = "OUI", macPrefix = "MAC_PREFIX", nameContains = "NAME_CONTAINS", nameGlob = "NAME_GLOB"
    case serviceUUID = "SERVICE_UUID", serviceData = "SERVICE_DATA", manufacturerID = "MANUFACTURER_ID"
    case manufacturerData = "MANUFACTURER_DATA", radioKind = "RADIO_KIND", hiddenSSID = "HIDDEN_SSID", vendorIeOUI = "VENDOR_IE_OUI"
}

public struct MatchRule: Codable, Sendable, Equatable {
    public var kind: RuleKind
    public var text: String
    public var companyId: Int
    public var dataPrefixHex: String
    public var radio: RadioKind?
    public var enabled: Bool
    public init(kind: RuleKind, text: String = "", companyId: Int = 0, dataPrefixHex: String = "", radio: RadioKind? = nil, enabled: Bool = true) {
        self.kind = kind; self.text = text; self.companyId = companyId; self.dataPrefixHex = dataPrefixHex; self.radio = radio; self.enabled = enabled
    }
}

public enum DecodeSource: String, Codable, Sendable { case manufacturerData = "manufacturerData", serviceData = "serviceData", unsupported = "unsupported" }
public enum DecodeType: String, Codable, Sendable { case u8="u8", i8="i8", u16="u16", i16="i16", u24="u24", u32="u32", i32="i32", f32="f32", bits="bits", utf8="utf8", hex="hex", mac="mac", bool="bool" }
public enum DecodeEndian: String, Codable, Sendable { case le="le", be="be" }
public enum DecodeWhenOp: String, Codable, Sendable { case eq="eq", neq="neq", mask="mask", nmask="nmask", len="len" }

public final class DecodeWhen: Codable, @unchecked Sendable, Equatable {
    public var offset: Int; public var length: Int; public var op: DecodeWhenOp; public var valueHex: String; public var and: DecodeWhen?
    public init(offset: Int, length: Int = 1, op: DecodeWhenOp, valueHex: String, and: DecodeWhen? = nil) { self.offset=offset; self.length=length; self.op=op; self.valueHex=valueHex; self.and=and }
    public static func == (lhs: DecodeWhen, rhs: DecodeWhen) -> Bool { lhs.offset == rhs.offset && lhs.length == rhs.length && lhs.op == rhs.op && lhs.valueHex == rhs.valueHex && lhs.and == rhs.and }
}

public struct DecodeField: Codable, Sendable, Equatable {
    public var id: String; public var label: String; public var offset: Int; public var length: Int?; public var type: DecodeType
    public var endian: DecodeEndian; public var bitOffset: Int?; public var bitWidth: Int?; public var scale: Double?; public var offsetAdd: Double?
    public var modulo: Double?; public var unit: String?; public var when: DecodeWhen?; public var enumLabels: [String:String]?; public var live: Bool; public var liveEmphasis: [String]; public var enumNotes: [String:String]?
    public init(id:String,label:String,offset:Int,length:Int?=nil,type:DecodeType,endian:DecodeEndian = .le,bitOffset:Int?=nil,bitWidth:Int?=nil,scale:Double?=nil,offsetAdd:Double?=nil,modulo:Double?=nil,unit:String?=nil,when:DecodeWhen?=nil,enumLabels:[String:String]?=nil,live:Bool=false,liveEmphasis:[String]=[],enumNotes:[String:String]?=nil) {
        self.id=id; self.label=label; self.offset=offset; self.length=length; self.type=type; self.endian=endian; self.bitOffset=bitOffset; self.bitWidth=bitWidth; self.scale=scale; self.offsetAdd=offsetAdd; self.modulo=modulo; self.unit=unit; self.when=when; self.enumLabels=enumLabels; self.live=live; self.liveEmphasis=liveEmphasis; self.enumNotes=enumNotes
    }
    /// FIX-07: مطابق لـ Kotlin `DecodeField.resolvedLength()` — mac=6،
    /// وbits = ceil((bitOffset+bitWidth)/8)، والباقي كما في defaultLength.
    public func resolvedLength() -> Int {
        if let length, length > 0 { return length }
        if type == .bits {
            let start = bitOffset ?? 0
            let width = bitWidth ?? 1
            return max(1, (start + width + 7) / 8)
        }
        switch type {
        case .u8, .i8, .bool: return 1
        case .u16, .i16: return 2
        case .u24: return 3
        case .u32, .i32, .f32: return 4
        case .mac: return 6
        case .bits, .utf8, .hex: return 1
        }
    }
}

public struct FleetDecode: Codable, Sendable, Equatable {
    public var source: DecodeSource; public var companyId: Int?; public var serviceUuid: String?; public var includeCompanyId: Bool; public var fields: [DecodeField]
    public init(source:DecodeSource,companyId:Int?=nil,serviceUuid:String?=nil,includeCompanyId:Bool=false,fields:[DecodeField]=[]) { self.source=source; self.companyId=companyId; self.serviceUuid=serviceUuid; self.includeCompanyId=includeCompanyId; self.fields=fields }
}

public struct Fleet: Codable, Sendable, Equatable {
    public var id:String; public var name:String; public var enabled:Bool; public var matchAny:Bool; public var colorIndex:Int; public var rules:[MatchRule]
    public var minPeers:Int; public var peerWindowSec:Int; public var clusterByOui:Bool; public var sequentialMac:Bool; public var notes:String; public var attentionNote:String; public var builtIn:Bool; public var kind:SignatureClass; public var decode:FleetDecode?
    public init(id:String,name:String,enabled:Bool=true,matchAny:Bool=true,colorIndex:Int=0,rules:[MatchRule]=[],minPeers:Int=0,peerWindowSec:Int=60,clusterByOui:Bool=false,sequentialMac:Bool=false,notes:String="",attentionNote:String="",builtIn:Bool=false,kind:SignatureClass = .other,decode:FleetDecode?=nil) { self.id=id;self.name=name;self.enabled=enabled;self.matchAny=matchAny;self.colorIndex=colorIndex;self.rules=rules;self.minPeers=minPeers;self.peerWindowSec=peerWindowSec;self.clusterByOui=clusterByOui;self.sequentialMac=sequentialMac;self.notes=notes;self.attentionNote=attentionNote;self.builtIn=builtIn;self.kind=kind;self.decode=decode }
}


extension FleetDecode {
    enum CodingKeys: String, CodingKey { case source, companyId, serviceUuid, includeCompanyId, fields }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.source = try c.decodeIfPresent(DecodeSource.self, forKey: .source) ?? .unsupported
        self.companyId = try c.decodeIfPresent(Int.self, forKey: .companyId)
        self.serviceUuid = try c.decodeIfPresent(String.self, forKey: .serviceUuid)
        self.includeCompanyId = try c.decodeIfPresent(Bool.self, forKey: .includeCompanyId) ?? false
        self.fields = try c.decodeIfPresent([DecodeField].self, forKey: .fields) ?? []
    }
}

extension DecodeField {
    enum CodingKeys: String, CodingKey { case id,label,offset,length,type,endian,bitOffset,bitWidth,scale,offsetAdd,modulo,unit,when,enumLabels = "enum",live,liveEmphasis,enumNotes }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        id=try c.decode(String.self,forKey:.id); label=try c.decode(String.self,forKey:.label); offset=try c.decode(Int.self,forKey:.offset); length=try c.decodeIfPresent(Int.self,forKey:.length); type=try c.decode(DecodeType.self,forKey:.type); endian=try c.decodeIfPresent(DecodeEndian.self,forKey:.endian) ?? .le; bitOffset=try c.decodeIfPresent(Int.self,forKey:.bitOffset); bitWidth=try c.decodeIfPresent(Int.self,forKey:.bitWidth); scale=try c.decodeIfPresent(Double.self,forKey:.scale); offsetAdd=try c.decodeIfPresent(Double.self,forKey:.offsetAdd); modulo=try c.decodeIfPresent(Double.self,forKey:.modulo); unit=try c.decodeIfPresent(String.self,forKey:.unit); when=try c.decodeIfPresent(DecodeWhen.self,forKey:.when); enumLabels=try c.decodeIfPresent([String:String].self,forKey:.enumLabels); live=try c.decodeIfPresent(Bool.self,forKey:.live) ?? false; liveEmphasis=try c.decodeIfPresent([String].self,forKey:.liveEmphasis) ?? []; enumNotes=try c.decodeIfPresent([String:String].self,forKey:.enumNotes)
    }
}
