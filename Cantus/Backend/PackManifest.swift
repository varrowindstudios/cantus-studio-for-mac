import Foundation

struct PackManifest: Codable {
    let packId: String
    let version: Int
    let totalBytes: Int64
    let assets: [PackManifestAsset]
}

struct PackManifestAsset: Codable {
    let assetId: String
    let itemId: String
    let url: String
    let sha256: String?
    let bytes: Int64
    let codec: String?
    let sampleRate: Int?
    let channels: Int?
    let loopable: Bool?
    let tags: PackManifestTags?
    let attribution: PackManifestAttribution?
}

struct PackManifestAttribution: Codable {
    let author: String?
    let source: String?
    let license: String?
    let licenseURL: String?

    enum CodingKeys: String, CodingKey {
        case author
        case source
        case license
        case licenseURL = "licenseUrl"
    }
}

struct PackManifestTags: Codable {
    let locations: [String]?
    let moods: [String]?
    let themes: [String]?
    let creatureTypes: [String]?

    enum CodingKeys: String, CodingKey {
        case locations
        case moods
        case themes
        case creatureTypes = "creatureTypes"
    }
}
