class_name Build
extends RefCounted

# What an encounter builder gets to work with (the `ctx` in the JS), and the
# shared pieces they're made from (port of encounters/helpers.js).

# How often a camp or homestead is set back off in the wilds rather than
# beside the road, and how much likelier a chest is out there.
const DEEP_CHANCE := 0.5 # (0.45 in the JS)
const DEEP_CHEST_CHANCE := 0.9

var layer: Node2D # this encounter's ground view (in the flat props layer)
var upright: Node2D # the y-sorted layer shared with the people
var road: Road
var i: int # the main-road point it's placed at
var zones: Array # Vector3(x, y, radius) to keep clear of
var towns: Array = [] # towns' walls, Vector3(x, y, radius): side roads keep well clear
var difficulty: float # +1 per 500 m
var extra: int # room for bigger groups (Threat extra_members)
var enemies: Enemies
var uprights: Array = [] # everything stood up, so it can be cleared away: { node, fade }
var g: Sketch # the ground drawing (clearings, paths, bones), in `layer`


func _init(layer_: Node2D, upright_: Node2D, road_: Road, i_: int, zones_: Array, difficulty_: float, extra_: int, enemies_: Enemies) -> void:
	layer = layer_
	upright = upright_
	road = road_
	i = i_
	zones = zones_
	difficulty = difficulty_
	extra = extra_
	enemies = enemies_
	g = Sketch.new()
	layer.add_child(g)


# Stand something up at (x, y): sorted by depth with the people, and cleared
# away with the encounter. `depth` sorts it somewhere other than its foot (a
# flame on a roof sorts with the house front; a hood peeking from a bush just
# in front of the bush): it's then held in a node at that depth. `fade`:
# { r, height } if it's big enough to hide behind (it fades when you do).
func stand(obj: Node2D, x: float, y: float, depth: Variant = null, fade := {}) -> Node2D:
	var holder := obj
	if depth != null and depth != y:
		holder = Node2D.new()
		holder.position = Vector2(x, depth)
		obj.position = Vector2(0, y - depth)
		holder.add_child(obj)
	else:
		obj.position = Vector2(x, y)
	upright.add_child(holder)
	var entry := {"node": holder}
	if not fade.is_empty():
		entry.fade = {"x": x, "y": y, "r": fade.r, "height": fade.height}
	uprights.append(entry)
	return obj


# Undo everything stood up so far (a builder that didn't fit).
func clear_uprights() -> void:
	for u in uprights:
		u.node.queue_free()
	uprights.clear()


static func rand_int(lo: int, hi: int) -> int:
	return randi_range(lo, hi)


static func side_sign() -> float:
	return -1.0 if randf() < 0.5 else 1.0


# --- Placing things relative to the road ----------------------------------

# Local frame at a road point: at(along, lateral) converts road-relative
# offsets (along the direction of travel, sideways from the centre line) into
# world coordinates.
class Frame:
	var p: Vector2
	var n: Vector2
	var d: Vector2

	func _init(road: Road, i: int) -> void:
		p = road.points[i]
		var q := road.points[i + 1]
		n = road.normal(i)
		d = (q - p).normalized() if q != p else Vector2.UP

	func at(along: float, lateral: float) -> Vector2:
		return p + d * along + n * lateral


func frame() -> Frame:
	return Frame.new(road, i)


# Which side of the road (-1 or 1) has room for something `offset` away from
# the centre line without spilling onto a nearby bend. 0 if neither.
func side_that_fits(offset: float) -> float:
	var f := frame()
	var fits := func(s: float) -> bool:
		var at := f.p + f.n * s * offset
		for j in range(maxi(0, i - 40), mini(road.points.size(), i + 40)):
			if road.points[j].distance_to(at) <= offset - 10:
				return false
		return true
	var first := side_sign()
	if fits.call(first):
		return first
	if fits.call(-first):
		return -first
	return 0.0


# Where to put something `radius` across that would sit `near` the road edge.
# Often it's further off, out of sight in the wilds (`deep`), found by a
# footpath, a column of smoke or a marker by the road. Null if nothing fits:
# { side, offset, deep, x, y }.
func set_back(near: float, radius: float, deep_only := false, far := 700.0) -> Variant: # (far was 380 in the JS)
	var go_deep := deep_only or randf() < DEEP_CHANCE
	var tries := []
	if go_deep:
		tries = [randf_range(near + 160, near + far), randf_range(near + 100, near + 220)]
	if not deep_only:
		tries.append(near)
	var f := frame()
	for offset: float in tries:
		var side := side_that_fits(offset)
		if not side:
			continue
		var at := f.at(0, side * offset)
		var clear := true
		for z: Vector3 in zones:
			if Vector2(z.x, z.y).distance_to(at) <= z.z + radius:
				clear = false
				break
		if not clear:
			continue
		var deep := offset > near + 60
		# The road still to come must steer round it
		if deep:
			road.keep_out.append(Vector3(at.x, at.y, radius + 30))
		return {"side": side, "offset": offset, "deep": deep, "x": at.x, "y": at.y}
	return null


# --- Ground pieces --------------------------------------------------------------

