class_name Road
extends RefCounted

# An endless winding dirt road (port of road.js), generated ahead of the player
# as a polyline and drawn in chunks so old pieces can be thrown away.
#
# The JS draws it as stacked round-capped strokes with a world-anchored dirt
# pattern; here each stroke is a triangle strip with UVs from world position.

const SEGMENT := 30.0
const ROAD_WIDTH := 96.0
const CHUNK := 40
const LOOK_AHEAD := 120
const MAX_DRIFT := 1.1 # max angle (rad) the road may wander from heading "up"
const UP := -PI / 2
const MAX_HEADING := 1.4 # hard limit (rad) from "up": the road never turns back on itself
const AVOID_LOOKAHEAD := 12 # segments ahead the road checks for places to steer round
const PX_PER_METRE := 20.0
const MILESTONE_EVERY := 250 # metres

var edge_layer: Node2D
var fill_layer: Node2D
var points := PackedVector2Array([Vector2(0, 300)]) # point i lies `i * SEGMENT` along the road
var heading := UP
var curve := 0.0
var target_curve := 0.0
var until_new_curve := 15
var keep_out: Array = [] # Vector3(x, y, radius): places the road must steer round (side-road destinations)
var chunks: Array = [] # { end, nodes }
var drawn_up_to := 0


func _init(edge_layer_: Node2D, fill_layer_: Node2D) -> void:
	edge_layer = edge_layer_
	fill_layer = fill_layer_


# Debug: start the road this far along (px), e.g. in another region
# (`-- --metres=N`, read by Game).
static var start_along := 0.0


# How far along the road point i is (px).
static func along(i: int) -> float:
	return start_along + i * SEGMENT


func generate(count: int) -> void:
	for n in count:
		var last := points[points.size() - 1]
		# Forget keep-out zones the road has long since left behind.
		if n == 0:
			keep_out = keep_out.filter(func(z: Vector3) -> bool: return z.y - last.y < 2500)

		until_new_curve -= 1
		if until_new_curve <= 0:
			target_curve = (randf() * 2 - 1) * 0.09
			until_new_curve = 8 + randi() % 14
		var drift := heading - UP
		if absf(drift) > MAX_DRIFT:
			target_curve = -signf(drift) * 0.06

		# Steer hard away from anything built off a side road.
		var away := _avoid(last)
		if away:
			target_curve = away * 0.12
			curve = away * maxf(absf(curve), 0.07)

		# Straight through a town, gate to gate (settling in on the way)
		if Towns.straight_at(along(points.size())):
			target_curve = 0.0
			curve *= 0.6

		curve += (target_curve - curve) * 0.12
		heading = UP + clampf(heading + curve - UP, -MAX_HEADING, MAX_HEADING)
		points.append(last + Vector2(cos(heading), sin(heading)) * SEGMENT)


# Which way to turn (-1 left, 1 right, 0 no need) to keep the road ahead
# clear of the keep-out zones.
func _avoid(from: Vector2) -> int:
	var dir := Vector2(cos(heading), sin(heading))
	for zone: Vector3 in keep_out:
		var centre := Vector2(zone.x, zone.y)
		var reach := zone.z + ROAD_WIDTH / 2 + 60
		if centre.distance_to(from) > reach + AVOID_LOOKAHEAD * SEGMENT:
			continue
		for k in range(1, AVOID_LOOKAHEAD + 1):
			if centre.distance_to(from + dir * SEGMENT * k) < reach:
				# Turn away from the side the zone is on.
				var side := dir.x * (zone.y - from.y) - dir.y * (zone.x - from.x)
				return -1 if side > 0 else 1
	return 0


# Make sure road exists well beyond the given point index.
func ensure_ahead(index: int) -> void:
	while points.size() < index + LOOK_AHEAD:
		generate(CHUNK)
		# Stop one short of the end: the last point's normal isn't settled until
		# the road goes on past it, and chunks must agree where they meet.
		var end := points.size() - 2
		_draw_chunk(maxi(0, drawn_up_to - 1), end)
		drawn_up_to = end


# Unit vector along the road at point i.
func direction(i: int) -> Vector2:
	var n := normal(i)
	return Vector2(n.y, -n.x)


# Normal of the segment from point i (to the right of the way the road runs).
func normal(i: int) -> Vector2:
	var j := mini(i, points.size() - 2)
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
	return (normal(i - 1) + normal(i)).normalized()


