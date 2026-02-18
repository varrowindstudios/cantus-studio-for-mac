import Foundation
import GRDB
import CryptoKit

final class PackDownloadManager {
    private let dbQueue: DatabaseQueue
    private let session: URLSession

    init(dbQueue: DatabaseQueue, session: URLSession = .shared) {
        self.dbQueue = dbQueue
        self.session = session
    }

    func startDownload(packId: UUID) async throws {
        let pack = try await fetchPack(packId: packId)
        await updatePackState(packId: packId, state: .downloading, bytesTotal: nil, bytesDownloaded: 0, error: nil, installedVersion: nil)

        let manifest = try await fetchManifest(urlString: pack.manifestURL)
        await updatePackState(packId: packId, state: .downloading, bytesTotal: manifest.totalBytes, bytesDownloaded: 0, error: nil, installedVersion: nil)

        let packKind = PackKind(rawValue: pack.kind) ?? .atmosphere
        try await applyManifestTags(manifest: manifest, packKind: packKind)

        var downloaded: Int64 = 0
        for asset in manifest.assets {
            let fileURL = try await downloadAsset(asset, packId: packId)
            downloaded += asset.bytes
            try await updateLocalAsset(asset: asset, packId: packId, localURL: fileURL)
            await updatePackState(packId: packId, state: .downloading, bytesTotal: manifest.totalBytes, bytesDownloaded: downloaded, error: nil, installedVersion: nil)
        }

        await updatePackState(packId: packId, state: .downloaded, bytesTotal: manifest.totalBytes, bytesDownloaded: downloaded, error: nil, installedVersion: manifest.version)
    }

    func cancelDownload(packId: UUID) async {
        await updatePackState(packId: packId, state: .failed, bytesTotal: nil, bytesDownloaded: nil, error: "Download canceled", installedVersion: nil)
    }

