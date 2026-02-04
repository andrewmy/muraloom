import SwiftUI

@main
struct GPhotoPaperApp: App {
    @State private var settings = SettingsModel()
    // TODO: Implement these services
    // @StateObject private var authService = OneDriveAuthService()
    // @State private var photosService: OneDrivePhotosService
    @State private var wallpaperManager: WallpaperManager

    init() {
        let settings = SettingsModel()
        _settings = State(wrappedValue: settings)

        // TODO: Initialize with proper OneDrive services
        // let photosService = OneDrivePhotosService(authService: authService, settings: settings)
        // _photosService = State(wrappedValue: photosService)

        // TODO: Update WallpaperManager to not depend on a photos service directly
        //       or create a protocol that both GooglePhotosService and OneDrivePhotosService can conform to.
        // _wallpaperManager = State(wrappedValue: WallpaperManager(photosService: photosService, settings: settings))
        _wallpaperManager = State(wrappedValue: WallpaperManager(photosService: DummyPhotosService(), settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                // .environmentObject(authService)
                // .environmentObject(photosService)
                .environmentObject(wallpaperManager)
        }
    }
}

// Dummy service to avoid compilation errors
class DummyPhotosService {
    func searchPhotos(in albumId: String) async throws -> [MediaItem] {
        return []
    }

    func verifyAlbumExists(albumId: String) async throws -> Album? {
        return nil
    }
}

// These are placeholders and will be implemented later
struct MediaItem: Codable, Identifiable {
    var id: String
    var baseUrl: URL
}

struct Album: Codable {
    var id: String
    var productUrl: String
}