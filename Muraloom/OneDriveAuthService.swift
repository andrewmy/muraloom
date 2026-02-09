import Combine
import Foundation

enum OneDriveAuthError: Error, LocalizedError {
    case notConfigured
    case notSignedIn
    case cancelled
    case msalError(details: String)
    case msalInitializationFailed(underlying: String)
    case invalidRedirectURL
    case missingAuthorizationCode
    case tokenResponseMissingFields
    case httpError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OneDrive auth is not configured. Set ONEDRIVE_CLIENT_ID (via Muraloom/Secrets.xcconfig) and ensure OneDriveRedirectUri/OneDriveScopes are set in Info.plist."
        case .notSignedIn:
            return "Not signed in."
        case .cancelled:
            return "Sign-in cancelled."
        case .msalError(let details):
            if details.isEmpty { return "OneDrive sign-in failed." }
            return "OneDrive sign-in failed: \(details)"
        case .msalInitializationFailed(let underlying):
            if underlying.isEmpty {
                return "OneDrive auth setup failed."
            }
            return "OneDrive auth setup failed: \(underlying)"
        case .invalidRedirectURL:
            return "Invalid redirect URL."
        case .missingAuthorizationCode:
            return "Authorization code missing."
        case .tokenResponseMissingFields:
            return "Token response missing fields."
        case .httpError(let status, _):
            return "HTTP \(status)."
        }
    }
}

#if canImport(MSAL)
import AppKit
import MSAL

@MainActor
final class OneDriveAuthService: AuthService {
    private let config: OneDriveConfig
    private var application: MSALPublicClientApplication?
    private var applicationInitError: Error?
    private var currentAccount: MSALAccount?

    init(config: OneDriveConfig = OneDriveConfig()) {
        self.config = config
        super.init()

        guard config.isConfigured else { return }
        do {
            let authority = try MSALAADAuthority(url: config.authorityURL)
            let msalConfig = MSALPublicClientApplicationConfig(
                clientId: config.clientId,
                redirectUri: config.redirectUri,
                authority: authority
            )
            let app = try MSALPublicClientApplication(configuration: msalConfig)
            self.application = app
            self.currentAccount = try app.allAccounts().first
            self.isSignedIn = self.currentAccount != nil
            self.signedInUsername = self.currentAccount?.username
        } catch {
            self.applicationInitError = error
            self.application = nil
            self.currentAccount = nil
            self.isSignedIn = false
            self.signedInUsername = nil
        }
    }

    override func signOut() {
        let accountToRemove = currentAccount
        currentAccount = nil
        isSignedIn = false
        signedInUsername = nil

        guard let application, let accountToRemove else { return }
        do {
            try application.remove(accountToRemove)
        } catch {
        }
    }

    override func validAccessToken() async throws -> String {
        let application = try ensureApplication()
        let account = try ensureAccount(application: application)

        let params = MSALSilentTokenParameters(scopes: config.msalScopes, account: account)
        do {
            let result = try await acquireTokenSilent(application: application, params: params)
            return result.accessToken
        } catch {
            throw OneDriveAuthError.msalError(details: Self.describeMSALError(error))
        }
    }

    override func signIn() async throws {
        let application = try ensureApplication()

        let webviewParams = MSALWebviewParameters(authPresentationViewController: presentationViewController())
        let params = MSALInteractiveTokenParameters(scopes: config.msalScopes, webviewParameters: webviewParams)
        params.promptType = .selectAccount

        do {
            let result = try await acquireTokenInteractive(application: application, params: params)
            currentAccount = result.account
            isSignedIn = true
            signedInUsername = result.account.username
        } catch {
            throw OneDriveAuthError.msalError(details: Self.describeMSALError(error))
        }
    }

    private func ensureApplication() throws -> MSALPublicClientApplication {
        guard config.isConfigured else { throw OneDriveAuthError.notConfigured }
        if let application { return application }
        if let applicationInitError {
            throw OneDriveAuthError.msalInitializationFailed(underlying: Self.describeMSALError(applicationInitError))
        }
        throw OneDriveAuthError.notConfigured
    }

    private func ensureAccount(application: MSALPublicClientApplication) throws -> MSALAccount {
        if let currentAccount { return currentAccount }
        let account = try application.allAccounts().first
        guard let account else { throw OneDriveAuthError.notSignedIn }
        currentAccount = account
        isSignedIn = true
        signedInUsername = account.username
        return account
    }

