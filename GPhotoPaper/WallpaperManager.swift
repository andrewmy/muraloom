import AppKit // For NSWorkspace
import CryptoKit
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
    @Published private(set) var isUpdating: Bool = false

    private let photosService: any PhotosService
    private let settings: SettingsModel
    private var wallpaperTimer: Timer?

    private var inFlightUpdateTask: Task<Void, Never>?
    private var inFlightUpdateId: UUID?
    private var inFlightUpdateTrigger: WallpaperUpdateTrigger?
    private var lastAttemptDate: Date?

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
        isUpdating = true

        inFlightUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.inFlightUpdateId == updateId {
                    self.inFlightUpdateTask = nil
                    self.inFlightUpdateId = nil
                    self.inFlightUpdateTrigger = nil
                    self.isUpdating = false
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
            let maxDimension = WallpaperImageTranscoder.maxRecommendedDisplayPixelDimension()

            let maxAttempts = min(3, filteredItems.count)
            struct Candidate {
                let item: MediaItem
                let filteredIndex: Int?
            }

            let candidates: [Candidate]
            if settings.pickRandomly {
                var pool = filteredItems
                if let lastId = settings.lastSetWallpaperItemId, filteredItems.count > 1 {
                    let withoutLast = filteredItems.filter { $0.id != lastId }
                    if withoutLast.isEmpty == false {
                        pool = withoutLast
                    }
                }
                candidates = Array(pool.shuffled().prefix(maxAttempts)).map { Candidate(item: $0, filteredIndex: nil) }
            } else {
                var list: [Candidate] = []
                let startIndex = (settings.lastPickedIndex + 1) % filteredItems.count
                let avoidId = settings.lastSetWallpaperItemId

                for offset in 0..<filteredItems.count {
                    if list.count >= maxAttempts { break }
                    let idx = (startIndex + offset) % filteredItems.count
                    let item = filteredItems[idx]

                    if let avoidId, filteredItems.count > 1, item.id == avoidId {
                        continue
                    }
                    list.append(Candidate(item: item, filteredIndex: idx))
                }

                // If we only have one usable item, allow it.
                if list.isEmpty, let only = filteredItems.first {
                    list = [Candidate(item: only, filteredIndex: 0)]
                }
                candidates = list
            }

            var conversionErrors: [String] = []
            var updatedSequentialIndex: Int?
            var didSetWallpaper = false

            for (i, candidate) in candidates.enumerated() {
                if Task.isCancelled { return }
                do {
                    if let lastId = settings.lastSetWallpaperItemId, filteredItems.count > 1, candidate.item.id == lastId {
                        continue
                    }

                    let wallpaperFileURL = wallpaperCacheFileURL(for: candidate.item, in: wallpaperDirURL)
                    if isUsableCachedWallpaperFile(at: wallpaperFileURL) {
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
                        settings.lastSetWallpaperItemId = candidate.item.id
                        conversionErrors.removeAll()
                        didSetWallpaper = true
                        cleanupOldWallpaperFiles(in: wallpaperDirURL, keep: 50)
                        break
                    }

                    let rawData = try await photosService.downloadImageData(for: candidate.item)
                    if Task.isCancelled { return }

                    let jpegData = try await WallpaperImageTranscoder.prepareWallpaperJPEGAsync(
                        from: rawData,
                        maxDimension: maxDimension,
                        filenameHint: candidate.item.name
                    )

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
                    settings.lastSetWallpaperItemId = candidate.item.id
                    conversionErrors.removeAll()
                    didSetWallpaper = true
                    cleanupOldWallpaperFiles(in: wallpaperDirURL, keep: 50)
                    break
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let wallpaperFileURL = wallpaperCacheFileURL(for: candidate.item, in: wallpaperDirURL)
                    try? FileManager.default.removeItem(at: wallpaperFileURL)
                    conversionErrors.append("#\(i + 1): \(error.localizedDescription)")
                }
            }

            guard Task.isCancelled == false else { return }
            guard didSetWallpaper else {
                if conversionErrors.isEmpty {
                    if filteredItems.count <= 1 {
                        lastUpdateError = "Only one usable photo is available, so the wallpaper can repeat."
                    } else {
                        lastUpdateError = "Couldn’t pick a different photo to avoid repeating the last wallpaper."
                    }
                } else {
                    lastUpdateError = "Couldn’t decode/convert any of the last \(maxAttempts) photos. " + conversionErrors.joined(separator: " ")
                }
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

    func clearWallpaperCache() {
        do {
            let dir = try ensureWallpaperDirectoryURL()
            let fm = FileManager.default
            guard let urls = try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            for url in urls {
                let name = url.lastPathComponent
                guard name.hasPrefix("wallpaper-"), name.hasSuffix(".jpg") else { continue }
                try? fm.removeItem(at: url)
            }

            // Legacy filename, for older builds.
            try? fm.removeItem(at: dir.appendingPathComponent("wallpaper.jpg"))

            settings.lastSetWallpaperItemId = nil
            lastUpdateError = nil
        } catch {
            lastUpdateError = error.localizedDescription
        }
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

    private func wallpaperCacheFileURL(for item: MediaItem, in dir: URL) -> URL {
        let cacheKey = wallpaperCacheKey(for: item)
        return dir.appendingPathComponent("wallpaper-\(cacheKey).jpg")
    }

    private func wallpaperCacheKey(for item: MediaItem) -> String {
        let raw = "\(item.id)|\(item.cTag ?? "")"
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(32).lowercased()
    }

    private func isUsableCachedWallpaperFile(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        if let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
           values.isRegularFile == true,
           let size = values.fileSize,
           size > 0 {
            return true
        }
        return false
    }
}
