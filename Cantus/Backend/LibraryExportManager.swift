import Foundation
import GRDB
import ZIPFoundation

enum LibraryExportError: Error {
    case zipUnavailable
    case missingLibraryFile
    case invalidExport
}

enum LibraryExportScope: String, CaseIterable, Identifiable {
    case everything
    case playlists
    case atmospheres
    case soundEffects

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everything:
            return "Everything"
        case .playlists:
            return "Playlists"
        case .atmospheres:
            return "Atmospheres"
        case .soundEffects:
            return "Sound Effects"
        }
    }

    var includesPlaylists: Bool {
        self == .everything || self == .playlists
    }

    var includesAtmospheres: Bool {
        self == .everything || self == .atmospheres
    }

    var includesSoundEffects: Bool {
        self == .everything || self == .soundEffects
    }

    var includedKinds: Set<String> {
        switch self {
        case .everything:
            return [
                LibraryKind.music.rawValue,
                LibraryKind.atmosphere.rawValue,
                LibraryKind.sfx.rawValue
            ]
        case .playlists:
            return [LibraryKind.music.rawValue]
        case .atmospheres:
            return [LibraryKind.atmosphere.rawValue]
        case .soundEffects:
            return [LibraryKind.sfx.rawValue]
        }
    }
}

struct LibraryExportPreferences {
    var masterVolume: Double
    var musicVolume: Double
    var atmosphereVolume: Double
    var sfxVolume: Double
    var loopBookmarks: [String]
    var sfxBookmarks: [String]
    var hasCompletedSetup: Bool
}

struct LibraryExportBundle {
    let bundleURL: URL
    let zipURL: URL
    let summary: LibraryExportSummary
    let zipSizeBytes: Int64
    let timestampToken: String
}

struct LibraryExportSummary {
    let scope: LibraryExportScope
    let itemCount: Int
    let atmosphereCount: Int
    let sfxCount: Int
    let playlistItemCount: Int
    let assetCount: Int
    let packCount: Int
    let packItemCount: Int
    let tagCount: Int
    let itemTagCount: Int
    let playlistCount: Int
    let loopBookmarkCount: Int
    let sfxBookmarkCount: Int
    let includesPreferences: Bool
    let mediaFileCount: Int
}

final class LibraryExportManager {
    static let shared = LibraryExportManager()

    private init() {}

    func exportBundle(
        backend: AppBackend,
        bookmarks: BookmarksStore,
        playback: PlaybackStateStore,
        hasCompletedSetup: Bool,
        scope: LibraryExportScope
    ) async throws -> LibraryExportBundle {
        let timestampToken = Self.dateStamp()
        let bundleName = "Cantus_Export_\(timestampToken)"
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(bundleName, isDirectory: true)

        if FileManager.default.fileExists(atPath: tempBase.path) {
            try? FileManager.default.removeItem(at: tempBase)
        }

        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)

