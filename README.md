# GPhotoPaper

GPhotoPaper is a macOS application that allows you to use photos from a dedicated Google Photos album as your desktop wallpaper, with options for automatic changes and filtering.

## Features

*   **Google Photos Integration**: Authenticate with your Google account and select a specific album to source wallpapers from.
*   **App-Managed Album**: Create a dedicated album within Google Photos for your wallpapers.
*   **Customizable Wallpaper Changes**:
    *   Set the frequency of wallpaper changes (e.g., hourly, daily).
    *   Choose between random or sequential photo picking.
    *   Filter photos by minimum width and aspect ratio (horizontal only).
*   **Wallpaper Management**: Automatically sets your desktop wallpaper using photos from your chosen album.

## Getting Started

### Prerequisites

*   macOS 12.0+
*   Xcode 15.0+
*   A Google Cloud Project with the Google Photos Library API enabled.

### Build and Run

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/your-username/GPhotoPaper.git
    cd GPhotoPaper
    ```

2.  **Open in Xcode**:
    Open `GPhotoPaper.xcodeproj` in Xcode.

3.  **Configure Google API Client ID**:
    This application requires a Google API Client ID for authentication with Google Photos. Follow these steps to set it up:
    *   Go to the [Google Cloud Console](https://console.cloud.google.com/).
    *   Select your project or create a new one.
    *   Navigate to "APIs & Services" > "Credentials".
    *   Create an "OAuth client ID" of type "iOS".
    *   **Important**: The "Bundle ID" in the Google Cloud Console must match the Bundle Identifier of your Xcode project (e.g., `com.yourcompany.GPhotoPaper`). You can find/set this in Xcode under your project target's "Signing & Capabilities" tab.
    *   After creating the client ID, download the `client_secret.json` (or copy the client ID string).
    *   **In Xcode**:
        *   Open `GPhotoPaper/Info.plist`.
        *   Locate the `CFBundleURLTypes` array.
        *   Under `Item 0` (or the relevant item), find `CFBundleURLSchemes`.
        *   The `Item 0` within `CFBundleURLSchemes` should be set to your **reversed client ID**. For example, if your client ID is `YOUR_CLIENT_ID.apps.googleusercontent.com`, your URL scheme will be `com.googleusercontent.apps.YOUR_CLIENT_ID`.
        *   You will also need to ensure your client ID is correctly configured in `GoogleAuthService.swift`. Look for a placeholder or a variable where the client ID is expected to be set.

4.  **Enable Capabilities**:
    Ensure the following capabilities are enabled for your target in Xcode under "Signing & Capabilities":
    *   `Keychain Sharing`
    *   `App Sandbox` (with `Network: Outgoing Connections (Client)` enabled)

5.  **Build and Run**:
    Select the `GPhotoPaper` target and your macOS device (or "My Mac") and click the "Run" button in Xcode.

## Troubleshooting

*   **Authentication Issues**: Double-check your Google API Client ID setup, especially the reversed client ID in `Info.plist` and the bundle identifier in both Xcode and Google Cloud Console.
*   **API Scope Errors**: Ensure that the `Google Photos Library API` is enabled in your Google Cloud Project and that the correct scopes (`https://www.googleapis.com/auth/photoslibrary.appendonly` and `https://www.googleapis.com/auth/photoslibrary.readonly.appcreateddata`) are being requested by the application.

---

## Development Notes

*   [TODO List](TODO.md)
*   [Gemini Development Instructions](GEMINI.md)