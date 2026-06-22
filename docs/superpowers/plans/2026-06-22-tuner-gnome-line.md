# Tuner Gnome Line Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign the instrument tuner screen so the cents/note overlay floats above the 3D scene, instrument-specific gnome lines appear in the forest (6 gnomes for guitar, 4 for bass/ukulele/violin, 1 for chromatic), each gnome shows its string note below it, and clicking a gnome locks the tuner to that string.

**Architecture:** TunerUI detaches from UIManager's bottom panel and moves to a dedicated CanvasLayer (layer 2) centered in the upper portion of the screen. UIManager in tuner mode shrinks to just the Metronome|Tuner tab strip. `main.gd` owns a separate `_tuner_gnomes` array (parallel to the metronome `_gnomes`) which is rebuilt when the instrument preset changes; each gnome carries a billboard `Label3D` below it and an `Area3D` for click-to-lock.

**Tech Stack:** Godot 4.6 GDScript, existing gnome model (`_gnome_scene`), `Label3D` (billboard, always faces camera), `Area3D` + `CollisionShape3D` for click detection, `CanvasLayer` for the floating overlay, existing `Tuner`/`TunerUI` classes.

---

## File Map

| File | Change |
|------|--------|
| `tuner_ui.gd` | Remove bottom-anchored preset; become a self-sizing panel (fixed height 200px, centered by parent) |
| `ui_manager.gd` | Remove `_build_tuner_ui()`, `_tuner_ui`, `get_tuner_ui()`; tuner-mode height = tab bar only |
| `main.gd` | Add `_tuner_overlay: CanvasLayer`, `_tuner_ui: TunerUI`, `_tuner_gnomes`, `_tuner_gnome_midis`, `_tuner_gnome_note_names`, `_tuner_selected_idx`, `_tuner_auto_idx`; new functions for building/destroying the tuner gnome line and click handling |

---

### Task A: TunerUI — self-sizing floating panel

TunerUI is currently anchored to the bottom of its container. Strip those anchors so it sizes itself and lets its parent position it.

**Files:**
- Modify: `tuner_ui.gd:33-37` (the `_ready` anchor/grow lines)

- [ ] **Step 1: Replace bottom-anchored anchor preset with neutral sizing**

In `tuner_ui.gd`, replace the opening lines of `_ready()`:

```gdscript
# OLD (remove these 3 lines):
#   set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
#   grow_vertical = Control.GROW_DIRECTION_BEGIN
#   mouse_filter = Control.MOUSE_FILTER_IGNORE

# NEW _ready() opening:
func _ready() -> void:
	custom_minimum_size = Vector2(360, 200)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
```

The `Panel` child already uses `PRESET_FULL_RECT`, so it fills whatever size TunerUI is given.

- [ ] **Step 2: Parse-check tuner_ui.gd in isolation**

```bash
pkill -f "Godot.*metrognome" 2>/dev/null
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/ianlintner/Projects/metrognome \
  --headless --quit 2>&1 | grep -E "SCRIPT ERROR|tuner_ui"
```

Expected: no output (clean parse).

- [ ] **Step 3: Commit**

```bash
git add tuner_ui.gd
git commit -m "feat: TunerUI becomes self-sizing (no bottom-wide anchor)"
```

---

### Task B: UIManager — tuner mode collapses to tab strip only

Remove TunerUI from UIManager's `_outer` VBox. In tuner mode the panel shows only the Metronome|Tuner tab bar (≈40px), leaving the full screen for the 3D scene and the floating overlay.

**Files:**
- Modify: `ui_manager.gd` — remove `_tuner_ui`, `_build_tuner_ui()`, `get_tuner_ui()`; fix `_refresh_panel_height` for tuner mode

- [ ] **Step 1: Remove the `_tuner_ui` member variable**

In `ui_manager.gd`, delete:
```gdscript
var _tuner_ui: Control  # TunerUI instance
```

- [ ] **Step 2: Remove `_build_tuner_ui()` call from `_ready()`**

```gdscript
# In _ready(), remove this line:
_build_tuner_ui()          # bottom tuner meter, hidden until Tuner tab
```

