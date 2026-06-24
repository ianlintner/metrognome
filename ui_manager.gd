extends Control
class_name UIManager

signal bpm_changed(bpm: int)
signal time_signature_changed(beats: int, unit: int)
signal volume_changed(vol: float)
signal play_toggled(playing: bool)
signal sound_changed(sound_type: int)
signal accent_mode_changed(mode: int)
signal character_changed(index: int)
signal day_night_changed(time_of_day: int)
signal mode_changed(mode: int)  # 0 = metronome, 1 = tuner

const TIME_SIGNATURES: Array = [
	["2/4", 2, 4], ["3/4", 3, 4], ["4/4", 4, 4],
	["5/4", 5, 4], ["6/8", 6, 8], ["7/8", 7, 8],
]
const SOUND_NAMES: Array = ["Metronome", "Ribbit", "Thump", "Wood Block", "Beep"]
const ACCENT_NAMES: Array = ["Downbeat", "1st & 3rd", "All Even", "None"]

const PANEL_BG_COLOR := Color(0.08, 0.08, 0.1, 0.94)
const LABEL_COLOR := Color(0.85, 0.85, 0.9)
const VALUE_COLOR := Color(1, 1, 1)
const ACCENT_COLOR := Color(0.95, 0.65, 0.2)
const DIM_COLOR := Color(0.25, 0.25, 0.3)
const PLAY_COLOR := Color(0.2, 0.7, 0.3)
const PAUSE_COLOR := Color(0.85, 0.65, 0.2)
const STEP_BTN_COLOR := Color(0.18, 0.20, 0.26)
const TOGGLE_COLOR := Color(0.22, 0.24, 0.30)

const BPM_MIN := 20
const BPM_MAX := 300
# Max width of the control cluster on wide screens (tablet/landscape); the bar
# background still spans full width, but controls center within this column.
const MAX_CONTENT_WIDTH := 720.0

# --- Always-visible bar ---
var _bar: HBoxContainer
var _play_button: Button
var _bpm_minus_btn: Button
var _bpm_plus_btn: Button
var _bpm_value_label: Label
var _beat_dots_container: HBoxContainer
var _beat_dots: Array[ColorRect] = []
var _drawer_toggle: Button
var _daynight_button: Button
var _time_of_day: int = 1  # 0=dawn 1=day 2=dusk 3=night
var _dawn_icon: ImageTexture
var _sun_icon: ImageTexture
var _dusk_icon: ImageTexture
var _moon_icon: ImageTexture
var _icon_layer_overlay: Control  # shared full-viewport overlay for corner icon buttons
var _help_button: Button
var _help_modal: Control

# --- Collapsible drawer ---
var _drawer: VBoxContainer
var _char_strip: HBoxContainer
var _char_buttons: Array[Button] = []
var _char_group: ButtonGroup
var _bpm_slider: HSlider
var _time_sig_button: OptionButton
var _sound_button: OptionButton
var _accent_button: OptionButton
var _volume_slider: HSlider
var _volume_value_label: Label
var _tap_tempo_button: Button

# --- Tap tempo overlay ---
var _tap_overlay: Control
var _tap_bpm_label: Label
var _tap_hint_label: Label
var _tap_times: Array[float] = []

# --- Layout scaffolding ---
var _bg_panel: Panel
var _margin: MarginContainer
var _outer: VBoxContainer
var _all_labels: Array[Label] = []
var _height_tween: Tween

var _is_playing: bool = false
var _drawer_open: bool = false
var _current_beats: int = 4
var _ui_scale: float = 1.0

# --- Tab bar (Metronome | Tuner) ---
var _tab_bar: HBoxContainer
var _metronome_tab: Button
var _tuner_tab: Button
var _mode: int = 0  # 0 = metronome, 1 = tuner


func _ready() -> void:
	# Root spans the full width, pinned to the bottom, growing upward. Only the
	# panel itself captures input so the 3D scene above stays interactive.
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_bg_panel = Panel.new()
	_bg_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	_bg_panel.add_theme_stylebox_override("panel", style)
	add_child(_bg_panel)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bg_panel.add_child(_margin)

	# The control column fills _margin; _margin's left/right margins are computed
	# in _apply_responsive_layout to center a width-capped column on wide screens.
	_outer = VBoxContainer.new()
	_outer.add_theme_constant_override("separation", 10)
	_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_outer)

	_build_tabs()              # top Metronome|Tuner segmented control
	_build_drawer()            # top (collapsible)
	_build_bar()               # bottom (always visible)
	_build_daynight_overlay()  # icon pinned to top-right corner (also creates _icon_layer_overlay)
	_build_help_button()       # ? icon pinned to top-left corner (reuses _icon_layer_overlay)
	_build_tap_overlay()       # full-screen tap tempo mode (layer 2)
	_build_help_modal()        # full-screen help modal (layer 3)


	_create_beat_dots(4)
	_update_play_button_style()
	_drawer.visible = false
	_apply_responsive_layout()
	_refresh_panel_height(false)
	get_viewport().size_changed.connect(_on_viewport_resized)


