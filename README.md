# GPhotoPaper

GPhotoPaper is a macOS application that allows you to automatically change your desktop wallpaper using photos from a specific Google Photos album.

## Features

*   **Google Photos Integration**: Authenticate with your Google account. The application will create and use a dedicated album in your Google Photos for wallpapers.
*   **Automatic Wallpaper Changes**: Set a frequency for how often your wallpaper changes (e.g., hourly, daily).
*   **Customizable Photo Selection**: Choose between random or sequential photo picking.
*   **Image Filtering**: Filter photos by minimum width and orientation (horizontal only).
*   **Wallpaper Fill Mode**: Control how the image fills your desktop (fill, fit, stretch, center).

## Getting Started

### Prerequisites

*   macOS 12.0 or later
*   Xcode 13.0 or later
*   A Google Cloud Project with the Google Photos Library API enabled.

### Google Cloud Project Setup

1.  Go to the [Google Cloud Console](https://console.cloud.google.com/).
2.  Create a new project or select an existing one.
3.  Navigate to "APIs & Services" > "Library".
4.  Search for and enable the "Google Photos Library API".
5.  Go to "APIs & Services" > "OAuth consent screen".
    *   Configure your OAuth consent screen (User type, App name, etc.).
    *   Under "Scopes", add the following scopes:
        *   `https://www.googleapis.com/auth/photoslibrary.appendonly`
        *   `https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata`
6.  Go to "APIs & Services" > "Credentials".
7.  Click "Create Credentials" > "OAuth client ID".
8.  Select "macOS" as the Application type.
9.  Enter a name for your OAuth client (e.g., "GPhotoPaper Desktop").
10. Click "Create".
11. Note down your **Client ID**. You will need this for the Xcode project.

### Xcode Setup

1.  Clone this repository:
    ```bash
    git clone https://github.com/andrewmy/GPhotoPaper.git
    cd GPhotoPaper
    ```
2.  Open the `GPhotoPaper.xcodeproj` file in Xcode.
3.  In Xcode, select the `GPhotoPaper` target in the project navigator.
4.  Go to the "Signing & Capabilities" tab.
5.  Change the "Team" to your development team.
6.  Change the "Bundle Identifier" to a unique identifier (e.g., `com.yourcompany.GPhotoPaper`).
7.  **Update Google Client ID**:
    *   Open `GPhotoPaperApp.swift`.
    *   Locate the `GIDSignIn.sharedInstance.configuration` line.
    *   Replace `"YOUR_CLIENT_ID_HERE"` with the Client ID you obtained from the Google Cloud Console.
        ```swift
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: "YOUR_CLIENT_ID_HERE" // <--- Update this line
        )
        ```
8.  **Add URL Scheme**:
    *   In the "Info" tab of your `GPhotoPaper` target, expand "URL Types".
    *   Click the "+" button to add a new URL Type.
    *   For "URL Schemes", enter your reversed Client ID. For example, if your Client ID is `1234567890-abcdef123456.apps.googleusercontent.com`, your URL Scheme would be `com.googleusercontent.apps.1234567890-abcdef123456`.

    *Note: Keychain and Network capabilities are typically handled automatically by Xcode for standard macOS applications. You generally do not need to manually enable them in the project settings.*

### Build and Run

1.  In Xcode, select your Mac as the target device.
2.  Click the "Run" button (or `Cmd + R`).

The application should now build and run on your macOS device.

## Usage

1.  **Authenticate**: On the first launch, you will be prompted to sign in with your Google account.
2.  **Create Album**: If no app-managed album is found, click "Create New Album". This will create a new album in your Google Photos named "GPhotoPaper" (or "GPhotoPaper - [UUID]" if a conflict occurs).
3.  **Add Photos**: Add photos to the newly created "GPhotoPaper" album in your Google Photos.
4.  **Configure Settings**: Adjust the wallpaper change frequency, photo picking method, and other preferences in the application's settings.
5.  **Change Wallpaper Now**: Click this button to immediately change your wallpaper based on your current settings.

## Dev Notes

This section contains notes for developers working on the project.

*   **Temporary File Management**: The current implementation creates a new temporary file for each wallpaper change and immediately deletes it. A more robust strategy for managing temporary wallpaper files (e.g., reusing files, periodic cleanup of old files) should be considered for future improvements.
*   **TODO List**: Refer to the [`TODO.md`](TODO.md) file for a list of pending tasks and future enhancements.
*   **Gemini Progress**: Refer to the [`GEMINI.md`](GEMINI.md) file for a detailed log of development progress and completed tasks.
