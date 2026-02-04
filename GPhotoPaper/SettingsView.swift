import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @EnvironmentObject var authService: OneDriveAuthService
    @EnvironmentObject var photosService: OneDrivePhotosService
    @EnvironmentObject var wallpaperManager: WallpaperManager

    @State private var folders: [OneDriveFolder] = []
    @State private var isSigningIn: Bool = false
    @State private var isLoadingFolders: Bool = false
    @State private var oneDriveError: String?

    var body: some View {
        Form {
            Section(header: Text("OneDrive")) {
                if authService.isSignedIn {
                    Text("Signed in.")
                    Button("Sign Out") {
                        authService.signOut()
                        folders = []
                    }
                } else {
                    Button(isSigningIn ? "Signing In…" : "Sign In") {
                        isSigningIn = true
                        oneDriveError = nil
                        Task {
                            do {
                                try await authService.signIn()
                            } catch {
                                oneDriveError = error.localizedDescription
                            }
                            isSigningIn = false
                        }
                    }
                    .disabled(isSigningIn)
                }

                if let oneDriveError, !oneDriveError.isEmpty {
                    Text(oneDriveError)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(header: Text("OneDrive Folder")) {
                if authService.isSignedIn {
                    Button(isLoadingFolders ? "Loading…" : "Load Folders") {
                        isLoadingFolders = true
                        oneDriveError = nil
                        Task {
                            do {
                                folders = try await photosService.listFoldersInRoot()
                                if settings.selectedFolderId == nil, let first = folders.first {
                                    applySelectedFolder(first)
                                }
                            } catch {
                                oneDriveError = error.localizedDescription
                            }
                            isLoadingFolders = false
                        }
                    }
                    .disabled(isLoadingFolders)

                    if folders.isEmpty {
                        Text("No folders loaded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "Folder",
                            selection: Binding(
                                get: { settings.selectedFolderId ?? "" },
                                set: { newValue in
                                    guard let match = folders.first(where: { $0.id == newValue }) else { return }
                                    applySelectedFolder(match)
                                }
                            )
                        ) {
                            ForEach(folders, id: \.id) { folder in
                                Text(folder.name ?? folder.id).tag(folder.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                TextField(
                    "Folder ID (manual)",
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

    private func applySelectedFolder(_ folder: OneDriveFolder) {
        settings.selectedFolderId = folder.id
        settings.selectedFolderName = folder.name
        settings.selectedFolderWebUrl = folder.webUrl
    }
}
