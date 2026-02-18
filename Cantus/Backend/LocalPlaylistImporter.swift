import Foundation
import GRDB
import AVFoundation

enum LocalPlaylistImportError: Error {
    case emptyName
    case noTracks
    case copyFailed
}

struct ImportedPlaylist {
    let itemId: String
    let title: String
    let trackCount: Int
}

struct LocalPlaylistImporter {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func importPlaylist(
        name: String,
        trackURLs: [URL],
        selectedTagIDs: [TagCategory: [Int64]]
    ) async throws -> ImportedPlaylist {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LocalPlaylistImportError.emptyName }
        guard !trackURLs.isEmpty else { throw LocalPlaylistImportError.noTracks }

        let now = ISO8601DateFormatter().string(from: Date())
        let itemId = UUID().uuidString
        let packId = UserImportPack.musicId.uuidString
        let normalizedTitle = trimmed

        var trackEntries: [LocalPlaylistTrackEntry] = []
        trackEntries.reserveCapacity(trackURLs.count)
        for (offset, url) in trackURLs.enumerated() {
            let metadata = await extractMetadata(from: url)
            trackEntries.append(
                LocalPlaylistTrackEntry(
                    sourceURL: url,
                    position: offset,
                    title: metadata.title,
                    artist: metadata.artist,
                    duration: metadata.duration
                )
            )
        }

        let finalTitle = try await dbQueue.write { db -> String in
            try upsertMusicImportPack(db: db, packId: packId, createdAt: now)
            let uniqueTitle = try uniqueTitle(db: db, base: normalizedTitle, kind: .music)
            let item = LibraryItemRow(
                id: itemId,
                kind: LibraryKind.music.rawValue,
                title: uniqueTitle,
                subtitle: "Local Playlist",
                duration: nil,
                artworkURL: nil,
                isVisible: true,
                containsMusic: true,
                createdAt: now,
                updatedAt: now
            )
            try item.insert(db)
            try insertMusicTags(db: db, itemId: itemId, selectedTagIDs: selectedTagIDs)
            return uniqueTitle
        }

        var importedCount = 0
        for entry in trackEntries {
            let assetInfo = try copyTrack(entry: entry, packId: packId)
            try await dbQueue.write { db in
                let assetRow = LocalAssetRow(
                    id: assetInfo.assetId,
                    packId: packId,
                    remoteURL: entry.sourceURL.absoluteString,
                    localPath: assetInfo.relativePath,
                    etag: nil,
                    sha256: nil,
                    bytesTotal: assetInfo.bytesTotal,
                    attributionAuthor: nil,
                    attributionSource: nil,
                    attributionLicense: nil,
                    attributionLicenseURL: nil,
                    createdAt: now
                )
                try assetRow.insert(db)

                let trackRow = LocalPlaylistTrackRow(
                    id: UUID().uuidString,
                    playlistItemId: itemId,
                    assetId: assetInfo.assetId,
                    position: entry.position,
                    title: entry.title,
                    artist: entry.artist,
                    duration: entry.duration
                )
                try trackRow.insert(db)
            }
            importedCount += 1
        }

