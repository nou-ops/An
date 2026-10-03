//
//  FilterEngine.swift
//  FieldwatchCore
//
//  نقل 1:1 لـ FilterEngine.kt — بوابات التصفية الحية بنفس ترتيب Kotlin ونفس منطق AND/OR.
//

import Foundation

public final class FilterEngine {

    public init() {}

    public func pass(
        _ device: Sighting,
        _ filter: FilterState,
        travel: CoTravel.Ctx = .none,
        now: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        classByFleetId: [String: SignatureClass] = [:],
        namedRadioKeys: Set<String> = [],
        watchedFleetIds: Set<String> = [],
        alertDeviceKeys: Set<String> = []
    ) -> Bool {
        let named = !device.fleetIds.isEmpty
        let namedOk = filter.namedOnly ? named : true
        let customNamedOk = filter.customNamesOnly ? namedRadioKeys.contains(device.key) : true
        let watchedOk: Bool
        if !filter.watchedOnly {
            watchedOk = true
        } else {
            watchedOk = alertDeviceKeys.contains(device.key)
                || device.fleetIds.contains(where: { watchedFleetIds.contains($0) })
        }

        let typeOk: Bool
        switch device.kind {
        case .wifi: typeOk = filter.showWifi
        case .ble: typeOk = filter.showBle
        }

        let hideOk: Bool
        if filter.excludeSignatures && !filter.fleetIds.isEmpty {
            hideOk = !device.fleetIds.contains(where: { filter.fleetIds.contains($0) })
        } else {
            hideOk = true
        }

        let includeOk: Bool
        if !filter.includeSignatures || filter.includeFleetIds.isEmpty {
            includeOk = true
        } else {
            includeOk = device.fleetIds.contains(where: { filter.includeFleetIds.contains($0) })
        }

        let deviceClasses = Set(device.fleetIds.compactMap { classByFleetId[$0] })

        let hideClassOk: Bool
        if filter.excludeClasses && !filter.classes.isEmpty {
            hideClassOk = !deviceClasses.contains(where: { filter.classes.contains($0) })
        } else {
            hideClassOk = true
        }

        let includeClassOk: Bool
        if !filter.useClassFilter || filter.excludeClasses || filter.classes.isEmpty {
            includeClassOk = true
        } else {
            includeClassOk = deviceClasses.contains(where: { filter.classes.contains($0) })
        }

        let rssiOk = device.rssi >= filter.rssiMin
        let nameOk = filter.nameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || TextMatch.contains(device.name, filter.nameQuery)
            || TextMatch.contains(device.mac, filter.nameQuery)
        let ouiOk = filter.ouiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || TextMatch.contains(device.mac, filter.ouiQuery)
            || (device.vendor != nil && TextMatch.contains(device.vendor!, filter.ouiQuery))

        let gates: Bool
        if filter.logic == .and {
            gates = namedOk && customNamedOk && watchedOk && typeOk && hideOk && includeOk
                && hideClassOk && includeClassOk && rssiOk && nameOk && ouiOk
        } else {
            var optional = [Bool]()
            if filter.includeSignatures { optional.append(includeOk) }
            if filter.useClassFilter && !filter.excludeClasses { optional.append(includeClassOk) }
            if !filter.nameQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                optional.append(nameOk)
            }
            if !filter.ouiQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                optional.append(ouiOk)
            }
            if filter.rssiMin > -100 { optional.append(rssiOk) }
            let any = optional.isEmpty ? true : optional.contains(true)
            gates = namedOk && customNamedOk && watchedOk && typeOk && hideOk && hideClassOk && any
        }

        if !gates { return false }
        if filter.hideFastPairAccountKey && FastPair.isAccountKeyOnly(device) { return false }
        if !filter.movingWithYou { return true }
        return CoTravel.withYou(device, travel, now: now)
    }

    /// Kotlin: defaultPresets(fleets) — البارامتر `fleets` غير مستخدَم في Kotlin أيضًا
    /// (مُعلَّم بـ UNUSED_PARAMETER)، لذا أُسقط هنا بنفس الدلالة.
    public func defaultPresets() -> [FilterPreset] {
        [
            FilterPreset(id: "all", name: "All traffic", filter: FilterState()),
            FilterPreset(id: "wifi", name: "Wi-Fi only", filter: FilterState(showBle: false)),
            FilterPreset(id: "ble", name: "BLE only", filter: FilterState(showWifi: false)),
            FilterPreset(id: "strong", name: "Strong signal", filter: FilterState(rssiMin: -70)),
            FilterPreset(id: "with-you", name: "Moving with you",
                         filter: FilterState(showWifi: false, movingWithYou: true)),
            FilterPreset(id: "watched", name: "Watched only",
                         filter: FilterState(watchedOnly: true)),
        ]
    }
}

extension FilterState {
    /// مُنشئ مريح لقائمة القيم: يعكس استعمال Kotlin للأسماء المسماة في `FilterState(...)`.
    public init(
        namedOnly: Bool = false,
        customNamesOnly: Bool = false,
        watchedOnly: Bool = false,
        useFleetFilter: Bool = false,
        excludeSignatures: Bool = false,
        fleetIds: Set<String> = [],
        includeSignatures: Bool = false,
        includeFleetIds: Set<String> = [],
        showWifi: Bool = true,
        showBle: Bool = true,
        rssiMin: Int = -100,
        nameQuery: String = "",
        ouiQuery: String = "",
        logic: FilterLogic = .and,
        movingWithYou: Bool = false,
        arrivalsOnly: Bool = false,
        hideFastPairAccountKey: Bool = false,
        useClassFilter: Bool = false,
        excludeClasses: Bool = false,
        classes: Set<SignatureClass> = []
    ) {
        self.init()
        self.namedOnly = namedOnly
        self.customNamesOnly = customNamesOnly
        self.watchedOnly = watchedOnly
        self.useFleetFilter = useFleetFilter
        self.excludeSignatures = excludeSignatures
        self.fleetIds = fleetIds
        self.includeSignatures = includeSignatures
        self.includeFleetIds = includeFleetIds
        self.showWifi = showWifi
        self.showBle = showBle
        self.rssiMin = rssiMin
        self.nameQuery = nameQuery
        self.ouiQuery = ouiQuery
        self.logic = logic
        self.movingWithYou = movingWithYou
        self.arrivalsOnly = arrivalsOnly
        self.hideFastPairAccountKey = hideFastPairAccountKey
        self.useClassFilter = useClassFilter
        self.excludeClasses = excludeClasses
        self.classes = classes
    }
}
