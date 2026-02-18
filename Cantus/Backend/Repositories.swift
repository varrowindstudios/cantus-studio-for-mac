import Foundation
import GRDB
import MusicKit

struct ItemDetail {
    let item: LibraryItemRow
    let locations: [TagValue]
    let moods: [TagValue]
    let musicThemes: [TagValue]
    let atmosphereThemes: [TagValue]
    let sfxThemes: [TagValue]
    let creatureTypes: [TagValue]
    let availability: ItemAvailability
}

enum ItemAvailability {
    case available
    case unavailable
}

struct FacetCounts {
    let locations: [(TagValue, Int)]
    let moods: [(TagValue, Int)]
    let musicThemes: [(TagValue, Int)]
    let atmosphereThemes: [(TagValue, Int)]
    let sfxThemes: [(TagValue, Int)]
    let creatureTypes: [(TagValue, Int)]
}

struct PackWithState {
    let pack: PackRow
    let state: PackStateRow?
}

struct PackDetail {
    let pack: PackRow
    let state: PackStateRow?
    let items: [LibraryItemRow]
}

struct MusicEntry {
    let item: LibraryItemRow
    let playlistRef: MusicPlaylistRefRow
}

struct LocalPlaylistTrack {
    let id: String
    let playlistItemId: String
    let assetId: String
    let position: Int
    let title: String
    let artist: String?
    let duration: Double?
    let localPath: String
}

struct ItemAttributionGroup {
    let titles: [String]
    let author: String
    let source: String?
    let license: String?
    let licenseURL: String?
}

