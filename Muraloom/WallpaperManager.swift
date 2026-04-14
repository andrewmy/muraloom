import AppKit // For NSWorkspace
import CryptoKit
import Foundation
import ImageIO

protocol WallpaperApplying {
    var screenCount: Int { get }
    func currentWallpaperURL() -> URL?
    func setWallpaper(
        _ wallpaperFileURL: URL,
        options: [NSWorkspace.DesktopImageOptionKey: Any]
    ) throws
}

struct SystemWallpaperApplier: WallpaperApplying {
    var screenCount: Int { NSScreen.screens.count }

    func currentWallpaperURL() -> URL? {
        guard let screen = NSScreen.screens.first else { return nil }
        return NSWorkspace.shared.desktopImageURL(for: screen)
    }

    func setWallpaper(
        _ wallpaperFileURL: URL,
        options: [NSWorkspace.DesktopImageOptionKey: Any]
    ) throws {
        let screens = NSScreen.screens
        guard screens.isEmpty == false else {
            throw NSError(
                domain: "WallpaperManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No screens available."]
            )
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
}

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
    @Published private(set) var isUsingCachedFallback: Bool = false
    @Published private(set) var cacheReadyCount: Int = 0
    @Published private(set) var cacheTargetCount: Int = 20
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastSyncError: String?
    @Published private(set) var offlineCooldownUntil: Date?

    private let photosService: any PhotosService
    private let settings: SettingsModel
    private let wallpaperApplier: any WallpaperApplying
    private let applicationSupportDirectoryProvider: () throws -> URL
    private let recommendedWallpaperMaxDimensionProvider: () -> Int
    private let nowProvider: () -> Date
    private var wallpaperTimer: Timer?

    private var inFlightUpdateTask: Task<Void, Never>?
    private var inFlightUpdateId: UUID?
    private var inFlightUpdateTrigger: WallpaperUpdateTrigger?
    private var inFlightBypassesOfflineCooldown: Bool = false
    private var lastAttemptDate: Date?
    private var cachePrefetchTask: Task<Void, Never>?
    private var cacheIndexByItemId: [String: CacheIndexEntry] = [:]
    private var consecutiveUnauthorizedTokenErrors: Int = 0

    private let offlineCooldownDuration: TimeInterval = 300
    private let maxCachePrefetchPerSync: Int = 4

    private struct CacheIndexEntry: Codable {
        let itemId: String
        let cTag: String?
        let fileURL: String
        let lastUsedAt: Date?
    }

    private struct CacheIndexPayload: Codable {
        var entries: [CacheIndexEntry]
    }

    init(
        photosService: any PhotosService,
        settings: SettingsModel,
        wallpaperApplier: any WallpaperApplying = SystemWallpaperApplier(),
        applicationSupportDirectoryProvider: @escaping () throws -> URL = {
            try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        },
        recommendedWallpaperMaxDimensionProvider: @escaping () -> Int = WallpaperImageTranscoder.maxRecommendedDisplayPixelDimension,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.photosService = photosService
        self.settings = settings
        self.wallpaperApplier = wallpaperApplier
        self.applicationSupportDirectoryProvider = applicationSupportDirectoryProvider
        self.recommendedWallpaperMaxDimensionProvider = recommendedWallpaperMaxDimensionProvider
        self.nowProvider = nowProvider
        self.lastSuccessfulUpdate = settings.lastSuccessfulWallpaperUpdate
        if let dir = try? ensureWallpaperDirectoryURL() {
            cacheIndexByItemId = loadCacheIndex(from: dir)
            recalculateCacheReadyCount()
        }
    }

    struct WallpaperCandidate {
        let item: MediaItem
        let filteredIndex: Int?
    }

    struct FilteredMediaResults {
        let eligibleItems: [MediaItem]
        let excludedItems: [ExcludedMediaItem]
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
        minimumRetryDelay: TimeInterval = 300,
        offlineCooldownUntil: Date? = nil
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

