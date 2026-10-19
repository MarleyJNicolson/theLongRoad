class_name Scenery
extends RefCounted

# Trees, rocks, ruins and ground clutter (port of scenery.js). Dresses the land
# on both sides of the road, out past the edge of the screen, and keeps it
# clear of the road, side roads and encounters.
#
# Everything standing up is drawn in three-quarter view like the people: its
# base sits at the origin (where it meets the ground) and it rises up the
# screen.

const SPREAD := 950.0 # how far from the road the land is dressed
const ATTEMPTS := 5 # tries per side for each stretch of road

const BARK := Color("#5c4632")
const BARK_SHADE := Color("#46352a")

# Relative chances of each feature in each region. `size` is a radius range;
# `upright` things stand up and are depth-sorted with the people (a trunk or
# boulder hides whoever is behind it); `solid` is how much of the base you
# can't pass through (for trees, just the trunk: [per radius, plus]); `spin`
# things lie flat on the ground and can be turned any way.
const FEATURES := {
	"oak": {"size": [26, 44], "upright": true, "solid": [0.16, 4], "grove": 0.35, "tree": true},
	"birch": {"size": [16, 24], "upright": true, "solid": [0, 4], "grove": 0.5, "tree": true},
	"pine": {"size": [20, 36], "upright": true, "solid": [0.1, 4], "grove": 0.6, "tree": true},
	"deadTree": {"size": [22, 34], "upright": true, "solid": [0, 5], "tree": true},
	# `stones` is how many stones can be gathered from it
	"boulder": {"size": [16, 32], "upright": true, "solid": [0.85, 0], "stones": [10, 16]},
	"rock": {"size": [5, 12], "stones": [3, 6]},
	"stump": {"size": [6, 10]},
	"log": {"size": [16, 26], "spin": true},
	"bush": {"size": [10, 17]},
	"tufts": {"size": [10, 10]},
	"flowers": {"size": [10, 16], "spin": true},
	"mushrooms": {"size": [8, 12]},
	"bones": {"size": [8, 12], "spin": true},
	"patch": {"size": [70, 140], "flat": true, "spin": true},
	"ruin": {"size": [48, 48], "parts": true},
	"stones": {"size": [40, 46], "parts": true},
}

const MIXES := {
	"The Meadows": {"oak": 10, "birch": 6, "pine": 2, "deadTree": 1, "bush": 9, "boulder": 2, "rock": 6, "stump": 2, "log": 1.5, "flowers": 8, "tufts": 14, "patch": 2, "ruin": 0.4, "stones": 0.15},
	"The Darkwood": {"pine": 16, "oak": 6, "deadTree": 4, "bush": 8, "mushrooms": 6, "log": 4, "stump": 4, "boulder": 2, "rock": 3, "tufts": 8, "patch": 2, "bones": 1, "ruin": 0.35, "stones": 0.1},
	"The Barrens": {"deadTree": 5, "oak": 1, "bush": 7, "boulder": 6, "rock": 10, "bones": 4, "tufts": 12, "patch": 3, "ruin": 0.5, "stones": 0.3},
	"The Frostmarch": {"pine": 12, "deadTree": 3, "birch": 3, "boulder": 5, "rock": 6, "tufts": 6, "log": 2, "patch": 2, "ruin": 0.35, "stones": 0.3},
}

var patches: Node2D # ground colour patches lie under everything
var ground: Node2D
var upright: Node2D
var road: Road
var get_zones: Callable # areas (camps, roadblocks) to keep clear: Array of Vector3(x, y, radius)
# { obj, extras, index, x, y, r, big, solids, gather, kind, height }
var items: Array = []
var placed_up_to := 0
var _obstacles: Array = []
var _obstacles_dirty := true


# `upright_layer` is the depth-sorted layer shared with the people.
func _init(ground_layer: Node2D, upright_layer: Node2D, road_: Road, get_zones_: Callable = Callable()) -> void:
	patches = Node2D.new()
	ground_layer.add_child(patches)
	ground = ground_layer
	upright = upright_layer
	road = road_
	get_zones = get_zones_ if get_zones_.is_valid() else func() -> Array: return []


# Everything solid, as Vector3(x, y, radius).
func obstacles() -> Array:
	if _obstacles_dirty:
		_obstacles = []
		for item in items:
			_obstacles.append_array(item.solids)
		_obstacles_dirty = false
	return _obstacles


