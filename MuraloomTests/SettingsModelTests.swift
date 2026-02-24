import Foundation
import Testing
@testable import Muraloom

struct SettingsModelTests {
    private func makeUserDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "SettingsModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func cleanUpUserDefaults(named suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    @Test func defaultsFallbackWhenPersistedValuesAreMissingOrInvalid() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanUpUserDefaults(named: suiteName) }

        defaults.set("not_a_frequency", forKey: "changeFrequency")
        defaults.set("not_a_fill_mode", forKey: "wallpaperFillMode")
        defaults.set("", forKey: "selectedAlbumId")
        defaults.set("", forKey: "selectedAlbumName")
        defaults.set("", forKey: "selectedAlbumWebUrl")
        defaults.set(0, forKey: "lastSuccessfulWallpaperUpdate")
        defaults.set("", forKey: "lastSetWallpaperItemId")
        defaults.set("", forKey: "lastSetWallpaperItemName")
        defaults.set(0.0, forKey: "minimumPictureWidth")

        let model = SettingsModel(userDefaults: defaults)

        #expect(model.changeFrequency == .daily)
        #expect(model.wallpaperFillMode == .fill)
        #expect(model.selectedAlbumId == nil)
        #expect(model.selectedAlbumName == nil)
        #expect(model.selectedAlbumWebUrl == nil)
        #expect(model.lastSuccessfulWallpaperUpdate == nil)
        #expect(model.lastSetWallpaperItemId == nil)
        #expect(model.lastSetWallpaperItemName == nil)
        #expect(model.minimumPictureWidth == Double(WallpaperImageTranscoder.maxRecommendedDisplayPixelWidth()))
    }

    @Test func initLoadsPersistedValuesAndParsesOptionalFields() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanUpUserDefaults(named: suiteName) }

        let savedDate = Date(timeIntervalSince1970: 1_700_000_123)
        defaults.set("six_hours", forKey: "changeFrequency")
        defaults.set(true, forKey: "isPaused")
        defaults.set(true, forKey: "pickRandomly")
        defaults.set(3100.0, forKey: "minimumPictureWidth")
        defaults.set(true, forKey: "horizontalPhotosOnly")
        defaults.set("fit", forKey: "wallpaperFillMode")
        defaults.set("album-1", forKey: "selectedAlbumId")
        defaults.set("Vacation", forKey: "selectedAlbumName")
        defaults.set("https://photos.onedrive.com/album-1", forKey: "selectedAlbumWebUrl")
        defaults.set(9, forKey: "lastPickedIndex")
        defaults.set(savedDate.timeIntervalSince1970, forKey: "lastSuccessfulWallpaperUpdate")
        defaults.set("item-42", forKey: "lastSetWallpaperItemId")
        defaults.set("frame.jpg", forKey: "lastSetWallpaperItemName")

        let model = SettingsModel(userDefaults: defaults)

        #expect(model.changeFrequency == .sixHours)
        #expect(model.isPaused)
        #expect(model.pickRandomly)
        #expect(model.minimumPictureWidth == 3100.0)
        #expect(model.horizontalPhotosOnly)
        #expect(model.wallpaperFillMode == .fit)
        #expect(model.selectedAlbumId == "album-1")
        #expect(model.selectedAlbumName == "Vacation")
        #expect(model.selectedAlbumWebUrl?.absoluteString == "https://photos.onedrive.com/album-1")
        #expect(model.lastPickedIndex == 9)
        #expect(model.lastSuccessfulWallpaperUpdate == savedDate)
        #expect(model.lastSetWallpaperItemId == "item-42")
        #expect(model.lastSetWallpaperItemName == "frame.jpg")
    }

    @Test func publishedPropertyChangesPersistMachineReadableValues() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanUpUserDefaults(named: suiteName) }

        let model = SettingsModel(userDefaults: defaults)
        let updatedAt = Date(timeIntervalSince1970: 1_700_123_456)
        let albumURL = URL(string: "https://photos.onedrive.com/new-album")!

        model.changeFrequency = .hourly
        model.isPaused = true
        model.pickRandomly = true
        model.minimumPictureWidth = 2800.0
        model.horizontalPhotosOnly = true
        model.wallpaperFillMode = .stretch
        model.selectedAlbumId = "album-22"
        model.selectedAlbumName = "Trip"
        model.selectedAlbumWebUrl = albumURL
        model.lastPickedIndex = 4
        model.lastSetWallpaperItemId = "item-7"
        model.lastSetWallpaperItemName = "best.jpg"
        model.lastSuccessfulWallpaperUpdate = updatedAt

        #expect(defaults.string(forKey: "changeFrequency") == "hourly")
        #expect(defaults.bool(forKey: "isPaused"))
        #expect(defaults.bool(forKey: "pickRandomly"))
        #expect(defaults.double(forKey: "minimumPictureWidth") == 2800.0)
        #expect(defaults.bool(forKey: "horizontalPhotosOnly"))
        #expect(defaults.string(forKey: "wallpaperFillMode") == "stretch")
        #expect(defaults.string(forKey: "selectedAlbumId") == "album-22")
        #expect(defaults.string(forKey: "selectedAlbumName") == "Trip")
        #expect(defaults.string(forKey: "selectedAlbumWebUrl") == albumURL.absoluteString)
        #expect(defaults.integer(forKey: "lastPickedIndex") == 4)
        #expect(defaults.string(forKey: "lastSetWallpaperItemId") == "item-7")
        #expect(defaults.string(forKey: "lastSetWallpaperItemName") == "best.jpg")
        #expect(defaults.double(forKey: "lastSuccessfulWallpaperUpdate") == updatedAt.timeIntervalSince1970)

        model.lastSuccessfulWallpaperUpdate = nil
        #expect(defaults.object(forKey: "lastSuccessfulWallpaperUpdate") == nil)
    }

    @Test @MainActor func flushToDiskWritesLatestValues() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { cleanUpUserDefaults(named: suiteName) }

        let model = SettingsModel(userDefaults: defaults)
        model.changeFrequency = .never
        model.wallpaperFillMode = .center
        model.flushToDisk()

        #expect(defaults.string(forKey: "changeFrequency") == "never")
        #expect(defaults.string(forKey: "wallpaperFillMode") == "center")
    }
}