final class LibraryRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func fetchItems(kind: LibraryKind, filters: Filters, sort: LibrarySort) async throws -> [LibraryItemRow] {
        try await dbQueue.read { db in
            let (sql, args) = LibraryRepository.buildItemsQuery(kind: kind, filters: filters, sort: sort)
            return try LibraryItemRow.fetchAll(db, SQLRequest(sql: sql, arguments: args))
        }
    }

    func fetchItemDetail(itemId: UUID) async throws -> ItemDetail {
        try await dbQueue.read { db in
            guard let item = try LibraryItemRow.fetchOne(db, key: itemId.uuidString) else {
                throw RepositoryError.notFound
            }
            let locations = try Self.fetchTagValues(db, dimension: "location", joinTable: "item_location", joinColumn: "location_id", itemId: item.id)
            let moods = try Self.fetchTagValues(db, dimension: "mood", joinTable: "item_mood", joinColumn: "mood_id", itemId: item.id)
            let musicThemes = try Self.fetchTagValues(db, dimension: "music_theme", joinTable: "item_music_theme", joinColumn: "music_theme_id", itemId: item.id)
            let atmosphereThemes = try Self.fetchTagValues(db, dimension: "atmosphere_theme", joinTable: "item_atmosphere_theme", joinColumn: "atmosphere_theme_id", itemId: item.id)
            let sfxThemes = try Self.fetchTagValues(db, dimension: "sfx_theme", joinTable: "item_sfx_theme", joinColumn: "sfx_theme_id", itemId: item.id)
            let creatureTypes = try Self.fetchTagValues(db, dimension: "creature_type", joinTable: "item_creature_type", joinColumn: "creature_type_id", itemId: item.id)
            let availability = try Self.checkAvailability(db, itemId: item.id)
            return ItemDetail(
                item: item,
                locations: locations,
                moods: moods,
                musicThemes: musicThemes,
                atmosphereThemes: atmosphereThemes,
                sfxThemes: sfxThemes,
                creatureTypes: creatureTypes,
                availability: availability
            )
        }
    }

    func fetchItemAttributions(itemId: UUID) async throws -> [ItemAttributionGroup] {
        struct AttributionRow: FetchableRecord, Decodable {
            let assetTitle: String?
            let author: String?
            let source: String?
            let license: String?
            let licenseURL: String?

            enum CodingKeys: String, CodingKey {
                case assetTitle = "asset_title"
                case author = "attribution_author"
                case source = "attribution_source"
                case license = "attribution_license"
                case licenseURL = "attribution_license_url"
            }
        }

        struct AttributionKey: Hashable {
            let author: String
            let source: String?
            let license: String?
            let licenseURL: String?
        }

        return try await dbQueue.read { db in
            let rows = try AttributionRow.fetchAll(
                db,
                sql: """
                SELECT
                    lpt.title AS asset_title,
                    la.attribution_author,
                    la.attribution_source,
                    la.attribution_license,
                    la.attribution_license_url,
                    lpt.position AS sort_order,
                    0 AS source_rank
                FROM local_playlist_track lpt
                JOIN local_asset la ON la.id = lpt.asset_id
                WHERE lpt.playlist_item_id = ?

                UNION ALL

                SELECT
                    li.title AS asset_title,
                    la.attribution_author,
                    la.attribution_source,
                    la.attribution_license,
                    la.attribution_license_url,
                    0 AS sort_order,
                    1 AS source_rank
                FROM item_local_audio ila
                JOIN local_asset la ON la.id = ila.asset_id
                JOIN library_item li ON li.id = ila.item_id
                WHERE ila.item_id = ?

                ORDER BY source_rank ASC, sort_order ASC, asset_title COLLATE NOCASE ASC
                """,
                arguments: [itemId.uuidString, itemId.uuidString]
            )

            var groupsByKey: [AttributionKey: [String]] = [:]
            var keyOrder: [AttributionKey] = []

            for row in rows {
                let author = row.author?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                guard !author.isEmpty else { continue }

                let source = row.source?.trimmingCharacters(in: .whitespacesAndNewlines)
                let license = row.license?.trimmingCharacters(in: .whitespacesAndNewlines)
                let licenseURL = row.licenseURL?.trimmingCharacters(in: .whitespacesAndNewlines)

                let key = AttributionKey(
                    author: author,
                    source: source?.isEmpty == true ? nil : source,
                    license: license?.isEmpty == true ? nil : license,
                    licenseURL: licenseURL?.isEmpty == true ? nil : licenseURL
                )
                if groupsByKey[key] == nil {
                    groupsByKey[key] = []
                    keyOrder.append(key)
                }

                let title = row.assetTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !title.isEmpty, !(groupsByKey[key]?.contains(title) ?? false) {
                    groupsByKey[key, default: []].append(title)
                }
            }

            return keyOrder.map { key in
                ItemAttributionGroup(
                    titles: groupsByKey[key] ?? [],
                    author: key.author,
                    source: key.source,
                    license: key.license,
                    licenseURL: key.licenseURL
                )
            }
        }
    }

    func deleteItem(itemId: UUID) async throws {
        let id = itemId.uuidString
        let paths = try await dbQueue.read { db in
            try String.fetchAll(
                db,
                sql: """
                SELECT DISTINCT local_asset.local_path
                FROM local_asset
                LEFT JOIN item_local_audio ila ON ila.asset_id = local_asset.id
                LEFT JOIN local_playlist_track lpt ON lpt.asset_id = local_asset.id
                WHERE ila.item_id = ? OR lpt.playlist_item_id = ?
                """,
                arguments: [id, id]
            )
        }

        try await dbQueue.write { db in
            try db.execute(sql: "DELETE FROM item_location WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_mood WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_music_theme WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_atmosphere_theme WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_sfx_theme WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_creature_type WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM pack_item WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM music_playlist_ref WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM local_playlist_track WHERE playlist_item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_local_audio WHERE item_id = ?", arguments: [id])
            try db.execute(
                sql: """
                DELETE FROM local_asset
                WHERE id NOT IN (SELECT asset_id FROM item_local_audio)
                  AND id NOT IN (SELECT asset_id FROM local_playlist_track)
                """
            )
            try db.execute(sql: "DELETE FROM library_item WHERE id = ?", arguments: [id])
        }

        for path in paths {
            let url = AppFilePaths.applicationSupportURL().appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }

    }

    func titleExists(_ title: String) async throws -> Bool {
        try await dbQueue.read { db in
            let sql = "SELECT 1 FROM library_item WHERE lower(title) = lower(?) LIMIT 1"
            return try Row.fetchOne(db, sql: sql, arguments: [title]) != nil
        }
    }

    func updateItemProperties(
        itemId: UUID,
        title: String,
        kind: LibraryKind,
        selectedTagIDs: [TagCategory: [Int64]],
        containsMusic: Bool
    ) async throws {
        let id = itemId.uuidString
        let now = ISO8601DateFormatter().string(from: Date())
        let packId = UserImportPack.id(for: kind).uuidString
        let userImportPackIds = [UserImportPack.atmosphereId.uuidString, UserImportPack.sfxId.uuidString]
        let resolvedContainsMusic = (kind == .atmosphere) ? containsMusic : false

        try await dbQueue.write { db in
            try db.execute(
                sql: "UPDATE library_item SET title = ?, kind = ?, contains_music = ?, updated_at = ? WHERE id = ?",
                arguments: [title, kind.rawValue, resolvedContainsMusic, now, id]
            )

            try db.execute(sql: "UPDATE item_local_audio SET loopable = ? WHERE item_id = ?", arguments: [kind == .atmosphere, id])

            try db.execute(sql: "DELETE FROM item_location WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_mood WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_music_theme WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_atmosphere_theme WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_sfx_theme WHERE item_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM item_creature_type WHERE item_id = ?", arguments: [id])

            try self.insertTagJoins(db: db, itemId: id, selectedTagIDs: selectedTagIDs)

            try self.upsertUserImportPack(db: db, packId: packId, kind: kind, createdAt: now)

            let existingPackIds = try String.fetchAll(
                db,
                sql: "SELECT pack_id FROM pack_item WHERE item_id = ?",
                arguments: [id]
            )

            if existingPackIds.isEmpty {
                let nextOrder = try self.nextPackSortOrder(db: db, packId: packId)
                let packItem = PackItemRow(packId: packId, itemId: id, sortOrder: nextOrder)
                try packItem.insert(db)
            } else {
                try db.execute(
                    sql: "UPDATE pack_item SET pack_id = ? WHERE item_id = ? AND pack_id IN (?, ?)",
                    arguments: [packId, id, userImportPackIds[0], userImportPackIds[1]]
                )
            }
        }

    }

    func searchItems(kind: LibraryKind?, query: String, filters: Filters) async throws -> [LibraryItemRow] {
        try await dbQueue.read { db in
            let term = "%\(query)%"
            var base = """
            SELECT DISTINCT li.*
            FROM library_item li
            LEFT JOIN item_location il ON il.item_id = li.id
            LEFT JOIN location l ON l.id = il.location_id
            LEFT JOIN item_mood im ON im.item_id = li.id
            LEFT JOIN mood m ON m.id = im.mood_id
            LEFT JOIN item_music_theme imt ON imt.item_id = li.id
            LEFT JOIN music_theme mt ON mt.id = imt.music_theme_id
            LEFT JOIN item_atmosphere_theme iat ON iat.item_id = li.id
            LEFT JOIN atmosphere_theme at ON at.id = iat.atmosphere_theme_id
            LEFT JOIN item_sfx_theme ist ON ist.item_id = li.id
            LEFT JOIN sfx_theme st ON st.id = ist.sfx_theme_id
            LEFT JOIN item_creature_type ict ON ict.item_id = li.id
            LEFT JOIN creature_type ct ON ct.id = ict.creature_type_id
            WHERE li.is_visible = 1
            """
            var args: [DatabaseValueConvertible] = []

            if let kind {
                base += " AND li.kind = ?"
                args.append(kind.rawValue)
            }

            base += """
             AND (
                li.title LIKE ? COLLATE NOCASE
                OR l.name LIKE ? COLLATE NOCASE
                OR m.name LIKE ? COLLATE NOCASE
                OR mt.name LIKE ? COLLATE NOCASE
                OR at.name LIKE ? COLLATE NOCASE
                OR st.name LIKE ? COLLATE NOCASE
                OR ct.name LIKE ? COLLATE NOCASE
             )
            """
            args.append(contentsOf: [term, term, term, term, term, term, term])

            let (filterSQL, filterArgs) = LibraryRepository.filterClause(filters: filters, excluding: nil, itemAlias: "li")
            base += filterSQL
            args.append(contentsOf: filterArgs)

            base += " ORDER BY li.title COLLATE NOCASE ASC"

            return try LibraryItemRow.fetchAll(db, SQLRequest(sql: base, arguments: StatementArguments(args)))
        }
    }

    func searchAtmosphereAssets(query: String) async throws -> [LibraryItemRow] {
        try await dbQueue.read { db in
            let term = "%\(query)%"
            let sql = """
            SELECT DISTINCT li.*
            FROM library_item li
            LEFT JOIN item_location il ON il.item_id = li.id
            LEFT JOIN location l ON l.id = il.location_id
            LEFT JOIN item_mood im ON im.item_id = li.id
            LEFT JOIN mood m ON m.id = im.mood_id
            LEFT JOIN item_atmosphere_theme ia ON ia.item_id = li.id
            LEFT JOIN atmosphere_theme at ON at.id = ia.atmosphere_theme_id
            WHERE li.kind = ? AND li.is_visible = 1
              AND (
                li.title LIKE ? COLLATE NOCASE
                OR l.name LIKE ? COLLATE NOCASE
                OR m.name LIKE ? COLLATE NOCASE
                OR at.name LIKE ? COLLATE NOCASE
              )
            ORDER BY li.title COLLATE NOCASE ASC
            """
            let args: [DatabaseValueConvertible] = [LibraryKind.atmosphere.rawValue, term, term, term, term]
            return try LibraryItemRow.fetchAll(db, SQLRequest(sql: sql, arguments: StatementArguments(args)))
        }
    }

    func searchSFXAssets(query: String) async throws -> [LibraryItemRow] {
        try await dbQueue.read { db in
            let term = "%\(query)%"
            let sql = """
            SELECT DISTINCT li.*
            FROM library_item li
            LEFT JOIN item_location il ON il.item_id = li.id
            LEFT JOIN location l ON l.id = il.location_id
            LEFT JOIN item_sfx_theme ist ON ist.item_id = li.id
            LEFT JOIN sfx_theme st ON st.id = ist.sfx_theme_id
            LEFT JOIN item_creature_type ict ON ict.item_id = li.id
            LEFT JOIN creature_type ct ON ct.id = ict.creature_type_id
            LEFT JOIN item_mood im ON im.item_id = li.id
            LEFT JOIN mood m ON m.id = im.mood_id
            WHERE li.kind = ? AND li.is_visible = 1
              AND (
                li.title LIKE ? COLLATE NOCASE
                OR l.name LIKE ? COLLATE NOCASE
                OR st.name LIKE ? COLLATE NOCASE
                OR ct.name LIKE ? COLLATE NOCASE
                OR m.name LIKE ? COLLATE NOCASE
              )
            ORDER BY li.title COLLATE NOCASE ASC
            """
            let args: [DatabaseValueConvertible] = [LibraryKind.sfx.rawValue, term, term, term, term, term]
            return try LibraryItemRow.fetchAll(db, SQLRequest(sql: sql, arguments: StatementArguments(args)))
        }
    }

    private static func buildItemsQuery(kind: LibraryKind, filters: Filters, sort: LibrarySort) -> (String, StatementArguments) {
        var sql = "SELECT * FROM library_item WHERE kind = ? AND is_visible = 1"
        var args: [DatabaseValueConvertible] = [kind.rawValue]

        let (filterSQL, filterArgs) = filterClause(filters: filters, excluding: nil)
        sql += filterSQL
        args.append(contentsOf: filterArgs)

        switch sort {
        case .titleAsc:
            sql += " ORDER BY title COLLATE NOCASE ASC"
        case .titleDesc:
            sql += " ORDER BY title COLLATE NOCASE DESC"
        case .createdAtDesc:
            sql += " ORDER BY created_at DESC"
        }

        return (sql, StatementArguments(args))
    }

    static func filterClause(filters: Filters, excluding: FilterDimension?, itemAlias: String = "library_item") -> (String, [DatabaseValueConvertible]) {
        var clauses: [String] = []
        var args: [DatabaseValueConvertible] = []

        func addFilter(_ ids: [Int64], _ table: String, _ column: String, _ dimensionTable: String, _ dim: FilterDimension) {
            guard !ids.isEmpty, excluding != dim else { return }
            let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
            let matchesSelected = "EXISTS (SELECT 1 FROM \(table) WHERE \(table).item_id = \(itemAlias).id AND \(table).\(column) IN (\(placeholders)))"
            let matchesAll = """
            EXISTS (
                SELECT 1
                FROM \(table) all_join
                JOIN \(dimensionTable) all_tag ON all_tag.id = all_join.\(column)
                WHERE all_join.item_id = \(itemAlias).id AND all_tag.name = 'All'
            )
            """
            clauses.append("(\(matchesSelected) OR \(matchesAll))")
            args.append(contentsOf: ids)
        }

        addFilter(filters.locationIDs, "item_location", "location_id", "location", .location)
        addFilter(filters.moodIDs, "item_mood", "mood_id", "mood", .mood)
        addFilter(filters.musicThemeIDs, "item_music_theme", "music_theme_id", "music_theme", .musicTheme)
        addFilter(filters.atmosphereThemeIDs, "item_atmosphere_theme", "atmosphere_theme_id", "atmosphere_theme", .atmosphereTheme)
        addFilter(filters.sfxThemeIDs, "item_sfx_theme", "sfx_theme_id", "sfx_theme", .sfxTheme)
        addFilter(filters.creatureTypeIDs, "item_creature_type", "creature_type_id", "creature_type", .creatureType)

        if clauses.isEmpty {
            return ("", [])
        }

        return (" AND " + clauses.joined(separator: " AND "), args)
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
        try insert("item_music_theme", "music_theme_id", selectedTagIDs[.musicTheme] ?? [])
        try insert("item_atmosphere_theme", "atmosphere_theme_id", selectedTagIDs[.atmosphereTheme] ?? [])
        try insert("item_sfx_theme", "sfx_theme_id", selectedTagIDs[.sfxTheme] ?? [])
        try insert("item_creature_type", "creature_type_id", selectedTagIDs[.creatureType] ?? [])
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

    private static func fetchTagValues(_ db: Database, dimension: String, joinTable: String, joinColumn: String, itemId: String) throws -> [TagValue] {
        let sql = """
        SELECT d.id, d.name
        FROM \(dimension) d
        JOIN \(joinTable) j ON j.\(joinColumn) = d.id
        WHERE j.item_id = ?
        ORDER BY COALESCE(d.sort_order, 100000), d.name COLLATE NOCASE ASC
        """
        return try TagValue.fetchAll(db, SQLRequest(sql: sql, arguments: [itemId]))
    }

    private static func checkAvailability(_ db: Database, itemId: String) throws -> ItemAvailability {
        let sql = """
        SELECT local_asset.local_path
        FROM item_local_audio
        JOIN local_asset ON local_asset.id = item_local_audio.asset_id
        WHERE item_local_audio.item_id = ?
        LIMIT 1
        """
        if let row = try Row.fetchOne(db, SQLRequest(sql: sql, arguments: [itemId])),
           let path = row["local_path"] as String? {
            let fileURL = AppFilePaths.applicationSupportURL().appendingPathComponent(path)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                return .available
            }
        }
        return .unavailable
    }
}

