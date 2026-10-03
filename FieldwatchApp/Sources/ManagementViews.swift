import SwiftUI
import FieldwatchCore

struct FiltersView: View {
    @EnvironmentObject private var store: FieldwatchStore
    var body: some View {
        Form {
            Section("Radio") {
                Toggle("Wi‑Fi", isOn: $store.filter.showWifi)
                Toggle("BLE", isOn: $store.filter.showBle)
                Toggle("Watched only", isOn: $store.filter.watchedOnly)
                Toggle("Named radios only", isOn: $store.filter.namedOnly)
                Toggle("Hide Fast Pair account keys", isOn: $store.filter.hideFastPairAccountKey)
            }
            Section("Signal") {
                Picker("Minimum RSSI", selection: $store.filter.rssiMin) { ForEach([-100,-90,-80,-70,-60,-50], id: \.self) { Text("\($0) dBm").tag($0) } }
                TextField("Name", text: $store.filter.nameQuery)
                TextField("OUI / prefix", text: $store.filter.ouiQuery)
            }
            Section("Classes") {
                Toggle("Enable class filter", isOn: $store.filter.useClassFilter)
                ForEach(SignatureClass.allCases, id: \.self) { c in
                    Toggle(c.label(), isOn: Binding(get: { store.filter.classes.contains(c) }, set: { on in if on { store.filter.classes.insert(c) } else { store.filter.classes.remove(c) } }))
                }
            }
        }.navigationTitle("Filters")
    }
}

struct FleetsView: View {
    @EnvironmentObject private var store: FieldwatchStore
    var body: some View {
        List {
            Section("Catalog") {
                ForEach(store.fleets, id: \.id) { f in
                    VStack(alignment: .leading) {
                        HStack { Text(f.name).font(.headline); Spacer(); if f.builtIn { Text("built-in").font(.caption).foregroundStyle(.secondary) } }
                        Text("\(f.kind.label()) • \(f.rules.count) rules").font(.caption).foregroundStyle(.secondary)
                    }.swipeActions { if !f.builtIn { Button(role: .destructive) { store.deleteCustomFleet(f.id) } label: { Label("Delete", systemImage: "trash") } } }
                }
            }
        }.navigationTitle("Signatures")
    }
}

struct DecodeFieldsView: View {
    @EnvironmentObject private var store: FieldwatchStore
    let device: FieldwatchCore.Sighting
    var body: some View {
        List {
            let values = SignatureFieldDecoder.decodeSighting(device, fleets: store.fleets)
            if values.isEmpty { Text("No catalog decode fields are available for this sighting.").foregroundStyle(.secondary) }
            ForEach(values, id: \.id) { v in
                VStack(alignment: .leading) { Text(v.label).font(.headline); Text(v.display).font(.system(.body, design: .monospaced)); if !v.note.isEmpty { Text(v.note).font(.caption).foregroundStyle(.secondary) } }
            }
        }.navigationTitle("Decoded fields")
    }
}

struct BookmarksView: View {
    @EnvironmentObject private var store: FieldwatchStore
    var body: some View {
        List {
            ForEach(store.scanner.sightings.filter { store.watchedKeys.contains($0.id) }, id: \.id) { row in
                HStack { Image(systemName: "bookmark.fill"); VStack(alignment: .leading) { Text(store.customNames[row.id] ?? row.name ?? "Unnamed"); Text(row.id).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text("\(row.rssi) dBm") }
            }
            if store.watchedKeys.isEmpty { Text("No bookmarked radios.").foregroundStyle(.secondary) }
        }.navigationTitle("Radio bookmarks")
    }
}

struct HuntView: View {
    @EnvironmentObject private var store: FieldwatchStore
    var body: some View {
        List {
            Section("Hunt") {
                Text("Select a watched radio in Live and move toward stronger RSSI.")
                ForEach(store.visibleSightings.filter { store.watchedKeys.contains($0.key) }, id: \.key) { d in
                    HStack { Image(systemName: "scope"); Text(d.displayName); Spacer(); Text("\(d.rssi) dBm").monospacedDigit() }
                }
            }
            Section("Platform note") { Text("Direction finding is not available from ordinary CoreBluetooth RSSI. This screen provides the same hunt workflow without inventing a bearing that iOS does not expose.").font(.footnote) }
        }.navigationTitle("Hunt")
    }
}
