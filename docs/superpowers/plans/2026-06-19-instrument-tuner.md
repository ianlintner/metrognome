# Instrument Tuner Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a microphone-driven instrument tuner as a second mode of the app, sharing the existing 3D forest + character scene, with a UI cents meter, a gnome that leans + points the way to tune, and the scene desaturating to grayscale when off / regaining full color (plus a celebration pop) as you dial in.

**Architecture:** Four focused units. `pitch_detector.gd` is a pure autocorrelation algorithm (headless-testable). `tuner.gd` (Node) owns mic capture and maps Hz → note/cents, emitting signals. `tuner_ui.gd` (Control) is the meter overlay. `main.gd` is the coordinator (mode switch, saturation, gnome reaction) and `ui_manager.gd` gains a top Metronome|Tuner tab bar. The audio engine and UI never touch each other directly — `main.gd` wires them, exactly like the existing metronome flow.

**Tech Stack:** Godot 4.6 (gl_compatibility/mobile renderer), GDScript only. `AudioStreamMicrophone` + `AudioEffectCapture` for capture. Existing `Environment.adjustment_saturation` (already enabled at `main.gd:253`) for the grayscale effect. `GPUParticles3D` (pattern at `main.gd:853`) for the celebration sparkle.

**Key conventions (from the repo):**
- Parse/validate after every change: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .` (no errors = success).
- Visual run loop: `pkill -f "Godot.*metrognome" 2>/dev/null; /Applications/Godot.app/Contents/MacOS/Godot --path . > /dev/null 2>&1 &`
- After every `look_at`, follow with `node.rotate_object_local(Vector3.UP, PI)` (glTF −Z forward).
- Typed vars/signatures; snake_case; signals at top of file; no comments that restate code.
- Direction convention (locked): too **sharp** → gnome/arrow point **down/toward flat** ("bring it down"); too **flat** → point **up** ("raise it").

---

## File structure

| File | Create/Modify | Responsibility |
|------|---------------|----------------|
| `pitch_detector.gd` | Create | Pure algorithm. `static detect(samples, sample_rate) -> {frequency, clarity}`. |
| `tests/test_pitch_detector.gd` | Create | Headless `SceneTree` test feeding synthetic sines. |
| `tuner.gd` | Create | `Node`. Mic capture, Hz→note/cents mapping, signals. Static `nearest_note`. |
| `tests/test_tuner_notes.gd` | Create | Headless test for `Tuner.nearest_note` / `freq_to_midi`. |
| `tuner_ui.gd` | Create | `Control`. Note label, cents bar+needle, preset selector, mic-permission card. |
| `project.godot` | Modify | `audio/driver/enable_input=true`. |
| `export_presets.cfg` | Modify | Android `permissions/record_audio=true`; iOS `NSMicrophoneUsageDescription`. |
| `ui_manager.gd` | Modify | Top Metronome\|Tuner tab bar; `mode_changed` signal; show/hide `tuner_ui`; `force_paused()`. |
| `main.gd` | Modify | Create/own `Tuner`; mode switch; saturation lerp; gnome lean+arm; celebration. |

---

## Task 0: Enable audio input and microphone permissions

**Files:**
- Modify: `project.godot`
- Modify: `export_presets.cfg`

- [ ] **Step 1: Add the audio input driver flag to `project.godot`**

Add an `[audio]` `driver/enable_input` key. The file already has an `[audio]` section (`general/ios/session_category=3`). Edit that section to:

```
[audio]

general/ios/session_category=3
driver/enable_input=true
```

- [ ] **Step 2: Enable Android RECORD_AUDIO permission**

In `export_presets.cfg`, find `permissions/record_audio=false` (in the Android preset's permissions block, near `permissions/record_audio`) and change it to:

```
permissions/record_audio=true
```

If a `permissions/record_audio` key is not present, instead set `permissions/custom_permissions=PackedStringArray("android.permission.RECORD_AUDIO")`.

- [ ] **Step 3: Add iOS microphone usage description**

In `export_presets.cfg`, locate the iOS preset's `application/` keys. Add (or set) the microphone usage string key used by the Godot iOS exporter:

```
application/microphone_usage_description="Metrognomes uses the microphone to hear your instrument and help you tune it."
```

(If the installed Godot iOS exporter uses a different key name, set the equivalent `NSMicrophoneUsageDescription` value. This only affects iOS export, not the parse check.)

- [ ] **Step 4: Parse-check the project**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .`
Expected: exits cleanly, no parse/load errors printed.

- [ ] **Step 5: Commit**

```bash
git add project.godot export_presets.cfg
git commit -m "Enable audio input + microphone permissions for tuner"
```

---

## Task 1: Pitch detection algorithm (TDD)

