# Instrument Tuner — Design Spec

**Date:** 2026-06-19
**Branch:** feature/time-of-day-tap-tempo (tuner work likely on its own branch)
**Status:** Approved design, ready for implementation plan

## Goal

Add a real-time instrument tuner as a second mode of the app, sharing the existing
3D forest + character ("gnome") scene. The tuner listens through the microphone,
detects the played pitch, and gives playful visual feedback: a UI cents bar/arrow
above the gnome, the gnome physically leaning + pointing the direction to tune, and
the whole scene desaturating to grayscale when off and regaining full color as you
dial in — with a celebratory pop at the moment you lock in.

## Decisions (locked during brainstorming)

1. **Tuner mode:** Hybrid — auto-detect the nearest note by default, with
   instrument **presets** that narrow the candidate notes, and an optional **lock**
   to a single target note ("selected note").
2. **Navigation:** Full mode swap — top segmented tabs **Metronome | Tuner**. Both
   modes share the one procedural scene (no separate `.tscn`).
3. **Gnome gesture:** Both **lean** (whole-body tilt) **and arm point**, with a
   **lean-only fallback** when a character rig has no identifiable arm bone.
4. **Color reward:** Continuous saturation **ramp** while searching **plus a
   celebration pop** at lock-in.

## Architecture

Everything stays in the existing single-scene, procedural-in-`_ready()` model.
`main.gd` remains the coordinator/wiring hub; the audio engine and UI never touch
each other directly.

### New / changed files

| File | Type | Responsibility |
|------|------|----------------|
| `pitch_detector.gd` | new | **Pure algorithm.** `detect(samples: PackedFloat32Array, sample_rate: float) -> Dictionary` returning `{ frequency, clarity }`. No engine/scene deps. Autocorrelation + parabolic interpolation + a clarity (peak-strength) score. |
| `tuner.gd` | new (`Node`) | Owns mic capture (`AudioStreamMicrophone` + `AudioEffectCapture` on a muted "MicCapture" bus). Accumulates a ~2048-sample mono window, calls `pitch_detector`, maps Hz → nearest candidate note + cents. Emits `pitch_detected(frequency, note_name, cents, clarity)` and `signal_lost`. Start/stop capture on demand. |
| `tuner_ui.gd` | new (`Control`) | The tuner overlay: large note label, cents bar with center in-tune zone + moving arrow/needle, frequency readout, instrument-preset selector, and a mic-permission prompt card. |
| `main.gd` | edit | Mode switch; drives `_env.adjustment_saturation`; gnome lean + arm point; celebration pop; creates/owns `tuner.gd` and relays its signals. |
| `ui_manager.gd` | edit | Adds top **Metronome \| Tuner** tab bar; shows/hides `tuner_ui`; emits `mode_changed(mode)`. Starts/stops tuner capture on tab switch. |
| `project.godot` | edit | `audio/driver/enable_input=true`. |
| `export_presets.cfg` | edit | Android `permissions/record_audio=true`; iOS `NSMicrophoneUsageDescription`. |

### Data flow (one direction)

```
mic → tuner.gd (capture) → pitch_detector.gd (Hz + clarity)
    → tuner.gd (Hz→note/cents) → signal → main.gd (coordinator)
        ├→ tuner_ui.gd   (note label, cents arrow, frequency)
        └→ scene         (saturation lerp, gnome lean+arm, celebrate)
```

## Audio capture & pitch detection

### Capture chain (created on entering tuner mode, torn down on exit)

1. `project.godot`: `audio/driver/enable_input=true`.
2. Audio bus **"MicCapture"**, output **muted** (no speaker echo / feedback), with an
   `AudioEffectCapture` effect.
3. `AudioStreamPlayer` with `stream = AudioStreamMicrophone.new()`, `bus =
   "MicCapture"`, `.play()`.
4. `tuner.gd._process` (gated on tuner mode active): pull frames via
   `AudioEffectCapture.get_buffer()`, average L/R → mono, accumulate into a ~2048
   sample window, run detection when the window is full.

The bus + player are created lazily on first tuner entry and the mic stream is
**stopped on exit** so the app does not hold the mic in metronome mode.

### Detection (`pitch_detector.gd`)

- Autocorrelation over the window with parabolic interpolation of the peak.
- **Clarity score** (normalized peak strength). Below a threshold → report no signal,
  so background noise/silence doesn't make the gnome and color jitter.