# Remove anything already standing inside these zones (a side road laid
# through ground that has been planted).
func clear(zones: Array) -> void:
	items = items.filter(func(item: Dictionary) -> bool:
		for z: Vector3 in zones:
			if Vector2(z.x, z.y).distance_to(Vector2(item.x, item.y)) < z.z + item.r * 0.5:
				_remove(item)
				return false
		return true)
	_obstacles_dirty = true


# `budget` caps how many stretches of road get dressed this frame, so a
# freshly generated chunk of road is spread over several frames.
func update(index: int, budget := 1 << 30) -> void:
	# Lag behind generation so we can check clearance against upcoming road.
	while budget > 0 and placed_up_to < road.points.size() - 40:
		budget -= 1
		_place_around(placed_up_to)
		placed_up_to += 1
	var before := items.size()
	items = items.filter(func(item: Dictionary) -> bool:
		if item.index >= index - 80:
			return true
		_remove(item)
		return false)
	if items.size() != before:
		_obstacles_dirty = true


func _remove(item: Dictionary) -> void:
	item.obj.queue_free()
	for o in item.extras:
		o.queue_free()


# Trees you're standing behind fade, so you never lose sight of yourself.
func fade_around(x: float, y: float) -> void:
	for item in items:
		if not item.height:
			continue
		var hidden: bool = y < item.y and y > item.y - item.height and absf(x - item.x) < item.r + 6
		var target := 0.4 if hidden else 1.0
		item.obj.modulate.a += (target - item.obj.modulate.a) * 0.2


func _place_around(i: int) -> void:
	var p := road.points[i]
	var n := road.normal(i)
	var biome: Dictionary = Threat.stage_at(Road.along(i) / 20.0).biome
	var mix: Dictionary = MIXES.get(biome.name, MIXES["The Meadows"])
	for side: float in [-1.0, 1.0]:
		for k in ATTEMPTS:
			var feature := _choose(mix)
			# Spread evenly across the whole width, not bunched by the road
			var offset := Road.ROAD_WIDTH / 2 + 30 + randf() * SPREAD
			var x := p.x + n.x * offset * side + randf_range(-15, 15)
			var y := p.y + n.y * offset * side + randf_range(-15, 15)
			var f: Dictionary = FEATURES[feature]
			if _place(feature, x, y, i, biome) and f.has("grove") and randf() < f.grove:
				# Trees like company
				for g in floori(randf_range(2, 5)):
					var a := randf() * TAU
					var d := randf_range(40, 90)
					_place(feature, x + cos(a) * d, y + sin(a) * d, i, biome)


static func _choose(mix: Dictionary) -> String:
	var total := 0.0
	for w in mix.values():
		total += w
	var roll := randf() * total
	for feature in mix:
		roll -= mix[feature]
		if roll < 0:
			return feature
	return "tufts"


func _place(feature: String, x: float, y: float, i: int, biome: Dictionary) -> bool:
	var f: Dictionary = FEATURES[feature]
	var r := randf_range(f.size[0], f.size[1])
	var big: bool = f.has("solid") or f.has("parts")
	if not _is_clear(x, y, i, 0.0 if f.has("flat") else r + 12, r if big else 0.0):
		return false

	var drawn: Dictionary = _draw_feature(feature, r, biome)
	var obj: Node2D = drawn.g
	obj.position = Vector2(x, y)
	if f.has("spin"):
		obj.rotation = randf() * TAU
	if f.has("upright"):
		upright.add_child(obj) # depth-sorted by where it meets the ground
	else:
		(patches if f.has("flat") else ground).add_child(obj)

	var solids := []
	var extras := []
	if f.has("parts"):
		for q: Vector3 in drawn.solids:
			solids.append(Vector3(x + q.x, y + q.y, q.z))
		# Separate standing pieces (stones in a ring), each sorted by its own base
		for u in drawn.uprights:
			u.g.position = Vector2(x + u.x, y + u.y)
			upright.add_child(u.g)
			extras.append(u.g)
	elif f.has("solid"):
		solids = [Vector3(x, y, r * f.solid[0] + f.solid[1])]
	var gather := randi_range(f.stones[0], f.stones[1]) if f.has("stones") else 0
	var height: float = drawn.get("height", 0.0) if f.has("tree") else 0.0 # only trees fade (see fade_around)
	items.append({"obj": obj, "extras": extras, "index": i, "x": x, "y": y, "r": r, "big": big,
		"solids": solids, "gather": gather, "kind": feature, "height": height})
	if not solids.is_empty():
		_obstacles_dirty = true
	return true


