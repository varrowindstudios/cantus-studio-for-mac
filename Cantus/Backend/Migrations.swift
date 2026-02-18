import Foundation
import GRDB

enum DatabaseMigratorFactory {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "library_item") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("subtitle", .text)
                t.column("duration", .double)
                t.column("artwork_url", .text)
                t.column("is_visible", .boolean).notNull().defaults(to: true)
                t.column("contains_music", .boolean).notNull().defaults(to: false)
                t.column("created_at", .text).notNull()
                t.column("updated_at", .text).notNull()
            }

            try db.create(index: "idx_library_item_kind", on: "library_item", columns: ["kind"])

            try db.create(table: "music_playlist_ref") { t in
                t.column("item_id", .text).primaryKey().references("library_item", onDelete: .cascade)
                t.column("apple_music_playlist_id", .text).notNull().unique()
                t.column("last_sync_at", .text)
                t.column("use_snapshot", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "music_track_cache") { t in
                t.column("track_id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("artist", .text).notNull()
                t.column("album", .text)
                t.column("duration", .double)
                t.column("artwork_url", .text)
                t.column("last_seen_at", .text).notNull()
            }

            try db.create(table: "playlist_track") { t in
                t.column("playlist_id", .text).notNull()
                t.column("track_id", .text).notNull()
                t.column("position", .integer).notNull()
                t.column("snapshot_at", .text)
                t.primaryKey(["playlist_id", "track_id", "snapshot_at"], onConflict: .replace)
            }

            try db.create(table: "pack") { t in
                t.column("id", .text).primaryKey()
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("description", .text)
                t.column("artwork_url", .text)
                t.column("version", .integer).notNull()
                t.column("manifest_url", .text).notNull()
                t.column("created_at", .text).notNull()
            }

            try db.create(table: "pack_state") { t in
                t.column("pack_id", .text).primaryKey().references("pack", onDelete: .cascade)
                t.column("state", .text).notNull()
                t.column("bytes_total", .integer)
                t.column("bytes_downloaded", .integer)
                t.column("installed_version", .integer)
                t.column("last_error", .text)
                t.column("updated_at", .text).notNull()
            }

            try db.create(index: "idx_pack_state_state", on: "pack_state", columns: ["state"])

            try db.create(table: "pack_item") { t in
                t.column("pack_id", .text).notNull().references("pack", onDelete: .cascade)
                t.column("item_id", .text).notNull().references("library_item", onDelete: .cascade)
                t.column("sort_order", .integer).notNull()
                t.primaryKey(["pack_id", "item_id"], onConflict: .replace)
            }

            try db.create(index: "idx_pack_item_pack", on: "pack_item", columns: ["pack_id"])

            try db.create(table: "local_asset") { t in
                t.column("id", .text).primaryKey()
                t.column("pack_id", .text).notNull().references("pack", onDelete: .cascade)
                t.column("remote_url", .text).notNull()
                t.column("local_path", .text)
                t.column("etag", .text)
                t.column("sha256", .text)
                t.column("bytes_total", .integer)
                t.column("attribution_author", .text)
                t.column("attribution_source", .text)
                t.column("attribution_license", .text)
                t.column("attribution_license_url", .text)
                t.column("created_at", .text).notNull()
            }

            try db.create(table: "item_local_audio") { t in
                t.column("item_id", .text).primaryKey().references("library_item", onDelete: .cascade)
                t.column("asset_id", .text).notNull().references("local_asset", onDelete: .cascade)
                t.column("codec", .text)
                t.column("sample_rate", .integer)
                t.column("channels", .integer)
                t.column("loopable", .boolean).notNull().defaults(to: false)
            }

            try db.create(table: "location") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("sort_order", .integer)
                t.column("is_system", .boolean).notNull().defaults(to: true)
                t.column("created_at", .text).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "mood") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("sort_order", .integer)
                t.column("is_system", .boolean).notNull().defaults(to: true)
                t.column("created_at", .text).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "music_theme") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("sort_order", .integer)
                t.column("is_system", .boolean).notNull().defaults(to: true)
                t.column("created_at", .text).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "atmosphere_theme") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("sort_order", .integer)
                t.column("is_system", .boolean).notNull().defaults(to: true)
                t.column("created_at", .text).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "sfx_theme") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("sort_order", .integer)
                t.column("is_system", .boolean).notNull().defaults(to: true)
                t.column("created_at", .text).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "creature_type") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().unique()
                t.column("sort_order", .integer)
                t.column("is_system", .boolean).notNull().defaults(to: true)
                t.column("created_at", .text).notNull().defaults(to: "CURRENT_TIMESTAMP")
            }

            try db.create(table: "item_location") { t in
                t.column("item_id", .text).notNull()
                t.column("location_id", .integer).notNull()
                t.primaryKey(["item_id", "location_id"], onConflict: .replace)
            }

            try db.create(table: "item_mood") { t in
                t.column("item_id", .text).notNull()
                t.column("mood_id", .integer).notNull()
                t.primaryKey(["item_id", "mood_id"], onConflict: .replace)
            }

            try db.create(table: "item_music_theme") { t in
                t.column("item_id", .text).notNull()
                t.column("music_theme_id", .integer).notNull()
                t.primaryKey(["item_id", "music_theme_id"], onConflict: .replace)
            }

            try db.create(table: "item_atmosphere_theme") { t in
                t.column("item_id", .text).notNull()
                t.column("atmosphere_theme_id", .integer).notNull()
                t.primaryKey(["item_id", "atmosphere_theme_id"], onConflict: .replace)
            }

            try db.create(table: "item_sfx_theme") { t in
                t.column("item_id", .text).notNull()
                t.column("sfx_theme_id", .integer).notNull()
                t.primaryKey(["item_id", "sfx_theme_id"], onConflict: .replace)
            }

            try db.create(table: "item_creature_type") { t in
                t.column("item_id", .text).notNull()
                t.column("creature_type_id", .integer).notNull()
                t.primaryKey(["item_id", "creature_type_id"], onConflict: .replace)
            }

            try db.create(index: "idx_item_location_location", on: "item_location", columns: ["location_id"])
            try db.create(index: "idx_item_mood_mood", on: "item_mood", columns: ["mood_id"])
            try db.create(index: "idx_item_music_theme_theme", on: "item_music_theme", columns: ["music_theme_id"])
            try db.create(index: "idx_item_atmo_theme_theme", on: "item_atmosphere_theme", columns: ["atmosphere_theme_id"])
            try db.create(index: "idx_item_sfx_theme_theme", on: "item_sfx_theme", columns: ["sfx_theme_id"])
            try db.create(index: "idx_item_creature_type_type", on: "item_creature_type", columns: ["creature_type_id"])
        }

        migrator.registerMigration("v2_add_contains_music") { db in
            guard try db.tableExists("library_item") else { return }
            let columns = try db.columns(in: "library_item").map(\.name)
            guard !columns.contains("contains_music") else { return }
            try db.alter(table: "library_item") { t in
                t.add(column: "contains_music", .boolean).notNull().defaults(to: false)
            }
        }

        migrator.registerMigration("v3_local_playlists") { db in
            guard !(try db.tableExists("local_playlist_track")) else { return }
            try db.create(table: "local_playlist_track") { t in
                t.column("id", .text).primaryKey()
                t.column("playlist_item_id", .text).notNull().references("library_item", onDelete: .cascade)
                t.column("asset_id", .text).notNull().references("local_asset", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("title", .text).notNull()
                t.column("artist", .text)
                t.column("duration", .double)
            }
            try db.create(index: "idx_local_playlist_track_playlist", on: "local_playlist_track", columns: ["playlist_item_id"])
            try db.create(index: "idx_local_playlist_track_asset", on: "local_playlist_track", columns: ["asset_id"])
        }

        migrator.registerMigration("v4_asset_attribution") { db in
            guard try db.tableExists("local_asset") else { return }
            let columns = try db.columns(in: "local_asset").map(\.name)
            try db.alter(table: "local_asset") { t in
                if !columns.contains("attribution_author") {
                    t.add(column: "attribution_author", .text)
                }
                if !columns.contains("attribution_source") {
                    t.add(column: "attribution_source", .text)
                }
                if !columns.contains("attribution_license") {
                    t.add(column: "attribution_license", .text)
                }
                if !columns.contains("attribution_license_url") {
                    t.add(column: "attribution_license_url", .text)
                }
            }
        }

        return migrator
    }
}