        if let offlineCooldownUntil, offlineCooldownUntil > now, due < offlineCooldownUntil {
            due = offlineCooldownUntil
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

    func retryOnlineNow() {
        requestWallpaperUpdate(trigger: .manual, bypassOfflineCooldown: true)
    }

    func requestWallpaperUpdate(
        trigger: WallpaperUpdateTrigger,
        bypassOfflineCooldown: Bool = false
    ) {
        if trigger == .manual {
            wallpaperTimer?.invalidate()
            wallpaperTimer = nil
            nextScheduledUpdate = nil
        }

        cachePrefetchTask?.cancel()
        cachePrefetchTask = nil

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
        inFlightBypassesOfflineCooldown = bypassOfflineCooldown
        isUpdating = true
        updateStage = .fetchingAlbumItems

        inFlightUpdateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.inFlightUpdateId == updateId {
                    self.inFlightUpdateTask = nil
                    self.inFlightUpdateId = nil
                    self.inFlightUpdateTrigger = nil
                    self.inFlightBypassesOfflineCooldown = false
                    self.isUpdating = false
                    if self.updateStage != .idle {
                        self.updateStage = .idle
                    }
                }
            }
            await self.updateWallpaper(
                trigger: trigger,
                bypassOfflineCooldown: bypassOfflineCooldown
            )
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

        let now = nowProvider()
        let interval = Self.intervalSeconds(for: settings.changeFrequency)
        let hasSelectedAlbum = (settings.selectedAlbumId?.isEmpty == false)
        guard let due = Self.computeNextDueDate(
            now: now,
            lastSuccessfulWallpaperUpdate: settings.lastSuccessfulWallpaperUpdate,
            intervalSeconds: interval,
            hasSelectedAlbum: hasSelectedAlbum,
            isPaused: settings.isPaused,
            lastAttemptDate: lastAttemptDate,
            offlineCooldownUntil: offlineCooldownUntil
        ) else {
            nextScheduledUpdate = nil
            return
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

    private enum FailureClass {
        case offline
        case authRequired
        case other
    }

    private struct ApplyCandidatesResult {
        let didSetWallpaper: Bool
        let updatedSequentialIndex: Int?
        let errors: [String]
        let maxAttempts: Int
    }

    private func updateWallpaper(
        trigger: WallpaperUpdateTrigger,
        bypassOfflineCooldown: Bool
    ) async {
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

        let now = nowProvider()
        lastAttemptDate = now

        do {
            let wallpaperDirURL = try ensureWallpaperDirectoryURL()
            cacheIndexByItemId = loadCacheIndex(from: wallpaperDirURL)
            recalculateCacheReadyCount()

            let maxDimension = recommendedWallpaperMaxDimensionProvider()
            let currentWallpaperURL = currentManagedWallpaperURL(in: wallpaperDirURL)

            let inCooldown = (offlineCooldownUntil?.timeIntervalSince(nowProvider()) ?? 0) > 0
            if inCooldown && bypassOfflineCooldown == false {
                let cachedItems = cachedFallbackItems()
                let fallback = try await applyCandidates(
                    cachedItems,
                    allowNetworkDownload: false,
                    maxDimension: maxDimension,
                    wallpaperDirURL: wallpaperDirURL,
                    currentWallpaperURL: currentWallpaperURL
                )

                guard Task.isCancelled == false else { return }
                if fallback.didSetWallpaper {
                    finalizeSuccessfulWallpaperChange(
                        updatedSequentialIndex: fallback.updatedSequentialIndex,
                        usedCachedFallback: true
                    )
                    return
                }

                isUsingCachedFallback = false
                lastUpdateError = "Offline and no cached photos are available. Connect to the internet, then use Retry online now."
                updateStage = .idle
                return
            }

            updateStage = .fetchingAlbumItems
            let mediaItems = try await photosService.searchPhotos(inAlbumId: albumId)
            if Task.isCancelled { return }

            consecutiveUnauthorizedTokenErrors = 0
            offlineCooldownUntil = nil
            isUsingCachedFallback = false
            lastSyncAt = nowProvider()
            lastSyncError = nil

            updateStage = .filtering
            settings.albumRawPictureCount = mediaItems.count
            let filtered = Self.filteredMediaItems(
                from: mediaItems,
                minimumPictureWidth: settings.minimumPictureWidth,
                horizontalPhotosOnly: settings.horizontalPhotosOnly
            )
            let filteredItems = filtered.eligibleItems
            settings.albumPictureCount = filteredItems.count
            settings.showNoPicturesWarning = filteredItems.isEmpty

            syncCacheIndex(with: filteredItems, in: wallpaperDirURL)
            if filteredItems.isEmpty {
                lastUpdateError = "No usable photos found after applying filters."
                updateStage = .idle
                return
            }

            let liveResult = try await applyCandidates(
                filteredItems,
                allowNetworkDownload: true,
                maxDimension: maxDimension,
                wallpaperDirURL: wallpaperDirURL,
                currentWallpaperURL: currentWallpaperURL
            )

            guard Task.isCancelled == false else { return }
            guard liveResult.didSetWallpaper else {
                updateStage = .idle
                if liveResult.errors.isEmpty {
                    if filteredItems.count <= 1 {
                        lastUpdateError = "Only one usable photo is available, so the wallpaper can repeat."
                    } else {
                        lastUpdateError = "Couldn’t pick a different photo to avoid repeating the last wallpaper."
                    }
                } else {
                    lastUpdateError = "Couldn’t decode/convert any of the last \(liveResult.maxAttempts) photos. " + liveResult.errors.joined(separator: " ")
                }
                return
            }

            finalizeSuccessfulWallpaperChange(
                updatedSequentialIndex: liveResult.updatedSequentialIndex,
                usedCachedFallback: false
            )
            scheduleCachePrefetch(
                items: filteredItems,
                in: wallpaperDirURL,
                maxDimension: maxDimension
            )

        } catch is CancellationError {
            // Manual updates can cancel timer-driven updates; treat cancellation as expected.
            shouldScheduleAfter = false
            updateStage = .idle
        } catch {
            let failureClass = classifyFailure(error)
            switch failureClass {
            case .offline:
                lastSyncError = error.localizedDescription
                offlineCooldownUntil = nowProvider().addingTimeInterval(offlineCooldownDuration)

                do {
                    let wallpaperDirURL = try ensureWallpaperDirectoryURL()
                    cacheIndexByItemId = loadCacheIndex(from: wallpaperDirURL)
                    recalculateCacheReadyCount()
                    let fallback = try await applyCandidates(
                        cachedFallbackItems(),
                        allowNetworkDownload: false,
                        maxDimension: recommendedWallpaperMaxDimensionProvider(),
                        wallpaperDirURL: wallpaperDirURL,
                        currentWallpaperURL: currentManagedWallpaperURL(in: wallpaperDirURL)
                    )

                    guard Task.isCancelled == false else { return }
                    if fallback.didSetWallpaper {
                        finalizeSuccessfulWallpaperChange(
                            updatedSequentialIndex: fallback.updatedSequentialIndex,
                            usedCachedFallback: true
                        )
                        return
                    }
                } catch is CancellationError {
                    shouldScheduleAfter = false
                    updateStage = .idle
                    return
                } catch {
                    lastSyncError = error.localizedDescription
                }

                isUsingCachedFallback = false
                lastUpdateError = "Offline and no cached photos are available. Connect to the internet, then use Retry online now."
                updateStage = .idle

            case .authRequired:
                lastSyncError = error.localizedDescription
                isUsingCachedFallback = false
                lastUpdateError = "Sign-in is required. Please sign out and sign in again."
                updateStage = .idle

            case .other:
                lastSyncError = error.localizedDescription
                lastUpdateError = error.localizedDescription
                updateStage = .idle
            }
        }
    }

    private func classifyFailure(_ error: Error) -> FailureClass {
        if Self.isOfflineClassError(error) {
            consecutiveUnauthorizedTokenErrors = 0
            return .offline
        }

        if Self.isExplicitAuthInvalidError(error) {
            consecutiveUnauthorizedTokenErrors = 0
            return .authRequired
        }

        if Self.isUnauthorizedTokenError(error) {
            consecutiveUnauthorizedTokenErrors += 1
            if consecutiveUnauthorizedTokenErrors >= 2 {
                return .authRequired
            }
            return .other
        }

        consecutiveUnauthorizedTokenErrors = 0
        return .other
    }

    nonisolated static func isOfflineClassError(_ error: Error) -> Bool {
        let offlineCodes: Set<URLError.Code> = [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
        ]

        func containsOfflineCode(_ error: Error) -> Bool {
            if let urlError = error as? URLError {
                return offlineCodes.contains(urlError.code)
            }

            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain {
                let code = URLError.Code(rawValue: nsError.code)
                if offlineCodes.contains(code) {
                    return true
                }
            }

            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                return containsOfflineCode(underlying)
            }

            return false
        }

        return containsOfflineCode(error)
    }

    nonisolated static func isExplicitAuthInvalidError(_ error: Error) -> Bool {
        switch error {
        case OneDriveAuthError.notSignedIn:
            return true

        case OneDriveAuthError.providerError(let details):
            let normalized = details.lowercased()
            return normalized.contains("invalid_grant")
                || normalized.contains("sign in again")
                || normalized.contains("session expired")

        case OneDriveAuthError.httpError(_, let body):
            return body.lowercased().contains("invalid_grant")

        default:
            return false
        }
    }

    nonisolated static func isUnauthorizedTokenError(_ error: Error) -> Bool {
        func bodyLooksLikeInvalidToken(_ body: String) -> Bool {
            let normalized = body.lowercased()
            return normalized.contains("invalidauthenticationtoken")
                || normalized.contains("invalid_token")
                || normalized.contains("token expired")
                || normalized.contains("token is expired")
        }

        switch error {
        case OneDriveGraphError.httpError(let status, let body):
            return status == 401 && bodyLooksLikeInvalidToken(body)
        case OneDriveAuthError.httpError(let status, let body):
            return status == 401 && bodyLooksLikeInvalidToken(body)
        default:
            return false
        }
    }

    private func finalizeSuccessfulWallpaperChange(
        updatedSequentialIndex: Int?,
        usedCachedFallback: Bool
    ) {
        if let updatedSequentialIndex {
            settings.lastPickedIndex = updatedSequentialIndex
        }

        let now = nowProvider()
        settings.lastSuccessfulWallpaperUpdate = now
        lastSuccessfulUpdate = now
        lastUpdateError = nil
        isUsingCachedFallback = usedCachedFallback
        settings.flushToDisk()

        let finalName = settings.lastSetWallpaperItemName?.trimmingCharacters(in: .whitespacesAndNewlines)
        updateStage = .done(name: (finalName?.isEmpty == false) ? finalName! : (settings.lastSetWallpaperItemId ?? ""))
    }

    private func applyCandidates(
        _ items: [MediaItem],
        allowNetworkDownload: Bool,
        maxDimension: Int,
        wallpaperDirURL: URL,
        currentWallpaperURL: URL?
    ) async throws -> ApplyCandidatesResult {
        guard items.isEmpty == false else {
            return ApplyCandidatesResult(didSetWallpaper: false, updatedSequentialIndex: nil, errors: [], maxAttempts: 0)
        }

        let maxAttempts = min(currentWallpaperURL == nil ? 3 : 5, items.count)
        let candidates = Self.buildWallpaperCandidates(
            filteredItems: items,
            maxAttempts: maxAttempts,
            pickRandomly: settings.pickRandomly,
            lastPickedIndex: settings.lastPickedIndex,
            avoidItemId: settings.lastSetWallpaperItemId
        )

        var conversionErrors: [String] = []
        var updatedSequentialIndex: Int?

        for (i, candidate) in candidates.enumerated() {
            if Task.isCancelled { return ApplyCandidatesResult(didSetWallpaper: false, updatedSequentialIndex: nil, errors: [], maxAttempts: maxAttempts) }
            do {
                if let lastId = settings.lastSetWallpaperItemId, items.count > 1, candidate.item.id == lastId {
                    continue
                }

                let candidateName = candidateDisplayName(candidate.item)
                updateStage = .selectingCandidate(attempt: i + 1, total: candidates.count, name: candidateName)

                let wallpaperFileURL = wallpaperCacheFileURL(for: candidate.item, in: wallpaperDirURL)
                if let currentWallpaperURL, items.count > 1,
                   wallpaperFileURL.standardizedFileURL == currentWallpaperURL {
                    continue
                }

                if isReusableCachedWallpaperFile(
                    at: wallpaperFileURL,
                    requiredMaxDimension: maxDimension,
                    allowUndersizedFallback: allowNetworkDownload == false
                ) {
                    updateStage = .usingCachedWallpaper(name: candidateName)
                    try setWallpaperOnAllScreens(wallpaperFileURL, options: wallpaperOptions())
                    updatedSequentialIndex = candidate.filteredIndex
                    markItemAsUsed(candidate.item, wallpaperFileURL: wallpaperFileURL)
                    cleanupOldWallpaperFiles(in: wallpaperDirURL, keep: 50)
                    return ApplyCandidatesResult(
                        didSetWallpaper: true,
                        updatedSequentialIndex: updatedSequentialIndex,
                        errors: [],
                        maxAttempts: maxAttempts
                    )
                }

                guard allowNetworkDownload else { continue }

                updateStage = .downloading(name: candidateName, attempt: i + 1, total: candidates.count)
                let rawData = try await photosService.downloadImageData(for: candidate.item)
                if Task.isCancelled { return ApplyCandidatesResult(didSetWallpaper: false, updatedSequentialIndex: nil, errors: [], maxAttempts: maxAttempts) }

                updateStage = .decoding(name: candidateName)
                let jpegData = try await WallpaperImageTranscoder.prepareWallpaperJPEGAsync(
                    from: rawData,
                    maxDimension: maxDimension,
                    filenameHint: candidate.item.name
                )

                if Task.isCancelled { return ApplyCandidatesResult(didSetWallpaper: false, updatedSequentialIndex: nil, errors: [], maxAttempts: maxAttempts) }
                updateStage = .writingFile(name: candidateName)
                try jpegData.write(to: wallpaperFileURL, options: [.atomic])
                try setWallpaperOnAllScreens(wallpaperFileURL, options: wallpaperOptions())

                updatedSequentialIndex = candidate.filteredIndex
                markItemAsUsed(candidate.item, wallpaperFileURL: wallpaperFileURL)
                cleanupOldWallpaperFiles(in: wallpaperDirURL, keep: 50)
                return ApplyCandidatesResult(
                    didSetWallpaper: true,
                    updatedSequentialIndex: updatedSequentialIndex,
                    errors: [],
                    maxAttempts: maxAttempts
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let wallpaperFileURL = wallpaperCacheFileURL(for: candidate.item, in: wallpaperDirURL)
                if allowNetworkDownload {
                    try? FileManager.default.removeItem(at: wallpaperFileURL)
                }
                conversionErrors.append("#\(i + 1): \(error.localizedDescription)")
            }
        }

        return ApplyCandidatesResult(
            didSetWallpaper: false,
            updatedSequentialIndex: nil,
            errors: conversionErrors,
            maxAttempts: maxAttempts
        )
    }

    private func scheduleCachePrefetch(items: [MediaItem], in wallpaperDirURL: URL, maxDimension: Int) {
        cachePrefetchTask?.cancel()
        cachePrefetchTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.prefetchMissingCacheItems(
                from: items,
                in: wallpaperDirURL,
                maxDimension: maxDimension
            )
        }
    }

    private func prefetchMissingCacheItems(
        from items: [MediaItem],
        in wallpaperDirURL: URL,
        maxDimension: Int
    ) async {
        let desiredItems = Array(items.prefix(cacheTargetCount))
        guard desiredItems.isEmpty == false else {
            recalculateCacheReadyCount()
            return
        }

        let currentlyReady = desiredItems.filter { isUsableCachedWallpaperFile(at: wallpaperCacheFileURL(for: $0, in: wallpaperDirURL)) }.count
        let remaining = max(0, cacheTargetCount - currentlyReady)
        let prefetchBudget = min(maxCachePrefetchPerSync, remaining)
        guard prefetchBudget > 0 else {
            recalculateCacheReadyCount()
            return
        }

        var prefetched = 0
        var prefetchErrors: [String] = []

        for item in desiredItems {
            if Task.isCancelled { return }
            if prefetched >= prefetchBudget { break }

            let fileURL = wallpaperCacheFileURL(for: item, in: wallpaperDirURL)
            if isUsableCachedWallpaperFile(at: fileURL) { continue }

            do {
                let rawData = try await photosService.downloadImageData(for: item)
                if Task.isCancelled { return }
                let jpegData = try await WallpaperImageTranscoder.prepareWallpaperJPEGAsync(
                    from: rawData,
                    maxDimension: maxDimension,
                    filenameHint: item.name
                )
                try jpegData.write(to: fileURL, options: [.atomic])
                upsertCacheEntry(for: item, fileURL: fileURL, lastUsedAt: cacheIndexByItemId[item.id]?.lastUsedAt)
                prefetched += 1
            } catch {
                try? FileManager.default.removeItem(at: fileURL)
                prefetchErrors.append(error.localizedDescription)
            }
        }

        recalculateCacheReadyCount()
        if prefetchErrors.isEmpty == false {
            lastSyncError = "Cache prefetch incomplete: \(prefetchErrors.joined(separator: " | "))"
        }
    }

    private func candidateDisplayName(_ item: MediaItem) -> String {
        let displayName = item.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (displayName?.isEmpty == false) ? displayName! : item.id
    }

    private func wallpaperOptions() -> [NSWorkspace.DesktopImageOptionKey: Any] {
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
        return options
    }

    nonisolated static func eligibleMediaItems(
        from items: [MediaItem],
        minimumPictureWidth: Double,
        horizontalPhotosOnly: Bool
    ) -> [MediaItem] {
        filteredMediaItems(
            from: items,
            minimumPictureWidth: minimumPictureWidth,
            horizontalPhotosOnly: horizontalPhotosOnly
        ).eligibleItems
    }

    nonisolated static func filteredMediaItems(
        from items: [MediaItem],
        minimumPictureWidth: Double,
        horizontalPhotosOnly: Bool
    ) -> FilteredMediaResults {
        var eligibleItems: [MediaItem] = []
        var excludedItems: [ExcludedMediaItem] = []
        let minimumWidthPx = Int(max(0, minimumPictureWidth.rounded(.up)))

        for item in items {
            let displayName = item.displayName
            if minimumPictureWidth > 0, let width = item.pixelWidth, Double(width) < minimumPictureWidth {
                excludedItems.append(
                    ExcludedMediaItem(
                        id: item.id,
                        name: displayName,
                        webUrl: item.webUrl,
                        reason: .belowMinimumWidth(minimumWidth: minimumWidthPx)
                    )
                )
                continue
            }

            if horizontalPhotosOnly, let width = item.pixelWidth, let height = item.pixelHeight, width < height {
                excludedItems.append(
                    ExcludedMediaItem(
                        id: item.id,
                        name: displayName,
                        webUrl: item.webUrl,
                        reason: .portraitWhenHorizontalOnly
                    )
                )
                continue
            }

            eligibleItems.append(item)
        }

        return FilteredMediaResults(eligibleItems: eligibleItems, excludedItems: excludedItems)
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

    private func markItemAsUsed(_ item: MediaItem, wallpaperFileURL: URL) {
        persistLastSetWallpaperItem(item)
        upsertCacheEntry(for: item, fileURL: wallpaperFileURL, lastUsedAt: nowProvider())
    }

    private func ensureWallpaperDirectoryURL() throws -> URL {
        let baseDir = try applicationSupportDirectoryProvider()
        let appDir = baseDir.appendingPathComponent("Muraloom", isDirectory: true)
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
            try? fm.removeItem(at: cacheIndexFileURL(in: dir))

            settings.lastSetWallpaperItemId = nil
            settings.lastSetWallpaperItemName = nil
            lastUpdateError = nil
            lastSyncError = nil
            lastSyncAt = nil
            offlineCooldownUntil = nil
            isUsingCachedFallback = false
            cacheIndexByItemId = [:]
            cacheReadyCount = 0
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
        updateStage = .applyingToScreens(screenCount: wallpaperApplier.screenCount)
        try wallpaperApplier.setWallpaper(wallpaperFileURL, options: options)
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
        recalculateCacheReadyCount()
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

    private func isReusableCachedWallpaperFile(
        at url: URL,
        requiredMaxDimension: Int,
        allowUndersizedFallback: Bool
    ) -> Bool {
        guard isUsableCachedWallpaperFile(at: url) else { return false }
        guard allowUndersizedFallback == false else { return true }
        guard requiredMaxDimension > 0 else { return true }
        guard let cachedMaxDimension = cachedWallpaperMaxDimension(at: url) else { return true }
        return cachedMaxDimension >= requiredMaxDimension
    }

    private func cachedWallpaperMaxDimension(at url: URL) -> Int? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else {
            return nil
        }

        return max(width, height)
    }

    private func currentManagedWallpaperURL(in wallpaperDirURL: URL) -> URL? {
        guard let url = wallpaperApplier.currentWallpaperURL() else { return nil }
        let standardized = url.standardizedFileURL
        let filename = standardized.lastPathComponent
        guard filename.hasPrefix("wallpaper-"), filename.hasSuffix(".jpg") else { return nil }
        guard standardized.deletingLastPathComponent().standardizedFileURL == wallpaperDirURL.standardizedFileURL else { return nil }
        return standardized
    }

    private func cachedFallbackItems() -> [MediaItem] {
        let readyEntries = cacheIndexByItemId.values
            .filter { isUsableCachedWallpaperFile(at: URL(fileURLWithPath: $0.fileURL)) }
            .sorted { lhs, rhs in
                (lhs.lastUsedAt ?? .distantPast) < (rhs.lastUsedAt ?? .distantPast)
            }

        recalculateCacheReadyCount()
        return readyEntries.map { entry in
            MediaItem(
                id: entry.itemId,
                downloadUrl: nil,
                webUrl: nil,
                pixelWidth: nil,
                pixelHeight: nil,
                name: nil,
                mimeType: "image/jpeg",
                cTag: entry.cTag
            )
        }
    }

    private func syncCacheIndex(with items: [MediaItem], in dir: URL) {
        let previous = cacheIndexByItemId
        var synced: [String: CacheIndexEntry] = [:]

        for item in items {
            let fileURL = wallpaperCacheFileURL(for: item, in: dir).standardizedFileURL
            let previousLastUsed = previous[item.id]?.lastUsedAt
            synced[item.id] = CacheIndexEntry(
                itemId: item.id,
                cTag: item.cTag,
                fileURL: fileURL.path,
                lastUsedAt: previousLastUsed
            )
        }

        cacheIndexByItemId = synced
        saveCacheIndex(cacheIndexByItemId, in: dir)
        recalculateCacheReadyCount()
    }

    private func upsertCacheEntry(
        for item: MediaItem,
        fileURL: URL,
        lastUsedAt: Date?
    ) {
        cacheIndexByItemId[item.id] = CacheIndexEntry(
            itemId: item.id,
            cTag: item.cTag,
            fileURL: fileURL.standardizedFileURL.path,
            lastUsedAt: lastUsedAt
        )

        if let dir = try? ensureWallpaperDirectoryURL() {
            saveCacheIndex(cacheIndexByItemId, in: dir)
        }
        recalculateCacheReadyCount()
    }

    private func recalculateCacheReadyCount() {
        cacheReadyCount = cacheIndexByItemId.values.reduce(into: 0) { partialResult, entry in
            if isUsableCachedWallpaperFile(at: URL(fileURLWithPath: entry.fileURL)) {
                partialResult += 1
            }
        }
    }

    private func cacheIndexFileURL(in dir: URL) -> URL {
        dir.appendingPathComponent("wallpaper-cache-index.json")
    }

    private func loadCacheIndex(from dir: URL) -> [String: CacheIndexEntry] {
        let url = cacheIndexFileURL(in: dir)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        guard let payload = try? decoder.decode(CacheIndexPayload.self, from: data) else {
            return [:]
        }

        var map: [String: CacheIndexEntry] = [:]
        for entry in payload.entries {
            map[entry.itemId] = entry
        }
        return map
    }

    private func saveCacheIndex(_ entriesById: [String: CacheIndexEntry], in dir: URL) {
        let payload = CacheIndexPayload(entries: entriesById.values.sorted { $0.itemId < $1.itemId })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        guard let data = try? encoder.encode(payload) else { return }
        try? data.write(to: cacheIndexFileURL(in: dir), options: [.atomic])
    }
}
