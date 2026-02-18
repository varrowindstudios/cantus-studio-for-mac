import Foundation
import GRDB

struct SeedImporter {
    private let dbQueue: DatabaseQueue
    private let fileManager = FileManager.default

    private static let defaultMusicPackId = "7B9FE5A1-0D4B-4E5E-82A2-6F2D33E5A101"
    private static let defaultAtmospherePackId = "7B9FE5A1-0D4B-4E5E-82A2-6F2D33E5A102"
    private static let defaultSFXPackId = "7B9FE5A1-0D4B-4E5E-82A2-6F2D33E5A103"
    private static let kevinMacLeodName = "Kevin MacLeod"
    private static let kevinMacLeodSource = "incompetech.com"
    private static let kevinMacLeodLicense = "Creative Commons: By Attribution 4.0"
    private static let kevinMacLeodLicenseURL = "http://creativecommons.org/licenses/by/4.0/"
    private static let varrowindStudiosName = "Varrowind Studios"
    private static let varrowindStudiosSource = "Varrowind Studios"
    private static let varrowindStudiosLicense = "Licensed under Creative Commons: By Attribution 4.0"
    private static let varrowindStudiosLicenseURL = "http://creativecommons.org/licenses/by/4.0/"

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func importIfNeeded() async throws {
        let shouldImportDefaultPack = try await dbQueue.read { db in
            let installedPackCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM pack WHERE id IN (?, ?, ?)",
                arguments: [Self.defaultMusicPackId, Self.defaultAtmospherePackId, Self.defaultSFXPackId]
            ) ?? 0
            return installedPackCount < 3
        }

        if shouldImportDefaultPack {
            try await applySeed()
            try await importDefaultSoundPack()
        }

