import Testing
@testable import Muraloom

struct WallpaperSchedulingTests {
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