- [ ] **Step 3: Remove the three functions that reference `_tuner_ui`**

Delete these entire functions:
- `_build_tuner_ui()` (creates TunerUI and adds to `_outer`)
- `get_tuner_ui() -> Control` (returns `_tuner_ui`)

Keep `force_paused()` — main.gd still calls it.

- [ ] **Step 4: Fix `_refresh_panel_height` — tuner mode uses tab height only**

Replace the existing `_refresh_panel_height` body with:

```gdscript
func _refresh_panel_height(animate: bool) -> void:
	var is_metro := (_mode == 0)
	_drawer.visible = is_metro and _drawer_open
	_bar.visible = is_metro

	var inset := _bottom_inset()
	var v_pad := int(14.0 * _ui_scale)
	var sep := _outer.get_theme_constant("separation")
	var tab_h := _tab_bar.get_combined_minimum_size().y if _tab_bar != null else 0.0
	var total: float
	if is_metro:
		var bar_h := _bar.get_combined_minimum_size().y
		total = tab_h + sep + bar_h + v_pad * 2.0 + inset
		if _drawer_open:
			total += _drawer.get_combined_minimum_size().y + sep
	else:
		# Tuner mode: show only the tab strip — the floating overlay provides the UI.
		total = tab_h + v_pad * 2.0 + inset

	if _height_tween != null and _height_tween.is_valid():
		_height_tween.kill()
	if animate:
		_height_tween = create_tween()
		_height_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_height_tween.tween_property(self, "offset_top", -total, 0.22)
	else:
		offset_top = -total
	offset_bottom = 0
```

- [ ] **Step 5: Parse-check**

```bash
pkill -f "Godot.*metrognome" 2>/dev/null
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/ianlintner/Projects/metrognome \
  --headless --quit 2>&1 | grep "SCRIPT ERROR"
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add ui_manager.gd
git commit -m "feat: UIManager tuner mode shrinks to tab strip; TunerUI removed from panel"
```

---

### Task C: main.gd — floating TunerUI canvas-layer overlay

`main.gd` takes ownership of TunerUI. It creates a dedicated `CanvasLayer` (layer 2, above UIManager), positions TunerUI centered near the top of the screen, and connects the instrument-changed signal.

**Files:**
- Modify: `main.gd`

- [ ] **Step 1: Add new state variables** (after the existing `_tuner_sparkle` var)

```gdscript
# In the --- Tuner --- var block, add:
var _tuner_overlay: CanvasLayer
var _tuner_ui: TunerUI
```

- [ ] **Step 2: Add `_setup_tuner_overlay()` function**

```gdscript
func _setup_tuner_overlay() -> void:
	_tuner_overlay = CanvasLayer.new()
	_tuner_overlay.layer = 2
	_tuner_overlay.name = "TunerOverlay"
	add_child(_tuner_overlay)

	# Center-top anchor so TunerUI floats above the 3D scene.
	var anchor := Control.new()
	anchor.set_anchors_preset(Control.PRESET_TOP_WIDE)
	anchor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.offset_bottom = 220.0
	_tuner_overlay.add_child(anchor)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor.add_child(center)

	_tuner_ui = TunerUI.new()
	center.add_child(_tuner_ui)
	_tuner_overlay.visible = false
```

- [ ] **Step 3: Call `_setup_tuner_overlay()` in `_setup_tuner()` just before probe_arm_bone**

```gdscript
func _setup_tuner() -> void:
	_tuner = Tuner.new()
	_tuner.name = "Tuner"
	add_child(_tuner)
	_tuner.pitch_detected.connect(_on_tuner_pitch)
	_tuner.signal_lost.connect(_on_tuner_signal_lost)
	_setup_tuner_sparkle()
	_setup_tuner_overlay()      # <-- add this line
	_probe_arm_bone()
	_tuner_ui.instrument_changed.connect(_on_tuner_instrument_changed)
```

- [ ] **Step 4: Remove the old `_ui_manager.get_tuner_ui()` call from `_setup_tuner()`**