        return ImportedPlaylist(itemId: itemId, title: finalTitle, trackCount: importedCount)
    }

    private func copyTrack(entry: LocalPlaylistTrackEntry, packId: String) throws -> (assetId: String, relativePath: String, bytesTotal: Int64?) {
        let access = entry.sourceURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                entry.sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let fileExtension = entry.sourceURL.pathExtension.isEmpty ? "m4a" : entry.sourceURL.pathExtension
        let assetId = UUID().uuidString
        let folder = AppFilePaths.applicationSupportURL().appendingPathComponent("AudioImports/\(packId)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destinationURL = folder.appendingPathComponent("\(assetId).\(fileExtension)")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        do {
            try FileManager.default.copyItem(at: entry.sourceURL, to: destinationURL)
        } catch {
            throw LocalPlaylistImportError.copyFailed
        }

        let bytesTotal = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? nil
        let relativePath = "AudioImports/\(packId)/\(assetId).\(fileExtension)"
        return (assetId, relativePath, bytesTotal)
    }

    private func upsertMusicImportPack(db: Database, packId: String, createdAt: String) throws {
        if try PackRow.fetchOne(db, key: packId) != nil {
            return
        }
        let pack = PackRow(
            id: packId,
            kind: PackKind.music.rawValue,
            title: "User Imports (Music)",
            description: "Imported by user",
            artworkURL: nil,
            version: 1,
            manifestURL: "local://imports/music",
            createdAt: createdAt
        )
        try pack.insert(db)
    }

    private func uniqueTitle(db: Database, base: String, kind: LibraryKind) throws -> String {
        let sql = "SELECT title FROM library_item WHERE kind = ? AND title LIKE ?"
        let like = "\(base)%"
        let existing = try String.fetchAll(db, SQLRequest(sql: sql, arguments: [kind.rawValue, like]))
        if !existing.contains(base) {
            return base
        }
        var counter = 2
        var candidate = "\(base) (\(counter))"
        while existing.contains(candidate) {
            counter += 1
            candidate = "\(base) (\(counter))"
        }
        return candidate
    }

    private func insertMusicTags(db: Database, itemId: String, selectedTagIDs: [TagCategory: [Int64]]) throws {
        func insert(_ table: String, _ column: String, _ ids: [Int64]) throws {
            guard !ids.isEmpty else { return }
            for id in ids {
                try db.execute(
                    sql: "INSERT INTO \(table) (item_id, \(column)) VALUES (?, ?) ON CONFLICT DO NOTHING",
                    arguments: [itemId, id]
                )
            }
        }

        try insert("item_location", "location_id", selectedTagIDs[.location] ?? [])
        try insert("item_mood", "mood_id", selectedTagIDs[.mood] ?? [])
        try insert("item_music_theme", "music_theme_id", selectedTagIDs[.musicTheme] ?? [])
    }

    private func normalizeTitle(_ raw: String) -> String {
        let replaced = raw
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let collapsed = replaced.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        return titleCasePreservingAcronyms(collapsed)
    }

    private func titleCasePreservingAcronyms(_ value: String) -> String {
        let lowercaseWords: Set<String> = [
            "a", "an", "and", "as", "at", "but", "by", "for", "from", "if",
            "in", "into", "nor", "of", "on", "or", "over", "per", "the",
            "to", "up", "via", "with"
        ]
        let words = value.split(separator: " ")
        let transformed = words.enumerated().map { index, word -> String in
            let raw = String(word)
            let upper = raw.uppercased()
            if raw.count > 1 && raw == upper {
                return upper
            }
            let lower = raw.lowercased()
            if index > 0 && lowercaseWords.contains(lower) {
                return lower
            }
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        return transformed.joined(separator: " ")
    }

    private struct LocalPlaylistTrackEntry {
        let sourceURL: URL
        let position: Int
        let title: String
        let artist: String?
        let duration: Double?
    }

    private struct LocalTrackMetadata {
        let title: String
        let artist: String?
        let duration: Double?
    }

    private func extractMetadata(from url: URL) async -> LocalTrackMetadata {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access {
                url.stopAccessingSecurityScopedResource()
            }
        }
        let asset = AVURLAsset(url: url)
        let duration = await loadDuration(from: asset)
        var title = url.deletingPathExtension().lastPathComponent
        var artist: String? = nil
        if let metadata = await loadMetadata(from: asset) {
            for item in metadata {
                guard let key = item.commonKey else { continue }
                if key == .commonKeyTitle, let value = await loadStringValue(from: item), !value.isEmpty {
                    title = value
                } else if key == .commonKeyArtist, let value = await loadStringValue(from: item), !value.isEmpty {
                    artist = value
                }
            }
        }

        return LocalTrackMetadata(
            title: normalizeTitle(title),
            artist: artist,
            duration: duration
        )
    }

    private func loadDuration(from asset: AVURLAsset) async -> Double? {
        do {
            let duration = try await asset.load(.duration)
            return duration.isNumeric ? duration.seconds : nil
        } catch {
            return nil
        }
    }

    private func loadMetadata(from asset: AVURLAsset) async -> [AVMetadataItem]? {
        do {
            return try await asset.load(.commonMetadata)
        } catch {
            return nil
        }
    }

    private func loadStringValue(from item: AVMetadataItem) async -> String? {
        do {
            return try await item.load(.stringValue)
        } catch {
            return nil
        }
    }
}
