class_name ItemIcon
extends RefCounted

# Item pictures (port of ItemIcon.vue): simple silhouettes in a 40×40 box,
# kept as the same SVG path data and drawn with a small path reader (M L H V
# Q A Z, absolute coordinates). `trim` parts turn gold on fine gear; `color`
# fixes a part's colour regardless of tier; `line` parts are strokes (`wide`
# ones thicker).

const ICONS := {
	"helmet": [{"d": "M8 26 Q8 7 20 7 Q32 7 32 26 Z"}, {"d": "M5 25 H35 V30 H5 Z"}, {"d": "M18.5 26 H21.5 V35 H18.5 Z", "trim": true}],
	"shoulders": [{"d": "M3 27 Q4 12 17 11 L17 29 Z"}, {"d": "M37 27 Q36 12 23 11 L23 29 Z"}, {"d": "M8 17 L13 15 M27 15 L32 17", "line": true, "trim": true}],
	"body": [{"d": "M10 7 L30 7 L34 16 L29 18 L29 34 L11 34 L11 18 L6 16 Z"}, {"d": "M20 9 V32 M13 22 H27", "line": true, "trim": true}],
	"legs": [{"d": "M11 5 H29 V13 L26.5 35 H21.5 L20 17 L18.5 35 H13.5 L11 13 Z"}, {"d": "M11 10 H29", "line": true, "trim": true}],
	"stone": [{"d": "M13 22 Q12 13 20 12 Q29 12 28 21 Q28 29 20 29 Q13 29 13 22 Z"}],
	"fist": [{"d": "M11 14 Q11 10 15 10 H27 Q30 10 30 14 V24 Q30 31 23 31 H17 Q11 31 11 25 Z"}, {"d": "M17 10 V18 M23 10 V18", "line": true}],
	"sling": [
		{"d": "M12 8 A3 3 0 1 1 12.1 8", "line": true}, # finger loop
		{"d": "M12 11 L20 27 M15 9 L26 25", "line": true},
		{"d": "M17 26 Q22 34 29 24 Q23 29 17 26 Z"},
		{"d": "M21 27.5 A2.6 2.6 0 1 1 21.1 27.5 Z", "color": "#9a968c"}, # the stone
	],
	"bow": [{"d": "M13 4 Q37 20 13 36", "line": true, "wide": true}, {"d": "M13 4 L13 36", "line": true, "trim": true}, {"d": "M8 20 H32 M28 17 L32 20 L28 23", "line": true}],
	"crossbow": [{"d": "M20 9 V36", "line": true, "wide": true}, {"d": "M5 15 Q20 5 35 15", "line": true, "wide": true}, {"d": "M5 15 L20 19 L35 15", "line": true, "trim": true}],
	"club": [{"d": "M9 33 L12 36 L31 14 Q33 6 26 6 Z"}, {"d": "M24 12 L27 15 M27 9 L30 12", "line": true, "trim": true}],
	"sword": [{"d": "M28 5 L33 7 L31 12 L16 27 L12 23 Z"}, {"d": "M8 20 L19 31", "line": true, "wide": true, "trim": true}, {"d": "M13 27 L7 33", "line": true, "wide": true}],
	"spear": [{"d": "M6 35 L28 10", "line": true, "wide": true}, {"d": "M25 9 L36 3 L31 15 Z", "trim": true}],
	"axe": [{"d": "M10 35 L26 7", "line": true, "wide": true}, {"d": "M21 5 Q36 4 33 20 L25 14 Z", "trim": true}],
	# The off hand
	"shield": [
		{"d": "M20 5 Q31 8 33 12 Q33 27 20 36 Q7 27 7 12 Q9 8 20 5 Z"},
		{"d": "M20 9 V32 M10 14 H30", "line": true, "trim": true},
		{"d": "M17 17 H23 V23 H17 Z", "color": "#a6aeb7"},
	],
	"quiver": [
		{"d": "M9 13 L23 7 L32 29 L18 35 Z"},
		{"d": "M11 16 Q24 19 31 29", "line": true, "trim": true},
		{"d": "M12 11 L8 3 M16 9 L13 1 M20 8 L19 1", "line": true, "color": "#8b6236"},
		{"d": "M8 3 L6 6 M13 1 L11 4 M19 1 L17 4", "line": true, "color": "#e8e0c8"},
	],
	# Ammunition stacks
	"stones": [
		{"d": "M7 26 Q7 20 13 20 Q19 20 19 26 Q19 31 13 31 Q7 31 7 26 Z", "color": "#8d8a80"},
		{"d": "M20 24 Q20 17 27 17 Q34 17 33 24 Q33 30 27 30 Q20 30 20 24 Z", "color": "#a8a59a"},
		{"d": "M13 15 Q13 9 19 9 Q25 9 25 15 Q25 20 19 20 Q13 20 13 15 Z", "color": "#7c766c"},
	],
	"arrows": [
		{"d": "M8 33 L31 8 M13 34 L34 12 M6 28 L28 6", "line": true, "color": "#8b6236"},
		{"d": "M31 8 L33 4 L35 9 Z M34 12 L37 9 L37 14 Z M28 6 L29 2 L32 6 Z", "color": "#d8dde2"},
		{"d": "M8 33 L5 31 M8 33 L7 36 M13 34 L10 32 M13 34 L12 37 M6 28 L3 26 M6 28 L5 31", "line": true, "color": "#e8e0c8"},
	],
	"bolts": [
		{"d": "M10 30 L28 12 M16 32 L33 15", "line": true, "wide": true, "color": "#5e3f22"},
		{"d": "M28 12 L32 9 L31 14 Z M33 15 L37 12 L36 17 Z", "color": "#a6b0bb"},
	],
	"poultice": [
		{"d": "M9 20 Q9 11 20 11 Q31 11 31 20 Q31 33 20 33 Q9 33 9 20 Z", "color": "#c9b98c"},
		{"d": "M15 11 Q20 4 25 11", "line": true, "color": "#7a5a34"},
		{"d": "M20 16 V28 M14 22 H26", "line": true, "wide": true, "color": "#c0392b"},
	],
	"planks": [
		{"d": "M5 12 L33 6 L35 13 L7 19 Z", "color": "#b98a52"},
		{"d": "M5 24 L33 18 L35 25 L7 31 Z", "color": "#8b6236"},
		{"d": "M11 13 V14 M28 9 V10 M11 25 V26 M28 21 V22", "line": true, "wide": true, "color": "#d0d0d0"},
	],
	# Not items: the bag and cart buttons on the equipment panel
	"bag": [
		{"d": "M14 13 Q14 5 20 5 Q26 5 26 13", "line": true, "wide": true, "color": "#5e3f22"},
		{"d": "M7 15 Q7 12 10 12 H30 Q33 12 33 15 L31 33 Q31 36 28 36 H12 Q9 36 9 33 Z", "color": "#8b6236"},
		{"d": "M7 16 Q20 24 33 16", "line": true, "color": "#5e3f22"},
		{"d": "M17.5 18 H22.5 V23 H17.5 Z", "color": "#d4a32a"},
	],
	"cart": [
		{"d": "M7 9 H12 V31 H7 Z", "color": "#3a2a1a"},
		{"d": "M28 9 H33 V31 H28 Z", "color": "#3a2a1a"},
		{"d": "M10 6 H30 V34 H10 Z", "color": "#8b6236"},
		{"d": "M10 15 H30 M10 24 H30", "line": true, "color": "#6e4a28"},
		{"d": "M12 12 A4 3.5 0 1 1 12.1 12 Z", "color": "#d9b44a"},
		{"d": "M19 20 A4 3 0 1 1 19.1 20 Z", "color": "#c9b28a"},
		{"d": "M20 34 V39", "line": true, "wide": true, "color": "#5e3f22"},
	],
}

