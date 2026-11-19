class_name SoundFalloff
extends RefCounted
## Static helpers for distance-based loudness (free-field inverse-square law).
##
## A sound source is treated as a point source in open air. Its level falls by
## [code]20 * log10(d / d_ref)[/code] decibels, about 6.02 dB per doubling of
## distance. An optional air-absorption term subtracts
## [code]absorption_db_per_km * (d - d_ref) / 1000[/code] (distances in metres).
## [codeblock]
## L(d) = L_ref - 20 * log10(d / d_ref) - alpha * (d - d_ref) / 1000
## [/codeblock]
## All functions are static: call them as [code]SoundFalloff.level_at_distance(...)[/code].
## Distances can be in any unit as long as [param distance] and
## [param ref_distance] use the same one. [param unit_in_meters] is only used
## by the absorption term ([code]1.0[/code] for Godot units / metres,
## [constant METERS_PER_FOOT] for feet).
## [br][br]
## Invalid input (non-positive distance, NaN, ...) reports an error with
## [method @GlobalScope.push_error] and returns [constant @GDScript.NAN].
## [br][br]
## Limits: free field only (no ground reflection, walls, wind or temperature
## gradients); not valid very close to a large source; results are estimates,
## not measurements.

## Metres in one international foot.
const METERS_PER_FOOT: float = 0.3048

## Approximate atmospheric absorption in dB/km at 10 degC and 70 % relative
## humidity (an ISO 9613-2 table condition, from the ISO 9613-1 equations).
## Keys are octave-band centre frequencies in Hz. Rounded, typical values:
## use them as a rough guide only.
const AIR_ABSORPTION_DB_PER_KM: Dictionary = {
	63: 0.1,
	125: 0.4,
	250: 1.0,
	500: 1.9,
	1000: 3.7,
	2000: 9.7,
	4000: 32.8,
	8000: 117.0,
}

const _BISECTION_STEPS: int = 200


## Estimated level (dB) at [param distance] for a source that measures
## [param source_db] at [param ref_distance].
## [codeblock]
## SoundFalloff.level_at_distance(150.0, 100.0, 10.0)  # 130.0 (150 dB at 10 ft -> 100 ft)
## [/codeblock]
static func level_at_distance(
		source_db: float,
		distance: float,
		ref_distance: float = 1.0,
		absorption_db_per_km: float = 0.0,
		unit_in_meters: float = 1.0
) -> float:
	var change: float = attenuation_db(distance, ref_distance, absorption_db_per_km, unit_in_meters)
	if not _is_finite_number("source_db", source_db) or is_nan(change):
		return NAN
	return source_db + change


## Level change (dB, usually negative) when moving from [param ref_distance]
## to [param distance]. Positive when [param distance] is closer than the
## reference.
static func attenuation_db(
		distance: float,
		ref_distance: float = 1.0,
		absorption_db_per_km: float = 0.0,
		unit_in_meters: float = 1.0
) -> float:
	if not (_is_positive("distance", distance)
			and _is_positive("ref_distance", ref_distance)
			and _is_non_negative("absorption_db_per_km", absorption_db_per_km)
			and _is_positive("unit_in_meters", unit_in_meters)):
		return NAN
	var change: float = -20.0 * _log10(distance / ref_distance)
	if absorption_db_per_km > 0.0:
		change -= absorption_db_per_km * (distance - ref_distance) * unit_in_meters / 1000.0
	return change


## Distance at which the level falls (or rises) to [param target_db]; the
## inverse of [method level_at_distance]. The result is in the unit of
## [param ref_distance].
## [br]Without absorption: [code]d = d_ref * 10^((source_db - target_db) / 20)[/code].
## With absorption there is no elementary closed form, so the root is found
## by bisection (the level strictly decreases with distance).
static func distance_for_level(
		source_db: float,
		target_db: float,
		ref_distance: float = 1.0,
		absorption_db_per_km: float = 0.0,
		unit_in_meters: float = 1.0
) -> float:
	if not (_is_finite_number("source_db", source_db)
			and _is_finite_number("target_db", target_db)
			and _is_positive("ref_distance", ref_distance)
			and _is_non_negative("absorption_db_per_km", absorption_db_per_km)
			and _is_positive("unit_in_meters", unit_in_meters)):
		return NAN
	var free_field: float = ref_distance * pow(10.0, (source_db - target_db) / 20.0)
	if free_field == 0.0 or is_inf(free_field):
		push_error("SoundFalloff: source_db and target_db are too far apart for a usable distance.")
		return NAN
	if absorption_db_per_km == 0.0 or free_field == ref_distance:
		return free_field
	# Absorption lowers the level beyond d_ref and raises it inside d_ref,
	# so the root lies between the free-field answer and the reference distance.
	var lo: float = minf(free_field, ref_distance)
	var hi: float = maxf(free_field, ref_distance)
	for _step in _BISECTION_STEPS:
		var mid: float = 0.5 * (lo + hi)
		var level: float = level_at_distance(
				source_db, mid, ref_distance, absorption_db_per_km, unit_in_meters)
		if level - target_db > 0.0:
			lo = mid
		else:
			hi = mid
		if hi - lo <= 1e-12 * hi:
			break
	return 0.5 * (lo + hi)


