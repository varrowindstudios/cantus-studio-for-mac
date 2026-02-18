//
//  CantusTests.swift
//  CantusTests
//
//  Created by Thom Anthony on 2/13/26.
//

import Foundation
import Testing
@testable import Cantus

@MainActor
struct CantusTests {
    private static let playbackKeys = [
        "recentLoopHistory",
        "recentSFXHistory",
        "recentPlaylistHistory",
        "lastPlayedLoops",
        "lastPlayedSFX",
        "lastPlayedPlaylists",
        "masterVolume",
        "musicVolume",
        "atmosphereVolume",
        "sfxVolume"
    ]

    private static let bookmarkKeys = [
        "bookmarkedLoops",
        "bookmarkedSFX",
        "bookmarkedPlaylists"
    ]

    private static func resetUserDefaults(keys: [String]) {
        let defaults = UserDefaults.standard
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.synchronize()
    }

    @Test func quickPlayTriggerSetsFlag() async throws {
        let state = AppMenuState()
        await MainActor.run {
            state.triggerQuickPlay()
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(state.quickPlayRequested == true)
    }

    @Test func closePanelsAndSheetsClearsFlags() async throws {
        let state = AppMenuState()
        await MainActor.run {
            state.showAbout = true
            state.showSettings = true
            state.showPlaylistPanel = true
            state.showAtmospherePanel = true
            state.showSoundboardPanel = true
            state.showAddPlaylistSheet = true
            state.closePanelsAndSheets()
        }
        #expect(state.showAbout == false)
        #expect(state.showSettings == false)
        #expect(state.showPlaylistPanel == false)
        #expect(state.showAtmospherePanel == false)
        #expect(state.showSoundboardPanel == false)
        #expect(state.showAddPlaylistSheet == false)
    }

    @Test func playbackStateToggleLoopUpdatesRecents() async throws {
        Self.resetUserDefaults(keys: Self.playbackKeys)
        let store = await MainActor.run { PlaybackStateStore() }
        await MainActor.run {
            store.toggleLoop("Dungeon Drips")
        }
        #expect(store.playingLoops.contains("Dungeon Drips"))
        #expect(store.recentLoops.first == "Dungeon Drips")
        #expect(store.lastPlayedLoop("Dungeon Drips") != nil)
        Self.resetUserDefaults(keys: Self.playbackKeys)
    }

    @Test func playbackStateToggleSFXUpdatesRecents() async throws {
        Self.resetUserDefaults(keys: Self.playbackKeys)
        let store = await MainActor.run { PlaybackStateStore() }
        await MainActor.run {
            store.toggleSFX("Thunder")
        }
        #expect(store.playingSFX.contains("Thunder"))
        #expect(store.recentSFX.first == "Thunder")
        #expect(store.lastPlayedSFX("Thunder") != nil)
        Self.resetUserDefaults(keys: Self.playbackKeys)
    }

    @Test func bookmarksTogglePlaylistPersists() async throws {
        Self.resetUserDefaults(keys: Self.bookmarkKeys)
        let store = await MainActor.run { BookmarksStore() }
        await MainActor.run {
            store.togglePlaylist("Epic Mix")
        }
        #expect(store.playlistBookmarks.contains("Epic Mix"))
        #expect(store.playlistBookmarkList.first == "Epic Mix")
        Self.resetUserDefaults(keys: Self.bookmarkKeys)
    }
}
