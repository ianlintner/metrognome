# Metrognome — Distribution Readiness Checklist

Tracks everything needed to ship to the App Store and Google Play. Items marked
**[done]** were implemented in the repo; **[you]** require your accounts,
hardware, or a console action that can't be automated from here.

---

## 1. Branding assets — [done]

Source of truth: `assets/branding/` (regenerate with
`Godot --headless --path . --script res://tools/make_icons.gd`).

- [done] Master icon `assets/branding/icon_1024.png` (full‑bleed, opaque, no rounded corners — the OS masks)
- [done] iOS icon set: `assets/branding/ios/icon_*.png` (40–1024) wired into the iOS preset
- [done] Android legacy icon `assets/branding/android/icon_192.png`
- [done] Android adaptive foreground/background (`adaptive_fg_432.png`, `adaptive_bg_432.png`)
- [done] Boot splash `assets/branding/splash_logo.png` + brand bg color (`project.godot`)
- [done] iOS launch storyboard images (`assets/branding/ios/launch_2x|3x.png`) + brand bg
- [ ] **[you]** Optional: Android adaptive **monochrome** icon (themed‑icon support) — left blank, not required

## 2. App configuration — [done]

- [done] Display name **"Metrognome"** (`config/name`; Android `package/name`)
- [done] Version **1.1.2**, iOS build **8**, Android versionCode **6**
- [done] iOS `targeted_device_family=3` (iPhone + iPad — was mis‑set to iPad‑only)
- [done] iOS `export_path` fixed (was pointing at an APK)
- [done] iOS min version 14.0; Android `min_sdk=24`, `target_sdk=35` (Play 2025 requirement)
- [done] Bundle/package ID kept as `com.codelintner.metrognomes` (matches the live Play listing — do NOT change)
- [done] **Follows device rotation** — `window/handheld/orientation=6` (Sensor: portrait + landscape, both ways). UI re-lays out on rotation.

## 3. Privacy & compliance — [done]

- [done] iOS privacy manifest: **no data collected** (correct — app is fully offline)
- [done] No runtime permissions; Android `permissions/internet=false`
- [done] Privacy policy drafted: `store/privacy-policy.md`
- [done] Privacy policy hosted at **https://cat-herding.net/metrognome/privacy** (portfolio site)

## 4. Signing — [you]

### Android (already working for v1.0.5)
- [done] Keystore + CI signing via `android.yml` (creds in Keychain + GitHub secrets — see `.remember`/memory)
- [done] `version/code=6`, `version/name=1.1.2`, `target_sdk=35`, native debug symbols (FULL) set for this release

### iOS (not yet configured — requires Apple Developer account)
- [ ] **[you]** Apple Developer Program membership ($99/yr)
- [ ] **[you]** Create an App ID for `com.codelintner.metrognomes` in the Apple Developer portal
- [ ] **[you]** Distribution certificate + App Store provisioning profile
- [ ] **[you]** Fill the iOS preset signing fields (Team ID, signing identity, provisioning profile) — left blank in `export_presets.cfg` intentionally (secrets)
- [ ] **[you]** Build the Xcode project (Godot iOS export emits an Xcode project), archive, and upload via Xcode or Transporter

## 5. Store listings — [you] (copy is drafted in `store/store-listing.md`)

- [ ] **[you]** App Store Connect: create the app record, paste name/subtitle/description/keywords
- [ ] **[you]** Play Console: the listing exists (v1.0.5) — refresh description, upload the new 512×512 icon (`assets/branding/android/icon_192.png` upscaled, or export the 512 from the master)
- [ ] **[you]** Data Safety (Play) / App Privacy (Apple): answer **"no data collected"** (see `store-listing.md`)
- [ ] **[you]** Age rating questionnaire → 4+ / Everyone

### Screenshots (capture from the running app)
- [ ] **[you]** iPhone 6.9" (1320×2868) — at least 1, up to 10
- [ ] **[you]** iPad 13" (2064×2752) — required because the build is Universal
- [ ] **[you]** Play phone screenshots — at least 2 (min 320px, max 3840px)
- [ ] **[you]** Play **feature graphic** 1024×500 (required) — can reuse the gradient + gnome
- [ ] **[you]** Optional 7"/10" tablet screenshots

## 6. Open product decisions

- **Orientation:** now **Sensor** (`orientation=6`) — the app follows device
  rotation in both portrait and landscape. Capture store screenshots in **both**
  orientations (or at least the primary one you expect players to use).

## 7. Build commands (reference)

```bash
# Regenerate all icons/splash from the gnome cutout
Godot --headless --path . --script res://tools/make_icons.gd

# Android AAB (signed via CI, or locally with keystore configured)
Godot --headless --path . --export-release "Android" build/android/metrognome.aab

# iOS — emits an Xcode project to build/ios/ ; open, archive, upload
Godot --headless --path . --export-release "iOS" build/ios/metrognome.ipa
```
