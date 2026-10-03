import SwiftUI
import FieldwatchCore

struct LiveView: View {
    @EnvironmentObject private var store: FieldwatchStore
    @State private var search = ""
    @State private var selected: FieldwatchCore.Sighting?

    private var rows: [FieldwatchCore.Sighting] {
        let base = store.visibleSightings
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return base }
        return base.filter { TextMatch.contains($0.displayName, search) || TextMatch.contains($0.mac, search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(store.bluetoothState).font(.headline)
                            Text("\(rows.count) visible / \(store.scanner.sightings.count) heard")
                                .font(.caption).foregroundStyle(.secondary)
                            // سطر تشخيص مختصر (fix5): يكفي لمعرفة مكان توقف الأنبوب
                            Text("state=\(store.scanner.stateName) · auth=\(store.scanner.authorizationName) · scan#\(store.scanner.scanStarts) · callbacks=\(store.scanner.discoverCallbacks) · iOS \(store.scanner.iosVersion)")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            // حالة Wi-Fi: هل الـ backend قادر؟ وكم شبكة رآها آخر مسح؟
                            Text("wifi: \(store.wifi.isAvailable ? "قادر" : "غير متاح") · src=\(store.wifi.activeSource) · last=\(store.wifi.lastScanCount) · scans=\(store.wifi.totalScans)")
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Button(store.scanner.isScanning ? "Stop" : "Start") {
                            store.scanner.isScanning ? store.scanner.stop() : store.scanner.start()
                        }.buttonStyle(.borderedProminent)
                    }
                }
                Section {
                    ForEach(rows, id: \.key) { d in
                        Button { selected = d } label: { DeviceRow(device: d, watched: store.watchedKeys.contains(d.key)) }
                            .buttonStyle(.plain)
                    }
                } header: { Text("Live radios") }
            }
            .searchable(text: $search, prompt: "Name or identifier")
            .navigationTitle("Fieldwatch")
            .sheet(item: $selected) { DeviceDetailView(device: $0) }
            // إن لم يكن المسح جاريًا عند فتح الشاشة، ابدأه (بجانب بدءه تلقائيًا عند poweredOn)
            .onAppear { store.scanner.start() }
        }
    }
}

private struct DeviceRow: View {
    let device: FieldwatchCore.Sighting
    let watched: Bool
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: device.kind == .ble ? "dot.radiowaves.left.and.right" : "wifi")
                .foregroundStyle(device.rssi > -70 ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(device.displayName).font(.headline).lineLimit(1)
                Text(device.mac).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if !device.fleetIds.isEmpty { Text(device.fleetIds.count == 1 ? "1 signature" : "\(device.fleetIds.count) signatures").font(.caption).foregroundStyle(.blue) }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text("\(device.rssi) dBm").monospacedDigit()
                if watched { Image(systemName: "eye.fill").font(.caption).foregroundStyle(.orange) }
            }
        }.padding(.vertical, 4)
    }
}

private struct DeviceDetailView: View, Identifiable {
    let device: FieldwatchCore.Sighting
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: FieldwatchStore
    @State private var name = ""
    var id: String { device.key }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    LabeledContent("Name", value: device.displayName)
                    LabeledContent("Identifier", value: device.mac)
                    LabeledContent("Radio", value: device.kind.label())
                    LabeledContent("RSSI", value: "\(device.rssi) dBm")
                    if device.channel != 0 { LabeledContent("Channel", value: "\(device.channel)") }
                    Button(store.watchedKeys.contains(device.key) ? "Unwatch" : "Watch") { store.toggleWatch(device.key) }
                }
                Section("Custom name") {
                    TextField("Name", text: $name)
                    Button("Save name") { store.rename(device.key, name) }
                }
                Section("Payload") {
                    if let id = device.payloadUasId { LabeledContent("UAS ID", value: id) }
                    if let lat = device.payloadLat, let lon = device.payloadLon { LabeledContent("Position", value: String(format: "%.6f, %.6f", lat, lon)) }
                    if let alt = device.payloadAlt { LabeledContent("Altitude", value: String(format: "%.1f", alt)) }
                    if let speed = device.payloadSpeed { LabeledContent("Speed", value: String(format: "%.1f m/s", speed)) }
                    if device.payloadUasId == nil && device.payloadLat == nil { Text("No decoded Remote ID payload in this sighting.").foregroundStyle(.secondary) }
                }
                Section("Raw") {
                    Text(device.manufacturerDataHex.isEmpty ? "No manufacturer payload" : device.manufacturerDataHex).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    ForEach(device.serviceUuids, id: \.self) { Text("Service: \($0)").font(.caption).textSelection(.enabled) }
                }
            }
            .navigationTitle("Device")
            // iOS 16: ‏.topBarTrailing متاح من iOS 17 فقط ⇒ نستخدم navigationBarTrailing
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }.onAppear { name = store.customNames[device.key] ?? device.name }
    }
}