# ---------------------------------------------------------------------------
# Always-visible bar
# ---------------------------------------------------------------------------
func _build_bar() -> void:
	_bar = HBoxContainer.new()
	_bar.add_theme_constant_override("separation", 12)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outer.add_child(_bar)

	# Primary CTA — biggest, leftmost, always reachable.
	_play_button = Button.new()
	_play_button.text = "▶  Play"
	_play_button.focus_mode = Control.FOCUS_NONE
	_play_button.pressed.connect(_on_play_pressed)
	_bar.add_child(_play_button)

	# Center cluster: BPM steppers + readout + beat dots, expands to fill.
	var center := HBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 12)
	_bar.add_child(center)

	_bpm_minus_btn = _make_step_button("−")
	_bpm_minus_btn.pressed.connect(func(): _nudge_bpm(-1))
	center.add_child(_bpm_minus_btn)

	var bpm_box := VBoxContainer.new()
	bpm_box.alignment = BoxContainer.ALIGNMENT_CENTER
	bpm_box.add_theme_constant_override("separation", 0)
	center.add_child(bpm_box)

	_bpm_value_label = _make_label("120")
	_bpm_value_label.add_theme_color_override("font_color", VALUE_COLOR)
	_bpm_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bpm_box.add_child(_bpm_value_label)

	var bpm_caption := _make_label("BPM")
	bpm_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bpm_caption.modulate = Color(1, 1, 1, 0.6)
	bpm_box.add_child(bpm_caption)

	_bpm_plus_btn = _make_step_button("+")
	_bpm_plus_btn.pressed.connect(func(): _nudge_bpm(1))
	center.add_child(_bpm_plus_btn)

	_beat_dots_container = HBoxContainer.new()
	_beat_dots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_beat_dots_container.add_theme_constant_override("separation", 8)
	center.add_child(_beat_dots_container)

	# Drawer toggle — rightmost, always reachable.
	_drawer_toggle = Button.new()
	_drawer_toggle.text = "▲"
	_drawer_toggle.focus_mode = Control.FOCUS_NONE
	_drawer_toggle.tooltip_text = "Show controls"
	var ts := StyleBoxFlat.new()
	ts.bg_color = TOGGLE_COLOR
	ts.set_corner_radius_all(14)
	_drawer_toggle.add_theme_stylebox_override("normal", ts)
	_drawer_toggle.add_theme_color_override("font_color", Color.WHITE)
	_drawer_toggle.pressed.connect(_toggle_drawer)
	_bar.add_child(_drawer_toggle)


# ---------------------------------------------------------------------------
# Collapsible drawer
# ---------------------------------------------------------------------------
func _build_drawer() -> void:
	_drawer = VBoxContainer.new()
	_drawer.add_theme_constant_override("separation", 10)
	_drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outer.add_child(_drawer)

	# Character selector — a centered strip of toggles. (A ScrollContainer would
	# left-align the cards even when they fit; a plain HBox with alignment CENTER
	# keeps them centered. The roster is small enough to fit without scrolling.)
	_char_strip = HBoxContainer.new()
	_char_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_char_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_strip.add_theme_constant_override("separation", 10)
	_drawer.add_child(_char_strip)

	# BPM fine slider.
	_bpm_slider = HSlider.new()
	_bpm_slider.min_value = BPM_MIN
	_bpm_slider.max_value = BPM_MAX
	_bpm_slider.value = 120
	_bpm_slider.step = 1
	_bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bpm_slider.value_changed.connect(_on_bpm_slider_changed)
	_drawer.add_child(_bpm_slider)

	# Selectors — wide row in landscape, three equal columns.
	var selectors := HBoxContainer.new()
	selectors.add_theme_constant_override("separation", 8)
	_drawer.add_child(selectors)

	_time_sig_button = OptionButton.new()
	for ts in TIME_SIGNATURES:
		_time_sig_button.add_item(ts[0])
	_time_sig_button.selected = 2
	_time_sig_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_sig_button.item_selected.connect(_on_time_sig_changed)
	selectors.add_child(_time_sig_button)

	_sound_button = OptionButton.new()
	for s in SOUND_NAMES:
		_sound_button.add_item(s)
	_sound_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_button.item_selected.connect(_on_sound_changed)
	selectors.add_child(_sound_button)

	_accent_button = OptionButton.new()
	for a in ACCENT_NAMES:
		_accent_button.add_item(a)
	_accent_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accent_button.item_selected.connect(_on_accent_changed)
	selectors.add_child(_accent_button)

	# Volume row.
	var vol_row := HBoxContainer.new()
	vol_row.add_theme_constant_override("separation", 10)
	_drawer.add_child(vol_row)

	var vol_caption := _make_label("Vol")
	vol_row.add_child(vol_caption)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.value = 80
	_volume_slider.step = 1
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	vol_row.add_child(_volume_slider)

	_volume_value_label = _make_label("80%")
	_volume_value_label.add_theme_color_override("font_color", VALUE_COLOR)
	vol_row.add_child(_volume_value_label)

	# Tap Tempo button — full width, bottom of drawer.
	_tap_tempo_button = Button.new()
	_tap_tempo_button.text = "Tap Tempo"
	_tap_tempo_button.focus_mode = Control.FOCUS_NONE
	_tap_tempo_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tt_style := StyleBoxFlat.new()
	tt_style.bg_color = Color(0.18, 0.22, 0.32)
	tt_style.set_corner_radius_all(14)
	_tap_tempo_button.add_theme_stylebox_override("normal", tt_style)
	var tt_hover := StyleBoxFlat.new()
	tt_hover.bg_color = Color(0.25, 0.32, 0.48)
	tt_hover.set_corner_radius_all(14)
	_tap_tempo_button.add_theme_stylebox_override("hover", tt_hover)
	_tap_tempo_button.add_theme_color_override("font_color", Color(0.85, 0.9, 1.0))
	_tap_tempo_button.pressed.connect(_show_tap_overlay)
	_drawer.add_child(_tap_tempo_button)


