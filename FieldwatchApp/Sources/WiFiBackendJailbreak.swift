//
//  WiFiBackendJailbreak.swift
//  Fieldwatch (target التطبيق)
//
//  JailbreakBackend — مسح Wi-Fi حقيقي عبر أطر آبل الخاصة. مسارَان:
//
//    1) MobileWiFi  ← **المسار الحديث والصحيح**.
//       إطار MobileWiFi هو الواجهة الفعلية لإدارة الـ Wi-Fi في iOS الحديث،
//       وهو الذي يستعمله SpringBoard وشاشة الإعدادات. دالته الأساسية
//       WiFiManagerClientCreate، والمسح عبر WiFiDeviceClientScanAsync.
//       ويشترط: صلاحية `com.apple.wifi.manager-access` — يتحقق منها wifid نفسه
//       بـ SecTaskCopyValueForEntitlement. لذلك أُضيفت إلى ملفات الصلاحيات.
//
//    2) Apple80211  ← مسار قديم (احتياطي).
//       إطار مهجور استُبدل بـ MobileWiFi. لكن نتائج مسحه ترجع **IE خام**
//       (بيت القصيد لـ Remote ID عبر Wi-Fi)، لذلك نُبقيه: إن نجح فهو الأفضل.
//
//  قواعد ملف الـ handoff التي يلتزم بها هذا الملف:
//    • معزول تمامًا خلف WiFiBackend (لا يعرف بقية التطبيق أنه موجود).
//    • لا يُقدَّم كحل مستقر: الرموز والمفاتيح تختلف بين إصدارات iOS.
//    • كل تحميل رموز بـ dlopen، وفشل هادئ (isAvailable = false) بدل إسقاط التطبيق.
//
//  التشخيص على الجهاز: probe() يطبع أي مسار حُمّل، أي رموز وُجدت، وما المفاتيح
//  الفعلية التي رجعت من أول نتيجة مسح — لأن هذا هو ما لا يمكن تخمينه من بعيد.
//

import Foundation
import Darwin

/// ردّ MobileWiFi غير المتزامن — على نطاق الملف لأن دالة C لا تلتقط شيئًا.
typealias MobileWiFiScanCallback = @convention(c) (UnsafeMutableRawPointer?, CFArray?, CFError?, UnsafeMutableRawPointer?) -> Void

final class JailbreakWiFiBackend: WiFiBackend {

    let kind: WiFiBackendKind = .jailbreakPrivate

    var onObservation: ((WiFiScanResult) -> Void)?
    var onScanFinished: ((Int, Bool) -> Void)?

    // MARK: - توقيعات Apple80211

