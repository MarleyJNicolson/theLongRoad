class_name SideRoads
extends RefCounted

# Turnings off the main road to somewhere bigger (port of
# encounters/sideroads.js): a winding side road, a fingerpost at the junction,
# and a destination (see Destinations) at the far end.

const SIDE_WIDTH := 72.0
const ROUTE_ATTEMPTS := 20
const PX_PER_METRE := 20.0

const KINDS := [
	["friendly_village", 34],
	["raided_village", 22],
	["bandit_stronghold", 22],
	["goblin_warcamp", 22],
]


static func _pick_kind() -> String:
	var total := 0
	for k in KINDS:
		total += k[1]
	var roll := randf() * total
	for k in KINDS:
		roll -= k[1]
		if roll < 0:
			return k[0]
	return KINDS[0][0]


# Wind a side road out from main-road point `b.i`. It bends back toward road
# that already exists: the main road only ever heads up the map, so nothing
# built down there can be run over later. Null if there's no room.
static func _plan_route(b: Build) -> Variant:
	var road := b.road
	var f := b.frame()
	var main := road.points.slice(maxi(0, b.i - 160))
	var clear := func(at: Vector2, gap: float) -> bool:
		var gap2 := gap * gap
		for m in main:
			if m.distance_squared_to(at) <= gap2:
				return false
		return true
	var first_side := 1.0 if randf() < 0.5 else -1.0
	# Try a handful of routes on each side: steeper or shallower, longer or
	# shorter, until one has room.
	for attempt in ROUTE_ATTEMPTS:
		var side := first_side if attempt % 2 == 0 else -first_side
		# Out to the side, often angled back down the map
		var heading := atan2(f.n.y * side + randf_range(-0.2, 1.4), f.n.x * side)
		var curve := 0.0
		var points := PackedVector2Array([f.p])
		for k in randi_range(20, 32):
			curve = clampf(curve + randf_range(-0.04, 0.04), -0.07, 0.07)
			heading += curve
			points.append(points[points.size() - 1] + Vector2(cos(heading), sin(heading)) * Road.SEGMENT)
		var end := points[points.size() - 1]
		# The destination sits just past the end of the road
		var c := end + Vector2(cos(heading), sin(heading)) * (Destinations.DEST_RADIUS - 40)
		# Keep destinations level with or behind the junction, so the main road
		# (which only heads up the map) has plenty of room to steer round them.
		if c.y < f.p.y - 150:
			continue
		var apart := true
		for z: Vector3 in b.zones:
			if Vector2(z.x, z.y).distance_to(c) <= z.z + Destinations.DEST_RADIUS:
				apart = false
				break
		if not apart or not clear.call(c, Destinations.DEST_RADIUS + Road.ROAD_WIDTH / 2 + 40):
			continue
		var road_clear := true
		for k in range(4, points.size()):
			if not clear.call(points[k], Road.ROAD_WIDTH / 2 + SIDE_WIDTH / 2 + 30):
				road_clear = false
				break
		if road_clear:
			return {"side": side, "points": points, "c": c, "entrance": (end - c).angle()}
	return null


# Same textured earth as the main road, just narrower and less worn, in the
# same layers so the two blend at the junction.
static func _draw_route(road: Road, points: PackedVector2Array, colours: Dictionary) -> Array:
	var dirt := Textures.dirt_texture()
	var stroke := func(g: Sketch, width: float, colour: Color, alpha: float, textured: bool, offset: float) -> void:
		var strip := Road.strip_along(points, width, offset)
		g.triangles(strip[0], strip[1], Color(colour, alpha), dirt if textured else null)
	var edge := Sketch.new()
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	stroke.call(edge, SIDE_WIDTH + 28, colours.edge, 0.3, false, 0.0)
	stroke.call(edge, SIDE_WIDTH + 10, colours.edge, 0.9, true, 0.0)
	var fill := Sketch.new()
	fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	stroke.call(fill, SIDE_WIDTH, colours.fill, 1.0, true, 0.0)
	stroke.call(fill, 18, colours.crown, 0.35, true, 0.0)
	stroke.call(fill, 8, colours.rut, 0.65, true, -14.0)
	stroke.call(fill, 8, colours.rut, 0.65, true, 14.0)
	road.edge_layer.add_child(edge)
	road.fill_layer.add_child(fill)
	return [edge, fill]


