//
//  RadarPlot.swift
//  FieldwatchCore
//
//  نقل 1:1 لـ RadarPlot.kt — نصف القطر القطبي في الرادار الكلاسيكي.
//  الإشارة الأقوى أقرب إليك. [zoom] > 1 يمدّ الرسم فيتشتّت القوي وتخرج
//  الضعيفة من القرص. الزاوية ليست جزءًا من هذا التحويل.
//

import Foundation

public enum RadarPlot {

    public static let MIN_ZOOM: Float = 1
    public static let MAX_ZOOM: Float = 4

    public static func clampZoom(_ zoom: Float) -> Float {
        min(max(zoom, MIN_ZOOM), MAX_ZOOM)
    }

    public static func radius(_ rssi: Int, maxR: Float, zoom: Float = 1) -> Float {
        let t = min(max(Float(-30 - rssi) / 70, 0), 1)
        return maxR * (0.12 + t * 0.88) * clampZoom(zoom)
    }

    public static func onDisc(_ rssi: Int, maxR: Float, zoom: Float) -> Bool {
        radius(rssi, maxR: maxR, zoom: zoom) <= maxR + 0.5
    }
}
