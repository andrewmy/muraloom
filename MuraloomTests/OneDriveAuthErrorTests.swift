import Testing
@testable import Muraloom

struct OneDriveAuthErrorTests {
    @Test func missingEntitlementDetectorRecognizesKnownPatterns() {
        #expect(oneDriveAuthLooksLikeMissingEntitlement("OSStatus error -34018."))
        #expect(oneDriveAuthLooksLikeMissingEntitlement("errSecMissingEntitlement"))
        #expect(oneDriveAuthLooksLikeMissingEntitlement("ERRSECMISSINGENTITLEMENT"))
        #expect(oneDriveAuthLooksLikeMissingEntitlement("random failure") == false)
    }

    @Test func notConfiguredIncludesDiagnosticDetails() throws {
        let error = OneDriveAuthError.notConfigured(details: "OneDriveClientId is still the placeholder")
        let description = try #require(error.errorDescription)
        #expect(description.contains("OneDrive auth is not configured."))
        #expect(description.contains("OneDriveClientId is still the placeholder"))
    }

    @Test func providerErrorAddsEntitlementHintForOSStatus34018() throws {
        let error = OneDriveAuthError.providerError(details: "OSStatus error -34018.")
        let description = try #require(error.errorDescription)
        #expect(description.contains("OneDrive sign-in failed: OSStatus error -34018."))
        #expect(description.contains("keychain access is unavailable"))
        #expect(description.contains("Team + Automatically manage signing"))
    }

    @Test func providerErrorAddsEntitlementHintForErrSecMissingEntitlement() throws {
        let error = OneDriveAuthError.providerError(details: "errSecMissingEntitlement")
        let description = try #require(error.errorDescription)
        #expect(description.contains("OneDrive sign-in failed: errSecMissingEntitlement"))
        #expect(description.contains("OSStatus -34018"))
    }

    @Test func tokenResponseMissingFieldsIncludesDetails() throws {
        let error = OneDriveAuthError.tokenResponseMissingFields(details: "access_token, expires_in")
        let description = try #require(error.errorDescription)
        #expect(description.contains("Token response missing fields"))
        #expect(description.contains("access_token, expires_in"))
    }

    @Test func httpErrorIncludesBodySnippet() throws {
        let error = OneDriveAuthError.httpError(status: 400, body: #"{"error":"invalid_scope"}"#)
        let description = try #require(error.errorDescription)
        #expect(description.contains("HTTP 400"))
        #expect(description.contains("invalid_scope"))
    }
}
