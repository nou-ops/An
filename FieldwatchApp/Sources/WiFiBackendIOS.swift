//
//  WiFiBackendIOS.swift
//  Fieldwatch (target التطبيق)
//
//  iOSNativeBackend — ما تسمح به آبل رسميًا، بلا jailbreak.
//
//  الحقيقة التي يجب أن تكون واضحة في الواجهة: هذا الـ backend
//    • لا يمسح المحيط إطلاقًا (لا ScanResult ولا IEs)،
//    • يعطي الشبكة المتصلة بها فقط (SSID/BSSID) وبشروط صلاحية،
//    • بلا RSSI وبلا قناة.
//  أي أن Wi-Fi في Fieldwatch على iOS = إما Jailbreak أو راديو خارجي.
//

import Foundation
import SystemConfiguration.CaptiveNetwork

final class iOSNativeWiFiBackend: WiFiBackend {

    let kind: WiFiBackendKind = .iOSNative

    var onObservation: ((WiFiScanResult) -> Void)?
    var onScanFinished: ((Int, Bool) -> Void)?

    /// متاح دائمًا — لكنه لا يعني أن هناك مسحًا؛ فقط معلومات الشبكة الحالية.
    var isAvailable: Bool { true }

    func start() { requestScan(minIntervalMs: 0) }
    func stop() {}

    func requestScan(minIntervalMs: Int) {
        var count = 0

        // CNCopyCurrentNetworkInfo: يحتاج إذن الموقع (وعلى iOS 13+ قد يعطي BSSID/Prefix مع entitlement خاص).
        if let interfaces = CNCopySupportedInterfaces() as? [String] {
            for name in interfaces {
                guard
                    let info = CNCopyCurrentNetworkInfo(name as CFString) as? [String: Any]
                else { continue }

                let ssid = info[kCNNetworkInfoKeySSID as String] as? String
                let bssid = info[kCNNetworkInfoKeyBSSID as String] as? String
                if ssid == nil && bssid == nil { continue }

                count += 1
                onObservation?(WiFiScanResult(
                    bssid: bssid,
                    ssid: ssid,
                    rssi: 0,            // غير متاح على iOS بلا private API
                    channel: nil,       // غير متاح
                    ieBlob: nil,        // لا IEs إطلاقًا — لذلك لا Remote ID عبر Wi-Fi
                    capabilities: nil,
                    source: .iOSNative
                ))
            }
        }

        // fresh = false: هذه ليست نتائج مسح جديدة، بل حالة الشبكة الحالية.
        onScanFinished?(count, false)
    }
}
