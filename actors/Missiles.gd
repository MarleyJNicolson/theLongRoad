class_name Missiles
extends RefCounted

# Missiles loosed by the peasant (port of stones.js): stones are lobbed in an
# arc, arrows and bolts fly flat. Each carries the thrower's momentum and the
# weapon's damage.
#
# Kept as plain data and all drawn by one node; hits are looked for only among
# the raiders near each missile (see Enemies.near).

const ARC_HEIGHT := 28.0
const HIT_RADIUS := 6.0
const STONE := Color("#8f8b82")
const STONE_LIT := Color("#b5b1a6")
const BOLT := Color("#5e3f22")
const SHAFT := Color("#8b6236")
const STEEL := Color("#d8dde2")
const FEATHER := Color("#ffffff")

var layer: Node2D
var list: Array = [] # { lobbed, shot, damage, pos, vel, dir, t, duration, height, landed, gone }
var _view: Painter


func _init(layer_: Node2D) -> void:
	layer = layer_
	_view = Painter.new(_draw)
	layer.add_child(_view)


# `weapon` supplies range, speed, damage and the kind of shot.
func throw(from: Vector2, to: Vector2, carry: Vector2, weapon: Dictionary) -> void:
	var d := to - from
	var length := d.length()
	if length == 0.0:
		length = 1.0
	var dist := minf(weapon.range, maxf(80.0, length))
	var lobbed: bool = weapon.shot == "stone"
	var vel: Vector2 = d / length * weapon.speed + (carry if lobbed else Vector2.ZERO)
	list.append({"lobbed": lobbed, "shot": weapon.shot, "damage": weapon.damage, "pos": from, "vel": vel,
		"dir": vel.normalized(), "t": 0.0, "duration": dist / weapon.speed, "height": 0.0, "landed": 0.0, "gone": false})


# Returns the enemies knocked out this frame.
func update(dt: float, enemies: Enemies) -> Array:
	var kills := []
	var finished := false
	for s in list:
		if s.landed:
			s.landed += dt
			finished = finished or s.landed >= 0.8
			continue
		s.t += dt
		s.pos += s.vel * dt
		var f := minf(1.0, s.t / s.duration)
		s.height = 4 * ARC_HEIGHT * f * (1 - f) if s.lobbed else 15.0 # arrows fly flat, at chest height

		# Anything hiding fills the whole bush or burrow it is in.
		var target: Enemy = null
		for e: Enemy in enemies.near(s.pos, 24.0 + HIT_RADIUS):
			if e.alive() and e.position.distance_to(s.pos) < (24.0 if e.in_hiding else e.radius) + HIT_RADIUS:
				target = e
				break
		if target:
			target.hit(s.dir.x, s.dir.y, s.damage)
			if not target.alive():
				kills.append(target)
			# Arrows and bolts stay stuck in whoever they hit
			if not s.lobbed:
				target.rig.stick_shaft(s.vel.x, s.vel.y, s.shot)
				s.gone = true
			s.landed = 0.4
			s.height = 0.0
		elif f >= 1:
			s.landed = dt
			s.height = 0.0
	if finished:
		list = list.filter(func(s: Dictionary) -> bool: return s.landed < 0.8)
	_view.queue_redraw()
	return kills


func _draw(ci: CanvasItem) -> void:
	var none := PackedVector2Array()
	for s in list:
		if s.gone:
			continue
		var alpha: float = 1.0 if not s.landed else maxf(0.0, 1 - s.landed / 0.8)
		var p: Vector2 = s.pos
		if s.lobbed:
			Draw.ellipse(ci, p, 4, 3, Color(0, 0, 0, 0.25 * alpha))
			var size: float = 1 + s.height / 50
			var at: Vector2 = p - Vector2(0, s.height)
			Draw.circle(ci, at, 4 * size, Color(STONE, alpha))
			Draw.circle(ci, at - Vector2(1.2, 1.2) * size, 1.6 * size, Color(STONE_LIT, alpha))
			continue
		# Arrow or bolt, the size of the one on the bow: shaft, steel head, fletching
		var d: Vector2 = s.dir
		var n := d.orthogonal()
		ci.draw_line(p - d * 7, p + d * 8, Color(0, 0, 0, 0.2 * alpha), 1.5)
		var at: Vector2 = p - Vector2(0, s.height)
		var bolt: bool = s.shot == "bolt"
		var half := 4.5 if bolt else 6.5
		ci.draw_line(at - d * half, at + d * half, Color(BOLT if bolt else SHAFT, alpha), 1.6 if bolt else 1.3)
		ci.draw_primitive(PackedVector2Array([at + d * (half + 3), at + d * (half - 0.5) - n * 1.6, at + d * (half - 0.5) + n * 1.6]), PackedColorArray([Color(STEEL, alpha)]), none)
		var feather := Color(BOLT if bolt else FEATHER, alpha)
		ci.draw_primitive(PackedVector2Array([at - d * half, at - d * (half + 3) - n * 2.2, at - d * (half - 2.5)]), PackedColorArray([feather]), none)
		ci.draw_primitive(PackedVector2Array([at - d * half, at - d * (half + 3) + n * 2.2, at - d * (half - 2.5)]), PackedColorArray([feather]), none)
