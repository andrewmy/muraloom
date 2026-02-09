# Muraloom

Muraloom is a macOS app that automatically changes your desktop wallpaper using photos from a OneDrive album.

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
3. Add an **iOS/macOS** redirect URI that matches `OneDriveRedirectUri` in `Muraloom/Info.plist`.
   - Azure will generate the redirect URI in the format `msauth.<bundle_id>://auth`.
4. Add delegated Microsoft Graph permissions:
   - `User.Read`
   - `Files.Read`
5. Provide your **Application (client) ID** to the app (don’t commit secrets):
   - Copy `Muraloom/Secrets.xcconfig.example` to `Muraloom/Secrets.xcconfig` (gitignored).
   - Set `ONEDRIVE_CLIENT_ID = ...` in `Muraloom/Secrets.xcconfig`.

### Troubleshooting

If clicking “Sign In” shows **“OneDrive auth is not configured”**, it means the app is still using placeholder values.

- Ensure `Muraloom/Secrets.xcconfig` exists and contains `ONEDRIVE_CLIENT_ID = ...` (this is used by `Muraloom/Info.plist` via `$(ONEDRIVE_CLIENT_ID)`).
- Verify `OneDriveRedirectUri` matches the redirect URI shown in the Azure portal for the **iOS/macOS** platform (usually `msauth.<bundle_id>://auth`).
- Verify `OneDriveScopes` is a space-separated list (e.g. `User.Read Files.Read`).
  - Note: `openid`, `profile`, and `offline_access` are reserved OIDC scopes. MSAL handles these automatically, so don’t include them here.

If clicking “Sign In” shows **“OneDrive auth setup failed …”**, MSAL failed to initialize using the values from `Info.plist`.

- Verify `OneDriveRedirectUri` matches the redirect URI shown in the Azure portal for the **iOS/macOS** platform (usually `msauth.<bundle_id>://auth`).
- Verify your app bundle identifier (Xcode target → **Signing & Capabilities** → **Bundle Identifier**) matches the `<bundle_id>` you entered in the Azure portal.
- If you changed bundle ID / redirect settings recently, try **Product → Clean Build Folder** in Xcode and run again.
- If the underlying error is **OSStatus -34018**, it usually means the app is missing a required Keychain entitlement. Ensure the `Muraloom` target’s entitlements include MSAL’s default macOS cache group (`$(AppIdentifierPrefix)com.microsoft.identity.universalstorage`) and that the app is run as a signed build from Xcode.

If you downloaded `Muraloom.app` and macOS refuses to open it, remove the quarantine attribute and try again:

```bash
xattr -dr com.apple.quarantine /path/to/Muraloom.app
open /path/to/Muraloom.app
```

### Xcode Setup

1.  Clone this repository:
    ```bash
    git clone https://github.com/andrewmy/muraloom.git
    cd muraloom
    ```
2.  Open the `Muraloom.xcodeproj` file in Xcode.
3.  In Xcode, select the `Muraloom` target in the project navigator.
4.  Go to the "Signing & Capabilities" tab.
5.  Change the "Team" to your development team.
6.  Change the "Bundle Identifier" to a unique identifier (e.g., `com.yourcompany.Muraloom`).
7.  Ensure the URL scheme in `Muraloom/Info.plist` matches the scheme used by your redirect URI (default scheme: `msauth.<bundle_id>`).

### Build and Run

1.  In Xcode, select your Mac as the target device.
2.  Click the "Run" button (or `Cmd + R`).

The application should now build and run on your macOS device.

#### Build / Run / Test via CLI

Build (Debug):

```bash
xcodebuild -scheme Muraloom -destination 'platform=macOS' -derivedDataPath /tmp/muraloom_deriveddata build
```

If you only need a compile sanity check (and want to avoid signing/keychain issues):

```bash
xcodebuild -scheme Muraloom -destination 'platform=macOS' -derivedDataPath /tmp/muraloom_deriveddata CODE_SIGNING_ALLOWED=NO build
```

Run the built app (requires a signed build; `CODE_SIGNING_ALLOWED=NO` won’t produce a runnable app):

```bash
open /tmp/muraloom_deriveddata/Build/Products/Debug/Muraloom.app
```

Run tests from CLI:

```bash
xcodebuild -scheme Muraloom -destination 'platform=macOS' -derivedDataPath /tmp/muraloom_deriveddata test
```

Run only unit tests:

```bash
xcodebuild -scheme Muraloom -destination 'platform=macOS' -derivedDataPath /tmp/muraloom_deriveddata_test test -only-testing:MuraloomTests
```

Run unit tests with code coverage (and produce an `.xcresult` bundle you can inspect in Xcode):

```bash
xcodebuild -scheme Muraloom -destination 'platform=macOS' -derivedDataPath /tmp/muraloom_deriveddata_test -resultBundlePath /tmp/muraloom_tests.xcresult -enableCodeCoverage YES test -only-testing:MuraloomTests
bash bin/coverage-gate.sh /tmp/muraloom_tests.xcresult 50 Muraloom
```

CI enforces this as a gate (unit tests only): `Muraloom.app` line coverage must be at least 50%.
To run the same gate locally, use `just coverage` (or `just coverage-report` for a report without enforcing a minimum).

Run only UI tests (hermetic; no network/auth required):

```bash
xcodebuild -scheme Muraloom -destination 'platform=macOS' -derivedDataPath /tmp/muraloom_deriveddata_ui_test -resultBundlePath /tmp/muraloom_ui_tests.xcresult CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="-" CODE_SIGN_ENTITLEMENTS="" test -only-testing:MuraloomUITests
```

Convenience `just` recipes:

```bash
just test      # unit tests
just coverage  # unit tests + coverage gate
just ui-test   # UI tests
just test-all  # unit + UI tests
```

UI tests (Debug builds) launch the app with `-ui-testing` to use local fixture services (no interactive sign-in, no Graph calls). In UI testing mode, Advanced also shows a small “Menu Bar (UI testing)” harness so menu actions can be tested without relying on the system status bar UI.
On macOS, Xcode UI tests may also prompt to close other running apps (“Remove Other Apps”) to improve reliability.

#### RAW photos (LibRaw)

RAW decoding is optional and off by default. To enable it, follow `docs/LIBRAW.md`. CI installs LibRaw via Homebrew automatically (see `.github/workflows/ci.yml`).

## Usage

1.  Configure the wallpaper change frequency and selection settings in the app.
2.  Sign in to OneDrive.
3.  Load albums and select an album.
    - To create/manage albums, use OneDrive Photos (https://photos.onedrive.com) and then reload albums in the app.
    - If you can’t load albums for some reason, use **Advanced** to paste an album ID manually.
4.  Click "Change Wallpaper Now" to update immediately.

## Contributing

- Roadmap / implementation notes: `docs/PROJECT_PLAN.md`
- Repo guidance (contributors/Codex): `AGENTS.md`
