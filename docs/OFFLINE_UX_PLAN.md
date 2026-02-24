# Offline UX Plan (Lean)

## Summary
This plan defines a minimal offline behavior that avoids overengineering:
- Network-first when conditions are normal.
- Cached fallback when network/auth transport fails.
- No sign-out on offline-class failures.
- No continuous pinging/active connectivity probes.

## Definitions
- `readyCount`: number of valid cached wallpaper JPEGs currently usable for the selected album.
- `targetCount`: desired cache depth for background refill; initial fixed default `20`.
- `sync`: metadata-first refresh for the selected album (IDs/cTags/dimensions), then prefetch missing/stale images up to `targetCount`.

## Required UX Behavior
1. Change initiated (manual or timer) uses network-first in normal mode.
2. If network succeeds, choose from full album candidates and apply wallpaper.
3. If network fails with offline-class error, fallback to cached candidates.
4. If fallback succeeds, wallpaper changes and UI indicates cached/offline fallback.
5. If no cache exists, show actionable message (offline and no local photos).
6. Offline-class errors do not sign out the user.
7. Auth-required state is reserved for real auth-invalid conditions only.

## Error Handling Policy

### Offline-class (no sign-out)
Treat as offline fallback triggers:
- `URLError.notConnectedToInternet`
- `URLError.networkConnectionLost`
- `URLError.timedOut`
- DNS/host unreachable transport failures

Behavior:
- Keep auth/session state unchanged.
- Attempt cached fallback.
- Enter temporary offline cooldown.

### Auth-required (may require re-sign-in)
Only for explicit auth invalidation:
- refresh token rejected (`invalid_grant`)
- repeated Graph/token 401 invalid-token responses with working transport

Behavior:
- No silent sign-out loops.
- Surface explicit re-auth guidance.

## Cooldown Policy
After offline-class failure:
- Enter offline cooldown (initial default: 5 minutes).
- During cooldown, skip network/auth attempts and use cache-first.
- Manual `Retry online now` bypasses cooldown.
- Exit cooldown on first successful network request.

## Candidate Selection Rules
- On network success: pick next candidate from full album list with repeat-avoidance.
- On cache fallback: use cache list with same repeat-avoidance rules.
- If only one candidate exists, repeat is allowed.
- Never fail hard if a non-current cached candidate exists.

## Minimal Data/Type Additions
- Cache index persisted in Application Support:
  - `itemId`
  - `cTag`
  - `fileURL`
  - `lastUsedAt`
- Manager state additions:
  - `isUsingCachedFallback: Bool`
  - `cacheReadyCount: Int`
  - `cacheTargetCount: Int` (default 20)
  - `lastSyncAt: Date?`
  - `lastSyncError: String?` (optional)

## Implementation Steps
1. Reorder wallpaper update flow:
   - network-first in normal mode
   - cache fallback on offline-class failure
2. Add offline cooldown state and bypass logic.
3. Ensure cached fallback path does not call auth/token/network APIs.
4. Add lightweight cache index read/write and count computation.
5. Add status rows/messages in Settings and Menu Bar:
   - Source: Live / Cached fallback
   - Cache: `readyCount/targetCount`
   - Last sync time/error
6. Add manual `Retry online now` action.

## Test Plan

### Unit tests
1. Offline-class network failure with cache available:
   - change succeeds from cache
   - auth/token path is not invoked during fallback
2. Offline-class failure with empty cache:
   - change fails gracefully with actionable status
3. Network success path:
   - full-album candidate selection is used
4. Cooldown behavior:
   - subsequent attempts within cooldown skip network
   - manual retry bypasses cooldown
5. Auth-required errors:
   - do not classify as offline fallback

### UI tests
1. Simulated network failure + warm cache shows cached fallback status.
2. Simulated network failure + empty cache shows offline/no-cache guidance.
3. Retry online path transitions back to live mode when backend recovers.

## Acceptance Criteria
- App continues changing wallpaper offline when cache has usable items.
- Offline transport failures never force sign-out.
- Live network path avoids "always same wallpaper" when album has alternatives.
- UI clearly distinguishes live mode, cached fallback, and offline without cache.
- Behavior remains simple and maintainable (no continuous ping subsystem).
