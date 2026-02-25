import AppKit
import Foundation
import SwiftUI

@main
struct MuraloomApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsModel
    @StateObject private var authService: AuthService
    @StateObject private var photosService: PhotosServiceModel
    @StateObject private var wallpaperManager: WallpaperManager
    @StateObject private var appTesting: AppTesting

    init() {
        let isUITesting = AppEnvironment.isUITesting

        let settings: SettingsModel
        let authService: AuthService
        let photosService: PhotosServiceModel
        let wallpaperApplier: any WallpaperApplying
        let appSupportProvider: (() throws -> URL)?

        if isUITesting {
            let defaults = UserDefaults(suiteName: AppEnvironment.uiTestUserDefaultsSuiteName)
            defaults?.removePersistentDomain(forName: AppEnvironment.uiTestUserDefaultsSuiteName)

            let model = SettingsModel(userDefaults: defaults ?? .standard)
            model.changeFrequency = .never
            model.isPaused = true
            settings = model

            authService = UITestAuthService()

            let mode = AppEnvironment.uiTestPhotosMode
            photosService = UITestPhotosService(config: .init(mode: mode))
            wallpaperApplier = UITestWallpaperApplier()
            let base = AppEnvironment.uiTestCacheBaseDirectory
            try? FileManager.default.removeItem(at: base)
            try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            appSupportProvider = {
                return base
            }
        } else {
            settings = SettingsModel()

            let liveAuth = OneDriveAuthService()
            authService = liveAuth
            photosService = OneDrivePhotosService(authService: liveAuth)
            wallpaperApplier = SystemWallpaperApplier()
            appSupportProvider = nil
        }

        _appTesting = StateObject(wrappedValue: AppTesting(isUITesting: isUITesting))
        _settings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: authService)
        _photosService = StateObject(wrappedValue: photosService)

        _wallpaperManager = StateObject(
            wrappedValue: WallpaperManager(
                photosService: photosService,
                settings: settings,
                wallpaperApplier: wallpaperApplier,
                applicationSupportDirectoryProvider: appSupportProvider ?? {
                    try FileManager.default.url(
                        for: .applicationSupportDirectory,
                        in: .userDomainMask,
                        appropriateFor: nil,
                        create: true
                    )
                }
            )
        )
    }

    var body: some Scene {
        WindowGroup(id: "settings") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(authService)
                .environmentObject(photosService)
                .environmentObject(wallpaperManager)
                .environmentObject(appTesting)
                .onAppear {
                    if authService.isSignedIn {
                        wallpaperManager.startWallpaperUpdates()
                    } else {
                        wallpaperManager.stopWallpaperUpdates()
                    }
                }
                .onChange(of: settings.changeFrequency) { _, _ in
                    if authService.isSignedIn {
                        wallpaperManager.startWallpaperUpdates()
                    } else {
                        wallpaperManager.stopWallpaperUpdates()
                    }
                }
                .onChange(of: settings.isPaused) { _, newValue in
                    if authService.isSignedIn == false {
                        wallpaperManager.stopWallpaperUpdates()
                    } else if newValue {
                        wallpaperManager.stopWallpaperUpdates()
                    } else {
                        wallpaperManager.startWallpaperUpdates()
                    }
                }
                .onChange(of: authService.isSignedIn) { _, isSignedIn in
                    if isSignedIn {
                        wallpaperManager.startWallpaperUpdates()
                    } else {
                        wallpaperManager.stopWallpaperUpdates()
                    }
                }
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarMenuView()
                .environmentObject(settings)
                .environmentObject(authService)
                .environmentObject(wallpaperManager)
        } label: {
            MenuBarLabelView()
                .environmentObject(settings)
                .environmentObject(authService)
                .environmentObject(wallpaperManager)
        }
        .menuBarExtraStyle(.menu)
    }
}

protocol PhotosService {
    func scanAlbum(inAlbumId albumId: String) async throws -> AlbumScanResult
    func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem]
    func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum?
    func downloadImageData(for item: MediaItem) async throws -> Data
}

extension PhotosService {
    func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] {
        try await scanAlbum(inAlbumId: albumId).usableItems
    }
}

// Dummy service to keep the app building until OneDrive integration is implemented.
final class DummyOneDrivePhotosService: PhotosService {
    func scanAlbum(inAlbumId albumId: String) async throws -> AlbumScanResult {
        AlbumScanResult(usableItems: [], nonUsableExclusions: [], scannedAt: Date())
    }

    func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? { nil }
    func downloadImageData(for item: MediaItem) async throws -> Data { throw URLError(.unsupportedURL) }
}

// These are placeholders and will be implemented with Microsoft Graph responses later.
struct MediaItem: Codable, Identifiable {
    var id: String
    var downloadUrl: URL?
    var webUrl: URL? = nil
    var pixelWidth: Int?
    var pixelHeight: Int?
    var name: String?
    var mimeType: String?
    var cTag: String?
}

struct OneDriveAlbum: Codable {
    var id: String
    var webUrl: URL?
    var name: String?
}

enum AppEnvironment {
    static let uiTestUserDefaultsSuiteName = "lv.andr.muraloom.uitests"
    static let uiTestPhotosModeEnvironmentKey = "MURALOOM_UI_TEST_PHOTOS_MODE"
    static let uiTestCacheBaseDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("MuraloomUITestCache", isDirectory: true)

    static var isUITesting: Bool {
#if DEBUG
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-ui-testing") { return true }
        if ProcessInfo.processInfo.environment["MURALOOM_UI_TESTING"] == "1" { return true }
        return false
#else
        return false
#endif
    }

    static var uiTestPhotosMode: UITestPhotosService.PhotosMode {
#if DEBUG
        guard isUITesting else { return .normal }
        let raw = (ProcessInfo.processInfo.environment[uiTestPhotosModeEnvironmentKey] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return UITestPhotosService.PhotosMode(rawValue: raw) ?? .normal
#else
        return .normal
#endif
    }
}

private final class UITestWallpaperApplier: WallpaperApplying {
    var screenCount: Int { 1 }
    private var currentURL: URL?

    func currentWallpaperURL() -> URL? {
        currentURL
    }

    func setWallpaper(
        _ wallpaperFileURL: URL,
        options: [NSWorkspace.DesktopImageOptionKey: Any]
    ) throws {
        currentURL = wallpaperFileURL
    }
}
