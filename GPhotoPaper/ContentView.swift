import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsModel
    @State private var showAdvancedControls: Bool = false

    private let windowWidth: CGFloat = 560

    var body: some View {
        VStack(spacing: 16) {
            Text("GPhotoPaper")
                .font(.largeTitle)

            SettingsView(settings: settings, showAdvancedControls: $showAdvancedControls)
                .frame(maxWidth: 520)
        }
        .padding(24)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: windowWidth, alignment: .top)
        .animation(.snappy, value: showAdvancedControls)
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
