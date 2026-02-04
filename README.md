# GPhotoPaper

GPhotoPaper is a macOS application that will automatically change your desktop wallpaper using photos from a selected OneDrive folder (via Microsoft Graph).

**Status:** OneDrive authentication and folder browsing are not implemented yet. The app currently includes the settings UI and wallpaper-setting logic, plus a stub photos service used to keep the project building.

## Features

*   **Automatic Wallpaper Changes**: Set a frequency for how often your wallpaper changes (e.g., hourly, daily).
*   **Customizable Photo Selection**: Choose between random or sequential photo picking.
*   **Image Filtering**: Filter photos by minimum width and orientation (horizontal only).
*   **Wallpaper Fill Mode**: Control how the image fills your desktop (fill, fit, stretch, center).
*   **OneDrive (Planned)**: Authenticate, select/create a OneDrive folder, and fetch photos via Microsoft Graph.

## Getting Started

### Prerequisites

*   macOS 12.0 or later
*   Xcode 13.0 or later
*   (Planned) A Microsoft Entra ID / Azure App Registration for Microsoft Graph.

### Microsoft App Registration (Planned)

This repo is set up to integrate with OneDrive using Microsoft Graph, but the OAuth flow is not wired up yet. When implemented, you’ll need to:

1. Create an app registration in Microsoft Entra ID (Azure).
2. Configure a redirect URI appropriate for a macOS app.
3. Grant Graph permissions required for reading photos.

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
7.  (Planned) Configure the OAuth callback URL scheme once OneDrive auth is implemented.

### Build and Run

1.  In Xcode, select your Mac as the target device.
2.  Click the "Run" button (or `Cmd + R`).

The application should now build and run on your macOS device.

## Usage

1.  Configure the wallpaper change frequency and selection settings in the app.
2.  (Planned) Sign in to OneDrive, select/create a folder, and fetch photos.
3.  Click "Change Wallpaper Now" to update immediately.

## Dev Notes

This section contains notes for developers working on the project.

*   **TODO List**: Refer to the [`TODO.md`](TODO.md) file for a list of pending tasks and future enhancements.
*   **Gemini Progress**: Refer to the [`GEMINI.md`](GEMINI.md) file for a detailed log of development progress and completed tasks.