```gdscript
# DELETE these lines from _setup_tuner():
# var tu := _ui_manager.get_tuner_ui() as TunerUI
# if tu != null:
#     tu.instrument_changed.connect(_on_tuner_instrument_changed)
```

- [ ] **Step 5: Update `_enter_tuner_mode` to show/hide overlay and use `_tuner_ui` directly**

Replace the body with:

```gdscript
func _enter_tuner_mode() -> void:
	_tuner_mode = true
	if _metronome.is_playing():
		_metronome.pause()
		_ui_manager.force_paused()
		for ap in _anim_players:
			ap.pause()
	_env.adjustment_saturation = TUNER_BASE_SATURATION
	_tuner_overlay.visible = true
	_tuner.set_candidates([])
	_tuner.start()
	var ok: bool = true
	if OS.get_name() == "Android":
		ok = OS.request_permission("RECORD_AUDIO")
	_tuner_ui.set_mic_available(ok)
```

- [ ] **Step 6: Update `_exit_tuner_mode` to hide overlay**

```gdscript
func _exit_tuner_mode() -> void:
	_tuner_mode = false
	_tuner_has_signal = false
	_tuner_celebrated = false
	_tuner.stop()
	_reset_gnome_pose()
	_tuner_overlay.visible = false
	_env.adjustment_saturation = TUNER_FULL_SATURATION
```

- [ ] **Step 7: Update `_on_tuner_pitch` and `_on_tuner_signal_lost` — use `_tuner_ui` directly**

```gdscript
func _on_tuner_pitch(frequency: float, note_name: String, cents: float, _clarity: float) -> void:
	if not _tuner_mode:
		return
	_tuner_has_signal = true
	_tuner_cents = cents
	_tuner_ui.set_reading(note_name, cents, frequency)


func _on_tuner_signal_lost() -> void:
	if not _tuner_mode:
		return
	_tuner_has_signal = false
	_tuner_ui.clear_reading()
```

- [ ] **Step 8: Parse-check and visual verify**

```bash
pkill -f "Godot.*metrognome" 2>/dev/null
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/ianlintner/Projects/metrognome \
  --headless --quit 2>&1 | grep "SCRIPT ERROR"
```

Then launch the project visually:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/ianlintner/Projects/metrognome &
```

Tap the **Tuner** tab. Confirm:
- Bottom bar collapses to just the Metronome|Tuner tabs (minimal height)
- TunerUI floating panel appears centered near the top of the screen
- TunerUI shows note label, cents bar, preset dropdown

- [ ] **Step 9: Commit**

```bash
git add main.gd
git commit -m "feat: TunerUI owned by main.gd as floating canvas-layer overlay (Task C)"
```

---

### Task D: Tuner gnome line — instrument-specific gnomes with note labels

Build a parallel gnome array (`_tuner_gnomes`) in main.gd. When entering tuner mode, hide the metronome gnomes and show the tuner gnome line. Each gnome gets a billboard `Label3D` below it showing its note name (e.g., "E2", "A2"). When no string is selected, all gnomes stand at rest. Rebuilding happens on both `_enter_tuner_mode` and `_on_tuner_instrument_changed`.

**Files:**
- Modify: `main.gd`

**Note constants used throughout this task:**
```gdscript
const NOTE_NAMES_SHARP := ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

# midi_to_note_name: e.g. midi 40 → "E2"
static func _midi_note_name(midi: int) -> String:
    var octave := midi / 12 - 1
    return NOTE_NAMES_SHARP[midi % 12] + str(octave)
```

- [ ] **Step 1: Add new tuner gnome state variables** (after `_tuner_ui` var)

```gdscript
var _tuner_gnomes: Array[GnomePulse] = []
var _tuner_gnome_midis: Array[int] = []       # parallel to _tuner_gnomes
var _tuner_gnome_note_names: Array[String] = [] # parallel to _tuner_gnomes
var _tuner_selected_idx: int = -1  # which gnome is locked (-1 = auto)
var _tuner_auto_idx: int = 0       # which gnome matches current pitch
var _metronome_line_count: int = 4  # saved line count while tuner is active
```

- [ ] **Step 2: Add `_midi_note_name()` static helper near top of main.gd (after constants)**

```gdscript
const TUNER_NOTE_NAMES := ["C","C#","D","D#","E","F","F#","G","G#","A","A#","B"]