static var _parsed := {} # path data -> Array of PackedVector2Array (one per subpath)


# Draw the picture for `item` (anything with { icon, tier }), or the empty
# slot's `silhouette`, filling `rect` on `ci` (call from its _draw).
static func draw(ci: CanvasItem, rect: Rect2, item: Variant, silhouette := "", alpha := 1.0) -> void:
	var icon: String = item.icon if item and item.has("icon") else silhouette
	if not ICONS.has(icon):
		return
	var tier: int = item.get("tier", 0) if item else 0
	var base: Color = Items.TIER_COLOURS[clampi(tier, 0, 3)].fill
	var k := minf(rect.size.x, rect.size.y) / 40.0
	var origin := rect.position + (rect.size - Vector2(40, 40) * k) / 2
	for part in ICONS[icon]:
		var colour: Color = Color(part.color) if part.has("color") else (Color("#d4a32a") if part.get("trim", false) and tier == 3 else base)
		colour.a *= alpha
		for sub in _subpaths(part.d):
			var pts := PackedVector2Array()
			for p in sub:
				pts.append(origin + p * k)
			if part.get("line", false):
				Sketch.round_line(ci, pts, (3.5 if part.get("wide", false) else 2.0) * k, colour)
			else:
				Sketch.fill(ci, pts, colour)
				var outline := pts.duplicate()
				outline.append(pts[0])
				ci.draw_polyline(outline, Color(0, 0, 0, 0.45 * alpha), 1.2 * k)