# A fingerpost by the junction. The board stays level so it's easy to read,
# and points left or right toward the turning.
static func _signpost(b: Build, at: Vector2, points_left: bool, title: String, metres: int, hostile: bool) -> void:
	var post := Node2D.new()
	var g := Sketch.new()
	g.circle(Vector2(2, 2), 4, Color(0, 0, 0, 0.25))
	g.circle(Vector2.ZERO, 3.5, Color("#5e3f22"))
	# Board drawn pointing right; mirrored to point left.
	var board := Sketch.new()
	var shape := PackedVector2Array([Vector2(-125, -36), Vector2(125, -36), Vector2(145, -20), Vector2(125, -4), Vector2(-125, -4)])
	board.poly(shape, Color("#7a4a3a") if hostile else Color("#a8875c"))
	board.poly_stroke(shape, 3, Color("#3d2f25"))
	if hostile:
		board.circle(Vector2(125, -20), 5, Color("#e8e0c8"))
	if points_left:
		board.scale.x = -1
	post.add_child(g)
	post.add_child(board)
	post.add_child(Fonts.world_label("%s · %d m" % [title, metres], Vector2(0, -20), 18, Color("#f3e3c0") if hostile else Color("#2a1f14")))
	b.stand(post, at.x, at.y)


# A side road off main-road point `b.i` leading to a big destination, or null
# if it won't fit here.
static func side_road(b: Build) -> Variant:
	var route: Variant = _plan_route(b)
	if route == null:
		return null
	var road := b.road
	var metres := Road.along(b.i) / PX_PER_METRE
	var biome: Dictionary = Threat.stage_at(metres).biome
	var road_views := _draw_route(road, route.points, biome.road)
	var c: Vector2 = route.c
	# The main road, still to be generated beyond here, must steer round it all.
	road.keep_out.append(Vector3(c.x, c.y, Destinations.DEST_RADIUS))
	for k in route.points.size():
		if k > 3 and k % 2 == 0:
			road.keep_out.append(Vector3(route.points[k].x, route.points[k].y, SIDE_WIDTH / 2 + 10))

	var kind := _pick_kind()
	var faction := "goblin" if biome.name == "The Darkwood" else ("bandit" if biome.name == "The Barrens" else ("goblin" if randf() < 0.5 else "bandit"))
	var dest: Dictionary = Destinations.make(kind, b, c, route.entrance, metres, faction)

	# Signpost on the verge just past the turning (the side road bends back the
	# other way, so it stays clear)
	var f := b.frame()
	var sign_at: Vector2 = f.p + f.n * route.side * (Road.ROAD_WIDTH / 2 + 70) + f.d * 80
	var length := roundi((route.points.size() * Road.SEGMENT + Destinations.DEST_RADIUS) / PX_PER_METRE)
	_signpost(b, sign_at, route.points[6].x < f.p.x, dest.title, length, dest.hostile)

	var zones := [Vector3(c.x, c.y, Destinations.DEST_RADIUS + 20)]
	for q in route.points:
		zones.append(Vector3(q.x, q.y, SIDE_WIDTH / 2 + 14))
	dest.road_views = road_views
	dest.side_road = {"points": route.points, "width": SIDE_WIDTH}
	# Keep trees off the road and out of the destination
	dest.zones = zones
	dest.trigger = Vector3(c.x, c.y, dest.get("trigger_radius", 0.0))
	return dest


# Is `at` on this side road's surface?
static func on_side_road(enc: Dictionary, at: Vector2) -> bool:
	var points: PackedVector2Array = enc.side_road.points
	var reach: float = enc.side_road.width / 2 + 4
	for k in points.size() - 1:
		if at.distance_to(Geometry2D.get_closest_point_to_segment(at, points[k], points[k + 1])) < reach:
			return true
	return false
