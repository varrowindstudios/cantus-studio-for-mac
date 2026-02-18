import Foundation
import GRDB

enum TagCategory: String, CaseIterable, Identifiable {
    case location
    case mood
    case musicTheme
    case atmosphereTheme
    case sfxTheme
    case creatureType

    var id: String { rawValue }

    var label: String {
        switch self {
        case .location: return "Location"
        case .mood: return "Mood"
        case .musicTheme: return "Theme"
        case .atmosphereTheme: return "Theme"
        case .sfxTheme: return "Theme"
        case .creatureType: return "Creature Type"
        }
    }

    var tableName: String {
        switch self {
        case .location: return "location"
        case .mood: return "mood"
        case .musicTheme: return "music_theme"
        case .atmosphereTheme: return "atmosphere_theme"
        case .sfxTheme: return "sfx_theme"
        case .creatureType: return "creature_type"
        }
    }
}

struct TagCatalog {
    var locations: [TagValue]
    var moods: [TagValue]
    var musicThemes: [TagValue]
    var atmosphereThemes: [TagValue]
    var sfxThemes: [TagValue]
    var creatureTypes: [TagValue]
}

final class TagRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func ensureBaselineTags() async throws {
        try await dbQueue.write { db in
            try Self.upsertAllTag(db: db, table: TagCategory.location.tableName)
            try Self.upsertNames(db: db, table: TagCategory.location.tableName, names: Self.baselineLocations)
            try Self.upsertAllTag(db: db, table: TagCategory.mood.tableName)
            try Self.upsertNames(db: db, table: TagCategory.mood.tableName, names: Self.baselineMoods)
            try Self.upsertAllTag(db: db, table: TagCategory.musicTheme.tableName)
            try Self.upsertNames(db: db, table: TagCategory.musicTheme.tableName, names: Self.baselineMusicThemes)
            try Self.upsertAllTag(db: db, table: TagCategory.atmosphereTheme.tableName)
            try Self.upsertNames(db: db, table: TagCategory.atmosphereTheme.tableName, names: Self.baselineAtmosphereThemes)
            try Self.upsertAllTag(db: db, table: TagCategory.sfxTheme.tableName)
            try Self.upsertNames(db: db, table: TagCategory.sfxTheme.tableName, names: Self.baselineSFXThemes)
            try Self.upsertAllTag(db: db, table: TagCategory.creatureType.tableName)
            try Self.upsertNames(db: db, table: TagCategory.creatureType.tableName, names: Self.baselineCreatureTypes)
        }
    }

    func fetchAllTags() async throws -> TagCatalog {
        try await dbQueue.read { db in
            let locations = try self.fetchTags(db, table: TagCategory.location.tableName)
            let moods = try self.fetchTags(db, table: TagCategory.mood.tableName)
            let musicThemes = try self.fetchTags(db, table: TagCategory.musicTheme.tableName)
            let atmosphereThemes = try self.fetchTags(db, table: TagCategory.atmosphereTheme.tableName)
            let sfxThemes = try self.fetchTags(db, table: TagCategory.sfxTheme.tableName)
            let creatureTypes = try self.fetchTags(db, table: TagCategory.creatureType.tableName)
            return TagCatalog(
                locations: locations,
                moods: moods,
                musicThemes: musicThemes,
                atmosphereThemes: atmosphereThemes,
                sfxThemes: sfxThemes,
                creatureTypes: creatureTypes
            )
        }
    }

    func upsertTag(name: String, category: TagCategory) async throws -> TagValue {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TagRepositoryError.emptyName }
        let value = try await dbQueue.write { db in
            try db.execute(
                sql: "INSERT INTO \(category.tableName) (name, is_system) VALUES (?, 0) ON CONFLICT(name) DO NOTHING",
                arguments: [trimmed]
            )
            if let row = try Row.fetchOne(
                db,
                sql: "SELECT id, name FROM \(category.tableName) WHERE name = ?",
                arguments: [trimmed]
            ),
               let id = row["id"] as Int64?,
               let storedName = row["name"] as String? {
                return TagValue(id: id, name: storedName)
            }
            throw TagRepositoryError.insertFailed
        }
        return value
    }

    private func fetchTags(_ db: Database, table: String) throws -> [TagValue] {
        let sql = """
        SELECT id, name
        FROM \(table)
        ORDER BY COALESCE(sort_order, 100000), name COLLATE NOCASE ASC
        """
        return try TagValue.fetchAll(db, SQLRequest(sql: sql))
    }

    private static func upsertNames(db: Database, table: String, names: [String]) throws {
        for name in names {
            try db.execute(
                sql: "INSERT INTO \(table) (name, is_system) VALUES (?, 1) ON CONFLICT(name) DO NOTHING",
                arguments: [name]
            )
        }
    }

    private static func upsertAllTag(db: Database, table: String) throws {
        try db.execute(
            sql: "INSERT INTO \(table) (name, is_system, sort_order) VALUES ('All', 1, 0) ON CONFLICT(name) DO UPDATE SET is_system = 1, sort_order = 0"
        )
    }

    private static let baselineLocations = [
        "Arctic",
        "Coastal",
        "Desert",
        "Forest",
        "Grassland",
        "Hill",
        "Mountain",
        "Swamp",
        "Underdark",
        "Underwater",
        "Urban",
        "Outer Space",
        "Elemental Planes",
        "Celestial Plane",
        "Fey Plane",
        "Shadow Plane",
        "Hell"
    ]

    private static let baselineMoods = [
        "Action",
        "Mysterious",
        "Horrific",
        "Awe-Inspiring",
        "Arcane Wonder",
        "Suspenseful",
        "Investigative",
        "Lighthearted",
        "Sentimental",
        "Sorrowful",
        "Cozy",
        "Bustling",
        "Curious",
        "Intimate",
        "Ominous",
        "Victorious & Jubilant",
        "Wistful"
    ]

    private static let baselineAtmosphereThemes = [
        "Festival / Carnival",
        "Ritual / Magic Working",
        "Investigation / Crime Scene",
        "Battlefield (Active)",
        "Battlefield (Aftermath)",
        "Expedition / Exploration",
        "Frontier Outpost",
        "High Society / Gala",
        "Underworld / Den of Vice",
        "Sacred / Divine Presence",
        "Haunting / Paranormal",
        "Dreamscape / Surreal",
        "Apocalypse / Collapse",
        "Political Intrigue / Court Tension",
        "Nature Reclaiming / Overgrowth"
    ]

    private static let baselineSFXThemes = [
        "Combat Impacts",
        "Weapon Handling",
        "Magic",
        "Tech Interface",
        "Doors & Mechanisms",
        "Tools & Crafting",
        "Household Props",
        "Vehicles & Mounts",
        "Footsteps",
        "Cloth & Gear",
        "Water Interactions",
        "Fire & Heat",
        "Debris & Destruction",
        "Stealth & Thievery",
        "Horror Stingers",
        "Monsters & Beasts"
    ]

    private static let baselineCreatureTypes = [
        "Aberration",
        "Beast",
        "Celestial",
        "Construct",
        "Dragon",
        "Elemental",
        "Fey",
        "Fiend",
        "Giant",
        "Humanoid",
        "Monstrosity",
        "Ooze",
        "Plant",
        "Undead"
    ]

    private static let baselineMusicThemes: [String] = []
}

enum TagRepositoryError: Error {
    case emptyName
    case insertFailed
}
