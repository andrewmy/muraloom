import Testing
@testable import Muraloom

struct WallpaperCandidateSelectionTests {
    private func item(_ id: String, _ name: String) -> MediaItem {
        MediaItem(id: id, downloadUrl: nil, pixelWidth: nil, pixelHeight: nil, name: name, mimeType: nil, cTag: nil)
    }

    @Test func randomAvoidsImmediateRepeatWhenPossible() {
        let items = [
            item("1", "one.jpg"),
            item("2", "two.jpg"),
            item("3", "three.jpg"),
        ]

        let candidates = WallpaperManager.buildWallpaperCandidates(
            filteredItems: items,
            maxAttempts: 3,
            pickRandomly: true,
            lastPickedIndex: 0,
            avoidItemId: "2"
        )

        #expect(candidates.isEmpty == false)
        #expect(candidates.contains(where: { $0.item.id == "2" }) == false)
    }

    @Test func randomAllowsRepeatWhenOnlyOneItem() {
        let items = [item("1", "one.jpg")]
        let candidates = WallpaperManager.buildWallpaperCandidates(
            filteredItems: items,
            maxAttempts: 3,
            pickRandomly: true,
            lastPickedIndex: 0,
            avoidItemId: "1"
        )

        #expect(candidates.count == 1)
        #expect(candidates.first?.item.id == "1")
    }

    @Test func sequentialSkipsAvoidIdAndWraps() {
        let items = [
            item("a", "a.jpg"), // idx 0
            item("b", "b.jpg"), // idx 1
            item("c", "c.jpg"), // idx 2
        ]

        // lastPickedIndex=1 => start at 2 ("c"), but avoid "c", so should pick "a" then "b".
        let candidates = WallpaperManager.buildWallpaperCandidates(
            filteredItems: items,
            maxAttempts: 2,
            pickRandomly: false,
            lastPickedIndex: 1,
            avoidItemId: "c"
        )

        #expect(candidates.map(\.item.id) == ["a", "b"])
        #expect(candidates.map(\.filteredIndex) == [0, 1])
    }
}

