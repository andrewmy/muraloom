import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Security

func oneDriveAuthLooksLikeMissingEntitlement(_ details: String) -> Bool {
    details.contains("-34018")
        || details.localizedCaseInsensitiveContains("errSecMissingEntitlement")
}

enum OneDriveAuthError: Error, LocalizedError {
    case notConfigured(details: String)
    case notSignedIn
    case cancelled
    case providerError(details: String)
    case invalidRedirectURL
    case missingAuthorizationCode
    case tokenResponseMissingFields(details: String)
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let details):
            return """
            OneDrive auth is not configured. Set ONEDRIVE_CLIENT_ID (via Muraloom/Secrets.xcconfig) and ensure OneDriveRedirectUri/OneDriveScopes are set in Info.plist. Details: \(details)
            """
        case .notSignedIn:
            return "Not signed in."
        case .cancelled:
            return "Sign-in cancelled."
        case .providerError(let details):
            if details.isEmpty { return "OneDrive sign-in failed." }
            return Self.withAuthSetupHintIfNeeded(base: "OneDrive sign-in failed: \(details)", details: details)
        case .invalidRedirectURL:
            return "Invalid redirect URL."
        case .missingAuthorizationCode:
            return "Authorization code missing."
        case .tokenResponseMissingFields(let details):
            if details.isEmpty {
                return "Token response missing fields."
            }
            return "Token response missing fields: \(details)"
        case .httpError(let status, let body):
            let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedBody.isEmpty == false else { return "HTTP \(status)." }
            return "HTTP \(status): \(trimmedBody.prefix(300))"
        }
    }

    private static func withAuthSetupHintIfNeeded(base: String, details: String) -> String {
        guard oneDriveAuthLooksLikeMissingEntitlement(details) else {
            return base
        }
        return """
        \(base) This usually means keychain access is unavailable for this build (OSStatus -34018). Build and run from Xcode with Team + Automatically manage signing.
        """
    }
}

@MainActor
final class OneDriveAuthService: AuthService {
    private let config: OneDriveConfig
    private let keychain = OneDriveTokenKeychain()
    private var authSession: ASWebAuthenticationSession?
    private let presentationContextProvider = WebAuthPresentationContextProvider()

    private var token: OneDriveToken? {
        didSet {
            isSignedIn = token != nil
        }
    }

    init(config: OneDriveConfig = OneDriveConfig()) {
        self.config = config
        super.init()

        self.token = keychain.load()
        self.isSignedIn = self.token != nil
        self.signedInUsername = nil
    }

    override func signOut() {
        token = nil
        signedInUsername = nil
        keychain.delete()
    }

    override func validAccessToken() async throws -> String {
        guard let currentToken = self.token else { throw OneDriveAuthError.notSignedIn }
        if !currentToken.isExpired { return currentToken.accessToken }

        guard let refreshToken = currentToken.refreshToken, refreshToken.isEmpty == false else {
            self.token = nil
            keychain.delete()
            throw OneDriveAuthError.providerError(details: "Sign-in session expired. Please sign in again.")
        }

        let refreshed = try await refreshAccessToken(refreshToken: refreshToken)
        self.token = refreshed
        keychain.save(refreshed)
        return refreshed.accessToken
    }

    override func signIn() async throws {
        guard config.isConfigured else {
            throw OneDriveAuthError.notConfigured(details: config.configurationStatusSummary)
        }

        let pkce = PKCE()
        let state = UUID().uuidString

        var components = URLComponents(url: config.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            .init(name: "client_id", value: config.clientId),
            .init(name: "response_type", value: "code"),
            .init(name: "redirect_uri", value: config.redirectUri),
            .init(name: "response_mode", value: "query"),
            .init(name: "scope", value: config.scopes.joined(separator: " ")),
            .init(name: "state", value: state),
            .init(name: "code_challenge", value: pkce.codeChallenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "prompt", value: "select_account"),
        ]

        guard let url = components.url else {
            throw OneDriveAuthError.notConfigured(details: config.configurationStatusSummary)
        }

        let callbackScheme = URL(string: config.redirectUri)?.scheme
        let redirectURL = try await startWebAuthSession(url: url, callbackScheme: callbackScheme)

        guard let redirectComponents = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false) else {
            throw OneDriveAuthError.invalidRedirectURL
        }

