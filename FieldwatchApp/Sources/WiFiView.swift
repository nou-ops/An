import SwiftUI
import FieldwatchCore

/// شاشة شبكات Wi‑Fi (fix6).
///
/// القاعدة التي لا تتغيّر: iOS **لا يسمح** لأي تطبيق عادي بمسح الشبكات المحيطة.
/// المسار الوحيد هو backend الـ jailbreak (Apple80211) — وهو موجود في التطبيق،
/// وهذه الشاشة تُظهر: أيّ backend عمل، وهل نجح المسح، وما المفاتيح التي رجعها
/// النظام على إصدار iOS عندك (probe)، ثم قائمة الشبكات نفسها.
struct WiFiView: View {
    @EnvironmentObject private var store: FieldwatchStore
    @State private var probeText: String?

    private var w: WiFiScanner { store.wifi }

    var body: some View {
        List {
            Section("الحالة") {
                row("المسار (backend)", w.backendName)
                row("قادر على مسح المحيط", w.isAvailable ? "نعم ✓" : "لا")
                row("إطار MobileWiFi", w.mobileWiFiPathLoaded ? "محمّل ✓" : "غير محمّل ✗")
                row("إطار Apple80211", w.applePathLoaded ? "محمّل ✓" : "غير محمّل ✗")
                row("مصدر آخر نتائج", w.activeSource)
                row("عدد المسحات", "\(w.totalScans)")
                row("آخر مسح", w.lastScanCount == 0 ? "—" : "\(w.lastScanCount) شبكة")
                row("شبكات محفوظة", "\(w.rows.count)")
                if !w.backendNote.isEmpty {
                    Text(w.backendNote).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("إجراءات") {
                Button("امسح الشبكات الآن") { w.scanOnce() }
                Button("تشخيص Wi‑Fi (probe)") { probeText = w.probe() }
            }

            if let probeText {
                Section("ناتج probe") {
                    Text(probeText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section("الشبكات المحيطة") {
                if w.rows.isEmpty {
                    Text(w.isAvailable
                         ? "لا نتائج بعد — اضغط «امسح الشبكات الآن» وانتظر ثانيتين."
                         : "لا يمكن مسح الشبكات: هذا الجهاز/التطبيق لا يملك مسار الـ jailbreak (Apple80211).")
                        .foregroundStyle(.secondary)
                }
                ForEach(w.rows) { r in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Image(systemName: "wifi")
                            Text(r.ssid ?? "(SSID مخفي)").font(.headline).lineLimit(1)
                            Spacer()
                            Text("\(r.rssi) dBm").monospacedDigit()
                        }
                        if let b = r.bssid { Text(b).font(.caption2).monospaced().foregroundStyle(.secondary) }
                        HStack(spacing: 10) {
                            if let ch = r.channel { Text("قناة \(ch)").font(.caption).foregroundStyle(.secondary) }
                            if let sec = r.security, !sec.isEmpty { Text(sec).font(.caption).foregroundStyle(.secondary) }
                            if r.vendorIeCount > 0 { Text("vendor IEs: \(r.vendorIeCount)").font(.caption).foregroundStyle(.blue) }
                        }
                        if let lat = r.ridLat, let lon = r.ridLon {
                            Text("Remote ID عبر Wi‑Fi: \(String(format: "%.5f, %.5f", lat, lon))")
                                .font(.caption).foregroundStyle(.green)
                        }
                    }.padding(.vertical, 2)
                }
            }

            Section("لماذا لا تظهر الشبكات عادة؟") {
                Text("iOS يمنع مسح الشبكات المحيطة في التطبيقات العادية (بخلاف أندرويد). لذلك مسار Wi‑Fi في Fieldwatch يعمل فقط على جهاز مكسور الحماية عبر إطار Apple80211 الخاص.")
                Text("إن ظهر «قادر على مسح المحيط: لا» فجرّب نسخة IPA الموقّعة بصلاحيات platform (اسمها Fieldwatch-trollstore-platform.ipa) — فهي التي تمنح الوصول لهذا الإطار.")
            }.font(.footnote)
        }
        .navigationTitle("شبكات Wi‑Fi")
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).monospaced()
        }
    }
}