# The nearest rock or boulder with stones left, within `reach` of its edge.
func gatherable_near(x: float, y: float, reach: float) -> Variant:
	var best: Variant = null
	var best_dist := INF
	for item in items:
		if not item.gather:
			continue
		var d: float = Vector2(item.x - x, item.y - y).length() - item.r
		if d < reach and d < best_dist:
			best = item
			best_dist = d
	return best


# Take stones from a rock: small rocks are carried off whole once empty;
# boulders stay, chipped and pale.
func quarry(item: Dictionary, taken: int) -> void:
	item.gather = maxi(0, item.gather - taken)
	if item.gather:
		return
	if item.kind == "rock":
		_remove(item)
		items.erase(item)
	else:
		item.obj.modulate = Color("#c8c2b8", item.obj.modulate.a)
		for k in 6:
			item.obj.circle(Vector2(randf_range(-item.r, item.r) * 0.8, -item.r * randf_range(0.1, 1.1)), randf_range(1, 2.5), Color("#a8a59a"))


# Clear of the road, encounters, and (for big things) other big things.
func _is_clear(x: float, y: float, i: int, margin: float, room: float) -> bool:
	var at := Vector2(x, y)
	for z: Vector3 in get_zones.call():
		if Vector2(z.x, z.y).distance_to(at) < z.z + margin:
			return false
	var pts := road.points
	var road_clear := pow(Road.ROAD_WIDTH / 2 + margin, 2)
	for j in range(maxi(0, i - 70), mini(pts.size(), i + 70)):
		if pts[j].distance_squared_to(at) < road_clear:
			return false
	if room:
		var k := items.size() - 1
		while k >= 0 and k > items.size() - 400:
			var o: Dictionary = items[k]
			if o.big and Vector2(o.x - x, o.y - y).length() < (o.r + room) * 0.8:
				return false
			k -= 1
	return true


# --- Drawing ---------------------------------------------------------------
# Each returns { g } plus, for trees, { height }; ruins and stone rings also
# { solids: [Vector3], uprights: [{ g, x, y }] }.

static func _draw_feature(feature: String, r: float, biome: Dictionary) -> Dictionary:
	match feature:
		"oak": return _oak(r, biome)
		"birch": return _birch(r, biome)
		"pine": return _pine(r, biome)
		"deadTree": return _dead_tree(r)
		"boulder": return _boulder(r, biome)
		"rock": return {"g": _rock(r)}
		"stump": return {"g": _stump(r)}
		"log": return {"g": _fallen_log(r)}
		"bush": return {"g": bush(r, biome)}
		"tufts": return {"g": _tufts(r, biome)}
		"flowers": return {"g": _flowers(r)}
		"mushrooms": return {"g": _mushrooms(r)}
		"bones": return {"g": _bones(r)}
		"patch": return {"g": _patch(r, biome)}
		"ruin": return _ruin()
		"stones": return _standing_stones(r)
	return {"g": Sketch.new()}


static func _pick(arr: Array) -> Variant:
	return arr[randi() % arr.size()]


# The region's tree colours sorted by hex code, as the JS did: dark, mid, light.
static func _sorted(colours: Array) -> Array:
	var out := colours.duplicate()
	out.sort_custom(func(a: Color, b: Color) -> bool: return a.to_html(false) < b.to_html(false))
	return out


# A shadow on the ground, cast down and to the right (the light is from the
# top left), under something standing at the origin.
static func _shadow(g: Sketch, w: float, h: float, alpha := 0.22) -> void:
	g.ellipse(Vector2(w * 0.3, h * 0.15), w, h, Color(0, 0, 0, alpha))


static func _poly(g: Sketch, pts: Array, colour: Color) -> void:
	g.poly(PackedVector2Array(pts), colour)


# --- Trees -----------------------------------------------------------------