# ---------------------------------------------------------------------------
# Top-right day/night icon overlay
# ---------------------------------------------------------------------------
func _build_daynight_overlay() -> void:
	_dawn_icon = _make_sun_icon(Color(1.0, 0.72, 0.40))
	_sun_icon  = _make_sun_icon(Color(1.0, 0.82, 0.28))
	_dusk_icon = _make_sun_icon(Color(1.0, 0.48, 0.18))
	_moon_icon = _make_moon_icon()

	# Use a child CanvasLayer so the overlay spans the full viewport regardless
	# of UIManager's own PRESET_BOTTOM_WIDE rect.
	var layer := CanvasLayer.new()
	layer.layer = 1  # above the main UI (layer 0), below the title splash (layer 100)
	add_child(layer)

	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(overlay)
	_icon_layer_overlay = overlay  # shared with _build_help_button()

	_daynight_button = Button.new()
	_daynight_button.flat = true
	_daynight_button.focus_mode = Control.FOCUS_NONE
	_daynight_button.expand_icon = true
	_daynight_button.tooltip_text = "Change time of day"
	_daynight_button.pressed.connect(_on_daynight_pressed)

	# Subtle semi-transparent disc so the icon reads against any sky color.
	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.28 if state_name == "normal" else 0.45)
		sb.set_corner_radius_all(100)
		sb.set_content_margin_all(0)
		_daynight_button.add_theme_stylebox_override(state_name, sb)

	# Anchor to top-right; exact offsets tuned in _apply_responsive_layout.
	_daynight_button.anchor_left = 1.0
	_daynight_button.anchor_right = 1.0
	_daynight_button.anchor_top = 0.0
	_daynight_button.anchor_bottom = 0.0
	_daynight_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_daynight_button.grow_vertical = Control.GROW_DIRECTION_END

	overlay.add_child(_daynight_button)
	_update_daynight_icon()


# ---------------------------------------------------------------------------
# Tap tempo overlay  (CanvasLayer layer 2 — above day/night icon at layer 1)
# ---------------------------------------------------------------------------
func _build_tap_overlay() -> void:
	var tap_layer := CanvasLayer.new()
	tap_layer.layer = 2
	add_child(tap_layer)

	_tap_overlay = Control.new()
	_tap_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tap_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_tap_overlay.visible = false
	_tap_overlay.gui_input.connect(_on_tap_input)
	tap_layer.add_child(_tap_overlay)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.08, 0.88)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_overlay.add_child(bg)

	# "Done" button — top-left, always reachable
	var close_btn := Button.new()
	close_btn.text = "✕  Done"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.anchor_left = 0.0
	close_btn.anchor_right = 0.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = 20.0
	close_btn.offset_top = 20.0
	close_btn.offset_right = 180.0
	close_btn.offset_bottom = 68.0
	close_btn.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	close_btn.add_theme_font_size_override("font_size", 22)
	close_btn.pressed.connect(_hide_tap_overlay)
	_tap_overlay.add_child(close_btn)

	# Centered column: title, big BPM number, unit label, hint
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_overlay.add_child(center)

	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 16)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(col)

	var title_lbl := Label.new()
	title_lbl.text = "TAP TEMPO"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title_lbl)

	_tap_bpm_label = Label.new()
	_tap_bpm_label.text = "---"
	_tap_bpm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap_bpm_label.add_theme_color_override("font_color", Color.WHITE)
	_tap_bpm_label.add_theme_font_size_override("font_size", 112)
	_tap_bpm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tap_bpm_label)

	var unit_lbl := Label.new()
	unit_lbl.text = "BPM"
	unit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	unit_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	unit_lbl.add_theme_font_size_override("font_size", 26)
	unit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(unit_lbl)

	_tap_hint_label = Label.new()
	_tap_hint_label.text = "Tap anywhere to set tempo"
	_tap_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tap_hint_label.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_tap_hint_label.add_theme_font_size_override("font_size", 20)
	_tap_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(_tap_hint_label)


