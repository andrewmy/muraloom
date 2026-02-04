import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        SettingsView(settings: settings)
            .frame(minWidth: 520, minHeight: 560)
    }
}

#Preview {
    let settings = SettingsModel()
    let authService = OneDriveAuthService()
    let photosService = OneDrivePhotosService(authService: authService)
    return ContentView()
        .environmentObject(settings)
        .environmentObject(authService)
        .environmentObject(photosService)
        .environmentObject(WallpaperManager(photosService: DummyOneDrivePhotosService(), settings: settings))
}
