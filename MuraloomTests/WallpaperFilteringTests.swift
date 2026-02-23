import Testing
@testable import Muraloom

struct WallpaperFilteringTests {
    private func item(
        _ id: String,
        width: Int?,
        height: Int?
    ) -> MediaItem {
        MediaItem(
            id: id,
            downloadUrl: nil,
            pixelWidth: width,
            pixelHeight: height,
            name: "\(id).jpg",
            mimeType: "image/jpeg",
            cTag: nil
        )
    }

    @Test func eligibleItemsApplyMinimumWidthAndHorizontalFilters() {
        let items = [
            item("keep", width: 6000, height: 4000),
            item("small", width: 3000, height: 2000),
            item("portrait", width: 5500, height: 6500),
            item("unknown", width: nil, height: nil),
        ]

        let eligible = WallpaperManager.eligibleMediaItems(
            from: items,
            minimumPictureWidth: 5000,
            horizontalPhotosOnly: true
        )

        #expect(eligible.map(\.id) == ["keep", "unknown"])
    }
}
