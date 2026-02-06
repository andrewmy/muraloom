import AppKit // For NSWorkspace
import Foundation

@MainActor
final class WallpaperManager: ObservableObject {
    enum WallpaperUpdateTrigger {
        case timer
        case manual
    }

    @Published private(set) var lastSuccessfulUpdate: Date?
    @Published private(set) var nextScheduledUpdate: Date?
    @Published private(set) var lastUpdateError: String?

    private let photosService: any PhotosService
    private let settings: SettingsModel
    private var wallpaperTimer: Timer?

    private var inFlightUpdateTask: Task<Void, Never>?
    private var inFlightUpdateId: UUID?
    private var inFlightUpdateTrigger: WallpaperUpdateTrigger?
    private var lastAttemptDate: Date?
    private var lastSetItemId: String?

    init(photosService: any PhotosService, settings: SettingsModel) {
        self.photosService = photosService
        self.settings = settings
        self.lastSuccessfulUpdate = settings.lastSuccessfulWallpaperUpdate
    }

    func startWallpaperUpdates() {
        scheduleNextTimer()
    }

    func stopWallpaperUpdates() {
        wallpaperTimer?.invalidate()
        wallpaperTimer = nil
        nextScheduledUpdate = nil
    }

    func requestWallpaperUpdate(trigger: WallpaperUpdateTrigger) {
        if trigger == .manual {
            wallpaperTimer?.invalidate()
            wallpaperTimer = nil
            nextScheduledUpdate = nil
        }

        if let inFlightUpdateTask, let inFlightUpdateTrigger {
            switch (inFlightUpdateTrigger, trigger) {
            case (.timer, .manual):
                inFlightUpdateTask.cancel()
            case (.manual, .timer), (.timer, .timer):
                return
            case (.manual, .manual):
                inFlightUpdateTask.cancel()
            }
        }

        let updateId = UUID()
        inFlightUpdateId = updateId
        inFlightUpdateTrigger = trigger

        inFlightUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.inFlightUpdateId == updateId {
                    self.inFlightUpdateTask = nil
                    self.inFlightUpdateId = nil
                    self.inFlightUpdateTrigger = nil
                }
            }
            await self.updateWallpaper(trigger: trigger)
        }
    }

    private func intervalSeconds(for frequency: WallpaperChangeFrequency) -> TimeInterval? {
        switch frequency {
        case .never:
            return nil
        case .hourly:
            return 3600
        case .sixHours:
            return 21600
        case .daily:
            return 86400
        }
    }

    private func scheduleNextTimer() {
        wallpaperTimer?.invalidate()
        wallpaperTimer = nil

        guard let interval = intervalSeconds(for: settings.changeFrequency) else {
            nextScheduledUpdate = nil
            return
        }

        guard let selectedAlbumId = settings.selectedAlbumId, !selectedAlbumId.isEmpty else {
            nextScheduledUpdate = nil
            return
        }

        let now = Date()
        let lastSuccess = settings.lastSuccessfulWallpaperUpdate
        var due = (lastSuccess ?? now).addingTimeInterval(interval)

        // MVP: avoid changing wallpaper immediately on app launch.
        let minimumLeadTime: TimeInterval = 60
        let earliest = now.addingTimeInterval(minimumLeadTime)
        if due < earliest {
            due = earliest
        }

        // Avoid tight failure loops when due is already reached but updates keep failing.
        let minimumRetryDelay: TimeInterval = 300
        if let lastAttemptDate {
            let retryAfter = lastAttemptDate.addingTimeInterval(minimumRetryDelay)
            if due < retryAfter {
                due = retryAfter
            }
        }

        nextScheduledUpdate = due

        let timeInterval = max(1, due.timeIntervalSinceNow)
        wallpaperTimer = Timer(timeInterval: timeInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.wallpaperTimer?.invalidate()
                self.wallpaperTimer = nil
                self.requestWallpaperUpdate(trigger: .timer)
            }
        }

        if let wallpaperTimer {
            RunLoop.current.add(wallpaperTimer, forMode: .common)
        }
    }

    private func updateWallpaper(trigger: WallpaperUpdateTrigger) async {
        var shouldScheduleAfter = true
        defer {
            if shouldScheduleAfter {
                scheduleNextTimer()
            }
        }

        guard let albumId = settings.selectedAlbumId, !albumId.isEmpty else {
            print("Error: No OneDrive album selected.")
            return
        }

        do {
            lastAttemptDate = Date()

            let mediaItems = try await photosService.searchPhotos(inAlbumId: albumId)
            if Task.isCancelled { return }

            let filteredItems = filterMediaItems(mediaItems)
            settings.albumPictureCount = filteredItems.count
            settings.showNoPicturesWarning = filteredItems.isEmpty
            if filteredItems.isEmpty {
                print("No photos found after applying filters.")
                return
            }

            let wallpaperDirURL = try ensureWallpaperDirectoryURL()
            let wallpaperFileURL = wallpaperDirURL.appendingPathComponent("wallpaper-\(UUID().uuidString).jpg")
            let maxDimension = WallpaperImageTranscoder.maxRecommendedDisplayPixelDimension()

            let maxAttempts = min(3, filteredItems.count)
            struct Candidate {
                let item: MediaItem
                let filteredIndex: Int?
            }

            let candidates: [Candidate]
            if settings.pickRandomly {
                var pool = filteredItems
                if let lastSetItemId, filteredItems.count > 1 {
                    let withoutLast = filteredItems.filter { $0.id != lastSetItemId }
                    if withoutLast.isEmpty == false {
                        pool = withoutLast
                    }
                }
                candidates = Array(pool.shuffled().prefix(maxAttempts)).map { Candidate(item: $0, filteredIndex: nil) }
            } else {
                let startIndex = (settings.lastPickedIndex + 1) % filteredItems.count
                candidates = (0..<maxAttempts).map { offset in
                    let idx = (startIndex + offset) % filteredItems.count
                    return Candidate(item: filteredItems[idx], filteredIndex: idx)
                }
            }

            var conversionErrors: [String] = []
            var updatedSequentialIndex: Int?

            for (i, candidate) in candidates.enumerated() {
                if Task.isCancelled { return }
                do {
                    if let lastSetItemId, filteredItems.count > 1, candidate.item.id == lastSetItemId {
                        continue
                    }

                    let rawData = try await photosService.downloadImageData(for: candidate.item)
                    if Task.isCancelled { return }

                    let jpegData = try await Task.detached(priority: .utility) {
                        try WallpaperImageTranscoder.prepareWallpaperJPEG(
                            from: rawData,
                            maxDimension: maxDimension,
                            filenameHint: candidate.item.name
                        )
                    }.value

                    if Task.isCancelled { return }
                    try jpegData.write(to: wallpaperFileURL, options: [.atomic])

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

                    try setWallpaperOnAllScreens(wallpaperFileURL, options: options)

                    updatedSequentialIndex = candidate.filteredIndex
                    lastSetItemId = candidate.item.id
                    conversionErrors.removeAll()
                    cleanupOldWallpaperFiles(in: wallpaperDirURL, keep: 5)
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    try? FileManager.default.removeItem(at: wallpaperFileURL)
                    conversionErrors.append("#\(i + 1): \(error.localizedDescription)")
                }
            }

            guard Task.isCancelled == false else { return }
            guard conversionErrors.isEmpty else {
                lastUpdateError = "Couldn’t decode/convert any of the last \(maxAttempts) photos. " + conversionErrors.joined(separator: " ")
                return
            }

            if let updatedSequentialIndex {
                settings.lastPickedIndex = updatedSequentialIndex
            }

            print("Wallpaper updated successfully!")
            let now = Date()
            settings.lastSuccessfulWallpaperUpdate = now
            lastSuccessfulUpdate = now
            lastUpdateError = nil

        } catch is CancellationError {
            // Manual updates can cancel timer-driven updates; treat cancellation as expected.
            shouldScheduleAfter = false
        } catch {
            print("Error updating wallpaper: \(error.localizedDescription)")
            lastUpdateError = error.localizedDescription
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

    private func ensureWallpaperDirectoryURL() throws -> URL {
        let baseDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appDir = baseDir.appendingPathComponent("GPhotoPaper", isDirectory: true)
        try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        return appDir
    }

    private func setWallpaperOnAllScreens(
        _ wallpaperFileURL: URL,
        options: [NSWorkspace.DesktopImageOptionKey: Any]
    ) throws {
        let screens = NSScreen.screens
        guard screens.isEmpty == false else {
            throw NSError(domain: "WallpaperManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No screens available."])
        }

        var firstError: Error?
        for screen in screens {
            do {
                try NSWorkspace.shared.setDesktopImageURL(wallpaperFileURL, for: screen, options: options)
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private func cleanupOldWallpaperFiles(in dir: URL, keep: Int) {
        guard keep > 0 else { return }
        let fm = FileManager.default

        guard let urls = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let candidates: [(url: URL, date: Date)] = urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("wallpaper-"), name.hasSuffix(".jpg") else { return nil }
            guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey]),
                  values.isRegularFile == true
            else { return nil }
            return (url, values.contentModificationDate ?? .distantPast)
        }

        let sorted = candidates.sorted(by: { $0.date > $1.date })
        for old in sorted.dropFirst(keep) {
            try? fm.removeItem(at: old.url)
        }
    }
}
