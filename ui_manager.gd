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

const PANEL_BG_COLOR := Color(0.08, 0.08, 0.1, 0.85)
const LABEL_COLOR := Color(0.85, 0.85, 0.9)
const ACCENT_COLOR := Color(0.95, 0.65, 0.2)
const DIM_COLOR := Color(0.25, 0.25, 0.3)
const PLAY_COLOR := Color(0.2, 0.7, 0.3)
const PAUSE_COLOR := Color(0.85, 0.65, 0.2)

var _bpm_slider: HSlider
var _bpm_value_label: Label
var _time_sig_button: OptionButton
var _sound_button: OptionButton
var _accent_button: OptionButton
var _volume_slider: HSlider
var _volume_value_label: Label
var _play_button: Button
var _beat_dots_container: HBoxContainer
var _beat_dots: Array[ColorRect] = []
var _time_sig_display_label: Label

# References needed for responsive updates
var _margin: MarginContainer
var _label_bpm: Label
var _label_time: Label
var _label_sound: Label
var _label_accent: Label
var _label_vol: Label
var _all_labels: Array[Label] = []

var _is_playing: bool = false
var _current_beats: int = 4
var _current_unit: int = 4


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	offset_top = -160
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
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	panel.add_theme_stylebox_override("panel", style)

	_margin = MarginContainer.new()
	_margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.add_child(_margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_margin.add_child(vbox)

	# Row 1: BPM + Time signature
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 12)
	vbox.add_child(row1)

	_label_bpm = _make_label("BPM")
	row1.add_child(_label_bpm)

	_bpm_slider = HSlider.new()
	_bpm_slider.min_value = 20
	_bpm_slider.max_value = 300
	_bpm_slider.value = 120
	_bpm_slider.step = 1
	_bpm_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bpm_slider.value_changed.connect(_on_bpm_slider_changed)
	row1.add_child(_bpm_slider)

	_bpm_value_label = _make_label("120")
	row1.add_child(_bpm_value_label)

	_label_time = _make_label("Time")
	row1.add_child(_label_time)

	_time_sig_button = OptionButton.new()
	for ts in TIME_SIGNATURES:
		_time_sig_button.add_item(ts[0])
	_time_sig_button.selected = 2
	_time_sig_button.item_selected.connect(_on_time_sig_changed)
	row1.add_child(_time_sig_button)

	# Row 2: Sound + Accent + Volume
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 12)
	vbox.add_child(row2)

	_label_sound = _make_label("Sound")
	row2.add_child(_label_sound)

	_sound_button = OptionButton.new()
	for s in SOUND_NAMES:
		_sound_button.add_item(s)
	_sound_button.item_selected.connect(_on_sound_changed)
	row2.add_child(_sound_button)

	_label_accent = _make_label("Accent")
	row2.add_child(_label_accent)

	_accent_button = OptionButton.new()
	for a in ACCENT_NAMES:
		_accent_button.add_item(a)
	_accent_button.item_selected.connect(_on_accent_changed)
	row2.add_child(_accent_button)

	_label_vol = _make_label("Vol")
	row2.add_child(_label_vol)

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0
	_volume_slider.max_value = 100
	_volume_slider.value = 80
	_volume_slider.step = 1
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_volume_slider.value_changed.connect(_on_volume_changed)
	row2.add_child(_volume_slider)

	_volume_value_label = _make_label("80%")
	row2.add_child(_volume_value_label)

	# Row 3: Play button + beat dots + time sig display
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 10)
	row3.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(row3)

	_play_button = Button.new()
	_play_button.text = "▶ Play"
	_play_button.pressed.connect(_on_play_pressed)
	row3.add_child(_play_button)

	_beat_dots_container = HBoxContainer.new()
	_beat_dots_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_beat_dots_container.add_theme_constant_override("separation", 6)
	_beat_dots_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row3.add_child(_beat_dots_container)

	_time_sig_display_label = _make_label("4/4")
	row3.add_child(_time_sig_display_label)

	_create_beat_dots(4)
	_update_play_button_style()
	_apply_responsive_layout()
	get_viewport().size_changed.connect(_apply_responsive_layout)


