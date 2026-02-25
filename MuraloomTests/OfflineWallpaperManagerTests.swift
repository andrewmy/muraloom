import AppKit
import Foundation
import Testing
@testable import Muraloom

@MainActor
struct OfflineWallpaperManagerTests {
    private final class TestWallpaperApplier: WallpaperApplying {
        var screenCount: Int = 1
        var currentURL: URL?
        var setCalls: Int = 0

        func currentWallpaperURL() -> URL? {
            currentURL
        }

        func setWallpaper(
            _ wallpaperFileURL: URL,
            options: [NSWorkspace.DesktopImageOptionKey: Any]
        ) throws {
            setCalls += 1
            currentURL = wallpaperFileURL
        }
    }

    private final class MockPhotosService: PhotosServiceModel {
        var items: [MediaItem] = []
        var searchError: Error?
        var downloadData: Data

        private(set) var searchPhotosCalls: Int = 0
        private(set) var downloadCalls: Int = 0

        init(items: [MediaItem], downloadData: Data) {
            self.items = items
            self.downloadData = downloadData
            super.init()
        }

        override func scanAlbum(inAlbumId albumId: String) async throws -> AlbumScanResult {
            if let searchError { throw searchError }
            return AlbumScanResult(usableItems: items, nonUsableExclusions: [], scannedAt: Date())
        }

        override func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] {
            searchPhotosCalls += 1
            if let searchError { throw searchError }
            return items
        }

        override func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? {
            OneDriveAlbum(id: albumId, webUrl: nil, name: "Album")
        }

