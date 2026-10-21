class_name RoadNet
extends RefCounted

# The roads and towns of each zone (not in the JS original, which had one
# endless road). A zone is a stretch of country ZONE_METRES deep: you come in
# at its start town in the south, and its final town at the north edge is the
# gate to the next. Between, rows of towns: one on the way straight north (the
# "spine"), and others off to the east and west, reached by roads running
# across. Those cost you time going north, but that's where most of the towns
# are, and so the supply missions, the richer pickings and the rarer traders.
#
# How far north you've come is the measure of everything: threat, region and
# your score (see metres_at). North is up the screen (negative y); you start at
# y = 0.

const ZONE_METRES := 2500.0 # (one region each: see Threat.STAGE_LENGTH)
const PX_PER_METRE := 20.0
const ZONE_H := ZONE_METRES * PX_PER_METRE
const HALF_W := 26000.0 # px either side of the spine that side towns lie
const ROWS := [0.27, 0.53, 0.78] # the rows of towns between, as a share of the zone's depth
const SIDE_CHANCE := 0.7 # of a row having a town off to each side
const FLANK_CHANCE := 0.6 # of side towns on the same side being joined north
const PLAZA := 70.0 # px: roads start this far out from a town's middle

var edge_layer: Node2D
var fill_layer: Node2D
var roads: Array = [] # Road
# { id, pos, name, zone, kind: start|town|final, side: w|c|e, roads: [Road], gates: [angle], number }
var towns: Array = []
var zone := -1 # the newest zone made
var _grid := Grid.new(256) # every road point: Vector2i(road id, index)
var _names := 0 # towns named so far


static func metres_at(y: float) -> float:
	return -y / PX_PER_METRE


func _init(edge_layer_: Node2D, fill_layer_: Node2D) -> void:
	edge_layer = edge_layer_
	fill_layer = fill_layer_


# Lay out zone `k`, starting from `start` (the last zone's final town), or from
# a new start town in the south at zone k's southern edge if there isn't one.
# Returns the new roads.
func add_zone(k: int, start: Variant = null) -> Array:
	zone = k
	if start == null:
		start = _town(Vector2(0, -k * ZONE_H), k, "start", "c")
	var y0: float = start.pos.y
	var x0: float = start.pos.x
	var made := []
	var spine := [start]
	var rows := []
	for r in ROWS.size():
		var y: float = y0 - ROWS[r] * ZONE_H + randf_range(-0.03, 0.03) * ZONE_H
		var row := {"c": _town(Vector2(x0 + randf_range(-0.12, 0.12) * HALF_W, y), k, "town", "c")}
		var sides := []
		if randf() < SIDE_CHANCE:
			sides.append("w")
		if randf() < SIDE_CHANCE:
			sides.append("e")
		if sides.is_empty():
			sides.append("w" if randf() < 0.5 else "e")
		for s in sides:
			var sign := -1.0 if s == "w" else 1.0
			row[s] = _town(Vector2(row.c.pos.x + sign * randf_range(0.6, 0.9) * HALF_W, y + randf_range(-0.06, 0.06) * ZONE_H), k, "town", s)
		rows.append(row)
		spine.append(row.c)
	var final := _town(Vector2(x0 + randf_range(-0.1, 0.1) * HALF_W, y0 - ZONE_H), k, "final", "c")
	spine.append(final)

	# The spine, straight up the zone
	for r in spine.size() - 1:
		made.append(_connect(spine[r], spine[r + 1], "north"))
	# Across to each side town, and now and then north between side towns
	for r in rows.size():
		for s in ["w", "e"]:
			if rows[r].has(s):
				made.append(_connect(rows[r].c, rows[r][s], "ew"))
				if r + 1 < rows.size() and rows[r + 1].has(s) and randf() < FLANK_CHANCE:
					made.append(_connect(rows[r][s], rows[r + 1][s], "north"))
	return made


func _town(pos: Vector2, k: int, kind: String, side: String) -> Dictionary:
	var number := _names
	_names += 1
	var name: String = Towns.NAMES[number % Towns.NAMES.size()]
	if number >= Towns.NAMES.size():
		name += " %d" % (number / Towns.NAMES.size() + 1)
	var town := {"id": towns.size(), "pos": pos, "name": name, "zone": k, "kind": kind, "side": side,
		"roads": [], "gates": [], "number": number}
	towns.append(town)
	return town


# A road between two towns, out of a gate in each.
func _connect(a: Dictionary, b: Dictionary, kind: String) -> Road:
	var road := Road.new(edge_layer, fill_layer)
	road.id = roads.size()
	road.kind = kind
	road.from_town = a
	road.to_town = b
	var dir: Vector2 = (b.pos - a.pos).normalized()
	road.lay(a.pos + dir * PLAZA, b.pos - dir * PLAZA)
	a.roads.append(road)
	b.roads.append(road)
	a.gates.append(dir.angle())
	b.gates.append((-dir).angle())
	roads.append(road)
	for i in road.points.size():
		_grid.add(road.points[i], 0, Vector2i(road.id, i))
	return road


# The nearest point of any road within `reach` of `at`:
# { road, index, dist } (road null if there's none that near).
func nearest(at: Vector2, reach := 260.0) -> Dictionary:
	var best := {"road": null, "index": 0, "dist": INF}
	for key: Vector2i in _grid.near(at, reach):
		var road: Road = roads[key.x]
		var i: int = mini(key.y, road.points.size() - 2)
		var a := road.points[i]
		var d := road.points[i + 1] - a
		var t := clampf((at - a).dot(d) / maxf(d.length_squared(), 0.001), 0.0, 1.0)
		var dist := at.distance_to(a + d * t)
		if dist < best.dist:
			best = {"road": road, "index": i, "dist": dist}
	return best


# Road points within `reach` of `at`: [Vector2i(road id, index)] (unsorted;
# some may be a little further off).
func points_near(at: Vector2, reach: float) -> Array:
	return _grid.near(at, reach)


# Is `at` within `gap` of any road?
func near_road(at: Vector2, gap: float) -> bool:
	var gap2 := gap * gap
	for key: Vector2i in _grid.near(at, gap):
		if roads[key.x].points[key.y].distance_squared_to(at) < gap2:
			return true
	return false


# Draw the road near `at`; let go of what's far off.
func update_view(at: Vector2) -> void:
	for road: Road in roads:
		road.update_view(at)


# Every town's keep-clear circle: Vector3(x, y, radius).
func town_circles(radius: float) -> Array:
	return towns.map(func(t: Dictionary) -> Vector3: return Vector3(t.pos.x, t.pos.y, radius))


func clear() -> void:
	for road: Road in roads:
		road.clear_view()
