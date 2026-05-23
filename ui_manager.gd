extends Control
class_name UIManager

signal bpm_changed(bpm: int)
signal time_signature_changed(beats: int, unit: int)
signal volume_changed(vol: float)
signal play_toggled(playing: bool)
signal sound_changed(sound_type: int)
signal accent_mode_changed(mode: int)

const TIME_SIGNATURES: Array = [
	["2/4", 2, 4],
	["3/4", 3, 4],
	["4/4", 4, 4],
	["5/4", 5, 4],
	["6/8", 6, 8],
	["7/8", 7, 8],
]
const SOUND_NAMES: Array = ["Click", "Wood Block", "Beep"]
const ACCENT_NAMES: Array = ["Downbeat", "1st & 3rd", "All Even", "None"]

const PANEL_BG_COLOR := Color(0.08, 0.08, 0.1, 0.92)
const LABEL_COLOR := Color(0.85, 0.85, 0.9)
const VALUE_COLOR := Color(1, 1, 1)
const ACCENT_COLOR := Color(0.95, 0.65, 0.2)
const DIM_COLOR := Color(0.25, 0.25, 0.3)
const PLAY_COLOR := Color(0.2, 0.7, 0.3)
const PAUSE_COLOR := Color(0.85, 0.65, 0.2)
const STEP_BTN_COLOR := Color(0.18, 0.20, 0.26)

const BPM_MIN := 20
const BPM_MAX := 300

var _bpm_slider: HSlider
var _bpm_value_label: Label
var _bpm_minus_btn: Button
var _bpm_plus_btn: Button
var _time_sig_button: OptionButton
var _sound_button: OptionButton
var _accent_button: OptionButton
var _volume_slider: HSlider
var _volume_value_label: Label
var _play_button: Button
var _beat_dots_container: HBoxContainer
var _beat_dots: Array[ColorRect] = []

var _margin: MarginContainer
var _root_vbox: VBoxContainer
var _all_labels: Array[Label] = []
var _bpm_caption: Label
var _vol_caption: Label

var _is_playing: bool = false
var _current_beats: int = 4
var _current_unit: int = 4


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -360
	offset_bottom = 0
	offset_left = 0
	offset_right = 0
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var panel := Panel.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG_COLOR
	style.corner_radius_top_left = 18
	style.corner_radius_top_right = 18
	panel.add_theme_stylebox_override("panel", style)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_margin)

	_root_vbox = VBoxContainer.new()
	_root_vbox.add_theme_constant_override("separation", 12)
	_margin.add_child(_root_vbox)

	_build_bpm_row()
	_build_selectors_row()
	_build_volume_row()
	_build_beat_dots_row()
	_build_play_row()

	_create_beat_dots(4)
	_update_play_button_style()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_apply_responsive_layout)


func _build_bpm_row() -> void:
	_bpm_caption = _make_label("BPM")
	_bpm_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_root_vbox.add_child(_bpm_caption)

	# Big BPM readout + ± buttons
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", 16)
	_root_vbox.add_child(top)

	_bpm_minus_btn = _make_step_button("−")
	_bpm_minus_btn.pressed.connect(func(): _nudge_bpm(-1))
	top.add_child(_bpm_minus_btn)

	_bpm_value_label = _make_label("120")
	_bpm_value_label.add_theme_color_override("font_color", VALUE_COLOR)
	_bpm_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bpm_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_bpm_value_label)

	_bpm_plus_btn = _make_step_button("+")
	_bpm_plus_btn.pressed.connect(func(): _nudge_bpm(1))
	top.add_child(_bpm_plus_btn)

	# Slider
	_bpm_slider = HSlider.new()
	_bpm_slider.min_value = BPM_MIN
	_bpm_slider.max_value = BPM_MAX
	_bpm_slider.value = 120
	_bpm_slider.step = 1
	_bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bpm_slider.value_changed.connect(_on_bpm_slider_changed)
	_root_vbox.add_child(_bpm_slider)


func _build_selectors_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_root_vbox.add_child(row)

	_time_sig_button = OptionButton.new()
	for ts in TIME_SIGNATURES:
		_time_sig_button.add_item(ts[0])
	_time_sig_button.selected = 2
	_time_sig_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_time_sig_button.item_selected.connect(_on_time_sig_changed)
	row.add_child(_time_sig_button)

	_sound_button = OptionButton.new()
	for s in SOUND_NAMES:
		_sound_button.add_item(s)
	_sound_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sound_button.item_selected.connect(_on_sound_changed)
	row.add_child(_sound_button)

	_accent_button = OptionButton.new()
	for a in ACCENT_NAMES:
		_accent_button.add_item(a)
	_accent_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_accent_button.item_selected.connect(_on_accent_changed)
	row.add_child(_accent_button)


