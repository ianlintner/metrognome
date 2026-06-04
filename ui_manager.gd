extends Control
class_name UIManager

signal bpm_changed(bpm: int)
signal time_signature_changed(beats: int, unit: int)
signal volume_changed(vol: float)
signal play_toggled(playing: bool)
signal sound_changed(sound_type: int)
signal accent_mode_changed(mode: int)
signal character_changed(index: int)

const TIME_SIGNATURES: Array = [
	["2/4", 2, 4], ["3/4", 3, 4], ["4/4", 4, 4],
	["5/4", 5, 4], ["6/8", 6, 8], ["7/8", 7, 8],
]
const SOUND_NAMES: Array = ["Click", "Wood Block", "Beep"]
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

# --- Always-visible bar ---
var _bar: HBoxContainer
var _play_button: Button
var _bpm_minus_btn: Button
var _bpm_plus_btn: Button
var _bpm_value_label: Label
var _beat_dots_container: HBoxContainer
var _beat_dots: Array[ColorRect] = []
var _drawer_toggle: Button

# --- Collapsible drawer ---
var _drawer: VBoxContainer
var _char_scroll: ScrollContainer
var _char_strip: HBoxContainer
var _char_buttons: Array[Button] = []
var _char_group: ButtonGroup
var _bpm_slider: HSlider
var _time_sig_button: OptionButton
var _sound_button: OptionButton
var _accent_button: OptionButton
var _volume_slider: HSlider
var _volume_value_label: Label

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

	_outer = VBoxContainer.new()
	_outer.add_theme_constant_override("separation", 10)
	_outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_outer)

	_build_drawer()   # top (collapsible)
	_build_bar()      # bottom (always visible)

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

	# Character selector — horizontally scrollable strip of toggles.
	_char_scroll = ScrollContainer.new()
	_char_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_char_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_char_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_drawer.add_child(_char_scroll)

	_char_strip = HBoxContainer.new()
	_char_strip.alignment = BoxContainer.ALIGNMENT_CENTER
	_char_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_char_strip.add_theme_constant_override("separation", 10)
	_char_scroll.add_child(_char_strip)

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


func _toggle_drawer() -> void:
	_drawer_open = not _drawer_open
	_drawer_toggle.text = "▼" if _drawer_open else "▲"
	_drawer_toggle.tooltip_text = "Hide controls" if _drawer_open else "Show controls"
	_refresh_panel_height(true)


func _refresh_panel_height(animate: bool) -> void:
	# Panel height = bar (+ drawer when open). Slide offset_top so the bar stays
	# pinned to the bottom and the drawer expands upward.
	_drawer.visible = _drawer_open
	var inset := _bottom_inset()
	var v_pad := int(14.0 * _ui_scale)
	var bar_h := _bar.get_combined_minimum_size().y
	var total := bar_h + v_pad * 2.0 + inset
	if _drawer_open:
		total += _drawer.get_combined_minimum_size().y + _outer.get_theme_constant("separation")

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
		btn.text = String(item.get("name", ""))
		btn.icon = item.get("icon")
		btn.expand_icon = true
		btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		btn.add_theme_color_override("font_color", LABEL_COLOR)
		_style_char_button(btn)
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
	_margin.add_theme_constant_override("margin_left", h_pad)
	_margin.add_theme_constant_override("margin_right", h_pad)
	_margin.add_theme_constant_override("margin_top", v_pad)
	_margin.add_theme_constant_override("margin_bottom", v_pad + inset)
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

	var char_size := int(clampf(72.0 * _ui_scale, 60.0, 96.0))
	var char_label := int(20.0 * _ui_scale)
	for cb in _char_buttons:
		cb.custom_minimum_size = Vector2(char_size, char_size + char_label)
		cb.add_theme_font_size_override("font_size", int(clampf(13.0 * _ui_scale, 12.0, 17.0)))
	# ScrollContainer reports ~0 min height; pin it so the strip isn't clipped.
	_char_scroll.custom_minimum_size = Vector2(0, char_size + char_label + int(8.0 * _ui_scale))


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
