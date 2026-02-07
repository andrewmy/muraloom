# OneDrive Integration Battle Plan

This document outlines the plan to integrate OneDrive for photo management, targeting **personal Microsoft accounts** and using **Microsoft Graph Albums (bundles)** as the primary wallpaper source.

## Current status (repo)

- Repo is aligned to OneDrive (Google Sign-In removed).
- Core wallpaper pipeline exists (`WallpaperManager`) and settings UI exists.
- Implemented:
  - `OneDriveAuthService`: **MSAL** wrapper (interactive sign-in, silent token acquisition, sign-out).
  - `OneDrivePhotosService`: Microsoft Graph v1.0 for **albums (bundle albums)** (list albums, verify album, fetch photos in an album).
  - Settings UI: sign-in + **album** selection (+ link to manage albums in OneDrive Photos).
- CLI builds: `xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' ... build` succeeds when the environment has keychain/signing access.

### What works today (album mode)

- Sign in/out (MSAL) and silent token acquisition for scheduled wallpaper updates.
- List albums, select an album, and fetch image items from that album via Graph.
- Wallpaper update:
  - Downloads via `GET /me/drive/items/{item-id}/content` (authorized)
  - Does not rely on selecting `@microsoft.graph.downloadUrl` in `$select` (can 400 on some endpoints)
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

### Graph v1.0 quirk (personal accounts)

In practice (at least for some personal accounts), `bundle.album` is not reliably present and the `$filter=bundle/album ne null` query can return an empty list even when OneDrive Photos shows albums.

Current implementation uses the bundles endpoints and identifies “album-like” bundles using:

- `bundle.album` when present, OR
- `webUrl` host `photos.onedrive.com` (matches the OneDrive Photos album UI).

### Learnings / gotchas (Graph)

- Some Graph responses expose `@microsoft.graph.downloadUrl`, but selecting it via `$select` can fail with HTTP 400 (“AnnotationSegment”). Prefer downloading the chosen item using `/content`.
- For DriveItem `children` expansion, Graph supports only `$select` and `$expand` inside the `$expand` options. Using `$top` inside `children(...)` can fail with HTTP 400 (“Can only provide expand and select for expand options”).
- For bundle albums, `GET /me/drive/items/{id}/children` can be unreliable; prefer `GET /me/drive/items/{id}?$expand=children(...)` (and page using `children@odata.nextLink`).

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

### Phase 2 — Albums API (Graph bundles) (done)

- Update the service layer:
  - Add `listAlbums()`, `verifyAlbumExists(albumId:)`, `searchPhotos(in albumId:)` (album contents).
- Update models:
  - Rename settings from folder to album: `selectedAlbumId`, `selectedAlbumName`, `selectedAlbumWebUrl`.
  - Ensure picture metadata is captured (`width/height`) to support filtering in `WallpaperManager`.
- Scopes:
  - Start: `User.Read Files.Read` (MSAL handles OIDC reserved scopes like `offline_access` automatically)
  - Add later if needed: `Files.ReadWrite` (create album / add items).

### Phase 3 — UI update (albums instead of folders) (done)

- Album picker (done):
  - “Load albums” → list bundles
  - Selection persisted in settings
  - Link to open the selected album (when `webUrl` is available from bundle metadata)
  - Link to manage albums in OneDrive Photos
- Startup behavior / validation:
  - On app start, verify the previously selected album still exists and is accessible.
  - When loading a stored selection, probe the first page and show a warning if there are no usable photos.
  - Auto-load albums on startup when signed in (so the picker appears without manual reload).
  - Keep manual ID entry + full scan behind “Advanced”.

### Phase 3.5 — MVP wallpaper + app-shell polish (next)

Goal: make wallpaper changes reliable and user-visible for MVP, without changing the wallpaper on app launch.

Immediate (MVP) improvements (priority order: reliability → UX/status → selection quality):

- Multi-monitor (MVP): set the **same** wallpaper on **all** screens (not just the main screen).
- Update serialization (MVP): prevent overlapping wallpaper updates (timer tick + “Change Now” + album change).
  - Policy: **manual overrides timer** (manual cancels/replaces timer-driven work; timer ticks never interrupt a manual update).
- Status + errors (MVP): stop relying on `print()` as the only feedback.
  - Persist and show: last successful update time, last error (if any), and the selected album identity.
  - Disable or explain “Change Wallpaper Now” when signed out or no album is selected.
- Timer UX (MVP): interval-based schedule with clear status.
  - Next auto change is computed as: `next = lastSuccessfulWallpaperUpdate + interval`.
  - Manual changes update `lastSuccessfulWallpaperUpdate` (so manual resets the schedule), and the UI shows “Last changed” + “Next change”.