    private typealias OpenFn  = @convention(c) (UnsafeMutablePointer<UnsafeMutableRawPointer?>?) -> Int32
    private typealias BindFn  = @convention(c) (UnsafeMutableRawPointer?, NSString) -> Int32
    private typealias ScanFn  = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutablePointer<Unmanaged<CFArray>?>?, CFDictionary?) -> Int32
    private typealias CloseFn = @convention(c) (UnsafeMutableRawPointer?) -> Int32

    // MARK: - توقيعات MobileWiFi

    private typealias MgrCreateFn    = @convention(c) (CFAllocator?, Int32) -> UnsafeMutableRawPointer?
    private typealias CopyDevicesFn  = @convention(c) (UnsafeMutableRawPointer?) -> CFArray?
    private typealias ScheduleFn     = @convention(c) (UnsafeMutableRawPointer?, CFRunLoop?, CFString?) -> Void
    private typealias ScanAsyncFn    = @convention(c) (UnsafeMutableRawPointer?, CFDictionary?, MobileWiFiScanCallback?, UnsafeMutableRawPointer?) -> Void
    private typealias NetStringFn    = @convention(c) (UnsafeMutableRawPointer?) -> CFString?
    private typealias NetPropFn      = @convention(c) (UnsafeMutableRawPointer?, CFString?) -> CFTypeRef?

    /// مسارات محتملة؛ نجرّبها بالترتيب ونتوقف عند أول نجاح.
    private static let apple80211Paths = [
        "/System/Library/PrivateFrameworks/Apple80211.framework/Apple80211",
        "/usr/lib/libApple80211.dylib",
    ]
    private static let mobileWiFiPaths = [
        "/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi",
        "/usr/lib/libMobileWiFi.dylib",
    ]

    /// en0 هو واجهة Wi-Fi على iPhone.
    private var interfaces: [String] = ["en0"]

    // Apple80211
    private var appleHandle: UnsafeMutableRawPointer?
    private var openFn: OpenFn?
    private var bindFn: BindFn?
    private var scanFn: ScanFn?
    private var closeFn: CloseFn?
    private(set) var appleLoaded = false
    private(set) var appleLoadedPath: String?

    // MobileWiFi
    private var mwHandle: UnsafeMutableRawPointer?
    private var mgrCreateFn: MgrCreateFn?
    private var copyDevicesFn: CopyDevicesFn?
    private var scheduleFn: ScheduleFn?
    private var scanAsyncFn: ScanAsyncFn?
    private var netSSIDFn: NetStringFn?
    private var netBSSIDFn: NetStringFn?
    private var netPropFn: NetPropFn?
    private(set) var mobileWiFiLoaded = false
    private(set) var mobileWiFiLoadedPath: String?
    private var manager: UnsafeMutableRawPointer?
    private var device: UnsafeMutableRawPointer?
    private var scanGeneration = 0

    private(set) var isAvailable: Bool = false
    private(set) var loadedPath: String?
    /// أي مسار أنتج آخر نتائج فعليًا: "Apple80211" أو "MobileWiFi".
    private(set) var activePath: String = "—"

    /// آخر مفاتيح ظهرت في نتيجة مسح — للتشخيص على الجهاز (probe).
    private(set) var lastResultKeys: [String] = []
    private(set) var lastNote: String = ""

    private var lastScanAt: Date = .distantPast
    private let scanLock = NSLock()

    // MARK: - Lifecycle

    init() {
        appleLoaded = loadApple80211()
        mobileWiFiLoaded = loadMobileWiFi()
        isAvailable = appleLoaded || mobileWiFiLoaded
        loadedPath = appleLoadedPath ?? mobileWiFiLoadedPath
    }

    deinit {
        if let appleHandle { dlclose(appleHandle) }
        if let mwHandle { dlclose(mwHandle) }
    }

    private func loadApple80211() -> Bool {
        if openFn != nil && scanFn != nil { return true }
        for path in Self.apple80211Paths {
            guard let h = dlopen(path, RTLD_LAZY) else { continue }
            guard
                let openSym = dlsym(h, "Apple80211Open"),
                let bindSym = dlsym(h, "Apple80211BindToInterface"),
                let scanSym = dlsym(h, "Apple80211Scan")
            else {
                dlclose(h)
                continue
            }
            appleHandle = h
            appleLoadedPath = path
            openFn = unsafeBitCast(openSym, to: OpenFn.self)
            bindFn = unsafeBitCast(bindSym, to: BindFn.self)
            scanFn = unsafeBitCast(scanSym, to: ScanFn.self)
            if let closeSym = dlsym(h, "Apple80211Close") {
                closeFn = unsafeBitCast(closeSym, to: CloseFn.self)
            }
            return true
        }
        return false
    }

    private func loadMobileWiFi() -> Bool {
        if mgrCreateFn != nil && scanAsyncFn != nil { return true }
        for path in Self.mobileWiFiPaths {
            guard let h = dlopen(path, RTLD_LAZY) else { continue }
            guard
                let createSym = dlsym(h, "WiFiManagerClientCreate"),
                let devicesSym = dlsym(h, "WiFiManagerClientCopyDevices"),
                let scanSym = dlsym(h, "WiFiDeviceClientScanAsync")
            else {
                dlclose(h)
                continue
            }
            mwHandle = h
            mobileWiFiLoadedPath = path
            mgrCreateFn = unsafeBitCast(createSym, to: MgrCreateFn.self)
            copyDevicesFn = unsafeBitCast(devicesSym, to: CopyDevicesFn.self)
            scanAsyncFn = unsafeBitCast(scanSym, to: ScanAsyncFn.self)
            if let s = dlsym(h, "WiFiManagerClientScheduleWithRunLoop") {
                scheduleFn = unsafeBitCast(s, to: ScheduleFn.self)
            }
            if let s = dlsym(h, "WiFiNetworkGetSSID")  { netSSIDFn  = unsafeBitCast(s, to: NetStringFn.self) }
            if let s = dlsym(h, "WiFiNetworkGetBSSID") { netBSSIDFn = unsafeBitCast(s, to: NetStringFn.self) }
            if let s = dlsym(h, "WiFiNetworkGetProperty") { netPropFn = unsafeBitCast(s, to: NetPropFn.self) }
            return true
        }
        return false
    }

    func start() { requestScan(minIntervalMs: 0) }

    func stop() { /* المسح متزامن/فوري، أو async مع رد واحد؛ لا شيء يتوقف */ }

    // MARK: - المسح

    func requestScan(minIntervalMs: Int) {
        scanLock.lock()
        defer { scanLock.unlock() }

        guard loadApple80211() || loadMobileWiFi() else {
            lastNote = "لا مسار: لم تُحمَّل أي مكتبة (Apple80211/MobileWiFi)"
            onScanFinished?(0, false)
            return
        }
        appleLoaded = (openFn != nil && scanFn != nil)
        mobileWiFiLoaded = (mgrCreateFn != nil && scanAsyncFn != nil)
        isAvailable = appleLoaded || mobileWiFiLoaded

        if minIntervalMs > 0 {
            let elapsed = Date().timeIntervalSince(lastScanAt) * 1000
            if elapsed < Double(minIntervalMs) {
                onScanFinished?(0, false)
                return
            }
        }
        lastScanAt = Date()

        // 1) Apple80211 أولًا: نتائجه تحمل IE خام (لازمة لـ Remote ID عبر Wi-Fi).
        if appleLoaded, let count = scanViaApple80211() {
            activePath = "Apple80211"
            onScanFinished?(count, true)
            if count > 0 { return }
        }

        // 2) MobileWiFi: المسار الحديث — يُشترط com.apple.wifi.manager-access.
        if mobileWiFiLoaded {
            scanViaMobileWiFi()
            return          // onScanFinished يأتي من الرد غير المتزامن
        }

        onScanFinished?(0, false)
    }

    /// يرجع عدد الشبكات، أو nil إن فشل المسح نفسه (لم يُنفَّذ).
    private func scanViaApple80211() -> Int? {
        guard let openFn, let bindFn, let scanFn else { return nil }

        var instance: UnsafeMutableRawPointer?
        guard openFn(&instance) == 0, let airport = instance else {
            lastNote = "Apple80211: فشل Apple80211Open (صلاحيات؟)"
            return nil
        }
        defer { _ = closeFn?(airport) }

        let bound = interfaces.first { bindFn(airport, $0 as NSString) == 0 }
        guard bound != nil else {
            lastNote = "Apple80211: فشل BindToInterface (en0)"
            return nil
        }

        var out: Unmanaged<CFArray>?
        let status = withUnsafeMutablePointer(to: &out) { ptr in
            scanFn(airport, ptr, nil as CFDictionary?)
        }
        guard status == 0, let cf = out?.takeUnretainedValue() else {
            lastNote = "Apple80211: فشل Scan (status=\(status)) — غالبًا صلاحية Wi-Fi"
            return nil
        }

        let rows = unsafeBitCast(cf, to: NSArray.self)
        var count = 0
        var keysLogged = false
        for row in rows {
            guard let dict = row as? [String: Any] else { continue }
            if !keysLogged { lastResultKeys = dict.keys.sorted(); keysLogged = true }
            guard let result = makeResult(dict) else { continue }
            count += 1
            onObservation?(result)
        }
        return count
    }

    private func scanViaMobileWiFi() {
        let run: () -> Void = { [weak self] in self?.performMobileWiFiScan() }
        if Thread.isMainThread { run() } else { DispatchQueue.main.async(execute: run) }
    }

    /// يجب أن يُنفَّذ على الخيط الرئيسي: نُجدول المدير على run loop الرئيسي.
    private func performMobileWiFiScan() {
        guard ensureMobileWiFiReady() else {
            lastNote = "MobileWiFi: تعذّر إنشاء المدير أو الجهاز (صلاحية com.apple.wifi.manager-access؟)"
            onScanFinished?(0, false)
            return
        }
        guard let device, let scanAsyncFn else {
            lastNote = "MobileWiFi: لا جهاز Wi-Fi (en0)"
            onScanFinished?(0, false)
            return
        }

        scanGeneration += 1
        let generation = scanGeneration
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        // قاموس فارغ = مسح كل القنوات — نفس ما ورد في الأمثلة المُثبتة لـ WiFiDeviceClientScanAsync.
        let params = [String: Any]() as CFDictionary
        scanAsyncFn(device, params, jailbreakWiFiScanCallback, ctx)

        // أمان: إن لم يرجع النظام أي رد خلال ٨ ثوانٍ نُعلن الفشل بدل أن ننتظر للأبد.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            guard let self, self.scanGeneration == generation, self.activePath != "MobileWiFi" else { return }
            self.lastNote = "MobileWiFi: لا رد من النظام خلال ٨ ثوانٍ (الصلاحية أو الـ daemon رفض الطلب)"
            self.onScanFinished?(0, false)
        }
    }

    private func ensureMobileWiFiReady() -> Bool {
        if manager != nil && device != nil { return true }
        guard let mgrCreateFn, let copyDevicesFn else { return false }

        guard let mgr = mgrCreateFn(kCFAllocatorDefault, 0) else {
            lastNote = "MobileWiFi: WiFiManagerClientCreate أرجع nil"
            return false
        }
        manager = mgr
        // ملاحظة (fix8): في SDK الحديث النوع CFRunLoopMode غلافٌ حول CFString،
        // فلا يُمرَّر مباشرة إلى مُعامل CFString؟ — نحوّله صراحةً كما اقترح مُصرِّف Xcode.
        scheduleFn?(mgr, CFRunLoopGetMain(), kCFRunLoopDefaultMode as! CFString)

        guard let devices = copyDevicesFn(mgr) else {
            lastNote = "MobileWiFi: CopyDevices أرجع nil"
            return false
        }
        let list = unsafeBitCast(devices, to: NSArray.self)
        guard let first = list.firstObject else {
            lastNote = "MobileWiFi: لا أجهزة Wi-Fi"
            return false
        }
        device = Unmanaged.passUnretained(first as AnyObject).toOpaque()
        return true
    }

    /// يُنادى من رد النظام غير المتزامن (على run loop الرئيسي).
    fileprivate func handleMobileWiFiResults(_ results: CFArray?, error: CFError?) {
        guard scanGeneration > 0 else { return }
        activePath = "MobileWiFi"
        scanGeneration += 1   // يُبطل مؤقّت الأمان

        var count = 0
        if let result = parseMobileWiFiResults(results) {
            count = result.count
            if lastResultKeys.isEmpty { lastResultKeys = result.keys }
            for row in result.rows { onObservation?(row) }
        }
        if let error {
            lastNote = "MobileWiFi: رد بخطأ — " + String(describing: error)
        } else if count == 0 {
            lastNote = "MobileWiFi: نجح الطلب لكن النظام أرجع صفر شبكات"
        } else {
            lastNote = "MobileWiFi: \(count) شبكة"
        }
        onScanFinished?(count, true)
    }

    private func parseMobileWiFiResults(_ results: CFArray?) -> (count: Int, keys: [String], rows: [WiFiScanResult])? {
        guard let results else { return nil }
        let list = unsafeBitCast(results, to: NSArray.self)
        var rows: [WiFiScanResult] = []
        var firstKeys: [String] = []

        for element in list {
            let net = Unmanaged.passUnretained(element as AnyObject).toOpaque()
            let ssid  = readString(net, netSSIDFn)
            let bssid = readString(net, netBSSIDFn)
            if ssid == nil && bssid == nil { continue }

            var rssi = 0
            for key in ["RSSI", "RSSI_CTL_AGR", "Signal"] {
                if let n = readProp(net, key) as? NSNumber { rssi = n.intValue; break }
            }
            var channel: Int?
            for key in ["CHANNEL", "CHANNEL_NUM"] {
                if let n = readProp(net, key) as? NSNumber { channel = n.intValue; break }
            }
            var blob: [UInt8]?
            for key in ["IE", "IES", "BSSID_IE", "BEACON_IE"] {
                if let d = readProp(net, key) as? Data, !d.isEmpty { blob = [UInt8](d); break }
            }
            var security: String?
            for key in ["SECURITY", "CAPABILITIES", "PRIVACY"] {
                if let s = readProp(net, key) as? String, !s.isEmpty { security = s; break }
            }
            if firstKeys.isEmpty { firstKeys = presentKeys(net) }

            rows.append(WiFiScanResult(
                bssid: bssid,
                ssid: ssid,
                rssi: rssi,
                channel: channel,
                ieBlob: blob,
                capabilities: security,
                source: .jailbreakPrivate
            ))
        }
        return (rows.count, firstKeys, rows)
    }

    private func readString(_ net: UnsafeMutableRawPointer?, _ fn: NetStringFn?) -> String? {
        guard let fn, let value = fn(net) else { return nil }
        let s = value as String
        return s.isEmpty ? nil : s
    }

    private func readProp(_ net: UnsafeMutableRawPointer?, _ key: String) -> CFTypeRef? {
        guard let netPropFn else { return nil }
        return netPropFn(net, key as CFString)
    }

    /// أي المفاتيح المرشّحة موجودة فعلًا في كائن الشبكة؟ (يُطبع في probe)
    private func presentKeys(_ net: UnsafeMutableRawPointer?) -> [String] {
        let candidates = ["SSID", "BSSID", "RSSI", "RSSI_CTL_AGR", "CHANNEL", "CHANNEL_NUM",
                          "IE", "IES", "BSSID_IE", "BEACON_IE", "SECURITY", "CAPABILITIES", "PRIVACY"]
        var found: [String] = []
        for key in candidates where readProp(net, key) != nil { found.append(key) }
        return found
    }

    // MARK: - تحويل نتيجة مسح Apple80211 إلى WiFiScanResult

    private func makeResult(_ dict: [String: Any]) -> WiFiScanResult? {
        let ssid = stringValue(dict, ["SSID", "ssid", "SSID_STR"])
        let bssid = stringValue(dict, ["BSSID", "bssid"])
        guard ssid != nil || bssid != nil else { return nil }

        let rssi = intValue(dict, ["RSSI", "rssi", "Signal", "signal"]) ?? 0
        let channel = intValue(dict, ["CHANNEL", "channel", "CHANNEL_NUM"])

        var blob: [UInt8]?
        if let data = dataValue(dict, ["IE", "ie", "IE_DATA", "informationElements"]) {
            blob = [UInt8](data)
        }

        return WiFiScanResult(
            bssid: bssid,
            ssid: ssid,
            rssi: rssi,
            channel: channel,
            ieBlob: blob,
            capabilities: stringValue(dict, ["CAPABILITIES", "capabilities", "PRIVACY"]),
            source: .jailbreakPrivate
        )
    }

    private func stringValue(_ dict: [String: Any], _ keys: [String]) -> String? {
        if let v = rawValue(dict, keys) as? String { return v }
        if let data = rawValue(dict, keys) as? Data { return String(decoding: data, as: UTF8.self) }
        return nil
    }

    private func intValue(_ dict: [String: Any], _ keys: [String]) -> Int? {
        if let n = rawValue(dict, keys) as? NSNumber { return n.intValue }
        if let i = rawValue(dict, keys) as? Int { return i }
        if let d = rawValue(dict, keys) as? Double { return Int(d) }
        return nil
    }

    private func dataValue(_ dict: [String: Any], _ keys: [String]) -> Data? {
        if let d = rawValue(dict, keys) as? Data { return d }
        return nil
    }

    private func rawValue(_ dict: [String: Any], _ keys: [String]) -> Any? {
        for k in keys { if let v = dict[k] { return v } }
        let lowered = keys.map { $0.lowercased() }
        for (k, v) in dict where lowered.contains(k.lowercased()) { return v }
        return nil
    }

    // MARK: - تشخيص على الجهاز

    /// شغّل هذا مرة واحدة على الجهاز وسجّل الناتج: أي مسار حُمّل، أي رموز وُجدت،
    /// وهل نجح المسح، وما أسماء المفاتيح الفعلية في النتائج على إصدار iOS عندك.
    func probe() -> String {
        var lines = [String]()
        lines.append("JailbreakWiFiBackend probe")
        lines.append("isAvailable: \(isAvailable)")
        lines.append("المسار الفعلي لآخر نتائج: \(activePath)")
        lines.append("Apple80211: \(appleLoaded ? "محمّل ✓" : "غير محمّل ✗") — \(appleLoadedPath ?? "لا مسار")")
        lines.append("MobileWiFi: \(mobileWiFiLoaded ? "محمّل ✓" : "غير محمّل ✗") — \(mobileWiFiLoadedPath ?? "لا مسار")")
        lines.append("رموز Apple80211: open=\(openFn != nil) bind=\(bindFn != nil) scan=\(scanFn != nil) close=\(closeFn != nil)")
        lines.append("رموز MobileWiFi: create=\(mgrCreateFn != nil) devices=\(copyDevicesFn != nil) scanAsync=\(scanAsyncFn != nil) schedule=\(scheduleFn != nil)")
        lines.append("رموز الشبكة: ssid=\(netSSIDFn != nil) bssid=\(netBSSIDFn != nil) prop=\(netPropFn != nil)")
        lines.append("آخر ملاحظة: \(lastNote.isEmpty ? "—" : lastNote)")

        var observed = 0
        let previous = onObservation
        onObservation = { _ in observed += 1 }
        requestScan(minIntervalMs: 0)
        onObservation = previous

        lines.append("شبكات رصدت في هذه المحاولة: \(observed)")
        if mobileWiFiLoaded {
            lines.append("ملاحظة: مسار MobileWiFi غير متزامن — عدّاد هذه المحاولة قد يكون 0؛")
            lines.append("        راقب «مصدر آخر نتائج» و«آخر ملاحظة» أعلى الصفحة بعد ثانيتين.")
        }
        lines.append("مفاتيح أول نتيجة: \(lastResultKeys.isEmpty ? "لا شيء — المسح لم يُرجع نتائج" : lastResultKeys.joined(separator: ", "))")
        return lines.joined(separator: "\n")
    }
}

// MARK: - رد MobileWiFi غير المتزامن (دالة C بلا التقاطات)

let jailbreakWiFiScanCallback: MobileWiFiScanCallback = { device, results, error, context in
    _ = device
    guard let context else { return }
    let backend = Unmanaged<JailbreakWiFiBackend>.fromOpaque(context).takeUnretainedValue()
    backend.handleMobileWiFiResults(results, error: error)
}
