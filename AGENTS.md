## Repo guidance (Codex / contributors)

### Product direction

- Target integration is **OneDrive** (Microsoft Graph) for **personal Microsoft accounts**.
- Source of truth for roadmap/decisions: `docs/PROJECT_PLAN.md`.
- Locked-in direction:
  - Auth: **MSAL**
  - Wallpaper source: **OneDrive Albums** (Graph bundle albums), not folders

### Builds

- CLI build:
  - `xcodebuild -scheme Muraloom -destination 'platform=macOS' -derivedDataPath /tmp/muraloom_deriveddata build`
- Unit tests (local):
  - `just test`
- Coverage gate (local, same as CI):
  - `just coverage` (or `just coverage-report` for a report without enforcing a minimum).
- UI tests (local, hermetic):
  - `just ui-test`
- If CLI builds fail with signing/keychain errors but Xcode builds work:
  - Ensure Xcode is signed into your Apple ID and the target has a Team + “Automatically manage signing”.
  - Some sandboxed/automation environments may need elevated permissions to access signing certificates.
  - For a “compile-only” sanity check in CI, you can use `CODE_SIGNING_ALLOWED=NO` (won’t produce a runnable signed app).

### UI tests (hermetic / non-flaky)

- UI tests run the app in a fixture mode (no interactive MSAL sign-in, no Microsoft Graph calls) by launching with `-ui-testing` + `MURALOOM_UI_TESTING=1`.
- Configure fixture behavior via `MURALOOM_UI_TEST_PHOTOS_MODE` (e.g. `listAlbumsFailOnce` to simulate a reload error that recovers on retry).
- Prefer in-app harnesses over system UI automation when needed:
  - Menu bar actions are exercised via an in-window “Menu Bar (UI testing)” harness shown under Advanced in UI testing mode (system status bar UI is flaky/unreliable in XCUITest).
- Avoid tests that change global macOS state (e.g. appearance/theme). Xcode can prompt to run UI tests under multiple UI configurations; that can leave the system in Dark/Light if interrupted.
- Expect Xcode UI tests to sometimes prompt “Remove Other Apps” (it’s Xcode/XCUITest trying to improve reliability by closing other apps).

### Current implementation status

- Present today (working): **MSAL** auth + **album-based** Graph fetching (bundle albums via `/drive/bundles`).
- Notes:
  - For some personal accounts, `$filter=bundle/album ne null` can return 0 even when albums exist in OneDrive Photos.
  - The app treats `photos.onedrive.com` bundle URLs as albums (and uses `bundle.album` when available).
  - Practical Graph quirks:
    - Selecting `@microsoft.graph.downloadUrl` via `$select` can fail with HTTP 400 (“AnnotationSegment”); prefer downloading with `GET /me/drive/items/{item-id}/content`.
    - For `children(...)` inside `$expand`, Graph supports only `$select`/`$expand` (using `$top` can 400).
    - For bundle albums, `GET /me/drive/items/{id}/children` can be unreliable; prefer `GET /me/drive/items/{id}?$expand=children(...)` + `children@odata.nextLink` paging.
  - UI:
    - When signed in, albums auto-load on startup so the picker appears without manual reload.
    - Manual album ID + full scan live behind “Advanced”.

### Config & scopes (today)

- `Info.plist` keys used by the current MSAL path:
  - `OneDriveClientId`, `OneDriveRedirectUri`, `OneDriveScopes`
- Default read-only scope set for wallpaper fetching:
  - `User.Read Files.Read` (MSAL handles reserved OIDC scopes like `openid`, `profile`, `offline_access`)
- Only add `Files.ReadWrite` if/when implementing album creation or adding/removing items via the app.
- MSAL token cache entitlement (macOS): ensure `keychain-access-groups` includes `$(AppIdentifierPrefix)com.microsoft.identity.universalstorage` (or you may hit OSStatus `-34018`).

### Code style

- Keep services behind protocols where it helps testability (`PhotosService`).
- Avoid sprinkling `AppEnvironment.isUITesting` across the codebase; keep UI-test branching in the composition root and inject fixture implementations instead.
- Prefer concise errors and minimal UI state in views.
- When making behavioral changes, **add or update unit tests** to cover them whenever practical.

### Persistence (UserDefaults)

- Store **stable, machine-readable values** in `UserDefaults` (e.g. enum raw values like `hourly`, not user-facing strings like “Every Hour”).
- Keep user-facing labels separate (e.g. `displayName`) so they can change/localize without breaking stored settings.
- When loading settings, avoid writing back to `UserDefaults` during initialization/rehydration (guard with an `isLoadingFromDisk` flag or similar) to prevent accidentally removing keys.
- Don’t add migrations unless explicitly needed; prefer “clean slate” assumptions for new schema decisions unless the product explicitly requires preserving legacy installs.

### Menu Bar UX (MVP)

- The app is a normal Dock app; the menu bar icon is supplemental for quick actions and status.
- The settings window is the main `WindowGroup` and is opened/foregrounded via `openWindow(id: "settings")`.
- Ensure the app keeps running after closing the settings window (menu bar icon must remain usable).
- For interactive sign-in launched from the menu bar, open/activate the settings window first so MSAL has a presentation context.
- “Pause” means pause **scheduled/timer-driven** changes only (manual “Change Now” still works).

### Context

Always use context7 when I need code generation, setup or configuration steps, or
library/API documentation. This means you should automatically use the Context7 MCP
tools to resolve library id and get library docs without me having to explicitly ask.

Always use serena for code features which would benefit from LSP.
