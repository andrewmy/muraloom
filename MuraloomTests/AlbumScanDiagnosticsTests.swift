import Foundation
import Testing
@testable import Muraloom

struct AlbumScanDiagnosticsTests {
    @Test func exclusionStageMetadataIsStable() {
        #expect(ExclusionStage.wallpaperFilters.id == "wallpaperFilters")
        #expect(ExclusionStage.wallpaperFilters.displayName == "Wallpaper Filters")
        #expect(ExclusionStage.notUsableMedia.id == "notUsableMedia")
        #expect(ExclusionStage.notUsableMedia.displayName == "Not Usable Media")
    }

    @Test func exclusionReasonLabelsMatchCases() {
        #expect(ExclusionReason.belowMinimumWidth(minimumWidth: 3000).label == "Too Small (< 3000px)")
        #expect(ExclusionReason.portraitWhenHorizontalOnly.label == "Portrait Blocked")
        #expect(ExclusionReason.notImageMedia.label == "Not Image Media")
        #expect(ExclusionReason.rawUnsupported.label == "RAW Unsupported")
    }

    @Test func diagnosticsTotalsAndStageFilteringUseExpectedBuckets() {
        let wallpaperFiltered = [
            ExcludedMediaItem(id: "w1", name: "small.jpg", webUrl: nil, reason: .belowMinimumWidth(minimumWidth: 2500))
        ]
        let nonUsable = [
            ExcludedMediaItem(id: "n1", name: "movie.mp4", webUrl: nil, reason: .notImageMedia),
            ExcludedMediaItem(id: "n2", name: "raw.arw", webUrl: nil, reason: .rawUnsupported)
        ]

        let diagnostics = AlbumScanDiagnostics(
            scannedAt: Date(timeIntervalSince1970: 1_700_000_000),
            wallpaperFilterExclusions: wallpaperFiltered,
            nonUsableExclusions: nonUsable
        )

        #expect(diagnostics.totalExclusions == 3)
        #expect(diagnostics.exclusions(for: .wallpaperFilters) == wallpaperFiltered)
        #expect(diagnostics.exclusions(for: .notUsableMedia) == nonUsable)
    }

    @Test func mediaItemDisplayNameTrimsWhitespaceAndFallsBackToId() {
        let named = MediaItem(
            id: "item-1",
            downloadUrl: nil,
            webUrl: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            name: "  Sunrise  ",
            mimeType: nil,
            cTag: nil
        )
        #expect(named.displayName == "Sunrise")

        let blank = MediaItem(
            id: "item-2",
            downloadUrl: nil,
            webUrl: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            name: " \n\t ",
            mimeType: nil,
            cTag: nil
        )
        #expect(blank.displayName == "item-2")

        let missing = MediaItem(
            id: "item-3",
            downloadUrl: nil,
            webUrl: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            name: nil,
            mimeType: nil,
            cTag: nil
        )
        #expect(missing.displayName == "item-3")
    }
}