func _apply_responsive_layout() -> void:
	var vp := get_viewport().get_visible_rect().size

	# Scale relative to 1280-wide desktop baseline, clamped for phone/tablet range
	var ui_scale := clampf(vp.x / 1280.0, 0.65, 1.6)

	# Safe area: avoid home indicator / notch on iPhone
	var safe := DisplayServer.get_display_safe_area()
	var bottom_inset := int(vp.y - (safe.position.y + safe.size.y))
	bottom_inset = maxi(0, bottom_inset)

	# Panel height: taller on tablet/large phone, accounts for safe area
	var panel_h := int(clampf(vp.y * 0.24, 160.0, 300.0))
	offset_top = -(panel_h + bottom_inset)
	offset_bottom = 0

	# Inner margins — extra bottom pad covers home indicator
	var h_pad := int(clampf(16.0 * ui_scale, 12.0, 28.0))
	var v_pad := int(clampf(10.0 * ui_scale, 8.0, 18.0))
	_margin.add_theme_constant_override("margin_left", h_pad)
	_margin.add_theme_constant_override("margin_right", h_pad)
	_margin.add_theme_constant_override("margin_top", v_pad)
	_margin.add_theme_constant_override("margin_bottom", v_pad + bottom_inset)

	# Font size
	var font_size := int(clampf(14.0 * ui_scale, 14.0, 22.0))
	for lbl in _all_labels:
		lbl.add_theme_font_size_override("font_size", font_size)

	# Hide short labels on very narrow screens to free space for controls
	var show_labels: bool = vp.x >= 520.0
	_label_bpm.visible = show_labels
	_label_time.visible = show_labels
	_label_sound.visible = show_labels
	_label_accent.visible = show_labels
	_label_vol.visible = show_labels

	# Play button — Apple HIG minimum tap target is 44 pt
	var btn_h := int(clampf(44.0 * ui_scale, 44.0, 68.0))
	var btn_w := int(clampf(100.0 * ui_scale, 100.0, 180.0))
	_play_button.custom_minimum_size = Vector2(btn_w, btn_h)
	_update_play_button_style()

	# Time sig display label width
	_time_sig_display_label.custom_minimum_size = Vector2(int(50.0 * ui_scale), 0)

	# BPM and volume value label widths
	_bpm_value_label.custom_minimum_size = Vector2(int(40.0 * ui_scale), 0)
	_volume_value_label.custom_minimum_size = Vector2(int(40.0 * ui_scale), 0)

	# OptionButton touch height
	var opt_h := int(clampf(36.0 * ui_scale, 36.0, 56.0))
	for btn in [_time_sig_button, _sound_button, _accent_button]:
		btn.custom_minimum_size = Vector2(0, opt_h)

	# Slider grab area — larger hit zone on mobile touch
	var grab_h := int(clampf(20.0 * ui_scale, 20.0, 40.0))
	_bpm_slider.add_theme_constant_override("grab_height", grab_h)
	_volume_slider.add_theme_constant_override("grab_height", grab_h)

	# Beat dots
	var dot_size := int(clampf(18.0 * ui_scale, 18.0, 32.0))
	for dot in _beat_dots:
		dot.custom_minimum_size = Vector2(dot_size, dot_size)
	_beat_dots_container.add_theme_constant_override("separation", int(6.0 * ui_scale))


func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", LABEL_COLOR)
	label.add_theme_font_size_override("font_size", 14)
	_all_labels.append(label)
	return label


func _create_beat_dots(count: int) -> void:
	for dot in _beat_dots:
		dot.queue_free()
	_beat_dots.clear()
	for i in count:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(18, 18)
		dot.color = ACCENT_COLOR if i == 0 else DIM_COLOR
		_beat_dots.append(dot)
		_beat_dots_container.add_child(dot)
	# Resize dots to match current scale if layout already applied
	if get_viewport() != null and is_inside_tree():
		var vp := get_viewport().get_visible_rect().size
		var ui_scale := clampf(vp.x / 1280.0, 0.65, 1.6)
		var dot_size := int(clampf(18.0 * ui_scale, 18.0, 32.0))
		for dot in _beat_dots:
			dot.custom_minimum_size = Vector2(dot_size, dot_size)


func on_tick(beat: int, _total_beats: int) -> void:
	for i in _beat_dots.size():
		_beat_dots[i].color = ACCENT_COLOR if i == beat else DIM_COLOR


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
	_time_sig_display_label.text = ts[0]
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
	_play_button.text = "⏸ Pause" if _is_playing else "▶ Play"
	_update_play_button_style()
	play_toggled.emit(_is_playing)


func _update_play_button_style() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = PAUSE_COLOR if _is_playing else PLAY_COLOR
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	_play_button.add_theme_stylebox_override("normal", sb)

	var sb_h := StyleBoxFlat.new()
	var base: Color = PAUSE_COLOR if _is_playing else PLAY_COLOR
	sb_h.bg_color = Color(base.r * 0.8, base.g * 0.8, base.b * 0.8)
	sb_h.corner_radius_bottom_left = 8
	sb_h.corner_radius_bottom_right = 8
	sb_h.corner_radius_top_left = 8
	sb_h.corner_radius_top_right = 8
	_play_button.add_theme_stylebox_override("hover", sb_h)

	# Pressed state (important for touch — no hover on mobile)
	var sb_p := StyleBoxFlat.new()
	sb_p.bg_color = Color(base.r * 0.65, base.g * 0.65, base.b * 0.65)
	sb_p.corner_radius_bottom_left = 8
	sb_p.corner_radius_bottom_right = 8
	sb_p.corner_radius_top_left = 8
	sb_p.corner_radius_top_right = 8
	_play_button.add_theme_stylebox_override("pressed", sb_p)
