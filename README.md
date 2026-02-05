# GPhotoPaper

GPhotoPaper is a macOS application that automatically changes your desktop wallpaper using photos from OneDrive (via Microsoft Graph).

**Status:** OneDrive sign-in (MSAL) and basic folder-based photo fetching work. The planned next step is selecting OneDrive *albums* (Graph bundles) instead of folders (see `ONEDRIVE_PLAN.md`).

## Features

*   **Automatic Wallpaper Changes**: Set a frequency for how often your wallpaper changes (e.g., hourly, daily).
*   **Customizable Photo Selection**: Choose between random or sequential photo picking.
*   **Image Filtering**: Filter photos by minimum width and orientation (horizontal only).
*   **Wallpaper Fill Mode**: Control how the image fills your desktop (fill, fit, stretch, center).
*   **OneDrive (Current)**: Authenticate, select a OneDrive folder, and fetch photos via Microsoft Graph.
*   **Albums (Planned)**: Select a OneDrive album (Graph bundle album) instead of a folder.

## Getting Started

### Prerequisites

*   macOS 12.0 or later
*   Xcode 13.0 or later
*   A Microsoft Entra ID (Azure) app registration for Microsoft Graph.

### Microsoft App Registration

You’ll need to:

1. Create an app registration (Azure portal): https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade
2. Set supported account types to include **personal Microsoft accounts**.
3. Add a redirect URI that matches `OneDriveRedirectUri` in `GPhotoPaper/Info.plist`.
   - In the Azure portal, go to your app → **Authentication** → **Add a platform** → **iOS/macOS**.
   - Enter your app’s **Bundle ID** (from Xcode target settings).
   - Azure will generate the redirect URI in the format `msauth.<bundle_id>://auth` (this is what the default `OneDriveRedirectUri` is set to).
4. Add Microsoft Graph delegated permissions:
   - `User.Read`
   - `Files.Read`
5. Set your **Application (client) ID** (don’t commit secrets):
   - Copy `GPhotoPaper/Secrets.xcconfig.example` to `GPhotoPaper/Secrets.xcconfig` (gitignored).
   - Set `ONEDRIVE_CLIENT_ID = ...` in `GPhotoPaper/Secrets.xcconfig`.
   - Where to find it (Microsoft Entra admin center):
     - Go to **Microsoft Entra ID** → **App registrations** → select your app.
     - On the app’s **Overview** page, copy **Application (client) ID**.
     - If the Entra portal warns that new registrations are deprecated, use the Azure portal instead:
       - App registrations (Azure portal): https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade
   - The app reads this via `GPhotoPaper/Config.xcconfig` → `ONEDRIVE_CLIENT_ID` → `OneDriveClientId` in `GPhotoPaper/Info.plist`.

### Troubleshooting

If clicking “Sign In” shows **“OneDrive auth is not configured”**, it means the app is still using placeholder values.

- Ensure `GPhotoPaper/Secrets.xcconfig` exists and contains `ONEDRIVE_CLIENT_ID = ...` (this is used by `GPhotoPaper/Info.plist` via `$(ONEDRIVE_CLIENT_ID)`).
- Verify `OneDriveRedirectUri` matches the redirect URI shown in the Azure portal for the **iOS/macOS** platform (usually `msauth.<bundle_id>://auth`).
- Verify `OneDriveScopes` is a space-separated list (e.g. `User.Read Files.Read`).
  - Note: `openid`, `profile`, and `offline_access` are reserved OIDC scopes. MSAL handles these automatically, so don’t include them here.

If clicking “Sign In” shows **“OneDrive auth setup failed …”**, MSAL failed to initialize using the values from `Info.plist`.

- Verify `OneDriveRedirectUri` matches the redirect URI shown in the Azure portal for the **iOS/macOS** platform (usually `msauth.<bundle_id>://auth`).
- Verify your app bundle identifier (Xcode target → **Signing & Capabilities** → **Bundle Identifier**) matches the `<bundle_id>` you entered in the Azure portal.
- If you changed bundle ID / redirect settings recently, try **Product → Clean Build Folder** in Xcode and run again.
- If the underlying error is **OSStatus -34018**, it usually means the app is missing a required Keychain entitlement. Ensure the `GPhotoPaper` target’s entitlements include MSAL’s default macOS cache group (`$(AppIdentifierPrefix)com.microsoft.identity.universalstorage`) and that the app is run as a signed build from Xcode.

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
7.  Ensure the URL scheme in `GPhotoPaper/Info.plist` matches the scheme used by your redirect URI (default scheme: `msauth.<bundle_id>`).

### Build and Run

1.  In Xcode, select your Mac as the target device.
2.  Click the "Run" button (or `Cmd + R`).

The application should now build and run on your macOS device.

To build via CLI:

```bash
xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' -derivedDataPath /tmp/gphotopaper_deriveddata build
```

## Usage

1.  Configure the wallpaper change frequency and selection settings in the app.
2.  Sign in to OneDrive.
3.  Load folders and select a folder (or paste a folder ID manually).
4.  Click "Change Wallpaper Now" to update immediately.

## Dev Notes

This section contains notes for developers working on the project.

*   **OneDrive Roadmap**: Refer to [`ONEDRIVE_PLAN.md`](ONEDRIVE_PLAN.md) for the MSAL + Albums plan.
*   **Repo Guidance**: Refer to [`AGENTS.md`](AGENTS.md) for contributor/Codex notes.
