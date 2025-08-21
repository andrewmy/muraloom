# Gemini Development Instructions

This document contains specific instructions for the Gemini agent to continue development of the GPhotoPaper macOS application.

## Current State

- Authentication flow is implemented and should be working (requires user verification).
- Basic UI for settings is in place, including album creation button.
- Google Photos API integration for album creation is implemented.
- File access issues have been resolved (user moved files into workspace).
- `replace` tool has been unreliable; prefer `write_file` for full file updates.

## Next Steps for Gemini

1.  **Verify User Authentication & Album Creation**:
    - Wait for user confirmation that authentication and "Create New Album" button work as expected.
    - If the user reports errors, diagnose and fix them using `write_file` for updates.

2.  **Implement Album ID Persistence**:
    - Modify `SettingsView.swift` to save `settings.appCreatedAlbumId` and `settings.appCreatedAlbumName` to `UserDefaults` after an album is successfully created.
    - Modify `SettingsModel.swift` to load these values from `UserDefaults` on initialization.

3.  **Implement Photo Search Logic**:
    - Modify `GooglePhotosService.swift` to implement `searchPhotos(in albumId: String)` fully, applying `minimumPictureWidth` and `horizontalPhotosOnly` filters.

4.  **Implement Wallpaper Management Logic**:
    - Modify `WallpaperManager.swift` to:
        - Fetch photos using `GooglePhotosService`.
        - Apply random/sequential picking.
        - Set the wallpaper using `NSWorkspace`.
        - Implement scheduling based on `changeFrequency`.

5.  **Integrate Wallpaper Management with UI**:
    - Connect "Change Wallpaper Now" button in `SettingsView.swift` to `WallpaperManager`.

6.  **Create `README.md`**:
    - [x] Generate a comprehensive `README.md` file with build/run instructions, manual Xcode steps, and client ID information.

## Tool Usage Guidelines

- **Always prioritize user instructions.**
- **For file modifications, prefer `write_file` over `replace` if `replace` has been unreliable.**
- **Provide clear, concise explanations for any actions taken.**
- **Request user verification after significant changes.**
