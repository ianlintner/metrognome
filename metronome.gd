extends Node
class_name Metronome

signal tick(beat: int, total_beats: int, is_accent: bool)
signal beat_changed(beat: int)

var _bpm: int = 120
var bpm: int:
	get:
		return _bpm
	set(value):
		_bpm = clampi(value, 20, 300)
		_tick_interval = 60.0 / float(_bpm)

var _beats_per_measure: int = 4
var beats_per_measure: int:
	get:
		return _beats_per_measure
	set(value):
		_beats_per_measure = clampi(value, 1, 16)
		_current_beat = 0
		_time_accumulator = 0.0
		accent_pattern = _generate_pattern(_beats_per_measure, _accent_mode)

var beat_unit: int = 4
var accent_pattern: Array[bool] = [true, false, false, false]

var _accent_mode: int = 0
var _current_beat: int = 0
var _time_accumulator: float = 0.0
var _tick_interval: float = 0.5
var _is_playing: bool = false


func is_playing() -> bool:
	return _is_playing


func _ready() -> void:
	_tick_interval = 60.0 / float(_bpm)


func play() -> void:
	_is_playing = true
	_time_accumulator = 0.0


func pause() -> void:
	_is_playing = false


func stop() -> void:
	_is_playing = false
	_current_beat = 0
	_time_accumulator = 0.0
	beat_changed.emit(0)


func set_accent_mode(mode: int) -> void:
	_accent_mode = mode
	accent_pattern = _generate_pattern(_beats_per_measure, mode)


func set_time_signature(beats: int, unit: int) -> void:
	beats_per_measure = beats
	beat_unit = unit


func _generate_pattern(beats: int, mode: int) -> Array[bool]:
	var pattern: Array[bool] = []
	pattern.resize(beats)
	for i in beats:
		pattern[i] = false
	match mode:
		0:
			pattern[0] = true
		1:
			pattern[0] = true
			if beats > 2:
				pattern[2] = true
		2:
			var i := 0
			while i < beats:
				pattern[i] = true
				i += 2
		_:
			pass
	return pattern


func _process(delta: float) -> void:
	if not _is_playing:
		return
	_time_accumulator += delta
	if _time_accumulator >= _tick_interval:
		_time_accumulator -= _tick_interval
		var is_accent := _current_beat < accent_pattern.size() and accent_pattern[_current_beat]
		tick.emit(_current_beat, _beats_per_measure, is_accent)
		beat_changed.emit(_current_beat)
		_current_beat = (_current_beat + 1) % _beats_per_measure