static func _midi_note_name(midi: int) -> String:
	return TUNER_NOTE_NAMES[midi % 12] + str(midi / 12 - 1)
```

- [ ] **Step 3: Add `_rebuild_tuner_gnome_line(midis: Array)` function**

Add this function in main.gd (near `_rebuild_gnome_line`):

```gdscript
func _rebuild_tuner_gnome_line(midis: Array) -> void:
	# Free existing tuner gnomes.
	for g in _tuner_gnomes:
		g.queue_free()
	_tuner_gnomes.clear()
	_tuner_gnome_midis.clear()
	_tuner_gnome_note_names.clear()
	_tuner_selected_idx = -1
	_tuner_auto_idx = 0
	_arm_skeleton = null
	_arm_bone_idx = -1

	if _gnome_scene == null:
		return

	# Chromatic (empty midis) → single gnome; otherwise one per string.
	var entries: Array = midis if midis.size() > 0 else [69]  # A4 placeholder for chromatic
	var is_chromatic: bool = midis.is_empty()
	var count := entries.size()
	var char_scale: float = float(CHARACTERS[_active_char].scale)
	var total_width := float(count - 1) * GNOME_SPACING
	var start_x := -total_width / 2.0

	for i in count:
		var midi: int = int(entries[i])
		var pulse := GnomePulse.new()
		pulse.name = "TunerGnome%d" % i
		pulse.position = Vector3(-(start_x + i * GNOME_SPACING), 0.0, 0)
		pulse.base_bounce_height = 0.0   # tuner gnomes don't bounce
		pulse.accent_bounce_height = 0.0
		add_child(pulse)

		var model := _gnome_scene.instantiate() as Node3D
		model.name = "GnomeModel"
		model.scale = Vector3(char_scale, char_scale, char_scale)
		pulse.add_child(model)

		# Arm-down idle pose.
		var ap := _find_animation_player(model)
		if ap != null and _hop_anim != null:
			var lib := ap.get_animation_library("")
			if lib == null:
				lib = AnimationLibrary.new()
				ap.add_animation_library("", lib)
			if not lib.has_animation(GNOME_HOP):
				lib.add_animation(GNOME_HOP, _hop_anim)
			ap.play(GNOME_HOP)
			ap.pause()

		# Billboard note label below gnome.
		var label := Label3D.new()
		label.text = "" if is_chromatic else _midi_note_name(midi)
		label.font_size = 64
		label.pixel_size = 0.004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0, -0.5, 0)
		label.modulate = Color(0.9, 0.9, 1.0)
		pulse.add_child(label)

		# Area3D for click detection (only needed when more than one gnome).
		if count > 1:
			var area := Area3D.new()
			area.name = "ClickArea"
			area.input_ray_pickable = true
			var shape := CollisionShape3D.new()
			var capsule := CapsuleShape3D.new()
			capsule.radius = 0.55
			capsule.height = 1.8
			shape.shape = capsule
			shape.position = Vector3(0, 0.9, 0)  # centred on gnome body
			area.add_child(shape)
			var idx_capture := i  # capture loop var for closure
			area.input_event.connect(
				func(_cam, event: InputEvent, _pos, _normal, _shape_idx):
					if event is InputEventMouseButton \
					and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT \
					and (event as InputEventMouseButton).pressed:
						_on_tuner_gnome_clicked(idx_capture)
			)
			pulse.add_child(area)

		_tuner_gnomes.append(pulse)
		_tuner_gnome_midis.append(midi)
		_tuner_gnome_note_names.append(_midi_note_name(midi) if not is_chromatic else "")

	# Orient toward camera, reuse existing logic.
	_frame_camera()
	# Probe arm bone from the new tuner gnomes.
	if not _tuner_gnomes.is_empty():
		var skel := _find_skeleton_in(_tuner_gnomes[0])
		if skel != null:
			for preferred: String in ["RightArm", "RightShoulder", "LeftArm"]:
				for bi in skel.get_bone_count():
					if skel.get_bone_name(bi) == preferred:
						_arm_skeleton = skel
						_arm_bone_idx = bi
						break
			if _arm_bone_idx >= 0:
				pass  # found