    private func acquireTokenInteractive(
        application: MSALPublicClientApplication,
        params: MSALInteractiveTokenParameters
    ) async throws -> MSALResult {
        try await withCheckedThrowingContinuation { continuation in
            application.acquireToken(with: params) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: OneDriveAuthError.tokenResponseMissingFields)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func acquireTokenSilent(
        application: MSALPublicClientApplication,
        params: MSALSilentTokenParameters
    ) async throws -> MSALResult {
        try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: params) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: OneDriveAuthError.tokenResponseMissingFields)
                    return
                }
                continuation.resume(returning: result)
            }
        }
    }

    private func presentationViewController() -> NSViewController {
        NSApp.keyWindow?.contentViewController
            ?? NSApp.windows.first?.contentViewController
            ?? NSViewController()
    }

    private static func describeMSALError(_ error: Error) -> String {
        let nsError = error as NSError
        guard nsError.domain == MSALErrorDomain else {
            return nsError.localizedDescription
        }

        var parts: [String] = []
        parts.append("\(nsError.domain) \(nsError.code)")

        if let internalCode = nsError.userInfo[MSALInternalErrorCodeKey] as? Int {
            parts.append("internal=\(internalCode)")
        } else if let internalCode = nsError.userInfo[MSALInternalErrorCodeKey] as? NSNumber {
            parts.append("internal=\(internalCode.intValue)")
        }

        if let oauth = nsError.userInfo[MSALOAuthErrorKey] as? String, !oauth.isEmpty {
            parts.append("oauth=\(oauth)")
        }
        if let sub = nsError.userInfo[MSALOAuthSubErrorKey] as? String, !sub.isEmpty {
            parts.append("sub=\(sub)")
        }
        if let http = nsError.userInfo[MSALHTTPResponseCodeKey] as? Int {
            parts.append("http=\(http)")
        } else if let http = nsError.userInfo[MSALHTTPResponseCodeKey] as? NSNumber {
            parts.append("http=\(http.intValue)")
        }
        if let corr = nsError.userInfo[MSALCorrelationIDKey] as? UUID {
            parts.append("corr=\(corr.uuidString)")
        } else if let corr = nsError.userInfo[MSALCorrelationIDKey] as? String, !corr.isEmpty {
            parts.append("corr=\(corr)")
        }

        if let desc = nsError.userInfo[MSALErrorDescriptionKey] as? String, !desc.isEmpty {
            parts.append(desc)
        } else if !nsError.localizedDescription.isEmpty {
            parts.append(nsError.localizedDescription)
        }

        return parts.joined(separator: " | ")
    }
}

#else
import AppKit
import AuthenticationServices
import CryptoKit
import Security

@MainActor
final class OneDriveAuthService: AuthService {
    private let config: OneDriveConfig
    private let keychain = OneDriveTokenKeychain()
    private var authSession: ASWebAuthenticationSession?

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

        let refreshed = try await refreshAccessToken(refreshToken: currentToken.refreshToken)
        self.token = refreshed
        keychain.save(refreshed)
        return refreshed.accessToken
    }

    override func signIn() async throws {
        guard config.isConfigured else { throw OneDriveAuthError.notConfigured }

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

        guard let url = components.url else { throw OneDriveAuthError.notConfigured }

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
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: OneDriveAuthError.cancelled)
                    return
                }
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: OneDriveAuthError.invalidRedirectURL)
                    return
                }
                continuation.resume(returning: callbackURL)
            }

            session.presentationContextProvider = WebAuthPresentationContextProvider()
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            session.start()
        }
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
        guard let accessToken = tokenResponse.access_token,
              let refreshToken = tokenResponse.refresh_token,
              let expiresIn = tokenResponse.expires_in
        else {
            throw OneDriveAuthError.tokenResponseMissingFields
        }

        return OneDriveToken(
            accessToken: accessToken,
            refreshToken: refreshToken,
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
        guard let accessToken = tokenResponse.access_token,
              let expiresIn = tokenResponse.expires_in
        else {
            throw OneDriveAuthError.tokenResponseMissingFields
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
    let refreshToken: String
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
}

private final class WebAuthPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
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
#endif
