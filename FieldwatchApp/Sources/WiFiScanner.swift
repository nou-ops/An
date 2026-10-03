//
//  WiFiScanner.swift
//  Fieldwatch (target التطبيق)
//
//  يستعمل WiFiBackendSelector ويمرّر كل نتيجة عبر نفس مسار أندرويد:
//      WiFiScanResult → (فك IE) → RadioFacts → OpenDroneId / WifiIeParser
//  فيظهر في الواجهة: SSID/BSSID، القوة، القناة، الأمان، عدد vendor IEs،
//  وإن كان AP يحمل Remote ID عبر Wi-Fi (vendor IE FA:0B:BC نوع 0x0D).
//

import Foundation
import Combine
import FieldwatchCore

struct WiFiRow: Identifiable, Hashable {
    let id: String
    var ssid: String?
    var bssid: String?
    var rssi: Int
    var channel: Int?
    var security: String?
    var vendorIeCount: Int
    var ridLat: Double?
    var ridLon: Double?
    var source: String
}

final class WiFiScanner: ObservableObject {

    @Published private(set) var rows: [WiFiRow] = []
    @Published private(set) var backendName: String = "…"
    @Published private(set) var isScanning = false
    @Published private(set) var lastNote: String = ""
    @Published private(set) var lastScanCount = 0
    @Published private(set) var totalScans = 0

    /// هل الـ backend قادر على مسح المحيط فعلًا؟ (الأصلي: لا)
    var isAvailable: Bool { backend.isAvailable }
    var backendKind: WiFiBackendKind { backend.kind }

    /// أي إطار من آبل حُمّل فعلًا؟ (يظهر في الواجهة وprobe)
    var applePathLoaded: Bool { (backend as? JailbreakWiFiBackend)?.appleLoaded ?? false }
    var mobileWiFiPathLoaded: Bool { (backend as? JailbreakWiFiBackend)?.mobileWiFiLoaded ?? false }
    /// أي مسار أنتج آخر نتائج: "Apple80211" أو "MobileWiFi" أو "—"
    var activeSource: String { (backend as? JailbreakWiFiBackend)?.activePath ?? "—" }
    /// آخر ما قاله الـ backend عن نفسه (رسالة قصيرة تشرح سبب الفشل)
    var backendNote: String { (backend as? JailbreakWiFiBackend)?.lastNote ?? lastNote }
    /// مسح Wi-Fi عبر Apple80211 متزامن ويحجب الخيط ⇒ لا نستدعيه إلا على طابور خلفي.
    private let queue = DispatchQueue(label: "app.fieldwatch.wifi")
    private var lastPeriodicAt = Date.distantPast

    private let selector = WiFiBackendSelector(preferJailbreak: true)
    private var backend: WiFiBackend { selector.backend }

    init() {
        backendName = Self.describe(backend.kind)
        backend.onObservation = { [weak self] result in
            self?.ingest(result)
        }
        backend.onScanFinished = { [weak self] count, fresh in
            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanning = false
                self.lastScanCount = count
                self.totalScans += 1
                self.lastNote = "انتهى المسح: \(count) شبكة" + (fresh ? " (نتائج جديدة)" : " (ليست مسحًا جديدًا)")
            }
        }
    }

    func start() {
        isScanning = true
        backend.start()
    }

    func stop() {
        backend.stop()
        isScanning = false
    }

    /// مسح فوري بطلب المستخدم (على طابور خلفي حتى لا تتجمد الواجهة).
    func scanOnce() {
        isScanning = true
        queue.async { [weak self] in self?.backend.requestScan(minIntervalMs: 0) }
    }

    /// مسح دوري هادئ: يُستدعى من نبضة المتجر (كل ٠٫٥ ث) لكنه يمرّ مرة كل
    /// `minIntervalMs` فقط — ولا يعمل إلا إذا كان الـ backend يقدر فعلًا.
    func periodicScan(minIntervalMs: Int = 6000) {
        guard backend.kind == .jailbreakPrivate, backend.isAvailable else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPeriodicAt) * 1000 >= Double(minIntervalMs) else { return }
        lastPeriodicAt = now
        queue.async { [weak self] in self?.backend.requestScan(minIntervalMs: 0) }
    }

    /// تشخيص على الجهاز: يخبرك هل حُمّلت Apple80211، وهل نجح المسح،
    /// وما أسماء المفاتيح الفعلية في نتائج المسح على إصدار iOS عندك.
    func probe() -> String {
        if let jb = backend as? JailbreakWiFiBackend {
            return jb.probe()
        }
        return """
        الـ backend الحالي: \(backendName)
        لا يدعم probe — iOS الأصلي لا يوفّر مسح Wi-Fi ولا IEs إطلاقًا.
        الحل: جهاز مكسور الحماية (TrollStore/AppSync) أو راديو خارجي.
        """
    }

    // MARK: - Internal

    private func ingest(_ result: WiFiScanResult) {
        let facts = result.toRadioFacts()
        let rid = result.remoteIdLocation()

        let row = WiFiRow(
            id: result.bssid ?? result.ssid ?? UUID().uuidString,
            ssid: result.ssid,
            bssid: result.bssid,
            rssi: result.rssi,
            channel: result.channelResolved(),
            security: facts.security,
            vendorIeCount: facts.vendorIes.count,
            ridLat: rid.lat,
            ridLon: rid.lon,
            source: Self.describe(result.source)
        )

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            var map = [String: WiFiRow]()
            for r in self.rows { map[r.id] = r }
            map[row.id] = row
            self.rows = map.values.sorted { $0.rssi > $1.rssi }
        }
    }

    private static func describe(_ kind: WiFiBackendKind) -> String {
        switch kind {
        case .iOSNative: return "iOS الأصلي (بلا مسح)"
        case .jailbreakPrivate: return "Jailbreak / Apple80211"
        case .externalRadio: return "راديو خارجي"
        }
    }
}
