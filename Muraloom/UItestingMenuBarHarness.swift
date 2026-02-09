import SwiftUI

struct UItestingMenuBarHarness: View {
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @Environment(\.openWindow) private var openWindow

    @State private var menuError: String?
    @State private var isSigningIn: Bool = false

    private var hasSelectedAlbum: Bool {
        settings.selectedAlbumId?.isEmpty == false
    }

    private func activateAppAndOpenSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func beginSignIn() {
        guard isSigningIn == false else { return }
        isSigningIn = true
        menuError = nil

        activateAppAndOpenSettings()

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            do {
                try await authService.signIn()
                wallpaperManager.startWallpaperUpdates()
            } catch {
                menuError = error.localizedDescription
            }
            isSigningIn = false
        }
    }

    private func signOut() {
        authService.signOut()
        wallpaperManager.stopWallpaperUpdates()
        menuError = nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if authService.isSignedIn {
                if let username = authService.signedInUsername, !username.isEmpty {
                    Text("Signed in as \(username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Signed in")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Signed out")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    activateAppAndOpenSettings()
                } label: {
                    Label("Open Settings…", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("menubar.openSettings")

                if authService.isSignedIn {
                    Button {
                        signOut()
                    } label: {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("menubar.signOut")
                } else {
                    Button {
                        beginSignIn()
                    } label: {
                        Label(isSigningIn ? "Signing In…" : "Sign In…", systemImage: "person.crop.circle.badge.plus")
                    }
                    .disabled(isSigningIn)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("menubar.signIn")
                }
            }

            if let menuError, !menuError.isEmpty {
                Text(menuError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
