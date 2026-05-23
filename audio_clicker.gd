extends Node
class_name AudioClicker

var _player: AudioStreamPlayer
var _volume: float = 0.8
var volume: float:
	get:
		return _volume
	set(value):
		_volume = clampf(value, 0.0, 1.0)
		if _player != null:
			_player.volume_db = linear_to_db(_volume)

var _click_frames: PackedVector2Array
var _accent_frames: PackedVector2Array
var _is_playing: bool = false
var _current_frames: PackedVector2Array
var _current_frame: int = 0
var _playback: AudioStreamGeneratorPlayback
var _sample_rate: int = 44100


func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "Master"
	add_child(_player)
	_generate_sounds(0)
	volume = _volume


func set_sound_type(type: int) -> void:
	_generate_sounds(type)


func play_click() -> void:
	_start_playback(_click_frames)


func play_accent() -> void:
	_start_playback(_accent_frames)


func _start_playback(frames: PackedVector2Array) -> void:
	if frames.is_empty():
		return
	_player.stop()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = _sample_rate
	generator.buffer_length = 0.15
	_player.stream = generator
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback
	_current_frames = frames
	_current_frame = 0
	_is_playing = true


func _process(_delta: float) -> void:
	if not _is_playing or _playback == null:
		return
	var pushed := 0
	var max_per_frame := 200
	while _current_frame < _current_frames.size() and pushed < max_per_frame:
		if _playback.can_push_buffer(1):
			_playback.push_frame(_current_frames[_current_frame])
			_current_frame += 1
			pushed += 1
		else:
			break
	if _current_frame >= _current_frames.size():
		_is_playing = false


func _generate_sounds(type: int) -> void:
	match type:
		0:
			_click_frames = _generate_frames(1200.0, 0.025, 0.6)
			_accent_frames = _generate_frames(1600.0, 0.035, 0.8)
		1:
			_click_frames = _generate_frames(500.0, 0.04, 0.7)
			_accent_frames = _generate_frames(700.0, 0.05, 0.9)
		2:
			_click_frames = _generate_frames(900.0, 0.02, 0.5)
			_accent_frames = _generate_frames(1300.0, 0.03, 0.7)


func _generate_frames(frequency: float, duration: float, amplitude: float) -> PackedVector2Array:
	var total_frames := int(_sample_rate * duration)
	var frames := PackedVector2Array()
	frames.resize(total_frames)
	for i in total_frames:
		var t := float(i) / float(_sample_rate)
		var envelope := exp(-t * 50.0)
		var value := sin(2.0 * PI * frequency * t) * envelope * amplitude
		frames[i] = Vector2(value, value)
	return frames