**Files:**
- Create: `pitch_detector.gd`
- Test: `tests/test_pitch_detector.gd`

- [ ] **Step 1: Write the failing headless test**

Create `tests/test_pitch_detector.gd`:

```gdscript
extends SceneTree
# Headless test:  godot --headless --script res://tests/test_pitch_detector.gd

func _sine(freq: float, sr: float, n: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = sin(TAU * freq * float(i) / sr)
	return buf

func _noise(n: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	return buf

func _initialize() -> void:
	var failures := 0
	var sr := 44100.0
	var n := 2048

	# A2 = 110 Hz, A4 = 440 Hz, D3 = 146.83 Hz
	for freq in [110.0, 220.0, 440.0, 146.83]:
		var r: Dictionary = PitchDetector.detect(_sine(freq, sr, n), sr)
		var err: float = abs(r.frequency - freq)
		if err > freq * 0.02:   # within 2%
			push_error("FREQ FAIL %f -> %f (err %f)" % [freq, r.frequency, err])
			failures += 1
		if r.clarity < 0.8:
			push_error("CLARITY FAIL %f -> clarity %f" % [freq, r.clarity])
			failures += 1

	# Noise should report low clarity (no stable pitch)
	var nr: Dictionary = PitchDetector.detect(_noise(n), sr)
	if nr.clarity >= 0.6:
		push_error("NOISE FAIL clarity %f should be < 0.6" % nr.clarity)
		failures += 1

	if failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: %d" % failures)
		quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `mkdir -p tests; /Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tests/test_pitch_detector.gd --path .`
Expected: FAIL — error referencing `PitchDetector` not declared / identifier not found (the class does not exist yet).

- [ ] **Step 3: Implement `pitch_detector.gd`**

Create `pitch_detector.gd`:

```gdscript
class_name PitchDetector
extends RefCounted

# Autocorrelation pitch detection over a mono window. Pure + static so it can be
# unit-tested headless with synthetic sine buffers. Returns the fundamental
# frequency (Hz) and a clarity score in [0,1] (normalized peak strength); low
# clarity means "no stable pitch" (silence / noise) and callers should ignore it.

const MIN_FREQ := 50.0    # below low B on a bass guitar
const MAX_FREQ := 1500.0  # above the top of most fretted-instrument tuning range

static func detect(samples: PackedFloat32Array, sample_rate: float) -> Dictionary:
	var n := samples.size()
	if n < 4 or sample_rate <= 0.0:
		return {"frequency": 0.0, "clarity": 0.0}

	# Remove DC offset so silence/bias doesn't fake a low-frequency peak.
	var mean := 0.0
	for s in samples:
		mean += s
	mean /= float(n)

	var energy := 0.0
	for i in n:
		var v := samples[i] - mean
		energy += v * v
	if energy <= 0.00001:
		return {"frequency": 0.0, "clarity": 0.0}

	var min_lag := int(sample_rate / MAX_FREQ)
	var max_lag := int(sample_rate / MIN_FREQ)
	max_lag = min(max_lag, n - 1)
	if min_lag < 1:
		min_lag = 1
	if max_lag <= min_lag:
		return {"frequency": 0.0, "clarity": 0.0}

	# Normalized autocorrelation across the candidate lag range.
	var corrs := PackedFloat32Array()
	corrs.resize(max_lag + 1)
	var best_lag := -1
	var best_corr := 0.0
	for lag in range(min_lag, max_lag + 1):
		var corr := 0.0
		for i in range(n - lag):
			corr += (samples[i] - mean) * (samples[i + lag] - mean)
		corr /= energy
		corrs[lag] = corr
		if corr > best_corr:
			best_corr = corr
			best_lag = lag

	if best_lag <= 0:
		return {"frequency": 0.0, "clarity": 0.0}

	# Parabolic interpolation around the peak for sub-sample lag precision.
	var lag_f := float(best_lag)
	if best_lag > min_lag and best_lag < max_lag:
		var c0 := corrs[best_lag - 1]
		var c1 := corrs[best_lag]
		var c2 := corrs[best_lag + 1]
		var denom := c0 - 2.0 * c1 + c2
		if abs(denom) > 0.000001:
			lag_f = float(best_lag) + 0.5 * (c0 - c2) / denom

	return {"frequency": sample_rate / lag_f, "clarity": clamp(best_corr, 0.0, 1.0)}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tests/test_pitch_detector.gd --path .`
Expected: prints `ALL PASS`, exit code 0.

- [ ] **Step 5: Parse-check the whole project**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .`
Expected: clean, no errors.

- [ ] **Step 6: Commit**

```bash
git add pitch_detector.gd tests/test_pitch_detector.gd
git commit -m "Add autocorrelation pitch detector with headless test"
```

---

