import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var wallpaperManager: WallpaperManager

    private var symbolName: String {
        if wallpaperManager.isUpdating {
            return "arrow.triangle.2.circlepath"
        }
        if let error = wallpaperManager.lastUpdateError, !error.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        if authService.isSignedIn == false {
            return "person.crop.circle.badge.xmark"
        }
        return settings.isPaused ? "pause.circle" : "photo.on.rectangle"
    }

    var body: some View {
        Image(systemName: symbolName)
            .accessibilityLabel("Muraloom")
            .accessibilityIdentifier("menubar.statusItem")
    }
}

struct MenuBarMenuView: View {
    @EnvironmentObject private var settings: SettingsModel
    @EnvironmentObject private var authService: AuthService
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @Environment(\.openWindow) private var openWindow

    @State private var menuError: String?
    @State private var isSigningIn: Bool = false

    private var hasSelectedAlbum: Bool {
        settings.selectedAlbumId?.isEmpty == false
    }

    private var currentPhotoDisplay: String {
        let name = (settings.lastSetWallpaperItemName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty == false { return name }
        let id = (settings.lastSetWallpaperItemId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? "—" : id
    }

    private func stageText(_ stage: WallpaperManager.WallpaperUpdateStage) -> String {
        switch stage {
        case .idle:
            return "Idle"
        case .fetchingAlbumItems:
            return "Fetching album items…"
        case .filtering:
            return "Filtering candidates…"
        case .selectingCandidate(let attempt, let total, let name):
            return "Trying \(attempt)/\(max(1, total)): \(name)"
        case .usingCachedWallpaper(let name):
            return "Using cached: \(name)"
        case .downloading(let name, let attempt, let total):
            return "Downloading \(attempt)/\(max(1, total)): \(name)…"
        case .decoding(let name):
            return "Decoding/transcoding: \(name)…"
        case .writingFile(let name):
            return "Writing JPEG: \(name)…"
        case .applyingToScreens(let screenCount):
            return "Applying to \(screenCount) screen(s)…"
        case .done(let name):
            return name.isEmpty ? "Done" : "Done: \(name)"
        }
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
            // Give the settings window a moment to become the key window for MSAL presentation.
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
        Group {
            if let menuError, !menuError.isEmpty {
                Text(menuError)
            }

            if authService.isSignedIn {
                if let username = authService.signedInUsername, !username.isEmpty {
                    Text("Signed in as \(username)")
                } else {
                    Text("Signed in")
                }
            } else {
                Text("Signed out")
            }

            if let albumName = settings.selectedAlbumName, !albumName.isEmpty {
                Text("Album: \(albumName)")
            } else if hasSelectedAlbum {
                Text("Album: Saved album")
            } else {
                Text("Album: —")
            }

            Text("Activity: \(stageText(wallpaperManager.updateStage))")

            if let last = wallpaperManager.lastSuccessfulUpdate {
                Text("Last changed: \(last.formatted(date: .abbreviated, time: .shortened))")
            } else {
                Text("Last changed: —")
            }

            Text("Current: \(currentPhotoDisplay)")

            if authService.isSignedIn == false {
                Text("Next change: Sign in")
            } else if hasSelectedAlbum == false {
                Text("Next change: Select album")
            } else if settings.isPaused {
                Text("Next change: Paused")
            } else if settings.changeFrequency == .never {
                Text("Next change: Off")
            } else {
                let interval = WallpaperManager.intervalSeconds(for: settings.changeFrequency)
                let due = WallpaperManager.computeNextDueDate(
                    now: Date(),
                    lastSuccessfulWallpaperUpdate: settings.lastSuccessfulWallpaperUpdate,
                    intervalSeconds: interval,
                    hasSelectedAlbum: true,
                    isPaused: false,
                    lastAttemptDate: nil
                )
                if let due {
                    Text("Next change: \(due.formatted(date: .abbreviated, time: .shortened))")
                } else {
                    Text("Next change: —")
                }
            }

            if let lastError = wallpaperManager.lastUpdateError, !lastError.isEmpty {
                Text("Last error: \(lastError)")
            }

            Divider()

            Button {
                wallpaperManager.requestWallpaperUpdate(trigger: .manual)
            } label: {
                Label(wallpaperManager.isUpdating ? "Changing…" : "Change Wallpaper Now", systemImage: "sparkles")
            }
            .disabled(wallpaperManager.isUpdating || authService.isSignedIn == false || hasSelectedAlbum == false)
            .accessibilityIdentifier("menubar.changeNow")

            if settings.isPaused {
                Button {
                    settings.isPaused = false
                    wallpaperManager.startWallpaperUpdates()
                } label: {
                    Label("Resume Automatic Changes", systemImage: "play.fill")
                }
                .accessibilityIdentifier("menubar.pauseResume")
            } else {
                Button {
                    settings.isPaused = true
                    wallpaperManager.stopWallpaperUpdates()
                } label: {
                    Label("Pause Automatic Changes", systemImage: "pause.fill")
                }
                .accessibilityIdentifier("menubar.pauseResume")
            }

            Divider()

            Button {
                activateAppAndOpenSettings()
            } label: {
                Label("Open Settings…", systemImage: "gearshape")
            }
            .accessibilityIdentifier("menubar.openSettings")

            if let url = settings.selectedAlbumWebUrl {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Open Selected Album", systemImage: "photo.on.rectangle.angled")
                }
                .accessibilityIdentifier("menubar.openAlbum")
            }

            Divider()

            if authService.isSignedIn {
                Button {
                    signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityIdentifier("menubar.signOut")
            } else {
                Button {
                    beginSignIn()
                } label: {
                    Label(isSigningIn ? "Signing In…" : "Sign In…", systemImage: "person.crop.circle.badge.plus")
                }
                .disabled(isSigningIn)
                .accessibilityIdentifier("menubar.signIn")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Muraloom", systemImage: "power")
            }
            .accessibilityIdentifier("menubar.quit")
        }
        .task(id: authService.isSignedIn) {
            if authService.isSignedIn {
                wallpaperManager.startWallpaperUpdates()
            }
        }
    }
}
