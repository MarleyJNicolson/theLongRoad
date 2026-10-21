class_name Road
extends RefCounted

# A winding dirt road between two towns (from road.js, which made one endless
# road): a polyline laid out in full when its zone is made (see RoadNet), and
# drawn in chunks only while you're near them.
#
# The JS draws it as stacked round-capped strokes with a world-anchored dirt
# pattern; here each stroke is a triangle strip with UVs from world position.

const SEGMENT := 30.0
const ROAD_WIDTH := 96.0
const CHUNK := 40 # points per drawn piece
const PX_PER_METRE := 20.0
const MILESTONE_EVERY := 250 # metres
const DRAW_NEAR := 3400.0 # px: a chunk this close to you is drawn
const DRAW_FAR := 6500.0 # px: and thrown away again this far off
const WANDER := 0.55 # rad: most the road strays from heading straight for its end
const STRAIGHT_ENDS := 520.0 # px: straight out of one gate and into the other

var edge_layer: Node2D
var fill_layer: Node2D
var id := 0
var from_town: Dictionary # (see RoadNet.towns)
var to_town: Dictionary
var kind := "north" # "north" (on towards the zone's gate) or "ew" (across)
var points := PackedVector2Array() # point i lies `i * SEGMENT` along the road
var keep_out: Array = [] # (kept for the encounter builders; the route's already laid)
var placed := PackedByteArray() # which points the scenery has dressed (see Scenery)
var _chunks := {} # chunk number -> its nodes, while drawn


func _init(edge_layer_: Node2D, fill_layer_: Node2D) -> void:
	edge_layer = edge_layer_
	fill_layer = fill_layer_


# Lay the road from `a` to `b` (world px): out of the first gate straight,
# wandering a little on the way, and straight in at the other end.
func lay(a: Vector2, b: Vector2) -> void:
	points = PackedVector2Array([a])
	var heading := (b - a).angle()
	var curve := 0.0
	var target_curve := 0.0
	var until_new_curve := 6
	var travelled := 0.0
	while true:
		var last := points[points.size() - 1]
		var to_end := b - last
		if to_end.length() <= SEGMENT * 1.2:
			break
		var straight := to_end.angle()
		if travelled < STRAIGHT_ENDS or to_end.length() < STRAIGHT_ENDS:
			heading = lerp_angle(heading, straight, 0.35)
			curve = 0.0
		else:
			until_new_curve -= 1
			if until_new_curve <= 0:
				target_curve = randf_range(-0.09, 0.09)
				until_new_curve = 8 + randi() % 14
			curve += (target_curve - curve) * 0.12
			var off := wrapf(heading + curve - straight, -PI, PI)
			if absf(off) > WANDER:
				target_curve = -signf(off) * 0.06
			heading = straight + clampf(off, -WANDER, WANDER)
		points.append(last + Vector2.from_angle(heading) * SEGMENT)
		travelled += SEGMENT
	points.append(b)
	placed.resize(points.size())
	placed.fill(0)


func length() -> float:
	return (points.size() - 1) * SEGMENT


# Unit vector along the road at point i.
func direction(i: int) -> Vector2:
	var n := normal(i)
	return Vector2(n.y, -n.x)


# Normal of the segment from point i (to the right of the way the road runs).
func normal(i: int) -> Vector2:
	var j := clampi(i, 0, points.size() - 2)
	var d := points[j + 1] - points[j]
	if d == Vector2.ZERO:
		return Vector2(0, 1)
	d = d.normalized()
	return Vector2(-d.y, d.x)


# Normal at point i itself, averaged over the segments either side, so strips
# from neighbouring chunks meet exactly.
func _point_normal(i: int) -> Vector2:
	if i <= 0:
		return normal(0)
	return (normal(i - 1) + normal(mini(i, points.size() - 2))).normalized()


# Draw the chunks near `at`, and let go of those far off.
func update_view(at: Vector2) -> void:
	var count := ceili(float(points.size() - 1) / CHUNK)
	for c in count:
		var s := c * CHUNK
		var e := mini(s + CHUNK, points.size() - 1)
		var mid := points[(s + e) / 2]
		var reach := CHUNK * SEGMENT * 0.5
		var d := mid.distance_to(at) - reach
		if d < DRAW_NEAR and not _chunks.has(c):
			_chunks[c] = _draw_chunk(s, e)
		elif d > DRAW_FAR and _chunks.has(c):
			for node: Node2D in _chunks[c]:
				node.queue_free()
			_chunks.erase(c)


func clear_view() -> void:
	for nodes in _chunks.values():
		for node: Node2D in nodes:
			node.queue_free()
	_chunks.clear()


# A strip `width` wide along points start..end, `offset` from the centre.
# `wobble` makes it wander a little, so edges and ruts aren't ruler-straight
# (smooth in `along`, so it joins up across chunks). Returns [points, indices].
func _strip(start: int, end: int, width: float, offset := 0.0, wobble := 0.0, seed := 0.0) -> Array:
	var verts := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(start, end + 1):
		var n := _point_normal(i)
		var a := i * SEGMENT + id * 977.0
		var w := wobble * sin(a * 0.021 + seed) * sin(a * 0.0137 + seed * 2.3)
		var c := points[i] + n * (offset + w)
		verts.append(c - n * width / 2)
		verts.append(c + n * width / 2)
		if i > start:
			var k := (i - start) * 2
			indices.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	return [verts, indices]