# ---------------------------------------------------------------------------
# Top-left help icon button  (reuses _icon_layer_overlay from day/night)
# ---------------------------------------------------------------------------
func _build_help_button() -> void:
	_help_button = Button.new()
	_help_button.text = "?"
	_help_button.flat = true
	_help_button.focus_mode = Control.FOCUS_NONE
	_help_button.tooltip_text = "Help"
	_help_button.pressed.connect(_show_help_modal)

	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.0, 0.0, 0.0, 0.28 if state_name == "normal" else 0.45)
		sb.set_corner_radius_all(100)
		sb.set_content_margin_all(0)
		_help_button.add_theme_stylebox_override(state_name, sb)

	# Anchor to top-left; exact offsets tuned in _apply_responsive_layout.
	_help_button.anchor_left = 0.0
	_help_button.anchor_right = 0.0
	_help_button.anchor_top = 0.0
	_help_button.anchor_bottom = 0.0
	_help_button.grow_horizontal = Control.GROW_DIRECTION_END
	_help_button.grow_vertical = Control.GROW_DIRECTION_END
	_help_button.add_theme_color_override("font_color", Color(0.88, 0.88, 1.0))

	_icon_layer_overlay.add_child(_help_button)


# ---------------------------------------------------------------------------
# Full-screen help modal  (CanvasLayer layer 3 — above everything)
# ---------------------------------------------------------------------------
func _build_help_modal() -> void:
	var help_layer := CanvasLayer.new()
	help_layer.layer = 3
	add_child(help_layer)

	_help_modal = Control.new()
	_help_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_help_modal.visible = false
	help_layer.add_child(_help_modal)

	# Dark backdrop
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.0, 0.02, 0.08, 0.92)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_modal.add_child(bg)

	# Card panel — inset from all edges to give a floating sheet feel.
	var card := Panel.new()
	card.anchor_left = 0.04
	card.anchor_right = 0.96
	card.anchor_top = 0.05
	card.anchor_bottom = 0.95
	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.08, 0.09, 0.15, 0.98)
	card_style.set_corner_radius_all(20)
	card_style.set_content_margin_all(0)
	card.add_theme_stylebox_override("panel", card_style)
	_help_modal.add_child(card)

	var inner := MarginContainer.new()
	inner.set_anchors_preset(Control.PRESET_FULL_RECT)
	inner.add_theme_constant_override("margin_left", 24)
	inner.add_theme_constant_override("margin_right", 24)
	inner.add_theme_constant_override("margin_top", 20)
	inner.add_theme_constant_override("margin_bottom", 20)
	card.add_child(inner)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	inner.add_child(col)

	# Title row with close button
	var title_row := HBoxContainer.new()
	col.add_child(title_row)

	var title_lbl := Label.new()
	title_lbl.text = "HOW TO PLAY"
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.add_theme_color_override("font_color", ACCENT_COLOR)
	title_lbl.add_theme_font_size_override("font_size", 26)
	title_row.add_child(title_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.flat = true
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	close_btn.add_theme_font_size_override("font_size", 26)
	close_btn.pressed.connect(_hide_help_modal)
	title_row.add_child(close_btn)

	var sep := HSeparator.new()
	sep.modulate = Color(1.0, 1.0, 1.0, 0.15)
	col.add_child(sep)

	# Scrollable content area — takes all remaining vertical space.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 4)
	scroll.add_child(entries)

	# ── Main bar ──────────────────────────────────────────────────────────
	_add_help_section(entries, "MAIN BAR")
	_add_help_entry(entries, "▶ Play / ▌▌ Pause",
		"Starts and stops the metronome")
	_add_help_entry(entries, "−  /  +",
		"Nudge the BPM down or up by one step")
	_add_help_entry(entries, "BPM readout",
		"Current tempo — open the drawer to fine-tune with the slider")
	_add_help_entry(entries, "Beat dots",
		"Pulses on every beat; the gold dot marks the accented beat")
	_add_help_entry(entries, "▲  /  ▼",
		"Opens and closes the settings drawer")

	# ── Settings drawer ───────────────────────────────────────────────────
	_add_help_section(entries, "SETTINGS DRAWER  (tap ▲)")
	_add_help_entry(entries, "Character cards",
		"Choose Gnome, Frog, or Beaver — each has a distinct click sound")
	_add_help_entry(entries, "BPM slider",
		"Fine-tune the tempo from 20 to 300 BPM")
	_add_help_entry(entries, "Time Signature",
		"2/4 · 3/4 · 4/4 · 5/4 · 6/8 · 7/8")
	_add_help_entry(entries, "Sound",
		"Click voice: Metronome, Ribbit, Thump, Wood Block, or Beep")
	_add_help_entry(entries, "Accent",
		"Which beats are emphasized: Downbeat, 1st & 3rd, All Even, or None")
	_add_help_entry(entries, "Volume",
		"Master volume for all sounds")
	_add_help_entry(entries, "Tap Tempo",
		"Opens a full-screen overlay — tap anywhere to set BPM by feel; uses a rolling average of your last 8 taps")

	# ── Corner icons ──────────────────────────────────────────────────────
	_add_help_section(entries, "CORNER ICONS")
	_add_help_entry(entries, "Time-of-day  (top right)",
		"Cycles Dawn → Day → Dusk → Night; auto-set from your device clock on launch")
	_add_help_entry(entries, "Help  (top left)",
		"This screen")


func _add_help_section(parent: VBoxContainer, title: String) -> void:
	# Spacer before section header (skip for the very first one).
	if parent.get_child_count() > 0:
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 10)
		parent.add_child(spacer)

	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_color_override("font_color", Color(0.55, 0.65, 0.85))
	lbl.add_theme_font_size_override("font_size", 13)
	parent.add_child(lbl)

	var rule := HSeparator.new()
	rule.modulate = Color(1.0, 1.0, 1.0, 0.10)
	parent.add_child(rule)


