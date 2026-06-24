class_name PitchSmoother
extends RefCounted

# Turns the tuner's noisy per-window pitch estimates into a stable reading.
# Three defenses against jumpiness:
#   1. median-of-N on the raw frequency rejects octave errors and lone spikes,
#   2. an exponential moving average damps the residual jitter,
#   3. note "commitment" — the displayed note only changes after a *different*
#      note has been nearest for COMMIT_FRAMES consecutive pushes, so the big
#      letter never flickers between neighbours. Cents are always reported
#      relative to the committed note, so letter and needle never disagree.
#
# Note math lives in tuner.gd; we reach it by runtime-safe preload. tuner.gd
# loads THIS script at runtime (not via const preload) to avoid a cyclic
# compile-time dependency.

const NoteMath = preload("res://tuner.gd")

const MEDIAN_WINDOW := 5
const EMA_ALPHA := 0.55     # ~150 ms time constant at the 0.12 s push interval
const COMMIT_FRAMES := 3    # consecutive pushes a new note must win before it sticks

const _UNSET := -9999

var _recent: Array = []         # recent raw frequencies (most recent last)
var _ema_freq: float = 0.0
var _committed_midi: int = _UNSET
var _pending_midi: int = _UNSET
var _pending_count: int = 0


func reset() -> void:
	_recent.clear()
	_ema_freq = 0.0
	_committed_midi = _UNSET
	_pending_midi = _UNSET
	_pending_count = 0


# Feed one raw detection; returns the smoothed, committed reading:
#   { "name": String, "cents": float, "freq": float, "midi": int }
func push(raw_freq: float, _clarity: float, candidates: Array) -> Dictionary:
	# 1. median filter rejects octave errors / lone spikes
	_recent.append(raw_freq)
	if _recent.size() > MEDIAN_WINDOW:
		_recent.remove_at(0)
	var med: float = _median(_recent)

	# 2. exponential moving average damps the rest
	if _ema_freq <= 0.0:
		_ema_freq = med
	else:
		_ema_freq = _ema_freq + EMA_ALPHA * (med - _ema_freq)

	# 3. nearest note from the smoothed frequency
	var note: Dictionary = NoteMath.nearest_note(_ema_freq, candidates)
	var midi: int = int(note.midi)

	# 4. commitment: first reading after silence commits immediately; afterward a
	#    new note must be nearest for COMMIT_FRAMES consecutive pushes to take over.
	if _committed_midi == _UNSET or midi == _committed_midi:
		_committed_midi = midi
		_pending_midi = midi
		_pending_count = 0
	else:
		if midi == _pending_midi:
			_pending_count += 1
		else:
			_pending_midi = midi
			_pending_count = 1
		if _pending_count >= COMMIT_FRAMES:
			_committed_midi = midi
			_pending_count = 0

	# 5. cents relative to the committed note (never the raw nearest)
	var ref_freq: float = NoteMath.midi_to_freq(float(_committed_midi))
	var cents: float = 1200.0 * (log(_ema_freq / ref_freq) / log(2.0))
	var octave: int = _committed_midi / 12 - 1
	var note_name: String = NoteMath.NOTE_NAMES[_committed_midi % 12] + str(octave)

	return {"name": note_name, "cents": cents, "freq": _ema_freq, "midi": _committed_midi}


static func _median(values: Array) -> float:
	var n: int = values.size()
	if n == 0:
		return 0.0
	var s: Array = values.duplicate()
	s.sort()
	if n % 2 == 1:
		return float(s[n / 2])
	return (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5
