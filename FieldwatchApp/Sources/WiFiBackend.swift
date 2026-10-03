//
//  WiFiBackend.swift
//  Fieldwatch (target التطبيق)
//
//  العقد الذي فرضه ملف الـ handoff: كل مسح Wi‑Fi يبقى خلف `WiFiBackend`،
//  وللـ backends تطبيقات منفصلة:
//      iOSNativeBackend        — ما تسمح به آبل رسميًا (بلا مسح، بلا IEs)
//      JailbreakBackend        — private APIs، معزول هنا، ولا يُقدَّم كحل مستقر
//      ExternalRadioBackend    — راديو خارجي (ESP32/nRF) — الخطوة K كما في الخطة
//
//  الجسر المهم: WiFiScanResult → RadioFacts عبر WifiIeParser →
//  OpenDroneId.fromFacts، أي نفس مسار أندرويد بالحرف (WifiRadio.toObservation).
//

import Foundation
import FieldwatchCore

// MARK: - الأنواع

enum WiFiBackendKind: String, Sendable, CaseIterable {
    case iOSNative
    case jailbreakPrivate
    case externalRadio
}

/// نتيجة مسح واحدة، بالشكل الموحّد الذي تراه بقية الطبقات.
struct WiFiScanResult: Sendable, Equatable {
    var bssid: String?          // أندرويد: BSSID. على iOS الأصلي: غالبًا nil (يحتاج صلاحية/entitlement)
    var ssid: String?
    var rssi: Int               // أندرويد: level/RSSI. الـ backend الأصلي على iOS لا يعطيه ⇒ 0
    var channel: Int?
    var ieBlob: [UInt8]?        // الـ raw information elements — بيت القصيد لهذا التطبيق
    var capabilities: String?   // نص وصفي للقدرات/الأمان إن توفّر
    var seenAt: Date = Date()
    var fresh: Bool = true
    var source: WiFiBackendKind = .jailbreakPrivate
}

protocol WiFiBackend: AnyObject {
    var kind: WiFiBackendKind { get }
    var isAvailable: Bool { get }
    var onObservation: ((WiFiScanResult) -> Void)? { get set }
    var onScanFinished: ((_ count: Int, _ fresh: Bool) -> Void)? { get set }
    func start()
    func stop()
    func requestScan(minIntervalMs: Int)
}

/// اختيار الـ backend: Jailbreak إن أمكن، وإلا الأصلي (يظل التطبيق يعمل، بلا Wi‑Fi حقيقي).
final class WiFiBackendSelector {
    let backend: WiFiBackend

    init(preferJailbreak: Bool = true) {
        let jb = JailbreakWiFiBackend()
        if preferJailbreak && jb.isAvailable {
            backend = jb
        } else {
            backend = iOSNativeWiFiBackend()
        }
    }
}

// MARK: - الجسر نحو Core

extension WiFiScanResult {

    /// تفكيك IE blob خام إلى عناصر (id + payload).
    /// على أندرويد يفكّه النظام في ScanResult.informationElements؛ هنا نفكّه بأنفسنا.
    static func splitIes(_ blob: [UInt8]) -> [WifiIeParser.Ie] {
        var out = [WifiIeParser.Ie]()
        var i = 0
        while i + 2 <= blob.count {
            let id = Int(blob[i])
            let len = Int(blob[i + 1])
            if i + 2 + len > blob.count { break }   // إطار مبتور: نتوقف بدل أن نخمّن
            out.append(WifiIeParser.Ie(id: id, bytes: Array(blob[(i + 2)..<(i + 2 + len)])))
            i += 2 + len
        }
        return out
    }

    /// نتيجة فك الـ IEs — nil إن لم يكن لهذا الـ backend blob خام (iOSNative).
    func parsedIes() -> WifiIeParser.Parsed? {
        guard let blob = ieBlob else { return nil }
        return WifiIeParser.parseIes(Self.splitIes(blob), capabilities: capabilities)
    }

    /// نفس دور WifiRadio.toObservation: يبني RadioFacts بما فيها vendorIes.
    func toRadioFacts() -> RadioFacts {
        var facts = RadioFacts()
        facts.capabilities = capabilities
        facts.security = capabilities
        if let parsed = parsedIes() {
            facts.vendorIes = parsed.vendorIes
            facts.supportedRates = parsed.rates
            facts.security = parsed.security
        }
        return facts
    }

    /// القناة: قناة النظام إن وُجدت، وإلا من عنصر DS parameter (id 3).
    func channelResolved() -> Int? {
        channel ?? parsedIes()?.channelFromDs
    }

    /// هل هذا الـ AP يحمل Remote ID عبر Wi-Fi؟ (vendor IE FA:0B:BC type 0x0D)
    func remoteIdLocation() -> PayloadLocation {
        OpenDroneId.fromFacts(toRadioFacts())
    }
}