# A trunk rising from the ground, flared at the roots, shaded on the right.
static func _trunk(g: Sketch, width: float, height: float, colour := BARK, shade := BARK_SHADE) -> void:
	_poly(g, [Vector2(-width, 0), Vector2(-width * 0.65, -height), Vector2(width * 0.65, -height), Vector2(width, 0)], colour)
	_poly(g, [Vector2(width * 0.15, 0), Vector2(width * 0.2, -height), Vector2(width * 0.65, -height), Vector2(width, 0)], shade)
	for s in [-1.0, 1.0]:
		_poly(g, [Vector2(s * width * 0.6, 0), Vector2(s * width * 1.7, 1.5), Vector2(s * width * 0.9, -width * 0.8)], colour)


# Broad oak: a stout trunk under a big lumpy crown, lit from the top left.
static func _oak(r: float, biome: Dictionary) -> Dictionary:
	var g := Sketch.new()
	var tones := _sorted(biome.trees)
	var dark: Color = tones[0]
	var mid: Color = tones[1]
	var light: Color = tones[2]
	var stem := r * 0.8
	var cy := -(stem + r * 0.55) # middle of the crown
	_shadow(g, r * 1.05, r * 0.42)
	_trunk(g, r * 0.16 + 2, stem + r * 0.2)
	g.circle(Vector2(0, cy + r * 0.1), r, dark)
	for k in 7:
		var a := float(k) / 7 * TAU + randf_range(-0.25, 0.25)
		var lit := sin(a) < 0 # upper clumps catch the light
		g.circle(Vector2(cos(a) * r * 0.55, cy + sin(a) * r * 0.5), r * randf_range(0.38, 0.52), mid if lit else dark)
	g.circle(Vector2(-r * 0.25, cy - r * 0.3), r * 0.5, Color(light, 0.85))
	g.circle(Vector2(-r * 0.4, cy - r * 0.5), r * 0.22, Color(biome.leaf, 0.8))
	# The crown's shadowed underside
	g.ellipse(Vector2(0, cy + r * 0.62), r * 0.8, r * 0.25, Color(0, 0, 0, 0.18))
	return {"g": g, "height": stem + r * 1.55}


# Birch: a slender white trunk with dark marks and a small, airy crown.
static func _birch(r: float, biome: Dictionary) -> Dictionary:
	var g := Sketch.new()
	var stem := r * 1.4
	_shadow(g, r * 0.8, r * 0.3, 0.18)
	_trunk(g, 2.6, stem, Color("#e8e0c8"), Color("#c9bfa6"))
	for k in 5:
		g.rect(randf_range(-2, 0.5), -stem * randf_range(0.1, 0.9), randf_range(1.5, 3), 1.2, Color("#2b221c"))
	var pale := [Color("#a7aeb6"), Color("#c0c6cc"), Color("#d9dee2")] if biome.name == "The Frostmarch" \
		else [Color("#6a7f42"), Color("#7a8c4c"), Color("#8a9a55"), Color("#9fab66")]
	var cy := -stem - r * 0.3
	for k in 9:
		var x := randf_range(-r, r) * 0.55
		var y := cy + randf_range(-r, r) * 0.6
		g.circle(Vector2(x, y), r * randf_range(0.28, 0.42), pale[-1] if y < cy else _pick(pale))
	return {"g": g, "height": stem + r * 0.9}


# Pine: stacked tiers of needles narrowing to a point; snow on the tiers in
# the Frostmarch.
static func _pine(r: float, biome: Dictionary) -> Dictionary:
	var g := Sketch.new()
	var snowy: bool = biome.name == "The Frostmarch"
	var tones := _sorted(biome.trees)
	var stem := r * 0.35
	var tiers := 4
	var tier_h := r * 0.62
	_shadow(g, r * 0.9, r * 0.35)
	_trunk(g, r * 0.1 + 2, stem + 4)
	for k in tiers:
		var w := r * (1 - k * 0.2)
		var base := -stem - k * tier_h * 0.8
		var top := base - tier_h * 1.25
		_poly(g, [Vector2(-w, base), Vector2(0, top), Vector2(w, base)], tones[1] if k % 2 else tones[0])
		_poly(g, [Vector2(0, top), Vector2(w, base), Vector2(w * 0.35, base)], Color(0, 0, 0, 0.15)) # shaded side
		if snowy:
			_poly(g, [Vector2(-w * 0.55, base - tier_h * 0.55), Vector2(0, top), Vector2(w * 0.25, base - tier_h * 0.6)], Color("#eef1f2"))
		elif k == tiers - 1:
			_poly(g, [Vector2(-w * 0.35, base - tier_h * 0.6), Vector2(0, top), Vector2(0, base - tier_h * 0.4)], Color(biome.leaf, 0.6))
	return {"g": g, "height": stem + tier_h * (tiers * 0.8 + 0.45)}