## Task 2: Tuner node — mic capture + note mapping

**Files:**
- Create: `tuner.gd`
- Test: `tests/test_tuner_notes.gd`

- [ ] **Step 1: Write the failing note-mapping test**

Create `tests/test_tuner_notes.gd`:

```gdscript
extends SceneTree
# Headless test:  godot --headless --script res://tests/test_tuner_notes.gd

func _check(cond: bool, msg: String) -> int:
	if cond:
		return 0
	push_error("FAIL: " + msg)
	return 1

func _initialize() -> void:
	var failures := 0

	# 440 Hz is A4, ~0 cents, chromatic (empty candidate list).
	var a: Dictionary = Tuner.nearest_note(440.0, [])
	failures += _check(a.name == "A4", "440Hz name was %s" % a.name)
	failures += _check(abs(a.cents) < 1.0, "440Hz cents was %f" % a.cents)

	# 110 Hz is A2.
	var a2: Dictionary = Tuner.nearest_note(110.0, [])
	failures += _check(a2.name == "A2", "110Hz name was %s" % a2.name)

	# Slightly sharp of A4: positive cents.
	var sharp: Dictionary = Tuner.nearest_note(445.0, [])
	failures += _check(sharp.cents > 0.0, "445Hz should be sharp, cents %f" % sharp.cents)

	# Guitar low E preset (midi 40 = E2 = 82.41 Hz): 83 Hz snaps to E2 even though
	# F2 is chromatically closer-by-name only after snapping to candidates.
	var e: Dictionary = Tuner.nearest_note(83.0, [40, 45, 50, 55, 59, 64])
	failures += _check(e.midi == 40, "83Hz on guitar preset snapped to midi %d" % e.midi)

	if failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		quit(1)
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tests/test_tuner_notes.gd --path .`
Expected: FAIL — `Tuner` not declared.

- [ ] **Step 3: Implement `tuner.gd`**

Create `tuner.gd`:

```gdscript
class_name Tuner
extends Node

# Owns microphone capture and converts the live signal into note + cents readings.
# Capture chain (built lazily on first start()): a muted "MicCapture" audio bus
# carrying an AudioEffectCapture, fed by an AudioStreamPlayer playing the mic.
# Muting the bus prevents the mic from echoing to the speakers (feedback).

signal pitch_detected(frequency: float, note_name: String, cents: float, clarity: float)
signal signal_lost()

const BUS_NAME := "MicCapture"
const WINDOW := 2048
const CLARITY_THRESHOLD := 0.6

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

var _player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _bus_idx: int = -1
var _window := PackedFloat32Array()
var _active := false
var _candidates: Array = []  # midi note numbers; empty = chromatic (all 12)
var _had_signal := false

# ---- pure note math (static, unit-tested) --------------------------------

static func freq_to_midi(freq: float) -> float:
	return 69.0 + 12.0 * (log(freq / 440.0) / log(2.0))

static func midi_to_freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

static func nearest_note(freq: float, candidates: Array) -> Dictionary:
	var midi := freq_to_midi(freq)
	var nearest_midi: int
	if candidates.is_empty():
		nearest_midi = int(round(midi))
	else:
		nearest_midi = int(candidates[0])
		var best: float = abs(midi - float(nearest_midi))
		for c in candidates:
			var d: float = abs(midi - float(c))
			if d < best:
				best = d
				nearest_midi = int(c)
	var ref := midi_to_freq(float(nearest_midi))
	var cents := 1200.0 * (log(freq / ref) / log(2.0))
	var octave := nearest_midi / 12 - 1
	var name := NOTE_NAMES[nearest_midi % 12] + str(octave)
	return {"midi": nearest_midi, "name": name, "cents": cents}

# ---- capture lifecycle ----------------------------------------------------

func start() -> void:
	if _active:
		return
	_ensure_bus()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS_NAME
		add_child(_player)
	_player.play()
	_window.clear()
	_had_signal = false
	_active = true

func stop() -> void:
	if not _active:
		return
	if _player != null:
		_player.stop()
	_window.clear()
	_had_signal = false
	_active = false

func is_active() -> bool:
	return _active

func set_candidates(midis: Array) -> void:
	_candidates = midis

func _ensure_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx == -1:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		AudioServer.set_bus_mute(_bus_idx, true)
	if AudioServer.get_bus_effect_count(_bus_idx) == 0:
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_bus_idx, _capture)
	else:
		_capture = AudioServer.get_bus_effect(_bus_idx, 0) as AudioEffectCapture

func _process(_delta: float) -> void:
	if not _active or _capture == null:
		return
	var available := _capture.get_frames_available()
	if available <= 0:
		return
	var frames := _capture.get_buffer(available)  # PackedVector2Array
	for f in frames:
		_window.append((f.x + f.y) * 0.5)
	if _window.size() < WINDOW:
		return
	if _window.size() > WINDOW:
		_window = _window.slice(_window.size() - WINDOW)

	var sr := AudioServer.get_mix_rate()
	var r := PitchDetector.detect(_window, sr)
	_window.clear()

	if r.clarity < CLARITY_THRESHOLD or r.frequency <= 0.0:
		if _had_signal:
			_had_signal = false
			signal_lost.emit()
		return
	_had_signal = true
	var note := Tuner.nearest_note(r.frequency, _candidates)
	pitch_detected.emit(r.frequency, String(note.name), float(note.cents), float(r.clarity))
```

