class_name PitchDetector
extends RefCounted

# Autocorrelation pitch detection over a mono window. Pure + static so it can be
# unit-tested headless with synthetic sine buffers. Returns the fundamental
# frequency (Hz) and a clarity score in [0,1]; low clarity = silence/noise.
#
# Normalization: r(τ) = Σ x(i)·x(i+τ) / Σ x(i)²  (left-window denominator).
# For a sine at f, this equals cos(2π·f·τ/sr) independently of τ-length,
# producing a clean local maximum exactly at the fundamental period.
#
# Peak-picking: the first local maximum above threshold gives the SHORTEST
# matching period (highest frequency = fundamental), avoiding octave-down errors
# that would occur if we naively took the global maximum.

const MIN_FREQ := 50.0
const MAX_FREQ := 1500.0

static func detect(samples: PackedFloat32Array, sample_rate: float) -> Dictionary:
	var n := samples.size()
	if n < 4 or sample_rate <= 0.0:
		return {"frequency": 0.0, "clarity": 0.0}

	var mean := 0.0
	for s in samples:
		mean += s
	mean /= float(n)

	var total_energy := 0.0
	for i in n:
		var v := samples[i] - mean
		total_energy += v * v
	if total_energy <= 0.00001:
		return {"frequency": 0.0, "clarity": 0.0}

	var min_lag := int(sample_rate / MAX_FREQ)
	var max_lag := int(sample_rate / MIN_FREQ)
	max_lag = min(max_lag, n - 1)
	if min_lag < 1:
		min_lag = 1
	if max_lag <= min_lag:
		return {"frequency": 0.0, "clarity": 0.0}

	# Build per-lag-normalized correlation array.
	var corrs := PackedFloat32Array()
	corrs.resize(max_lag + 1)
	for lag in range(min_lag, max_lag + 1):
		var numer := 0.0
		var win_energy := 0.0
		for i in range(n - lag):
			var a := samples[i] - mean
			numer += a * (samples[i + lag] - mean)
			win_energy += a * a
		if win_energy > 0.00001:
			corrs[lag] = numer / win_energy

	# Find global max for threshold + clarity.
	var global_max := 0.0
	for lag in range(min_lag, max_lag + 1):
		if corrs[lag] > global_max:
			global_max = corrs[lag]

	if global_max < 0.3:
		return {"frequency": 0.0, "clarity": 0.0}

	# Peak-pick: first local maximum above threshold (= shortest valid period).
	var threshold := maxf(0.5, 0.85 * global_max)
	var best_lag := -1
	for lag in range(min_lag + 1, max_lag):
		if corrs[lag] > threshold and corrs[lag] >= corrs[lag - 1] and corrs[lag] >= corrs[lag + 1]:
			best_lag = lag
			break

	if best_lag < 0:
		return {"frequency": 0.0, "clarity": global_max}

	# Parabolic interpolation for sub-sample precision.
	var lag_f := float(best_lag)
	if best_lag > min_lag and best_lag < max_lag:
		var c0 := corrs[best_lag - 1]
		var c1 := corrs[best_lag]
		var c2 := corrs[best_lag + 1]
		var denom := c0 - 2.0 * c1 + c2
		if abs(denom) > 0.000001:
			lag_f = float(best_lag) + 0.5 * (c0 - c2) / denom

	return {"frequency": sample_rate / lag_f, "clarity": clamp(global_max, 0.0, 1.0)}