        override func downloadImageData(for item: MediaItem) async throws -> Data {
            downloadCalls += 1
            return downloadData
        }
    }

    private func makeUserDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "OfflineWallpaperManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    private func removeUserDefaults(named suiteName: String) {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    private func makeTempBaseDir() -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("offline-wallpaper-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func waitForUpdateCompletion(_ manager: WallpaperManager) async {
        for _ in 0..<300 {
            if manager.isUpdating == false { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        Issue.record("Timed out waiting for wallpaper update to complete")
    }

    private func png1x1Data() -> Data {
        Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMB/6X0mXcAAAAASUVORK5CYII="
        )!
    }

    private func makeMediaItems() -> [MediaItem] {
        [
            MediaItem(
                id: "photo-1",
                downloadUrl: nil,
                webUrl: nil,
                pixelWidth: 4000,
                pixelHeight: 3000,
                name: "Photo 1",
                mimeType: "image/png",
                cTag: "c1"
            )
        ]
    }

    private func makeManager(
        photosService: MockPhotosService,
        wallpaperApplier: TestWallpaperApplier,
        baseDir: URL,
        settings: SettingsModel
    ) -> WallpaperManager {
        WallpaperManager(
            photosService: photosService,
            settings: settings,
            wallpaperApplier: wallpaperApplier,
            applicationSupportDirectoryProvider: { baseDir }
        )
    }

    private func prepareSettings(_ defaults: UserDefaults) -> SettingsModel {
        let settings = SettingsModel(userDefaults: defaults)
        settings.selectedAlbumId = "album-1"
        settings.minimumPictureWidth = 0
        settings.horizontalPhotosOnly = false
        settings.pickRandomly = true
        return settings
    }

    @Test func offlineFallbackUsesCacheAndCooldownSkipsNetwork() async {
        let (defaults, suiteName) = makeUserDefaults()
        defer { removeUserDefaults(named: suiteName) }

        let baseDir = makeTempBaseDir()
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let settings = prepareSettings(defaults)
        let photosService = MockPhotosService(items: makeMediaItems(), downloadData: png1x1Data())
        let wallpaperApplier = TestWallpaperApplier()
        let manager = makeManager(
            photosService: photosService,
            wallpaperApplier: wallpaperApplier,
            baseDir: baseDir,
            settings: settings
        )

        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)
        #expect(manager.lastUpdateError == nil)
        #expect(manager.cacheReadyCount >= 1)

        photosService.searchError = URLError(.notConnectedToInternet)
        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)

        #expect(manager.isUsingCachedFallback)
        #expect(manager.lastUpdateError == nil)
        #expect(manager.offlineCooldownUntil != nil)

        let callsAfterFirstOfflineAttempt = photosService.searchPhotosCalls
        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)

        #expect(manager.isUsingCachedFallback)
        #expect(photosService.searchPhotosCalls == callsAfterFirstOfflineAttempt)
    }

    @Test func offlineFailureWithoutCacheShowsActionableMessage() async {
        let (defaults, suiteName) = makeUserDefaults()
        defer { removeUserDefaults(named: suiteName) }

        let baseDir = makeTempBaseDir()
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let settings = prepareSettings(defaults)
        let photosService = MockPhotosService(items: makeMediaItems(), downloadData: png1x1Data())
        photosService.searchError = URLError(.notConnectedToInternet)
        let wallpaperApplier = TestWallpaperApplier()
        let manager = makeManager(
            photosService: photosService,
            wallpaperApplier: wallpaperApplier,
            baseDir: baseDir,
            settings: settings
        )

        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)

        let message = manager.lastUpdateError ?? ""
        #expect(message.contains("Offline and no cached photos are available"))
        #expect(manager.isUsingCachedFallback == false)
        #expect(manager.cacheReadyCount == 0)
        #expect(manager.offlineCooldownUntil != nil)
    }

    @Test func retryOnlineNowBypassesCooldownAndAttemptsNetwork() async {
        let (defaults, suiteName) = makeUserDefaults()
        defer { removeUserDefaults(named: suiteName) }

        let baseDir = makeTempBaseDir()
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let settings = prepareSettings(defaults)
        let photosService = MockPhotosService(items: makeMediaItems(), downloadData: png1x1Data())
        let wallpaperApplier = TestWallpaperApplier()
        let manager = makeManager(
            photosService: photosService,
            wallpaperApplier: wallpaperApplier,
            baseDir: baseDir,
            settings: settings
        )

        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)

        photosService.searchError = URLError(.networkConnectionLost)
        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)
        #expect(manager.isUsingCachedFallback)
        #expect(manager.offlineCooldownUntil != nil)

        photosService.searchError = nil
        let callsBeforeNormalManualInCooldown = photosService.searchPhotosCalls
        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)
        #expect(photosService.searchPhotosCalls == callsBeforeNormalManualInCooldown)

        manager.retryOnlineNow()
        await waitForUpdateCompletion(manager)

        #expect(photosService.searchPhotosCalls == callsBeforeNormalManualInCooldown + 1)
        #expect(manager.isUsingCachedFallback == false)
        #expect(manager.offlineCooldownUntil == nil)
    }

    @Test func authRequiredErrorDoesNotUseOfflineFallback() async {
        let (defaults, suiteName) = makeUserDefaults()
        defer { removeUserDefaults(named: suiteName) }

        let baseDir = makeTempBaseDir()
        defer { try? FileManager.default.removeItem(at: baseDir) }

        let settings = prepareSettings(defaults)
        let photosService = MockPhotosService(items: makeMediaItems(), downloadData: png1x1Data())
        let wallpaperApplier = TestWallpaperApplier()
        let manager = makeManager(
            photosService: photosService,
            wallpaperApplier: wallpaperApplier,
            baseDir: baseDir,
            settings: settings
        )

        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)
        #expect(manager.cacheReadyCount >= 1)

        photosService.searchError = OneDriveAuthError.providerError(details: "Token endpoint error: invalid_grant")
        manager.requestWallpaperUpdate(trigger: .manual)
        await waitForUpdateCompletion(manager)

        #expect(manager.isUsingCachedFallback == false)
        #expect(manager.offlineCooldownUntil == nil)
        #expect((manager.lastUpdateError ?? "").contains("Sign-in is required"))
    }
}
