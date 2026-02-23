import Testing
@testable import Muraloom

struct OneDriveAuthErrorTests {
    @Test func notConfiguredIncludesDiagnosticDetails() throws {
        let error = OneDriveAuthError.notConfigured(details: "OneDriveClientId is still the placeholder")
        let description = try #require(error.errorDescription)
        #expect(description.contains("OneDrive auth is not configured."))
        #expect(description.contains("OneDriveClientId is still the placeholder"))
    }

    @Test func msalSetupErrorAddsEntitlementHintForOSStatus34018() throws {
        let error = OneDriveAuthError.msalInitializationFailed(underlying: "OSStatus error -34018.")
        let description = try #require(error.errorDescription)
        #expect(description.contains("OneDrive auth setup failed: OSStatus error -34018."))
        #expect(description.contains("keychain access is unavailable"))
        #expect(description.contains("Team + Automatically manage signing"))
    }

    @Test func msalSignInErrorAddsEntitlementHintForErrSecMissingEntitlement() throws {
        let error = OneDriveAuthError.msalError(details: "errSecMissingEntitlement")
        let description = try #require(error.errorDescription)
        #expect(description.contains("OneDrive sign-in failed: errSecMissingEntitlement"))
        #expect(description.contains("OSStatus -34018"))
    }
}