func _add_help_entry(parent: VBoxContainer, ctrl_text: String, desc_text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	parent.add_child(row)

	var ctrl_lbl := Label.new()
	ctrl_lbl.text = ctrl_text
	ctrl_lbl.custom_minimum_size = Vector2(130, 0)
	ctrl_lbl.size_flags_horizontal = Control.SIZE_FILL
	ctrl_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl_lbl.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	ctrl_lbl.add_theme_font_size_override("font_size", 15)
	row.add_child(ctrl_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = desc_text
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.84))
	desc_lbl.add_theme_font_size_override("font_size", 14)
	row.add_child(desc_lbl)


func _show_help_modal() -> void:
	_help_modal.visible = true


func _hide_help_modal() -> void:
	_help_modal.visible = false


func _show_tap_overlay() -> void:
	_tap_times.clear()
	_tap_bpm_label.text = "---"
	_tap_hint_label.text = "Tap anywhere to set tempo"
	_tap_overlay.visible = true
	if not _is_playing:
		_on_play_pressed()


func _hide_tap_overlay() -> void:
	_tap_overlay.visible = false


func _on_tap_input(event: InputEvent) -> void:
	var pressed := false
	if event is InputEventMouseButton:
		pressed = (event as InputEventMouseButton).pressed
	elif event is InputEventScreenTouch:
		pressed = (event as InputEventScreenTouch).pressed
	if pressed:
		_register_tap()


func _register_tap() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	# Reset if the user paused for more than 3 seconds
	if _tap_times.size() > 0 and (now - _tap_times.back()) > 3.0:
		_tap_times.clear()
	_tap_times.append(now)
	while _tap_times.size() > 8:
		_tap_times.remove_at(0)

	# Flash the BPM number on each tap
	var tw := create_tween()
	tw.tween_property(_tap_bpm_label, "modulate", Color(ACCENT_COLOR.r, ACCENT_COLOR.g, ACCENT_COLOR.b), 0.0)
	tw.tween_property(_tap_bpm_label, "modulate", Color.WHITE, 0.18)

	if _tap_times.size() < 2:
		_tap_hint_label.text = "Keep tapping..."
		return

	var bpm := _calculate_tap_bpm()
	_tap_bpm_label.text = str(bpm)
	_tap_hint_label.text = "Tap to refine"
	# Drive slider → triggers _on_bpm_slider_changed → updates label + emits bpm_changed
	_bpm_slider.value = float(bpm)


func _calculate_tap_bpm() -> int:
	if _tap_times.size() < 2:
		return 120
	var total_interval: float = float(_tap_times.back()) - float(_tap_times.front())
	var avg_interval: float = total_interval / float(_tap_times.size() - 1)
	if avg_interval <= 0.0:
		return 120
	return clamp(int(round(60.0 / avg_interval)), BPM_MIN, BPM_MAX)


func _on_daynight_pressed() -> void:
	_time_of_day = (_time_of_day + 1) % 4
	_update_daynight_icon()
	day_night_changed.emit(_time_of_day)


# Called by main to sync the button with the clock-derived starting state.
func set_day_night(tod: int) -> void:
	_time_of_day = clamp(tod, 0, 3)
	_update_daynight_icon()


func _update_daynight_icon() -> void:
	if _daynight_button == null:
		return
	var icons: Array = [_dawn_icon, _sun_icon, _dusk_icon, _moon_icon]
	var tips: Array  = ["Dawn", "Day", "Dusk", "Night"]
	_daynight_button.icon = icons[_time_of_day]
	_daynight_button.tooltip_text = tips[_time_of_day]


# Procedurally drawn sun icon (disc + 8 rays). Pass a tint to get dawn/day/dusk variants.
func _make_sun_icon(tint: Color = Color(1.0, 0.82, 0.28)) -> ImageTexture:
	var s := 96
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(s / 2.0, s / 2.0)
	var core := s * 0.24
	var ray_in := s * 0.30
	var ray_out := s * 0.47
	var gold := tint
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := p.distance_to(c)
			var lit := false
			if d <= core:
				lit = true
			elif d >= ray_in and d <= ray_out:
				var seg: float = fposmod((p - c).angle(), PI / 4.0)
				if seg < 0.20 or seg > (PI / 4.0 - 0.20):
					lit = true
			if lit:
				img.set_pixel(x, y, gold)
	return ImageTexture.create_from_image(img)