```

- [ ] **Step 4: Update `_enter_tuner_mode` — hide metro gnomes, show tuner gnomes**

Replace the existing function body:

```gdscript
func _enter_tuner_mode() -> void:
	_tuner_mode = true
	if _metronome.is_playing():
		_metronome.pause()
		_ui_manager.force_paused()
		for ap in _anim_players:
			ap.pause()
	# Save metro line count, hide metro gnomes.
	_metronome_line_count = _line_count
	for g in _gnomes:
		g.visible = false

	_env.adjustment_saturation = TUNER_BASE_SATURATION
	_tuner_overlay.visible = true
	# Chromatic by default — single gnome.
	_rebuild_tuner_gnome_line([])
	_tuner.set_candidates([])
	_tuner.start()
	var ok: bool = true
	if OS.get_name() == "Android":
		ok = OS.request_permission("RECORD_AUDIO")
	_tuner_ui.set_mic_available(ok)
```

- [ ] **Step 5: Update `_exit_tuner_mode` — free tuner gnomes, restore metro gnomes**

```gdscript
func _exit_tuner_mode() -> void:
	_tuner_mode = false
	_tuner_has_signal = false
	_tuner_celebrated = false
	_tuner.stop()
	_tuner_overlay.visible = false

	# Free tuner gnomes, restore metronome gnomes.
	for g in _tuner_gnomes:
		g.queue_free()
	_tuner_gnomes.clear()
	_tuner_gnome_midis.clear()
	_tuner_gnome_note_names.clear()
	_arm_skeleton = null
	_arm_bone_idx = -1

	_line_count = _metronome_line_count
	for g in _gnomes:
		g.visible = true
	_frame_camera()
	_env.adjustment_saturation = TUNER_FULL_SATURATION
```

- [ ] **Step 6: Update `_on_tuner_instrument_changed` — rebuild tuner gnomes**

```gdscript
func _on_tuner_instrument_changed(midis: Array) -> void:
	_tuner.set_candidates(midis)
	if _tuner_mode:
		_rebuild_tuner_gnome_line(midis)
```

- [ ] **Step 7: Update `_apply_gnome_tuning` — operate on tuner gnomes instead of metro gnomes**

```gdscript
func _apply_gnome_tuning(cents: float) -> void:
	if _tuner_gnomes.is_empty():
		return
	var idx := _tuner_selected_idx if _tuner_selected_idx >= 0 else _tuner_auto_idx
	idx = clampi(idx, 0, _tuner_gnomes.size() - 1)
	var gnome := _tuner_gnomes[idx]
	var lean: float = clampf(cents / 50.0, -1.0, 1.0) * -TUNER_MAX_LEAN
	gnome.rotation.z = lerpf(gnome.rotation.z, lean, 0.1)
	if _arm_skeleton != null and _arm_bone_idx >= 0:
		var arm_angle: float = clampf(-cents / 50.0, -1.0, 1.0) * 0.6
		_arm_skeleton.set_bone_pose_rotation(_arm_bone_idx, Quaternion(Vector3.RIGHT, arm_angle))
```

- [ ] **Step 8: Update `_reset_gnome_pose` — reset tuner gnomes**

```gdscript
func _reset_gnome_pose() -> void:
	for g in _tuner_gnomes:
		g.rotation.z = 0.0
	if _arm_skeleton != null and _arm_bone_idx >= 0:
		_arm_skeleton.set_bone_pose_rotation(_arm_bone_idx, Quaternion.IDENTITY)
```

- [ ] **Step 9: Parse-check**

```bash
pkill -f "Godot.*metrognome" 2>/dev/null
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/ianlintner/Projects/metrognome \
  --headless --quit 2>&1 | grep "SCRIPT ERROR"
