extends SceneTree
# Headless test:  godot --headless --script res://tests/test_tuner_notes.gd
const Tuner = preload("res://tuner.gd")

func _check(cond: bool, msg: String) -> int:
	if cond:
		return 0
	push_error("FAIL: " + msg)
	return 1

func _initialize() -> void:
	var failures := 0

	# 440 Hz is A4, ~0 cents, chromatic (empty candidate list).
	var a: Dictionary = Tuner.nearest_note(440.0, [])
	failures += _check(a.name == "A4", "440Hz name was %s" % a.name)
	failures += _check(abs(a.cents) < 1.0, "440Hz cents was %f" % a.cents)

	# 110 Hz is A2.
	var a2: Dictionary = Tuner.nearest_note(110.0, [])
	failures += _check(a2.name == "A2", "110Hz name was %s" % a2.name)

	# Slightly sharp of A4: positive cents.
	var sharp: Dictionary = Tuner.nearest_note(445.0, [])
	failures += _check(sharp.cents > 0.0, "445Hz should be sharp, cents %f" % sharp.cents)

	# Guitar low E preset (midi 40 = E2 = 82.41 Hz): 83 Hz snaps to E2 even though
	# F2 is chromatically closer-by-name only after snapping to candidates.
	var e: Dictionary = Tuner.nearest_note(83.0, [40, 45, 50, 55, 59, 64])
	failures += _check(e.midi == 40, "83Hz on guitar preset snapped to midi %d" % e.midi)

	if failures == 0:
		print("ALL PASS")
		quit(0)
	else:
		quit(1)
