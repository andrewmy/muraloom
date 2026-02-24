import AppKit
import Testing
@testable import Muraloom

@MainActor
struct AuthServiceTests {
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
