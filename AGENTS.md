## Repo guidance (Codex / contributors)

### Product direction

- Target integration is **OneDrive** (Microsoft Graph) for **personal Microsoft accounts**.
- Source of truth for roadmap/decisions: `ONEDRIVE_PLAN.md`.
- Locked-in direction:
  - Auth: **MSAL**
  - Wallpaper source: **OneDrive Albums** (Graph bundle albums), not folders

### Builds

- CLI build:
  - `xcodebuild -scheme GPhotoPaper -destination 'platform=macOS' -derivedDataPath /tmp/gphotopaper_deriveddata build`
- If CLI builds fail with signing/keychain errors but Xcode builds work:
  - Ensure Xcode is signed into your Apple ID and the target has a Team + “Automatically manage signing”.
  - Some sandboxed/automation environments may need elevated permissions to access signing certificates.
  - For a “compile-only” sanity check in CI, you can use `CODE_SIGNING_ALLOWED=NO` (won’t produce a runnable signed app).

### Current implementation status

- Present today (working): native OAuth (`ASWebAuthenticationSession` + PKCE) + **folder-based** Graph fetching.
- Transitional code to expect refactors:
  - `OneDriveAuthService` will become an MSAL wrapper.
  - `OneDrivePhotosService` will switch from folders to **album bundles** (`/drive/bundles`).

### Config & scopes (today)

- `Info.plist` keys used by the current native OAuth path:
  - `OneDriveClientId`, `OneDriveRedirectUri`, `OneDriveScopes`
- Default read-only scope set for wallpaper fetching:
  - `User.Read offline_access Files.Read`
- Only add `Files.ReadWrite` if/when implementing album creation or adding/removing items via the app.

### Code style

- Keep services behind protocols where it helps testability (`PhotosService`).
- Prefer concise errors and minimal UI state in views.

### Context

Always use context7 when I need code generation, setup or configuration steps, or
library/API documentation. This means you should automatically use the Context7 MCP
tools to resolve library id and get library docs without me having to explicitly ask.

Always use serena for code features which would benefit from LSP.