# A drawing whose overlapping shapes merge into one, then fade to `alpha`
# together (a Pixi path filled once with alpha, rather than shape by shape).
func merged(alpha: float) -> Sketch:
	var group := CanvasGroup.new()
	group.self_modulate.a = alpha
	layer.add_child(group)
	layer.move_child(group, 0) # the ground under everything else drawn here
	var sketch := Sketch.new()
	group.add_child(sketch)
	return sketch


# A trampled clearing, with a path out to the road edge (unless it's off in
# the wilds: see footpath).
func draw_clearing(centre: Vector2, edge: Variant, colour := Color("#8f8a52")) -> void:
	var patch := merged(0.55)
	for k in 7:
		var a := float(k) / 7 * TAU
		patch.circle(centre + Vector2(cos(a) * 55, sin(a) * 45), randf_range(60, 80), colour)
	if edge != null:
		g.capsule(centre, edge, 26, Color(colour, 0.5))


# A winding footpath trodden from the road edge out to `to`. Returns zones
# along it to keep trees off.
func footpath(from: Vector2, to: Vector2, colour := Color("#8a7f55")) -> Array:
	var length := from.distance_to(to)
	var steps := maxi(2, roundi(length / 28))
	var nrm := Vector2(-(to.y - from.y), to.x - from.x) / length
	var sway := randf_range(18, 40) * side_sign()
	var wobble := randf_range(1.5, 3)
	var pts := PackedVector2Array()
	for k in steps + 1:
		var t := float(k) / steps
		var off := sin(t * PI) * sway + sin(t * PI * wobble) * 8 * sin(t * PI)
		pts.append(from.lerp(to, t) + nrm * off)
	g.round_stroke(pts, 24, Color(colour, 0.35))
	g.round_stroke(pts, 13, Color(colour, 0.55))
	var out := []
	for p in pts:
		out.append(Vector3(p.x, p.y, 18))
	return out


# Smoke curling up from (x, y) at height `z`, high enough to be seen over the
# trees from the road. Call the returned function(time, dt) every frame.
func smoke_plume(x: float, y: float, z := 10.0, every := 0.2, colour := Color("#b4aea4")) -> Callable:
	var smoke := stand(Node2D.new(), x, y, y + 2)
	var puffs := []
	var state := {"next": 0.0}
	return func(time: float, dt: float) -> void:
		if time > state.next and is_instance_valid(smoke):
			var puff := Sketch.new().circle(Vector2.ZERO, 8, Color(colour, 0.55))
			puff.position = Vector2(randf_range(-4, 4), -z)
			smoke.add_child(puff)
			puffs.append({"g": puff, "seed": randf_range(0, 6), "life": 0.0})
			state.next = time + every
		for k in range(puffs.size() - 1, -1, -1):
			var p: Dictionary = puffs[k]
			p.life += dt
			if not is_instance_valid(p.g):
				puffs.remove_at(k)
				continue
			p.g.position.x += dt * (5 + p.life * 4 + sin(p.life * 1.7 + p.seed) * 9)
			p.g.position.y -= dt * 42
			p.g.scale = Vector2.ONE * (1 + p.life * 0.8)
			p.g.modulate.a = maxf(0.0, 1 - p.life / 7)
			if p.life > 7:
				p.g.queue_free()
				puffs.remove_at(k)


# Stone-ringed campfire: stones and glow on the ground, the flames stood up.
# Call the returned function(time, dt) every frame to make it flicker.
func campfire(x: float, y: float) -> Callable:
	for k in 8:
		var a := float(k) / 8 * TAU
		g.ellipse(Vector2(x + cos(a) * 15, y + sin(a) * 12), 4.5, 3.5, Color("#7d7a72"))
	g.ellipse(Vector2(x, y), 11, 8, Color("#2a1f14"))
	for a in [0.4, 2.2]:
		var d := Vector2(cos(a) * 10, sin(a) * 7)
		g.round_stroke(PackedVector2Array([Vector2(x, y) - d, Vector2(x, y) + d]), 3.5, Color("#4a3220"))
	var fire := stand(Structures.flames(), x, y + 1)
	var light := Glow.light(170, Color("#ff9a3c"), 1.2)
	light.position = Vector2(0, -8)
	fire.add_child(light)
	var glow := Sketch.new().circle(Vector2.ZERO, 70, Color("#ff9a3c", 0.12))
	glow.position = Vector2(x, y)
	layer.add_child(glow)
	var smoke := smoke_plume(x, y, 16)
	return func(time: float, dt: float) -> void:
		smoke.call(time, dt)
		fire.scale = Vector2(1 + sin(time * 7.3) * 0.08, 1 + sin(time * 17) * 0.14 + sin(time * 5.1) * 0.08)
		fire.skew = sin(time * 4.3) * 0.12
		glow.modulate.a = 0.85 + sin(time * 11) * 0.15


# Bones strewn about (x, y).
func scatter_bones(at: Vector2, spread: Vector2, count: int) -> void:
	for k in count:
		var b := at + Vector2(randf_range(-spread.x, spread.x), randf_range(-spread.y, spread.y))
		var a := randf() * PI
		var d := Vector2(cos(a), sin(a)) * 5
		g.round_stroke(PackedVector2Array([b - d, b + d]), 2, Color("#e8e0c8"))