func _build_volume_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_root_vbox.add_child(row)

	_vol_caption = _make_label("Vol")
	row.add_child(_vol_caption)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.value = 80
	_volume_slider.step = 1
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	row.add_child(_volume_slider)

	_volume_value_label = _make_label("80%")
	_volume_value_label.add_theme_color_override("font_color", VALUE_COLOR)
	row.add_child(_volume_value_label)


func _build_beat_dots_row() -> void:
	_beat_dots_container = HBoxContainer.new()
	_beat_dots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_beat_dots_container.add_theme_constant_override("separation", 10)
	_root_vbox.add_child(_beat_dots_container)


func _build_play_row() -> void:
	_play_button = Button.new()
	_play_button.text = "▶ PLAY"
	_play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_play_button.pressed.connect(_on_play_pressed)
	_root_vbox.add_child(_play_button)


func _apply_responsive_layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var is_portrait: bool = vp.y > vp.x

	# Safe area (notch / home indicator)
	var safe := DisplayServer.get_display_safe_area()
	var bottom_inset: int = maxi(0, int(vp.y - (safe.position.y + safe.size.y)))

	# UI scale: portrait scales by width, landscape by height
	var ui_scale: float
	if is_portrait:
		ui_scale = clampf(vp.x / 720.0, 0.85, 1.6)
	else:
		ui_scale = clampf(vp.y / 720.0, 0.7, 1.4)

	# Panel takes ~45% of portrait viewport, ~50% in landscape
	var panel_ratio: float = 0.46 if is_portrait else 0.42
	var panel_h: int = int(clampf(vp.y * panel_ratio, 280.0, 560.0))
	offset_top = -(panel_h + bottom_inset)
	offset_bottom = 0

	var h_pad: int = int(20.0 * ui_scale)
	var v_pad: int = int(14.0 * ui_scale)
	_margin.add_theme_constant_override("margin_left", h_pad)
	_margin.add_theme_constant_override("margin_right", h_pad)
	_margin.add_theme_constant_override("margin_top", v_pad)
	_margin.add_theme_constant_override("margin_bottom", v_pad + bottom_inset)
	_root_vbox.add_theme_constant_override("separation", int(12.0 * ui_scale))

	# Font sizes
	var label_fs: int = int(clampf(16.0 * ui_scale, 16.0, 24.0))
	for lbl in _all_labels:
		lbl.add_theme_font_size_override("font_size", label_fs)

	# BPM big readout — large display number
	var bpm_fs: int = int(clampf(56.0 * ui_scale, 48.0, 88.0))
	_bpm_value_label.add_theme_font_size_override("font_size", bpm_fs)
	_bpm_caption.add_theme_font_size_override("font_size", int(label_fs * 0.9))

	# Touch targets — Material Design 48dp min, we use 56-72 for comfort
	var tap_h: int = int(clampf(56.0 * ui_scale, 56.0, 72.0))
	var step_size: int = int(clampf(64.0 * ui_scale, 56.0, 88.0))

	_bpm_minus_btn.custom_minimum_size = Vector2(step_size, step_size)
	_bpm_plus_btn.custom_minimum_size = Vector2(step_size, step_size)
	_bpm_minus_btn.add_theme_font_size_override("font_size", int(step_size * 0.5))
	_bpm_plus_btn.add_theme_font_size_override("font_size", int(step_size * 0.5))

	for btn: OptionButton in [_time_sig_button, _sound_button, _accent_button]:
		btn.custom_minimum_size = Vector2(0, tap_h)
		btn.add_theme_font_size_override("font_size", int(label_fs * 1.05))

	# Big play button — primary CTA, 72-96 tall
	var play_h: int = int(clampf(80.0 * ui_scale, 72.0, 110.0))
	_play_button.custom_minimum_size = Vector2(0, play_h)
	_play_button.add_theme_font_size_override("font_size", int(clampf(28.0 * ui_scale, 26.0, 40.0)))
	_update_play_button_style()

	# Sliders: tall grab area for thumb-friendly dragging
	var grab_h: int = int(clampf(44.0 * ui_scale, 36.0, 64.0))
	_bpm_slider.custom_minimum_size = Vector2(0, grab_h)
	_volume_slider.custom_minimum_size = Vector2(0, grab_h)
	_bpm_slider.add_theme_constant_override("grab_height", grab_h)
	_volume_slider.add_theme_constant_override("grab_height", grab_h)
	_style_slider(_bpm_slider, grab_h)
	_style_slider(_volume_slider, grab_h)

	_volume_value_label.custom_minimum_size = Vector2(int(56.0 * ui_scale), 0)

	# Beat dots — bigger on portrait for visibility
	var dot_size: int = int(clampf(28.0 * ui_scale, 24.0, 44.0))
	for dot in _beat_dots:
		dot.custom_minimum_size = Vector2(dot_size, dot_size)
	_beat_dots_container.add_theme_constant_override("separation", int(12.0 * ui_scale))


