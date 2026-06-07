extends Node
class_name AudioClicker

# Pre-renders each click/accent into an AudioStreamWAV and plays it as a static
# sample. (The old realtime AudioStreamGenerator under-ran its buffer on iOS —
# pushing ~12k frames/sec while playback consumed 44.1k/sec — which sounded like
# garbage. A baked WAV has no realtime buffer to starve.)

var _player: AudioStreamPlayer
var _volume: float = 0.8
var volume: float:
	get:
		return _volume
	set(value):
		_volume = clampf(value, 0.0, 1.0)
		if _player != null:
			_player.volume_db = linear_to_db(maxf(_volume, 0.0001))

var _click_stream: AudioStreamWAV
var _accent_stream: AudioStreamWAV
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
	_play(_click_stream)


func play_accent() -> void:
	_play(_accent_stream)


func _play(stream: AudioStreamWAV) -> void:
	if stream == null:
		return
	_player.stream = stream
	_player.play()


func _generate_sounds(type: int) -> void:
	match type:
		1:
			_click_stream = _make_wav(500.0, 0.04, 0.7)
			_accent_stream = _make_wav(700.0, 0.05, 0.9)
		2:
			_click_stream = _make_wav(900.0, 0.02, 0.5)
			_accent_stream = _make_wav(1300.0, 0.03, 0.7)
		_:
			_click_stream = _make_wav(1200.0, 0.025, 0.6)
			_accent_stream = _make_wav(1600.0, 0.035, 0.8)


# Bake a decaying sine "click" into a 16-bit stereo PCM AudioStreamWAV.
func _make_wav(frequency: float, duration: float, amplitude: float) -> AudioStreamWAV:
	var n := int(_sample_rate * duration)
	var bytes := PackedByteArray()
	bytes.resize(n * 4)  # 16-bit stereo = 4 bytes/frame
	for i in n:
		var t := float(i) / float(_sample_rate)
		var envelope := exp(-t * 50.0)
		var value := sin(2.0 * PI * frequency * t) * envelope * amplitude
		var s := clampi(int(value * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 4, s)      # left
		bytes.encode_s16(i * 4 + 2, s)  # right
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = _sample_rate
	wav.data = bytes
	return wav
