# GPhotoPaper

GPhotoPaper is a macOS app that automatically changes your desktop wallpaper using photos from a OneDrive album.

## Features

*   **Automatic Wallpaper Changes**: Set a frequency for how often your wallpaper changes (e.g., hourly, daily).
*   **Customizable Photo Selection**: Choose between random or sequential photo picking.
*   **Image Filtering**: Filter photos by minimum width and orientation (horizontal only).
*   **Wallpaper Fill Mode**: Control how the image fills your desktop (fill, fit, stretch, center).
*   **OneDrive Album Picker**: Sign in and pick a OneDrive album (advanced: manual album ID).
*   **RAW Photos (optional)**: ARW/DNG/etc are supported when LibRaw is enabled (see `docs/LIBRAW.md`).

## Getting Started

### Prerequisites

*   macOS 12.0 or later
*   Xcode 13.0 or later
*   A Microsoft Entra ID (Azure) app registration for Microsoft Graph (personal Microsoft accounts).

### Microsoft App Registration

You’ll need to:

1. Create an app registration in the Azure portal: https://portal.azure.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade
2. Set supported account types to include **personal Microsoft accounts**.
3. Add an **iOS/macOS** redirect URI that matches `OneDriveRedirectUri` in `GPhotoPaper/Info.plist`.
   - Azure will generate the redirect URI in the format `msauth.<bundle_id>://auth`.
4. Add delegated Microsoft Graph permissions:
   - `User.Read`
   - `Files.Read`
5. Provide your **Application (client) ID** to the app (don’t commit secrets):
   - Copy `GPhotoPaper/Secrets.xcconfig.example` to `GPhotoPaper/Secrets.xcconfig` (gitignored).
   - Set `ONEDRIVE_CLIENT_ID = ...` in `GPhotoPaper/Secrets.xcconfig`.

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

#### Build / Run / Test via CLI

Build (Debug):

```bash
xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' -derivedDataPath /tmp/gphotopaper_deriveddata build
```

If you only need a compile sanity check (and want to avoid signing/keychain issues):

```bash
xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' -derivedDataPath /tmp/gphotopaper_deriveddata CODE_SIGNING_ALLOWED=NO build
```

Run the built app (requires a signed build; `CODE_SIGNING_ALLOWED=NO` won’t produce a runnable app):

```bash
open /tmp/gphotopaper_deriveddata/Build/Products/Debug/GPhotoPaper.app
```

Run tests from CLI:

```bash
xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' -derivedDataPath /tmp/gphotopaper_deriveddata test
```

If UI tests fail to bootstrap in your environment, run only unit tests:

```bash
xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' -derivedDataPath /tmp/gphotopaper_deriveddata test -only-testing:GPhotoPaperTests
```

## Usage

1.  Configure the wallpaper change frequency and selection settings in the app.
2.  Sign in to OneDrive.
3.  Load albums and select an album.
    - To create/manage albums, use OneDrive Photos (https://photos.onedrive.com) and then reload albums in the app.
    - If you can’t load albums for some reason, use **Advanced** to paste an album ID manually.
4.  Click "Change Wallpaper Now" to update immediately.

## Contributing

- Roadmap / implementation notes: `ONEDRIVE_PLAN.md`
- Repo guidance (contributors/Codex): `AGENTS.md`