        let mediaRoot = tempBase.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: mediaRoot, withIntermediateDirectories: true)

        let export = try await buildExportSnapshot(
            backend: backend,
            bookmarks: bookmarks,
            playback: playback,
            hasCompletedSetup: hasCompletedSetup,
            scope: scope
        )

        try writeXML(export: export, to: tempBase.appendingPathComponent("library.xml"))
        try copyMediaFiles(assets: export.assets, to: mediaRoot)

        let zipURL = tempBase.deletingLastPathComponent().appendingPathComponent("\(bundleName).zip")
        try zipBundle(at: tempBase, to: zipURL)

        let atmosphereCount = export.items.filter { $0.kind == LibraryKind.atmosphere.rawValue }.count
        let sfxCount = export.items.filter { $0.kind == LibraryKind.sfx.rawValue }.count
        let playlistItemCount = export.items.filter { $0.kind == LibraryKind.music.rawValue }.count
        let summary = LibraryExportSummary(
            scope: scope,
            itemCount: export.items.count,
            atmosphereCount: atmosphereCount,
            sfxCount: sfxCount,
            playlistItemCount: playlistItemCount,
            assetCount: export.assets.count,
            packCount: export.packs.count,
            packItemCount: export.packItems.count,
            tagCount: export.tags.count,
            itemTagCount: export.itemTags.count,
            playlistCount: export.playlists.count,
            loopBookmarkCount: export.preferences.loopBookmarks.count,
            sfxBookmarkCount: export.preferences.sfxBookmarks.count,
            includesPreferences: true,
            mediaFileCount: export.assets.filter { $0.localPath != nil }.count
        )

        let zipSize = fileSize(for: zipURL)
        return LibraryExportBundle(
            bundleURL: tempBase,
            zipURL: zipURL,
            summary: summary,
            zipSizeBytes: zipSize,
            timestampToken: timestampToken
        )
    }

    func importBundle(
        zipURL: URL,
        backend: AppBackend,
        bookmarks: BookmarksStore,
        playback: PlaybackStateStore,
        hasCompletedSetup: inout Bool
    ) async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cantus-import-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        try unzipBundle(from: zipURL, to: tempDir)

        guard let libraryXML = findLibraryXML(in: tempDir) else {
            throw LibraryExportError.missingLibraryFile
        }

        let export = try parseXML(from: libraryXML)

        try await applyExport(export, backend: backend)
        try copyImportedMedia(export: export, bundleRoot: libraryXML.deletingLastPathComponent())
        let setupValue = export.preferences.hasCompletedSetup
        await MainActor.run {
            bookmarks.applyExport(loopBookmarks: export.preferences.loopBookmarks, sfxBookmarks: export.preferences.sfxBookmarks)
            playback.applyExportPreferences(
                master: export.preferences.masterVolume,
                music: export.preferences.musicVolume,
                atmosphere: export.preferences.atmosphereVolume,
                sfx: export.preferences.sfxVolume
            )
        }
        hasCompletedSetup = setupValue
    }

    // MARK: - Snapshot

    private func buildExportSnapshot(
        backend: AppBackend,
        bookmarks: BookmarksStore,
        playback: PlaybackStateStore,
        hasCompletedSetup: Bool,
        scope: LibraryExportScope
    ) async throws -> LibraryExportSnapshot {
        let preferences = await MainActor.run {
            LibraryExportPreferences(
                masterVolume: playback.masterVolume,
                musicVolume: playback.musicVolume,
                atmosphereVolume: playback.atmosphereVolume,
                sfxVolume: playback.sfxVolume,
                loopBookmarks: bookmarks.loopBookmarkList,
                sfxBookmarks: bookmarks.sfxBookmarkList,
                hasCompletedSetup: hasCompletedSetup
            )
        }

        let snapshot = try await backend.database.dbQueue.read { db -> LibraryExportSnapshot in
            let items = try LibraryItemRow.fetchAll(db)
            let packs = try PackRow.fetchAll(db)
            let packItems = try PackItemRow.fetchAll(db)
            let assets = try LocalAssetRow.fetchAll(db)
            let itemAudio = try ItemLocalAudioRow.fetchAll(db)
            let playlists = try MusicPlaylistRefRow.fetchAll(db)
            let localPlaylistTracks = try LocalPlaylistTrackRow.fetchAll(db)

            let tags = try ExportTag.fetchAll(db)
            let itemTags = try ExportItemTag.fetchAll(db)

            return LibraryExportSnapshot(
                createdAt: Self.timestamp(),
                items: items,
                packs: packs,
                packItems: packItems,
                assets: assets,
                itemAudio: itemAudio,
                localPlaylistTracks: localPlaylistTracks,
                playlists: playlists,
                tags: tags,
                itemTags: itemTags,
                preferences: preferences
            )
        }

        return filterSnapshot(snapshot, scope: scope)
    }

    // MARK: - XML

    private func writeXML(export: LibraryExportSnapshot, to url: URL) throws {
        var writer = XMLWriter()
        writer.start("cantus_export", attributes: [
            "version": "1.0",
            "created_at": export.createdAt
        ])

        writer.start("library")

        writer.start("items")
        for item in export.items {
            var attrs: [String: String] = [
                "id": item.id,
                "kind": item.kind,
                "title": item.title,
                "is_visible": item.isVisible ? "1" : "0",
                "contains_music": item.containsMusic ? "1" : "0",
                "created_at": item.createdAt,
                "updated_at": item.updatedAt
            ]
            if let subtitle = item.subtitle { attrs["subtitle"] = subtitle }
            if let duration = item.duration { attrs["duration"] = String(duration) }
            if let artwork = item.artworkURL { attrs["artwork_url"] = artwork }

            writer.start("item", attributes: attrs)

            if let audio = export.itemAudio.first(where: { $0.itemId == item.id }) {
                var audioAttrs: [String: String] = [
                    "asset_id": audio.assetId,
                    "loopable": audio.loopable ? "1" : "0"
                ]
                if let codec = audio.codec { audioAttrs["codec"] = codec }
                if let sampleRate = audio.sampleRate { audioAttrs["sample_rate"] = String(sampleRate) }
                if let channels = audio.channels { audioAttrs["channels"] = String(channels) }
                writer.empty("audio", attributes: audioAttrs)
            }

            let itemTags = export.itemTags.filter { $0.itemId == item.id }
            if !itemTags.isEmpty {
                writer.start("tags")
                for tag in itemTags {
                    writer.empty("tag", attributes: [
                        "category": tag.category,
                        "name": tag.tagName
                    ])
                }
                writer.end("tags")
            }

            writer.end("item")
        }
        writer.end("items")

        writer.start("assets")
        for asset in export.assets {
            var attrs: [String: String] = [
                "id": asset.id,
                "pack_id": asset.packId,
                "remote_url": asset.remoteURL,
                "created_at": asset.createdAt
            ]
            if let localPath = asset.localPath {
                attrs["local_path"] = localPath
                attrs["media_path"] = "media/\(localPath)"
            }
            if let etag = asset.etag { attrs["etag"] = etag }
            if let sha256 = asset.sha256 { attrs["sha256"] = sha256 }
            if let bytes = asset.bytesTotal { attrs["bytes_total"] = String(bytes) }
            if let attributionAuthor = asset.attributionAuthor { attrs["attribution_author"] = attributionAuthor }
            if let attributionSource = asset.attributionSource { attrs["attribution_source"] = attributionSource }
            if let attributionLicense = asset.attributionLicense { attrs["attribution_license"] = attributionLicense }
            if let attributionLicenseURL = asset.attributionLicenseURL { attrs["attribution_license_url"] = attributionLicenseURL }
            writer.empty("asset", attributes: attrs)
        }
        writer.end("assets")

        writer.start("packs")
        for pack in export.packs {
            var attrs: [String: String] = [
                "id": pack.id,
                "kind": pack.kind,
                "title": pack.title,
                "version": String(pack.version),
                "manifest_url": pack.manifestURL,
                "created_at": pack.createdAt
            ]
            if let desc = pack.description { attrs["description"] = desc }
            if let artwork = pack.artworkURL { attrs["artwork_url"] = artwork }
            writer.empty("pack", attributes: attrs)
        }
        for packItem in export.packItems {
            writer.empty("pack_item", attributes: [
                "pack_id": packItem.packId,
                "item_id": packItem.itemId,
                "sort_order": String(packItem.sortOrder)
            ])
        }
        writer.end("packs")

        writer.start("music_playlists")
        for playlist in export.playlists {
            var attrs: [String: String] = [
                "item_id": playlist.itemId,
                "apple_music_playlist_id": playlist.appleMusicPlaylistId,
                "use_snapshot": playlist.useSnapshot ? "1" : "0"
            ]
            if let lastSync = playlist.lastSyncAt { attrs["last_sync_at"] = lastSync }
            writer.empty("playlist", attributes: attrs)
        }
        writer.end("music_playlists")

        writer.start("local_playlist_tracks")
        for track in export.localPlaylistTracks {
            var attrs: [String: String] = [
                "id": track.id,
                "playlist_item_id": track.playlistItemId,
                "asset_id": track.assetId,
                "position": String(track.position),
                "title": track.title
            ]
            if let artist = track.artist { attrs["artist"] = artist }
            if let duration = track.duration { attrs["duration"] = String(duration) }
            writer.empty("local_playlist_track", attributes: attrs)
        }
        writer.end("local_playlist_tracks")

        writer.start("tags")
        for tag in export.tags {
            var attrs: [String: String] = [
                "category": tag.category,
                "name": tag.name,
                "is_system": tag.isSystem ? "1" : "0",
                "created_at": tag.createdAt
            ]
            if let order = tag.sortOrder { attrs["sort_order"] = String(order) }
            writer.empty("tag", attributes: attrs)
        }
        writer.end("tags")

        writer.end("library")

        writer.start("preferences")
        writer.empty("volumes", attributes: [
            "master": String(export.preferences.masterVolume),
            "music": String(export.preferences.musicVolume),
            "atmosphere": String(export.preferences.atmosphereVolume),
            "sfx": String(export.preferences.sfxVolume)
        ])

        writer.start("bookmarks")
        for title in export.preferences.loopBookmarks {
            writer.empty("loop", attributes: ["title": title])
        }
        for title in export.preferences.sfxBookmarks {
            writer.empty("sfx", attributes: ["title": title])
        }
        writer.end("bookmarks")

        writer.empty("ui", attributes: [
            "has_completed_setup": export.preferences.hasCompletedSetup ? "1" : "0"
        ])
        writer.start("sort_options")
        writer.end("sort_options")
        writer.end("preferences")

        writer.end("cantus_export")

        try writer.output.write(to: url, atomically: true, encoding: .utf8)
    }

    private func parseXML(from url: URL) throws -> LibraryExportSnapshot {
        guard let parser = XMLParser(contentsOf: url) else {
            throw LibraryExportError.missingLibraryFile
        }
        let delegate = LibraryExportXMLParser()
        parser.delegate = delegate
        if parser.parse() {
            return delegate.snapshot
        }
        throw LibraryExportError.invalidExport
    }

    // MARK: - Import Apply

    private func applyExport(_ export: LibraryExportSnapshot, backend: AppBackend) async throws {
        try await backend.database.dbQueue.write { db in
            try db.execute(sql: "DELETE FROM item_location")
            try db.execute(sql: "DELETE FROM item_mood")
            try db.execute(sql: "DELETE FROM item_music_theme")
            try db.execute(sql: "DELETE FROM item_atmosphere_theme")
            try db.execute(sql: "DELETE FROM item_sfx_theme")
            try db.execute(sql: "DELETE FROM item_creature_type")
            try db.execute(sql: "DELETE FROM item_local_audio")
            try db.execute(sql: "DELETE FROM local_playlist_track")
            try db.execute(sql: "DELETE FROM pack_item")
            try db.execute(sql: "DELETE FROM local_asset")
            try db.execute(sql: "DELETE FROM music_playlist_ref")
            try db.execute(sql: "DELETE FROM library_item")
            try db.execute(sql: "DELETE FROM pack")

            try db.execute(sql: "DELETE FROM location")
            try db.execute(sql: "DELETE FROM mood")
            try db.execute(sql: "DELETE FROM music_theme")
            try db.execute(sql: "DELETE FROM atmosphere_theme")
            try db.execute(sql: "DELETE FROM sfx_theme")
            try db.execute(sql: "DELETE FROM creature_type")

            for tag in export.tags {
                try self.upsertTag(tag, db: db)
            }

            for pack in export.packs { try pack.insert(db) }
            for item in export.items { try item.insert(db) }
            for asset in export.assets { try asset.insert(db) }
            for audio in export.itemAudio { try audio.insert(db) }
            for track in export.localPlaylistTracks { try track.insert(db) }
            for playlist in export.playlists { try playlist.insert(db) }
            for packItem in export.packItems { try packItem.insert(db) }
            for join in export.itemTags { try self.insertJoin(join, db: db) }
        }
    }

    private func filterSnapshot(_ snapshot: LibraryExportSnapshot, scope: LibraryExportScope) -> LibraryExportSnapshot {
        guard scope != .everything else { return snapshot }

        let includedKinds = scope.includedKinds
        let items = snapshot.items.filter { includedKinds.contains($0.kind) }
        let itemIds = Set(items.map(\.id))

        let itemAudio = snapshot.itemAudio.filter { itemIds.contains($0.itemId) }
        let localPlaylistTracks = snapshot.localPlaylistTracks.filter { itemIds.contains($0.playlistItemId) }
        let playlists = snapshot.playlists.filter { itemIds.contains($0.itemId) }

        let assetIds = Set(itemAudio.map(\.assetId) + localPlaylistTracks.map(\.assetId))
        let assets = snapshot.assets.filter { assetIds.contains($0.id) }

        let packItems = snapshot.packItems.filter { itemIds.contains($0.itemId) }
        let packIds = Set(packItems.map(\.packId) + assets.map(\.packId))
        let packs = snapshot.packs.filter { packIds.contains($0.id) }

        let itemTags = snapshot.itemTags.filter { itemIds.contains($0.itemId) }
        let tags = snapshot.tags.filter { includedTagCategories(for: scope).contains($0.category) }

        var preferences = snapshot.preferences
        if scope.includesAtmospheres {
            let atmosphereTitles = Set(items.filter { $0.kind == LibraryKind.atmosphere.rawValue }.map(\.title))
            preferences.loopBookmarks = preferences.loopBookmarks.filter { atmosphereTitles.contains($0) }
        } else {
            preferences.loopBookmarks = []
        }

        if scope.includesSoundEffects {
            let sfxTitles = Set(items.filter { $0.kind == LibraryKind.sfx.rawValue }.map(\.title))
            preferences.sfxBookmarks = preferences.sfxBookmarks.filter { sfxTitles.contains($0) }
        } else {
            preferences.sfxBookmarks = []
        }

        return LibraryExportSnapshot(
            createdAt: snapshot.createdAt,
            items: items,
            packs: packs,
            packItems: packItems,
            assets: assets,
            itemAudio: itemAudio,
            localPlaylistTracks: localPlaylistTracks,
            playlists: playlists,
            tags: tags,
            itemTags: itemTags,
            preferences: preferences
        )
    }

    private func includedTagCategories(for scope: LibraryExportScope) -> Set<String> {
        switch scope {
        case .everything:
            return [
                "location",
                "mood",
                "music_theme",
                "atmosphere_theme",
                "sfx_theme",
                "creature_type"
            ]
        case .playlists:
            return ["location", "mood", "music_theme"]
        case .atmospheres:
            return ["location", "mood", "atmosphere_theme", "creature_type"]
        case .soundEffects:
            return ["location", "mood", "sfx_theme", "creature_type"]
        }
    }

    private func copyMediaFiles(assets: [LocalAssetRow], to mediaRoot: URL) throws {
        let appSupport = AppFilePaths.applicationSupportURL()
        for asset in assets {
            guard let localPath = asset.localPath else { continue }
            let source = appSupport.appendingPathComponent(localPath)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = mediaRoot.appendingPathComponent(localPath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func copyImportedMedia(export: LibraryExportSnapshot, bundleRoot: URL) throws {
        let mediaRoot = bundleRoot.appendingPathComponent("media", isDirectory: true)
        let appSupport = AppFilePaths.applicationSupportURL()
        for asset in export.assets {
            guard let localPath = asset.localPath else { continue }
            let source = mediaRoot.appendingPathComponent(localPath)
            guard FileManager.default.fileExists(atPath: source.path) else { continue }
            let destination = appSupport.appendingPathComponent(localPath)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func zipBundle(at folderURL: URL, to zipURL: URL) throws {
        if #available(iOS 16.0, *) {
            if FileManager.default.fileExists(atPath: zipURL.path) {
                try? FileManager.default.removeItem(at: zipURL)
            }
            try FileManager.default.zipItem(at: folderURL, to: zipURL, shouldKeepParent: true)
        } else {
            throw LibraryExportError.zipUnavailable
        }
    }

    private func unzipBundle(from zipURL: URL, to destination: URL) throws {
        if #available(iOS 16.0, *) {
            try FileManager.default.unzipItem(at: zipURL, to: destination)
        } else {
            throw LibraryExportError.zipUnavailable
        }
    }

    private func findLibraryXML(in folder: URL) -> URL? {
        let candidate = folder.appendingPathComponent("library.xml")
        if FileManager.default.fileExists(atPath: candidate.path) {
            return candidate
        }
        let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
        while let item = enumerator?.nextObject() as? URL {
            if item.lastPathComponent == "library.xml" {
                return item
            }
        }
        return nil
    }

    private func fileSize(for url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }

    // MARK: - Helpers

    static func timestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func dateStamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private func upsertTag(_ tag: ExportTag, db: Database) throws {
        guard let table = ExportTag.tableName(for: tag.category) else { return }
        let existingId = try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE name = ?", arguments: [tag.name])
        if let id = existingId {
            try db.execute(
                sql: "UPDATE \(table) SET sort_order = ?, is_system = ?, created_at = ? WHERE id = ?",
                arguments: [tag.sortOrder, tag.isSystem, tag.createdAt, id]
            )
        } else {
            try db.execute(
                sql: "INSERT INTO \(table) (name, sort_order, is_system, created_at) VALUES (?, ?, ?, ?)",
                arguments: [tag.name, tag.sortOrder, tag.isSystem, tag.createdAt]
            )
        }
    }

    private func insertJoin(_ join: ExportItemTag, db: Database) throws {
        guard let info = ExportTag.joinInfo(for: join.category),
              let table = ExportTag.tableName(for: join.category) else { return }
        var tagId = try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE name = ?", arguments: [join.tagName])
        if tagId == nil {
            try db.execute(
                sql: "INSERT INTO \(table) (name, sort_order, is_system, created_at) VALUES (?, NULL, ?, ?)",
                arguments: [join.tagName, true, Self.timestamp()]
            )
            tagId = try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE name = ?", arguments: [join.tagName])
        }
        guard let resolvedId = tagId else { return }
        try db.execute(
            sql: "INSERT OR IGNORE INTO \(info.table) (item_id, \(info.idColumn)) VALUES (?, ?)",
            arguments: [join.itemId, resolvedId]
        )
    }
}

// MARK: - XML Models

struct LibraryExportSnapshot {
    var createdAt: String
    var items: [LibraryItemRow]
    var packs: [PackRow]
    var packItems: [PackItemRow]
    var assets: [LocalAssetRow]
    var itemAudio: [ItemLocalAudioRow]
    var localPlaylistTracks: [LocalPlaylistTrackRow]
    var playlists: [MusicPlaylistRefRow]
    var tags: [ExportTag]
    var itemTags: [ExportItemTag]
    var preferences: LibraryExportPreferences
}

struct ExportTag {
    let category: String
    let name: String
    let sortOrder: Int?
    let isSystem: Bool
    let createdAt: String

    static func fetchAll(_ db: Database) throws -> [ExportTag] {
        try fetch(from: db, table: "location", category: "location")
            + fetch(from: db, table: "mood", category: "mood")
            + fetch(from: db, table: "music_theme", category: "music_theme")
            + fetch(from: db, table: "atmosphere_theme", category: "atmosphere_theme")
            + fetch(from: db, table: "sfx_theme", category: "sfx_theme")
            + fetch(from: db, table: "creature_type", category: "creature_type")
    }

    static func fetch(from db: Database, table: String, category: String) throws -> [ExportTag] {
        let sql = "SELECT name, sort_order, is_system, created_at FROM \(table)"
        let rows = try Row.fetchAll(db, SQLRequest(sql: sql))
        return rows.compactMap { row in
            guard let name = row["name"] as String? else { return nil }
            return ExportTag(
                category: category,
                name: name,
                sortOrder: row["sort_order"] as Int?,
                isSystem: row["is_system"] as Bool? ?? true,
                createdAt: row["created_at"] as String? ?? LibraryExportManager.timestamp()
            )
        }
    }

    static func tableName(for category: String) -> String? {
        switch category {
        case "location": return "location"
        case "mood": return "mood"
        case "music_theme": return "music_theme"
        case "atmosphere_theme": return "atmosphere_theme"
        case "sfx_theme": return "sfx_theme"
        case "creature_type": return "creature_type"
        default: return nil
        }
    }

    static func joinInfo(for category: String) -> (table: String, idColumn: String)? {
        switch category {
        case "location": return ("item_location", "location_id")
        case "mood": return ("item_mood", "mood_id")
        case "music_theme": return ("item_music_theme", "music_theme_id")
        case "atmosphere_theme": return ("item_atmosphere_theme", "atmosphere_theme_id")
        case "sfx_theme": return ("item_sfx_theme", "sfx_theme_id")
        case "creature_type": return ("item_creature_type", "creature_type_id")
        default: return nil
        }
    }
}

struct ExportItemTag {
    let itemId: String
    let category: String
    let tagName: String

    static func fetchAll(_ db: Database) throws -> [ExportItemTag] {
        try fetch(from: db, joinTable: "item_location", tagTable: "location", tagColumn: "location_id", category: "location")
            + fetch(from: db, joinTable: "item_mood", tagTable: "mood", tagColumn: "mood_id", category: "mood")
            + fetch(from: db, joinTable: "item_music_theme", tagTable: "music_theme", tagColumn: "music_theme_id", category: "music_theme")
            + fetch(from: db, joinTable: "item_atmosphere_theme", tagTable: "atmosphere_theme", tagColumn: "atmosphere_theme_id", category: "atmosphere_theme")
            + fetch(from: db, joinTable: "item_sfx_theme", tagTable: "sfx_theme", tagColumn: "sfx_theme_id", category: "sfx_theme")
            + fetch(from: db, joinTable: "item_creature_type", tagTable: "creature_type", tagColumn: "creature_type_id", category: "creature_type")
    }

    static func fetch(
        from db: Database,
        joinTable: String,
        tagTable: String,
        tagColumn: String,
        category: String
    ) throws -> [ExportItemTag] {
        let sql = """
        SELECT j.item_id as item_id, t.name as tag_name
        FROM \(joinTable) j
        JOIN \(tagTable) t ON t.id = j.\(tagColumn)
        """
        let rows = try Row.fetchAll(db, SQLRequest(sql: sql))
        return rows.compactMap { row in
            guard let itemId = row["item_id"] as String?,
                  let tagName = row["tag_name"] as String? else {
                return nil
            }
            return ExportItemTag(itemId: itemId, category: category, tagName: tagName)
        }
    }
}

// MARK: - XML Writer

private struct XMLWriter {
    private(set) var output = ""
    private var stack: [String] = []

    mutating func start(_ name: String, attributes: [String: String] = [:]) {
        output += "<\(name)\(attributesString(attributes))>"
        stack.append(name)
    }

    mutating func end(_ name: String) {
        output += "</\(name)>"
        _ = stack.popLast()
    }

    mutating func empty(_ name: String, attributes: [String: String] = [:]) {
        output += "<\(name)\(attributesString(attributes))/>";
    }

    private func attributesString(_ attributes: [String: String]) -> String {
        guard !attributes.isEmpty else { return "" }
        let rendered = attributes.map { key, value in
            " \(key)=\"\(escape(value))\""
        }.joined()
        return rendered
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - XML Parser

private final class LibraryExportXMLParser: NSObject, XMLParserDelegate {
    private(set) var snapshot = LibraryExportSnapshot(
        createdAt: "",
        items: [],
        packs: [],
        packItems: [],
        assets: [],
        itemAudio: [],
        localPlaylistTracks: [],
        playlists: [],
        tags: [],
        itemTags: [],
        preferences: LibraryExportPreferences(
            masterVolume: 0.9,
            musicVolume: 0.72,
            atmosphereVolume: 0.56,
            sfxVolume: 0.48,
            loopBookmarks: [],
            sfxBookmarks: [],
            hasCompletedSetup: true
        )
    )

    private var currentItem: LibraryItemRow?
    private var currentItemTags: [ExportItemTag] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        switch elementName {
        case let rootName where rootName == "cantus_export" || rootName.hasSuffix("_export"):
            snapshot = LibraryExportSnapshot(
                createdAt: attributeDict["created_at"] ?? "",
                items: [],
                packs: [],
                packItems: [],
                assets: [],
                itemAudio: [],
                localPlaylistTracks: [],
                playlists: [],
                tags: [],
                itemTags: [],
                preferences: snapshot.preferences
            )
        case "item":
            currentItemTags = []
            guard let id = attributeDict["id"],
                  let kind = attributeDict["kind"],
                  let title = attributeDict["title"],
                  let createdAt = attributeDict["created_at"],
                  let updatedAt = attributeDict["updated_at"] else { return }
            let subtitle = attributeDict["subtitle"]
            let duration = attributeDict["duration"].flatMap(Double.init)
            let artwork = attributeDict["artwork_url"]
            let isVisible = attributeDict["is_visible"].flatMap { $0 == "1" } ?? true
            let containsMusic = attributeDict["contains_music"].flatMap { $0 == "1" } ?? false
            currentItem = LibraryItemRow(
                id: id,
                kind: kind,
                title: title,
                subtitle: subtitle,
                duration: duration,
                artworkURL: artwork,
                isVisible: isVisible,
                containsMusic: containsMusic,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        case "audio":
            guard let item = currentItem,
                  let assetId = attributeDict["asset_id"] else { return }
            let codec = attributeDict["codec"]
            let sampleRate = attributeDict["sample_rate"].flatMap(Int.init)
            let channels = attributeDict["channels"].flatMap(Int.init)
            let loopable = attributeDict["loopable"] == "1"
            snapshot.itemAudio.append(ItemLocalAudioRow(
                itemId: item.id,
                assetId: assetId,
                codec: codec,
                sampleRate: sampleRate,
                channels: channels,
                loopable: loopable
            ))
        case "tag":
            if let item = currentItem {
                guard let category = attributeDict["category"],
                      let name = attributeDict["name"] else { return }
                currentItemTags.append(ExportItemTag(itemId: item.id, category: category, tagName: name))
            } else if let category = attributeDict["category"],
                      let name = attributeDict["name"],
                      let createdAt = attributeDict["created_at"] {
                snapshot.tags.append(ExportTag(
                    category: category,
                    name: name,
                    sortOrder: attributeDict["sort_order"].flatMap(Int.init),
                    isSystem: attributeDict["is_system"] == "1",
                    createdAt: createdAt
                ))
            }
        case "asset":
            guard let id = attributeDict["id"],
                  let packId = attributeDict["pack_id"],
                  let remoteURL = attributeDict["remote_url"],
                  let createdAt = attributeDict["created_at"] else { return }
            snapshot.assets.append(LocalAssetRow(
                id: id,
                packId: packId,
                remoteURL: remoteURL,
                localPath: attributeDict["local_path"],
                etag: attributeDict["etag"],
                sha256: attributeDict["sha256"],
                bytesTotal: attributeDict["bytes_total"].flatMap(Int64.init),
                attributionAuthor: attributeDict["attribution_author"],
                attributionSource: attributeDict["attribution_source"],
                attributionLicense: attributeDict["attribution_license"],
                attributionLicenseURL: attributeDict["attribution_license_url"],
                createdAt: createdAt
            ))
        case "pack":
            guard let id = attributeDict["id"],
                  let kind = attributeDict["kind"],
                  let title = attributeDict["title"],
                  let version = attributeDict["version"].flatMap(Int.init),
                  let manifestURL = attributeDict["manifest_url"],
                  let createdAt = attributeDict["created_at"] else { return }
            snapshot.packs.append(PackRow(
                id: id,
                kind: kind,
                title: title,
                description: attributeDict["description"],
                artworkURL: attributeDict["artwork_url"],
                version: version,
                manifestURL: manifestURL,
                createdAt: createdAt
            ))
        case "pack_item":
            guard let packId = attributeDict["pack_id"],
                  let itemId = attributeDict["item_id"],
                  let sortOrder = attributeDict["sort_order"].flatMap(Int.init) else { return }
            snapshot.packItems.append(PackItemRow(packId: packId, itemId: itemId, sortOrder: sortOrder))
        case "playlist":
            guard let itemId = attributeDict["item_id"],
                  let playlistId = attributeDict["apple_music_playlist_id"] else { return }
            snapshot.playlists.append(MusicPlaylistRefRow(
                itemId: itemId,
                appleMusicPlaylistId: playlistId,
                lastSyncAt: attributeDict["last_sync_at"],
                useSnapshot: attributeDict["use_snapshot"] == "1"
            ))
        case "local_playlist_track":
            guard let id = attributeDict["id"],
                  let playlistItemId = attributeDict["playlist_item_id"],
                  let assetId = attributeDict["asset_id"],
                  let position = attributeDict["position"].flatMap(Int.init),
                  let title = attributeDict["title"] else { return }
            snapshot.localPlaylistTracks.append(LocalPlaylistTrackRow(
                id: id,
                playlistItemId: playlistItemId,
                assetId: assetId,
                position: position,
                title: title,
                artist: attributeDict["artist"],
                duration: attributeDict["duration"].flatMap(Double.init)
            ))
        case "volumes":
            snapshot.preferences.masterVolume = attributeDict["master"].flatMap(Double.init) ?? snapshot.preferences.masterVolume
            snapshot.preferences.musicVolume = attributeDict["music"].flatMap(Double.init) ?? snapshot.preferences.musicVolume
            snapshot.preferences.atmosphereVolume = attributeDict["atmosphere"].flatMap(Double.init) ?? snapshot.preferences.atmosphereVolume
            snapshot.preferences.sfxVolume = attributeDict["sfx"].flatMap(Double.init) ?? snapshot.preferences.sfxVolume
        case "loop":
            if let title = attributeDict["title"] {
                snapshot.preferences.loopBookmarks.append(title)
            }
        case "sfx":
            if let title = attributeDict["title"] {
                snapshot.preferences.sfxBookmarks.append(title)
            }
        case "ui":
            snapshot.preferences.hasCompletedSetup = attributeDict["has_completed_setup"] == "1"
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "item", let item = currentItem {
            snapshot.items.append(item)
            snapshot.itemTags.append(contentsOf: currentItemTags)
            currentItem = nil
            currentItemTags = []
        }
    }
}
