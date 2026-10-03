import Foundation

public struct SettingsPack: Codable, Sendable, Equatable { public let format:String; public let version:Int; public let filter:FilterState; public let watchedKeys:[String]; public let customNames:[String:String]; public init(filter:FilterState,watchedKeys:Set<String>,customNames:[String:String]){self.format="fieldwatch-settings";self.version=1;self.filter=filter;self.watchedKeys=watchedKeys.sorted();self.customNames=customNames} }
public enum SettingsExchange {
    public static func encode(_ pack:SettingsPack)->String { (try? String(data:JSONEncoder().encode(pack),encoding:.utf8)) ?? "" }
    public static func decode(_ text:String)throws->SettingsPack { try JSONDecoder().decode(SettingsPack.self,from:Data(text.utf8)) }
}
