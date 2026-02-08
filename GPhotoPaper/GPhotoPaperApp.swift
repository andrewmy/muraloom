import SwiftUI

@main
struct GPhotoPaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settings: SettingsModel
    @StateObject private var authService: OneDriveAuthService
    @StateObject private var photosService: OneDrivePhotosService
    @StateObject private var wallpaperManager: WallpaperManager

    init() {
        let settings = SettingsModel()
        let authService = OneDriveAuthService()
        let photosService = OneDrivePhotosService(authService: authService)
        _settings = StateObject(wrappedValue: settings)
        _authService = StateObject(wrappedValue: authService)
        _photosService = StateObject(wrappedValue: photosService)

        _wallpaperManager = StateObject(
            wrappedValue: WallpaperManager(
                photosService: photosService,
                settings: settings
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
    func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem]
    func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum?
    func downloadImageData(for item: MediaItem) async throws -> Data
}

// Dummy service to keep the app building until OneDrive integration is implemented.
final class DummyOneDrivePhotosService: PhotosService {
    func searchPhotos(inAlbumId albumId: String) async throws -> [MediaItem] { [] }
    func verifyAlbumExists(albumId: String) async throws -> OneDriveAlbum? { nil }
    func downloadImageData(for item: MediaItem) async throws -> Data { throw URLError(.unsupportedURL) }
}

// These are placeholders and will be implemented with Microsoft Graph responses later.
struct MediaItem: Codable, Identifiable {
    var id: String
    var downloadUrl: URL?
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
