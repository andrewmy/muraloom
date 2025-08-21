# GPhotoPaper Development Checklist

This document outlines the remaining tasks for the GPhotoPaper macOS application.

## Core Features

- [x] **Authentication**
  - [x] Sign in to a Google account.
  - [x] Sign out from a Google account.
  - [x] Request `https://www.googleapis.com/auth/photoslibrary.appendonly` scope.
  - [x] Request `https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata` scope.

- [ ] **App-Managed Album**
  - [x] Implement logic to create an album with a unique, human-friendly name ("GPhotoPaper" or "GPhotoPaper - UUID").
  - [ ] Persist the ID and name of the app-created album using `UserDefaults`.
  - [x] Display instructions to the user to add photos to the app-created album.

- [ ] **Settings User Interface (UI)**
  - [x] Display UI for "Create/Manage App Album".
  - [x] Implement UI for choosing picture change frequency ("Never", "Every Hour", "Every 6 Hours", "Daily").
  - [x] Implement UI for choosing to pick the next picture randomly or in time sequence.
  - [x] Implement UI for choosing minimum picture width (default to desktop resolution).
  - [x] Implement UI for choosing wallpaper fill mode ("Fill", "Fit", "Stretch", "Center").
  - [x] Implement a button to change the wallpaper immediately.

- [ ] **Core Wallpaper Functionality**
  - [ ] Implement logic to fetch photos from the app-created album using `photoslibrary.readonly.appcreateddata` scope.
  - [ ] Implement logic to filter photos by minimum width.
  - [ ] Implement logic to filter photos by aspect ratio (horizontal only).
  - [ ] Implement logic to pick the next picture randomly or in time sequence.
  - [ ] Implement logic to set the current wallpaper using `NSWorkspace`.
  - [ ] Implement scheduling for automatic wallpaper changes based on frequency.

## Project Setup & Maintenance

- [x] Project opens and builds in Xcode.
- [x] Project uses Swift and SwiftUI.
- [x] Project builds via `xcodebuild` command line.
- [x] `Info.plist` correctly configured for URL schemes.
- [x] Keychain Sharing capability enabled.
- [x] App Sandbox capability enabled.
- [x] Create a comprehensive GitHub-friendly `README.md` file for humans. Include instructions on how to build and run the project, and what to do manually in the console or Xcode, and values to change in the code.

---