- [ ] **Step 4: Run the note-mapping test to verify it passes**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tests/test_tuner_notes.gd --path .`
Expected: prints `ALL PASS`, exit 0.

- [ ] **Step 5: Parse-check the project**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .`
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add tuner.gd tests/test_tuner_notes.gd
git commit -m "Add Tuner node: mic capture + note/cents mapping with test"
```

---

## Task 3: Tuner UI overlay

**Files:**
- Create: `tuner_ui.gd`

This is a `Control` overlay (visual; verified by running). It mirrors the existing overlay style in `ui_manager.gd` (panel colors, label styling). It exposes `set_reading()` and `clear_reading()` for `ui_manager` to call, an `instrument_changed(midis: Array)` signal, and a `set_mic_available(ok)` to toggle a permission card.

- [ ] **Step 1: Implement `tuner_ui.gd`**

Create `tuner_ui.gd`:

```gdscript
class_name TunerUI
extends Control

# Bottom-anchored tuner meter: large note name, a horizontal cents bar with a
# center in-tune zone and a moving needle, a frequency readout, and an instrument
# preset selector. Shown/hidden by UIManager when the Tuner tab is active.

signal instrument_changed(candidate_midis: Array)

const IN_TUNE_CENTS := 5.0
const BAR_WIDTH := 320.0
const BAR_HEIGHT := 54.0

# Instrument presets: name -> candidate midi note numbers ([] = chromatic).
const PRESETS := [
	{"name": "Chromatic", "midis": []},
	{"name": "Guitar", "midis": [40, 45, 50, 55, 59, 64]},   # E2 A2 D3 G3 B3 E4
	{"name": "Bass", "midis": [28, 33, 38, 43]},             # E1 A1 D2 G2
	{"name": "Ukulele", "midis": [67, 60, 64, 69]},          # G4 C4 E4 A4
	{"name": "Violin", "midis": [55, 62, 69, 76]},           # G3 D4 A4 E5
]

var _note_label: Label
var _freq_label: Label
var _bar: Control
var _preset_button: OptionButton
var _permission_card: Control

var _cents := 0.0
var _has_signal := false

func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, 0.94)
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	_note_label = Label.new()
	_note_label.text = "--"
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note_label.add_theme_color_override("font_color", Color.WHITE)
	_note_label.add_theme_font_size_override("font_size", 72)
	col.add_child(_note_label)

	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_bar.draw.connect(_draw_bar)
	col.add_child(_bar)

	_freq_label = Label.new()
	_freq_label.text = "listening…"
	_freq_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_freq_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_freq_label.add_theme_font_size_override("font_size", 20)
	col.add_child(_freq_label)

	_preset_button = OptionButton.new()
	_preset_button.focus_mode = Control.FOCUS_NONE
	_preset_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	for p in PRESETS:
		_preset_button.add_item(String(p.name))
	_preset_button.selected = 0
	_preset_button.item_selected.connect(_on_preset_selected)
	col.add_child(_preset_button)

	_build_permission_card()

func _build_permission_card() -> void:
	_permission_card = CenterContainer.new()
	_permission_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_permission_card.visible = false
	add_child(_permission_card)
	var lbl := Label.new()
	lbl.text = "🎤  I need to hear your instrument.\nEnable microphone access to use the tuner."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	lbl.add_theme_font_size_override("font_size", 22)
	_permission_card.add_child(lbl)

func _on_preset_selected(index: int) -> void:
	instrument_changed.emit(PRESETS[index].midis)

# Called by UIManager / main when a confident pitch arrives.
func set_reading(note_name: String, cents: float, frequency: float) -> void:
	_has_signal = true
	_cents = cents
	_note_label.text = note_name
	if abs(cents) <= IN_TUNE_CENTS:
		_note_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		_note_label.add_theme_color_override("font_color", Color.WHITE)
	_freq_label.text = "%.1f Hz   %+d¢" % [frequency, int(round(cents))]
	_bar.queue_redraw()

