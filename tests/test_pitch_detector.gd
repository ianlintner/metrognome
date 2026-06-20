extends SceneTree
# Headless test:  godot --headless --script res://tests/test_pitch_detector.gd
const PitchDetector = preload("res://pitch_detector.gd")

func _sine(freq: float, sr: float, n: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = sin(TAU * freq * float(i) / sr)
	return buf

func _noise(n: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = rng.randf_range(-1.0, 1.0)
	return buf

func _initialize() -> void:
	var failures := 0
	var sr := 44100.0
	var n := 2048

	# A2 = 110 Hz, A4 = 440 Hz, D3 = 146.83 Hz
	for freq in [110.0, 220.0, 440.0, 146.83]:
		var r: Dictionary = PitchDetector.detect(_sine(freq, sr, n), sr)
		var err: float = abs(r.frequency - freq)
		if err > freq * 0.02:   # within 2%
			push_error("FREQ FAIL %f -> %f (err %f)" % [freq, r.frequency, err])
			failures += 1
		if r.clarity < 0.8:
			push_error("CLARITY FAIL %f -> clarity %f" % [freq, r.clarity])
			failures += 1

	# Noise should report low clarity (no stable pitch)
	var nr: Dictionary = PitchDetector.detect(_noise(n), sr)
	if nr.clarity >= 0.6:
		push_error("NOISE FAIL clarity %f should be < 0.6" % nr.clarity)
		failures += 1

	if failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: %d" % failures)
		quit(1)
