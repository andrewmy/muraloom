import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @EnvironmentObject var authService: OneDriveAuthService
    @EnvironmentObject var photosService: OneDrivePhotosService
    @EnvironmentObject var wallpaperManager: WallpaperManager

    @State private var albums: [OneDriveAlbum] = []
    @State private var isSigningIn: Bool = false
    @State private var isLoadingAlbums: Bool = false
    @State private var oneDriveError: String?

    var body: some View {
        Form {
            Section(header: Text("OneDrive")) {
                if authService.isSignedIn {
                    Text("Signed in.")
                    Button("Sign Out") {
                        authService.signOut()
                        albums = []
                        settings.selectedAlbumId = nil
                        settings.selectedAlbumName = nil
                        settings.selectedAlbumWebUrl = nil
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

            Section(header: Text("OneDrive Album")) {
                if authService.isSignedIn {
                    Button(isLoadingAlbums ? "Loading…" : "Load Albums") {
                        isLoadingAlbums = true
                        oneDriveError = nil
                        Task {
                            do {
                                albums = try await photosService.listAlbums()
                                if settings.selectedAlbumId == nil, let first = albums.first {
                                    applySelectedAlbum(first)
                                }
                            } catch {
                                oneDriveError = error.localizedDescription
                            }
                            isLoadingAlbums = false
                        }
                    }
                    .disabled(isLoadingAlbums)

                    if albums.isEmpty {
                        Text("No albums loaded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker(
                            "Album",
                            selection: Binding(
                                get: { settings.selectedAlbumId ?? "" },
                                set: { newValue in
                                    guard let match = albums.first(where: { $0.id == newValue }) else { return }
                                    applySelectedAlbum(match)
                                }
                            )
                        ) {
                            ForEach(albums, id: \.id) { album in
                                Text(album.name ?? album.id).tag(album.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                
                    TextField(
                        "Album ID (manual)",
                        text: Binding(
                            get: { settings.selectedAlbumId ?? "" },
                            set: { settings.selectedAlbumId = $0.isEmpty ? nil : $0 }
                        )
                    )

                    if let albumId = settings.selectedAlbumId, !albumId.isEmpty {
                        Button("Validate Album ID") {
                            oneDriveError = nil
                            Task {
                                do {
                                    if let album = try await photosService.verifyAlbumExists(albumId: albumId) {
                                        applySelectedAlbum(album)
                                    } else {
                                        oneDriveError = "That ID is not an album (bundle album), or it isn’t accessible."
                                    }
                                } catch {
                                    oneDriveError = error.localizedDescription
                                }
                            }
                        }
                    }

                    if let name = settings.selectedAlbumName, !name.isEmpty {
                        Text("Selected: \(name)")
                    }

                    if let url = settings.selectedAlbumWebUrl {
                        Link("Open in OneDrive", destination: url)
                    }

                    if let albumId = settings.selectedAlbumId, !albumId.isEmpty {
                        Button("Check Album Photos") {
                            oneDriveError = nil
                            Task {
                                do {
                                    let photos = try await photosService.searchPhotos(inAlbumId: albumId)
                                    settings.albumPictureCount = photos.count
                                    settings.showNoPicturesWarning = photos.isEmpty
                                } catch {
                                    oneDriveError = error.localizedDescription
                                }
                            }
                        }
                        if settings.albumPictureCount > 0 {
                            Text("Photos: \(settings.albumPictureCount)")
                                .foregroundStyle(.secondary)
                        }
                        if settings.showNoPicturesWarning {
                            Text("This album has no photos.")
                                .foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Sign in to load and select an album.")
                        .foregroundStyle(.secondary)
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
    }

    private func applySelectedAlbum(_ album: OneDriveAlbum) {
        settings.selectedAlbumId = album.id
        settings.selectedAlbumName = album.name
        settings.selectedAlbumWebUrl = album.webUrl
        settings.albumPictureCount = 0
        settings.showNoPicturesWarning = false
    }
}
