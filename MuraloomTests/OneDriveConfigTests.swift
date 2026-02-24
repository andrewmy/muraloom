import Foundation
import Testing
@testable import Muraloom

struct OneDriveConfigTests {
    private enum FixtureError: Error {
        case failedToLoadBundle
    }

    private func makeBundle(info: [String: Any]) throws -> (bundle: Bundle, url: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("OneDriveConfigTests-\(UUID().uuidString).bundle", isDirectory: true)
        let contentsURL = root.appendingPathComponent("Contents", isDirectory: true)
        try fm.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        var mergedInfo = info
        mergedInfo["CFBundleIdentifier"] = mergedInfo["CFBundleIdentifier"] ?? "dev.muraloom.tests.config"
        mergedInfo["CFBundleName"] = mergedInfo["CFBundleName"] ?? "OneDriveConfigFixture"
        mergedInfo["CFBundleVersion"] = mergedInfo["CFBundleVersion"] ?? "1"
        mergedInfo["CFBundleShortVersionString"] = mergedInfo["CFBundleShortVersionString"] ?? "1.0"

        let plistData = try PropertyListSerialization.data(fromPropertyList: mergedInfo, format: .xml, options: 0)
        try plistData.write(to: contentsURL.appendingPathComponent("Info.plist"))

        guard let bundle = Bundle(url: root) else { throw FixtureError.failedToLoadBundle }
        return (bundle, root)
    }

    @Test func configuredValuesYieldNoIssuesAndBuildExpectedEndpoints() throws {
        let (bundle, rootURL) = try makeBundle(info: [
            "OneDriveClientId": "client-123",
            "OneDriveRedirectUri": "muraloom://auth",
            "OneDriveScopes": "User.Read Files.Read user.read OFFLINE_ACCESS",
            "OneDriveAuthorityHost": "login.example.com",
            "OneDriveTenant": "consumers"
        ])
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let config = OneDriveConfig(bundle: bundle)

        #expect(config.clientId == "client-123")
        #expect(config.redirectUri == "muraloom://auth")
        #expect(config.authorityHost == "login.example.com")
        #expect(config.tenant == "consumers")
        #expect(config.scopes == ["User.Read", "Files.Read", "OFFLINE_ACCESS"])
        #expect(config.scopes.filter { $0.lowercased() == "offline_access" }.count == 1)
        #expect(config.isConfigured)
        #expect(config.configurationIssues.isEmpty)
        #expect(config.configurationStatusSummary == "Auth config present (client id, redirect URI, and scopes are populated).")
        #expect(config.authorityURL.absoluteString == "https://login.example.com/consumers")
        #expect(config.authorizeEndpoint.absoluteString == "https://login.example.com/consumers/oauth2/v2.0/authorize")
        #expect(config.tokenEndpoint.absoluteString == "https://login.example.com/consumers/oauth2/v2.0/token")
    }

    @Test func invalidOrUnresolvedValuesProduceClearIssues() throws {
        let (bundle, rootURL) = try makeBundle(info: [
            "OneDriveClientId": "YOUR_ONEDRIVE_CLIENT_ID",
            "OneDriveRedirectUri": "$(REDIRECT_URI)",
            "OneDriveScopes": "$(ONEDRIVE_SCOPES)"
        ])
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let config = OneDriveConfig(bundle: bundle)

        #expect(config.authorityHost == "login.microsoftonline.com")
        #expect(config.tenant == "common")
        #expect(config.isConfigured == false)
        #expect(config.configurationIssues.contains("OneDriveClientId is still the placeholder"))
        #expect(config.configurationIssues.contains("OneDriveRedirectUri still contains an unresolved build setting"))
        #expect(config.configurationIssues.contains("OneDriveScopes still contains an unresolved build setting"))
        #expect(config.configurationStatusSummary.contains("placeholder"))
        #expect(config.configurationStatusSummary.contains("unresolved build setting"))
    }
}
