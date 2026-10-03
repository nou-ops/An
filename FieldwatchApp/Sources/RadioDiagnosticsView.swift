import SwiftUI
import CoreBluetooth
import UIKit
import FieldwatchCore

/// شاشة تشخيص الراديو (fix5).
/// الغرض: تُجيب على سؤال «لماذا لا تظهر رديوهات؟» من داخل التطبيق نفسه،
/// بلا تخمين: حالة النظام · إذن Bluetooth · عدّاد الإعلانات الواصلة · آخر خطوة.
struct RadioDiagnosticsView: View {
    @EnvironmentObject private var store: FieldwatchStore

    private var s: BleScanner { store.scanner }

    var body: some View {
        List {
            Section("الراديو") {
                row("حالة النظام", s.stateName)
                row("إذن Bluetooth", s.authorizationName)
                row("مسح جارٍ (تطبيقنا)", s.isScanning ? "نعم" : "لا")
                row("مسح جارٍ (النظام)", s.frameworkScanning ? "نعم" : "لا")
                row("iOS", s.iosVersion)
            }
            Section("العدّادات") {
                row("مرات بدء المسح", "\(s.scanStarts)")
                row("إعلانات وصلت (didDiscover)", "\(s.discoverCallbacks)")
                row("إعادات بناء تلقائية", "\(s.autoRestarts)")
                row("آخر إعلان", s.lastDiscoveryAgo)
                row("رديوهات محفوظة", "\(s.sightings.count)")
            }
            Section("آخر خطوة قام بها الماسح") {
                Text(s.lastNote.isEmpty ? "—" : s.lastNote).font(.footnote)
            }
            Section("إجراءات") {
                Button("إعادة بناء الراديو") { s.restartRadio() }
                Button(s.isScanning ? "إيقاف المسح" : "بدء المسح") {
                    if s.isScanning { s.stop() } else { s.start() }
                }
                Button("افتح إعدادات النظام") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
            Section("كيف تقرأ هذه الشاشة؟") {
                Text("• «إعلانات وصلت» = 0 بعد دقيقة ⇒ النظام لا يسلّم الإعلانات إلى التطبيق (غالبًا إذن Bluetooth أو صلاحيات التوقيع).")
                Text("• «إذن Bluetooth» = notDetermined ⇒ لم يظهر مربع الحوار أصلًا؛ افتح إعدادات النظام وامنح الإذن.")
                Text("• «إذن Bluetooth» = denied ⇒ أوقف «Screen Time → Content & Privacy → Bluetooth → Allow changes» ثم أعد المحاولة.")
                Text("• «مسح جارٍ (النظام)» = لا مع «تطبيقنا» = نعم ⇒ النداء قُبل لكن النظام لم يبدأ المسح فعلًا.")
            }.font(.footnote)
        }
        .navigationTitle("تشخيص الراديو")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospaced()
        }
    }
}
