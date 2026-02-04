import SwiftUI

@main
struct GPhotoPaperApp: App {
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
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(authService)
                .environmentObject(photosService)
                .environmentObject(wallpaperManager)
                .onAppear {
                    wallpaperManager.startWallpaperUpdates()
                }
                .onChange(of: settings.changeFrequency) { _, _ in
                    wallpaperManager.startWallpaperUpdates()
                }
        }
    }
}

protocol PhotosService {
    func searchPhotos(in folderId: String) async throws -> [MediaItem]
    func verifyFolderExists(folderId: String) async throws -> OneDriveFolder?
}

// Dummy service to keep the app building until OneDrive integration is implemented.
final class DummyOneDrivePhotosService: PhotosService {
    func searchPhotos(in folderId: String) async throws -> [MediaItem] { [] }
    func verifyFolderExists(folderId: String) async throws -> OneDriveFolder? { nil }
}

// These are placeholders and will be implemented with Microsoft Graph responses later.
struct MediaItem: Codable, Identifiable {
    var id: String
    var downloadUrl: URL
    var pixelWidth: Int?
    var pixelHeight: Int?
}

struct OneDriveFolder: Codable {
    var id: String
    var webUrl: URL?
    var name: String?
}
