extends Node
class_name AudioClicker

# Each sound is pre-rendered into an AudioStreamWAV and played as a static sample
# (a realtime AudioStreamGenerator under-runs on iOS and sounds like garbage).
#
# Sound types (must match UIManager.SOUND_NAMES and the per-character defaults):
#   0 Metronome  – crisp pulse (gnome)
#   1 Ribbit     – quick buzzy two-syllable croak (frog)
#   2 Thump      – deep damped wood-log knock (beaver)
#   3 Wood Block – mid woody tick
#   4 Beep       – high digital beep

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
		1:  # Ribbit (frog) — accent is a higher, louder croak
			_click_stream = _bake(_ribbit_samples(230.0, 0.70))
			_accent_stream = _bake(_ribbit_samples(275.0, 0.85))
		2:  # Thump (beaver) — accent is a touch higher + louder knock
			_click_stream = _bake(_thump_samples(95.0, 0.90))
			_accent_stream = _bake(_thump_samples(120.0, 1.00))
		3:  # Wood block
			_click_stream = _bake(_sine_samples(500.0, 0.04, 0.7))
			_accent_stream = _bake(_sine_samples(700.0, 0.05, 0.9))
		4:  # Beep
			_click_stream = _bake(_sine_samples(900.0, 0.02, 0.5))
			_accent_stream = _bake(_sine_samples(1300.0, 0.03, 0.7))
		_:  # 0 Metronome pulse
			_click_stream = _bake(_sine_samples(1200.0, 0.025, 0.6))
			_accent_stream = _bake(_sine_samples(1600.0, 0.035, 0.8))


# --- Waveform generators (return float samples in roughly [-1, 1]) ---

func _sine_samples(frequency: float, duration: float, amplitude: float) -> PackedFloat32Array:
	var n := int(_sample_rate * duration)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(_sample_rate)
		out[i] = sin(TAU * frequency * t) * exp(-t * 50.0) * amplitude
	return out


# A frog "ribbit": two amplitude bumps (ri-bbit), a buzzy ~55 Hz rasp, and a
# harmonic-rich carrier with a little vibrato.
func _ribbit_samples(base: float, amplitude: float) -> PackedFloat32Array:
	var dur := 0.20
	var n := int(_sample_rate * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(_sample_rate)
		var env: float = maxf(_bump(t, 0.0, 0.06), _bump(t, 0.075, 0.20))
		var f := base * (1.0 + 0.12 * sin(TAU * 6.0 * t))          # gentle vibrato
		var buzz := 0.55 + 0.45 * sin(TAU * 55.0 * t)              # raspy croak
		var carrier := sin(TAU * f * t) + 0.5 * sin(TAU * 2.0 * f * t) + 0.25 * sin(TAU * 3.0 * f * t)
		out[i] = carrier * buzz * env * amplitude * 0.5
	return out


# A deep wooden log thump: low body tone with a fast pitch drop + decay, plus a
# short noise transient for the "knock".
func _thump_samples(base: float, amplitude: float) -> PackedFloat32Array:
	var dur := 0.18
	var n := int(_sample_rate * dur)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / float(_sample_rate)
		var f := base * (0.6 + 0.4 * exp(-t * 60.0))              # pitch drops quickly
		var body := sin(TAU * f * t) * exp(-t * 26.0)
		var knock := (randf() * 2.0 - 1.0) * exp(-t * 180.0) * 0.4
		out[i] = (body + knock) * amplitude
	return out


# Smooth 0→1→0 hump between times a and b.
func _bump(t: float, a: float, b: float) -> float:
	if t < a or t > b:
		return 0.0
	return sin(PI * (t - a) / (b - a))


# Bake float samples into a 16-bit stereo PCM AudioStreamWAV.
func _bake(samples: PackedFloat32Array) -> AudioStreamWAV:
	var n := samples.size()
	var bytes := PackedByteArray()
	bytes.resize(n * 4)
	for i in n:
		var s := clampi(int(clampf(samples[i], -1.0, 1.0) * 32767.0), -32768, 32767)
		bytes.encode_s16(i * 4, s)
		bytes.encode_s16(i * 4 + 2, s)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = _sample_rate
	wav.data = bytes
	return wav