final class FacetRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func facetCounts(kind: LibraryKind, filters: Filters) async throws -> FacetCounts {
        try await dbQueue.read { db in
            let locations = try Self.fetchFacet(db, kind: kind, filters: filters, dimension: "location", joinTable: "item_location", joinColumn: "location_id", excluding: .location)
            let moods = try Self.fetchFacet(db, kind: kind, filters: filters, dimension: "mood", joinTable: "item_mood", joinColumn: "mood_id", excluding: .mood)
            let musicThemes = try Self.fetchFacet(db, kind: kind, filters: filters, dimension: "music_theme", joinTable: "item_music_theme", joinColumn: "music_theme_id", excluding: .musicTheme)
            let atmosphereThemes = try Self.fetchFacet(db, kind: kind, filters: filters, dimension: "atmosphere_theme", joinTable: "item_atmosphere_theme", joinColumn: "atmosphere_theme_id", excluding: .atmosphereTheme)
            let sfxThemes = try Self.fetchFacet(db, kind: kind, filters: filters, dimension: "sfx_theme", joinTable: "item_sfx_theme", joinColumn: "sfx_theme_id", excluding: .sfxTheme)
            let creatureTypes = try Self.fetchFacet(db, kind: kind, filters: filters, dimension: "creature_type", joinTable: "item_creature_type", joinColumn: "creature_type_id", excluding: .creatureType)

            return FacetCounts(
                locations: locations,
                moods: moods,
                musicThemes: musicThemes,
                atmosphereThemes: atmosphereThemes,
                sfxThemes: sfxThemes,
                creatureTypes: creatureTypes
            )
        }
    }

    private static func fetchFacet(_ db: Database, kind: LibraryKind, filters: Filters, dimension: String, joinTable: String, joinColumn: String, excluding: FilterDimension) throws -> [(TagValue, Int)] {
        let (filterSQL, filterArgs) = LibraryRepository.filterClause(filters: filters, excluding: excluding, itemAlias: "li")
        var args: [DatabaseValueConvertible] = [kind.rawValue]
        args.append(contentsOf: filterArgs)

        let sql = """
        SELECT d.id, d.name, COUNT(DISTINCT li.id) AS count
        FROM \(dimension) d
        JOIN \(joinTable) j ON j.\(joinColumn) = d.id
        JOIN library_item li ON li.id = j.item_id
        WHERE li.kind = ? AND li.is_visible = 1\(filterSQL)
        GROUP BY d.id, d.name
        ORDER BY COALESCE(d.sort_order, 100000), d.name COLLATE NOCASE ASC
        """

        let rows = try Row.fetchAll(db, SQLRequest(sql: sql, arguments: StatementArguments(args)))
        return rows.compactMap { row in
            guard let id = row["id"] as Int64?, let name = row["name"] as String? else { return nil }
            let count = row["count"] as Int? ?? 0
            return (TagValue(id: id, name: name), count)
        }
    }
}