# Crescent moon = pale disc with an offset disc subtracted.
func _make_moon_icon() -> ImageTexture:
	var s := 96
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var r := s * 0.36
	var c1 := Vector2(s * 0.46, s * 0.52)
	var c2 := Vector2(s * 0.64, s * 0.40)
	var pale := Color(0.95, 0.95, 0.82)
	for y in s:
		for x in s:
			var p := Vector2(x + 0.5, y + 0.5)
			if p.distance_to(c1) <= r and p.distance_to(c2) > r * 1.04:
				img.set_pixel(x, y, pale)
	return ImageTexture.create_from_image(img)


func _toggle_drawer() -> void:
	_drawer_open = not _drawer_open
	_drawer_toggle.text = "▼" if _drawer_open else "▲"
	_drawer_toggle.tooltip_text = "Hide controls" if _drawer_open else "Show controls"
	_refresh_panel_height(true)


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


# ---------------------------------------------------------------------------
# Character strip (populated by main.gd)
# ---------------------------------------------------------------------------
func set_characters(items: Array, active: int) -> void:
	for b in _char_buttons:
		b.queue_free()
	_char_buttons.clear()
	_char_group = ButtonGroup.new()

	for i in items.size():
		var item: Dictionary = items[i]
		var btn := Button.new()
		btn.toggle_mode = true
		btn.button_group = _char_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = String(item.get("name", ""))
		btn.clip_contents = true
		_style_char_button(btn)

		# Card content: big icon filling the top, name caption underneath. The
		# VBox fills the button and ignores the mouse so clicks reach the button.
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 2)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 6)
		btn.add_child(box)

		var pic := TextureRect.new()
		pic.texture = item.get("icon")
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(pic)

		var lbl := Label.new()
		lbl.text = String(item.get("name", ""))
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_color_override("font_color", LABEL_COLOR)
		box.add_child(lbl)

		btn.set_meta("pic", pic)
		btn.set_meta("lbl", lbl)
		if i == active:
			btn.button_pressed = true
		var idx := i
		btn.pressed.connect(func(): character_changed.emit(idx))
		_char_strip.add_child(btn)
		_char_buttons.append(btn)

	if is_inside_tree():
		_apply_responsive_layout()
		_refresh_panel_height(false)


