import Foundation
import GRDB

final class DatabaseManager {
    let dbQueue: DatabaseQueue
    let isInMemory: Bool

    init(fileURL: URL = DatabaseManager.defaultDatabaseURL(), inMemory: Bool = false) throws {
        self.isInMemory = inMemory
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        let path = inMemory ? ":memory:" : fileURL.path
        dbQueue = try DatabaseQueue(path: path, configuration: config)
        try DatabaseMigratorFactory.migrator.migrate(dbQueue)
    }

    static func defaultDatabaseURL() -> URL {
        AppFilePaths.applicationSupportURL().appendingPathComponent("cantus.sqlite")
    }
}

@MainActor
final class AppBackend: ObservableObject {
    static let shared = AppBackend()

    @Published private(set) var startupWarning: String?

    let database: DatabaseManager
    let libraryRepository: LibraryRepository
    let facetRepository: FacetRepository
    let packRepository: PackRepository
    let musicRepository: MusicRepository
    let tagRepository: TagRepository
    let localAssetImporter: LocalAssetImporter
    let localPlaylistImporter: LocalPlaylistImporter
    let packDownloadManager: PackDownloadManager
    let audioManager: AudioPlaybackManager
    private var seedTask: Task<Void, Never>?

    private init() {
        let resolvedDatabase: DatabaseManager
        var warning: String?

        do {
            resolvedDatabase = try DatabaseManager()
        } catch {
            warning = "Persistent database unavailable. Using in-memory fallback."
            do {
                resolvedDatabase = try DatabaseManager(inMemory: true)
            } catch {
                let fallbackURL = FileManager.default.temporaryDirectory.appendingPathComponent("cantus-recovery.sqlite")
                warning = "Primary database unavailable. Using temporary recovery storage."
                do {
                    resolvedDatabase = try DatabaseManager(fileURL: fallbackURL)
                } catch {
                    preconditionFailure("Failed to initialize database storage: \(error)")
                }
            }
        }
        database = resolvedDatabase
        startupWarning = warning

        libraryRepository = LibraryRepository(dbQueue: database.dbQueue)
        facetRepository = FacetRepository(dbQueue: database.dbQueue)
        packRepository = PackRepository(dbQueue: database.dbQueue)
        musicRepository = MusicRepository(dbQueue: database.dbQueue)
        tagRepository = TagRepository(dbQueue: database.dbQueue)
        localAssetImporter = LocalAssetImporter(dbQueue: database.dbQueue)
        localPlaylistImporter = LocalPlaylistImporter(dbQueue: database.dbQueue)
        packDownloadManager = PackDownloadManager(dbQueue: database.dbQueue)
        audioManager = AudioPlaybackManager(dbQueue: database.dbQueue)
        audioManager.prewarmAudioSession()
    }

    func seedIfNeeded() async {
        if let seedTask {
            await seedTask.value
            return
        }

        let task = Task { [dbQueue = database.dbQueue] in
            do {
                try await SeedImporter(dbQueue: dbQueue).importIfNeeded()
            } catch {
                print("Seed import failed: \(error)")
            }
        }
        seedTask = task
        await task.value
        seedTask = nil
    }

    func importLocalAsset(
        sourceURL: URL,
        kind: LibraryKind,
        selectedTagIDs: [TagCategory: [Int64]],
        containsMusic: Bool,
        preferredTitle: String?
    ) async throws -> ImportedAsset {
        try await localAssetImporter.importAsset(
            from: sourceURL,
            kind: kind,
            selectedTagIDs: selectedTagIDs,
            containsMusic: containsMusic,
            preferredTitle: preferredTitle
        )
    }

    func normalizedTitle(for sourceURL: URL) -> String {
        localAssetImporter.normalizedTitle(from: sourceURL)
    }

    func normalizedTitle(from name: String) -> String {
        localAssetImporter.normalizedTitle(from: name)
    }

    func updateItemProperties(
        itemId: UUID,
        title: String,
        kind: LibraryKind,
        selectedTagIDs: [TagCategory: [Int64]],
        containsMusic: Bool
    ) async throws {
        try await libraryRepository.updateItemProperties(
            itemId: itemId,
            title: title,
            kind: kind,
            selectedTagIDs: selectedTagIDs,
            containsMusic: containsMusic
        )
    }

    func addAppleMusicPlaylist(
        id: String,
        title: String,
        subtitle: String?,
        artworkURL: String?,
        selectedTagIDs: [TagCategory: [Int64]]? = nil
    ) async throws -> String {
        try await musicRepository.upsertAppleMusicPlaylist(
            id: id,
            title: title,
            subtitle: subtitle,
            artworkURL: artworkURL,
            selectedTagIDs: selectedTagIDs
        )
    }

    func addLocalPlaylist(
        name: String,
        trackURLs: [URL],
        selectedTagIDs: [TagCategory: [Int64]]
    ) async throws -> ImportedPlaylist {
        try await localPlaylistImporter.importPlaylist(
            name: name,
            trackURLs: trackURLs,
            selectedTagIDs: selectedTagIDs
        )
    }
}
