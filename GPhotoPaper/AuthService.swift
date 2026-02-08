import Foundation

@MainActor
class AuthService: ObservableObject {
    @Published var isSignedIn: Bool = false
    @Published var signedInUsername: String?

    func signIn() async throws {
        preconditionFailure("AuthService.signIn() must be overridden")
    }

    func signOut() {
        preconditionFailure("AuthService.signOut() must be overridden")
    }

    func validAccessToken() async throws -> String {
        preconditionFailure("AuthService.validAccessToken() must be overridden")
    }
}

@MainActor
final class UITestAuthService: AuthService {
    override init() {
        super.init()
        isSignedIn = true
        signedInUsername = "UI Tests"
    }

    override func signIn() async throws {
        isSignedIn = true
        signedInUsername = "UI Tests"
    }

    override func signOut() {
        isSignedIn = false
        signedInUsername = nil
    }

    override func validAccessToken() async throws -> String {
        "ui-testing-token"
    }
}
