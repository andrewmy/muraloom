# GPhotoPaper User Stories

This document outlines the user stories for the application, categorized into MVP (Minimum Viable Product) and Post-MVP features.

Source of truth for technical implementation details and sequencing is `ONEDRIVE_PLAN.md` (MSAL auth + OneDrive Albums / Graph bundles).

## MVP User Stories

These stories represent the core functionality required for the initial release.

*   **As a user, I want to securely connect my OneDrive account (MSAL)** so the app can access my photos.
*   **As a user, I want to see a list of my OneDrive albums** so I can pick a source for wallpapers.
*   **As a user, I want to select an album and have the selection remembered** so I don’t need to reconfigure it every time.
*   **As a user, I want the app to validate my selected album on startup** so I can quickly fix issues if the album was deleted or permissions changed.
*   **As a user, I want to see a clear warning when my selected album has no photos** so I understand why wallpapers aren’t changing.
*   **As a user, I want the app to set my desktop wallpaper to a photo from my selected OneDrive album.**
*   **As a user, I want the wallpaper to change automatically at a configurable interval** so I can enjoy a fresh view without manual effort.
*   **As a user, I want to be able to manually trigger a wallpaper change** so I can get a new photo on demand.
*   **As a user, I want basic photo filtering (minimum width, horizontal only)** so low-quality or poorly fitting photos are skipped.
*   **As a user, I want a menu bar icon for quick controls and status** so I can change/pause wallpapers and see sign-in/errors without opening the main window.
*   **As a user, I want a normal settings window** so configuration (sign-in, album selection, filters, schedule) is easy to discover and edit.
*   **As a user, I want a quick link to open my selected album in OneDrive** so I can curate it.

### MVP scope notes (locked in)

*   Read-only access: start with `User.Read Files.Read` (no `Files.ReadWrite` in MVP).

## Post-MVP / Nice-to-Have Stories

These are features that would add significant value but are not essential for the initial launch.

*   **Multiple Monitor Support:** As a user with multiple monitors, I want to configure how wallpapers are displayed across my screens (e.g., the same image on all, or a different image on each).
*   **Launch at Login:** As a user, I want the app to launch at login so it’s always running without manual startup.
*   **Offline Cache:** As a user, I want the application to cache a number of photos locally so it can continue to change wallpapers even when I'm offline.
*   **Photo History:** As a user, I want to see a history of recently used wallpapers and be able to revert to a previous one I liked.
*   **Advanced Scheduling:** As a user, I want more advanced scheduling options for wallpaper changes (e.g., change every hour, change on wake from sleep).
*   **Display Photo Info:** As a user, I want to easily see the filename or details of the currently displayed wallpaper.
*   **Multi-Account Support:** As a user, I want to be able to authorize and switch between multiple OneDrive accounts.
*   **Album Creation (Write Scopes):** As a user, I want to create an album from within the app to quickly start curating a wallpaper set (requires `Files.ReadWrite`).
*   **Album Management (Write Scopes):** As a user, I want to add/remove photos in my wallpaper album from within the app (requires `Files.ReadWrite`).

## Roadmap mapping

This document describes user-facing outcomes. For implementation details, see `ONEDRIVE_PLAN.md`.

*   **MVP stories** map primarily to:
    - Phase 2 — Albums API (Graph bundles)
    - Phase 3 — UI update (albums instead of folders)
*   **Post-MVP stories** map primarily to:
    - Phase 4 — Testing & hardening
    - Follow-on phases not yet written (menu-bar UX polish, caching/history, launch-at-login, multi-monitor).
