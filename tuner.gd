class_name Tuner
extends Node

const PitchDetector = preload("res://pitch_detector.gd")

# Owns microphone capture and converts the live signal into note + cents readings.
# Capture chain (built lazily on first start()): a muted "MicCapture" audio bus
# carrying an AudioEffectCapture, fed by an AudioStreamPlayer playing the mic.
# Muting the bus prevents the mic from echoing to the speakers (feedback).
#
# Pitch detection is throttled to DETECT_INTERVAL seconds to keep the main thread
# responsive — autocorrelation over 2048 samples is O(n²) in GDScript.

signal pitch_detected(frequency: float, note_name: String, cents: float, clarity: float)
signal signal_lost()

const BUS_NAME := "MicCapture"
const WINDOW := 2048
const CLARITY_THRESHOLD := 0.6
const DETECT_INTERVAL := 0.12  # seconds between detection passes

const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

var _player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _bus_idx: int = -1
var _window := PackedFloat32Array()
var _active := false
var _candidates: Array = []  # midi note numbers; empty = chromatic (all 12)
var _had_signal := false
var _detect_timer := 0.0
var _smoother  # PitchSmoother, loaded at runtime to avoid a cyclic preload


# ---- pure note math (static, unit-tested in tests/test_tuner_notes.gd) ----

static func freq_to_midi(freq: float) -> float:
	return 69.0 + 12.0 * (log(freq / 440.0) / log(2.0))

static func midi_to_freq(midi: float) -> float:
	return 440.0 * pow(2.0, (midi - 69.0) / 12.0)

static func nearest_note(freq: float, candidates: Array) -> Dictionary:
	var midi := freq_to_midi(freq)
	var nearest_midi: int
	if candidates.is_empty():
		nearest_midi = int(round(midi))
	else:
		nearest_midi = int(candidates[0])
		var best: float = abs(midi - float(nearest_midi))
		for c in candidates:
			var d: float = abs(midi - float(c))
			if d < best:
				best = d
				nearest_midi = int(c)
	var ref_freq := midi_to_freq(float(nearest_midi))
	var cents := 1200.0 * (log(freq / ref_freq) / log(2.0))
	var octave := nearest_midi / 12 - 1
	var note_name: String = NOTE_NAMES[nearest_midi % 12] + str(octave)
	return {"midi": nearest_midi, "name": note_name, "cents": cents}


# ---- capture lifecycle ------------------------------------------------

func start() -> void:
	if _active:
		return
	_ensure_bus()
	if _player == null:
		_player = AudioStreamPlayer.new()
		_player.stream = AudioStreamMicrophone.new()
		_player.bus = BUS_NAME
		add_child(_player)
	_player.play()
	_window.clear()
	_had_signal = false
	_detect_timer = 0.0
	if _smoother == null:
		_smoother = load("res://pitch_smoother.gd").new()
	_smoother.reset()
	_active = true

func stop() -> void:
	if not _active:
		return
	if _player != null:
		_player.stop()
	_window.clear()
	_had_signal = false
	if _smoother != null:
		_smoother.reset()
	_active = false

func is_active() -> bool:
	return _active

func set_candidates(midis: Array) -> void:
	_candidates = midis

func _ensure_bus() -> void:
	_bus_idx = AudioServer.get_bus_index(BUS_NAME)
	if _bus_idx == -1:
		_bus_idx = AudioServer.bus_count
		AudioServer.add_bus(_bus_idx)
		AudioServer.set_bus_name(_bus_idx, BUS_NAME)
		AudioServer.set_bus_mute(_bus_idx, true)
	if AudioServer.get_bus_effect_count(_bus_idx) == 0:
		_capture = AudioEffectCapture.new()
		AudioServer.add_bus_effect(_bus_idx, _capture)
	else:
		_capture = AudioServer.get_bus_effect(_bus_idx, 0) as AudioEffectCapture

func _process(delta: float) -> void:
	if not _active or _capture == null:
		return

	# Drain the capture buffer and accumulate mono samples.
	var available := _capture.get_frames_available()
	if available > 0:
		var frames := _capture.get_buffer(available)
		for f in frames:
			_window.append((f.x + f.y) * 0.5)
		if _window.size() > WINDOW:
			_window = _window.slice(_window.size() - WINDOW)

	# Throttle detection to avoid stalling the main thread.
	_detect_timer += delta
	if _detect_timer < DETECT_INTERVAL:
		return
	_detect_timer = 0.0

	if _window.size() < WINDOW:
		return

	var sr := float(AudioServer.get_mix_rate())
	var result := PitchDetector.detect(_window, sr)
	_window.clear()

	if result.clarity < CLARITY_THRESHOLD or result.frequency <= 0.0:
		if _had_signal:
			_had_signal = false
			if _smoother != null:
				_smoother.reset()
			signal_lost.emit()
		return

	_had_signal = true
	# Hand the raw estimate to the smoother; it returns a stable, committed reading.
	var r: Dictionary = _smoother.push(result.frequency, float(result.clarity), _candidates)
	pitch_detected.emit(float(r.freq), String(r.name), float(r.cents), float(result.clarity))
