class_name Missiles
extends RefCounted

# Missiles loosed by the peasant (port of stones.js): stones are lobbed in an
# arc, arrows and bolts fly flat. Each carries the thrower's momentum and the
# weapon's damage.

const ARC_HEIGHT := 28.0
const HIT_RADIUS := 6.0

var layer: Node2D
var list: Array = [] # { view, shot_node, shadow, lobbed, shot, damage, pos, vel, t, duration, landed }


func _init(layer_: Node2D) -> void:
	layer = layer_


static func _draw_shot(shot: String) -> Sketch:
	var g := Sketch.new()
	if shot == "stone":
		g.circle(Vector2.ZERO, 4, Color("#8f8b82"))
		g.circle(Vector2(-1.2, -1.2), 1.6, Color("#b5b1a6"))
	else:
		# Arrow or bolt, drawn pointing along +x at the same size as the one on
		# the bow: shaft, steel head, fletching
		var bolt := shot == "bolt"
		var half := 4.5 if bolt else 6.5
		g.round_stroke(PackedVector2Array([Vector2(-half, 0), Vector2(half, 0)]), 1.6 if bolt else 1.3, Color("#5e3f22") if bolt else Color("#8b6236"))
		g.poly(PackedVector2Array([Vector2(half + 3, 0), Vector2(half - 0.5, -1.6), Vector2(half - 0.5, 1.6)]), Color("#d8dde2"))
		var feather := Color("#5e3f22") if bolt else Color("#ffffff")
		g.poly(PackedVector2Array([Vector2(-half, 0), Vector2(-half - 3, -2.2), Vector2(-half + 2.5, 0)]), feather)
		g.poly(PackedVector2Array([Vector2(-half, 0), Vector2(-half - 3, 2.2), Vector2(-half + 2.5, 0)]), feather)
	return g


static func _draw_shadow(shot: String) -> Sketch:
	var g := Sketch.new()
	if shot == "stone":
		return g.ellipse(Vector2.ZERO, 4, 3, Color(0, 0, 0, 0.25))
	return g.capsule(Vector2(-7, 0), Vector2(8, 0), 1.5, Color(0, 0, 0, 0.2))


# `weapon` supplies range, speed, damage and the kind of shot.
func throw(from: Vector2, to: Vector2, carry: Vector2, weapon: Dictionary) -> void:
	var d := to - from
	var length := d.length()
	if length == 0.0:
		length = 1.0
	var dist := minf(weapon.range, maxf(80.0, length))
	var lobbed: bool = weapon.shot == "stone"

	var view := Node2D.new()
	var shadow := _draw_shadow(weapon.shot)
	var shot_node := _draw_shot(weapon.shot)
	view.add_child(shadow)
	view.add_child(shot_node)
	layer.add_child(view)

	var vel: Vector2 = d / length * weapon.speed + (carry if lobbed else Vector2.ZERO)
	if not lobbed:
		shot_node.rotation = vel.angle()
		shadow.rotation = vel.angle()
	view.position = from
	list.append({"view": view, "shot_node": shot_node, "lobbed": lobbed, "shot": weapon.shot, "damage": weapon.damage,
		"pos": from, "vel": vel, "t": 0.0, "duration": dist / weapon.speed, "landed": 0.0})


# Returns the enemies knocked out this frame.
func update(dt: float, enemies: Array) -> Array:
	var kills := []
	for s in list:
		if s.landed:
			s.landed += dt
			s.view.modulate.a = maxf(0.0, 1 - s.landed / 0.8)
			continue
		s.t += dt
		s.pos += s.vel * dt
		var f := minf(1.0, s.t / s.duration)
		var height: float = 4 * ARC_HEIGHT * f * (1 - f) if s.lobbed else 15.0 # arrows fly flat, at chest height
		s.view.position = s.pos
		s.shot_node.position.y = -height
		if s.lobbed:
			s.shot_node.scale = Vector2.ONE * (1 + height / 50)

		# Anything hiding fills the whole bush or burrow it is in.
		var target: Enemy = null
		for e: Enemy in enemies:
			if e.alive() and e.position.distance_to(s.pos) < (24.0 if e.in_hiding else e.radius) + HIT_RADIUS:
				target = e
				break
		if target:
			var dir: Vector2 = s.vel.normalized()
			target.hit(dir.x, dir.y, s.damage)
			if not target.alive():
				kills.append(target)
			# Arrows and bolts stay stuck in whoever they hit
			if not s.lobbed:
				target.rig.stick_shaft(s.vel.x, s.vel.y, s.shot)
				s.view.visible = false
			s.landed = 0.4
			s.shot_node.position.y = 0
		elif f >= 1:
			s.landed = dt
			s.shot_node.position.y = 0

	list = list.filter(func(s: Dictionary) -> bool:
		if s.landed < 0.8:
			return true
		s.view.queue_free()
		return false)
	return kills
