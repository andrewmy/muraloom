import AppKit // For NSWorkspace
import Foundation

class WallpaperManager: ObservableObject {
    private let photosService: DummyPhotosService
    private let settings: SettingsModel
    private var wallpaperTimer: Timer?

    init(photosService: DummyPhotosService, settings: SettingsModel) {
        self.photosService = photosService
        self.settings = settings
    }

    func startWallpaperUpdates() {
        // Invalidate existing timer if any
        wallpaperTimer?.invalidate()

        // Schedule new timer based on frequency
        switch settings.changeFrequency {
        case .never:
            // Do nothing, no automatic updates
            break
        case .hourly:
            wallpaperTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
                Task { await self?.updateWallpaper() }
            }
        case .sixHours:
            wallpaperTimer = Timer.scheduledTimer(withTimeInterval: 21600, repeats: true) { [weak self] _ in
                Task { await self?.updateWallpaper() }
            }
        case .daily:
            wallpaperTimer = Timer.scheduledTimer(withTimeInterval: 86400, repeats: true) { [weak self] _ in
                Task { await self?.updateWallpaper() }
            }
        }
        // Ensure the timer runs on a common run loop mode
        if let timer = wallpaperTimer { RunLoop.current.add(timer, forMode: .common) }
    }

    func stopWallpaperUpdates() {
        wallpaperTimer?.invalidate()
        wallpaperTimer = nil
    }

    func updateWallpaper() async {
        guard let albumId = settings.appCreatedAlbumId else {
            print("Error: No album ID found to fetch photos.")
            return
        }

        do {
            let mediaItems = try await photosService.searchPhotos(in: albumId)
            if mediaItems.isEmpty {
                print("No photos found in the album.")
                return
            }

            let selectedPhoto: MediaItem
            if settings.pickRandomly {
                selectedPhoto = mediaItems.randomElement()!
            } else {
                // Sequential picking
                let nextIndex = (settings.lastPickedIndex + 1) % mediaItems.count
                selectedPhoto = mediaItems[nextIndex]
                settings.lastPickedIndex = nextIndex
            }

            let imageUrl = selectedPhoto.baseUrl

            let tempDirectory = FileManager.default.temporaryDirectory
            let tempFileName = UUID().uuidString + ".jpg"
            let tempFileURL = tempDirectory.appendingPathComponent(tempFileName)

            let (imageData, _) = try await URLSession.shared.data(from: imageUrl)
            try imageData.write(to: tempFileURL)

            let screen = NSScreen.main!
            var options: [NSWorkspace.DesktopImageOptionKey: Any] = [:]

            switch settings.wallpaperFillMode {
            case .fill:
                options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
                options[.allowClipping] = true
            case .fit:
                options[.imageScaling] = NSImageScaling.scaleProportionallyUpOrDown.rawValue
                options[.allowClipping] = false
            case .stretch:
                options[.imageScaling] = NSImageScaling.scaleAxesIndependently.rawValue
                options[.allowClipping] = false
            case .center:
                options[.imageScaling] = NSImageScaling.scaleNone.rawValue
                options[.allowClipping] = false
            }

            try NSWorkspace.shared.setDesktopImageURL(tempFileURL, for: screen, options: options)
            print("Wallpaper updated successfully!")

            // TODO: Implement a more robust temporary file management strategy.
            // Currently, a new temp file is created for each wallpaper change.
            // Consider reusing files or cleaning up old ones periodically.
            try? FileManager.default.removeItem(at: tempFileURL)

        } catch {
            print("Error updating wallpaper: \(error.localizedDescription)")
        }
    }
}