import Foundation

public enum SitConstants {
    public static let nameMax = 40
    public static let radioCap = 6000
    public static let pathCap = 2000
    public static let closedCap = 10
    public static let trailCap = 40
    public static let pathMinM = 10.0
    public static let pathMinMs: Int64 = 5_000
    public static let format = "fieldwatch-sit"
    public static let formatVersion = 1
}

public enum Sit {
    public static func clipName(_ raw: String) -> String { String(raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ").prefix(SitConstants.nameMax)) }
    public static func resolveName(_ raw: String, _ at: Int64) -> String { let n = clipName(raw); return n.isEmpty ? Date(timeIntervalSince1970: Double(at)/1000).formatted(.dateTime.day().month(.abbreviated).hour().minute()) : n }
    public static func newId() -> String { UUID().uuidString }
    public static func pinned(_ device: Sighting, fleets: [Fleet], watchDeviceKeys: Set<String>, watchedFleetIds: Set<String>) -> Bool {
        device.payloadLat != nil && device.payloadLon != nil || device.fleetIds.contains { id in fleets.first(where: { $0.id == id })?.attentionNote.isEmpty == false } || watchDeviceKeys.contains(device.key) || !device.fleetIds.isDisjoint(with: watchedFleetIds)
    }
}

public struct SitSummary: Codable, Sendable, Equatable { public var id:String; public var name:String; public var startAt:Int64; public var endAt:Int64?; public var radioCount:Int; public var extraAttentionCount:Int; public var open:Bool { endAt == nil }; public init(id:String,name:String,startAt:Int64,endAt:Int64?=nil,radioCount:Int=0,extraAttentionCount:Int=0){self.id=id;self.name=name;self.startAt=startAt;self.endAt=endAt;self.radioCount=radioCount;self.extraAttentionCount=extraAttentionCount} }

public struct SitRadio: Codable, Sendable, Equatable {
    public var key:String; public var kind:RadioKind; public var mac:String; public var name:String; public var fleetIds:Set<String>; public var firstSeen:Int64; public var lastSeen:Int64; public var hitCount:Int; public var rssi:Int; public var rssiMin:Int; public var rssiMax:Int; public var channel:Int; public var frequencyMhz:Int; public var randomized:Bool; public var hiddenSsid:Bool; public var gone:Bool; public var extraAttention:Bool; public var payloadLat:Double?; public var payloadLon:Double?; public var payloadUasId:String?; public var payloadAlt:Double?; public var payloadHeading:Double?; public var payloadSpeed:Double?; public var payloadOpLat:Double?; public var payloadOpLon:Double?; public var payloadTrail:[PayloadFix]; public var gpsTrail:[GpsSample]; public var liveDecode:[LiveDecodeChip]
    public init(from d:Sighting, fleets:[Fleet]) { key=d.key;kind=d.kind;mac=d.mac;name=d.name;fleetIds=d.fleetIds;firstSeen=d.firstSeen;lastSeen=d.lastSeen;hitCount=d.hitCount;rssi=d.rssi;rssiMin=d.rssiMin;rssiMax=d.rssiMax;channel=d.channel;frequencyMhz=d.frequencyMhz;randomized=d.randomized;hiddenSsid=d.hiddenSsid;gone=d.gone;extraAttention = d.fleetIds.contains { id in fleets.first(where: { $0.id == id })?.attentionNote.isEmpty == false };payloadLat=d.payloadLat;payloadLon=d.payloadLon;payloadUasId=d.payloadUasId;payloadAlt=d.payloadAlt;payloadHeading=d.payloadHeading;payloadSpeed=d.payloadSpeed;payloadOpLat=d.payloadOpLat;payloadOpLon=d.payloadOpLon;payloadTrail=d.payloadTrail;gpsTrail=d.gpsTrail;liveDecode=d.liveDecode }
    public func toSighting() -> Sighting { Sighting(key:key,kind:kind,mac:mac,name:name,rssi:rssi,rssiMin:rssiMin,rssiMax:rssiMax,channel:channel,frequencyMhz:frequencyMhz,randomized:randomized,hiddenSsid:hiddenSsid,firstSeen:firstSeen,lastSeen:lastSeen,hitCount:hitCount,fleetIds:fleetIds,gone:gone,gpsTrail:gpsTrail,payloadLat:payloadLat,payloadLon:payloadLon,payloadAlt:payloadAlt,payloadOpLat:payloadOpLat,payloadOpLon:payloadOpLon,payloadUasId:payloadUasId,payloadHeading:payloadHeading,payloadSpeed:payloadSpeed,payloadTrail:payloadTrail,liveDecode:liveDecode) }
}

public struct SitFile: Codable, Sendable { public var format:String; public var formatVersion:Int; public var summary:SitSummary; public var radios:[SitRadio]; public var operatorPath:[GpsSample]; public init(summary:SitSummary,radios:[SitRadio]=[],operatorPath:[GpsSample]=[]){self.format=SitConstants.format;self.formatVersion=SitConstants.formatVersion;self.summary=summary;self.radios=radios;self.operatorPath=operatorPath} }

public final class SitSession: @unchecked Sendable {
    public private(set) var summary:SitSummary; private var radios:[String:SitRadio]; private var path:[GpsSample]; public private(set) var dirty=false
    public var radioCount:Int { radios.count }; public var atCap:Bool { radios.count >= SitConstants.radioCap }; public var operatorPath:[GpsSample] { path }
    public init(summary:SitSummary,radios:[SitRadio]=[],path:[GpsSample]=[]){self.summary=summary;self.radios=Dictionary(uniqueKeysWithValues:radios.map{($0.key,$0)});self.path=path}
    public static func start(name:String,now:Int64,heard:[Sighting],fleets:[Fleet],watchDeviceKeys:Set<String>=[],watchedFleetIds:Set<String>=[],id:String=Sit.newId())->SitSession { let s=SitSession(summary:SitSummary(id:id,name:Sit.resolveName(name,now),startAt:now)); heard.filter{!$0.gone}.forEach{_ = s.ingest($0,fleets:fleets,watchDeviceKeys:watchDeviceKeys,watchedFleetIds:watchedFleetIds)};s.dirty=true;return s }
    public func sightings()->[Sighting]{radios.values.map{$0.toSighting()}.sorted{$0.lastSeen > $1.lastSeen}}
    public func rename(_ raw:String)->Bool { guard summary.open else{return false}; let n=Sit.clipName(raw); guard !n.isEmpty,n != summary.name else{return false};summary.name=n;dirty=true;return true }
    public func ingest(_ d:Sighting,fleets:[Fleet],watchDeviceKeys:Set<String>,watchedFleetIds:Set<String>,tight:Bool=false)->Bool { guard summary.open else{return false}; if var old=radios[d.key] { old.name=d.name.isEmpty ? old.name:d.name;old.fleetIds.formUnion(d.fleetIds);old.firstSeen=min(old.firstSeen,d.firstSeen);old.lastSeen=max(old.lastSeen,d.lastSeen);old.hitCount=max(old.hitCount,d.hitCount);if Rssi.measured(d.rssi){old.rssi=d.rssi;old.rssiMin=Rssi.measured(old.rssiMin) ? min(old.rssiMin,d.rssi):d.rssi;old.rssiMax=Rssi.measured(old.rssiMax) ? max(old.rssiMax,d.rssi):d.rssi};old.gone=d.gone;old.extraAttention = old.extraAttention || d.fleetIds.contains { id in fleets.first(where: { $0.id == id })?.attentionNote.isEmpty == false };old.payloadLat=d.payloadLat ?? old.payloadLat;old.payloadLon=d.payloadLon ?? old.payloadLon;old.payloadUasId=d.payloadUasId ?? old.payloadUasId;old.payloadAlt=d.payloadAlt ?? old.payloadAlt;old.payloadHeading=d.payloadHeading ?? old.payloadHeading;old.payloadSpeed=d.payloadSpeed ?? old.payloadSpeed;old.payloadOpLat=d.payloadOpLat ?? old.payloadOpLat;old.payloadOpLon=d.payloadOpLon ?? old.payloadOpLon;old.payloadTrail=(old.payloadTrail + d.payloadTrail).suffix(SitConstants.trailCap).map{$0};old.gpsTrail=Array((old.gpsTrail+d.gpsTrail).suffix(SitConstants.trailCap));old.liveDecode=d.liveDecode.isEmpty ? old.liveDecode:d.liveDecode;radios[d.key]=old;dirty=true;return true }
        let pin=Sit.pinned(d,fleets:fleets,watchDeviceKeys:watchDeviceKeys,watchedFleetIds:watchedFleetIds); if (radios.count >= SitConstants.radioCap || tight) && !pin { evict(watchDeviceKeys:watchDeviceKeys,watchedFleetIds:watchedFleetIds); if radios.count >= SitConstants.radioCap || tight{return false} };radios[d.key]=SitRadio(from:d,fleets:fleets);dirty=true;return true }
    private func evict(watchDeviceKeys:Set<String>,watchedFleetIds:Set<String>){ while radios.count >= SitConstants.radioCap { guard let victim=radios.values.filter({!Sit.pinned($0.toSighting(),fleets:[],watchDeviceKeys:watchDeviceKeys,watchedFleetIds:watchedFleetIds)}).min(by:{$0.lastSeen < $1.lastSeen}) else {return};radios.removeValue(forKey:victim.key) } }
    public func recordPath(lat:Double,lon:Double,at:Int64)->Bool { guard summary.open else{return false};if let last=path.last { let d=Geo.meters(last.lat,last.lon,lat,lon);if d < SitConstants.pathMinM && at-last.at < SitConstants.pathMinMs {path[path.count-1]=GpsSample(at:at,lat:lat,lon:lon);dirty=true;return true} };path.append(GpsSample(at:at,lat:lat,lon:lon));if path.count>SitConstants.pathCap{path.removeFirst(path.count-SitConstants.pathCap)};dirty=true;return true }
    public func end(now:Int64,fleets:[Fleet])->SitFile {summary.endAt=now;dirty=true;return snapshot()}
    public func snapshot()->SitFile {summary.radioCount=radios.count;summary.extraAttentionCount=radios.values.filter{$0.extraAttention}.count;return SitFile(summary:summary,radios:Array(radios.values),operatorPath:path)}
    public func markClean(){dirty=false}
}