# A strip `width` wide along points start..end, `offset` from the centre.
# `wobble` makes it wander a little, so edges and ruts aren't ruler-straight
# (smooth in `along`, so it joins up across chunks). Returns [points, indices].
func _strip(start: int, end: int, width: float, offset := 0.0, wobble := 0.0, seed := 0.0) -> Array:
	var verts := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in range(start, end + 1):
		var n := _point_normal(i)
		var a := along(i)
		var w := wobble * sin(a * 0.021 + seed) * sin(a * 0.0137 + seed * 2.3)
		var c := points[i] + n * (offset + w)
		verts.append(c - n * width / 2)
		verts.append(c + n * width / 2)
		if i > start:
			var k := (i - start) * 2
			indices.append_array([k - 2, k - 1, k, k - 1, k + 1, k])
	return [verts, indices]


func _draw_chunk(start: int, end: int) -> void:
	var dirt := Textures.dirt_texture()
	var stroke := func(g: Sketch, width: float, colour: Color, alpha: float, textured: bool, offset: float, wobble: float, seed: float) -> void:
		var strip := _strip(start, end, width, offset, wobble, seed)
		colour.a = alpha
		g.triangles(strip[0], strip[1], colour, dirt if textured else null)

	# The road surface changes with the region it runs through.
	var biome: Dictionary = Threat.stage_at(along(start) / PX_PER_METRE).biome
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

	# Milestones on the right-hand verge
	var nodes: Array[Node2D] = [edge, fill]
	for i in range(start + 1, end + 1):
		var prev := floori(along(i - 1) / PX_PER_METRE / MILESTONE_EVERY)
		var here := floori(along(i) / PX_PER_METRE / MILESTONE_EVERY)
		if here == prev or here == 0:
			continue
		var marker := _milestone(here * MILESTONE_EVERY)
		marker.position = points[i] + normal(i) * (ROAD_WIDTH / 2 + 26)
		nodes.append(marker)

	edge_layer.add_child(edge)
	for node in nodes.slice(1):
		fill_layer.add_child(node)
	chunks.append({"end": end, "nodes": nodes})


# A stone by the roadside with the distance carved on it; where a new region
# begins, a wooden sign naming it as well.
static func _milestone(metres: int) -> Node2D:
	var view := Node2D.new()
	var stone := Sketch.new()
	stone.ellipse(Vector2(4, 6), 30, 16, Color(0, 0, 0, 0.25))
	var slab := Sketch.round_rect_points(-30, -15, 60, 30, 8)
	stone.poly(slab, Color("#b9b5aa")).poly_stroke(slab, 3, Color("#575f6b"))
	view.add_child(stone)
	view.add_child(_label("%d m" % metres, Vector2.ZERO))

	if metres % Threat.STAGE_LENGTH == 0:
		var sign := Sketch.new()
		sign.line(Vector2(0, -15), Vector2(0, -34), 5, Color("#5e3f22"))
		var board := Sketch.round_rect_points(-100, -68, 200, 34, 3)
		sign.poly(board, Color("#a8875c")).poly_stroke(board, 3, Color("#3d2f25"))
		view.add_child(sign)
		view.add_child(_label(Threat.stage_at(metres).name, Vector2(0, -51)))
	return view


# Big enough to stay legible once drawn at pixel-art resolution.
static func _label(text: String, centre: Vector2) -> Label:
	return Fonts.world_label(text, centre, 22, Color("#1c1714"))


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


# Nearest point on the road, searching around a hint index for speed:
# { dist, index, along }.
func nearest(x: float, y: float, hint: int) -> Dictionary:
	var best := {"dist": INF, "index": hint, "along": 0.0}
	var at := Vector2(x, y)
	for i in range(maxi(0, hint - 25), mini(points.size() - 2, hint + 40) + 1):
		var a := points[i]
		var d := points[i + 1] - a
		var t := clampf((at - a).dot(d) / d.length_squared(), 0.0, 1.0)
		var dist := at.distance_to(a + d * t)
		if dist < best.dist:
			best = {"dist": dist, "index": i, "along": along(i) + t * SEGMENT}
	return best


func cull(index: int) -> void:
	chunks = chunks.filter(func(c: Dictionary) -> bool:
		if c.end >= index - 60:
			return true
		for node: Node2D in c.nodes:
			node.queue_free()
		return false)
