class_name Peasant
extends Node2D

# The peasant on foot (port of peasant.js): walks with WASD, faces the mouse,
# and bumps into trees, buildings and the horse and cart. Drawn as a jointed
# figure in a straw hat (see Rig). The node sits where the peasant stands, so
# it sorts with the raiders by depth.

const WALK_SPEED := 120.0
const SPRINT_SPEED := 195.0
const DASH_SPEED := 430.0
const DASH_TIME := 0.17 # seconds of dash (about 70 px)
const RADIUS := 8.0

# Equipped items drawn in the peasant's hands (Rig weapon names), by icon.
const MELEE := {"club": "club", "sword": "sword", "spear": "spear", "axe": "axe"}
const RANGED := {"bow": "bow", "crossbow": "crossbow", "sling": "sling"}

var vx := 0.0
var vy := 0.0
var facing := 0.0
var dash_t := 0.0
var rig: Rig


func _init() -> void:
	rig = Rig.new({"skin": "#d9b08c", "shirt": "#6b5b3e", "legs": "#4a3a2b", "head": "straw"})
	add_child(rig)
	visible = false


func active() -> bool:
	return visible


func place(x: float, y: float) -> void:
	position = Vector2(x, y)
	vx = 0.0
	vy = 0.0
	visible = true
	_render(0.0)


func hide_peasant() -> void:
	visible = false


# --- What Game uses to put weapons in hand and play attacks ---

func set_weapon(item: Variant) -> void:
	rig.weapon = MELEE.get(item.icon) if item else null


func play(move: String, back := false, windup := 0.0) -> void:
	rig.play(move, back, windup)


# `draw`: how far the next shot has been drawn back (0..1)
func set_bow(item: Variant, loaded: bool, draw := 1.0) -> void:
	rig.offhand = RANGED.get(item.icon) if item else null
	rig.loaded = loaded
	rig.aiming = rig.offhand != null
	rig.pull = draw


func fire() -> void:
	rig.loose()


# A quick burst along (dx, dy); steering is ignored until it's over.
func dash(dx: float, dy: float) -> void:
	var d := Vector2(dx, dy)
	d = d.normalized() if d != Vector2.ZERO else Vector2.ZERO
	vx = d.x * DASH_SPEED
	vy = d.y * DASH_SPEED
	dash_t = DASH_TIME


func dashing() -> bool:
	return dash_t > 0


# input: { up, down, left, right }; obstacles: Vector3(x, y, radius).
func update(dt: float, input: Dictionary, aim: Vector2, obstacles: Array, sprinting := false) -> void:
	var mx := int(input.get("right", false)) - int(input.get("left", false))
	var my := int(input.get("down", false)) - int(input.get("up", false))
	var length := Vector2(mx, my).length()
	if length == 0.0:
		length = 1.0
	if dash_t > 0:
		dash_t -= dt
	else:
		var top := SPRINT_SPEED if sprinting else WALK_SPEED
		var k := 1.0 - exp(-dt * 12)
		vx += (mx / length * top - vx) * k
		vy += (my / length * top - vy) * k
	rig.lean = 1.0 if dash_t > 0 else (0.6 if sprinting and (mx or my) else 0.0)
	position += Vector2(vx, vy) * dt

	for ob: Vector3 in obstacles:
		var d := position - Vector2(ob.x, ob.y)
		var dist := d.length()
		if dist == 0.0:
			dist = 1.0
		var overlap := ob.z + RADIUS - dist
		if overlap > 0:
			position += d / dist * overlap

	facing = (aim - position).angle()
	_render(dt)


func _render(dt: float) -> void:
	rig.update(dt, facing, Vector2(vx, vy).length())
