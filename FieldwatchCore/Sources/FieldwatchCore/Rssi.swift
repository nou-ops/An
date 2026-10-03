//
//  Rssi.swift
//  FieldwatchCore
//
//  نقل 1:1 لـ Rssi.kt (الخطوة B في خطة النقل).
//

import Foundation

/// BLE/Wi-Fi RSSI كما استقبله هذا الهاتف (dBm). البلوتوث يستعمل 127
/// لـ "غير متاح" — وهذا ليس قدرة إرسال وليس استقبالًا حقيقيًا.
public enum Rssi {

    public static func measured(_ rssi: Int) -> Bool {
        (-127...126).contains(rssi)
    }

    public static func sessionRange(min lo: Int, max hi: Int, history: [RssiSample] = []) -> String {
        var vals = [Int]()
        vals.reserveCapacity(history.count + 2)
        if measured(lo) { vals.append(lo) }
        if measured(hi) { vals.append(hi) }
        for s in history where measured(s.rssi) { vals.append(s.rssi) }
        guard let low = vals.min(), let high = vals.max() else { return "Not available" }
        return low == high ? "\(low) dBm" : "\(low) to \(high) dBm"
    }

    public static func lastMeasured(rssi: Int, history: [RssiSample]) -> Int? {
        if measured(rssi) { return rssi }
        return history.reversed().first(where: { measured($0.rssi) })?.rssi
    }
}