        try await applyDefaultPackAttributionIfNeeded()
    }

    func applySeed() async throws {
        guard let url = Bundle.main.url(forResource: "seed_catalog", withExtension: "json") else {
            throw SeedError.missingSeedResource
        }
        let data = try Data(contentsOf: url)
        let catalog = try JSONDecoder().decode(SeedCatalog.self, from: data)

        try await dbQueue.write { db in
            try upsertDimensions(db: db, catalog: catalog)
        }

    }

    private func upsertDimensions(db: Database, catalog: SeedCatalog) throws {
        try upsertDimension(db: db, table: "location", values: catalog.locations)
        try upsertDimension(db: db, table: "mood", values: catalog.moods)
        try upsertDimension(db: db, table: "music_theme", values: catalog.musicThemes)
        try upsertDimension(db: db, table: "atmosphere_theme", values: catalog.atmosphereThemes)
        try upsertDimension(db: db, table: "sfx_theme", values: catalog.sfxThemes)
        try upsertDimension(db: db, table: "creature_type", values: catalog.creatureTypes)
    }

    private func upsertDimension(db: Database, table: String, values: [SeedDimension]) throws {
        for value in values {
            try db.execute(sql: "INSERT INTO \(table) (name, is_system, sort_order) VALUES (?, 1, ?) ON CONFLICT(name) DO NOTHING", arguments: [value.name, value.sortOrder])
        }
    }

    private func importDefaultSoundPack() async throws {
        guard let rootURL = Bundle.main.url(forResource: "DefaultSoundPack", withExtension: nil, subdirectory: "Audio") else {
            throw SeedError.missingDefaultSoundPackResource
        }

        let playlistDefinitions = try playlistDefinitions(from: rootURL.appendingPathComponent("Playlists", isDirectory: true))
        let atmosphereDefinitions = try assetDefinitions(from: rootURL.appendingPathComponent("Atmospheres", isDirectory: true))
        let sfxDefinitions = try assetDefinitions(from: rootURL.appendingPathComponent("Sound Effects", isDirectory: true))

        var copiedBySourcePath: [String: CopiedAudioFile] = [:]
        copiedBySourcePath.reserveCapacity(
            playlistDefinitions.reduce(0) { $0 + $1.tracks.count } + atmosphereDefinitions.count + sfxDefinitions.count
        )

        let playlistTrackURLs = playlistDefinitions.flatMap(\.tracks)
        let atmosphereURLs = atmosphereDefinitions.map(\.sourceURL)
        let sfxURLs = sfxDefinitions.map(\.sourceURL)

        for sourceURL in playlistTrackURLs + atmosphereURLs + sfxURLs {
            let copied = try copyBundledAudio(sourceURL: sourceURL, rootURL: rootURL)
            copiedBySourcePath[sourceURL.path] = copied
        }

        let musicBytes = playlistTrackURLs.compactMap { copiedBySourcePath[$0.path]?.bytes }.reduce(0, +)
        let atmosphereBytes = atmosphereURLs.compactMap { copiedBySourcePath[$0.path]?.bytes }.reduce(0, +)
        let sfxBytes = sfxURLs.compactMap { copiedBySourcePath[$0.path]?.bytes }.reduce(0, +)
        let now = ISO8601DateFormatter().string(from: Date())

        try await dbQueue.write { db in
            let existingItemIds = try String.fetchAll(
                db,
                sql: "SELECT DISTINCT item_id FROM pack_item WHERE pack_id IN (?, ?, ?)",
                arguments: [Self.defaultMusicPackId, Self.defaultAtmospherePackId, Self.defaultSFXPackId]
            )
            for itemId in existingItemIds {
                try db.execute(sql: "DELETE FROM library_item WHERE id = ?", arguments: [itemId])
            }
            try db.execute(
                sql: "DELETE FROM pack WHERE id IN (?, ?, ?)",
                arguments: [Self.defaultMusicPackId, Self.defaultAtmospherePackId, Self.defaultSFXPackId]
            )

            let musicPack = PackRow(
                id: Self.defaultMusicPackId,
                kind: PackKind.music.rawValue,
                title: "Cantus Default Playlists",
                description: "Bundled local playlists for immediate play.",
                artworkURL: nil,
                version: 1,
                manifestURL: "bundle://Audio/DefaultSoundPack/Playlists",
                createdAt: now
            )
            let atmospherePack = PackRow(
                id: Self.defaultAtmospherePackId,
                kind: PackKind.atmosphere.rawValue,
                title: "Cantus Default Atmospheres",
                description: "Bundled looping ambience for scenes and locations.",
                artworkURL: nil,
                version: 1,
                manifestURL: "bundle://Audio/DefaultSoundPack/Atmospheres",
                createdAt: now
            )
            let sfxPack = PackRow(
                id: Self.defaultSFXPackId,
                kind: PackKind.sfx.rawValue,
                title: "Cantus Default Sound Effects",
                description: "Bundled one-shot sound effects for encounters and actions.",
                artworkURL: nil,
                version: 1,
                manifestURL: "bundle://Audio/DefaultSoundPack/Sound Effects",
                createdAt: now
            )

            try musicPack.save(db)
            try atmospherePack.save(db)
            try sfxPack.save(db)

            var musicSortOrder = 1
            for playlist in playlistDefinitions {
                let itemId = UUID().uuidString
                let title = try uniqueTitle(db: db, base: playlist.title, kind: .music)
                let item = LibraryItemRow(
                    id: itemId,
                    kind: LibraryKind.music.rawValue,
                    title: title,
                    subtitle: playlist.category,
                    duration: nil,
                    artworkURL: nil,
                    isVisible: true,
                    containsMusic: true,
                    createdAt: now,
                    updatedAt: now
                )
                try item.insert(db)
                try PackItemRow(packId: Self.defaultMusicPackId, itemId: itemId, sortOrder: musicSortOrder).insert(db)
                musicSortOrder += 1
                try insertTagSet(db: db, itemId: itemId, kind: .music, tags: playlistTagSet(category: playlist.category, playlist: playlist.title))

                for (position, trackURL) in playlist.tracks.enumerated() {
                    guard let copied = copiedBySourcePath[trackURL.path] else { continue }
                    let metadata = trackMetadata(from: trackURL)
                    let attribution = attributionMetadata(forArtist: metadata.artist)
                    let asset = LocalAssetRow(
                        id: UUID().uuidString,
                        packId: Self.defaultMusicPackId,
                        remoteURL: copied.sourceURL.absoluteString,
                        localPath: copied.localPath,
                        etag: nil,
                        sha256: nil,
                        bytesTotal: copied.bytes,
                        attributionAuthor: attribution?.author,
                        attributionSource: attribution?.source,
                        attributionLicense: attribution?.license,
                        attributionLicenseURL: attribution?.licenseURL,
                        createdAt: now
                    )
                    try asset.insert(db)
                    let track = LocalPlaylistTrackRow(
                        id: UUID().uuidString,
                        playlistItemId: itemId,
                        assetId: asset.id,
                        position: position,
                        title: metadata.title,
                        artist: metadata.artist,
                        duration: nil
                    )
                    try track.insert(db)
                }
            }

            var atmosphereSortOrder = 1
            for definition in atmosphereDefinitions {
                guard let copied = copiedBySourcePath[definition.sourceURL.path] else { continue }
                let itemId = UUID().uuidString
                let title = try uniqueTitle(db: db, base: definition.title, kind: .atmosphere)
                let item = LibraryItemRow(
                    id: itemId,
                    kind: LibraryKind.atmosphere.rawValue,
                    title: title,
                    subtitle: nil,
                    duration: nil,
                    artworkURL: nil,
                    isVisible: true,
                    containsMusic: false,
                    createdAt: now,
                    updatedAt: now
                )
                try item.insert(db)
                try PackItemRow(packId: Self.defaultAtmospherePackId, itemId: itemId, sortOrder: atmosphereSortOrder).insert(db)
                atmosphereSortOrder += 1
                try insertTagSet(db: db, itemId: itemId, kind: .atmosphere, tags: atmosphereTagSet(for: definition.title))

                let asset = LocalAssetRow(
                    id: UUID().uuidString,
                    packId: Self.defaultAtmospherePackId,
                    remoteURL: copied.sourceURL.absoluteString,
                    localPath: copied.localPath,
                    etag: nil,
                    sha256: nil,
                    bytesTotal: copied.bytes,
                    attributionAuthor: Self.varrowindStudiosName,
                    attributionSource: Self.varrowindStudiosSource,
                    attributionLicense: Self.varrowindStudiosLicense,
                    attributionLicenseURL: Self.varrowindStudiosLicenseURL,
                    createdAt: now
                )
                try asset.insert(db)
                try ItemLocalAudioRow(
                    itemId: itemId,
                    assetId: asset.id,
                    codec: definition.sourceURL.pathExtension.lowercased(),
                    sampleRate: nil,
                    channels: nil,
                    loopable: true
                ).insert(db)
            }

            var sfxSortOrder = 1
            for definition in sfxDefinitions {
                guard let copied = copiedBySourcePath[definition.sourceURL.path] else { continue }
                let itemId = UUID().uuidString
                let title = try uniqueTitle(db: db, base: definition.title, kind: .sfx)
                let item = LibraryItemRow(
                    id: itemId,
                    kind: LibraryKind.sfx.rawValue,
                    title: title,
                    subtitle: nil,
                    duration: nil,
                    artworkURL: nil,
                    isVisible: true,
                    containsMusic: false,
                    createdAt: now,
                    updatedAt: now
                )
                try item.insert(db)
                try PackItemRow(packId: Self.defaultSFXPackId, itemId: itemId, sortOrder: sfxSortOrder).insert(db)
                sfxSortOrder += 1
                try insertTagSet(db: db, itemId: itemId, kind: .sfx, tags: sfxTagSet(for: definition.title))

                let asset = LocalAssetRow(
                    id: UUID().uuidString,
                    packId: Self.defaultSFXPackId,
                    remoteURL: copied.sourceURL.absoluteString,
                    localPath: copied.localPath,
                    etag: nil,
                    sha256: nil,
                    bytesTotal: copied.bytes,
                    attributionAuthor: Self.varrowindStudiosName,
                    attributionSource: Self.varrowindStudiosSource,
                    attributionLicense: Self.varrowindStudiosLicense,
                    attributionLicenseURL: Self.varrowindStudiosLicenseURL,
                    createdAt: now
                )
                try asset.insert(db)
                try ItemLocalAudioRow(
                    itemId: itemId,
                    assetId: asset.id,
                    codec: definition.sourceURL.pathExtension.lowercased(),
                    sampleRate: nil,
                    channels: nil,
                    loopable: false
                ).insert(db)
            }

            try PackStateRow(
                packId: Self.defaultMusicPackId,
                state: PackInstallState.downloaded.rawValue,
                bytesTotal: musicBytes,
                bytesDownloaded: musicBytes,
                installedVersion: 1,
                lastError: nil,
                updatedAt: now
            ).save(db)
            try PackStateRow(
                packId: Self.defaultAtmospherePackId,
                state: PackInstallState.downloaded.rawValue,
                bytesTotal: atmosphereBytes,
                bytesDownloaded: atmosphereBytes,
                installedVersion: 1,
                lastError: nil,
                updatedAt: now
            ).save(db)
            try PackStateRow(
                packId: Self.defaultSFXPackId,
                state: PackInstallState.downloaded.rawValue,
                bytesTotal: sfxBytes,
                bytesDownloaded: sfxBytes,
                installedVersion: 1,
                lastError: nil,
                updatedAt: now
            ).save(db)
        }
    }

    private func playlistDefinitions(from rootURL: URL) throws -> [DefaultPlaylistDefinition] {
        let categoryURLs = try childDirectories(at: rootURL)
        var definitions: [DefaultPlaylistDefinition] = []
        for categoryURL in categoryURLs {
            let categoryName = categoryURL.lastPathComponent
            let playlistURLs = try childDirectories(at: categoryURL)
            for playlistURL in playlistURLs {
                let tracks = try audioFiles(at: playlistURL)
                guard !tracks.isEmpty else { continue }
                definitions.append(
                    DefaultPlaylistDefinition(
                        category: categoryName,
                        title: playlistURL.lastPathComponent,
                        tracks: tracks
                    )
                )
            }
        }
        return definitions
    }

    private func assetDefinitions(from rootURL: URL) throws -> [DefaultAssetDefinition] {
        try audioFiles(at: rootURL).map { url in
            DefaultAssetDefinition(
                title: cleanedTitle(fromFileURL: url),
                sourceURL: url
            )
        }
    }

    private func childDirectories(at url: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        return try fileManager
            .contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            .filter { child in
                guard let values = try? child.resourceValues(forKeys: Set(keys)) else { return false }
                return values.isDirectory == true
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    private func audioFiles(at url: URL) throws -> [URL] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isRegularFileKey]
        let allowed: Set<String> = ["mp3", "wav", "m4a", "aac", "aif", "aiff", "caf"]
        return try fileManager
            .contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            .filter { file in
                guard let values = try? file.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true else {
                    return false
                }
                return allowed.contains(file.pathExtension.lowercased())
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }
    }

    private func copyBundledAudio(sourceURL: URL, rootURL: URL) throws -> CopiedAudioFile {
        let relative = relativePath(from: rootURL, to: sourceURL)
        let localPath = "AudioDefaults/DefaultSoundPack/\(relative)"
        let destinationURL = AppFilePaths.applicationSupportURL().appendingPathComponent(localPath)
        try fileManager.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        let bytes = (try? fileManager.attributesOfItem(atPath: destinationURL.path)[.size] as? Int64) ?? 0
        return CopiedAudioFile(localPath: localPath, sourceURL: sourceURL, bytes: bytes)
    }

    private func relativePath(from rootURL: URL, to fileURL: URL) -> String {
        let prefix = rootURL.path.hasSuffix("/") ? rootURL.path : rootURL.path + "/"
        if fileURL.path.hasPrefix(prefix) {
            return String(fileURL.path.dropFirst(prefix.count))
        }
        return fileURL.lastPathComponent
    }

    private func cleanedTitle(fromFileURL fileURL: URL) -> String {
        normalizeDisplayName(fileURL.deletingPathExtension().lastPathComponent, stripKevinPrefix: true)
    }

    private func trackMetadata(from fileURL: URL) -> (title: String, artist: String?) {
        let base = fileURL.deletingPathExtension().lastPathComponent
        if let separator = base.range(of: " - ") {
            let artist = String(base[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let rawTitle = String(base[separator.upperBound...])
            let title = normalizeDisplayName(rawTitle, stripKevinPrefix: false)
            return (title: title, artist: artist.isEmpty ? nil : artist)
        }
        return (title: normalizeDisplayName(base, stripKevinPrefix: true), artist: nil)
    }

    private func attributionMetadata(forArtist artist: String?) -> AttributionMetadata? {
        guard let artist else { return nil }
        if artist.caseInsensitiveCompare(Self.kevinMacLeodName) == .orderedSame {
            return AttributionMetadata(
                author: Self.kevinMacLeodName,
                source: Self.kevinMacLeodSource,
                license: Self.kevinMacLeodLicense,
                licenseURL: Self.kevinMacLeodLicenseURL
            )
        }
        return nil
    }

    private func normalizeDisplayName(_ value: String, stripKevinPrefix: Bool) -> String {
        var name = value
        if stripKevinPrefix, name.hasPrefix("Kevin MacLeod - ") {
            name = String(name.dropFirst("Kevin MacLeod - ".count))
        }
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "(?<=[a-z])(?=[A-Z])", with: " ", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func applyDefaultPackAttributionIfNeeded() async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE local_asset
                SET
                    attribution_author = ?,
                    attribution_source = ?,
                    attribution_license = ?,
                    attribution_license_url = ?
                WHERE id IN (
                    SELECT lpt.asset_id
                    FROM local_playlist_track lpt
                    JOIN local_asset la ON la.id = lpt.asset_id
                    WHERE la.pack_id = ?
                      AND (
                        lower(COALESCE(lpt.artist, '')) = lower(?)
                        OR lower(COALESCE(la.local_path, '')) LIKE lower(?)
                      )
                )
                """,
                arguments: [
                    Self.kevinMacLeodName,
                    Self.kevinMacLeodSource,
                    Self.kevinMacLeodLicense,
                    Self.kevinMacLeodLicenseURL,
                    Self.defaultMusicPackId,
                    Self.kevinMacLeodName,
                    "%kevin macleod - %"
                ]
            )

            try db.execute(
                sql: """
                UPDATE local_asset
                SET
                    attribution_author = ?,
                    attribution_source = ?,
                    attribution_license = ?,
                    attribution_license_url = ?
                WHERE pack_id IN (?, ?)
                """,
                arguments: [
                    Self.varrowindStudiosName,
                    Self.varrowindStudiosSource,
                    Self.varrowindStudiosLicense,
                    Self.varrowindStudiosLicenseURL,
                    Self.defaultAtmospherePackId,
                    Self.defaultSFXPackId
                ]
            )
        }
    }

    private func insertTagSet(db: Database, itemId: String, kind: LibraryKind, tags: InferredTagSet) throws {
        let normalized = normalizeTags(tags)
        try insertTagNames(db: db, itemId: itemId, table: "item_location", joinColumn: "location_id", dimensionTable: "location", names: normalized.locations)
        try insertTagNames(db: db, itemId: itemId, table: "item_mood", joinColumn: "mood_id", dimensionTable: "mood", names: normalized.moods)
        switch kind {
        case .music:
            try insertTagNames(db: db, itemId: itemId, table: "item_music_theme", joinColumn: "music_theme_id", dimensionTable: "music_theme", names: normalized.themes)
        case .atmosphere:
            try insertTagNames(db: db, itemId: itemId, table: "item_atmosphere_theme", joinColumn: "atmosphere_theme_id", dimensionTable: "atmosphere_theme", names: normalized.themes)
        case .sfx:
            try insertTagNames(db: db, itemId: itemId, table: "item_sfx_theme", joinColumn: "sfx_theme_id", dimensionTable: "sfx_theme", names: normalized.themes)
            try insertTagNames(db: db, itemId: itemId, table: "item_creature_type", joinColumn: "creature_type_id", dimensionTable: "creature_type", names: normalized.creatureTypes)
        }
    }

    private func insertTagNames(
        db: Database,
        itemId: String,
        table: String,
        joinColumn: String,
        dimensionTable: String,
        names: [String]
    ) throws {
        guard !names.isEmpty else { return }
        for name in names {
            let id = try dimensionId(db: db, table: dimensionTable, name: name)
            try db.execute(
                sql: "INSERT INTO \(table) (item_id, \(joinColumn)) VALUES (?, ?) ON CONFLICT DO NOTHING",
                arguments: [itemId, id]
            )
        }
    }

    private func normalizeTags(_ tags: InferredTagSet) -> InferredTagSet {
        InferredTagSet(
            locations: uniqueLimited(tags.locations, limit: 2),
            moods: uniqueLimited(tags.moods, limit: 2),
            themes: uniqueLimited(tags.themes, limit: 3),
            creatureTypes: uniqueLimited(tags.creatureTypes, limit: 1)
        )
    }

    private func uniqueLimited(_ values: [String], limit: Int) -> [String] {
        var output: [String] = []
        var seen: Set<String> = []
        for value in values {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard !seen.contains(key) else { continue }
            output.append(trimmed)
            seen.insert(key)
            if output.count >= limit {
                break
            }
        }
        return output
    }

    private func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func playlistTagSet(category: String, playlist: String) -> InferredTagSet {
        var tags = InferredTagSet()
        switch normalizedKey(category) {
        case "adventuring travel":
            tags.locations += ["Forest", "Mountain"]
            tags.moods += ["Curious", "Lighthearted"]
            tags.themes += ["Adventure / Travel"]
        case "town tavern social":
            tags.locations += ["Urban"]
            tags.moods += ["Cozy", "Lighthearted"]
            tags.themes += ["Town / Tavern"]
        case "danger dungeon horror":
            tags.locations += ["Underdark"]
            tags.moods += ["Ominous", "Suspenseful"]
            tags.themes += ["Dungeon / Horror"]
        default:
            break
        }

        switch normalizedKey(playlist) {
        case "maps on the tavern table":
            tags.locations += ["Urban"]
            tags.moods += ["Investigative"]
            tags.themes += ["Mystery / Investigation"]
        case "rain on the cloaks":
            tags.locations += ["Coastal", "Urban"]
            tags.moods += ["Mysterious"]
            tags.themes += ["Mystery / Investigation"]
        case "through the greenfire pines":
            tags.locations += ["Forest"]
            tags.moods += ["Mysterious"]
        case "ridgewalkers":
            tags.locations += ["Mountain"]
            tags.moods += ["Suspenseful"]
        case "lanternlight waltz":
            tags.themes += ["Courtly / Noble"]
        case "noble house strings":
            tags.themes += ["Courtly / Noble"]
            tags.moods += ["Mysterious"]
        case "back alley dice":
            tags.themes += ["Mystery / Investigation"]
            tags.moods += ["Mysterious", "Investigative"]
        case "after closing":
            tags.moods += ["Mysterious"]
            tags.themes += ["Mystery / Investigation"]
        case "initiative":
            tags.themes += ["Combat / Battle"]
            tags.moods += ["Heroic"]
        case "trapwire heartbeat":
            tags.themes += ["Mystery / Investigation"]
            tags.moods += ["Investigative"]
        case "victorious endings":
            tags.themes += ["Combat / Battle", "Adventure / Travel"]
            tags.moods += ["Triumphant"]
        default:
            break
        }
        return tags
    }

    private func atmosphereTagSet(for title: String) -> InferredTagSet {
        switch normalizedKey(title) {
        case "busy marketplace":
            return InferredTagSet(
                locations: ["Urban"],
                moods: ["Curious", "Lighthearted"],
                themes: ["Marketplace / Crowd", "Tavern / Room Tone"],
                creatureTypes: []
            )
        case "crowded room":
            return InferredTagSet(
                locations: ["Urban"],
                moods: ["Cozy", "Lighthearted"],
                themes: ["Tavern / Room Tone"],
                creatureTypes: []
            )
        case "damp sewers":
            return InferredTagSet(
                locations: ["Urban", "Underdark"],
                moods: ["Ominous", "Suspenseful"],
                themes: ["Urban / Sewers", "Dungeon / Cavern"],
                creatureTypes: []
            )
        case "dark cavern":
            return InferredTagSet(
                locations: ["Underdark"],
                moods: ["Ominous", "Suspenseful"],
                themes: ["Dungeon / Cavern"],
                creatureTypes: []
            )
        case "mucky swamp":
            return InferredTagSet(
                locations: ["Swamp"],
                moods: ["Mysterious", "Ominous"],
                themes: ["Wilderness / Wetlands"],
                creatureTypes: []
            )
        case "sunny forest":
            return InferredTagSet(
                locations: ["Forest"],
                moods: ["Cozy", "Curious"],
                themes: ["Wilderness / Forest"],
                creatureTypes: []
            )
        case "creepy drone":
            return InferredTagSet(
                locations: ["Underdark"],
                moods: ["Ominous", "Suspenseful"],
                themes: ["Haunting / Paranormal", "Dungeon / Cavern"],
                creatureTypes: []
            )
        default:
            return InferredTagSet(
                locations: ["Underdark"],
                moods: ["Mysterious", "Suspenseful"],
                themes: ["Haunting / Paranormal"],
                creatureTypes: []
            )
        }
    }

    private func sfxTagSet(for title: String) -> InferredTagSet {
        let key = normalizedKey(title)
        var tags = InferredTagSet()

        if key.contains("beast") || key.contains("dragon") || key.contains("insects") {
            tags.locations += ["Forest", "Mountain"]
            tags.moods += ["Ominous", "Suspenseful"]
            tags.themes += ["Monsters & Beasts"]
            if key.contains("dragon") {
                tags.creatureTypes += ["Dragon"]
            } else {
                tags.creatureTypes += ["Beast"]
            }
        }

        if key.contains("magic") || key.contains("magical") || key.contains("electrical") {
            tags.locations += ["Underdark"]
            tags.moods += ["Mysterious", "Suspenseful"]
            tags.themes += ["Magic"]
        }

        if key.contains("fire") || key.contains("fiery") {
            tags.locations += ["Mountain"]
            tags.moods += ["Ominous", "Suspenseful"]
            tags.themes += ["Fire & Heat"]
        }

        if key.contains("door") || key.contains("lock") || key.contains("mechanism") {
            tags.locations += ["Urban"]
            tags.moods += ["Investigative", "Suspenseful"]
            tags.themes += ["Doors & Mechanisms"]
        }

        if key.contains("running") || key.contains("footstep") {
            tags.locations += ["Urban"]
            tags.moods += ["Suspenseful", "Investigative"]
            tags.themes += ["Footsteps"]
        }

        if key.contains("arrow") {
            tags.locations += ["Forest"]
            tags.moods += ["Suspenseful", "Ominous"]
            tags.themes += ["Combat Impacts", "Ranged Weapons"]
        }

        if key.contains("blade") || key.contains("sword") || key.contains("blunt") || key.contains("impact") || key.contains("whip") {
            tags.locations += ["Urban"]
            tags.moods += ["Suspenseful", "Ominous"]
            tags.themes += ["Combat Impacts"]
        }

        if key.contains("gunshot") {
            tags.locations += ["Urban"]
            tags.moods += ["Suspenseful", "Ominous"]
            tags.themes += ["Combat Impacts", "Firearms"]
        }

        if tags.locations.isEmpty {
            tags.locations = ["Urban"]
        }
        if tags.moods.isEmpty {
            tags.moods = ["Suspenseful", "Mysterious"]
        }
        if tags.themes.isEmpty {
            tags.themes = ["Combat Impacts"]
        }

        return tags
    }

    private func uniqueTitle(db: Database, base: String, kind: LibraryKind) throws -> String {
        let existing = try String.fetchAll(
            db,
            sql: "SELECT title FROM library_item WHERE kind = ? AND title LIKE ?",
            arguments: [kind.rawValue, "\(base)%"]
        )
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

    private struct DefaultPlaylistDefinition {
        let category: String
        let title: String
        let tracks: [URL]
    }

    private struct DefaultAssetDefinition {
        let title: String
        let sourceURL: URL
    }

    private struct CopiedAudioFile {
        let localPath: String
        let sourceURL: URL
        let bytes: Int64
    }

    private struct AttributionMetadata {
        let author: String
        let source: String
        let license: String
        let licenseURL: String
    }

    private struct InferredTagSet {
        var locations: [String] = []
        var moods: [String] = []
        var themes: [String] = []
        var creatureTypes: [String] = []
    }

    private func upsertLibraryItems(db: Database, catalog: SeedCatalog) throws {
        for item in catalog.libraryItems {
            let row = LibraryItemRow(
                id: item.id,
                kind: item.kind,
                title: item.title,
                subtitle: item.subtitle,
                duration: item.duration,
                artworkURL: item.artworkURL,
                isVisible: item.isVisible,
                containsMusic: item.containsMusic ?? false,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt
            )
            try row.save(db)
        }
    }

    private func upsertMusicRefs(db: Database, catalog: SeedCatalog) throws {
        for music in catalog.musicPlaylists {
            let row = MusicPlaylistRefRow(
                itemId: music.itemId,
                appleMusicPlaylistId: music.appleMusicPlaylistId,
                lastSyncAt: nil,
                useSnapshot: music.useSnapshot
            )
            try row.save(db)
        }
    }

    private func upsertPacks(db: Database, catalog: SeedCatalog) throws {
        for pack in catalog.packs {
            let row = PackRow(
                id: pack.id,
                kind: pack.kind,
                title: pack.title,
                description: pack.description,
                artworkURL: pack.artworkURL,
                version: pack.version,
                manifestURL: pack.manifestURL,
                createdAt: pack.createdAt
            )
            try row.save(db)
        }
    }

    private func upsertPackItems(db: Database, catalog: SeedCatalog) throws {
        for packItem in catalog.packItems {
            let row = PackItemRow(
                packId: packItem.packId,
                itemId: packItem.itemId,
                sortOrder: packItem.sortOrder
            )
            try row.save(db)
        }
    }

    private func upsertTagJoins(db: Database, catalog: SeedCatalog) throws {
        for item in catalog.itemTags {
            let itemId = item.itemId
            try insertTagJoins(db: db, itemId: itemId, table: "item_location", dimensionTable: "location", dimensionIds: item.locations)
            try insertTagJoins(db: db, itemId: itemId, table: "item_mood", dimensionTable: "mood", dimensionIds: item.moods)
            try insertTagJoins(db: db, itemId: itemId, table: "item_music_theme", dimensionTable: "music_theme", dimensionIds: item.musicThemes)
            try insertTagJoins(db: db, itemId: itemId, table: "item_atmosphere_theme", dimensionTable: "atmosphere_theme", dimensionIds: item.atmosphereThemes)
            try insertTagJoins(db: db, itemId: itemId, table: "item_sfx_theme", dimensionTable: "sfx_theme", dimensionIds: item.sfxThemes)
            try insertTagJoins(db: db, itemId: itemId, table: "item_creature_type", dimensionTable: "creature_type", dimensionIds: item.creatureTypes)
        }
    }

    private func insertTagJoins(db: Database, itemId: String, table: String, dimensionTable: String, dimensionIds: [SeedTagValue]) throws {
        guard !dimensionIds.isEmpty else { return }
        let idColumn = "\(dimensionTable)_id"
        for tag in dimensionIds {
            let id = try dimensionId(db: db, table: dimensionTable, name: tag.name)
            try db.execute(sql: "INSERT INTO \(table) (item_id, \(idColumn)) VALUES (?, ?) ON CONFLICT DO NOTHING", arguments: [itemId, id])
        }
    }

    private func dimensionId(db: Database, table: String, name: String) throws -> Int64 {
        if let id = try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE name = ?", arguments: [name]) {
            return id
        }
        try db.execute(sql: "INSERT INTO \(table) (name, is_system) VALUES (?, 1) ON CONFLICT(name) DO NOTHING", arguments: [name])
        return try Int64.fetchOne(db, sql: "SELECT id FROM \(table) WHERE name = ?", arguments: [name]) ?? 0
    }
}

enum SeedError: Error {
    case missingSeedResource
    case missingDefaultSoundPackResource
}

struct SeedCatalog: Codable {
    let locations: [SeedDimension]
    let moods: [SeedDimension]
    let musicThemes: [SeedDimension]
    let atmosphereThemes: [SeedDimension]
    let sfxThemes: [SeedDimension]
    let creatureTypes: [SeedDimension]
    let libraryItems: [SeedLibraryItem]
    let musicPlaylists: [SeedMusicPlaylist]
    let packs: [SeedPack]
    let packItems: [SeedPackItem]
    let itemTags: [SeedItemTags]
}

struct SeedDimension: Codable {
    let name: String
    let sortOrder: Int?
}

struct SeedLibraryItem: Codable {
    let id: String
    let kind: String
    let title: String
    let subtitle: String?
    let duration: Double?
    let artworkURL: String?
    let isVisible: Bool
    let containsMusic: Bool?
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
}

struct SeedMusicPlaylist: Codable {
    let itemId: String
    let appleMusicPlaylistId: String
    let useSnapshot: Bool

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case appleMusicPlaylistId = "apple_music_playlist_id"
        case useSnapshot = "use_snapshot"
    }
}

struct SeedPack: Codable {
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

struct SeedPackItem: Codable {
    let packId: String
    let itemId: String
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case packId = "pack_id"
        case itemId = "item_id"
        case sortOrder = "sort_order"
    }
}

struct SeedItemTags: Codable {
    let itemId: String
    let locations: [SeedTagValue]
    let moods: [SeedTagValue]
    let musicThemes: [SeedTagValue]
    let atmosphereThemes: [SeedTagValue]
    let sfxThemes: [SeedTagValue]
    let creatureTypes: [SeedTagValue]

    enum CodingKeys: String, CodingKey {
        case itemId = "item_id"
        case locations
        case moods
        case musicThemes = "music_themes"
        case atmosphereThemes = "atmosphere_themes"
        case sfxThemes = "sfx_themes"
        case creatureTypes = "creature_types"
    }
}

struct SeedTagValue: Codable {
    let name: String
}
