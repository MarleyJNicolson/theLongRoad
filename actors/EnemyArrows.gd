class_name EnemyArrows
extends RefCounted

# Arrows loosed by enemy archers (port of enemyArrows.js). They fly flat and
# fairly slowly, so you can dodge them, and they thud into any tree or building
# in the way.
#
# They're kept as plain data and all drawn by one node (one per arrow was the
# JS way; with hundreds in the air that's the expensive part).

const SHAFT := Color("#5e3f22")
const HEAD := Color("#9aa3ad")
const GOBLIN := Color("#6fa83a")
const BANDIT := Color("#c0392b")
const SIZE := 1.3 # drawn this much bigger than the one on the bow
const STUCK_TIME := 8.0 # seconds one stays stuck in cover or the ground

var layer: Node2D
var list: Array = [] # { pos, dir, speed, left, damage, faction, stuck, flown }
var _view: Painter


func _init(layer_: Node2D) -> void:
	layer = layer_
	_view = Painter.new(_draw)
	layer.add_child(_view)


# volley: { x, y, aim_x, aim_y, speed, range, damage, faction }
func fire(v: Dictionary) -> void:
	var d := Vector2(v.aim_x - v.x, v.aim_y - v.y)
	var dir := d.normalized() if d != Vector2.ZERO else Vector2.RIGHT
	list.append({"pos": Vector2(v.x, v.y), "dir": dir, "speed": v.speed, "left": v.range, "damage": v.damage,
		"faction": v.faction, "stuck": 0.0, "flown": 0.0})


# `victims` are circles that get hurt (Vector3(x, y, r)); `obstacles` stop
# arrows dead. Returns the hits: [{ damage, faction }].
func update(dt: float, victims: Array, obstacles: Obstacles) -> Array:
	var hits := []
	var keep := false
	for a in list:
		if a.stuck:
			a.stuck += dt
			if a.stuck >= STUCK_TIME:
				keep = true # (something to clear away below)
			continue
		var step: float = a.speed * dt
		a.pos += a.dir * step
		a.left -= step
		a.flown += step
		var hit := false
		for v: Vector3 in victims:
			if Vector2(v.x, v.y).distance_to(a.pos) < v.z + 3:
				hit = true
				break
		if hit:
			hits.append({"damage": a.damage, "faction": a.faction, "from": a.pos - a.dir * 40})
			a.stuck = STUCK_TIME # gone at once
			keep = true
		elif a.left <= 0 or (a.flown > 30 and obstacles.hits(a.pos)):
			# Drops spent into the ground, or sticks in cover (once clear of the
			# archer's own perch, such as a watchtower); there it stays a while.
			a.stuck = dt
			a.grounded = a.left <= 0
	if keep:
		list = list.filter(func(a: Dictionary) -> bool: return a.stuck < STUCK_TIME)
	_view.queue_redraw()
	return hits


# Each drawn the size of the one on the archer's bow, flying at chest height
# over its shadow.
func _draw(ci: CanvasItem) -> void:
	for a in list:
		var alpha: float = 1.0 if not a.stuck else clampf((STUCK_TIME - a.stuck) / 0.8, 0, 1)
		var p: Vector2 = a.pos
		var d: Vector2 = a.dir
		var none := PackedVector2Array()
		var fletch: Color = GOBLIN if a.faction == "goblin" else BANDIT
		if a.get("grounded", false):
			# Stuck in the ground at a slant, the fletching up
			var tail := p - d * 6.5 * SIZE - Vector2(0, 8 * SIZE)
			ci.draw_line(p, tail, Color(SHAFT, alpha), 1.3 * SIZE)
			var up := (tail - p).normalized()
			ci.draw_primitive(PackedVector2Array([tail, tail + up * 3.5 - up.orthogonal() * 2.2, tail + up * 3.5 + up.orthogonal() * 2.2]), PackedColorArray([Color(fletch, alpha)]), none)
			continue
		var n := d.orthogonal() * SIZE
		if not a.stuck:
			ci.draw_line(p - d * 7, p + d * 8, Color(0, 0, 0, 0.2 * alpha), 1.5)
		var at := p - Vector2(0, 14)
		var half := 6.5 * SIZE
		ci.draw_line(at - d * half, at + d * half, Color(SHAFT, alpha), 1.3 * SIZE)
		ci.draw_primitive(PackedVector2Array([at + d * (half + 3 * SIZE), at + d * (half - 0.5) - n * 1.6, at + d * (half - 0.5) + n * 1.6]), PackedColorArray([Color(HEAD, alpha)]), none)
		ci.draw_primitive(PackedVector2Array([at - d * half, at - d * (half + 3 * SIZE) - n * 2.2, at - d * (half - 2.5 * SIZE), at - d * (half + 3 * SIZE) + n * 2.2]), PackedColorArray([Color(fletch, alpha)]), none)
