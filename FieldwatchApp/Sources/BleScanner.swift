//
//  BleScanner.swift
//  Fieldwatch (target التطبيق — هنا حيث يُسمح بـ CoreBluetooth)
//
//  بديل BleRadio.kt: نفس المبدأ (تجميع Observation من إعلان BLE) لكن بـ CoreBluetooth.
//
//  قيود iOS التي يعالجها هذا الملف بصراحة:
//    • لا يوجد MAC address. iOS يعطي CBPeripheral.identifier — UUID خاص بهذا
//      التطبيق على هذا الجهاز — وللأجهزة ذات العنوان العشوائي يتغير الـ UUID.
//    • لا يمكن قراءة AD structure الخام؛ CoreBluetooth يفكّ الإعلان إلى قاموس،
//      فيُبنى RadioFacts من المفاتيح المتاحة: manufacturer data، service data،
//      txPower، flags. والـ raw IE parsing غير متاح هنا إطلاقًا.
//    • المسح في الخلفية مقيّد جدًا: UIBackgroundModes = bluetooth-central،
//      وبلا AllowDuplicates فعليًا، ومدة الجلسة تحدّدها آبل.
//

import Foundation
import CoreBluetooth
import FieldwatchCore

/// صف واحد في الواجهة الحية. الاسم `BleRow` مقصود: لا نُسمّيه Sighting حتى لا يحجب
/// `FieldwatchCore.Sighting` (نموذج النواة المنقول من Kotlin) داخل وحدة التطبيق.
struct BleRow: Identifiable, Hashable {
    let id: String          // CBPeripheral.identifier (ليس MAC)
    var name: String?
    var rssi: Int
    var serviceUUIDs: [String]
    var uasId: String?
    var lat: Double?
    var lon: Double?
    var heading: Double?
    var speed: Double?
    var altitude: Double?
    var lastSeen: Date
}

final class BleScanner: NSObject, ObservableObject {

    @Published private(set) var sightings: [BleRow] = []
    @Published private(set) var bluetoothState: CBManagerState = .unknown
    @Published private(set) var isScanning = false

    // ── عدّادات تشخيصية (fix5): تُجيب على «لماذا لا تظهر رديوهات؟» من شاشة الجهاز ──
    @Published private(set) var discoverCallbacks = 0    // كم إعلانًا سلّمه النظام (didDiscover)
    @Published private(set) var scanStarts = 0           // كم مرة أرسلنا scanForPeripherals
    @Published private(set) var autoRestarts = 0         // كم مرة أعدنا بناء الراديو تلقائيًا
    @Published private(set) var lastDiscoveryAt: Date?   // وقت آخر إعلان وصل
    @Published private(set) var lastNote = ""            // آخر خطوة قام بها الماسح

    private var central: CBCentralManager!
    private let queue = DispatchQueue(label: "app.fieldwatch.ble")
    private var byId: [String: BleRow] = [:]
    private var watchdog: DispatchWorkItem?

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: - تشخيص (يُعرض في الواجهة)

    var stateName: String {
        switch bluetoothState {
        case .poweredOn: return "poweredOn"
        case .poweredOff: return "poweredOff"
        case .unauthorized: return "unauthorized"
        case .unsupported: return "unsupported"
        case .resetting: return "resetting"
        case .unknown: return "unknown"
        @unknown default: return "?"
        }
    }

    /// إذن Bluetooth كما يراه النظام: allowedAlways / denied / restricted / notDetermined
    var authorizationName: String {
        switch CBManager.authorization {
        case .allowedAlways: return "allowedAlways"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "?"
        }
    }

    /// هل يعتبر النظام نفسه أنه يمسح الآن؟ (قد يخالف علمنا إن تجاهل النداء)
    var frameworkScanning: Bool { central?.isScanning ?? false }

    var iosVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    var lastDiscoveryAgo: String {
        guard let d = lastDiscoveryAt else { return "لا شيء بعد" }
        let secs = Int(Date().timeIntervalSince(d))
        return secs < 60 ? "قبل \(secs) ث" : "قبل \(secs / 60) د"
    }

    // MARK: - التحكم

    func start() {
        guard central.state == .poweredOn else {
            lastNote = "لم أبدأ: حالة النظام \(stateName)"
            return
        }
        guard !isScanning else { return }
        isScanning = true
        scanStarts += 1
        lastNote = "بدأت المسح (محاولة #\(scanStarts)) — إذن: \(authorizationName)"
        // AllowDuplicates = true هو ما يجعل التتبع الحي ممكنًا (مصدر حرارة/بطارية:
        // نفس ما تعرفه Fieldwatch على أندرويد في ScanSettings).
        central.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        armWatchdog()
    }

