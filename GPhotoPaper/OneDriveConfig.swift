import Foundation

struct OneDriveConfig {
    let clientId: String
    let redirectUri: String
    let scopes: [String]
    let authorityHost: String
    let tenant: String

    init(bundle: Bundle = .main) {
        self.clientId = bundle.object(forInfoDictionaryKey: "OneDriveClientId") as? String ?? ""
        self.redirectUri = bundle.object(forInfoDictionaryKey: "OneDriveRedirectUri") as? String ?? ""
        let scopesString = bundle.object(forInfoDictionaryKey: "OneDriveScopes") as? String ?? ""
        self.scopes = scopesString.split(separator: " ").map(String.init)
        self.authorityHost = bundle.object(forInfoDictionaryKey: "OneDriveAuthorityHost") as? String ?? "login.microsoftonline.com"
        self.tenant = bundle.object(forInfoDictionaryKey: "OneDriveTenant") as? String ?? "common"
    }

    var isConfigured: Bool {
        !clientId.isEmpty
            && clientId != "YOUR_ONEDRIVE_CLIENT_ID"
            && clientId.contains("$(") == false
            && !redirectUri.isEmpty
            && !scopes.isEmpty
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

    var msalScopes: [String] {
        let reserved = Set(["openid", "profile", "offline_access"])
        return scopes.filter { !reserved.contains($0) }
    }
}
