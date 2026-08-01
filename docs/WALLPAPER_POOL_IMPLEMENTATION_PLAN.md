# Muraloom Wallpaper Pool Implementation Plan

This document defines the concrete engineering plan for moving Muraloom from the current single-OneDrive-album model to a provider-aware wallpaper pool, with `Photos on This Mac` as the first additional source.

It complements `docs/WALLPAPER_POOL_UX_SPEC.md` and `docs/PROJECT_PLAN.md`. This document is intended to be execution-ready and to serve as the handoff spec for implementation.

## 1. Goals

- Combine multiple sources into one wallpaper rotation pool.
- Keep the settings UI as a single page with sections.
- Use sheets for add/edit source subflows.
- Support both OneDrive and local Photos cleanly.
- Keep architecture open to multiple sources per provider.
- Enforce the v1 UX policy:
  - one OneDrive source max
  - multiple local Photos sources allowed

## 2. Product decisions

The following decisions are locked in for the first implementation pass:

- Pool selection weighting is per photo.
- The local Photos picker includes user albums plus a limited smart-album set.
- Migration strategy is fresh start.
- The architecture supports many entries per provider.
- The UX limits cloud providers to one source each in v1.
- No tabs in the main settings window.
- No merged-photo gallery in the main window.
- No source weighting UI in v1.
- No drag-reorder in v1.

## 3. New persisted model

Add the following new types:

### `WallpaperSourceProvider`

- `oneDrive`
- `photosOnMac`

### `WallpaperSourceKind`

- `oneDriveAlbum`
- `photosAlbum`
- `photosSmartAlbum`

### `WallpaperSourceRecord`

Fields:

- `id: UUID`
- `provider`
- `kind`
- `collectionIdentifier`
- `displayName`
- `subtitle`
- `isEnabled`
- `sortOrder`
- `deepLinkURLString`
- `createdAt`

Persistence rules:

- `SettingsModel` adds `poolSources: [WallpaperSourceRecord]`.
- `poolSources` is stored as JSON in `UserDefaults`.
- `settingsSchemaVersion = 2`.
- Legacy single-album keys are no longer active app state.

## 4. Migration behavior

Migration to the pool model is intentionally a fresh start.

If the stored schema version is older than `2`:

- preserve shared wallpaper settings:
  - frequency
  - paused state
  - fill mode
  - random
  - minimum width
  - horizontal-only
- clear legacy OneDrive source selection
- clear prior selected-item tracking state
- initialize `poolSources = []`
- write schema version `2` immediately

The post-migration UI should land in an empty-pool state, with no attempt to infer or recreate the old OneDrive album selection.

## 5. Provider-aware service layer

Replace the current single-album service shape with a provider-aware abstraction.

Add shared models:

- `SourceCollectionSummary`
- `SourceScanResult`
- `SourceAvailability`

Add protocol:

- `WallpaperSourceLibrary`
  - provider availability
  - request access if needed
  - list collections
  - verify a saved collection
  - scan a configured source
  - sample preview items
  - download image data

Define these implementations:

- `OneDriveSourceLibrary`
- `PhotosOnMacSourceLibrary`
- `CombinedWallpaperSourceLibrary`

`AuthService` remains OneDrive-specific for now. The app does not need a generalized multi-provider auth layer in this pass.

## 6. `MediaItem` changes

`MediaItem` becomes source-aware.

Add fields:

- `sourceRecordId`
- `sourceProvider`
- `providerItemIdentifier`

Global ID rule:

- `MediaItem.id` must be globally unique across providers and sources.
- Compose it from provider + source record + provider item id.

This is required to:

- avoid cache collisions
- preserve repeat avoidance across the pool
- make merged-pool selection deterministic

## 7. `Photos on This Mac` provider

Implement the first local provider using PhotoKit.

### Privacy and entitlement work

- Add `NSPhotoLibraryUsageDescription` to `Info.plist`.
- Add `com.apple.security.personal-information.photos-library` to entitlements.

### Authorization behavior

- Request access only during add/edit source flows.
- Never prompt at launch.
- Map PhotoKit authorization state into provider availability.

### Picker scope

The local picker includes:

- user albums
- smart albums:
  - `Library`
  - `Favorites`
  - `Recents`

The broader smart/system surface is excluded in v1.

### Asset behavior

- Image assets only.
- Use PhotoKit metadata for dimensions.
- Load original data for wallpaper application.
- Use `PHCachingImageManager` for preview-strip thumbnails.
- Use a lightweight library-change observer to refresh local-source metadata.