# Dead tree: a bare, twisted trunk with branches clawing upward.
static func _dead_tree(r: float) -> Dictionary:
	var g := Sketch.new()
	var stem := r * 0.9
	_shadow(g, r * 0.5, r * 0.2, 0.18)
	_trunk(g, 3, stem, Color("#5c4a38"), Color("#463828"))
	var limbs := floori(randf_range(3, 5))
	for k in limbs:
		var a := -PI / 2 + (float(k) / (limbs - 1) - 0.5) * 2.2 + randf_range(-0.2, 0.2)
		_branch(g, Vector2(0, -stem * randf_range(0.7, 1)), a, r * randf_range(0.45, 0.6), 3.2)
	return {"g": g, "height": stem + r * 0.6}


static func _branch(g: Sketch, from: Vector2, a: float, length: float, w: float) -> void:
	var end := from + Vector2(cos(a), sin(a)) * length
	g.round_stroke(PackedVector2Array([from, end]), w, Color("#5c4a38"))
	if length > 7:
		_branch(g, end, a + randf_range(0.25, 0.6), length * 0.62, w * 0.65)
		_branch(g, end, a - randf_range(0.25, 0.6), length * 0.55, w * 0.65)


# --- Rocks and stones -------------------------------------------------------

# A small rock: a low mound, lit on top.
static func _rock(r: float) -> Sketch:
	var g := Sketch.new()
	_shadow(g, r * 1.1, r * 0.45, 0.25)
	g.ellipse(Vector2(0, -r * 0.3), r, r * 0.6, Color("#77736a"))
	g.ellipse(Vector2(-r * 0.2, -r * 0.45), r * 0.65, r * 0.38, Color("#9a968c"))
	return g


# A big boulder: lit top, shaded face, a crack; lichen or snow on top.
static func _boulder(r: float, biome: Dictionary) -> Dictionary:
	var g := Sketch.new()
	_shadow(g, r * 1.2, r * 0.45, 0.28)
	var pts: Array[Vector2] = []
	var sides := floori(randf_range(8, 11))
	for k in sides:
		var a := float(k) / sides * TAU
		var d := randf_range(0.82, 1.05)
		# Flat underneath, where it sits on the ground
		pts.append(Vector2(cos(a) * r * d, minf(0.0, -r * 0.6 + sin(a) * r * 0.75 * d)))
	_poly(g, pts, Color("#5f5b54"))
	_poly(g, pts.map(func(p: Vector2) -> Vector2: return Vector2(p.x * 0.85 - r * 0.08, p.y * 0.75 - r * 0.2)), Color("#7c786f"))
	_poly(g, pts.map(func(p: Vector2) -> Vector2: return Vector2(p.x * 0.5 - r * 0.15, p.y * 0.42 - r * 0.42)), Color("#9a968c"))
	g.poly_stroke(PackedVector2Array([Vector2(r * 0.1, -r * 0.9), Vector2(r * 0.25, -r * 0.5), Vector2(r * 0.12, -r * 0.1)]), 1.5, Color("#3c3a35"), false)
	if biome.name == "The Frostmarch":
		g.ellipse(Vector2(-r * 0.1, -r * 1.05), r * 0.65, r * 0.25, Color("#eef1f2"))
	elif randf() < 0.4:
		g.ellipse(Vector2(r * 0.35, -r * 0.35), r * 0.25, r * 0.18, Color("#5d7339", 0.8))
	return {"g": g, "height": r * 1.4}


# One standing stone: a weathered upright slab.
static func _slab() -> Sketch:
	var g := Sketch.new()
	var w := randf_range(5, 7)
	var h := randf_range(16, 24)
	_shadow(g, w * 1.6, 4, 0.28)
	g.poly(Sketch.round_rect_points(-w, -h, w * 2, h, 2), Color("#69717c"))
	g.rect(w * 0.2, -h + 2, w * 0.8, h - 2, Color("#575f6b")) # shaded side
	g.poly(Sketch.round_rect_points(-w, -h, w * 2, 4, 2), Color("#8f97a1")) # weathered top
	g.line(Vector2(-w * 0.4, -h * 0.6), Vector2(-w * 0.1, -h * 0.35), 1, Color("#3c424d"))
	return g