# Parse SVG path data into point lists, one per subpath (curves sampled).
static func _subpaths(d: String) -> Array:
	if _parsed.has(d):
		return _parsed[d]
	var tokens := []
	var number := ""
	for ch in d:
		if ch in "MLHVQAZ":
			if number != "":
				tokens.append(float(number))
				number = ""
			tokens.append(ch)
		elif ch == " " or ch == ",":
			if number != "":
				tokens.append(float(number))
				number = ""
		else:
			number += ch
	if number != "":
		tokens.append(float(number))

	var out := []
	var sub := PackedVector2Array()
	var at := Vector2.ZERO
	var start := Vector2.ZERO
	var cmd := ""
	# (Shared by reference: a lambda would capture a plain int by value)
	var pos := {"k": 0}
	var next := func() -> float:
		pos.k += 1
		return tokens[pos.k - 1]
	while pos.k < tokens.size():
		if tokens[pos.k] is String:
			cmd = tokens[pos.k]
			pos.k += 1
		match cmd:
			"M":
				if sub.size() > 1:
					out.append(sub)
				at = Vector2(next.call(), next.call())
				start = at
				sub = PackedVector2Array([at])
				cmd = "L" # further pairs are line-tos
			"L":
				at = Vector2(next.call(), next.call())
				sub.append(at)
			"H":
				at = Vector2(next.call(), at.y)
				sub.append(at)
			"V":
				at = Vector2(at.x, next.call())
				sub.append(at)
			"Q":
				var control := Vector2(next.call(), next.call())
				var end := Vector2(next.call(), next.call())
				var curve := Sketch.quad_curve(at, control, end, 8)
				sub.append_array(curve.slice(1))
				at = end
			"A":
				var rx: float = next.call()
				var ry: float = next.call()
				next.call() # rotation (always 0 here)
				var large: bool = next.call() != 0.0
				var sweep: bool = next.call() != 0.0
				var end := Vector2(next.call(), next.call())
				sub.append_array(_arc(at, end, rx, ry, large, sweep))
				at = end
			"Z":
				at = start
				if sub.size() > 1:
					out.append(sub)
				sub = PackedVector2Array()
	if sub.size() > 1:
		out.append(sub)
	_parsed[d] = out
	return out


# An elliptical arc from a to b (SVG's endpoint form, no rotation), sampled.
static func _arc(a: Vector2, b: Vector2, rx: float, ry: float, large: bool, sweep: bool) -> PackedVector2Array:
	# Work in a space where the ellipse is a unit circle
	var p := Vector2((a.x - b.x) / 2 / rx, (a.y - b.y) / 2 / ry)
	var d2 := p.length_squared()
	var scale := sqrt(maxf(0.0, 1.0 / maxf(d2, 1e-9) - 1.0))
	if large == sweep:
		scale = -scale
	var c := Vector2(scale * p.y, -scale * p.x)
	var centre := Vector2(c.x * rx + (a.x + b.x) / 2, c.y * ry + (a.y + b.y) / 2)
	var t0 := atan2((p.y - c.y), (p.x - c.x))
	var t1 := atan2((-p.y - c.y), (-p.x - c.x))
	var span := t1 - t0
	if sweep and span < 0:
		span += TAU
	elif not sweep and span > 0:
		span -= TAU
	var pts := PackedVector2Array()
	var steps := 16
	for n in range(1, steps + 1):
		var t := t0 + span * n / steps
		pts.append(centre + Vector2(cos(t) * rx, sin(t) * ry))
	return pts