func _style_slider(slider: HSlider, grab_h: int) -> void:
	# Tall grabber circle for thumb-friendly touch
	var grabber := StyleBoxFlat.new()
	var r: int = grab_h / 2
	grabber.bg_color = Color(0.95, 0.95, 0.98)
	grabber.corner_radius_top_left = r
	grabber.corner_radius_top_right = r
	grabber.corner_radius_bottom_left = r
	grabber.corner_radius_bottom_right = r
	grabber.content_margin_left = r
	grabber.content_margin_right = r
	grabber.content_margin_top = r
	grabber.content_margin_bottom = r
	slider.add_theme_stylebox_override("grabber_area", grabber)
	slider.add_theme_stylebox_override("grabber_area_highlight", grabber)

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.22, 0.22, 0.28)
	track.corner_radius_top_left = 6
	track.corner_radius_top_right = 6
	track.corner_radius_bottom_left = 6
	track.corner_radius_bottom_right = 6
	track.content_margin_top = 6
	track.content_margin_bottom = 6
	slider.add_theme_stylebox_override("slider", track)

	var fill := StyleBoxFlat.new()
	fill.bg_color = ACCENT_COLOR
	fill.corner_radius_top_left = 6
	fill.corner_radius_top_right = 6
	fill.corner_radius_bottom_left = 6
	fill.corner_radius_bottom_right = 6
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
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	btn.add_theme_stylebox_override("normal", sb)

	var sb_p := StyleBoxFlat.new()
	sb_p.bg_color = Color(STEP_BTN_COLOR.r * 1.5, STEP_BTN_COLOR.g * 1.5, STEP_BTN_COLOR.b * 1.5)
	sb_p.corner_radius_top_left = 14
	sb_p.corner_radius_top_right = 14
	sb_p.corner_radius_bottom_left = 14
	sb_p.corner_radius_bottom_right = 14
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
		dot.custom_minimum_size = Vector2(28, 28)
		dot.color = ACCENT_COLOR if i == 0 else DIM_COLOR
		_beat_dots.append(dot)
		_beat_dots_container.add_child(dot)
	if get_viewport() != null and is_inside_tree():
		_apply_responsive_layout()


func on_tick(beat: int, _total_beats: int) -> void:
	for i in _beat_dots.size():
		_beat_dots[i].color = ACCENT_COLOR if i == beat else DIM_COLOR


func _nudge_bpm(delta: int) -> void:
	var b: int = clampi(int(_bpm_slider.value) + delta, BPM_MIN, BPM_MAX)
	_bpm_slider.value = b  # triggers _on_bpm_slider_changed


func _on_bpm_slider_changed(value: float) -> void:
	var b := int(value)
	_bpm_value_label.text = str(b)
	bpm_changed.emit(b)


func _on_time_sig_changed(index: int) -> void:
	if index < 0 or index >= TIME_SIGNATURES.size():
		return
	var ts: Array = TIME_SIGNATURES[index]
	_current_beats = ts[1]
	_current_unit = ts[2]
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
	_play_button.text = "⏸ PAUSE" if _is_playing else "▶ PLAY"
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
		sb.corner_radius_top_left = 18
		sb.corner_radius_top_right = 18
		sb.corner_radius_bottom_left = 18
		sb.corner_radius_bottom_right = 18
		_play_button.add_theme_stylebox_override(state_name, sb)
	_play_button.add_theme_color_override("font_color", Color.WHITE)
