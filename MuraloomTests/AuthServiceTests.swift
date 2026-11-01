import AppKit
import Testing
@testable import Muraloom

@MainActor
struct AuthServiceTests {
    @Test func hostedTestsUseFixtures() {
        #expect(AppEnvironment.isUnitTesting)
        #expect(AppEnvironment.usesTestFixtures)
    }

    @Test func restoredTokenAndSignOutUseInjectedStore() async throws {
        let store = InMemoryTokenStore()
        store.save(OneDriveToken(accessToken: "test-access", refreshToken: nil,
                                 expiresAt: Date().addingTimeInterval(3600)))
        let auth = OneDriveAuthService(tokenStore: store)
        #expect(auth.isSignedIn)
        #expect(try await auth.validAccessToken() == "test-access")
        auth.signOut()
        #expect(!auth.isSignedIn)
        #expect(store.load() == nil)
    }

    @Test func emptyStoreStartsSignedOut() async {
        let auth = OneDriveAuthService(tokenStore: InMemoryTokenStore())
        #expect(!auth.isSignedIn)
        await #expect(throws: OneDriveAuthError.self) { try await auth.validAccessToken() }
    }

    @Test func expiredTokenWithoutRefreshIsDeletedFromInjectedStore() async {
        let store = InMemoryTokenStore()
        store.save(OneDriveToken(accessToken: "expired", refreshToken: nil,
                                 expiresAt: .distantPast))
        let auth = OneDriveAuthService(tokenStore: store)
        await #expect(throws: OneDriveAuthError.self) { try await auth.validAccessToken() }
        #expect(!auth.isSignedIn)
        #expect(store.load() == nil)
    }

    @Test func uiTestAuthServiceLifecycle() async throws {
        let auth = UITestAuthService()

        #expect(auth.isSignedIn)
        #expect(auth.signedInUsername == "UI Tests")

        auth.signOut()
        #expect(auth.isSignedIn == false)
        #expect(auth.signedInUsername == nil)

        try await auth.signIn()
        #expect(auth.isSignedIn)
        #expect(auth.signedInUsername == "UI Tests")
        #expect(try await auth.validAccessToken() == "ui-testing-token")
    }

    @Test func appDelegateKeepsAppRunningWhenWindowsClose() {
        let delegate = AppDelegate()
        #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared) == false)
    }
}

@MainActor
private final class InMemoryTokenStore: OneDriveTokenStore {
    private var token: OneDriveToken?
    func load() -> OneDriveToken? { token }
    func save(_ token: OneDriveToken) { self.token = token }
    func delete() { token = nil }
}
