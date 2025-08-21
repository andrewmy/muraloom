import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @EnvironmentObject var authService: GoogleAuthService
    @EnvironmentObject var photosService: GooglePhotosService

    @State private var errorMessage: String? = nil

    var body: some View {
        Form {
            Section(header: Text("Google Photos Album")) {
                if let albumName = settings.appCreatedAlbumName {
                    Text("Using album: \(albumName)")
                    Text("Please add photos to this album in Google Photos.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No app-managed album found.")
                    Button("Create New Album") {
                        Task {
                            await createAndSetAlbum()
                        }
                    }
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
                    // Action to change wallpaper immediately
                }
            }
        }
        .padding()
        .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
        .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { _ in errorMessage = nil })) {
            Button("OK") { }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private func createAndSetAlbum() async {
        errorMessage = nil
        let defaultAlbumName = "GPhotoPaper" // Corrected default name
        do {
            var album: GooglePhotosAlbum
            do {
                // Try creating with default name first
                album = try await photosService.createAppAlbum(albumName: defaultAlbumName)
            } catch let error as GooglePhotosServiceError {
                // If it's a conflict error (album already exists), try with UUID
                if case .networkError(let statusCode, _) = error, statusCode == 409 { // 409 Conflict
                    let uniqueAlbumName = "\(defaultAlbumName) - \(UUID().uuidString.prefix(8))" // Use defaultAlbumName here
                    album = try await photosService.createAppAlbum(albumName: uniqueAlbumName)
                } else {
                    throw error // Re-throw other errors
                }
            }

            settings.appCreatedAlbumId = album.id
            settings.appCreatedAlbumName = album.title
            // Persist album ID (will implement later using UserDefaults)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}