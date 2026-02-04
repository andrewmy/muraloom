import AppKit // For NSWorkspace
import Foundation

@MainActor
final class WallpaperManager: ObservableObject {
    private let photosService: any PhotosService
    private let settings: SettingsModel
    private var wallpaperTimer: Timer?

    init(photosService: any PhotosService, settings: SettingsModel) {
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
        guard let folderId = settings.selectedFolderId, !folderId.isEmpty else {
            print("Error: No OneDrive folder ID configured.")
            return
        }

        do {
            let mediaItems = try await photosService.searchPhotos(in: folderId)
            let filteredItems = filterMediaItems(mediaItems)
            if filteredItems.isEmpty {
                print("No photos found after applying filters.")
                return
            }

            let selectedPhoto: MediaItem
            if settings.pickRandomly {
                guard let randomItem = filteredItems.randomElement() else { return }
                selectedPhoto = randomItem
            } else {
                // Sequential picking
                let nextIndex = (settings.lastPickedIndex + 1) % filteredItems.count
                selectedPhoto = filteredItems[nextIndex]
                settings.lastPickedIndex = nextIndex
            }

            let imageUrl = selectedPhoto.downloadUrl

            let wallpaperFileURL = try ensureWallpaperFileURL()

            let (imageData, _) = try await URLSession.shared.data(from: imageUrl)
            try imageData.write(to: wallpaperFileURL, options: [.atomic])

            guard let screen = NSScreen.main else {
                print("Error: No main screen available.")
                return
            }
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

            try NSWorkspace.shared.setDesktopImageURL(wallpaperFileURL, for: screen, options: options)
            print("Wallpaper updated successfully!")

        } catch {
            print("Error updating wallpaper: \(error.localizedDescription)")
        }
    }

    private func filterMediaItems(_ items: [MediaItem]) -> [MediaItem] {
        items.filter { item in
            if settings.minimumPictureWidth > 0, let width = item.pixelWidth, Double(width) < settings.minimumPictureWidth {
                return false
            }

            if settings.horizontalPhotosOnly, let width = item.pixelWidth, let height = item.pixelHeight, width < height {
                return false
            }

            return true
        }
    }

    private func ensureWallpaperFileURL() throws -> URL {
        let baseDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDir = baseDir.appendingPathComponent("GPhotoPaper", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        return appDir.appendingPathComponent("wallpaper.jpg")
    }
}
