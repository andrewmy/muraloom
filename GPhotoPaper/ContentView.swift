import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: SettingsModel

    var body: some View {
        VStack {
            Text("GPhotoPaper")
                .font(.largeTitle)
            
            // Pass the settings model to the SettingsView
            SettingsView(settings: settings)
        }
        .padding()
        .frame(width: 450, height: 350)
    }
}

#Preview {
    let settings = SettingsModel()
    return ContentView()
        .environmentObject(settings)
        .environmentObject(WallpaperManager(photosService: DummyOneDrivePhotosService(), settings: settings))
}
