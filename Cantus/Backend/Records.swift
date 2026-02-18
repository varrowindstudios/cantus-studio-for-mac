import Foundation
import GRDB

enum LibraryKind: String, Codable {
    case music
    case atmosphere
    case sfx
}

enum PackKind: String, Codable {
    case atmosphere
    case sfx
    case music
}

enum PackInstallState: String, Codable {
    case notDownloaded = "not_downloaded"
    case downloading
    case downloaded
    case failed
}

struct LibraryItemRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "library_item"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let id: String
    let kind: String
    let title: String
    let subtitle: String?
    let duration: Double?
    let artworkURL: String?
    let isVisible: Bool
    let containsMusic: Bool
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case subtitle
        case duration
        case artworkURL = "artwork_url"
        case isVisible = "is_visible"
        case containsMusic = "contains_music"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    enum Columns {
        static let id = Column("id")
        static let kind = Column("kind")
        static let title = Column("title")
        static let subtitle = Column("subtitle")
        static let duration = Column("duration")
        static let artworkURL = Column("artwork_url")
        static let isVisible = Column("is_visible")
        static let containsMusic = Column("contains_music")
        static let createdAt = Column("created_at")
        static let updatedAt = Column("updated_at")
    }
}

struct MusicPlaylistRefRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "music_playlist_ref"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let itemId: String
    let appleMusicPlaylistId: String
    let lastSyncAt: String?
    let useSnapshot: Bool

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case appleMusicPlaylistId = "apple_music_playlist_id"
        case lastSyncAt = "last_sync_at"
        case useSnapshot = "use_snapshot"
    }
}

struct PackRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pack"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let id: String
    let kind: String
    let title: String
    let description: String?
    let artworkURL: String?
    let version: Int
    let manifestURL: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case description
        case artworkURL = "artwork_url"
        case version
        case manifestURL = "manifest_url"
        case createdAt = "created_at"
    }
}

struct PackStateRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pack_state"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let packId: String
    let state: String
    let bytesTotal: Int64?
    let bytesDownloaded: Int64?
    let installedVersion: Int?
    let lastError: String?
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case state
        case bytesTotal = "bytes_total"
        case bytesDownloaded = "bytes_downloaded"
        case installedVersion = "installed_version"
        case lastError = "last_error"
        case updatedAt = "updated_at"
    }
}

struct PackItemRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "pack_item"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let packId: String
    let itemId: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case itemId = "item_id"
        case sortOrder = "sort_order"
    }
}

struct LocalAssetRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_asset"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let id: String
    let packId: String
    let remoteURL: String
    let localPath: String?
    let etag: String?
    let sha256: String?
    let bytesTotal: Int64?
    let attributionAuthor: String?
    let attributionSource: String?
    let attributionLicense: String?
    let attributionLicenseURL: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case packId = "pack_id"
        case remoteURL = "remote_url"
        case localPath = "local_path"
        case etag
        case sha256
        case bytesTotal = "bytes_total"
        case attributionAuthor = "attribution_author"
        case attributionSource = "attribution_source"
        case attributionLicense = "attribution_license"
        case attributionLicenseURL = "attribution_license_url"
        case createdAt = "created_at"
    }
}

struct ItemLocalAudioRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "item_local_audio"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let itemId: String
    let assetId: String
    let codec: String?
    let sampleRate: Int?
    let channels: Int?
    let loopable: Bool

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case assetId = "asset_id"
        case codec
        case sampleRate = "sample_rate"
        case channels
        case loopable
    }
}

struct LocalPlaylistTrackRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "local_playlist_track"
    static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)

    let id: String
    let playlistItemId: String
    let assetId: String
    let position: Int
    let title: String
    let artist: String?
    let duration: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case playlistItemId = "playlist_item_id"
        case assetId = "asset_id"
        case position
        case title
        case artist
        case duration
    }
}

struct TagValue: Codable, FetchableRecord {
    let id: Int64
    let name: String
}

struct LibraryItemRowWithPack: FetchableRecord, Decodable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String?
    let duration: Double?
    let artworkURL: String?
    let isVisible: Bool
    let containsMusic: Bool
    let createdAt: String
    let updatedAt: String
    let packId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case title
        case subtitle
        case duration
        case artworkURL = "artwork_url"
        case isVisible = "is_visible"
        case containsMusic = "contains_music"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case packId = "pack_id"
    }
}
