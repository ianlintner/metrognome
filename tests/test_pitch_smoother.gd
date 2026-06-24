extends SceneTree

# Headless unit tests for PitchSmoother. Run with:
#   Godot --headless --script tests/test_pitch_smoother.gd
# class_name globals aren't populated in --script mode, so preload directly.

const PitchSmoother = preload("res://pitch_smoother.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
	else:
		_fail += 1
		print("  FAIL: ", label)


func _init() -> void:
	_test_median_static()
	_test_stable_note()
	_test_outlier_rejected()
	_test_commitment_delay()
	_test_reset()

	print("test_pitch_smoother: %d passed, %d failed" % [_pass, _fail])
	print("ALL PASS" if _fail == 0 else "FAILURES")
	quit()


# Median is a pure helper — reject a lone octave spike outright.
func _test_median_static() -> void:
	_ok(PitchSmoother._median([110.0, 110.0, 440.0, 110.0, 110.0]) == 110.0, "median rejects spike")
	_ok(PitchSmoother._median([100.0, 200.0]) == 150.0, "median even-count averages")


# A steady 110 Hz commits to A2 with ~0 cents.
func _test_stable_note() -> void:
	var s = PitchSmoother.new()
	var r: Dictionary = {}
	for i in 5:
		r = s.push(110.0, 1.0, [])
	_ok(String(r.name) == "A2", "stable 110Hz -> A2 (got %s)" % r.name)
	_ok(absf(float(r.cents)) < 1.0, "stable 110Hz -> ~0 cents (got %.2f)" % r.cents)


# After a stable note, a single wild reading must not change the committed note.
func _test_outlier_rejected() -> void:
	var s = PitchSmoother.new()
	for i in 5:
		s.push(110.0, 1.0, [])
	var r: Dictionary = s.push(220.0, 1.0, [])  # lone octave jump
	_ok(String(r.name) == "A2", "single outlier keeps committed note (got %s)" % r.name)


# Switching to a genuinely new note must take several consistent pushes.
func _test_commitment_delay() -> void:
	var s = PitchSmoother.new()
	for i in 5:
		s.push(110.0, 1.0, [])  # commit A2
	# Now feed D3 (146.83 Hz). One push must NOT have switched yet.
	var first: Dictionary = s.push(146.83, 1.0, [])
	_ok(String(first.name) == "A2", "one new-note push doesn't switch (got %s)" % first.name)
	# Keep feeding D3 until median+commitment catch up.
	var last: Dictionary = first
	for i in 8:
		last = s.push(146.83, 1.0, [])
	_ok(String(last.name) == "D3", "sustained new note eventually commits (got %s)" % last.name)


# reset() wipes all state so a fresh note commits immediately again.
func _test_reset() -> void:
	var s = PitchSmoother.new()
	for i in 5:
		s.push(110.0, 1.0, [])
	s.reset()
	var r: Dictionary = s.push(82.41, 1.0, [])  # E2
	_ok(String(r.name) == "E2", "reset then E2 commits immediately (got %s)" % r.name)
