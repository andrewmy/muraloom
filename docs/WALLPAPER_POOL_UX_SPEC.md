# Muraloom Wallpaper Pool UX Spec

This document defines the proposed UX for supporting multiple wallpaper sources in a single rotation pool.

It complements `docs/PROJECT_PLAN.md`. If implementation sequencing changes, `docs/PROJECT_PLAN.md` remains the roadmap source of truth.

## Goals

- Let users combine photos from multiple sources into one wallpaper rotation pool.
- Keep the main settings window simple even as providers are added.
- Support both cloud-backed and local sources without forcing them into the same wording.
- Preserve the app's utility-first character instead of turning it into a media browser.

## Product framing

The user-facing concept is a **Wallpaper Pool**.

- A pool contains one or more sources.
- Each source contributes usable photos to the same rotation pool.
- The app rotates over the merged pool without requiring the user to think about provider-specific rules.

Preferred terminology:

- `Wallpaper Pool`
- `Source`
- `Sources in Pool`
- `Usable photos`
- `Add Source`

Avoid in the main UI:

- `Active provider`
- `Current provider`
- `Collection set`
- `Source` as a synonym for cache/live/offline state

## Core decisions

### Main window structure

Use a **single page with sections**, not tabs.

Reasons:

- The app still performs one job: configure and run the wallpaper pool.
- Tabs would hide state and create mode switching for a relatively small surface area.
- A single scrolling page is easier to understand and closer to the current app model.

Recommended section order:

1. `Wallpaper Pool`
2. `Rotation`
3. `Sources in Pool`
4. `Status`
5. `Advanced` (collapsed by default)

### Branching flows

Use **sheets** for temporary, focused subtasks.

Sheets are appropriate for:

- `Add Source`
- `Edit Source`
- provider sign-in / permission flows
- provider-specific source pickers

Do not use sheets for:

- quick enable/disable actions
- refresh actions
- small confirmations
- advanced toggles

### Pool model

The pool is the top-level object exposed to the user.

- Multiple sources may be active at once.
- All enabled sources contribute equally in v1.
- The pool continues working when one source is unavailable, as long as at least one other source is usable.

Out of scope for the first version of this UX:

- source weighting
- cross-source deduplication UI
- a giant mixed-photo browser for the full merged pool
- per-source rotation rules

## Layout spec

### Section 1: Wallpaper Pool

Purpose: summarize the current pool and expose primary actions.

Content:

- Section title: `Wallpaper Pool`
- Summary line: `{N} sources • {M} usable photos`
- Primary actions:
  - `Add Source`
  - `Change Wallpaper Now`
  - `Pause Automatic Changes` or `Resume Automatic Changes`

Optional status text:

- `2 of 3 sources available`
- `Refreshing sources...`

The pool summary should not require the user to understand which provider is currently "active." The pool is the active unit.

### Section 2: Rotation

Purpose: keep all shared wallpaper behavior controls together.

Content:

- `Change Frequency`
- `Fill Mode`
- `Pick Randomly`
- `Only Horizontal Photos`
- `Minimum Picture Width`

These controls apply to the pool as a whole, not to individual sources.

### Section 3: Sources in Pool

Purpose: visually represent the inputs that feed the pool.

This is the key section to borrow from macOS Wallpaper settings.

Borrow from macOS:

- card/list treatment
- visual preview of each source
- obvious "these items belong to the same set" presentation

Do not copy literally:

- full System Settings visual hierarchy
- large browsing-oriented galleries
- Apple-style ambiguity around state and controls

Recommended presentation:

- one row or card per source
- compact metadata
- a short thumbnail strip
- trailing source actions menu

Each source card should show:

- provider icon and provider name
- selected source name
  - examples: album name, folder path, local library album
- usable photo count
- freshness / availability text
- thumbnail strip
- overflow menu with source-specific actions

Example metadata strings:

- `184 usable photos • Synced just now`
- `126 usable photos • Local`
- `118 usable photos • Last refreshed 2h ago`
- `Unavailable • Sign in to refresh`

Suggested overflow menu actions:

- `Edit Source...`
- `Refresh`
- `Disable`
- `Remove from Pool`

### Thumbnail strip behavior

Each source card includes a fixed-width thumbnail strip.

Rules:

