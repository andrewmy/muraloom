import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: SettingsModel
    @Binding var showAdvancedControls: Bool
    @EnvironmentObject var authService: OneDriveAuthService
    @EnvironmentObject var photosService: OneDrivePhotosService
    @EnvironmentObject var wallpaperManager: WallpaperManager

    private let usablePhotosHelp =
        "Usable photos are image items (image/* files or items with image/photo metadata). Videos are ignored. RAW photos (ARW/DNG/etc) are included only when LibRaw support is enabled. The quick check scans only the first page."

    @State private var albums: [OneDriveAlbum] = []
    @State private var isSigningIn: Bool = false
    @State private var isLoadingAlbums: Bool = false
    @State private var didAttemptLoadAlbums: Bool = false
    @State private var didValidateStoredSelection: Bool = false
    @State private var didAutoLoadAlbums: Bool = false
    @State private var selectedAlbumUsableCountFirstPage: Int?
    @State private var oneDriveError: String?
#if DEBUG
    @State private var oneDriveDebugInfo: String?
#endif

    private var recommendedMinimumPictureWidthPixels: Double {
        Double(WallpaperImageTranscoder.maxRecommendedDisplayPixelWidth())
    }

    private func stageText(_ stage: WallpaperManager.WallpaperUpdateStage) -> String {
        switch stage {
        case .idle:
            return "Idle"
        case .fetchingAlbumItems:
            return "Fetching album items…"
        case .filtering:
            return "Filtering candidates…"
        case .selectingCandidate(let attempt, let total, let name):
            return "Trying \(attempt)/\(max(1, total)): \(name)"
        case .usingCachedWallpaper(let name):
            return "Using cached: \(name)"
        case .downloading(let name, let attempt, let total):
            return "Downloading \(attempt)/\(max(1, total)): \(name)…"
        case .decoding(let name):
            return "Decoding/transcoding: \(name)…"
        case .writingFile(let name):
            return "Writing JPEG: \(name)…"
        case .applyingToScreens(let screenCount):
            return "Applying to \(screenCount) screen(s)…"
        case .done(let name):
            return name.isEmpty ? "Done" : "Done: \(name)"
        }
    }

    var body: some View {
        Form {
            Section {
                if authService.isSignedIn {
                    if let username = authService.signedInUsername, !username.isEmpty {
                        Text("Signed in as \(username).")
                    } else {
                        Text("Signed in.")
                    }
                    Button {
                        authService.signOut()
                        wallpaperManager.stopWallpaperUpdates()
                        albums = []
                        didAttemptLoadAlbums = false
                        didAutoLoadAlbums = false
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } else {
                    Button {
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
                    } label: {
                        Label(isSigningIn ? "Signing In…" : "Sign In", systemImage: "person.crop.circle.badge.plus")
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
                    HStack {
                        Button(isLoadingAlbums ? "Loading…" : "Load Albums") {
                            Task {
                                await loadAlbumsIfNeeded(auto: false)
                            }
                        }
                        .disabled(isLoadingAlbums)

                        Link("Manage Albums…", destination: URL(string: "https://photos.onedrive.com")!)
                    }

                    if albums.isEmpty, let name = settings.selectedAlbumName, !name.isEmpty {
                        Text("Selected: \(name)")
                    }

                    if albums.isEmpty, settings.selectedAlbumName == nil,
                       let albumId = settings.selectedAlbumId, !albumId.isEmpty {
                        Text("Selected: Saved album")
                            .foregroundStyle(.secondary)
                    }

                    if albums.isEmpty {
                        Text(didAttemptLoadAlbums ? "No albums found via Microsoft Graph." : "No albums loaded yet.")
                            .foregroundStyle(.secondary)
                        if didAttemptLoadAlbums {
                            Text("Create/manage albums in OneDrive Photos, then reload here.")
                                .foregroundStyle(.secondary)
                        }
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

                        if let albumId = settings.selectedAlbumId, !albumId.isEmpty {
                            if let count = selectedAlbumUsableCountFirstPage {
                                HStack(spacing: 6) {
                                    Text("Usable photos (first page only): \(count)")
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(.secondary)
                                        .imageScale(.small)
                                        .help(usablePhotosHelp)
                                }
                                .foregroundStyle(.secondary)
                            } else {
                                HStack(spacing: 6) {
                                    Text("Usable photos (first page): …")
                                    Image(systemName: "questionmark.circle")
                                        .foregroundStyle(.secondary)
                                        .imageScale(.small)
                                        .help(usablePhotosHelp)
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let url = settings.selectedAlbumWebUrl {
                        Link("Open in OneDrive", destination: url)
                    }

                    if let albumId = settings.selectedAlbumId, !albumId.isEmpty {
                        if settings.albumPictureCount > 0 {
                            HStack(spacing: 6) {
                                Text("Usable photos (last scan): \(settings.albumPictureCount)")
                                Image(systemName: "questionmark.circle")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                                    .help(usablePhotosHelp)
                            }
                            .foregroundStyle(.secondary)
                        }
                        if settings.showNoPicturesWarning {
                            Text("No usable photos found (checked the first page for image items).")
                                .foregroundStyle(.orange)
                            Text("To fix: ensure the album contains images (not just videos). If you just changed the album in OneDrive Photos (web/mobile), wait a moment and check again.")
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .pickerStyle(.menu)

                let hasAlbum = (settings.selectedAlbumId?.isEmpty == false)
                let canChangeNow = authService.isSignedIn && hasAlbum
                Button {
                    settings.isPaused.toggle()
                    if authService.isSignedIn == false {
                        wallpaperManager.stopWallpaperUpdates()
                    } else if settings.isPaused {
                        wallpaperManager.stopWallpaperUpdates()
                    } else {
                        wallpaperManager.startWallpaperUpdates()
                    }
                } label: {
                    Label(
                        settings.isPaused ? "Resume Automatic Changes" : "Pause Automatic Changes",
                        systemImage: settings.isPaused ? "play.fill" : "pause.fill"
                    )
                }
                .help("Pauses only scheduled wallpaper changes (the timer). Manual changes still work.")
                .disabled(authService.isSignedIn == false)

                Button {
                    wallpaperManager.requestWallpaperUpdate(trigger: .manual)
                } label: {
                    Label(wallpaperManager.isUpdating ? "Changing…" : "Change Wallpaper Now", systemImage: "sparkles")
                }
                .disabled(wallpaperManager.isUpdating || canChangeNow == false)
                .help(canChangeNow ? "" : (authService.isSignedIn ? "Select an album to enable wallpaper changes." : "Sign in to enable wallpaper changes."))

                Toggle("Pick Randomly", isOn: $settings.pickRandomly)

                HStack {
                    Text("Minimum Picture Width:")
                    TextField("", value: $settings.minimumPictureWidth, formatter: NumberFormatter())
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                    Text("px")
                    let recommended = recommendedMinimumPictureWidthPixels
                    Button("Use Recommended (\(Int(recommended))px)") {
                        settings.minimumPictureWidth = recommended
                    }
                    .disabled(Int(settings.minimumPictureWidth.rounded()) == Int(recommended.rounded()))
                    .help("Sets minimum width to the largest connected display width, choosing the larger of physical panel pixels vs effective (“Looks like …”) width (\(Int(recommended))px).")
                }
#if DEBUG
                let sizing = WallpaperImageTranscoder.debugRecommendedWidths()
                Text("Recommended calc: logical \(sizing.logicalMax) / physical \(sizing.physicalMax)")
                    .font(.system(.caption))
                    .foregroundStyle(.secondary)
#endif

                Toggle("Only Horizontal Photos", isOn: $settings.horizontalPhotosOnly)

                Picker("Fill Mode", selection: $settings.wallpaperFillMode) {
                    ForEach(WallpaperFillMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section {
                Button {
                    showAdvancedControls.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: showAdvancedControls ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("Show Advanced Controls")
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)

                if showAdvancedControls {
                    VStack(alignment: .leading, spacing: 12) {
                        Group {
                            Text("Album")
                                .font(.system(.subheadline, weight: .semibold))

	                            if authService.isSignedIn {
	                                TextField(
	                                    "Album ID (manual)",
	                                    text: Binding(
	                                        get: { settings.selectedAlbumId ?? "" },
	                                        set: { settings.selectedAlbumId = $0.isEmpty ? nil : $0 }
	                                    )
	                                )
	                                .textFieldStyle(.roundedBorder)
	                                .frame(maxWidth: 420)

	                                if let albumId = settings.selectedAlbumId, !albumId.isEmpty {
	                                    Button("Validate Album ID") {
	                                        oneDriveError = nil
	                                        Task {
                                            do {
                                                if let album = try await photosService.verifyAlbumExists(albumId: albumId) {
                                                    applySelectedAlbum(album)
                                                } else {
                                                    oneDriveError = "That ID could not be verified as an accessible OneDrive album."
                                                }
                                            } catch {
                                                oneDriveError = error.localizedDescription
                                            }
                                        }
                                    }

                                    Button("Check Album Photos (full scan)") {
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
                                }
                            } else {
                                Text("Sign in to use advanced album tools.")
                                    .font(.system(.caption))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Divider()

                        Group {
                            Text("Wallpaper")
                                .font(.system(.subheadline, weight: .semibold))

                            Button("Clear Wallpaper Cache") {
                                wallpaperManager.clearWallpaperCache()
                            }

                            Text("Removes cached wallpaper JPEGs (including RAW conversions) so the next change re-downloads as needed.")
                                .font(.system(.caption))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

#if DEBUG
                        if authService.isSignedIn, didAttemptLoadAlbums {
                            Divider()

                            Group {
                                Text("Debug")
                                    .font(.system(.subheadline, weight: .semibold))

                                Button("Probe Albums") {
                                    oneDriveDebugInfo = nil
                                    Task {
                                        oneDriveDebugInfo = await photosService.debugProbeAlbumListing()
                                    }
                                }

                                if let oneDriveDebugInfo, !oneDriveDebugInfo.isEmpty {
                                    Text(oneDriveDebugInfo)
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .lineLimit(nil)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
#endif
                    }
                    .padding(.leading, 18)
                }
            }
            header: {
                Text("Advanced")
                    .font(.headline)
                    .textCase(nil)
                    .padding(.top, 12)
            }

            Section {
                HStack {
                    Text("Activity")
                    Spacer()
                    if wallpaperManager.isUpdating {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(stageText(wallpaperManager.updateStage))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(stageText(wallpaperManager.updateStage))
                }

                HStack {
                    Text("Current photo")
                    Spacer()
                    let name = (settings.lastSetWallpaperItemName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let id = (settings.lastSetWallpaperItemId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let display = name.isEmpty == false ? name : id
                    if display.isEmpty {
                        Text("—")
                            .foregroundStyle(.secondary)
                    } else {
                        Text(display)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(display)
                    }
                }

                HStack {
                    Text("Last changed")
                    Spacer()
                    if let last = wallpaperManager.lastSuccessfulUpdate {
                        Text(last, style: .relative)
                            .foregroundStyle(.secondary)
                            .help(last.formatted(date: .abbreviated, time: .shortened))
                    } else {
                        Text("—")
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Text("Next change")
                    Spacer()
                    if authService.isSignedIn == false {
                        Text("Sign in")
                            .foregroundStyle(.secondary)
                    } else if (settings.selectedAlbumId?.isEmpty ?? true) {
                        Text("Select album")
                            .foregroundStyle(.secondary)
                    } else if settings.isPaused {
                        Text("Paused")
                            .foregroundStyle(.secondary)
                    } else if settings.changeFrequency == .never {
                        Text("Off")
                            .foregroundStyle(.secondary)
                    } else {
                        let interval = WallpaperManager.intervalSeconds(for: settings.changeFrequency)
                        let due = WallpaperManager.computeNextDueDate(
                            now: Date(),
                            lastSuccessfulWallpaperUpdate: settings.lastSuccessfulWallpaperUpdate,
                            intervalSeconds: interval,
                            hasSelectedAlbum: true,
                            isPaused: false,
                            lastAttemptDate: nil
                        )
                        if let due {
                            Text(due, style: .relative)
                                .foregroundStyle(.secondary)
                                .help(due.formatted(date: .abbreviated, time: .shortened))
                        } else {
                            Text("—")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let error = wallpaperManager.lastUpdateError, !error.isEmpty {
                    Text("Last error: \(error)")
                        .font(.system(.caption))
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            header: {
                Text("Status")
                    .font(.headline)
                    .textCase(nil)
                    .padding(.top, 16)
            }
        }
        .task(id: authService.isSignedIn) {
            await startupRefreshIfNeeded()
        }
    }

    @MainActor
    private func startupRefreshIfNeeded() async {
        if authService.isSignedIn == false {
            didValidateStoredSelection = false
            didAutoLoadAlbums = false
            albums = []
            return
        }

        await loadAlbumsIfNeeded(auto: true)
        await validateStoredSelectionIfNeeded()
        wallpaperManager.startWallpaperUpdates()
    }

    @MainActor
    private func loadAlbumsIfNeeded(auto: Bool) async {
        if isLoadingAlbums { return }
        if auto, didAutoLoadAlbums { return }

        isLoadingAlbums = true
        oneDriveError = nil

        do {
            albums = try await photosService.listAlbums()
            didAttemptLoadAlbums = true
            if auto { didAutoLoadAlbums = true }

            if let selectedId = settings.selectedAlbumId, selectedId.isEmpty == false {
                if let match = albums.first(where: { $0.id == selectedId }) {
                    applySelectedAlbum(match)
                }
            } else if let first = albums.first {
                applySelectedAlbum(first)
            }
        } catch {
            oneDriveError = error.localizedDescription
        }

        isLoadingAlbums = false
    }

    @MainActor
    private func validateStoredSelectionIfNeeded() async {
        if authService.isSignedIn == false {
            didValidateStoredSelection = false
            return
        }

        guard didValidateStoredSelection == false else { return }
        didValidateStoredSelection = true

        guard let albumId = settings.selectedAlbumId, albumId.isEmpty == false else { return }

        oneDriveError = nil
        do {
            if let verified = try await photosService.verifyAlbumExists(albumId: albumId) {
                applySelectedAlbum(verified, shouldProbePhotos: false)
                await probeSelectedAlbumForUsablePhotos(albumId: albumId)
            } else {
                oneDriveError = "Previously selected album couldn’t be validated as an accessible OneDrive album. Keeping your saved Album ID, but wallpaper updates may fail until it’s available."
                settings.albumPictureCount = 0
                settings.showNoPicturesWarning = false
            }
        } catch OneDriveAuthError.notSignedIn {
            didValidateStoredSelection = false
        } catch OneDriveGraphError.httpError(let status, _) where status == 403 || status == 404 {
            oneDriveError = "Previously selected album could not be accessed (HTTP \(status)). Keeping your saved Album ID, but wallpaper updates may fail until it’s accessible."
            settings.albumPictureCount = 0
            settings.showNoPicturesWarning = false
        } catch {
            oneDriveError = error.localizedDescription
        }
    }

    @MainActor
    private func applySelectedAlbum(_ album: OneDriveAlbum, shouldProbePhotos: Bool = true) {
        settings.selectedAlbumId = album.id
        settings.selectedAlbumName = album.name
        settings.selectedAlbumWebUrl = album.webUrl
        settings.albumPictureCount = 0
        settings.showNoPicturesWarning = false
        selectedAlbumUsableCountFirstPage = nil
        wallpaperManager.startWallpaperUpdates()

        if shouldProbePhotos {
            let idToProbe = album.id
            Task { await probeSelectedAlbumForUsablePhotos(albumId: idToProbe) }
        }
    }

    @MainActor
    private func probeSelectedAlbumForUsablePhotos(albumId: String) async {
        guard authService.isSignedIn else { return }
        guard settings.selectedAlbumId == albumId else { return }

        do {
            let count = try await photosService.probeAlbumUsablePhotoCountFirstPage(albumId: albumId)
            guard settings.selectedAlbumId == albumId else { return }
            selectedAlbumUsableCountFirstPage = count
            settings.showNoPicturesWarning = count == 0
        } catch OneDriveAuthError.notSignedIn {
            // Ignore; user is effectively signed out.
        } catch {
            guard settings.selectedAlbumId == albumId else { return }
            oneDriveError = error.localizedDescription
        }
    }
}