func _style_char_button(btn: Button) -> void:
	for state_name in ["normal", "hover", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = STEP_BTN_COLOR
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(6)
		btn.add_theme_stylebox_override(state_name, sb)
	var on := StyleBoxFlat.new()
	on.bg_color = Color(STEP_BTN_COLOR.r * 1.4, STEP_BTN_COLOR.g * 1.4, STEP_BTN_COLOR.b * 1.6)
	on.set_corner_radius_all(14)
	on.set_content_margin_all(6)
	on.set_border_width_all(3)
	on.border_color = ACCENT_COLOR
	btn.add_theme_stylebox_override("pressed", on)


# ---------------------------------------------------------------------------
# Responsive layout
# ---------------------------------------------------------------------------
func _on_viewport_resized() -> void:
	_apply_responsive_layout()
	_refresh_panel_height(false)


func _apply_responsive_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var is_portrait: bool = vp.y > vp.x

	# Portrait scales by width, landscape by height — keeps touch targets sane.
	if is_portrait:
		_ui_scale = clampf(vp.x / 720.0, 0.85, 1.5)
	else:
		_ui_scale = clampf(vp.y / 720.0, 0.7, 1.25)

	var inset := _bottom_inset()
	var h_pad := int(20.0 * _ui_scale)
	var v_pad := int(14.0 * _ui_scale)
	# On wide screens (tablets / landscape) the dark bar still spans the full
	# bottom edge, but the controls are centered in a capped-width column so they
	# don't stretch awkwardly across the whole display. On phones it fills width.
	# Center a width-capped column via symmetric margins computed from the actual
	# viewport width. On phones the column is ~full width; on tablets/landscape it
	# stays a tidy centered column instead of stretching edge to edge.
	var col := minf(vp.x - 2.0 * h_pad, MAX_CONTENT_WIDTH)
	var side := int(maxf(float(h_pad), (vp.x - col) / 2.0))
	_margin.add_theme_constant_override("margin_left", side)
	_margin.add_theme_constant_override("margin_right", side)
	_margin.add_theme_constant_override("margin_top", v_pad)
	# Lift the bar clear of the curved bottom / home indicator: honor the safe-area
	# inset (with a sensible floor in case iOS under-reports) plus extra breathing room.
	var bottom_gap := v_pad + maxi(inset, int(20.0 * _ui_scale)) + int(16.0 * _ui_scale)
	_margin.add_theme_constant_override("margin_bottom", bottom_gap)
	_outer.custom_minimum_size.x = 0  # fill the centered column
	_outer.add_theme_constant_override("separation", int(10.0 * _ui_scale))
	_drawer.add_theme_constant_override("separation", int(10.0 * _ui_scale))

	var label_fs := int(clampf(16.0 * _ui_scale, 15.0, 22.0))
	for lbl in _all_labels:
		lbl.add_theme_font_size_override("font_size", label_fs)

	# Bar height — short in landscape, a touch taller in portrait.
	var bar_h := int(clampf((78.0 if is_portrait else 70.0) * _ui_scale, 64.0, 104.0))

	# Play button — dominant width, full bar height.
	_play_button.custom_minimum_size = Vector2(bar_h * 2.4, bar_h)
	_play_button.add_theme_font_size_override("font_size", int(clampf(24.0 * _ui_scale, 20.0, 34.0)))
	_update_play_button_style()

	# BPM steppers — square, bar height.
	var step := int(bar_h * 0.86)
	for b: Button in [_bpm_minus_btn, _bpm_plus_btn]:
		b.custom_minimum_size = Vector2(step, step)
		b.add_theme_font_size_override("font_size", int(step * 0.5))
	_bpm_value_label.add_theme_font_size_override("font_size", int(clampf(34.0 * _ui_scale, 28.0, 46.0)))

	# Drawer toggle — square.
	_drawer_toggle.custom_minimum_size = Vector2(bar_h, bar_h)
	_drawer_toggle.add_theme_font_size_override("font_size", int(bar_h * 0.34))

	# Beat dots.
	var dot := int(clampf(20.0 * _ui_scale, 16.0, 30.0))
	for d in _beat_dots:
		d.custom_minimum_size = Vector2(dot, dot)
	_beat_dots_container.add_theme_constant_override("separation", int(8.0 * _ui_scale))

	# Drawer controls.
	var tap_h := int(clampf(54.0 * _ui_scale, 48.0, 68.0))
	for btn: OptionButton in [_time_sig_button, _sound_button, _accent_button]:
		btn.custom_minimum_size = Vector2(0, tap_h)
		btn.add_theme_font_size_override("font_size", int(label_fs * 1.05))

	var grab_h := int(clampf(40.0 * _ui_scale, 34.0, 56.0))
	for sl: HSlider in [_bpm_slider, _volume_slider]:
		sl.custom_minimum_size = Vector2(0, grab_h)
		sl.add_theme_constant_override("grab_height", grab_h)
		_style_slider(sl, grab_h)
	_volume_value_label.custom_minimum_size = Vector2(int(54.0 * _ui_scale), 0)

	# Character cards: portrait shape, big icon on top, name caption below.
	var card_w := int(clampf(90.0 * _ui_scale, 78.0, 124.0))
	var card_h := int(card_w * 1.28)
	var clbl := int(clampf(15.0 * _ui_scale, 13.0, 19.0))
	for cb in _char_buttons:
		cb.custom_minimum_size = Vector2(card_w, card_h)
		var lbl = cb.get_meta("lbl") if cb.has_meta("lbl") else null
		if lbl != null:
			(lbl as Label).add_theme_font_size_override("font_size", clbl)
		var pic = cb.get_meta("pic") if cb.has_meta("pic") else null
		if pic != null:
			(pic as TextureRect).custom_minimum_size = Vector2(0, card_h - clbl - 18)
	# Pin the strip height so the cards aren't clipped.
	_char_strip.custom_minimum_size = Vector2(0, card_h + int(8.0 * _ui_scale))

	# Tap Tempo button — same height as option buttons.
	if _tap_tempo_button != null:
		_tap_tempo_button.custom_minimum_size = Vector2(0, tap_h)
		_tap_tempo_button.add_theme_font_size_override("font_size", int(label_fs * 1.05))

	# Day/night icon — top-right corner overlay, scaled with the UI.
	if _daynight_button != null:
		var icon_sz := int(clampf(56.0 * _ui_scale, 48.0, 72.0))
		var margin  := int(clampf(12.0 * _ui_scale, 8.0, 18.0))
		_daynight_button.offset_right  = -float(margin)
		_daynight_button.offset_left   = -(float(icon_sz) + float(margin))
		_daynight_button.offset_top    = float(margin)
		_daynight_button.offset_bottom = float(icon_sz) + float(margin)

	# Help icon — top-left corner overlay, same scale as day/night button.
	if _help_button != null:
		var icon_sz := int(clampf(56.0 * _ui_scale, 48.0, 72.0))
		var margin  := int(clampf(12.0 * _ui_scale, 8.0, 18.0))
		_help_button.offset_left   = float(margin)
		_help_button.offset_right  = float(icon_sz) + float(margin)
		_help_button.offset_top    = float(margin)
		_help_button.offset_bottom = float(icon_sz) + float(margin)
		_help_button.add_theme_font_size_override("font_size", int(icon_sz * 0.52))


func _bottom_inset() -> int:
	var vp := get_viewport().get_visible_rect().size
	var safe := DisplayServer.get_display_safe_area()
	return maxi(0, int(vp.y - (safe.position.y + safe.size.y)))


# ---------------------------------------------------------------------------
# Shared widget helpers
# ---------------------------------------------------------------------------
func _style_slider(slider: HSlider, grab_h: int) -> void:
	var r := int(grab_h / 2.0)
	var grabber := StyleBoxFlat.new()
	grabber.bg_color = Color(0.95, 0.95, 0.98)
	grabber.set_corner_radius_all(r)
	grabber.set_content_margin_all(r)
	slider.add_theme_stylebox_override("grabber_area", grabber)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.22, 0.28)
	track.set_corner_radius_all(6)
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT_COLOR
	fill.set_corner_radius_all(6)
	fill.content_margin_top = 6
	fill.content_margin_bottom = 6
	slider.add_theme_stylebox_override("grabber_area_highlight", fill)


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 16)
	_all_labels.append(label)
	return label