## 8. OneDrive provider adaptation

Reuse the existing OneDrive album behavior, but wrap it inside the provider-aware abstraction.

Required behavior:

- current album listing and Graph scan logic remain
- current auth flow remains
- current deep link to OneDrive can remain on the source record
- the UI must block adding a second OneDrive source, even though the model allows it

This keeps the OneDrive integration stable while letting the rest of the app move to a pool model.

## 9. Wallpaper manager refactor

`WallpaperManager` moves from single-album logic to pool logic.

Required behavior:

- schedule when at least one enabled source exists
- do not require OneDrive sign-in if the pool contains a local source
- scan enabled sources concurrently
- flatten eligible items into one merged list
- preserve source order by `sortOrder`
- random mode shuffles the merged list
- sequential mode walks the merged list deterministically using `lastPickedIndex`
- allow one failed source without failing the whole update
- use cached fallback across the whole pool, not per source

Per-source counts and errors should be surfaced to a UI model rather than stored in `SettingsModel`.

## 10. Runtime UI model

Add a new observable object such as `WallpaperPoolModel`.

Responsibilities:

- manage source-card runtime state
- load previews and counts
- expose source row status text
- enforce UI source-count rules
- drive add/edit source sheets
- compute pool summary values

This model owns transient source status and preview state. `SettingsModel` remains the persistence model and should not absorb runtime-only UI state.

## 11. Settings UI plan

The settings UI remains a single page with these sections:

1. `Wallpaper Pool`
2. `Rotation`
3. `Sources in Pool`
4. `Status`
5. `Advanced`

### Source-card layout

Each source card shows:

- provider icon
- source name
- metadata line
- overflow menu
- fixed four-slot preview strip
- final slot becomes a faded `+N` tile when needed

### Main actions

- `Add Source`
- `Change Wallpaper Now`
- `Pause/Resume Automatic Changes`

The main page no longer contains inline OneDrive album loading/picking controls.

## 12. Sheet flows

Document and implement two sheet-based source-management flows.

### `Add Source` sheet

- choose provider
- run provider-specific access/auth flow
- choose collection
- confirm with `Add to Pool`

### `Edit Source` sheet

- show provider-specific source info
- allow replacing the selected collection
- allow re-auth/re-grant access
- allow removal
- keep OneDrive manual album-ID fallback behind an `Advanced` disclosure here only

## 13. Menu bar changes

The menu bar becomes pool-oriented rather than album-oriented.

Show:

- pool source count
- available source count
- current wallpaper
- next change
- activity
- cache
- last changed

Keep actions:

- `Change Wallpaper Now`
- `Pause/Resume Automatic Changes`
- `Open Settings…`

Remove:

- `Open Selected Album` as a generic top-level assumption

Local Photos permission management stays in settings sheets, not the menu bar.

## 14. Composition root changes

Update app setup to:

- build the OneDrive provider
- build the local Photos provider
- build the combined source library
- build the pool runtime model
- inject them into settings and menu bar
- update startup scheduling rules to depend on pool state, not just OneDrive sign-in

## 15. Testing plan

### Unit tests

Add or update tests for:

- `SettingsModel` pool persistence and migration
- merged-pool scheduling logic
- pool candidate selection behavior
- local Photos provider behavior
- combined source library delegation
- mixed-source failure tolerance

### UI tests

Add or update tests for:

- empty-pool state
- add OneDrive source
- add local Photos source
- add multiple local Photos sources
- block second OneDrive source
- local-only pool enables wallpaper changes
- source-card `+N` preview behavior
- pool-level menu bar wording

## 16. Implementation order

Use this exact order:

1. new persisted pool model and schema migration
2. provider-aware shared interfaces and `MediaItem` changes
3. adapt OneDrive into provider abstraction
4. implement PhotoKit local provider
5. refactor `WallpaperManager` to merged-pool logic
6. add runtime UI model
7. rebuild settings page and source cards
8. add source-management sheets
9. update menu bar
10. update tests and fixtures
11. run `just test`
12. run `just ui-test`

## Important assumptions

- OneDrive remains single-account in v1.
- PhotoKit is the only supported implementation for `Photos on This Mac`.
- Local previews use memory cache only in v1.
- Source ordering is append order in v1.
- Source weighting UI is out of scope.
- Cloud providers are UX-limited to one source each in v1, but not architecturally limited.
- Multiple local Photos sources are allowed in v1.
