//
//  FastPair.swift
//  FieldwatchCore
//
//  الجزء المطلوب من FastPair.kt (البقية — جداول أسماء الطُرز — تُنقل مع الخطوة F).
//  ملاحظة NOTICE: أسماء طرز Fast Pair المترجَمة ليست مشمولة في منحة MIT الأصلية؛
//  ولذلك لم أُدرج أي جدول أسماء هنا.
//

import Foundation

public enum FastPair {

    public static let FLEET_ID = "fleet-fast-pair"

    /// Kotlin: isAccountKeyOnly — مفتاح حساب فقط: ليس وضع إقران، ومعرّف واحد فقط.
    public static func isAccountKeyOnly(_ device: Sighting) -> Bool {
        if device.fastPairPairing { return false }
        if !device.fleetIds.contains(FLEET_ID) { return false }
        return device.fleetIds.count == 1
    }

    public static func liveLabel(_ pairing: Bool) -> String {
        pairing ? "Fast Pair pairing" : "Fast Pair"
    }

    public static func isFastPairUuid(_ uuid: String) -> Bool {
        let hex = uuid.filter { $0.isLetter || $0.isNumber }.uppercased()
        return hex == "FE2C" || (hex.count >= 8 && String(hex.dropFirst(4).prefix(4)) == "FE2C")
    }
}