func clear_reading() -> void:
	_has_signal = false
	_note_label.text = "--"
	_note_label.add_theme_color_override("font_color", Color.WHITE)
	_freq_label.text = "listening…"
	_bar.queue_redraw()

func set_mic_available(ok: bool) -> void:
	_permission_card.visible = not ok

func _draw_bar() -> void:
	var w := _bar.size.x
	var h := _bar.size.y
	var cy := h * 0.5
	# Track.
	_bar.draw_rect(Rect2(0, cy - 3, w, 6), Color(0.25, 0.25, 0.32))
	# Center in-tune zone.
	var zone_w := w * (IN_TUNE_CENTS / 50.0)
	_bar.draw_rect(Rect2(w * 0.5 - zone_w, cy - 12, zone_w * 2.0, 24), Color(0.3, 0.9, 0.4, 0.25))
	# Center line.
	_bar.draw_line(Vector2(w * 0.5, 4), Vector2(w * 0.5, h - 4), Color(0.5, 0.9, 0.55), 2.0)
	if not _has_signal:
		return
	# Needle: cents in [-50, 50] -> x across the bar.
	var t := clamp(_cents / 50.0, -1.0, 1.0)
	var nx := w * 0.5 + t * (w * 0.5)
	var in_tune := abs(_cents) <= IN_TUNE_CENTS
	var col := Color(0.3, 0.9, 0.4) if in_tune else Color(0.95, 0.65, 0.2)
	_bar.draw_line(Vector2(nx, 2), Vector2(nx, h - 2), col, 4.0)
```

- [ ] **Step 2: Parse-check the project**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .`
Expected: clean, no errors.

- [ ] **Step 3: Commit**

```bash
git add tuner_ui.gd
git commit -m "Add TunerUI overlay: note label, cents needle, presets, mic card"
```

---

## Task 4: Tab bar + mode switching in UIManager

**Files:**
- Modify: `ui_manager.gd`

Add a top **Metronome | Tuner** segmented control above the existing drawer, an owned `TunerUI` instance, a `mode_changed(mode)` signal, and a `force_paused()` helper. Mode `0` = metronome, `1` = tuner. When switching to tuner, hide the metronome bar/drawer and show `TunerUI`; reverse on switch back.

- [ ] **Step 1: Add the signal and members**

In `ui_manager.gd`, after the existing signal block (ends at `signal day_night_changed(time_of_day: int)`, line ~11), add:

```gdscript
signal mode_changed(mode: int)  # 0 = metronome, 1 = tuner
```

In the member-var block (near `var _help_modal: Control`, line ~53), add:

```gdscript
var _tab_bar: HBoxContainer
var _metronome_tab: Button
var _tuner_tab: Button
var _tuner_ui: TunerUI
var _mode: int = 0
```

- [ ] **Step 2: Build the tab bar and tuner UI in `_ready`**

In `_ready()`, immediately after `_build_drawer()` (line ~116) and before `_build_bar()`, insert `_build_tabs()`. Then after `_build_help_modal()` (line ~121) insert `_build_tuner_ui()`. The updated block:

```gdscript
	_build_tabs()              # top Metronome|Tuner segmented control
	_build_drawer()            # top (collapsible)
	_build_bar()               # bottom (always visible)
	_build_daynight_overlay()  # icon pinned to top-right corner (also creates _icon_layer_overlay)
	_build_help_button()       # ? icon pinned to top-left corner (reuses _icon_layer_overlay)
	_build_tap_overlay()       # full-screen tap tempo mode (layer 2)
	_build_help_modal()        # full-screen help modal (layer 3)
	_build_tuner_ui()          # bottom tuner meter (hidden until Tuner tab)
```

Note: `_build_tabs()` must run before `_build_drawer()`/`_build_bar()` only for visual order inside `_outer`; `_outer.add_child` appends in call order, so calling `_build_tabs()` first puts the tabs at the top of the column. Keep `_create_beat_dots(4)` etc. after as-is.

- [ ] **Step 3: Implement `_build_tabs`, `_build_tuner_ui`, and handlers**

Add these functions to `ui_manager.gd` (e.g. just after `_build_bar()`):

