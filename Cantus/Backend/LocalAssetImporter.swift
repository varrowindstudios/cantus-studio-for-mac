import Foundation
import GRDB

enum LocalAssetImportError: Error {
    case missingFileName
    case unsupportedKind
    case copyFailed
}

struct LocalAssetImporter {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func importAsset(from sourceURL: URL, kind: LibraryKind, selectedTagIDs: [TagCategory: [Int64]], containsMusic: Bool, preferredTitle: String?) async throws -> ImportedAsset {
        let access = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if access {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        guard !baseName.isEmpty else { throw LocalAssetImportError.missingFileName }
        let fileExtension = sourceURL.pathExtension.isEmpty ? "wav" : sourceURL.pathExtension

        let packId = UserImportPack.id(for: kind).uuidString
        let itemId = UUID().uuidString
        let assetId = UUID().uuidString
        let now = ISO8601DateFormatter().string(from: Date())

        let folder = AppFilePaths.applicationSupportURL().appendingPathComponent("AudioImports/\(packId)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destinationURL = folder.appendingPathComponent("\(assetId).\(fileExtension)")

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        do {
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            throw LocalAssetImportError.copyFailed
        }

        let bytesTotal = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? nil
        let relativePath = "AudioImports/\(packId)/\(assetId).\(fileExtension)"

        let normalized = normalizeTitle(preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? preferredTitle! : baseName)

        let finalTitle = try await dbQueue.write { db -> String in
            try upsertUserImportPack(db: db, packId: packId, kind: kind, createdAt: now)

            let title = try uniqueTitle(db: db, base: normalized, kind: kind)
            let libraryItem = LibraryItemRow(
                id: itemId,
                kind: kind.rawValue,
                title: title,
                subtitle: nil,
                duration: nil,
                artworkURL: nil,
                isVisible: true,
                containsMusic: kind == .atmosphere ? containsMusic : false,
                createdAt: now,
                updatedAt: now
            )
            try libraryItem.insert(db)

            let localAsset = LocalAssetRow(
                id: assetId,
                packId: packId,
                remoteURL: sourceURL.absoluteString,
                localPath: relativePath,
                etag: nil,
                sha256: nil,
                bytesTotal: bytesTotal,
                attributionAuthor: nil,
                attributionSource: nil,
                attributionLicense: nil,
                attributionLicenseURL: nil,
                createdAt: now
            )
            try localAsset.insert(db)

            let loopable = (kind == .atmosphere)
            let itemAudio = ItemLocalAudioRow(
                itemId: itemId,
                assetId: assetId,
                codec: fileExtension,
                sampleRate: nil,
                channels: nil,
                loopable: loopable
            )
            try itemAudio.insert(db)

            let nextOrder = try nextPackSortOrder(db: db, packId: packId)
            let packItem = PackItemRow(packId: packId, itemId: itemId, sortOrder: nextOrder)
            try packItem.insert(db)

            try insertTagJoins(db: db, itemId: itemId, selectedTagIDs: selectedTagIDs)

            return title
        }


        return ImportedAsset(
            itemId: itemId,
            title: finalTitle,
            localPath: relativePath
        )
    }

    func normalizedTitle(from sourceURL: URL) -> String {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        return normalizeTitle(baseName)
    }

    func normalizedTitle(from name: String) -> String {
        normalizeTitle(name)
    }

    private func upsertUserImportPack(db: Database, packId: String, kind: LibraryKind, createdAt: String) throws {
        if try PackRow.fetchOne(db, key: packId) != nil {
            return
        }
        let pack = PackRow(
            id: packId,
            kind: kind.rawValue,
            title: kind == .atmosphere ? "User Imports (Atmosphere)" : "User Imports (SFX)",
            description: "Imported by user",
            artworkURL: nil,
            version: 1,
            manifestURL: "local://imports/\(kind.rawValue)",
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

    private func normalizeTitle(_ raw: String) -> String {
        // Strip leading track numbers like "01 - " or "1_"
        let stripped = raw.replacingOccurrences(of: #"^\s*\d+\s*[-_. ]+\s*"#, with: "", options: .regularExpression)
        let replaced = stripped
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

    private func nextPackSortOrder(db: Database, packId: String) throws -> Int {
        let maxOrder = try Int.fetchOne(db, sql: "SELECT MAX(sort_order) FROM pack_item WHERE pack_id = ?", arguments: [packId]) ?? 0
        return maxOrder + 1
    }

    private func insertTagJoins(db: Database, itemId: String, selectedTagIDs: [TagCategory: [Int64]]) throws {
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
        try insert("item_atmosphere_theme", "atmosphere_theme_id", selectedTagIDs[.atmosphereTheme] ?? [])
        try insert("item_sfx_theme", "sfx_theme_id", selectedTagIDs[.sfxTheme] ?? [])
        try insert("item_creature_type", "creature_type_id", selectedTagIDs[.creatureType] ?? [])
    }
}

enum UserImportPack {
    static let atmosphereId = UUID(uuidString: "E2D1E8C8-2B1E-4B7E-9A4E-1F8D4F6C8A01")!
    static let sfxId = UUID(uuidString: "A6D9F3C1-6B4E-4D1A-9D1E-3C9F2E1B7A02")!
    static let musicId = UUID(uuidString: "5C33B8D0-4D3B-4A3C-9E0F-7C9B1F63A103")!

    static func id(for kind: LibraryKind) -> UUID {
        switch kind {
        case .atmosphere: return atmosphereId
        case .sfx: return sfxId
        case .music: return musicId
        }
    }
}

struct ImportedAsset {
    let itemId: String
    let title: String
    let localPath: String
}
