# Tuner v2 — MPM detection upgrade + UI polish (v1.4.0)

Date: 2026-08-07
Status: approved (autonomous session — decisions documented here for review)

## Goal

Make the shipped tuner (v1.3.0) "a little better" along three axes, informed by how
established open-source tuners work (TarsosDSP, sevagh/pitch-detection, Beethoven,
pitchfinder):

1. **Accuracy/robustness** — the current detector normalizes autocorrelation by the
   *left* window's energy only. On decaying signals (every plucked string) the two
   windows have unequal energy, which skews correlation values and the threshold
   logic. Peak-picking ("first local max above `max(0.5, 0.85·global)`") can grab a
   shoulder ripple and mis-report a higher frequency.
2. **Performance** — time-domain correlation over 2048 samples × ~850 lags is ~1.4M
   GDScript loop iterations every 0.12 s. Fine on desktop, a frame-hitch risk on
   phones — and this release targets App Store / Google Play.
3. **UI clarity** — the meter has no scale, no flat/sharp direction cue, and a
   binary needle color.

## Approaches considered

- **A. YIN (CMNDF)** — full algorithm swap; inverts clarity semantics (minima),
  invalidates existing thresholds/tests wholesale. More change than needed.
- **B. MPM/NSDF upgrade of the existing detector (chosen)** — keeps the current
  code shape (correlation array → peak pick → parabolic interpolation) while fixing
  both known weaknesses. This is the method most professional OSS tuners use.
- **C. FFT-based detector** — biggest speedup but requires writing an FFT in
  GDScript; risk unjustified for this scope.

## Design

### pitch_detector.gd

- **NSDF normalization**: `n(τ) = 2·Σ x[i]·x[i+τ] / Σ (x[i]² + x[i+τ]²)`,
  bounded in [-1, 1] regardless of amplitude decay. The denominator is O(1) per lag
  via a prefix-sum of squares.
- **MPM key-maxima peak picking**: scan lags from 1; after the first negative-going
  zero crossing of the NSDF, record one maximum per positive region (between
  positive-going and negative-going crossings). Threshold `k·max(key maxima)` with
  `k = 0.9`; pick the *first* key maximum above it (shortest period ⇒ avoids
  octave-down), only accepting lags in the valid frequency band.
- **Clarity = the chosen peak's NSDF value** (not the global max) — a genuine
  confidence measure; noise stays well below the 0.6 gate in tuner.gd.
- **Two-stage search**: coarse pass on a 4× average-pooled copy (512 samples,
  sr/4), then re-run NSDF at full rate only for lags within ±6 of `4·coarse_lag`
  and parabolically interpolate. ~120K loop iterations vs ~1.4M (≈11× less CPU)
  with full-rate cents precision.
- Public API unchanged: `detect(samples, sr) -> {frequency, clarity}`.

### tuner.gd / pitch_smoother.gd

- `DETECT_INTERVAL` 0.12 → 0.08 s (affordable now; snappier readings).
- `EMA_ALPHA` 0.40 → 0.29 to preserve the same ~235 ms smoothing time constant at
  the faster push rate. `MEDIAN_WINDOW`/`COMMIT_FRAMES` unchanged (same frame
  counts ⇒ same outlier rejection, faster wall clock).

### tuner_ui.gd

- Cents-bar scale: minor ticks every 10¢, labeled ticks at −50/−25/0/+25/+50.
- ♭ / ♯ indicators flanking the note letter; the relevant side brightens when
  flat/sharp beyond the in-tune zone. (Glyph rendering verified by screenshot;
  ASCII fallback "b"/"#" if the default font lacks U+266D/U+266F.)
- Needle color blends orange → green as |cents| approaches the in-tune zone.
- Frequency line adds the committed note's target: `220.4 Hz → 220.0 Hz  +3¢`.
- Panel size/layout logic untouched (recently stabilized).

### Out of scope

Alternate temperaments, adjustable A4 calibration, transposing instruments,
strobe display. All possible later; YAGNI now.

## Testing

- Extend `tests/test_pitch_detector.gd`: guitar/violin open strings
  (82.41–659.26 Hz) within 0.3 % (~5¢), a decaying harmonic-rich tone (sawtooth
  partials, exponential envelope) within 0.5 %, noise clarity < 0.6, silence.
- `tests/test_pitch_smoother.gd`, `tests/test_tuner_notes.gd` must keep passing.
- Headless parse check, live run + debug output, screenshot review of the UI.

## Release (v1.4.0)

- `project.godot` config/version 1.4.0; Android `version/code` 11,
  `version/name` 1.4.0; iOS `short_version` 1.4.0, build `12`.
- Store listing "what's new" + release checklist refreshed.
