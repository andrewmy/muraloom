import Foundation

enum ExclusionStage: String, CaseIterable, Identifiable {
    case wallpaperFilters
    case notUsableMedia

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wallpaperFilters:
            return "Wallpaper Filters"
        case .notUsableMedia:
            return "Not Usable Media"
        }
    }
}

enum ExclusionReason: Hashable {
    case belowMinimumWidth(minimumWidth: Int)
    case portraitWhenHorizontalOnly
    case notImageMedia
    case rawUnsupported

    var label: String {
        switch self {
        case .belowMinimumWidth(let minimumWidth):
            return "Too Small (< \(minimumWidth)px)"
        case .portraitWhenHorizontalOnly:
            return "Portrait Blocked"
        case .notImageMedia:
            return "Not Image Media"
        case .rawUnsupported:
            return "RAW Unsupported"
        }
    }
}

struct ExcludedMediaItem: Identifiable, Hashable {
    let id: String
    let name: String
    let webUrl: URL?
    let reason: ExclusionReason
}

struct AlbumScanResult {
    let usableItems: [MediaItem]
    let nonUsableExclusions: [ExcludedMediaItem]
    let scannedAt: Date
}

struct AlbumScanDiagnostics {
    let scannedAt: Date
    let wallpaperFilterExclusions: [ExcludedMediaItem]
    let nonUsableExclusions: [ExcludedMediaItem]

    var totalExclusions: Int {
        wallpaperFilterExclusions.count + nonUsableExclusions.count
    }

    func exclusions(for stage: ExclusionStage) -> [ExcludedMediaItem] {
        switch stage {
        case .wallpaperFilters:
            return wallpaperFilterExclusions
        case .notUsableMedia:
            return nonUsableExclusions
        }
    }
}

extension MediaItem {
    var displayName: String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? id : trimmed
    }
}