- Graph resilience (MVP): add a small retry/backoff policy for transient errors (429 / 5xx) and handle token failures cleanly.
- Local file handling (MVP): don’t write raw downloaded bytes to `wallpaper.jpg` (file contents may be TIFF/HEIC/etc).
  - Keep atomic writes, and avoid leaving partial files behind if downloads fail.
  - MVP approach: always set the wallpaper from a real JPEG file on disk (transcode when needed) and downscale to a “recommended” max dimension:
    - `recommended = max(physical panel pixels, effective “Looks like …” pixels)` across connected displays.
  - If an item can’t be decoded/transcoded, try a few other photos before surfacing an error.
  - RAW photos (ARW/DNG/etc): require a dedicated decoder (LibRaw). If LibRaw is enabled, decode RAW → JPEG; otherwise exclude RAW items from “usable photos” (see `docs/LIBRAW.md`).
- Menu bar (MVP): add a status item for quick control + visibility (even when the window is closed).
  - Minimum actions: Change Now, Pause/Resume, Open Settings, Sign In/Out, Open Selected Album.
  - Minimum status: signed-in state + last update / last error indicator.
- Selection quality (MVP, lightweight): reduce obvious repeats and avoid expensive full-album scans on every tick when possible.
  - Example approach: cache the last fetched item list (with a TTL) and re-use it for selection.

Non-goals for MVP (explicit):

- Do **not** change wallpaper automatically on app launch (user should trigger manually or wait for next interval).
- Do **not** implement “different wallpaper per display” in MVP (post-MVP).

### Phase 4 — Offline mode (planned; post-MVP)

Goal: a workable experience when Graph is temporarily unavailable.

- Cache a “last known good” wallpaper image (and possibly a small ring buffer).
- If a wallpaper update fails (offline, token issue, Graph errors), fall back to cached images instead of failing silently.
- UX: surface an “offline / last updated” status and guidance to re-auth / retry.

### Phase 5 — Album write operations (planned; post-MVP / separate)

- Create album UI (requires `Files.ReadWrite`)
- Add/remove items from an album within the app (also `Files.ReadWrite`) to support curation without leaving the app

### Phase 6 — Wallpaper suitability filtering (planned; post-MVP)

Goal: prefer images that will look good as wallpaper on the current Mac (and later, multiple displays).

- Minimum resolution:
  - Prefer images with pixel dimensions >= current screen pixel size (account for Retina scaling).
  - Decide behavior when width/height metadata is missing: allow, deprioritize, or download headers to detect dimensions.
- Orientation and aspect ratio:
  - Keep “horizontal only” option, but consider aspect-ratio bounds (avoid extreme panoramas unless user opts in).
  - Optionally match aspect ratio to the current screen more closely (especially for Fill vs Fit).
- File format / type:
  - Exclude videos and non-image mime types.
  - Decide whether to accept formats like HEIC, PNG, GIF (animated), and how to handle alpha/animation.
- Quality / UX heuristics (optional):
  - Avoid duplicates (same item id) and repeat too frequently.
  - Prefer recent photos or favorites (if Graph metadata supports it later).

### Phase 7 — Testing & hardening (ongoing; expand post-MVP)

- Unit tests:
  - Token handling boundaries (signed out, expired token) via mocks.
  - Album paging and filtering logic.
- UX checks:
  - Error messaging for “not configured” vs “not signed in” vs “no albums/photos”.
  - Behavior when album disappears or loses permissions.
- Multi-monitor support (post-MVP): allow **different** wallpapers per screen and per-screen fill/scaling options.

## Nice-to-have backlog (post-MVP)

These are desirable, but not required to ship MVP.

- Launch at login (and a “running in menu bar” primary UX if desired).
- Advanced scheduling triggers:
  - Change on wake / unlock
  - Time-of-day scheduling (not just fixed intervals)
- Offline-first improvements:
  - Prefetch a small ring buffer so updates succeed while offline.
  - Persist a lightweight cache of album item IDs/metadata to reduce Graph work across launches.
- Photo history + undo:
  - Keep recent wallpapers, show a small history, and allow “back” / “favorite”.
- “Now playing” style info:
  - Show the current wallpaper’s filename / date / source (album) and provide “Open in OneDrive”.
- Selection/quality heuristics:
  - Stronger de-duplication (avoid repeats within N changes).
  - Better aspect ratio matching per display and fill mode.
- Multi-account support:
  - Switch between personal Microsoft accounts and bind albums per account.

## Cleanup checklist

- Remove folder-centric UI/strings once albums are the default. (done)
- Remove native OAuth implementation once MSAL is fully wired.
- Ensure `Info.plist` contains only the final OAuth callback configuration and documented keys.
