import Foundation

public struct SignatureCatalogDocument: Codable, Sendable {
    public let format: String?
    public let formatVersion: Int?
    public let exportedAt: String?
    public let appVersion: String?
    public let catalogVersion: Int?
    public let fleets: [Fleet]
}

public enum SignatureCatalog {
    public static func loadBundled() throws -> [Fleet] {
        guard let url = Bundle.module.url(forResource: "fieldwatch-signatures-v2", withExtension: "json") else { throw CatalogError.missingResource }
        return try JSONDecoder().decode(SignatureCatalogDocument.self, from: Data(contentsOf: url)).fleets
    }
    public static func loadBundledOrEmpty() -> [Fleet] { (try? loadBundled()) ?? [] }
    public enum CatalogError: Error { case missingResource }
}
