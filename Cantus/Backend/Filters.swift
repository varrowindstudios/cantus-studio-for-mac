import Foundation

enum LibrarySort {
    case titleAsc
    case titleDesc
    case createdAtDesc
}

struct Filters: Equatable {
    var locationIDs: [Int64] = []
    var moodIDs: [Int64] = []
    var musicThemeIDs: [Int64] = []
    var atmosphereThemeIDs: [Int64] = []
    var sfxThemeIDs: [Int64] = []
    var creatureTypeIDs: [Int64] = []
}

enum FilterDimension {
    case location
    case mood
    case musicTheme
    case atmosphereTheme
    case sfxTheme
    case creatureType
}
