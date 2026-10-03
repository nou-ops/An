import SwiftUI
import FieldwatchCore

struct RootView: View {
    @EnvironmentObject private var store: FieldwatchStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $store.selectedTab) {
            LiveView().tabItem { Label("Live", systemImage: "dot.radiowaves.left.and.right") }.tag(0)
            RadarView().tabItem { Label("Radar", systemImage: "scope") }.tag(1)
            CandidatesView().tabItem { Label("Candidates", systemImage: "person.3.sequence") }.tag(2)
            ReportsView().tabItem { Label("Reports", systemImage: "doc.text.magnifyingglass") }.tag(3)
            SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(4)
        }
        // عند العودة إلى التطبيق: أعِد التأكد من أن المسح يعمل (النظام قد يوقفه في الخلفية)
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                store.scanner.start()
                store.wifi.scanOnce()   // لا يفعل شيئًا إن لم يكن الـ backend قادرًا
            }
        }
    }
}

private struct RadarView: View {
    @EnvironmentObject private var store: FieldwatchStore
    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                HStack { metric("Visible", store.visibleSightings.count); metric("Watched", store.watchedKeys.count); metric("Signatures", store.fleets.count) }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.visibleSightings, id: \.key) { d in
                            HStack {
                                Circle().fill(d.rssi > -65 ? .green : d.rssi > -80 ? .orange : .gray).frame(width: 10, height: 10)
                                Text(d.displayName).lineLimit(1)
                                Spacer()
                                Text("\(d.rssi) dBm").monospacedDigit()
                            }.padding(.horizontal)
                        }
                    }
                }
            }.padding().navigationTitle("Radar")
        }
    }
    private func metric(_ title: String, _ value: Int) -> some View { VStack { Text("\(value)").font(.title2.bold().monospacedDigit()); Text(title).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
}

private struct CandidatesView: View {
    @EnvironmentObject private var store: FieldwatchStore
    var body: some View {
        NavigationStack {
            List {
                Section("Analysis") {
                    LabeledContent("Unique radios", value: "\(store.candidateReport.uniqueRadios)")
                    LabeledContent("Unmatched", value: "\(store.candidateReport.unmatchedRadios)")
                    LabeledContent("Families", value: "\(store.candidateReport.families.count)")
                }
                Section("Suggested families") {
                    if store.candidateReport.families.isEmpty { Text("No multi-radio family found yet.").foregroundStyle(.secondary) }
                    ForEach(store.candidateReport.families, id: \.id) { c in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(c.proposedName).font(.headline); Spacer(); Text("\(c.distinctRadios)").monospacedDigit() }
                            Text(c.ruleLabel).font(.caption).foregroundStyle(.secondary)
                            Text(c.why).font(.caption)
                            Button("Add to catalog") { store.addSuggestedFleet(c) }.buttonStyle(.bordered)
                        }
                    }
                }
            }.navigationTitle("Candidates")
        }
    }
}

private struct ReportsView: View {
    @EnvironmentObject private var store: FieldwatchStore
    @State private var sessionName = ""
    var body: some View {
        NavigationStack {
            List {
                Section("Current") {
                    LabeledContent("Visible radios", value: "\(store.visibleSightings.count)")
                    LabeledContent("Catalog signatures", value: "\(store.fleets.count)")
                    ShareLink(item: store.exportCSV(), preview: SharePreview("Fieldwatch CSV")) { Label("Share CSV", systemImage: "square.and.arrow.up") }
                    ShareLink(item: store.exportJSONL(), preview: SharePreview("Fieldwatch JSONL")) { Label("Share JSONL", systemImage: "square.and.arrow.up") }
                }
                Section("SIT session") {
                    TextField("Session name (optional)", text: $sessionName)
                    if store.session == nil {
                        Button("Start session") { store.sessionName = sessionName; store.createSession(); sessionName = "" }
                    } else {
                        Text("Recording \(store.session?.radioCount ?? 0) radios")
                        Button("Finish session") { _ = store.endSession() }
                    }
                }
            }.navigationTitle("Reports")
        }
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var store: FieldwatchStore
    var body: some View {
        NavigationStack {
            Form {
                Section("Bluetooth") {
                    Text(store.bluetoothState)
                    Toggle("Show BLE", isOn: Binding(get: { store.filter.showBle }, set: { store.filter.showBle = $0 }))
                    Toggle("Watched only", isOn: Binding(get: { store.filter.watchedOnly }, set: { store.filter.watchedOnly = $0 }))
                    Toggle("Hide Fast Pair account keys", isOn: Binding(get: { store.filter.hideFastPairAccountKey }, set: { store.filter.hideFastPairAccountKey = $0 }))
                }
                Section("Signal") {
                    Picker("Minimum RSSI", selection: Binding(get: { store.filter.rssiMin }, set: { store.filter.rssiMin = $0 })) {
                        ForEach([-100,-90,-80,-70,-60,-50], id: \.self) { Text("\($0) dBm").tag($0) }
                    }
                    TextField("Name contains", text: Binding(get: { store.filter.nameQuery }, set: { store.filter.nameQuery = $0 }))
                    TextField("OUI / prefix", text: Binding(get: { store.filter.ouiQuery }, set: { store.filter.ouiQuery = $0 }))
                }
                Section("Tools") {
                    NavigationLink("Filters") { FiltersView() }
                    NavigationLink("Signatures / Fleets") { FleetsView() }
                    NavigationLink("Radio bookmarks") { BookmarksView() }
                    NavigationLink("Hunt") { HuntView() }
                    NavigationLink("شبكات Wi‑Fi (المحيط)") { WiFiView() }
                    NavigationLink("تشخيص الراديو (Bluetooth)") { RadioDiagnosticsView() }
                }
                Section("Data") {
                    Text("Signature catalog: \(store.fleets.count) entries")
                    Text("Custom names: \(store.customNames.count)")
                    Text("Watched radios: \(store.watchedKeys.count)")
                }
                Section("Platform") {
                    Text("BLE uses CoreBluetooth. Wi‑Fi scanning requires the experimental jailbreak backend; normal iOS does not expose surrounding AP/IE scanning.").font(.footnote)
                }
            }.navigationTitle("Settings")
        }
    }
}