final class PackRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func listPacks(kind: PackKind) async throws -> [PackWithState] {
        try await dbQueue.read { db in
            let sql = """
            SELECT pack.*, pack_state.pack_id AS state_pack_id, pack_state.state, pack_state.bytes_total,
                   pack_state.bytes_downloaded, pack_state.installed_version, pack_state.last_error, pack_state.updated_at
            FROM pack
            LEFT JOIN pack_state ON pack_state.pack_id = pack.id
            WHERE pack.kind = ?
            ORDER BY pack.title COLLATE NOCASE ASC
            """
            let rows = try Row.fetchAll(db, SQLRequest(sql: sql, arguments: [kind.rawValue]))
            return rows.map { row in
                let pack = PackRow(
                    id: row["id"],
                    kind: row["kind"],
                    title: row["title"],
                    description: row["description"],
                    artworkURL: row["artwork_url"],
                    version: row["version"],
                    manifestURL: row["manifest_url"],
                    createdAt: row["created_at"]
                )
                let statePackId: String? = row["state_pack_id"]
                let state = statePackId == nil ? nil : PackStateRow(
                    packId: row["state_pack_id"],
                    state: row["state"],
                    bytesTotal: row["bytes_total"],
                    bytesDownloaded: row["bytes_downloaded"],
                    installedVersion: row["installed_version"],
                    lastError: row["last_error"],
                    updatedAt: row["updated_at"]
                )
                return PackWithState(pack: pack, state: state)
            }
        }
    }

    func packDetail(packId: UUID) async throws -> PackDetail {
        try await dbQueue.read { db in
            guard let pack = try PackRow.fetchOne(db, key: packId.uuidString) else {
                throw RepositoryError.notFound
            }
            let state = try PackStateRow.fetchOne(db, key: packId.uuidString)
            let sql = """
            SELECT library_item.*
            FROM pack_item
            JOIN library_item ON library_item.id = pack_item.item_id
            WHERE pack_item.pack_id = ?
            ORDER BY pack_item.sort_order ASC
            """
            let items = try LibraryItemRow.fetchAll(db, SQLRequest(sql: sql, arguments: [packId.uuidString]))
            return PackDetail(pack: pack, state: state, items: items)
        }
    }

    func isPackInstalled(packId: UUID) async throws -> Bool {
        try await dbQueue.read { db in
            guard let state = try PackStateRow.fetchOne(db, key: packId.uuidString) else { return false }
            return state.state == PackInstallState.downloaded.rawValue
        }
    }
}

