import SwiftUI

@available(iOS 18.0, *)
struct MenuControlsContext {
    let isPlaylistPlaying: Bool
    let togglePlayPause: () -> Void
    let nextSong: () -> Void
    let previousSong: () -> Void
    let stopAtmospheres: () -> Void
    let stopSoundEffects: () -> Void
    let increaseMixVolume: () -> Void
    let decreaseMixVolume: () -> Void
    let increaseAtmosphereVolume: () -> Void
    let decreaseAtmosphereVolume: () -> Void
    let increaseSoundEffectsVolume: () -> Void
    let decreaseSoundEffectsVolume: () -> Void
}

@available(iOS 18.0, *)
extension FocusedValues {
    @Entry var menuControlsContext: MenuControlsContext?
}