func _make_step_button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	var sb := StyleBoxFlat.new()
	sb.bg_color = STEP_BTN_COLOR
	sb.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("normal", sb)
	var sb_p := StyleBoxFlat.new()
	sb_p.bg_color = Color(STEP_BTN_COLOR.r * 1.5, STEP_BTN_COLOR.g * 1.5, STEP_BTN_COLOR.b * 1.5)
	sb_p.set_corner_radius_all(14)
	btn.add_theme_stylebox_override("pressed", sb_p)
	btn.add_theme_stylebox_override("hover", sb_p)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn


func _create_beat_dots(count: int) -> void:
	for dot in _beat_dots:
		dot.queue_free()
	_beat_dots.clear()
	for i in count:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(20, 20)
		dot.color = ACCENT_COLOR if i == 0 else DIM_COLOR
		_beat_dots.append(dot)
		_beat_dots_container.add_child(dot)
	if is_inside_tree():
		_apply_responsive_layout()
		_refresh_panel_height(false)


func on_tick(beat: int, _total_beats: int) -> void:
	for i in _beat_dots.size():
		_beat_dots[i].color = ACCENT_COLOR if i == beat else DIM_COLOR


func _nudge_bpm(delta: int) -> void:
	_bpm_slider.value = clampi(int(_bpm_slider.value) + delta, BPM_MIN, BPM_MAX)


func _on_bpm_slider_changed(value: float) -> void:
	var b := int(value)
	_bpm_value_label.text = str(b)
	bpm_changed.emit(b)


func _on_time_sig_changed(index: int) -> void:
	if index < 0 or index >= TIME_SIGNATURES.size():
		return
	var ts: Array = TIME_SIGNATURES[index]
	_current_beats = ts[1]
	_create_beat_dots(ts[1])
	time_signature_changed.emit(ts[1], ts[2])


func _on_sound_changed(index: int) -> void:
	sound_changed.emit(index)


# Set the sound selector to a given index without re-emitting (used when a
# character switch changes the default sound).
func set_sound_selection(index: int) -> void:
	if _sound_button != null and index >= 0 and index < _sound_button.item_count:
		_sound_button.selected = index


func _on_accent_changed(index: int) -> void:
	accent_mode_changed.emit(index)


func _on_volume_changed(value: float) -> void:
	var pct := int(value)
	_volume_value_label.text = "%d%%" % pct
	volume_changed.emit(pct / 100.0)


func _on_play_pressed() -> void:
	_is_playing = not _is_playing
	_play_button.text = "▌▌  Pause" if _is_playing else "▶  Play"
	_update_play_button_style()
	play_toggled.emit(_is_playing)


func _update_play_button_style() -> void:
	var base: Color = PAUSE_COLOR if _is_playing else PLAY_COLOR
	for state_name in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		var mult := 1.0
		if state_name == "hover":
			mult = 0.85
		elif state_name == "pressed":
			mult = 0.7
		sb.bg_color = Color(base.r * mult, base.g * mult, base.b * mult)
		sb.set_corner_radius_all(16)
		_play_button.add_theme_stylebox_override(state_name, sb)
	_play_button.add_theme_color_override("font_color", Color.WHITE)


# ---------------------------------------------------------------------------
# Tab bar — Metronome | Tuner
# ---------------------------------------------------------------------------
func _build_tabs() -> void:
	_tab_bar = HBoxContainer.new()
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_tab_bar.add_theme_constant_override("separation", 4)
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
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(120, 36)
	btn.add_theme_font_size_override("font_size", 16)
	return btn


func _update_tab_styles() -> void:
	for info: Array in [[_metronome_tab, 0], [_tuner_tab, 1]]:
		var btn: Button = info[0]
		var idx: int = info[1]
		var active := (_mode == idx)
		for state_name in ["normal", "hover", "pressed"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = ACCENT_COLOR if active else STEP_BTN_COLOR
			sb.set_corner_radius_all(10)
			btn.add_theme_stylebox_override(state_name, sb)
		btn.add_theme_color_override("font_color", Color.WHITE if active else LABEL_COLOR)


func _set_mode(mode: int) -> void:
	_mode = mode
	_update_tab_styles()
	_refresh_panel_height(true)
	mode_changed.emit(mode)


# Stub retained for compatibility until Task C removes the call from main.gd.
# TunerUI is no longer owned by UIManager; it lives on a CanvasLayer in main.gd.
func get_tuner_ui() -> Control:
	return null


func force_paused() -> void:
	if _is_playing:
		_is_playing = false
		_play_button.text = "▶  Play"
		_update_play_button_style()
		play_toggled.emit(false)
