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
    ContentView()
        .environmentObject(SettingsModel()) // Provide a dummy service for preview
}