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
			if a.stuck >= 1.2:
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
			hits.append({"damage": a.damage, "faction": a.faction})
			a.stuck = 1.2 # gone at once
			keep = true
		elif a.left <= 0 or (a.flown > 30 and obstacles.hits(a.pos)):
			# Drops spent, or sticks in cover (once clear of the archer's own
			# perch, such as a watchtower), then fades.
			a.stuck = dt
	if keep:
		list = list.filter(func(a: Dictionary) -> bool: return a.stuck < 1.2)
	_view.queue_redraw()
	return hits


# Each drawn the size of the one on the archer's bow, flying at chest height
# over its shadow.
func _draw(ci: CanvasItem) -> void:
	for a in list:
		var alpha: float = 1.0 if not a.stuck else maxf(0.0, 1 - a.stuck / 1.2)
		var p: Vector2 = a.pos
		var d: Vector2 = a.dir
		var n := d.orthogonal()
		ci.draw_line(p - d * 7, p + d * 8, Color(0, 0, 0, 0.2 * alpha), 1.5)
		var at := p - Vector2(0, 14)
		ci.draw_line(at - d * 6.5, at + d * 6.5, Color(SHAFT, alpha), 1.3)
		var none := PackedVector2Array()
		ci.draw_primitive(PackedVector2Array([at + d * 9.5, at + d * 6 - n * 1.6, at + d * 6 + n * 1.6]), PackedColorArray([Color(HEAD, alpha)]), none)
		var fletch: Color = GOBLIN if a.faction == "goblin" else BANDIT
		ci.draw_primitive(PackedVector2Array([at - d * 6.5, at - d * 9.5 - n * 2.2, at - d * 4, at - d * 9.5 + n * 2.2]), PackedColorArray([Color(fletch, alpha)]), none)