```gdscript
func _build_tabs() -> void:
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 8)
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outer.add_child(_tab_bar)

	_metronome_tab = _make_tab("Metronome")
	_metronome_tab.pressed.connect(func(): _set_mode(0))
	_tab_bar.add_child(_metronome_tab)

	_tuner_tab = _make_tab("Tuner")
	_tuner_tab.pressed.connect(func(): _set_mode(1))
	_tab_bar.add_child(_tuner_tab)

	_update_tab_styles()

func _make_tab(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(140, 44)
	return b

func _update_tab_styles() -> void:
	for pair in [[_metronome_tab, 0], [_tuner_tab, 1]]:
		var btn: Button = pair[0]
		var active: bool = pair[1] == _mode
		var sb := StyleBoxFlat.new()
		sb.bg_color = ACCENT_COLOR if active else TOGGLE_COLOR
		sb.set_corner_radius_all(12)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_color_override("font_color", Color(0.1, 0.08, 0.04) if active else Color.WHITE)

func _build_tuner_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	_tuner_ui = TunerUI.new()
	layer.add_child(_tuner_ui)

func _set_mode(mode: int) -> void:
	if mode == _mode:
		return
	_mode = mode
	_apply_mode_visibility()
	_update_tab_styles()
	mode_changed.emit(_mode)

func _apply_mode_visibility() -> void:
	var metronome := _mode == 0
	_bar.visible = metronome
	_drawer.visible = metronome and _drawer_open
	_tuner_ui.visible = not metronome

func get_tuner_ui() -> TunerUI:
	return _tuner_ui

func force_paused() -> void:
	# Reflect a stop initiated outside the play button (e.g. entering tuner mode).
	_is_playing = false
	_update_play_button_style()
```

- [ ] **Step 4: Parse-check the project**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .`
Expected: clean. (If `_update_play_button_style` has a different name in this file, use the actual one — it is called from `_ready` at line ~124.)

- [ ] **Step 5: Run and visually verify the tab bar appears**

Run: `pkill -f "Godot.*metrognome" 2>/dev/null; /Applications/Godot.app/Contents/MacOS/Godot --path . > /dev/null 2>&1 &`
Expected: app launches; a Metronome|Tuner tab row sits above the controls. Tapping **Tuner** hides the metronome controls and shows the tuner meter panel (note "--", empty cents bar, preset dropdown). Tapping **Metronome** restores the metronome controls. (Mic/scene behavior is wired in Task 5.)

- [ ] **Step 6: Commit**

```bash
git add ui_manager.gd
git commit -m "Add Metronome|Tuner tab bar and TunerUI hosting to UIManager"
```

---

## Task 5: Wire the tuner into main.gd (scene reaction + capture)

**Files:**
- Modify: `main.gd`

`main.gd` creates the `Tuner` node, connects UI + tuner signals, and on mode switch: collapses the gnome line to a single centered gnome, probes its arm bone, starts/stops capture, and pins/drives `adjustment_saturation`. Per-frame in tuner mode it lerps saturation toward the target, applies gnome lean + arm, and fires a one-shot celebration when locking in.

- [ ] **Step 1: Add tuner state members**

In `main.gd`, after `var _opossum_rng := RandomNumberGenerator.new()` (line ~94), add:

```gdscript
# --- Tuner mode -------------------------------------------------------------
var _tuner: Tuner
var _tuner_mode := false
var _tuner_cents := 0.0
var _tuner_has_signal := false
var _saved_line_count := 4          # restored when leaving tuner mode
var _arm_skeleton: Skeleton3D
var _arm_bone_idx := -1
var _arm_rest := Quaternion.IDENTITY
var _celebrate_timer := 0.0
var _was_in_tune := false
var _tuner_sparkle: GPUParticles3D

const TUNER_FULL_SATURATION := 1.15  # matches _setup_environment's normal value
const TUNER_IN_TUNE_CENTS := 5.0
const TUNER_MAX_LEAN := 0.35         # radians of body tilt at full sharp/flat
const TUNER_MAX_ARM := 0.7           # radians of arm raise at full sharp/flat
```

- [ ] **Step 2: Create the Tuner node and wire signals**

In `_ready()`, after `_setup_ui()` (line ~116), add `_setup_tuner()`. Then add this function near `_setup_metronome` (e.g. after `_setup_metronome`):

```gdscript
func _setup_tuner() -> void:
	_tuner = Tuner.new()
	_tuner.name = "Tuner"
	add_child(_tuner)
	_tuner.pitch_detected.connect(_on_tuner_pitch)
	_tuner.signal_lost.connect(_on_tuner_signal_lost)
	_ui_manager.mode_changed.connect(_on_ui_mode_changed)
	var tui := _ui_manager.get_tuner_ui()
	if tui != null:
		tui.instrument_changed.connect(_on_tuner_instrument_changed)
	_setup_tuner_sparkle()

