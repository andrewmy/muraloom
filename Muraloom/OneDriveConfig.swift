import Foundation

struct OneDriveConfig {
    let clientId: String
    let redirectUri: String
    let rawScopes: String
    let scopes: [String]
    let authorityHost: String
    let tenant: String

    init(bundle: Bundle = .main) {
        self.clientId = bundle.object(forInfoDictionaryKey: "OneDriveClientId") as? String ?? ""
        self.redirectUri = bundle.object(forInfoDictionaryKey: "OneDriveRedirectUri") as? String ?? ""
        let scopesString = bundle.object(forInfoDictionaryKey: "OneDriveScopes") as? String ?? ""
        self.rawScopes = scopesString
        self.scopes = Self.normalizedScopes(from: scopesString)
        self.authorityHost = bundle.object(forInfoDictionaryKey: "OneDriveAuthorityHost") as? String ?? "login.microsoftonline.com"
        self.tenant = bundle.object(forInfoDictionaryKey: "OneDriveTenant") as? String ?? "common"
    }

    var isConfigured: Bool {
        configurationIssues.isEmpty
    }

    var configurationIssues: [String] {
        var issues: [String] = []

        if clientId.isEmpty {
            issues.append("OneDriveClientId is empty")
        } else if clientId == "YOUR_ONEDRIVE_CLIENT_ID" {
            issues.append("OneDriveClientId is still the placeholder")
        } else if clientId.contains("$(") {
            issues.append("OneDriveClientId still contains an unresolved build setting")
        }

        if redirectUri.isEmpty {
            issues.append("OneDriveRedirectUri is empty")
        } else if redirectUri.contains("$(") {
            issues.append("OneDriveRedirectUri still contains an unresolved build setting")
        }

        if scopes.isEmpty {
            issues.append("OneDriveScopes is empty")
        } else if rawScopes.contains("$(") {
            issues.append("OneDriveScopes still contains an unresolved build setting")
        }

        return issues
    }

    var configurationStatusSummary: String {
        if configurationIssues.isEmpty {
            return "Auth config present (client id, redirect URI, and scopes are populated)."
        }
        return configurationIssues.joined(separator: "; ")
    }

    var authorizeEndpoint: URL {
        URL(string: "https://\(authorityHost)/\(tenant)/oauth2/v2.0/authorize")!
    }

    var tokenEndpoint: URL {
        URL(string: "https://\(authorityHost)/\(tenant)/oauth2/v2.0/token")!
    }

    var authorityURL: URL {
        URL(string: "https://\(authorityHost)/\(tenant)")!
    }

    private static func normalizedScopes(from raw: String) -> [String] {
        let requested = raw.split(separator: " ").map(String.init)
        let required = ["offline_access"]

        var seen = Set<String>()
        var result: [String] = []
        for scope in requested + required {
            let key = scope.lowercased()
            guard seen.insert(key).inserted else { continue }
            result.append(scope)
        }
        return result
    }
}
