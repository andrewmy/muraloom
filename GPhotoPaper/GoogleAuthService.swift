import Foundation
import GoogleSignIn
import AppKit

@MainActor
class GoogleAuthService: ObservableObject {
    @Published var user: GIDGoogleUser?
    @Published var errorMessage: String?

    // Updated scopes for app-created albums
    private let photosScopes = [
        "https://www.googleapis.com/auth/photoslibrary.appendonly",
        "https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata"
    ]

    init() {
        restorePreviousSignIn()
    }

    func signIn() {
        guard let presentingWindow = NSApplication.shared.windows.first else {
            errorMessage = "Could not find a presenting window."
            return
        }
        
        GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow, hint: nil, additionalScopes: photosScopes) { result, error in
            if let error = error {
                self.errorMessage = "Error signing in: \(error.localizedDescription)"
                self.user = nil
                return
            }
            
            guard let result = result else {
                self.errorMessage = "Result object was nil after sign in."
                self.user = nil
                return
            }
            
            self.user = result.user
            self.errorMessage = nil
        }
    }

    func signOut() {
        GIDSignIn.sharedInstance.signOut()
        self.user = nil
        // Clear the album ID and name from UserDefaults
        UserDefaults.standard.removeObject(forKey: "appCreatedAlbumId")
        UserDefaults.standard.removeObject(forKey: "appCreatedAlbumName")
    }

    func restorePreviousSignIn() {
        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            self.user = user
            self.errorMessage = nil
        }
    }
}