func _setup_tuner_sparkle() -> void:
	var p := GPUParticles3D.new()
	p.name = "TunerSparkle"
	p.amount = 24
	p.lifetime = 0.9
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.9
	p.position = Vector3(0.0, 2.6, 0.0)
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	proc.emission_sphere_radius = 0.4
	proc.direction = Vector3(0, 1, 0)
	proc.spread = 180.0
	proc.gravity = Vector3(0, -1.5, 0)
	proc.initial_velocity_min = 1.5
	proc.initial_velocity_max = 3.0
	proc.scale_min = 0.4
	proc.scale_max = 1.0
	p.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 0.18)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = _soft_dot()
	m.emission_enabled = true
	m.emission = Color(1.0, 0.95, 0.6)
	m.emission_texture = _soft_dot()
	m.emission_energy_multiplier = 2.0
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	_tuner_sparkle = p
```

- [ ] **Step 3: Implement mode switch + signal handlers**

Add to `main.gd`:

```gdscript
func _on_ui_mode_changed(mode: int) -> void:
	if mode == 1:
		_enter_tuner_mode()
	else:
		_exit_tuner_mode()

func _enter_tuner_mode() -> void:
	if _tuner_mode:
		return
	_tuner_mode = true
	if _metronome.is_playing():
		_metronome.stop()
		_ui_manager.force_paused()
	_saved_line_count = _line_count
	_rebuild_gnome_line(1)           # single centered gnome to tune in front of
	_probe_arm_bone()
	_request_mic_then_start()

func _exit_tuner_mode() -> void:
	if not _tuner_mode:
		return
	_tuner_mode = false
	_tuner.stop()
	_tuner_has_signal = false
	_reset_gnome_pose()
	if _env != null:
		_env.adjustment_saturation = TUNER_FULL_SATURATION
	_rebuild_gnome_line(_saved_line_count)

func _request_mic_then_start() -> void:
	# Android needs a runtime permission grant; other platforms prompt on first use.
	if OS.get_name() == "Android":
		var granted := "android.permission.RECORD_AUDIO" in OS.get_granted_permissions()
		if not granted:
			OS.request_permissions()
	_tuner.start()
	var tui := _ui_manager.get_tuner_ui()
	if tui != null:
		tui.set_mic_available(true)

func _on_tuner_instrument_changed(midis: Array) -> void:
	if _tuner != null:
		_tuner.set_candidates(midis)

func _on_tuner_pitch(frequency: float, note_name: String, cents: float, _clarity: float) -> void:
	_tuner_cents = cents
	_tuner_has_signal = true
	var tui := _ui_manager.get_tuner_ui()
	if tui != null:
		tui.set_reading(note_name, cents, frequency)
	# Fire the celebration once on entering the in-tune window.
	var in_tune := abs(cents) <= TUNER_IN_TUNE_CENTS
	if in_tune and not _was_in_tune:
		_celebrate_timer = 0.6
		if _tuner_sparkle != null:
			_tuner_sparkle.restart()
	_was_in_tune = in_tune

func _on_tuner_signal_lost() -> void:
	_tuner_has_signal = false
	_was_in_tune = false
	var tui := _ui_manager.get_tuner_ui()
	if tui != null:
		tui.clear_reading()
```

- [ ] **Step 4: Implement arm-bone probing, pose application, and reset**

Add to `main.gd`:

```gdscript
func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

func _probe_arm_bone() -> void:
	_arm_skeleton = null
	_arm_bone_idx = -1
	if _gnomes.is_empty():
		return
	var model := _gnomes[0].get_node_or_null("GnomeModel") as Node3D
	if model == null:
		return
	var skel := _find_skeleton(model)
	if skel == null:
		return
	for i in skel.get_bone_count():
		var bn := skel.get_bone_name(i).to_lower()
		if bn.contains("arm") or bn.contains("shoulder") or bn.contains("clavicle"):
			_arm_skeleton = skel
			_arm_bone_idx = i
			_arm_rest = skel.get_bone_pose_rotation(i)
			return  # lean-only fallback if no match found

func _apply_gnome_tuning(delta: float) -> void:
	if _gnomes.is_empty():
		return
	var pulse := _gnomes[0]
	# Direction: sharp (cents > 0) -> tilt/point toward flat (negative lean).
	var norm := 0.0
	if _tuner_has_signal:
		norm = clamp(_tuner_cents / 50.0, -1.0, 1.0)
	# Lean the whole body on Z (always available, robust on every rig).
	var target_lean := -norm * TUNER_MAX_LEAN
	pulse.rotation.z = lerp(pulse.rotation.z, target_lean, 1.0 - exp(-delta * 6.0))
	# Arm point (best-effort; only if a bone was found).
	if _arm_skeleton != null and _arm_bone_idx >= 0:
		var arm_angle := -norm * TUNER_MAX_ARM
		var target_q := _arm_rest * Quaternion(Vector3.FORWARD, arm_angle)
		var cur := _arm_skeleton.get_bone_pose_rotation(_arm_bone_idx)
		_arm_skeleton.set_bone_pose_rotation(_arm_bone_idx, cur.slerp(target_q, 1.0 - exp(-delta * 6.0)))

