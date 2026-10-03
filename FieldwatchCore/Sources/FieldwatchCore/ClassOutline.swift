import Foundation

public struct SignatureSlice: Sendable, Equatable { public let fleetId: String; public let radios: [Sighting] }
public struct ClassSlice: Sendable, Equatable { public let kind: SignatureClass?; public let radios: [Sighting]; public let signatures: [SignatureSlice]; public var id: String { kind?.rawValue ?? "unmatched" }; public var label: String { kind?.label() ?? "Unmatched" } }
public struct OutlineReveal: Sendable, Equatable { public let classIds: Set<String>; public let sigKeys: Set<String> }

public enum ClassOutline {
    public static func of(_ devices: [Sighting], classByFleetId: [String:SignatureClass], nameByFleetId: [String:String] = [:]) -> [ClassSlice] {
        var buckets: [SignatureClass:[String:Set<String>]] = [:]
        var byKey: [String:Sighting] = [:]
        for d in devices { byKey[d.key] = d }
        var unmatched:[Sighting] = []
        for d in devices {
            if d.fleetIds.isEmpty { unmatched.append(d); continue }
            for id in d.fleetIds {
                let kind = (classByFleetId[id] ?? .other).folded()
                buckets[kind, default: [:]][id, default: []].insert(d.key)
            }
        }
        let kinds = SignatureClass.allCases.sorted { $0.label().localizedCaseInsensitiveCompare($1.label()) == .orderedAscending }
        var out:[ClassSlice] = kinds.map { kind in
            let sigs = (buckets[kind] ?? [:]).sorted { (nameByFleetId[$0.key] ?? $0.key).localizedCaseInsensitiveCompare(nameByFleetId[$1.key] ?? $1.key) == .orderedAscending }.map { SignatureSlice(fleetId: $0.key, radios: $0.value.compactMap { byKey[$0] }) }
            let keys = Set(sigs.flatMap { $0.radios.map(\.key) })
            return ClassSlice(kind: kind, radios: keys.compactMap { byKey[$0] }, signatures: sigs)
        }
        out.append(ClassSlice(kind: nil, radios: unmatched, signatures: []))
        return out
    }
    public static func multiClassCount(_ devices: [Sighting], classByFleetId: [String:SignatureClass]) -> Int { devices.filter { Set($0.fleetIds.compactMap { classByFleetId[$0]?.folded() }).count > 1 }.count }
    public static func reveal(_ device: Sighting, classByFleetId: [String:SignatureClass]) -> OutlineReveal {
        guard !device.fleetIds.isEmpty else { return OutlineReveal(classIds: ["unmatched"], sigKeys: []) }
        let classes = Set(device.fleetIds.map { (classByFleetId[$0] ?? .other).folded().rawValue })
        let sigs = Set(device.fleetIds.map { "\((classByFleetId[$0] ?? .other).folded().rawValue)/\($0)" })
        return OutlineReveal(classIds: classes, sigKeys: sigs)
    }
}