## Level change in dB when the distance is multiplied by [param ratio]
## (free field): [code]20 * log10(ratio)[/code]. A ratio of 10 gives 20 dB.
static func distance_ratio_loss(ratio: float) -> float:
	if not _is_positive("ratio", ratio):
		return NAN
	return 20.0 * _log10(ratio)


## Free-field loss per doubling of distance: [code]20 * log10(2)[/code], about 6.02 dB.
static func db_per_doubling() -> float:
	return distance_ratio_loss(2.0)


## Combines incoherent sources (for example two horns) into one level:
## [code]10 * log10(sum(10^(L_i / 10)))[/code]. Two equal sources add about
## 3.01 dB, not double the decibels.
static func combine_levels(levels_db: Array) -> float:
	if levels_db.is_empty():
		push_error("SoundFalloff: combine_levels needs at least one level.")
		return NAN
	var peak: float = -INF
	for value: Variant in levels_db:
		if not (value is float or value is int):
			push_error("SoundFalloff: combine_levels expects numbers, got %s." % [value])
			return NAN
		var level: float = value
		if not _is_finite_number("level", level):
			return NAN
		peak = maxf(peak, level)
	var total: float = 0.0
	for value: Variant in levels_db:
		var level: float = value
		total += pow(10.0, (level - peak) / 10.0)
	return peak + 10.0 * _log10(total)


## Amplitude ratio for a level in dB: [code]10^(db / 20)[/code]
## (same as [method @GlobalScope.db_to_linear]).
static func db_to_amplitude(db: float) -> float:
	return pow(10.0, db / 20.0)


## Level in dB for an amplitude ratio: [code]20 * log10(amplitude)[/code].
## Returns [code]-INF[/code] for 0.
static func amplitude_to_db(amplitude: float) -> float:
	if not _is_non_negative("amplitude", amplitude):
		return NAN
	if amplitude == 0.0:
		return -INF
	return 20.0 * _log10(amplitude)


## Power (intensity) ratio for a level in dB: [code]10^(db / 10)[/code].
static func db_to_power(db: float) -> float:
	return pow(10.0, db / 10.0)


## Level in dB for a power (intensity) ratio: [code]10 * log10(power)[/code].
## Returns [code]-INF[/code] for 0.
static func power_to_db(power: float) -> float:
	if not _is_non_negative("power", power):
		return NAN
	if power == 0.0:
		return -INF
	return 10.0 * _log10(power)


## Converts feet to metres.
static func feet_to_meters(feet: float) -> float:
	return feet * METERS_PER_FOOT


## Converts metres to feet.
static func meters_to_feet(meters: float) -> float:
	return meters / METERS_PER_FOOT


static func _log10(x: float) -> float:
	return log(x) / log(10.0)


static func _is_finite_number(name: String, value: float) -> bool:
	if is_nan(value) or is_inf(value):
		push_error("SoundFalloff: %s must be a finite number, got %s." % [name, value])
		return false
	return true


static func _is_positive(name: String, value: float) -> bool:
	if not _is_finite_number(name, value):
		return false
	if value <= 0.0:
		push_error("SoundFalloff: %s must be greater than 0, got %s." % [name, value])
		return false
	return true


static func _is_non_negative(name: String, value: float) -> bool:
	if not _is_finite_number(name, value):
		return false
	if value < 0.0:
		push_error("SoundFalloff: %s must be 0 or greater, got %s." % [name, value])
		return false
	return true
