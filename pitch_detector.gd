class_name PitchDetector
extends RefCounted

# McLeod Pitch Method (MPM) detection over a mono window. Pure + static so it
# can be unit-tested headless with synthetic buffers. Returns the fundamental
# frequency (Hz) and a clarity score in [0,1]; low clarity = silence/noise.
#
# NSDF normalization: n(τ) = 2·Σ x(i)·x(i+τ) / Σ (x(i)² + x(i+τ)²).
# Unlike a left-window-only normalization, the denominator covers BOTH windows,
# so the value stays in [-1, 1] even while a plucked note decays — the exact
# signal a tuner sees. The denominator is O(1) per lag via a prefix sum of
# squares; only the numerator needs the O(n−τ) loop.
#
# Peak-picking (MPM "key maxima"): after the NSDF first goes negative, record
# one maximum per positive region (between zero crossings), then accept the
# FIRST key maximum ≥ K_THRESHOLD × the best key maximum. Taking the shortest
# qualifying period avoids octave-down errors; the k·max bar stops shoulder
# ripples and dominant-harmonic (octave-up) errors.
#
# Two-stage search for speed: a coarse pass on a 4× average-pooled copy finds
# the period region (~16× fewer numerator ops), then the NSDF is re-evaluated
# at full rate only within ±REFINE_SPAN lags of the coarse estimate and refined
# with parabolic interpolation — full-rate cents precision at a fraction of the
# cost, which matters for GDScript on phones.

const MIN_FREQ := 50.0
const MAX_FREQ := 1500.0
const K_THRESHOLD := 0.9   # key-maximum acceptance fraction of the best peak
const MIN_PEAK := 0.3      # below this even the best peak is treated as no pitch
const DECIMATION := 4
const REFINE_SPAN := 6     # full-rate lags searched either side of the coarse lag


static func detect(samples: PackedFloat32Array, sample_rate: float) -> Dictionary:
	var n := samples.size()
	if n < 64 or sample_rate <= 0.0:
		return {"frequency": 0.0, "clarity": 0.0}

	# Center the signal once; both passes reuse the copy.
	var mean := 0.0
	for s in samples:
		mean += s
	mean /= float(n)

	var x := PackedFloat32Array()
	x.resize(n)
	var total_energy := 0.0
	for i in n:
		var v := samples[i] - mean
		x[i] = v
		total_energy += v * v
	if total_energy <= 0.00001:
		return {"frequency": 0.0, "clarity": 0.0}

	# Stage 1 — coarse MPM on the average-pooled copy.
	var dn := n / DECIMATION
	var dec := PackedFloat32Array()
	dec.resize(dn)
	for i in dn:
		var b := i * DECIMATION
		dec[i] = (x[b] + x[b + 1] + x[b + 2] + x[b + 3]) * 0.25
	var dec_rate := sample_rate / float(DECIMATION)
	var min_lag_d := maxi(int(dec_rate / MAX_FREQ), 2)
	var max_lag_d := mini(int(dec_rate / MIN_FREQ), dn - 8)
	if max_lag_d <= min_lag_d:
		return {"frequency": 0.0, "clarity": 0.0}
	var coarse := _mpm_key_maximum(dec, min_lag_d, max_lag_d)
	if int(coarse.lag) <= 0:
		return {"frequency": 0.0, "clarity": 0.0}

	# Stage 2 — full-rate NSDF around the coarse estimate + parabolic interp.
	var center := int(coarse.lag) * DECIMATION
	var lo := maxi(center - REFINE_SPAN, 2)
	var hi := mini(center + REFINE_SPAN, n - 8)
	if hi <= lo:
		return {"frequency": 0.0, "clarity": 0.0}

	var prefix := PackedFloat64Array()
	prefix.resize(n + 1)
	prefix[0] = 0.0
	for i in n:
		prefix[i + 1] = prefix[i] + x[i] * x[i]

	var count := hi - lo + 1
	var vals := PackedFloat32Array()
	vals.resize(count)
	var best_i := 0
	for k in count:
		var lag := lo + k
		var m := n - lag
		var numer := 0.0
		for i in m:
			numer += x[i] * x[i + lag]
		var denom: float = prefix[m] + (prefix[n] - prefix[lag])
		vals[k] = (2.0 * numer / denom) if denom > 0.000000001 else 0.0
		if vals[k] > vals[best_i]:
			best_i = k

	var lag_f := float(lo + best_i)
	if best_i > 0 and best_i < count - 1:
		var c0 := vals[best_i - 1]
		var c1 := vals[best_i]
		var c2 := vals[best_i + 1]
		var denom2 := c0 - 2.0 * c1 + c2
		if abs(denom2) > 0.000001:
			lag_f += 0.5 * (c0 - c2) / denom2

	return {
		"frequency": sample_rate / lag_f,
		"clarity": clampf(vals[best_i], 0.0, 1.0),
	}


# One coarse MPM pass: NSDF over lags 1..max_lag, key maxima between zero
# crossings, first-above-k·max selection. Returns {lag: int, value: float};
# lag ≤ 0 means no acceptable pitch.
static func _mpm_key_maximum(x: PackedFloat32Array, min_lag: int, max_lag: int) -> Dictionary:
	var n := x.size()
	var prefix := PackedFloat64Array()
	prefix.resize(n + 1)
	prefix[0] = 0.0
	for i in n:
		prefix[i + 1] = prefix[i] + x[i] * x[i]

	var nsdf := PackedFloat32Array()
	nsdf.resize(max_lag + 1)
	for lag in range(1, max_lag + 1):
		var m := n - lag
		var numer := 0.0
		for i in m:
			numer += x[i] * x[i + lag]
		var denom: float = prefix[m] + (prefix[n] - prefix[lag])
		nsdf[lag] = (2.0 * numer / denom) if denom > 0.000000001 else 0.0

	# Key maxima: one candidate per positive region after the first negative dip
	# (the dip skips the zero-lag lobe, which is not a period peak).
	var key_lags: Array[int] = []
	var key_vals: Array[float] = []
	var crossed_negative := false
	var in_region := false
	var region_lag := -1
	var region_val := 0.0
	for lag in range(1, max_lag + 1):
		var v := nsdf[lag]
		if v <= 0.0:
			if in_region and region_lag >= min_lag:
				key_lags.append(region_lag)
				key_vals.append(region_val)
			in_region = false
			crossed_negative = true
		elif crossed_negative:
			if not in_region:
				in_region = true
				region_lag = -1
				region_val = 0.0
			if v > region_val:
				region_val = v
				region_lag = lag
	if in_region and region_lag >= min_lag:
		key_lags.append(region_lag)
		key_vals.append(region_val)

	if key_lags.is_empty():
		return {"lag": -1, "value": 0.0}

	var best := 0.0
	for v in key_vals:
		if v > best:
			best = v
	if best < MIN_PEAK:
		return {"lag": -1, "value": best}

	var threshold := K_THRESHOLD * best
	for i in key_lags.size():
		if key_vals[i] >= threshold:
			return {"lag": key_lags[i], "value": key_vals[i]}
	return {"lag": -1, "value": best}