        let query = Dictionary(uniqueKeysWithValues: (redirectComponents.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        guard query["state"] == state else {
            throw OneDriveAuthError.invalidRedirectURL
        }

        guard let code = query["code"], !code.isEmpty else {
            throw OneDriveAuthError.missingAuthorizationCode
        }

        let token = try await exchangeCodeForToken(code: code, codeVerifier: pkce.codeVerifier)
        self.token = token
        keychain.save(token)
    }

    private func startWebAuthSession(url: URL, callbackScheme: String?) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                if let error {
                    self.authSession = nil
                    continuation.resume(throwing: Self.mapWebAuthenticationError(error))
                    return
                }
                guard let callbackURL else {
                    self.authSession = nil
                    continuation.resume(throwing: OneDriveAuthError.invalidRedirectURL)
                    return
                }
                self.authSession = nil
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = presentationContextProvider
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            NSApp.activate(ignoringOtherApps: true)
            if session.start() == false {
                self.authSession = nil
                continuation.resume(
                    throwing: OneDriveAuthError.providerError(
                        details: "Could not start sign-in session. Open Settings and try again."
                    )
                )
            }
        }
    }

    private static func mapWebAuthenticationError(_ error: Error) -> OneDriveAuthError {
        if let webAuthError = error as? ASWebAuthenticationSessionError {
            return mapWebAuthenticationErrorCode(webAuthError.code.rawValue, fallback: webAuthError.localizedDescription)
        }

        let nsError = error as NSError
        if nsError.domain == "com.apple.AuthenticationServices.WebAuthenticationSession" {
            return mapWebAuthenticationErrorCode(nsError.code, fallback: nsError.localizedDescription)
        }

        return OneDriveAuthError.providerError(details: error.localizedDescription)
    }

    private static func mapWebAuthenticationErrorCode(_ code: Int, fallback: String) -> OneDriveAuthError {
        if code == ASWebAuthenticationSessionError.Code.canceledLogin.rawValue {
            return .cancelled
        }
        if code == ASWebAuthenticationSessionError.Code.presentationContextNotProvided.rawValue
            || code == ASWebAuthenticationSessionError.Code.presentationContextInvalid.rawValue
        {
            return .providerError(
                details: "Could not present sign-in window (AuthenticationServices error \(code)). Open Settings and try again."
            )
        }
        return .providerError(details: fallback)
    }

    private func exchangeCodeForToken(code: String, codeVerifier: String) async throws -> OneDriveToken {
        let body = formURLEncoded([
            "client_id": config.clientId,
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": config.redirectUri,
            "code_verifier": codeVerifier,
            "scope": config.scopes.joined(separator: " "),
        ])

        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200...299).contains(status) {
            throw OneDriveAuthError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let authError = tokenResponse.error, authError.isEmpty == false {
            let details = [authError, tokenResponse.error_description]
                .compactMap { value -> String? in
                    guard let value, value.isEmpty == false else { return nil }
                    return value
                }
                .joined(separator: ": ")
            throw OneDriveAuthError.providerError(details: "Token endpoint error: \(details)")
        }
        guard let accessToken = tokenResponse.access_token,
              let expiresIn = tokenResponse.expires_in
        else {
            throw OneDriveAuthError.tokenResponseMissingFields(details: tokenResponse.missingFieldSummary)
        }

        return OneDriveToken(
            accessToken: accessToken,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    private func refreshAccessToken(refreshToken: String) async throws -> OneDriveToken {
        let body = formURLEncoded([
            "client_id": config.clientId,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "redirect_uri": config.redirectUri,
            "scope": config.scopes.joined(separator: " "),
        ])

        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        if let status = http?.statusCode, !(200...299).contains(status) {
            throw OneDriveAuthError.httpError(status: status, body: String(data: data, encoding: .utf8) ?? "")
        }

        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        if let authError = tokenResponse.error, authError.isEmpty == false {
            let details = [authError, tokenResponse.error_description]
                .compactMap { value -> String? in
                    guard let value, value.isEmpty == false else { return nil }
                    return value
                }
                .joined(separator: ": ")
            throw OneDriveAuthError.providerError(details: "Token endpoint error: \(details)")
        }
        guard let accessToken = tokenResponse.access_token,
              let expiresIn = tokenResponse.expires_in
        else {
            throw OneDriveAuthError.tokenResponseMissingFields(details: tokenResponse.missingFieldSummary)
        }

        return OneDriveToken(
            accessToken: accessToken,
            refreshToken: tokenResponse.refresh_token ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }
}

private struct OneDriveToken: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date

    var isExpired: Bool {
        Date() >= expiresAt.addingTimeInterval(-60)
    }
}

private struct TokenResponse: Decodable {
    let token_type: String?
    let scope: String?
    let expires_in: Int?
    let access_token: String?
    let refresh_token: String?
    let error: String?
    let error_description: String?

    var missingFieldSummary: String {
        var missing: [String] = []
        if access_token == nil || access_token?.isEmpty == true {
            missing.append("access_token")
        }
        if expires_in == nil {
            missing.append("expires_in")
        }
        return missing.isEmpty ? "unexpected token payload" : missing.joined(separator: ", ")
    }
}

private final class WebAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var fallbackWindow: NSWindow?

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let keyWindow = NSApp.keyWindow {
            return keyWindow
        }
        if let mainWindow = NSApp.mainWindow {
            return mainWindow
        }
        if let visibleWindow = NSApp.windows.first(where: { $0.isVisible }) {
            return visibleWindow
        }
        if let fallbackWindow {
            return fallbackWindow
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()
        fallbackWindow = window
        return window
    }
}

private struct PKCE {
    let codeVerifier: String
    let codeChallenge: String

    init() {
        self.codeVerifier = Self.randomURLSafeString(length: 64)
        self.codeChallenge = Self.base64URLEncode(Data(SHA256.hash(data: codeVerifier.data(using: .utf8)!)))
    }

    private static func randomURLSafeString(length: Int) -> String {
        let charset = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        var result = ""
        result.reserveCapacity(length)
        for _ in 0..<length {
            result.append(charset[Int.random(in: 0..<charset.count)])
        }
        return result
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private func formURLEncoded(_ params: [String: String]) -> String {
    params
        .map { key, value in
            "\(key.urlFormEncoded)=\(value.urlFormEncoded)"
        }
        .sorted()
        .joined(separator: "&")
}

private extension String {
    var urlFormEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))) ?? self
    }
}

private final class OneDriveTokenKeychain {
    private let service = "lv.andr.muraloom.onedrive"
    private let account = "token"

    func load() -> OneDriveToken? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data
        else { return nil }

        return try? JSONDecoder().decode(OneDriveToken.self, from: data)
    }

    func save(_ token: OneDriveToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }

        let addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
        ]

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account,
            ]
            let attrs: [CFString: Any] = [kSecValueData: data]
            SecItemUpdate(updateQuery as CFDictionary, attrs as CFDictionary)
        }
    }

    func delete() {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
