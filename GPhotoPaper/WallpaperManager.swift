import AppKit // For NSWorkspace
import CryptoKit
import Foundation

@MainActor
final class WallpaperManager: ObservableObject {
    enum WallpaperUpdateTrigger {
        case timer
        case manual
    }

    enum WallpaperUpdateStage: Equatable {
        case idle
        case fetchingAlbumItems
        case filtering
        case selectingCandidate(attempt: Int, total: Int, name: String)
        case usingCachedWallpaper(name: String)
        case downloading(name: String, attempt: Int, total: Int)
        case decoding(name: String)
        case writingFile(name: String)
        case applyingToScreens(screenCount: Int)
        case done(name: String)
    }

    @Published private(set) var lastSuccessfulUpdate: Date?
    @Published private(set) var nextScheduledUpdate: Date?
    @Published private(set) var lastUpdateError: String?
    @Published private(set) var isUpdating: Bool = false
    @Published private(set) var updateStage: WallpaperUpdateStage = .idle

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

    struct WallpaperCandidate {
        let item: MediaItem
        let filteredIndex: Int?
    }

    nonisolated static func buildWallpaperCandidates(
        filteredItems: [MediaItem],
        maxAttempts: Int,
        pickRandomly: Bool,
        lastPickedIndex: Int,
        avoidItemId: String?
    ) -> [WallpaperCandidate] {
        guard filteredItems.isEmpty == false, maxAttempts > 0 else { return [] }

        if pickRandomly {
            var pool = filteredItems
            if let avoidItemId, filteredItems.count > 1 {
                let withoutAvoid = filteredItems.filter { $0.id != avoidItemId }
                if withoutAvoid.isEmpty == false {
                    pool = withoutAvoid
                }
            }
            return Array(pool.shuffled().prefix(maxAttempts)).map { WallpaperCandidate(item: $0, filteredIndex: nil) }
        }

        var list: [WallpaperCandidate] = []
        let startIndex = (lastPickedIndex + 1) % filteredItems.count

        for offset in 0..<filteredItems.count {
            if list.count >= maxAttempts { break }
            let idx = (startIndex + offset) % filteredItems.count
            let item = filteredItems[idx]

            if let avoidItemId, filteredItems.count > 1, item.id == avoidItemId {
                continue
            }
            list.append(WallpaperCandidate(item: item, filteredIndex: idx))
        }

        if list.isEmpty, let only = filteredItems.first {
            list = [WallpaperCandidate(item: only, filteredIndex: 0)]
        }
        return list
    }

