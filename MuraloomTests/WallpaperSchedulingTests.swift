import AppKit
import Testing
@testable import Muraloom

struct WallpaperSchedulingTests {
    @Test @MainActor func wakeRearmsOverdueScheduleAndHonorsStop() async throws {
        let suite = "WallpaperSchedulingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        var now = Date()
        let settings = SettingsModel(userDefaults: defaults)
        settings.selectedAlbumId = "album"
        settings.changeFrequency = .hourly
        settings.isPaused = false
        settings.lastSuccessfulWallpaperUpdate = now
        let manager = WallpaperManager(
            photosService: DummyOneDrivePhotosService(),
            settings: settings,
            applicationSupportDirectoryProvider: { directory },
            nowProvider: { now }
        )
        defer { manager.stopWallpaperUpdates() }
        manager.startWallpaperUpdates()
        let originalDue = try #require(manager.nextScheduledUpdate)
        now = now.addingTimeInterval(120)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(manager.nextScheduledUpdate == originalDue)

        now = now.addingTimeInterval(12 * 3600)
        manager.startWallpaperUpdates()
        #expect(manager.nextScheduledUpdate == originalDue)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(manager.nextScheduledUpdate == now.addingTimeInterval(60))
        #expect(manager.nextScheduledUpdate != originalDue)

        settings.isPaused = true
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(manager.nextScheduledUpdate == nil)

        settings.isPaused = false
        manager.startWallpaperUpdates()
        manager.stopWallpaperUpdates()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        #expect(manager.nextScheduledUpdate == nil)
        #expect(manager.isUpdating == false)

        manager.startWallpaperUpdates()
        let hourlyDue = try #require(manager.nextScheduledUpdate)
        settings.changeFrequency = .daily
        manager.startWallpaperUpdates()
        #expect(manager.nextScheduledUpdate != hourlyDue)
        settings.selectedAlbumId = nil
        manager.startWallpaperUpdates()
        #expect(manager.nextScheduledUpdate == nil)
    }

    @Test @MainActor func timerFiresAfterWakeAndRepeatedStartsThenSchedulesRetry() async throws {
        let suite = "WallpaperTimerDeliveryTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let settings = SettingsModel(userDefaults: defaults)
        settings.selectedAlbumId = "album"
        settings.changeFrequency = .hourly
        settings.isPaused = false
        settings.lastSuccessfulWallpaperUpdate = Date().addingTimeInterval(-7200)
        let manager = WallpaperManager(
            photosService: DummyOneDrivePhotosService(),
            settings: settings,
            applicationSupportDirectoryProvider: { directory },
            minimumSchedulingLeadTime: 0
        )
        defer { manager.stopWallpaperUpdates() }
        manager.startWallpaperUpdates()
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        for _ in 0..<20 { await Task.yield() }
        let due = try #require(manager.nextScheduledUpdate)
        for _ in 0..<40 {
            manager.startWallpaperUpdates()
            try await Task.sleep(for: .milliseconds(50))
            if manager.lastSyncAt != nil { break }
        }
        #expect(manager.lastSyncAt != nil)
        #expect(manager.lastUpdateError == "No usable photos found after applying filters.")
        #expect(manager.isUpdating == false)
        #expect(try #require(manager.nextScheduledUpdate) > due.addingTimeInterval(290))
    }

    @Test func pausedDisablesScheduling() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let due = WallpaperManager.computeNextDueDate(
            now: now,
            lastSuccessfulWallpaperUpdate: now,
            intervalSeconds: 3600,
            hasSelectedAlbum: true,
            isPaused: true,
            lastAttemptDate: nil
        )
        #expect(due == nil)
    }

    @Test func missingAlbumDisablesScheduling() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let due = WallpaperManager.computeNextDueDate(
            now: now,
            lastSuccessfulWallpaperUpdate: now,
            intervalSeconds: 3600,
            hasSelectedAlbum: false,
            isPaused: false,
            lastAttemptDate: nil
        )
        #expect(due == nil)
    }

    @Test func nilIntervalDisablesScheduling() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let due = WallpaperManager.computeNextDueDate(
            now: now,
            lastSuccessfulWallpaperUpdate: now,
            intervalSeconds: nil,
            hasSelectedAlbum: true,
            isPaused: false,
            lastAttemptDate: nil
        )
        #expect(due == nil)
    }

    @Test func enforcesMinimumLeadTime() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastSuccess = now.addingTimeInterval(-3590) // due = now + 10s

        let due = WallpaperManager.computeNextDueDate(
            now: now,
            lastSuccessfulWallpaperUpdate: lastSuccess,
            intervalSeconds: 3600,
            hasSelectedAlbum: true,
            isPaused: false,
            lastAttemptDate: nil,
            minimumLeadTime: 60,
            minimumRetryDelay: 300
        )

        #expect(due == now.addingTimeInterval(60))
    }

    @Test func enforcesMinimumRetryDelayWhenFailing() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let lastSuccess = now.addingTimeInterval(-3590) // due = now + 10s
        let lastAttempt = now.addingTimeInterval(-10) // retryAfter = now + 290s

        let due = WallpaperManager.computeNextDueDate(
            now: now,
            lastSuccessfulWallpaperUpdate: lastSuccess,
            intervalSeconds: 3600,
            hasSelectedAlbum: true,
            isPaused: false,
            lastAttemptDate: lastAttempt,
            minimumLeadTime: 60,
            minimumRetryDelay: 300
        )

        #expect(due == now.addingTimeInterval(290))
    }
}

