import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @EnvironmentObject var wallpaperManager: WallpaperManager

    var body: some View {
        Form {
            Section(header: Text("OneDrive Folder")) {
                Text("OneDrive integration is not yet implemented. For now, you can set a folder ID manually (used by the future Graph client).")

                TextField(
                    "Folder ID",
                    text: Binding(
                        get: { settings.selectedFolderId ?? "" },
                        set: { settings.selectedFolderId = $0.isEmpty ? nil : $0 }
                    )
                )

                if let name = settings.selectedFolderName, !name.isEmpty {
                    Text("Selected: \(name)")
                }

                if let url = settings.selectedFolderWebUrl {
                    Link("Open in OneDrive", destination: url)
                }
            }

            Section(header: Text("Wallpaper Change Settings")) {
                Picker("Change Frequency", selection: $settings.changeFrequency) {
                    ForEach(WallpaperChangeFrequency.allCases) { frequency in
                        Text(frequency.rawValue).tag(frequency)
                    }
                }
                .pickerStyle(.menu)

                Toggle("Pick Randomly", isOn: $settings.pickRandomly)

                HStack {
                    Text("Minimum Picture Width:")
                    TextField("", value: $settings.minimumPictureWidth, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("px")
                }

                Toggle("Only Horizontal Photos", isOn: $settings.horizontalPhotosOnly)

                Picker("Fill Mode", selection: $settings.wallpaperFillMode) {
                    ForEach(WallpaperFillMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Button("Change Wallpaper Now") {
                    Task {
                        await wallpaperManager.updateWallpaper()
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
    }
}
