class_name Companion
extends Node2D

# A friendly hand taken on in a town (not in the JS original). They ride in
# the back of the cart and defend it: an archer picks out the nearest raider
# in range, draws, leads the shot and looses, over and over. They bring their
# own arrows. The node is a child of the cart, sitting on its seat (see
# HorseCart.seat_of).

const KINDS := {
	"archer": {
		"look": {"skin": "#c9a27a", "shirt": "#3f5a3a", "legs": "#3a3f26", "head": "hood", "head_colour": "#2f4a2a", "extras": ["quiver"]},
		"weapon": {"range": 520.0, "speed": 760.0, "damage": 1, "shot": "arrow"},
		"cooldown": 0.8, # seconds between shots
		"draw": 0.4, # seconds to draw the bow
	},
	# A soldier of the garrison: slower, harder-hitting bolts. Guards towns
	# and traders; not for hire.
	"crossbowman": {
		"look": {}, # (each a Folk.soldier(), see _init)
		"offhand": "crossbow",
		"weapon": {"range": 480.0, "speed": 940.0, "damage": 2, "shot": "bolt", "yours": false}, # (their kills aren't yours)
		"cooldown": 1.5,
		"draw": 0.6,
	},
}
const NAMES := ["Wynn", "Edric", "Maud", "Osric", "Hild", "Aldo", "Bryn", "Tamsin", "Cuthbert", "Elsa"]
const SCAN := 0.25 # seconds between looks round for a target

var kind: String
var info: Dictionary
var who: String
var rig: Rig
var seat := 0
var cooldown := 0.0
var drawing := 0.0
var target: Enemy = null
var _target_was := Vector2.ZERO # where the target was last frame (to lead the shot)
var _target_vel := Vector2.ZERO
var _scan := 0.0
var _gaze := 0.0 # where they look, relative to the cart, with nothing to shoot


# `seated`: riding the cart; otherwise standing guard where they're put.
func _init(kind_: String, who_: String, seated := true) -> void:
	kind = kind_
	who = who_
	info = KINDS[kind]
	var look: Dictionary = info.look.duplicate()
	if kind == "crossbowman":
		look = Folk.soldier() # (each their own face)
	rig = Rig.new(look)
	rig.seated = seated
	rig.always = seated
	rig.offhand = info.get("offhand", "bow")
	add_child(rig)


func title() -> String:
	return "%s the %s" % [who, kind]


# Look for a target and shoot at it. `cart_heading` is the way the cart faces
# (or a guard's post faces); shots go straight into `missiles`.
func update(dt: float, cart_heading: float, enemies: Enemies, missiles: Missiles) -> void:
	var me := global_position
	var reach: float = info.weapon.range
	cooldown -= dt
	_scan -= dt
	if target and (not is_instance_valid(target) or not target.alive() or target.in_hiding or target.global_position.distance_to(me) > reach):
		target = null
	if not target and _scan <= 0:
		_scan = SCAN
		var best := reach
		for e: Enemy in enemies.near(me, reach):
			var d := e.global_position.distance_to(me)
			if d < best and e.alive() and not e.in_hiding:
				best = d
				target = e
		if target:
			_target_was = target.global_position
			_target_vel = Vector2.ZERO

	var look := cart_heading + _gaze
	if target:
		var at := target.global_position
		_target_vel = _target_vel.lerp((at - _target_was) / maxf(dt, 0.001), 0.3)
		_target_was = at
		# Lead it: where it'll be when the arrow gets there
		var flight := me.distance_to(at) / float(info.weapon.speed)
		var aim_at := at + _target_vel * flight
		look = (aim_at - me).angle()
		if cooldown <= 0:
			drawing += dt
			if drawing >= info.draw:
				missiles.throw(me, aim_at, Vector2.ZERO, info.weapon)
				rig.loose()
				drawing = 0.0
				cooldown = info.cooldown
	else:
		drawing = 0.0
		# Keep watch: glance from side to side
		_gaze = sin(Time.get_ticks_msec() / 1000.0 * 0.6 + seat * 2.0) * 1.2

	rig.aiming = target != null
	rig.loaded = cooldown <= 0
	rig.pull = clampf(drawing / info.draw, 0, 1) if target else 0.0
	rig.update(dt, look, 0)
