import Foundation

public struct SignaturePack: Codable, Sendable, Equatable { public let format:String; public let formatVersion:Int; public let exportedAt:String; public let appVersion:String; public let catalogVersion:Int; public let fleets:[Fleet]; public init(fleets:[Fleet],catalogVersion:Int=0,appVersion:String="1.1.17",exportedAt:String=ISO8601DateFormatter().string(from:Date())){self.format="fieldwatch-signatures";self.formatVersion=2;self.exportedAt=exportedAt;self.appVersion=appVersion;self.catalogVersion=catalogVersion;self.fleets=fleets} }
public enum SignatureExchange {
    public static func pack(_ fleets:[Fleet])->SignaturePack { SignaturePack(fleets:fleets) }
    public static func encode(_ pack:SignaturePack)->String { (try? String(data:JSONEncoder().encode(pack),encoding:.utf8)) ?? "" }
    public static func parse(_ text:String)throws->SignaturePack { try JSONDecoder().decode(SignaturePack.self,from:Data(text.trimmingCharacters(in:.whitespacesAndNewlines).utf8)) }
}
