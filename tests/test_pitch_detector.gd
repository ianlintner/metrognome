extends SceneTree
# Headless test:  godot --headless --script res://tests/test_pitch_detector.gd
const PitchDetector = preload("res://pitch_detector.gd")

func _sine(freq: float, sr: float, n: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		buf[i] = sin(TAU * freq * float(i) / sr)
	return buf

# Plucked-string stand-in: harmonic stack with 1/k amplitudes under an
# exponential decay — the asymmetric-energy case that broke the old
# left-window-normalized detector.
func _pluck(freq: float, sr: float, n: int, decay_tau: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / sr
		var v := 0.0
		for k in range(1, 7):
			v += sin(TAU * freq * float(k) * t) / float(k)
		buf[i] = v * exp(-t / decay_tau)
	return buf

# Octave-error trap: 2nd harmonic twice as strong as the fundamental.
func _dominant_second(freq: float, sr: float, n: int) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(n)
	for i in n:
		var t := float(i) / sr
		buf[i] = 0.5 * sin(TAU * freq * t) + 1.0 * sin(TAU * freq * 2.0 * t) \
			+ 0.3 * sin(TAU * freq * 3.0 * t)
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

	# Open strings across the supported instruments:
	# guitar E2..E4, violin up to E5, plus A4 reference.
	for freq in [82.41, 110.0, 146.83, 196.0, 246.94, 329.63, 440.0, 659.26]:
		var r: Dictionary = PitchDetector.detect(_sine(freq, sr, n), sr)
		var err: float = abs(r.frequency - freq)
		if err > freq * 0.003:   # within 0.3% (~5 cents)
			push_error("FREQ FAIL %f -> %f (err %f)" % [freq, r.frequency, err])
			failures += 1
		if r.clarity < 0.8:
			push_error("CLARITY FAIL %f -> clarity %f" % [freq, r.clarity])
			failures += 1

	# Decaying harmonic-rich pluck (37% amplitude drop across the window).
	for freq in [82.41, 110.0, 196.0, 329.63]:
		var p: Dictionary = PitchDetector.detect(_pluck(freq, sr, n, 0.1), sr)
		var perr: float = abs(p.frequency - freq)
		if perr > freq * 0.005:  # within 0.5%
			push_error("PLUCK FAIL %f -> %f (err %f)" % [freq, p.frequency, perr])
			failures += 1
		if p.clarity < 0.6:
			push_error("PLUCK CLARITY FAIL %f -> %f" % [freq, p.clarity])
			failures += 1

	# Dominant 2nd harmonic must not read an octave high.
	for freq in [110.0, 196.0]:
		var d: Dictionary = PitchDetector.detect(_dominant_second(freq, sr, n), sr)
		var derr: float = abs(d.frequency - freq)
		if derr > freq * 0.005:
			push_error("OCTAVE FAIL %f -> %f" % [freq, d.frequency])
			failures += 1

	# Noise should report low clarity (no stable pitch).
	var nr: Dictionary = PitchDetector.detect(_noise(n), sr)
	if nr.clarity >= 0.6:
		push_error("NOISE FAIL clarity %f should be < 0.6" % nr.clarity)
		failures += 1

	# Silence -> no pitch.
	var z := PackedFloat32Array()
	z.resize(n)
	var zr: Dictionary = PitchDetector.detect(z, sr)
	if zr.frequency != 0.0:
		push_error("SILENCE FAIL freq %f" % zr.frequency)
		failures += 1

	if failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		print("FAILURES: %d" % failures)
		quit(1)
