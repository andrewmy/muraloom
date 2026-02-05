import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        VStack(spacing: 16) {
            Text("GPhotoPaper")
                .font(.largeTitle)

            SettingsView(settings: settings)
                .frame(maxWidth: 520)
        }
        .padding(24)
        .frame(minWidth: 560, idealWidth: 560, minHeight: 520, idealHeight: 520)
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
