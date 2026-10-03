import Foundation

public enum SitDiff {
    public struct Radio: Sendable, Equatable { public let key:String; public let kind:RadioKind; public let mac:String; public let name:String; public let fleetNames:[String]; public let randomized:Bool; public let firstSeen:Int64; public let lastSeen:Int64; public init(key:String,kind:RadioKind,mac:String,name:String,fleetNames:[String],randomized:Bool=false,firstSeen:Int64=0,lastSeen:Int64=0){self.key=key;self.kind=kind;self.mac=mac;self.name=name;self.fleetNames=fleetNames;self.randomized=randomized;self.firstSeen=firstSeen;self.lastSeen=lastSeen} }
    public struct Side: Sendable, Equatable { public let name:String; public let radios:[Radio]; public init(name:String,radios:[Radio]){self.name=name;self.radios=radios}; public var keys:Set<String>{Set(radios.map(\.key))} }
    public struct Result: Sendable, Equatable { public let onlyLeft:[Radio]; public let onlyRight:[Radio]; public let common:[Radio]; public let leftName:String; public let rightName:String }
    public static func fromSighting(_ d:Sighting, fleets:[Fleet]) -> Radio { Radio(key:d.key,kind:d.kind,mac:d.mac,name:d.name.isEmpty ? d.mac : d.name,fleetNames:d.fleetIds.compactMap { id in fleets.first(where: { $0.id == id })?.name },randomized:d.randomized,firstSeen:d.firstSeen,lastSeen:d.lastSeen) }
    public static func compare(_ left:Side,_ right:Side)->Result { let l=Dictionary(uniqueKeysWithValues:left.radios.map{($0.key,$0)}); let r=Dictionary(uniqueKeysWithValues:right.radios.map{($0.key,$0)}); return Result(onlyLeft:left.radios.filter{r[$0.key]==nil},onlyRight:right.radios.filter{l[$0.key]==nil},common:left.radios.filter{r[$0.key] != nil},leftName:left.name,rightName:right.name) }
}
