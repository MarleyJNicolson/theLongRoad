class_name EnemyArrows
extends RefCounted

# Arrows loosed by enemy archers (port of enemyArrows.js). They fly flat and
# fairly slowly, so you can dodge them, and they thud into any tree or building
# in the way.

var layer: Node2D
var list: Array = [] # { g, pos, vel, left, damage, faction, stuck, flown }


func _init(layer_: Node2D) -> void:
	layer = layer_


# volley: { x, y, aim_x, aim_y, speed, range, damage, faction }
func fire(v: Dictionary) -> void:
	var d := Vector2(v.aim_x - v.x, v.aim_y - v.y)
	var dir := d.normalized() if d != Vector2.ZERO else Vector2.RIGHT
	# Drawn the size of the one on the archer's bow, flying at chest height
	# over its shadow
	var g := Node2D.new()
	var shadow := Sketch.new().capsule(Vector2(-7, 0), Vector2(8, 0), 1.5, Color(0, 0, 0, 0.2))
	var shaft := Sketch.new()
	shaft.round_stroke(PackedVector2Array([Vector2(-6.5, 0), Vector2(6.5, 0)]), 1.3, Color("#5e3f22"))
	shaft.poly(PackedVector2Array([Vector2(9.5, 0), Vector2(6, -1.6), Vector2(6, 1.6)]), Color("#9aa3ad"))
	shaft.poly(PackedVector2Array([Vector2(-6.5, 0), Vector2(-9.5, -2.2), Vector2(-4, 0), Vector2(-9.5, 2.2)]), Color("#6fa83a") if v.faction == "goblin" else Color("#c0392b"))
	shadow.rotation = dir.angle()
	shaft.rotation = dir.angle()
	shaft.position.y = -14
	g.add_child(shadow)
	g.add_child(shaft)
	g.position = Vector2(v.x, v.y)
	layer.add_child(g)
	list.append({"g": g, "pos": g.position, "vel": dir * v.speed, "left": v.range, "damage": v.damage, "faction": v.faction, "stuck": 0.0, "flown": 0.0})


# `victims` are circles that get hurt (Vector3(x, y, r)); `obstacles` stop
# arrows dead (Vector3(x, y, radius)). Returns the hits: [{ damage, faction }].
func update(dt: float, victims: Array, obstacles: Array) -> Array:
	var hits := []
	for a in list:
		if a.stuck:
			a.stuck += dt
			a.g.modulate.a = maxf(0.0, 1 - a.stuck / 1.2)
			continue
		a.pos += a.vel * dt
		var step: float = a.vel.length() * dt
		a.left -= step
		a.flown += step
		a.g.position = a.pos
		if _touches(a.pos, victims, 3.0):
			hits.append({"damage": a.damage, "faction": a.faction})
			a.stuck = 1.2 # gone at once
		elif a.left <= 0 or (a.flown > 30 and _touches(a.pos, obstacles, 0.0)):
			# Drops spent, or sticks in cover (once clear of the archer's own
			# perch, such as a watchtower), then fades.
			a.stuck = dt
	list = list.filter(func(a: Dictionary) -> bool:
		if a.stuck < 1.2:
			return true
		a.g.queue_free()
		return false)
	return hits


static func _touches(at: Vector2, circles: Array, extra: float) -> bool:
	for c: Vector3 in circles:
		if Vector2(c.x, c.y).distance_to(at) < c.z + extra:
			return true
	return false