# An ancient ring of standing stones round a flat altar stone.
static func _standing_stones(r: float) -> Dictionary:
	var g := Sketch.new()
	g.ellipse(Vector2.ZERO, r + 10, (r + 10) * 0.9, Color(0, 0, 0, 0.06))
	var altar := Sketch.round_rect_points(-10, -5, 20, 10, 2)
	g.poly(altar, Color("#7c848f")).poly_stroke(altar, 1, Color("#575f6b"))
	var solids := []
	var uprights := []
	var count := 7
	for k in count:
		var a := float(k) / count * TAU
		var x := cos(a) * r
		var y := sin(a) * r * 0.9
		uprights.append({"g": _slab(), "x": x, "y": y})
		solids.append(Vector3(x, y, 8))
	return {"g": g, "solids": solids, "uprights": uprights}


# --- Ground clutter ---------------------------------------------------------

# A tree stump: a short cylinder with rings on its cut top.
static func _stump(r: float) -> Sketch:
	var g := Sketch.new()
	_shadow(g, r * 1.2, r * 0.45, 0.25)
	var h := r * 0.9
	g.rect(-r, -h, r * 2, h, Color("#5c4632"))
	g.rect(r * 0.2, -h, r * 0.8, h, Color("#46352a"))
	g.ellipse(Vector2.ZERO, r, r * 0.45, Color("#5c4632"))
	g.ellipse(Vector2(0, -h), r, r * 0.45, Color("#b89a70"))
	g.ellipse_stroke(Vector2(0, -h), r * 0.55, r * 0.25, 1, Color("#8a6c4b"))
	return g


static func _fallen_log(r: float) -> Sketch:
	var g := Sketch.new()
	g.capsule(Vector2(-r + 3, 4), Vector2(r + 3, 4), 10, Color(0, 0, 0, 0.2))
	g.capsule(Vector2(-r, 0), Vector2(r, 0), 10, Color("#5e3f22"))
	g.line(Vector2(-r + 4, -2), Vector2(r - 6, -2), 2, Color("#7d5a36"))
	g.circle(Vector2(r, 0), 4.5, Color("#a8875c"))
	g.circle(Vector2(r, 0), 2, Color("#8a6a42"))
	g.round_stroke(PackedVector2Array([Vector2(-r * 0.2, -4), Vector2(-r * 0.35, -11)]), 2, Color("#5e3f22"))
	return g


# A bush: a rounded mound of leaves, lit on top.
static func bush(r: float, biome: Dictionary = Threat.BIOMES[0]) -> Sketch:
	var g := Sketch.new()
	_shadow(g, r * 1.1, r * 0.4, 0.18)
	g.circle(Vector2(-r * 0.45, -r * 0.45), r * 0.6, biome.bush[2])
	g.circle(Vector2(r * 0.45, -r * 0.45), r * 0.62, biome.bush[0])
	g.circle(Vector2(0, -r * 0.75), r * 0.7, biome.bush[1])
	g.circle(Vector2(-r * 0.2, -r * 0.95), r * 0.35, Color(1, 1, 1, 0.12))
	if randf() < 0.4:
		g.circle(Vector2(r * 0.25, -r * 0.7), 2.5, Color("#c0392b"))
	return g


static func _tufts(_r: float, biome: Dictionary) -> Sketch:
	var g := Sketch.new()
	for i in 5:
		var root := Vector2(randf_range(-10, 10), randf_range(-6, 6))
		g.round_stroke(PackedVector2Array([root, root + Vector2(randf_range(-3, 3), -randf_range(5, 9))]), 2, biome.grass)
	return g


static func _flowers(r: float) -> Sketch:
	var g := Sketch.new()
	var colour: Color = _pick([Color("#e6d3a8"), Color("#f6c25a"), Color("#a3331f"), Color("#8f6fb0"), Color("#d9dee2")])
	for k in 12:
		var at := Vector2(randf_range(-r, r), randf_range(-r, r) * 0.7)
		g.line(at, at + Vector2(0, 4), 1, Color("#4f6634"))
		g.circle(at, 1.8, colour)
	return g