func _draw_chunk(start: int, end: int) -> Array:
	var dirt := Textures.dirt_texture()
	var stroke := func(g: Sketch, width: float, colour: Color, alpha: float, textured: bool, offset: float, wobble: float, seed: float) -> void:
		var strip := _strip(start, end, width, offset, wobble, seed)
		colour.a = alpha
		g.triangles(strip[0], strip[1], colour, dirt if textured else null)

	# The road surface changes with the region it runs through.
	var biome: Dictionary = Threat.stage_at(RoadNet.metres_at(points[start].y)).biome
	var colours: Dictionary = biome.road

	# Verge: earth fading into the grass, then a darker, ragged edge
	var edge := Sketch.new()
	edge.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	stroke.call(edge, ROAD_WIDTH + 34, colours.edge, 0.3, false, 0.0, 5.0, 1.0)
	stroke.call(edge, ROAD_WIDTH + 12, colours.edge, 0.9, true, 0.0, 4.0, 2.0)

	# Surface: textured earth, a paler worn crown, wheel ruts with ridges
	var fill := Sketch.new()
	fill.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	stroke.call(fill, ROAD_WIDTH, colours.fill, 1.0, true, 0.0, 0.0, 0.0)
	stroke.call(fill, 26, colours.crown, 0.45, true, 0.0, 6.0, 3.0)
	for side in [-1.0, 1.0]:
		stroke.call(fill, 11, colours.rut, 0.75, true, side * 21, 2.0, 4 + side)
		stroke.call(fill, 2, colours.crown, 0.4, false, side * 28, 2.0, 4 + side)

	# Pebbles on the road, grass creeping in at the edges, the odd puddle
	var grass: Color = biome.grass
	grass.a = 0.9
	for i in range(start + 1, end + 1):
		var p := points[i]
		var n := normal(i)
		var d := direction(i)
		var at := func(a: float, across: float) -> Vector2: return p + d * a + n * across
		for k in 3:
			var pebble: Vector2 = at.call(randf() * SEGMENT, (randf() - 0.5) * ROAD_WIDTH * 0.85)
			var tone: Color = Color("#7c766c") if randf() < 0.5 else colours.edge
			tone.a = 0.8
			fill.circle(pebble, 0.8 + randf() * 1.4, tone)
		for side in [-1.0, 1.0]:
			for k in 2:
				var root: Vector2 = at.call(randf() * SEGMENT, side * (ROAD_WIDTH / 2 - 2 + randf() * 10))
				fill.line(root, root + Vector2((randf() - 0.5) * 4, -3 - randf() * 5), 1.5, grass)
		if biome.name != "The Barrens" and randf() < 0.035:
			# A puddle (ice, up north) lying along one of the ruts
			var icy: bool = biome.name == "The Frostmarch"
			var rut := (-1.0 if randf() < 0.5 else 1.0) * 21
			fill.capsule(at.call(4, rut), at.call(26, rut), 12, Color("#a7aeb6", 0.85) if icy else Color("#33475a", 0.85))
			fill.capsule(at.call(9, rut - 2), at.call(19, rut - 2), 3, Color("#eef1f2", 0.8) if icy else Color("#4d6478", 0.8))

	# Milestones every so often: one on each verge, naming the town that way
	# and how far it is
	var nodes: Array[Node2D] = [edge, fill]
	var every := roundi(MILESTONE_EVERY * PX_PER_METRE / SEGMENT)
	for i in range(maxi(start + 1, 1), end + 1):
		if i % every != 0 or i < every / 2 or points.size() - 1 - i < every / 2:
			continue
		var ahead := roundi((points.size() - 1 - i) * SEGMENT / PX_PER_METRE)
		var behind := roundi(i * SEGMENT / PX_PER_METRE)
		var right := _milestone("%s · %d m" % [to_town.name, ahead])
		right.position = points[i] + normal(i) * (ROAD_WIDTH / 2 + 30)
		nodes.append(right)
		var left := _milestone("%s · %d m" % [from_town.name, behind])
		left.position = points[i] - normal(i) * (ROAD_WIDTH / 2 + 30)
		nodes.append(left)

	edge_layer.add_child(edge)
	for node in nodes.slice(1):
		fill_layer.add_child(node)
	return nodes


# A stone by the roadside with a town's name and the distance to it carved on.
static func _milestone(text: String) -> Node2D:
	var view := Node2D.new()
	var stone := Sketch.new()
	var w := maxf(60.0, text.length() * 9.5 + 16)
	stone.ellipse(Vector2(4, 6), w / 2, 16, Color(0, 0, 0, 0.25))
	var slab := Sketch.round_rect_points(-w / 2, -15, w, 30, 8)
	stone.poly(slab, Color("#b9b5aa")).poly_stroke(slab, 3, Color("#575f6b"))
	view.add_child(stone)
	view.add_child(Fonts.world_label(text, Vector2.ZERO, 20, Color("#1c1714")))
	return view


# A strip `width` wide along any polyline, `offset` to one side, with normals
# taken across each point's neighbours (for side roads). Returns
# [points, indices] for Sketch.triangles.
static func strip_along(line: PackedVector2Array, width: float, offset := 0.0) -> Array:
	var verts := PackedVector2Array()
	var indices := PackedInt32Array()
	for k in line.size():
		var a := line[maxi(0, k - 1)]
		var b := line[mini(line.size() - 1, k + 1)]
		var d := (b - a).normalized() if a != b else Vector2.UP
		var n := Vector2(-d.y, d.x)
		var c := line[k] + n * offset
		verts.append(c - n * width / 2)
		verts.append(c + n * width / 2)
		if k > 0:
			var j := k * 2
			indices.append_array([j - 2, j - 1, j, j - 1, j + 1, j])
	return [verts, indices]