    func deletePack(packId: UUID) async throws {
        let assets = try await fetchLocalAssets(packId: packId)
        for asset in assets {
            if let path = asset.localPath {
                let fileURL = AppFilePaths.applicationSupportURL().appendingPathComponent(path)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM item_local_audio WHERE asset_id IN (SELECT id FROM local_asset WHERE pack_id = ?)", arguments: [packId.uuidString])
            try db.execute(sql: "DELETE FROM local_asset WHERE pack_id = ?", arguments: [packId.uuidString])
        }
        await updatePackState(packId: packId, state: .notDownloaded, bytesTotal: nil, bytesDownloaded: nil, error: nil, installedVersion: nil)
    }

    private func fetchPack(packId: UUID) async throws -> PackRow {
        try await dbQueue.read { db in
            guard let pack = try PackRow.fetchOne(db, key: packId.uuidString) else {
                throw RepositoryError.notFound
            }
            return pack
        }
    }

    private func fetchManifest(urlString: String) async throws -> PackManifest {
        guard let url = URL(string: urlString) else {
            throw PackDownloadError.invalidManifestURL
        }
        let (data, response) = try await session.data(from: url)
        try validateHTTPResponse(response)
        return try JSONDecoder().decode(PackManifest.self, from: data)
    }

    private func downloadAsset(_ asset: PackManifestAsset, packId: UUID) async throws -> URL {
        guard let url = URL(string: asset.url) else {
            throw PackDownloadError.invalidAssetURL
        }
        let (temporaryURL, response) = try await session.download(from: url)
        try validateHTTPResponse(response)

        let ext = url.pathExtension.isEmpty ? "dat" : url.pathExtension
        let folder = AppFilePaths.applicationSupportURL().appendingPathComponent("AudioAssets/\(packId.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appendingPathComponent("\(asset.assetId).\(ext)")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: fileURL)

        if let expected = asset.sha256 {
            let actual = try sha256Hex(for: fileURL)
            if actual.lowercased() != expected.lowercased() {
                throw PackDownloadError.hashMismatch
            }
        }

        return fileURL
    }

    private func updateLocalAsset(asset: PackManifestAsset, packId: UUID, localURL: URL) async throws {
        let relativePath = relativeAssetPath(for: localURL)
        try await dbQueue.write { db in
            let assetRow = LocalAssetRow(
                id: asset.assetId,
                packId: packId.uuidString,
                remoteURL: asset.url,
                localPath: relativePath,
                etag: nil,
                sha256: asset.sha256,
                bytesTotal: asset.bytes,
                attributionAuthor: asset.attribution?.author,
                attributionSource: asset.attribution?.source,
                attributionLicense: asset.attribution?.license,
                attributionLicenseURL: asset.attribution?.licenseURL,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            try assetRow.save(db)

            let itemLocal = ItemLocalAudioRow(
                itemId: asset.itemId,
                assetId: asset.assetId,
                codec: asset.codec,
                sampleRate: asset.sampleRate,
                channels: asset.channels,
                loopable: asset.loopable ?? false
            )
            try itemLocal.save(db)
        }
    }

    private func fetchLocalAssets(packId: UUID) async throws -> [LocalAssetRow] {
        try await dbQueue.read { db in
            try LocalAssetRow.fetchAll(db, sql: "SELECT * FROM local_asset WHERE pack_id = ?", arguments: [packId.uuidString])
        }
    }

    private func updatePackState(packId: UUID, state: PackInstallState, bytesTotal: Int64?, bytesDownloaded: Int64?, error: String?, installedVersion: Int?) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let row = PackStateRow(
            packId: packId.uuidString,
            state: state.rawValue,
            bytesTotal: bytesTotal,
            bytesDownloaded: bytesDownloaded,
            installedVersion: installedVersion,
            lastError: error,
            updatedAt: now
        )
        do {
            try await dbQueue.write { db in
                try row.save(db)
            }
        } catch {
            print("Failed updating pack state: \(error)")
        }
    }

    private func applyManifestTags(manifest: PackManifest, packKind: PackKind) async throws {
        try await dbQueue.write { db in
            for asset in manifest.assets {
                guard let tags = asset.tags else { continue }
                try self.upsertTags(db: db, itemId: asset.itemId, tags: tags, packKind: packKind)
            }
        }
    }

    private func upsertTags(db: Database, itemId: String, tags: PackManifestTags, packKind: PackKind) throws {
        if let locations = tags.locations {
            try upsertNames(db: db, table: "location", itemTable: "item_location", column: "location_id", itemId: itemId, names: locations)
        }
        if let moods = tags.moods {
            try upsertNames(db: db, table: "mood", itemTable: "item_mood", column: "mood_id", itemId: itemId, names: moods)
        }
        if let themes = tags.themes {
            switch packKind {
            case .sfx:
                try upsertNames(db: db, table: "sfx_theme", itemTable: "item_sfx_theme", column: "sfx_theme_id", itemId: itemId, names: themes)
            case .atmosphere:
                try upsertNames(db: db, table: "atmosphere_theme", itemTable: "item_atmosphere_theme", column: "atmosphere_theme_id", itemId: itemId, names: themes)
            case .music:
                try upsertNames(db: db, table: "music_theme", itemTable: "item_music_theme", column: "music_theme_id", itemId: itemId, names: themes)
            }
        }
        if let creatures = tags.creatureTypes {
            try upsertNames(db: db, table: "creature_type", itemTable: "item_creature_type", column: "creature_type_id", itemId: itemId, names: creatures)
        }
    }

    private func upsertNames(db: Database, table: String, itemTable: String, column: String, itemId: String, names: [String]) throws {
        for name in names {
            try db.execute(sql: "INSERT INTO \(table) (name, is_system) VALUES (?, 0) ON CONFLICT(name) DO NOTHING", arguments: [name])
            let id = try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE name = ?", arguments: [name]) ?? 0
            try db.execute(sql: "INSERT INTO \(itemTable) (item_id, \(column)) VALUES (?, ?) ON CONFLICT DO NOTHING", arguments: [itemId, id])
        }
    }

    private func relativeAssetPath(for fileURL: URL) -> String {
        let base = AppFilePaths.applicationSupportURL().path
        let full = fileURL.path
        if full.hasPrefix(base) {
            let start = full.index(full.startIndex, offsetBy: base.count + 1)
            return String(full[start...])
        }
        return fileURL.lastPathComponent
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PackDownloadError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw PackDownloadError.invalidResponse
        }
    }

    private func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        var digest = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            digest.update(data: chunk)
        }

        let finalized = digest.finalize()
        return finalized.map { String(format: "%02x", $0) }.joined()
    }
}

enum PackDownloadError: Error {
    case invalidManifestURL
    case invalidAssetURL
    case invalidResponse
    case hashMismatch
}
