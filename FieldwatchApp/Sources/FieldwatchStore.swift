import Foundation
import SwiftUI
import FieldwatchCore

@MainActor
final class FieldwatchStore: ObservableObject {
    let scanner = BleScanner()
    let wifi = WiFiScanner()
    let engine = SignatureEngine()

    @Published var fleets: [Fleet] = []
    @Published var filter = FilterState()
    @Published var watchedKeys: Set<String> = []
    @Published var customNames: [String:String] = [:]
    @Published var session: SitSession?
    @Published var sessionName = ""
    @Published var selectedTab = 0
    @Published var lastError: String?

    private var timer: Timer?
    private let defaults = UserDefaults.standard
    private let fleetsKey = "fieldwatch.custom.fleets"
    private let namesKey = "fieldwatch.custom.names"
    private let watchedKey = "fieldwatch.watched.keys"

    init() {
        fleets = SignatureCatalog.loadBundledOrEmpty()
        loadPersistence()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    deinit { timer?.invalidate() }

    var bluetoothState: String {
        switch scanner.bluetoothState {
        case .poweredOn: return "Bluetooth ready"
        case .poweredOff: return "Bluetooth off"
        case .unauthorized: return "Bluetooth permission denied"
        case .unsupported: return "Bluetooth unsupported"
        case .resetting: return "Bluetooth resetting"
        default: return "Bluetooth initializing"
        }
    }

    var coreSightings: [FieldwatchCore.Sighting] {
        bleSightings + wifiSightings
    }

    /// صفوف البلوتوث كما كانت.
    private var bleSightings: [FieldwatchCore.Sighting] {
        scanner.sightings.map { row in
            let name = customNames[row.id] ?? row.name ?? ""
            return FieldwatchCore.Sighting(
                key: row.id, kind: .ble, mac: row.id, name: name,
                rssi: row.rssi, rssiMin: row.rssi, rssiMax: row.rssi,
                serviceUuids: row.serviceUUIDs,
                firstSeen: Int64(row.lastSeen.timeIntervalSince1970 * 1000),
                lastSeen: Int64(row.lastSeen.timeIntervalSince1970 * 1000),
                hitCount: 1,
                fleetIds: [],
                payloadLat: row.lat, payloadLon: row.lon, payloadAlt: row.altitude,
                payloadHeading: row.heading, payloadSpeed: row.speed,
                liveDecode: []
            )
        }
    }

    /// شبكات Wi-Fi المحيطة — نفس مسار أندرويد: Sighting بنوع .wifi،
    /// المعرّف "WIFI:<BSSID أو SSID>"، والقناة من نتيجة المسح أو من عنصر DS.
    private var wifiSightings: [FieldwatchCore.Sighting] {
        wifi.rows.map { r in
            let ident = r.bssid ?? r.ssid ?? r.id
            let key = "WIFI:" + ident
            let name = customNames[key] ?? r.ssid ?? "(SSID مخفي)"
            let now = Int64(Date().timeIntervalSince1970 * 1000)
            return FieldwatchCore.Sighting(
                key: key, kind: .wifi, mac: ident, name: name,
                rssi: r.rssi, rssiMin: r.rssi, rssiMax: r.rssi,
                channel: r.channel ?? 0,
                firstSeen: now, lastSeen: now,
                hitCount: 1,
                fleetIds: [],
                payloadLat: r.ridLat, payloadLon: r.ridLon,
                liveDecode: []
            )
        }
    }

    var matched: [String:Set<String>] {
        Dictionary(uniqueKeysWithValues: engine.match(coreSightings, fleets: fleets).map { ($0.key, $0.value) })
    }

    var visibleSightings: [FieldwatchCore.Sighting] {
        let hits = matched
        let filtered = coreSightings.map { d -> FieldwatchCore.Sighting in
            var x = d
            x.fleetIds = hits[d.key] ?? []
            return x
        }
        let fe = FilterEngine()
        let classes = Dictionary(uniqueKeysWithValues: fleets.map { ($0.id, $0.kind) })
        return filtered.filter { fe.pass($0, filter, classByFleetId: classes, namedRadioKeys: Set(customNames.keys), watchedFleetIds: watchedFleetIds, alertDeviceKeys: watchedKeys) }
    }

    var candidateReport: CandidateReport {
        // الوسائط بأسمائها وترتيبها كما في مُهيّئ LogRadio (LogReplay.swift)
        let rows = coreSightings.map { LogRadio(
            kind: $0.kind, mac: $0.mac, name: $0.name, vendor: $0.vendor,
            manufacturerId: $0.manufacturerId, manufacturerDataHex: $0.manufacturerDataHex,
            serviceUuids: $0.serviceUuids, vendorIeOuis: $0.vendorIeOuis,
            randomized: $0.randomized, hiddenSsid: $0.hiddenSsid, rssi: $0.rssi,
            firstSeen: $0.firstSeen, lastSeen: $0.lastSeen, hits: $0.hitCount,
            channel: $0.channel, frequencyMhz: $0.frequencyMhz,
            latitude: $0.latitude, longitude: $0.longitude
        ) }
        return SignatureCandidates.analyze(rows, fleets: fleets, engine: engine, sourceLabel: "Live BLE")
    }

    func refresh() {
        wifi.periodicScan()   // لا تفعل شيئًا إن لم يكن الـ backend قادرًا (جهاز غير مكسور الحماية)
        let hits = matched
        for i in scanner.sightings.indices {
            let key = scanner.sightings[i].id
            _ = hits[key]
        }
        if let session {
            for d in coreSightings {
                var x = d
                x.fleetIds = hits[d.key] ?? []
                _ = session.ingest(x, fleets: fleets, watchDeviceKeys: watchedKeys, watchedFleetIds: watchedFleetIds)
            }
        }
        objectWillChange.send()
    }

    var watchedFleetIds: Set<String> { Set(fleets.filter { $0.attentionNote.isEmpty == false }.map(\.id)) }

    func toggleWatch(_ key: String) {
        if watchedKeys.contains(key) { watchedKeys.remove(key) } else { watchedKeys.insert(key) }
        savePersistence()
    }

    func rename(_ key: String, _ name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { customNames.removeValue(forKey: key) } else { customNames[key] = String(clean.prefix(64)) }
        savePersistence()
    }

    func createSession() {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        session = SitSession.start(name: sessionName, now: now, heard: visibleSightings,
                                   fleets: fleets, watchDeviceKeys: watchedKeys, watchedFleetIds: watchedFleetIds)
        sessionName = ""
    }

    func endSession() -> String? {
        guard let session else { return nil }
        let file = session.end(now: Int64(Date().timeIntervalSince1970 * 1000), fleets: fleets)
        self.session = nil
        guard let data = try? JSONEncoder().encode(file) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func exportCSV() -> String { SitExport.csv(visibleSightings, fleets: fleets) }
    func exportJSONL() -> String { SitExport.jsonl(visibleSightings, fleets: fleets) }

    func addSuggestedFleet(_ candidate: SignatureCandidate) {
        fleets.append(SignatureCandidates.suggestFleet(candidate))
        savePersistence()
    }

    func deleteCustomFleet(_ id: String) {
        guard let f = fleets.first(where: { $0.id == id }), !f.builtIn else { return }
        fleets.removeAll { $0.id == id }
        savePersistence()
    }

    private func loadPersistence() {
        if let data = defaults.data(forKey: fleetsKey), let saved = try? JSONDecoder().decode([Fleet].self, from: data) {
            fleets.append(contentsOf: saved.filter { !$0.builtIn })
        }
        if let data = defaults.data(forKey: namesKey), let saved = try? JSONDecoder().decode([String:String].self, from: data) { customNames = saved }
        if let data = defaults.data(forKey: watchedKey), let saved = try? JSONDecoder().decode(Set<String>.self, from: data) { watchedKeys = saved }
    }

    private func savePersistence() {
        let custom = fleets.filter { !$0.builtIn }
        defaults.set(try? JSONEncoder().encode(custom), forKey: fleetsKey)
        defaults.set(try? JSONEncoder().encode(customNames), forKey: namesKey)
        defaults.set(try? JSONEncoder().encode(watchedKeys), forKey: watchedKey)
    }
}

// MARK: - ملحقات العرض