func _reset_gnome_pose() -> void:
	if not _gnomes.is_empty():
		_gnomes[0].rotation.z = 0.0
	if _arm_skeleton != null and _arm_bone_idx >= 0:
		_arm_skeleton.set_bone_pose_rotation(_arm_bone_idx, _arm_rest)
	_arm_skeleton = null
	_arm_bone_idx = -1
```

- [ ] **Step 5: Drive saturation + gnome each frame in `_process`**

Modify `_process(delta)` (line ~994). Insert the tuner block at the very top, before the existing opossum early-return:

```gdscript
func _process(delta: float) -> void:
	if _tuner_mode:
		_update_tuner_visuals(delta)
		return

	if _opossum == null or _metronome == null or not _metronome.is_playing():
		return
	# ... existing opossum wander code unchanged ...
```

Then add the helper:

```gdscript
func _update_tuner_visuals(delta: float) -> void:
	if _env == null:
		return
	var target := 0.0
	if _tuner_has_signal:
		var off := clamp(abs(_tuner_cents) / 50.0, 0.0, 1.0)
		target = lerp(TUNER_FULL_SATURATION, 0.0, off)  # dead-on -> full color
	if _celebrate_timer > 0.0:
		_celebrate_timer -= delta
		target += 0.6 * max(_celebrate_timer / 0.6, 0.0)  # brief over-saturation pop
	_env.adjustment_saturation = lerp(_env.adjustment_saturation, target, 1.0 - exp(-delta * 5.0))
	_apply_gnome_tuning(delta)
```

- [ ] **Step 6: Parse-check the project**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .`
Expected: clean, no errors.

- [ ] **Step 7: Run and verify on desktop (mic available)**

Run: `pkill -f "Godot.*metrognome" 2>/dev/null; /Applications/Godot.app/Contents/MacOS/Godot --path . > /dev/null 2>&1 &`
Expected on tapping **Tuner**: the gnome line collapses to a single centered gnome; the scene desaturates toward grayscale; whistling/playing a note near the mic shows the note name + cents needle, the scene regains color as you approach the pitch, the gnome leans (and points if its rig has an arm bone), and locking in (≤5¢) pops a sparkle + color bloom. Tapping **Metronome** restores full color, the upright gnome line, and the metronome controls. Confirm no errors in the console.

- [ ] **Step 8: Commit**

```bash
git add main.gd
git commit -m "Wire tuner into scene: saturation ramp, gnome lean+arm, celebration"
```

---

## Task 6: Final validation + manual device checklist

**Files:** none (verification only)

- [ ] **Step 1: Run both headless unit tests**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tests/test_pitch_detector.gd --path .
/Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tests/test_tuner_notes.gd --path .
```
Expected: both print `ALL PASS`.

- [ ] **Step 2: Full parse/validate gate (same as CI)**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --quit --path .`
Expected: clean, no errors.

- [ ] **Step 3: Manual checklist (record results in the PR description)**

  - Desktop: tab switch, mic prompt (OS), needle tracks a known tuner-app pitch, saturation ramp, gnome lean, lock-in celebration, return to metronome restores state.
  - Android device: RECORD_AUDIO runtime prompt appears on first Tuner entry; capture works after granting; permission card shows if denied.
  - iOS device: microphone permission prompt appears; capture works.
  - Web (itch.io build): if mic unavailable, the permission card shows and the app does not crash; metronome mode unaffected.

- [ ] **Step 4: Update docs**

Add a short "Tuner" entry to `README.md`'s feature list and bump `project.godot` `config/version` if shipping. Commit:

```bash
git add README.md project.godot
git commit -m "Docs: document tuner mode"
```

---

## Self-review notes (addressed)

- **Spec coverage:** hybrid auto-detect + presets (Task 2/3 `nearest_note` + PRESETS), full mode swap (Task 4 tabs), gnome lean+arm with lean-only fallback (Task 5 `_apply_gnome_tuning`/`_probe_arm_bone`), continuous ramp + celebrate (Task 5 `_update_tuner_visuals` + sparkle), permissions/fallback (Task 0 + `_request_mic_then_start` + permission card), separate focused files (all). ✅
- **Type consistency:** `Tuner.nearest_note` returns `{midi,name,cents}` and is used as such; `pitch_detected(frequency, note_name, cents, clarity)` matches the handler signature in main.gd; `get_tuner_ui()` / `set_reading()` / `clear_reading()` / `set_mic_available()` / `set_candidates()` names match across files. ✅
- **Known risks (carried from spec):** autocorrelation can octave-error on rich timbres (clarity gate + preset snapping mitigate); arm-bone probe is heuristic (lean-only fallback guarantees correctness); paused AnimationPlayer may contend with bone pose override — if observed, the lean still reads and arm can be dropped. Web mic is environment-dependent (permission card covers it).
