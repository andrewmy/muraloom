import SwiftUI

@main
struct GPhotoPaperApp: App {
    @StateObject private var settings: SettingsModel
    @StateObject private var wallpaperManager: WallpaperManager

    init() {
        let settings = SettingsModel()
        _settings = StateObject(wrappedValue: settings)

        // TODO: Replace DummyOneDrivePhotosService with a real Microsoft Graph implementation.
        _wallpaperManager = StateObject(
            wrappedValue: WallpaperManager(
                photosService: DummyOneDrivePhotosService(),
                settings: settings
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(wallpaperManager)
                .onAppear {
                    wallpaperManager.startWallpaperUpdates()
                }
                .onChange(of: settings.changeFrequency) { _ in
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
