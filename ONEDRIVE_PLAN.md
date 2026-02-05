# OneDrive Integration Battle Plan

This document outlines the plan to integrate OneDrive for photo management, targeting **personal Microsoft accounts** and using **Microsoft Graph Albums (bundles)** as the primary wallpaper source.

## Current status (repo)

- Repo is aligned to OneDrive (Google Sign-In removed).
- Core wallpaper pipeline exists (`WallpaperManager`) and settings UI exists.
- Implemented:
  - `OneDriveAuthService`: **MSAL** wrapper (interactive sign-in, silent token acquisition, sign-out).
  - `OneDrivePhotosService`: Microsoft Graph v1.0 for **folders** (list root folders, verify folder, fetch photos in a folder).
  - Settings UI: sign-in + basic **folder** selection.
- CLI builds: `xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' ... build` succeeds when the environment has keychain/signing access.

### What works today (folder mode)

- Sign in/out (MSAL) and silent token acquisition for scheduled wallpaper updates.
- List root folders, select a folder, and fetch image items from that folder via Graph.
- Wallpaper update:
  - Downloads `@microsoft.graph.downloadUrl`
  - Applies filtering (min width, horizontal only) when image dimensions are available

### Configuration keys (current)

`Info.plist` currently expects:

- `OneDriveClientId`
- `OneDriveRedirectUri`
- `OneDriveScopes` (space-separated)
- Optional: `OneDriveAuthorityHost` (default `login.microsoftonline.com`), `OneDriveTenant` (default `common`)

## Decisions (locked in)

1. **Auth library:** MSAL (Microsoft Authentication Library).
  - Other providers may use AppAuth or other mechanism
2. **Wallpaper source:** OneDrive **Albums** (Graph “bundle album”) instead of folders.

## What “album” means in Graph

- Album is a **bundle**: a `driveItem` with `bundle.album` facet.
- Listing albums: `GET /drive/bundles?$filter=bundle/album ne null`
- Album contents: `GET /drive/items/{bundle-id}?expand=children` (page via `children@odata.nextLink`)
- Creating / modifying albums requires write scopes:
  - Create: `POST /drive/bundles` with `bundle: { album: {} }`
  - Add/remove item: `POST /drive/bundles/{id}/children` / `DELETE /drive/bundles/{id}/children/{item-id}`

Note: Bundle/album APIs are **personal Microsoft account** focused. If we later want to support work/school tenants, plan a fallback source mode (folder selection or in-app “virtual set”).

## Remaining work (phased)

### Phase 1 — Switch auth to MSAL (done)

- Add MSAL dependency (SwiftPM).
- Implement `OneDriveAuthService` as an MSAL wrapper:
  - Interactive sign-in + sign-out
  - Silent token acquisition for scheduled wallpaper updates
  - Multiple accounts: decide whether to support now or later (MSAL makes this easier).
- Update configuration:
  - Redirect URI uses `msauth.<bundle_id>://auth` (Azure portal iOS/macOS platform).
  - Local dev client id via `GPhotoPaper/Secrets.xcconfig` (gitignored) → `ONEDRIVE_CLIENT_ID` → `OneDriveClientId` in `Info.plist`.
  - Avoid passing reserved OIDC scopes to MSAL acquire-token calls (`openid`, `profile`, `offline_access`).
- Keychain entitlement (macOS):
  - Ensure `keychain-access-groups` includes `$(AppIdentifierPrefix)com.microsoft.identity.universalstorage` (MSAL default cache group), otherwise you may hit OSStatus `-34018`.
- Cleanup (later):
  - Remove the native `ASWebAuthenticationSession` + PKCE fallback once MSAL is stable.

### Phase 2 — Albums API (Graph bundles)

- Update the service layer:
  - Add `listAlbums()`, `verifyAlbumExists(albumId:)`, `searchPhotos(in albumId:)` (album contents).
  - Keep folder-based methods only as an optional fallback mode (or remove if not needed).
- Update models:
  - Rename settings from folder to album: `selectedAlbumId`, `selectedAlbumName`, `selectedAlbumWebUrl`.
  - Ensure picture metadata is captured (`width/height`) to support filtering in `WallpaperManager`.
- Scopes:
  - Start: `User.Read Files.Read` (MSAL handles OIDC reserved scopes like `offline_access` automatically)
  - Add later if needed: `Files.ReadWrite` (create album / add items).

### Phase 3 — UI update (albums instead of folders)

- Replace the folder picker with an album picker:
  - “Load albums” → list bundles
  - Selection persisted in settings
  - Link to open the album (if `webUrl` is available from bundle metadata)
- Startup behavior / validation:
  - On app start, verify the previously selected album still exists and is accessible.
  - When loading a stored selection, fetch photo count (or first page) and show a warning if the album has no photos.
- Optional:
  - Create album UI (requires `Files.ReadWrite`)
  - Add item to album from within the app (also `Files.ReadWrite`), if we want to support curation without leaving the app.

### Phase 4 — Testing & hardening

- Unit tests:
  - Token handling boundaries (signed out, expired token) via mocks.
  - Album paging and filtering logic.
- UX checks:
  - Error messaging for “not configured” vs “not signed in” vs “no albums/photos”.
  - Behavior when album disappears or loses permissions.
- Multi-monitor support (later): decide per-screen vs all screens.

## Cleanup checklist

- Remove folder-centric UI/strings once albums are the default.
- Remove native OAuth implementation once MSAL is fully wired.
- Ensure `Info.plist` contains only the final OAuth callback configuration and documented keys.
