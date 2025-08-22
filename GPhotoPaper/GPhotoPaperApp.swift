import SwiftUI
import GoogleSignIn

@main
struct GPhotoPaperApp: App {
    @StateObject private var authService = GoogleAuthService()
    @State private var settings = SettingsModel()
    @State private var photosService: GooglePhotosService
    @State private var wallpaperManager: WallpaperManager

    init() {
        let authService = GoogleAuthService()
        _authService = StateObject(wrappedValue: authService)

        let settings = SettingsModel()
        _settings = State(wrappedValue: settings)

        let photosService = GooglePhotosService(authService: authService, settings: settings)
        _photosService = State(wrappedValue: photosService)

        _wallpaperManager = State(wrappedValue: WallpaperManager(photosService: photosService, settings: settings))

        // Configure Google Sign-In
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "551418211174-tp2fuecl5kqf70p4nj8rg1ap2e7uok3b.apps.googleusercontent.com"
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authService)
                .environmentObject(settings)
                .environmentObject(photosService)
                .environmentObject(wallpaperManager)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
                .onChange(of: authService.user) { _ in
                    // When the user signs in or out, create a new SettingsModel
                    // to ensure we have a clean slate.
                    let newSettings = SettingsModel()
                    self.settings = newSettings
                    let newPhotosService = GooglePhotosService(authService: authService, settings: newSettings)
                    self.photosService = newPhotosService
                    self.wallpaperManager = WallpaperManager(photosService: newPhotosService, settings: newSettings)
                }
        }
    }
}