final class MusicRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func listMusicEntries() async throws -> [MusicEntry] {
        try await dbQueue.read { db in
            let sql = """
            SELECT library_item.*, music_playlist_ref.apple_music_playlist_id, music_playlist_ref.last_sync_at, music_playlist_ref.use_snapshot
            FROM library_item
            JOIN music_playlist_ref ON music_playlist_ref.item_id = library_item.id
            WHERE library_item.kind = ?
            ORDER BY library_item.title COLLATE NOCASE ASC
            """
            let rows = try Row.fetchAll(db, SQLRequest(sql: sql, arguments: [LibraryKind.music.rawValue]))
            return rows.map { row in
                let item = LibraryItemRow(
                    id: row["id"],
                    kind: row["kind"],
                    title: row["title"],
                    subtitle: row["subtitle"],
                    duration: row["duration"],
                    artworkURL: row["artwork_url"],
                    isVisible: row["is_visible"],
                    containsMusic: row["contains_music"],
                    createdAt: row["created_at"],
                    updatedAt: row["updated_at"]
                )
                let ref = MusicPlaylistRefRow(
                    itemId: row["id"],
                    appleMusicPlaylistId: row["apple_music_playlist_id"],
                    lastSyncAt: row["last_sync_at"],
                    useSnapshot: row["use_snapshot"]
                )
                return MusicEntry(item: item, playlistRef: ref)
            }
        }
    }

    func playlistSource(for itemId: UUID) async throws -> PlaylistSource {
        let id = itemId.uuidString
        return try await dbQueue.read { db in
            let local = try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM local_playlist_track WHERE playlist_item_id = ? LIMIT 1",
                arguments: [id]
            ) != nil
            if local {
                return .local
            }
            let apple = try Row.fetchOne(
                db,
                sql: "SELECT 1 FROM music_playlist_ref WHERE item_id = ? LIMIT 1",
                arguments: [id]
            ) != nil
            if apple {
                return .appleMusic
            }
            throw RepositoryError.notFound
        }
    }

    func playlistSourceMap() async throws -> [String: PlaylistSource] {
        try await dbQueue.read { db in
            var mapping: [String: PlaylistSource] = [:]
            let appleIds = try String.fetchAll(db, sql: "SELECT item_id FROM music_playlist_ref")
            for id in appleIds {
                mapping[id] = .appleMusic
            }
            let localIds = try String.fetchAll(db, sql: "SELECT DISTINCT playlist_item_id FROM local_playlist_track")
            for id in localIds {
                mapping[id] = .local
            }
            return mapping
        }
    }

    func fetchLocalPlaylistTracks(itemId: UUID) async throws -> [LocalPlaylistTrack] {
        try await dbQueue.read { db in
            let sql = """
            SELECT lpt.id, lpt.playlist_item_id, lpt.asset_id, lpt.position, lpt.title, lpt.artist, lpt.duration, local_asset.local_path
            FROM local_playlist_track lpt
            JOIN local_asset ON local_asset.id = lpt.asset_id
            WHERE lpt.playlist_item_id = ?
            ORDER BY lpt.position ASC
            """
            let rows = try Row.fetchAll(db, SQLRequest(sql: sql, arguments: [itemId.uuidString]))
            return rows.compactMap { row in
                guard let localPath = row["local_path"] as String? else { return nil }
                return LocalPlaylistTrack(
                    id: row["id"],
                    playlistItemId: row["playlist_item_id"],
                    assetId: row["asset_id"],
                    position: row["position"],
                    title: row["title"],
                    artist: row["artist"],
                    duration: row["duration"],
                    localPath: localPath
                )
            }
        }
    }

    func playlistID(for itemId: UUID) async throws -> String {
        try await dbQueue.read { db in
            guard let ref = try MusicPlaylistRefRow.fetchOne(db, key: itemId.uuidString) else {
                throw RepositoryError.notFound
            }
            return ref.appleMusicPlaylistId
        }
    }

    func fetchLibraryPlaylist(id: String) async throws -> Playlist? {
        var request = MusicLibraryRequest<Playlist>()
        request.filter(matching: \.id, equalTo: MusicItemID(id))
        let response = try await request.response()
        return response.items.first { $0.id.rawValue == id }
    }

    func upsertAppleMusicPlaylist(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        selectedTagIDs: [TagCategory: [Int64]]? = nil
    ) async throws -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        return try await dbQueue.write { db in
            let existingItemId = try String.fetchOne(
                db,
                sql: "SELECT item_id FROM music_playlist_ref WHERE apple_music_playlist_id = ?",
                arguments: [id]
            )

            if let itemId = existingItemId {
                try db.execute(
                    sql: """
                    UPDATE library_item
                    SET title = ?, subtitle = ?, artwork_url = ?, updated_at = ?
                    WHERE id = ?
                    """,
                    arguments: [title, subtitle, artworkURL, now, itemId]
                )
                if let selectedTagIDs {
                    try self.clearMusicTags(db: db, itemId: itemId)
                    try self.insertMusicTags(db: db, itemId: itemId, selectedTagIDs: selectedTagIDs)
                }
                return itemId
            } else {
                let itemId = UUID().uuidString
                let item = LibraryItemRow(
                    id: itemId,
                    kind: LibraryKind.music.rawValue,
                    title: title,
                    subtitle: subtitle,
                    duration: nil,
                    artworkURL: artworkURL,
                    isVisible: true,
                    containsMusic: true,
                    createdAt: now,
                    updatedAt: now
                )
                try item.insert(db)
                let ref = MusicPlaylistRefRow(
                    itemId: itemId,
                    appleMusicPlaylistId: id,
                    lastSyncAt: nil,
                    useSnapshot: false
                )
                try ref.insert(db)
                if let selectedTagIDs {
                    try self.insertMusicTags(db: db, itemId: itemId, selectedTagIDs: selectedTagIDs)
                }
                return itemId
            }
        }
    }

    private func clearMusicTags(db: Database, itemId: String) throws {
        try db.execute(sql: "DELETE FROM item_location WHERE item_id = ?", arguments: [itemId])
        try db.execute(sql: "DELETE FROM item_mood WHERE item_id = ?", arguments: [itemId])
        try db.execute(sql: "DELETE FROM item_music_theme WHERE item_id = ?", arguments: [itemId])
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
}

enum RepositoryError: Error {
    case notFound
}

enum AppFilePaths {
    static func applicationSupportURL() -> URL {
        let fileManager = FileManager.default
        let baseDirectory =
            fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory.appendingPathComponent("ApplicationSupport", isDirectory: true)

        let appFolder = baseDirectory.appendingPathComponent("Cantus", isDirectory: true)
        do {
            try fileManager.createDirectory(at: appFolder, withIntermediateDirectories: true)
            return appFolder
        } catch {
            let fallback = fileManager.temporaryDirectory.appendingPathComponent("Cantus", isDirectory: true)
            try? fileManager.createDirectory(at: fallback, withIntermediateDirectories: true)
            return fallback
        }
    }
}
