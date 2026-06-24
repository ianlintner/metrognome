class_name TunerUI
extends Control

# Bottom-anchored tuner meter: large note name, a horizontal cents bar with a
# center in-tune zone and a moving needle, a frequency readout, and an instrument
# preset selector. Shown/hidden by UIManager when the Tuner tab is active.

signal instrument_changed(candidate_midis: Array)

const IN_TUNE_CENTS := 5.0
const BAR_WIDTH := 320.0
const BAR_HEIGHT := 54.0

# Visual smoothing: the needle eases toward the latest reading every frame
# (60 fps) instead of snapping on each detection (~8 fps), so it never jumps.
const NEEDLE_TAU := 0.08      # seconds; smaller = snappier, larger = smoother
const LOCK_HOLD := 0.4        # seconds within the in-tune zone before we lock green
# Panel width tracks the viewport so it's wider on wider screens.
const PANEL_WIDTH_FRACTION := 0.5
const PANEL_WIDTH_MIN := 360.0
const PANEL_WIDTH_MAX := 720.0
const PANEL_HEIGHT := 260.0

# Instrument presets: name -> candidate midi note numbers ([] = chromatic).
const PRESETS := [
	{"name": "Chromatic", "midis": []},
	{"name": "Guitar",   "midis": [40, 45, 50, 55, 59, 64]},   # E2 A2 D3 G3 B3 E4
	{"name": "Bass",     "midis": [28, 33, 38, 43]},           # E1 A1 D2 G2
	{"name": "Ukulele",  "midis": [67, 60, 64, 69]},           # G4 C4 E4 A4
	{"name": "Violin",   "midis": [55, 62, 69, 76]},           # G3 D4 A4 E5
]

var _note_label: Label
var _freq_label: Label
var _bar: Control
var _preset_button: OptionButton
var _permission_card: Control

var _display_cents := 0.0    # animated needle position
var _target_cents := 0.0     # latest reading from the smoother
var _has_signal := false
var _lock_timer := 0.0
var _locked := false         # held in the in-tune zone long enough to glow green


func _ready() -> void:
	custom_minimum_size = Vector2(PANEL_WIDTH_MIN, PANEL_HEIGHT)
	size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_STOP
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
	_bar.size_flags_horizontal = Control.SIZE_FILL  # stretch to the panel's width
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
	lbl.text = "Enable microphone access to use the tuner."
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	lbl.add_theme_font_size_override("font_size", 22)
	_permission_card.add_child(lbl)


func _on_preset_selected(index: int) -> void:
	instrument_changed.emit(PRESETS[index].midis)


func _process(delta: float) -> void:
	# Keep the panel width in step with the viewport (wider screen -> wider bar).
	var vw: float = get_viewport_rect().size.x
	custom_minimum_size.x = clampf(vw * PANEL_WIDTH_FRACTION, PANEL_WIDTH_MIN, PANEL_WIDTH_MAX)

	if not _has_signal:
		return

	# Ease the needle toward the latest reading. Frame-rate independent: the
	# fraction covered per frame is 1 - e^(-dt/tau), so motion is identical at
	# any FPS and never snaps even when detections arrive in coarse 0.12 s steps.
	var prev: float = _display_cents
	_display_cents = lerp(_display_cents, _target_cents, 1.0 - exp(-delta / NEEDLE_TAU))

	# In-tune lock: must stay within the zone for LOCK_HOLD before we commit to
	# green, so a transient pass-through doesn't blink the lock on and off.
	if absf(_display_cents) <= IN_TUNE_CENTS:
		_lock_timer += delta
	else:
		_lock_timer = 0.0
	var was_locked: bool = _locked
	_locked = _lock_timer >= LOCK_HOLD

	if _locked != was_locked:
		_note_label.add_theme_color_override(
			"font_color", Color(0.3, 0.9, 0.4) if _locked else Color.WHITE)
	if absf(_display_cents - prev) > 0.02 or _locked != was_locked:
		_bar.queue_redraw()


func set_reading(note_name: String, cents: float, frequency: float) -> void:
	_has_signal = true
	_target_cents = cents
	_note_label.text = note_name
	_freq_label.text = "%.1f Hz   %+d¢" % [frequency, int(round(cents))]


func clear_reading() -> void:
	_has_signal = false
	_display_cents = 0.0
	_target_cents = 0.0
	_lock_timer = 0.0
	_locked = false
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
	# Track background.
	_bar.draw_rect(Rect2(0, cy - 3, w, 6), Color(0.25, 0.25, 0.32))
	# Center in-tune zone highlight.
	var zone_w := w * (IN_TUNE_CENTS / 50.0)
	_bar.draw_rect(Rect2(w * 0.5 - zone_w, cy - 12.0, zone_w * 2.0, 24.0), Color(0.3, 0.9, 0.4, 0.25))
	# Center tick.
	_bar.draw_line(Vector2(w * 0.5, 4.0), Vector2(w * 0.5, h - 4.0), Color(0.5, 0.9, 0.55), 2.0)
	if not _has_signal:
		return
	# Needle: animated cents in [-50, 50] -> x across the bar.
	var t: float = clampf(_display_cents / 50.0, -1.0, 1.0)
	var nx: float = w * 0.5 + t * (w * 0.5)
	var in_tune: bool = absf(_display_cents) <= IN_TUNE_CENTS
	var col: Color = Color(0.3, 0.9, 0.4) if in_tune else Color(0.95, 0.65, 0.2)
	_bar.draw_line(Vector2(nx, 2.0), Vector2(nx, h - 2.0), col, 4.0)
