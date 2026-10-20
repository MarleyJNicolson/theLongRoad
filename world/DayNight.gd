class_name DayNight
extends RefCounted

# The time of day (not in the JS original). A day lasts DAY seconds, ending in
# a DUSK fading to night; the night lasts NIGHT seconds, ending in a DAWN.
# Runs start in the morning, so the first town is easily reached in daylight.

const DAY := 480.0 # seconds of daylight, including the dusk at its end
const NIGHT := 240.0 # seconds of night, including the dawn at its end
const DUSK := 40.0
const DAWN := 40.0
const CYCLE := DAY + NIGHT

# The world's tint: daylight, a warm glow at dusk and dawn, deep blue night.
const NIGHT_TINT := Color(0.30, 0.34, 0.52)
const GLOW_TINT := Color(1.0, 0.72, 0.52)


# How dark it is at `clock` seconds into the cycle: 0 by day, 1 at night.
static func darkness(clock: float) -> float:
	var t := fposmod(clock, CYCLE)
	if t < DAY - DUSK:
		return 0.0
	if t < DAY:
		return smoothstep(0.0, 1.0, (t - (DAY - DUSK)) / DUSK)
	if t < CYCLE - DAWN:
		return 1.0
	return 1.0 - smoothstep(0.0, 1.0, (t - (CYCLE - DAWN)) / DAWN)


static func tint(clock: float) -> Color:
	var dark := darkness(clock)
	var colour := Color.WHITE.lerp(NIGHT_TINT, dark)
	# Warm in the middle of the turn, at dusk and dawn
	return colour.lerp(GLOW_TINT, sin(dark * PI) * 0.35)


static func is_night(clock: float) -> bool:
	return darkness(clock) > 0.5


# Seconds until dusk begins (by day) or dawn ends (by night).
static func until_change(clock: float) -> float:
	var t := fposmod(clock, CYCLE)
	return (DAY - DUSK - t) if t < DAY - DUSK else (CYCLE - t if t >= DAY else CYCLE - t)


# "morning", "afternoon", "dusk", "night" or "dawn".
static func phase(clock: float) -> String:
	var t := fposmod(clock, CYCLE)
	if t < (DAY - DUSK) / 2:
		return "morning"
	if t < DAY - DUSK:
		return "afternoon"
	if t < DAY:
		return "dusk"
	if t < CYCLE - DAWN:
		return "night"
	return "dawn"