    /// إعادة بناء CBCentralManager من الصفر — عندما لا يصل أي إعلان إطلاقًا.
    func restartRadio() {
        watchdog?.cancel()
        lastNote = "إعادة بناء الراديو (محاولة #\(autoRestarts + 1))"
        central?.stopScan()
        isScanning = false
        byId.removeAll()
        sightings = []
        autoRestarts += 1
        central = CBCentralManager(delegate: self, queue: queue)
        // يُستأنف المسح من centralManagerDidUpdateState عند وصول poweredOn
    }

    /// إن بدأ المسح ولم يصل أي إعلان خلال ٦ ثوانٍ: أولًا بلا خيارات، ثم إعادة بناء المدير.
    private func armWatchdog() {
        watchdog?.cancel()
        let seen = discoverCallbacks
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning, self.discoverCallbacks == seen else { return }
            if self.autoRestarts >= 4 {
                self.lastNote = "توقفت المحاولات التلقائية (٤ مرات) — راجع إذن Bluetooth ثم اضغط «إعادة بناء الراديو»"
                return
            }
            if self.autoRestarts == 0 {
                self.autoRestarts += 1
                self.lastNote = "لا إعلانات — أُعيد المسح بلا خيارات"
                self.central.stopScan()
                self.central.scanForPeripherals(withServices: nil, options: nil)
            } else {
                self.restartRadio()
            }
            self.armWatchdog()
        }
        watchdog = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: item)
    }

    func stop() {
        guard isScanning else { return }
        watchdog?.cancel()
        central.stopScan()
        isScanning = false
        lastNote = "أوقفتُ المسح"
    }

    func clear() {
        byId.removeAll()
        sights { self.sightings = [] }
    }

    // MARK: - Internal

    private func sights(_ body: @escaping () -> Void) {
        DispatchQueue.main.async(execute: body)
    }

    /// بناء RadioFacts من advertisementData — نفس دور BleAdParser.kt لكن بالمفاتيح المتاحة على iOS.
    private func facts(from advertisementData: [String: Any]) -> RadioFacts {
        var facts = RadioFacts()

        if let tx = advertisementData[CBAdvertisementDataTxPowerLevelKey] as? NSNumber {
            facts.txPowerDbm = tx.intValue
        }
        if let connectable = advertisementData[CBAdvertisementDataIsConnectable] as? NSNumber {
            facts.connectable = connectable.boolValue
        }

        if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           mfg.count >= 2 {
            let companyId = Int(mfg[0]) | (Int(mfg[1]) << 8) // little-endian
            facts.mfgRecords = [
                MfgRecord(companyId: companyId, dataHex: mfg.dropFirst(2).fieldwatchHexUpper)
            ]
        }

        if let sd = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data] {
            facts.serviceData = sd.map { key, value in
                ServiceDataRecord(uuid: key.uuidString, dataHex: value.fieldwatchHexUpper)
            }
        }

        return facts
    }
}

extension BleScanner: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let state = central.state
        sights {
            self.bluetoothState = state
            self.lastNote = "حالة النظام: \(self.stateName) · إذن: \(self.authorizationName)"
        }
        if state == .poweredOn { start() } else { isScanning = false }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // العدّاد أولًا: إن وصل هذا السطر فهذا يعني أن النظام يسلّم الإعلانات فعلًا.
        discoverCallbacks += 1
        lastDiscoveryAt = Date()
        let facts = facts(from: advertisementData)
        // نفس مسار أندرويد: OpenDroneId.fromFacts على service data FFFA
        // (وعلى iOS لا يوجد vendor IE، لذا Wi-Fi Remote ID غير ممكن).
        let loc = OpenDroneId.fromFacts(facts)

        let id = peripheral.identifier.uuidString
        var row = byId[id] ?? BleRow(
            id: id,
            name: nil,
            rssi: RSSI.intValue,
            serviceUUIDs: [],
            uasId: nil,
            lat: nil,
            lon: nil,
            heading: nil,
            speed: nil,
            altitude: nil,
            lastSeen: Date()
        )

        row.name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? row.name
        row.rssi = RSSI.intValue
        row.lastSeen = Date()

        if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
            row.serviceUUIDs = uuids.map(\.uuidString)
        }
        if let uas = loc.uasId { row.uasId = uas }
        if let lat = loc.lat, let lon = loc.lon { row.lat = lat; row.lon = lon }
        if let h = loc.headingDeg { row.heading = h }
        if let s = loc.speedMps { row.speed = s }
        if let a = loc.alt { row.altitude = a }

        byId[id] = row
        let rows = Array(byId.values).sorted { $0.rssi > $1.rssi }
        sights { self.sightings = rows }
    }
}
