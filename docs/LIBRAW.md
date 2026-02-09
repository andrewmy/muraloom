# LibRaw (RAW photo support) — dev + shipping notes

## Why you need a library for RAW (ARW/DNG/…)

Many camera RAW formats (ARW, DNG, CR2, NEF, …) are *not* reliably decodable/resizable with the macOS ImageIO thumbnail APIs. In practice this can lead to “solid color” fallback wallpapers or repeated decode errors when the album contains RAW files.

Muraloom’s wallpaper pipeline expects to write a **real JPEG** to disk before calling `NSWorkspace.setDesktopImageURL`. For RAW photos we need a reliable RAW → RGB → JPEG converter.

## Why LibRaw is the “least hassle” choice

There are big, capable image stacks (ImageMagick, libvips, etc.), but they tend to pull in many dependencies (multiple `.dylib`s), which makes macOS **signing + notarization + universal builds** much more painful.

LibRaw is relatively small, focused (camera RAW decode), and can be shipped as a **static library** so your app bundle contains fewer moving parts.

## What the app does when LibRaw is enabled

- Downloads the RAW bytes from Graph (`/content`).
- Uses LibRaw to decode/demosaic to an RGB bitmap.
- Downscales to the app’s recommended max display dimension.
- Encodes an opaque **JPEG** and caches it as a wallpaper candidate.

## Enable LibRaw locally (development)

1) Install LibRaw (example: Homebrew):
- `brew install libraw`

2) Create a local xcconfig (gitignored):
- Copy `Muraloom/LibRaw.xcconfig.example` → `Muraloom/LibRaw.xcconfig`
- Ensure `HEADER_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, and `OTHER_LDFLAGS` match your system.

3) Build and run.

If LibRaw isn’t enabled, the app will **exclude RAW items** from “usable photos”.

## GitHub Actions CI

The CI workflow on `macos-latest` installs LibRaw via Homebrew and generates a temporary `LibRaw.xcconfig` in the repo root (which is gitignored) so builds/tests run with RAW decoding enabled:

- Workflow: `.github/workflows/ci.yml`
- Step: “Install LibRaw (Homebrew)”

This is intended for **CI builds only**. For shipping, prefer static linking / an XCFramework to avoid bundling Homebrew `.dylib` dependencies inside the app.

## Shipping & notarization (first macOS app mental model)

### Why “it works on my Mac” often fails after you zip the app

If your app links against Homebrew-installed dynamic libraries, your build may run on your machine because those libraries exist in `/opt/homebrew/...`, but:
- Other users won’t have them.
- Notarization/codesigning expects all executable code inside the app bundle to be signed.

### Least-hassle shipping approach (recommended)

Ship LibRaw **statically** (or as a static `.xcframework`) and link it into the app binary:
- No extra `.dylib` files to embed.
- Fewer signing/notarization edge cases.

### If you ship a dynamic library anyway

You must:
- Embed the `.dylib`/`.framework` inside `Muraloom.app/Contents/Frameworks`.
- Ensure install names/rpaths are correct (so the app loads the embedded copy, not `/opt/homebrew/...`).
- Codesign the embedded libraries and the app with the same identity.

### Notarization at a glance

For a non–App Store distribution, the typical flow is:
- Sign the app (Developer ID) with hardened runtime.
- Submit for notarization.
- Staple the ticket to the app.

Xcode can do this for Archives. If you later automate it, the command-line tooling is `xcrun notarytool`.