- show up to 4 visual slots
- never expand the strip to show more than 4 slots
- if more photos exist, the last slot becomes a faded overlay card with a count label
- use a label like `+123`, not bare `...`

Rationale:

- fixed height and width per card
- better information scent than `...`
- no temptation to turn the settings page into a gallery browser

Examples:

- exactly 1-3 photos available: show available thumbnails, preserve strip layout
- exactly 4 photos available: show 4 thumbnails
- more than 4 photos available: show 3 thumbnails and a final faded `+N` tile, or 4 thumbnails with the final tile overlayed by `+N`

Loading / unavailable states:

- preserve layout with placeholders
- do not collapse the card when thumbnails are missing
- dim unavailable sources rather than removing them from the list

## Source types

The UI must support both cloud and local sources without pretending they behave the same.

### Cloud source language

Cloud sources may show:

- sign-in state
- refresh/sync time
- connectivity/auth problems

Examples:

- `Signed in`
- `Synced just now`
- `Needs sign-in`

### Local source language

Local sources should emphasize immediacy and privacy, not sync.

Local sources may show:

- library permission state
- selected album
- local availability

Examples:

- `Access granted`
- `Local`
- `Photos library access required`

Avoid cloud-centric words for local sources:

- `sync`
- `source: live`
- `downloaded`

## Naming changes from the current UI

Rename current or likely labels as follows:

- `OneDrive Album` -> `Wallpaper Pool` or provider-specific setup text inside a sheet
- `Album` -> source-specific name inside a source card, not a top-level settings row
- `Load Albums` -> inside provider sheet only
- `Open in OneDrive` -> `Open Source Collection`
- status `Source: Live` -> `Mode: Live` or `Connection: Live`

The main settings page should stop treating a single album as the app's central object.

## Add Source flow

`Add Source` opens a sheet attached to the settings window.

Step 1: choose source type

Options may include:

- `OneDrive Albums`
- `Dropbox Folder`
- `Photos on This Mac`

Step 2: provider-specific setup

Examples:

- cloud provider: sign in, then choose album/folder
- local provider: request library permission, then choose album

Step 3: confirmation

- show selected source name
- show estimated usable photo count when available
- primary button: `Add to Pool`

After completion:

- close the sheet
- insert the new source card into `Sources in Pool`
- update the pool summary immediately

## Edit Source flow

`Edit Source...` opens a sheet attached to the same settings window.

Expected actions:

- change the selected album/folder
- re-authenticate if needed
- review source-specific status
- remove the source from the pool

Edits should not navigate the main window away from pool settings.

## Menu bar implications

The menu bar should describe the pool, not pretend a single source is special.

Recommended status presentation:

- `Wallpaper Pool: 3 sources`
- `Current: <filename>`
- `Next change: <time>`
- `2 of 3 sources available`

Quick actions:

- `Change Wallpaper Now`
- `Pause Automatic Changes`
- `Open Settings...`

Optional provider/source actions:

- `Refresh Sources`
- `Open Current Source Collection`

Avoid a menu structure that makes source switching feel like the primary job of the app.

## Interaction principles

- The pool is the main unit of configuration.
- Source management must feel additive, not mode-switching.
- The settings page should remain operational and compact.
- Visual previews should build trust, not invite browsing.
- Reliability messaging matters more than visual richness.

## Inspiration from macOS Wallpaper settings

Take inspiration from macOS Wallpaper settings at the interaction-model level, not as a visual clone.

Use:

- familiar card/list organization
- thumbnail-driven confidence
- strong grouping around one conceptual set

Avoid:

- turning Muraloom into a mini System Settings replica
- giant wallpaper browsing grids
- over-abstracted labels that hide operational state

Target balance:

- familiar enough to feel native
- explicit enough to remain trustworthy as a utility app

## Non-goals

- No tabs in the main settings window.
- No full merged-pool photo browser in the main window.
- No source weighting UI in v1.
- No cross-source deduplication UI in v1.
- No requirement for all configured sources to be healthy before rotation can continue.

## Open implementation questions

- Should the source card use a row layout or a larger card layout at narrow window widths?
- Should unavailable sources remain enabled by default or auto-disable after repeated failures?
- Should the overflow menu include `Open Source Collection` for all providers or only those with a meaningful deep link?
- Should the pool summary show total usable photos only, or also a per-source healthy/unhealthy count?