- Hz → note (MIDI): `note = round(12 * log2(f / 440)) + 69`.
- Cents off: `1200 * log2(f / nearest_candidate_f)`.
- Clean interface so the algorithm can later be swapped for MPM/NSDF without touching
  callers.

### Instrument presets (hybrid model)

A preset is a **set of candidate notes**; detection snaps to the nearest candidate.

- **Chromatic** — all 12 notes (pure auto-detect).
- **Guitar** EADGBE, **Bass** EADG, **Ukulele** GCEA, **Violin** GDAE.
- Optional **lock**: tap a string in the preset to restrict to that single note.

### Permissions & platform fallback

- **Android:** `permissions/record_audio=true`; request at runtime via
  `OS.request_permissions()` on first tuner entry.
- **iOS:** `NSMicrophoneUsageDescription` in the iOS export preset.
- **Denied / no mic / web-without-mic:** `tuner_ui` shows a friendly "enable mic
  access" card instead of the meter; the tab still works, nothing crashes, and the
  metronome mode is unaffected.

## Visual behavior

### Saturation ramp (`main.gd`, tuner mode + confident pitch only)

- Map `abs(cents)` → target saturation: `>= 50` cents → `0.0` (grayscale);
  `0` cents → `1.15` (the project's existing normal value). Smooth curve between,
  `lerp`ed per-frame for a glide, not a snap.
- No confident pitch → ease back toward gray.
- **Metronome mode:** saturation pinned at `1.15` (unchanged from today). The
  time-of-day system never touches `adjustment_saturation`, so there is no conflict.

### Gnome reaction (lean + arm, with fallback)

- **Lean:** rotate the gnome node on Z — tilt toward the "flat" side when flat, "sharp"
  side when sharp, upright when in tune; magnitude scales with `cents`. Pure node
  rotation, robust on every rig.
- **Arm point:** procedurally rotate one shoulder/upper-arm bone so the hand rises
  toward the correction direction. On `_load_active_character`, probe the skeleton for
  a likely arm bone by name (`arm` / `shoulder` / `clavicle`). Found → lean + arm;
  **not found → lean only** (graceful degradation, never errors).
- **Direction convention:** too **sharp** → point **down / toward flat** ("bring it
  down"); too **flat** → point **up** ("raise it"). The UI arrow matches.

### Celebration at lock-in (entering the in-tune window, <= ~5 cents)

- Brief saturation **over-shoot bloom** (pop above 1.15, then settle).
- A small one-shot particle **sparkle** near the gnome, reusing the existing
  `GPUParticles3D` firefly approach.
- Fires **once per lock**, re-arms only after drifting back out of tune (no spam).

## UI & navigation

- Top **Metronome | Tuner** segmented tabs, added to `ui_manager`'s existing top
  `_bar`. Switching tabs starts/stops mic capture.
- Tuner overlay, bottom-anchored like the metronome controls: large **note name**
  (e.g. "A2"), a horizontal **cents bar** with a center in-tune zone and a moving
  **arrow/needle**, a **frequency readout** (e.g. "110.4 Hz"), and the **instrument
  preset** selector.
- Follows the existing full-screen-overlay patterns (tap-tempo overlay, help modal).

## Testing approach

- **`pitch_detector.gd`** — the high-value, deterministic unit. Generate synthetic
  sine buffers at known frequencies (e.g. 110 Hz A2, 440 Hz A4, plus a couple of
  detuned cases) and assert detected Hz within tolerance and clarity above threshold;
  assert low clarity on white-noise/silence buffers. Runnable headless.
- **Parse/validate gate:** `godot --headless --quit --path .` after each change (the
  repo's standard check; CI runs the same).
- **Manual / device:** mic permission flow on Android + iOS; verify capture
  start/stop on tab switch; visual check of saturation ramp, gnome lean/arm, and the
  lock-in celebration. Web build: confirm the graceful "enable mic" fallback.

## Out of scope (YAGNI)

- MPM/NSDF detector upgrade (interface leaves room; not needed for v1).
- Microtonal / alternate temperaments; transposition.
- Recording, history, or strobe-style displays.
- A separate tuner scene or duplicated forest.

## Risks / open implementation notes

- Autocorrelation can octave-error on rich timbres; the clarity gate + preset
  candidate-snapping mitigate this for v1.
- Arm-bone probing is heuristic; lean-only fallback guarantees correctness.
- Web mic capture is environment-dependent; the fallback card covers it.