```

Expected: no output.

- [ ] **Step 10: Visual verify**

Launch the project. Switch to Tuner tab. Confirm:
- Metronome gnomes disappear, one tuner gnome appears (chromatic)
- Switch preset to Guitar → 6 gnomes appear with E2, A2, D3, G3, B3, E4 labels below them
- Switch preset to Bass → 4 gnomes with E1, A1, D2, G2 labels
- Note labels face the camera (billboard mode)
- Switch back to Metronome → tuner gnomes disappear, metronome gnomes restore

- [ ] **Step 11: Commit**

```bash
git add main.gd
git commit -m "feat: instrument-specific tuner gnome line with billboard note labels (Task D)"
```

---

### Task E: Click-to-lock and auto-active gnome highlighting

When the user clicks a gnome it locks the tuner to that string and highlights the selected gnome. When no string is locked, the gnome whose string best matches the detected pitch is highlighted automatically. Unselected gnomes dim slightly.

**Files:**
- Modify: `main.gd`

- [ ] **Step 1: Add `_on_tuner_gnome_clicked(idx: int)` function**

```gdscript
func _on_tuner_gnome_clicked(idx: int) -> void:
	if idx == _tuner_selected_idx:
		# Second click on the same gnome → unlock (back to auto).
		_tuner_selected_idx = -1
		_tuner.set_candidates(_tuner_gnome_midis)  # allow all strings
	else:
		_tuner_selected_idx = idx
		_tuner.set_candidates([_tuner_gnome_midis[idx]])  # lock to one string
	_update_tuner_gnome_highlights()
```

- [ ] **Step 2: Add `_update_tuner_gnome_highlights()` function**

```gdscript
func _update_tuner_gnome_highlights() -> void:
	for i in _tuner_gnomes.size():
		var gnome := _tuner_gnomes[i]
		var active := (i == _tuner_selected_idx) or \
					  (_tuner_selected_idx < 0 and i == _tuner_auto_idx)
		var char_scale: float = float(CHARACTERS[_active_char].scale)
		var target_scale := char_scale * (1.1 if active else 0.85)
		var model := gnome.get_node_or_null("GnomeModel") as Node3D
		if model != null:
			model.scale = Vector3(target_scale, target_scale, target_scale)
		# Brighten/dim the note label.
		var label := gnome.get_node_or_null("Label3D") as Label3D
		if label != null:
			label.modulate = ACCENT_COLOR if active else Color(0.55, 0.55, 0.65)
```

> `ACCENT_COLOR` is already defined in UIManager but not in main.gd. Add this constant near the other tuner constants:
> ```gdscript
> const TUNER_ACCENT_COLOR := Color(0.95, 0.65, 0.2)  # same orange as UIManager.ACCENT_COLOR
> ```
> Then use `TUNER_ACCENT_COLOR` in the highlight function instead of `ACCENT_COLOR`.

- [ ] **Step 3: Detect auto-active gnome in `_on_tuner_pitch`**

Update `_on_tuner_pitch` to auto-detect which gnome's string matches the incoming note:

```gdscript
func _on_tuner_pitch(frequency: float, note_name: String, cents: float, _clarity: float) -> void:
	if not _tuner_mode:
		return
	_tuner_has_signal = true
	_tuner_cents = cents
	_tuner_ui.set_reading(note_name, cents, frequency)

	# Auto-highlight: find which gnome's note matches the detected note name.
	if _tuner_selected_idx < 0 and _tuner_gnome_note_names.size() > 1:
		for i in _tuner_gnome_note_names.size():
			if _tuner_gnome_note_names[i] == note_name:
				if _tuner_auto_idx != i:
					_tuner_auto_idx = i
					_update_tuner_gnome_highlights()
				break
```

- [ ] **Step 4: Call `_update_tuner_gnome_highlights()` at end of `_rebuild_tuner_gnome_line`**

Add as the last line of `_rebuild_tuner_gnome_line()`:

```gdscript
_update_tuner_gnome_highlights()
```

- [ ] **Step 5: Parse-check**

```bash
pkill -f "Godot.*metrognome" 2>/dev/null
/Applications/Godot.app/Contents/MacOS/Godot --path /Users/ianlintner/Projects/metrognome \
  --headless --quit 2>&1 | grep "SCRIPT ERROR"