static func _mushrooms(r: float) -> Sketch:
	var g := Sketch.new()
	for k in 4:
		var at := Vector2(randf_range(-r, r), randf_range(-r, r) * 0.6)
		var s := randf_range(2.5, 4)
		g.circle(at + Vector2(1, 1), s, Color(0, 0, 0, 0.2))
		g.circle(at, s, Color("#a3331f"))
		g.circle(at - Vector2(s, s) * 0.3, s * 0.3, Color("#e6d3a8"))
	return g


static func _bones(r: float) -> Sketch:
	var g := Sketch.new()
	for k in 4:
		var at := Vector2(randf_range(-r, r), randf_range(-r, r) * 0.6)
		var a := randf() * PI
		var d := Vector2(cos(a), sin(a)) * 6
		g.round_stroke(PackedVector2Array([at - d, at + d]), 2, Color("#e6d3a8"))
	g.circle(Vector2(randf_range(-4, 4), randf_range(-4, 4)), 4, Color("#e6d3a8"))
	return g


# A faint patch of the region's own grass tones, so the land isn't one flat
# colour.
static func _patch(r: float, biome: Dictionary) -> Sketch:
	var g := Sketch.new()
	var colour: Color = _pick([biome.grass, biome.leaf])
	colour.a = 0.1
	for k in 4:
		g.ellipse(Vector2(randf_range(-r, r) * 0.4, randf_range(-r, r) * 0.3), r * randf_range(0.5, 0.8), r * randf_range(0.35, 0.55), colour)
	return g


# --- Abandoned cottage ----------------------------------------------------------

# Tumbledown stone walls with gaps, a chimney stack still standing, fallen roof
# beams and rubble. The floor and rubble lie on the ground; each surviving
# stretch of wall stands up on its own, sorted by its base.
static func _ruin() -> Dictionary:
	var g := Sketch.new()
	var w := randf_range(64, 80)
	var h := randf_range(48, 60)
	var solids := []
	var uprights := []
	g.rect(-w / 2 - 2, -h / 2 - 2, w + 4, h + 4, Color(0, 0, 0, 0.12))
	g.rect(-w / 2, -h / 2, w, h, Color("#3d2f25", 0.75)) # the old floor
	# Collapsed roof timbers and rubble across the floor
	for k in 3:
		var y := randf_range(-h / 3, h / 3)
		g.line(Vector2(-w / 2 + randf_range(4, 15), y), Vector2(w / 2 - randf_range(4, 15), y + randf_range(-12, 12)), 3.5, Color("#2b221c"))
	for k in 14:
		g.ellipse(Vector2(randf_range(-w / 2 - 10, w / 2 + 10), randf_range(-h / 2 - 8, h / 2 + 10)), randf_range(2, 4), randf_range(1.5, 3), Color("#7c766c"))
	if randf() < 0.6:
		g.circle(Vector2(randf_range(-w / 4, w / 4), randf_range(-h / 4, h / 4)), 9, Color("#4f6634", 0.8))

	var corners := [Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)]
	for side in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var angle := (b - a).angle()
		var length := a.distance_to(b)
		# Each wall survives in a few stretches, highest towards the corners
		var steps := 5
		for k in steps:
			if randf() < 0.35:
				continue
			var t := (k + 0.5) / steps
			var edge := 1 - absf(t - 0.5) * 2 # 0 at the corners
			var high := randf_range(6, 14) + (1 - edge) * randf_range(6, 16)
			var at := a.lerp(b, t)
			var wall := Sketch.new()
			Iso.draw_solid(wall, Iso.box(length / steps + 0.5, 7, high, angle, _pick([Color("#8a857a"), Color("#827d72"), Color("#918c80")]), 0.0, Color("#a39e92")), Color("#4a463f"))
			# A stone or two left balanced on top
			if randf() < 0.5:
				wall.rect(randf_range(-5, 2), -high - 3, randf_range(4, 7), 3, Color("#7c776d"))
			uprights.append({"g": wall, "x": at.x, "y": at.y})
			solids.append(Vector3(at.x, at.y, 7))
	# Chimney stack still standing in one corner
	var c: Vector2 = _pick(corners)
	var chimney := Sketch.new()
	Iso.draw_solid(chimney, Iso.box(14, 14, randf_range(38, 52), 0, Color("#69717c"), 0.0, Color("#3c424d")), Color("#3c424d"))
	uprights.append({"g": chimney, "x": c.x, "y": c.y})
	solids.append(Vector3(c.x, c.y, 9))
	return {"g": g, "solids": solids, "uprights": uprights}