    nonisolated static func computeNextDueDate(
        now: Date,
        lastSuccessfulWallpaperUpdate: Date?,
        intervalSeconds: TimeInterval?,
        hasSelectedAlbum: Bool,
        isPaused: Bool,
        lastAttemptDate: Date?,
        minimumLeadTime: TimeInterval = 60,
        minimumRetryDelay: TimeInterval = 300
    ) -> Date? {
        guard isPaused == false else { return nil }
        guard hasSelectedAlbum else { return nil }
        guard let intervalSeconds else { return nil }

        var due = (lastSuccessfulWallpaperUpdate ?? now).addingTimeInterval(intervalSeconds)

        // MVP: avoid changing wallpaper immediately on app launch.
        let earliest = now.addingTimeInterval(max(0, minimumLeadTime))
        if due < earliest {
            due = earliest
        }

        // Avoid tight failure loops when due is already reached but updates keep failing.
        if let lastAttemptDate {
            let retryAfter = lastAttemptDate.addingTimeInterval(max(0, minimumRetryDelay))
            if due < retryAfter {
                due = retryAfter
            }
        }

        return due
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
        updateStage = .fetchingAlbumItems

        inFlightUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.inFlightUpdateId == updateId {
                    self.inFlightUpdateTask = nil
                    self.inFlightUpdateId = nil
                    self.inFlightUpdateTrigger = nil
                    self.isUpdating = false
                    if self.updateStage != .idle {
                        self.updateStage = .idle
                    }
                }
            }
            await self.updateWallpaper(trigger: trigger)
        }
    }

    nonisolated static func intervalSeconds(for frequency: WallpaperChangeFrequency) -> TimeInterval? {
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

        let now = Date()
        let interval = Self.intervalSeconds(for: settings.changeFrequency)
        let hasSelectedAlbum = (settings.selectedAlbumId?.isEmpty == false)
        guard let due = Self.computeNextDueDate(
            now: now,
            lastSuccessfulWallpaperUpdate: settings.lastSuccessfulWallpaperUpdate,
            intervalSeconds: interval,
            hasSelectedAlbum: hasSelectedAlbum,
            isPaused: settings.isPaused,
            lastAttemptDate: lastAttemptDate
        ) else {
            nextScheduledUpdate = nil
            return
        }

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
            lastUpdateError = "No OneDrive album selected."
            updateStage = .idle
            return
        }

        do {
            lastAttemptDate = Date()

            updateStage = .fetchingAlbumItems
            let mediaItems = try await photosService.searchPhotos(inAlbumId: albumId)
            if Task.isCancelled { return }

            updateStage = .filtering
            let filteredItems = filterMediaItems(mediaItems)
            settings.albumPictureCount = filteredItems.count
            settings.showNoPicturesWarning = filteredItems.isEmpty
            if filteredItems.isEmpty {
                print("No photos found after applying filters.")
                return
            }

            let wallpaperDirURL = try ensureWallpaperDirectoryURL()
            let maxDimension = WallpaperImageTranscoder.maxRecommendedDisplayPixelDimension()

            let currentWallpaperURL: URL? = {
                guard let screen = NSScreen.screens.first else { return nil }
                guard let url = try? NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
                let standardized = url.standardizedFileURL
                let filename = standardized.lastPathComponent
                guard filename.hasPrefix("wallpaper-"), filename.hasSuffix(".jpg") else { return nil }
                guard standardized.deletingLastPathComponent().standardizedFileURL == wallpaperDirURL.standardizedFileURL else { return nil }
                return standardized
            }()

            let maxAttempts = min(currentWallpaperURL == nil ? 3 : 5, filteredItems.count)
            let candidates = Self.buildWallpaperCandidates(
                filteredItems: filteredItems,
                maxAttempts: maxAttempts,
                pickRandomly: settings.pickRandomly,
                lastPickedIndex: settings.lastPickedIndex,
                avoidItemId: settings.lastSetWallpaperItemId
            )

            var conversionErrors: [String] = []
            var updatedSequentialIndex: Int?
            var didSetWallpaper = false

            for (i, candidate) in candidates.enumerated() {
                if Task.isCancelled { return }
                do {
                    if let lastId = settings.lastSetWallpaperItemId, filteredItems.count > 1, candidate.item.id == lastId {
                        continue
                    }

                    let displayName = candidate.item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let candidateName = (displayName?.isEmpty == false) ? displayName! : candidate.item.id
                    updateStage = .selectingCandidate(attempt: i + 1, total: candidates.count, name: candidateName)

                    let wallpaperFileURL = wallpaperCacheFileURL(for: candidate.item, in: wallpaperDirURL)
                    if let currentWallpaperURL, filteredItems.count > 1,
                       wallpaperFileURL.standardizedFileURL == currentWallpaperURL {
                        continue
                    }
                    if isUsableCachedWallpaperFile(at: wallpaperFileURL) {
                        updateStage = .usingCachedWallpaper(name: candidateName)
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
                        persistLastSetWallpaperItem(candidate.item)
                        conversionErrors.removeAll()
                        didSetWallpaper = true
                        cleanupOldWallpaperFiles(in: wallpaperDirURL, keep: 50)
                        break
                    }

                    updateStage = .downloading(name: candidateName, attempt: i + 1, total: candidates.count)
                    let rawData = try await photosService.downloadImageData(for: candidate.item)
                    if Task.isCancelled { return }

                    updateStage = .decoding(name: candidateName)
                    let jpegData = try await WallpaperImageTranscoder.prepareWallpaperJPEGAsync(
                        from: rawData,
                        maxDimension: maxDimension,
                        filenameHint: candidate.item.name
                    )

                    if Task.isCancelled { return }
                    updateStage = .writingFile(name: candidateName)
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

                    updateStage = .applyingToScreens(screenCount: NSScreen.screens.count)
                    try setWallpaperOnAllScreens(wallpaperFileURL, options: options)

                    updatedSequentialIndex = candidate.filteredIndex
                    persistLastSetWallpaperItem(candidate.item)
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
                updateStage = .idle
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
            settings.flushToDisk()
            let finalName = settings.lastSetWallpaperItemName?.trimmingCharacters(in: .whitespacesAndNewlines)
            updateStage = .done(name: (finalName?.isEmpty == false) ? finalName! : (settings.lastSetWallpaperItemId ?? ""))

        } catch is CancellationError {
            // Manual updates can cancel timer-driven updates; treat cancellation as expected.
            shouldScheduleAfter = false
            updateStage = .idle
        } catch {
            print("Error updating wallpaper: \(error.localizedDescription)")
            lastUpdateError = error.localizedDescription
            updateStage = .idle
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

    private func persistLastSetWallpaperItem(_ item: MediaItem) {
        let trimmedId = item.id.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedId.isEmpty == false {
            settings.lastSetWallpaperItemId = trimmedId
        }

        let trimmedName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        settings.lastSetWallpaperItemName = trimmedName.isEmpty ? nil : trimmedName
        settings.flushToDisk()
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
            settings.lastSetWallpaperItemName = nil
            lastUpdateError = nil
            updateStage = .idle
        } catch {
            lastUpdateError = error.localizedDescription
            updateStage = .idle
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