```

Expected: no output.

- [ ] **Step 6: Visual verify**

Launch. Switch to Tuner. Select Guitar preset (6 gnomes). Confirm:
- All gnomes appear at normal scale with dim labels
- Click a gnome → it scales up to 1.1× and its label turns orange; others shrink to 0.85×
- Click the same gnome again → unlocks (all gnomes return to normal scale)
- While unlocked: play a string near one of the notes → that gnome auto-highlights
- The highlighted gnome shows the lean/arm animation; others stay upright

- [ ] **Step 7: Commit**

```bash
git add main.gd
git commit -m "feat: click-to-lock string selection and auto-active gnome highlighting (Task E)"
```

---

### Task F: Final validation and unit tests

Run all automated tests, confirm a full visual pass, and verify both modes (metronome and tuner) work cleanly.

**Files:** No code changes — validation only.

- [ ] **Step 1: Run pitch detector tests**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/ianlintner/Projects/metrognome \
  --headless --script tests/test_pitch_detector.gd 2>&1 | tail -5
```

Expected: `ALL PASS`

- [ ] **Step 2: Run tuner note-math tests**

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/ianlintner/Projects/metrognome \
  --headless --script tests/test_tuner_notes.gd 2>&1 | tail -5
```

Expected: `ALL PASS`

- [ ] **Step 3: Final headless parse gate**

```bash
pkill -f "Godot.*metrognome" 2>/dev/null
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /Users/ianlintner/Projects/metrognome \
  --headless --quit 2>&1 | grep "SCRIPT ERROR"
```

Expected: no output.

- [ ] **Step 4: Visual checklist**

Launch the project. Walk through this checklist:

| Check | Expected |
|-------|----------|
| App opens on Metronome tab | Normal gnome line, full saturation |
| Tap Tuner tab | Metronome gnomes hide; 1 gnome (chromatic) appears; bottom bar shrinks to tab strip only; TunerUI floats at top-center |
| Select Guitar preset | 6 gnomes with E2/A2/D3/G3/B3/E4 labels appear, spaced evenly |
| Select Bass preset | 4 gnomes with E1/A1/D2/G2 labels |
| Select Ukulele preset | 4 gnomes with G4/C4/E4/A4 labels |
| Click gnome | That gnome highlights (1.1× scale, orange label); others dim (0.85×) |
| Click same gnome again | Unlocks — all gnomes at normal scale |
| Switch back to Metronome tab | Tuner gnomes disappear; metronome gnomes restore; saturation back to normal |
| Metronome still works | Play/pause, BPM changes, beat dots animate correctly |

- [ ] **Step 5: Commit validation note**

```bash
git commit --allow-empty -m "chore: final validation pass for tuner gnome line feature"
```

---

## Quick-reference: signal flow

```
User taps Tuner tab
  → UIManager.mode_changed(1)
  → main._on_ui_mode_changed(1)
  → main._enter_tuner_mode()
      → hides _gnomes, calls _rebuild_tuner_gnome_line([])
      → shows _tuner_overlay, starts Tuner.start()

User picks Guitar preset in TunerUI dropdown
  → TunerUI.instrument_changed([40,45,50,55,59,64])
  → main._on_tuner_instrument_changed([40,...])
      → Tuner.set_candidates([40,...])
      → _rebuild_tuner_gnome_line([40,...])  ← 6 gnomes

User clicks gnome[2] (D3)
  → Area3D.input_event → main._on_tuner_gnome_clicked(2)
      → _tuner_selected_idx = 2
      → Tuner.set_candidates([50])   ← locked to D3 only
      → _update_tuner_gnome_highlights()

Tuner detects pitch
  → Tuner.pitch_detected(146.8, "D3", +12.0, 0.92)
  → main._on_tuner_pitch(...)
      → _tuner_ui.set_reading("D3", +12.0, 146.8)
      → _tuner_auto_idx updated
  → _process_tuner(delta) each frame
      → saturation lerp, celebrate timer
      → _apply_gnome_tuning(+12.0) → gnome[2] leans, arm points down
```
