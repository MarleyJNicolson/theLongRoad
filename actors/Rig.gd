class_name Rig
extends Node2D

# A jointed humanoid seen in three-quarter view (port of rig.js): legs, arms,
# torso and head, posed procedurally (walking, swinging weapons, flinching) and
# turned into a verlet ragdoll when it dies.
#
# Poses are worked out in the figure's own 3D frame, as Vector3(a, b, z): `a`
# forward along the way it faces, `b` to its right, `z` up. They're drawn by
# putting the ground position on the map and lifting it by its height, so a
# figure seen from any direction shows its limbs, and parts nearer the camera
# (lower on the screen) are drawn over the ones further away.
#
# The node's origin is where the figure stands; sort it with the other uprights.

# Body proportions for a figure of scale 1 (an adult).
const BODY := {
	"hip": 15.0, # height of the hips
	"thigh": 7.8,
	"shin": 7.8,
	"torso": 11.0,
	"neck": 2.5,
	"head": 4.6, # radius
	"hip_w": 3.0,
	"shoulder_w": 5.2,
	"upper_arm": 6.2,
	"fore_arm": 6.2,
	"stride": 5.5,
	"lift": 3.0,
}

# How far each kind of weapon reaches from the hand, and how it's drawn.
const WEAPON_LENGTH := {"dagger": 9.0, "club": 14.0, "sword": 18.0, "cleaver": 18.0, "mace": 15.0, "spear": 30.0, "axe": 16.0}

const GRAVITY := 900.0
const RAGDOLL_TIME := 1.8 # seconds before a corpse settles for good

# Player move durations (seconds), by name.
const MOVE_TIME := {"swing": 0.18, "slash": 0.11, "jab": 0.2, "heavy": 0.16}

# Joint pairs held at fixed length in the ragdoll (with cross-braces so the
# torso keeps its shape).
const STICKS := [
	["hipL", "kneeL"], ["kneeL", "footL"], ["hipR", "kneeR"], ["kneeR", "footR"],
	["shL", "elbL"], ["elbL", "handL"], ["shR", "elbR"], ["elbR", "handR"],
	["neck", "head"], ["shL", "shR"], ["hipL", "hipR"], ["shL", "hipL"], ["shR", "hipR"],
	["shL", "hipR"], ["shR", "hipL"], ["neck", "shL"], ["neck", "shR"], ["neck", "hipL"], ["neck", "hipR"],
]

# Where an arrow can stick: joint pair and the span along it.
const SHAFT_SPOTS := [
	["neck", "hipL", 0.2, 0.7], ["neck", "hipR", 0.2, 0.7], ["neck", "hipL", 0.3, 0.6], # the trunk, most of all
	["shL", "elbL", 0.2, 0.8], ["shR", "elbR", 0.2, 0.8],
	["hipL", "kneeL", 0.2, 0.8], ["hipR", "kneeR", 0.2, 0.8],
]


# Colours, parsed once
const C_1C1714 := Color("#1c1714")
const C_2B221C := Color("#2b221c")
const C_3A3620 := Color("#3a3620")
const C_4A3220 := Color("#4a3220")
const C_5E3F22 := Color("#5e3f22")
const C_6B4A2A := Color("#6b4a2a")
const C_6E4A28 := Color("#6e4a28")
const C_7D8590 := Color("#7d8590")
const C_8A9096 := Color("#8a9096")
const C_8B6236 := Color("#8b6236")
const C_9A968C := Color("#9a968c")
const C_A6AEB7 := Color("#a6aeb7")
const C_B9C0C8 := Color("#b9c0c8")
const C_C29D48 := Color("#c29d48")
const C_C9A227 := Color("#c9a227")
const C_C9B28A := Color("#c9b28a")
const C_C9C9C9 := Color("#c9c9c9")
const C_D4B25E := Color("#d4b25e")
const C_D8CFB4 := Color("#d8cfb4")
const C_D8DDE2 := Color("#d8dde2")
const C_E8E0C8 := Color("#e8e0c8")
const C_EFE6CF := Color("#efe6cf")
const C_FFCF3A := Color("#ffcf3a")
const C_FFE14D := Color("#ffe14d")
const C_FFF4D6 := Color("#fff4d6")
const QUIVER := C_6E4A28
const FLETCH := C_E8E0C8

# The parts of a figure, drawn far to near (see _draw), and the four limbs:
# [joints..., width, style colour, end radius, end style colour]
enum { PART_LIMB, PART_TORSO, PART_QUIVER, PART_HEAD, PART_WEAPON, PART_OFFHAND, PART_SHAFT }
const LIMBS := [
	["hipL", "kneeL", "footL", 3.4, "legs", 1.9, "boots"],
	["hipR", "kneeR", "footR", 3.4, "legs", 1.9, "boots"],
	["shL", "elbL", "handL", 2.8, "shirt", 1.6, "skin"],
	["shR", "elbR", "handR", 2.8, "shirt", 1.6, "skin"],
]

# One point of the ragdoll (verlet: current and previous position).
class Particle:
	var p: Vector3
	var prev: Vector3

	func _init(p_: Vector3, prev_: Vector3) -> void:
		p = p_
		prev = prev_


# style: { scale, skin, shirt, legs, boots, head: straw|hood|goblin|orc|helm|hat|hair|kerchief,
#          head_colour, mask, extras: [quiver, cape, ears, apron], cape_colour, apron }
var style: Dictionary
var k: float # scale
var facing := PI / 2
var phase := randf() * TAU
var speed := 0.0
var weapon: Variant = null # dagger, club, sword, cleaver, mace, spear, axe (or null: fists)
var offhand: Variant = null # bow, crossbow, sling, shield
var loaded := true # an arrow nocked on the bow
var aiming := false
var pull := 0.0 # how far the bow (or crossbow) string is drawn back, 0..1
var spin := 0.0 # a sling's whirl
var lean := 0.0 # leaning into a sprint or dash, 0..1
var seated := false # sitting (on the cart's bench), hips at `seat_z`
var seat_z := 0.0
var wave := 0.0 # waving (a villager's greeting), 0 for not; counts up while waving
var move: Variant = null # a player's attack: { name, t, back, windup }
var strike: Variant = null # a raider's attack: { phase, p }
var trail: Variant = null # the arc of a swing, while it lasts: [from, to]
var kick := 0.0 # bow recoil
var flinch := 0.0
var ragdoll: Variant = null # { parts: {name: Particle}, sticks, t, weapon, offhand }
var stuck: Array = [] # arrows and bolts sticking out of it

var _frame: Dictionary = {} # the pose worked out by the last update, for _draw
var _settled_drawn := false # a corpse at rest is drawn once more, then left be
var _last_look: Array = [] # what the last drawing showed (see update)

# The part of the world in view (plus a margin), set by Game each frame: rigs
# outside it keep time but skip working out and drawing their pose, which is
# most of their cost. (Infinite until set, so everything draws.)
static var view := Rect2(-1e9, -1e9, 2e9, 2e9)


func _init(style_: Dictionary) -> void:
	style = {"scale": 1.0, "boots": "#2b221c", "extras": []}
	style.merge(style_, true)
	for key in ["skin", "shirt", "legs", "boots", "head_colour", "mask", "cape_colour", "apron"]:
		if style.has(key) and style[key] is String:
			style[key] = Color(style[key])
	k = style.scale
	weapon = style.get("weapon")
	offhand = style.get("offhand")
	_frame = pose()


func height() -> float:
	return (BODY.hip + BODY.torso + BODY.neck + BODY.head * 2) * k


func _has_extra(extra: String) -> bool:
	return extra in style.extras


# --- Driving it -------------------------------------------------------------

func play(move_name: String, back := false, windup := 0.0) -> void:
	move = {"name": move_name, "t": 0.0, "back": back, "windup": windup}


func set_strike(strike_phase: Variant, p := 0.0) -> void:
	strike = {"phase": strike_phase, "p": p} if strike_phase else null


func loose() -> void:
	kick = 1.0


func hit_by() -> void:
	flinch = 1.0


# Go limp: start the ragdoll from the current pose, flung along (dx, dy).
func die(dx := 0.0, dy := 0.0, force := 1.0) -> void:
	if ragdoll:
		return
	var joints: Dictionary = pose().joints
	var f := Vector2(cos(facing), sin(facing))
	var l := Vector2(-f.y, f.x)
	var parts := {}
	for joint_name in joints:
		var p: Vector3 = joints[joint_name]
		var x := f.x * p.x + l.x * p.y
		var y := f.y * p.x + l.y * p.y
		# Knocked along the blow, the upper body most, with a little lift
		var push := (60.0 + 90.0 * force) * (0.4 + p.z / height())
		var v := Vector3(dx * push + (randf() - 0.5) * 30.0, dy * push + (randf() - 0.5) * 30.0, 40.0 + randf() * 30.0)
		var at := Vector3(x, y, p.z)
		parts[joint_name] = Particle.new(at, at - v / 60.0)
	var sticks := []
	for pair in STICKS:
		var a: Particle = parts[pair[0]]
		var b: Particle = parts[pair[1]]
		sticks.append([a, b, a.p.distance_to(b.p)])
	ragdoll = {"parts": parts, "sticks": sticks, "t": 0.0, "weapon": weapon, "offhand": offhand}
	move = null
	strike = null
	trail = null


# An arrow or bolt flying along (dir_x, dir_y) sticks in somewhere on the body
# and stays there, through death and all.
func stick_shaft(dir_x: float, dir_y: float, kind := "arrow") -> void:
	var spot: Array = SHAFT_SPOTS[randi() % SHAFT_SPOTS.size()]
	stuck.append({
		"a": spot[0],
		"b": spot[1],
		"t": spot[2] + randf() * (spot[3] - spot[2]),
		"rel": atan2(dir_y, dir_x) - facing + (randf() - 0.5) * 0.5, # which way it came, relative to the body
		"tilt": randf() * 0.5,
		"kind": kind,
	})
	if stuck.size() > 8:
		stuck.pop_front()


# Where the weapon is, as points on the ground relative to the figure, from
# near the hand out to the tip (used to tell whether a blow connects).
func weapon_points() -> Array[Vector2]:
	var held: Dictionary = pose().weapon
	var length: float = WEAPON_LENGTH.get(weapon, 3.0) * k
	var f := Vector2(cos(facing), sin(facing))
	var l := Vector2(-f.y, f.x)
	var out: Array[Vector2] = []
	for t in [0.35, 0.7, 1.0]:
		var p: Vector3 = held.hand + held.dir * length * t
		out.append(Vector2(f.x * p.x + l.x * p.y, f.y * p.x + l.y * p.y))
	return out


# --- Each frame -------------------------------------------------------------

func update(dt: float, facing_: float, speed_: float) -> void:
	if ragdoll:
		_simulate(dt)
	else:
		facing = facing_
		speed = speed_
		phase += speed * dt / (5.5 * k)
		if move:
			move.t += dt
		if wave:
			wave += dt
		kick = maxf(0.0, kick - dt * 6.0)
		# A sling whirls faster the closer it is to being let fly
		if offhand == "sling" and aiming:
			spin += dt * (6.0 + pull * 22.0)
		flinch = maxf(0.0, flinch - dt * 4.0)
	# A corpse that has come to rest: draw it once more, then leave it be
	if ragdoll and ragdoll.t > RAGDOLL_TIME:
		if not _settled_drawn:
			_settled_drawn = true
			queue_redraw()
		return
	# Out of sight: nothing to draw (finished moves still end on time)
	if not view.has_point(global_position):
		if move and move.t > MOVE_TIME.get(move.name, 0.0) + move.windup:
			move = null
		return
	# Unchanged since it was last drawn (someone standing about): leave it be.
	# Drawing a figure is the dear part, and most of them are idle.
	if not ragdoll:
		var look := [facing, phase if speed > 0.5 else -1.0, flinch, kick, pull, spin, wave, lean, aiming, loaded,
			weapon, offhand, seated, stuck.size(), move.t if move else -1.0,
			str(strike.phase) + str(strike.p) if strike else ""]
		if look == _last_look:
			return
		_last_look = look
	# Work the pose out now (it also ends finished moves), draw it later.
	_frame = {} if ragdoll else pose()
	queue_redraw()


# Two-bone limb: where the middle joint sits, bending towards `bend` (+1
# forwards, -1 backwards) in the limb's own vertical plane.
static func joint(from: Vector3, to: Vector3, upper: float, lower: float, bend: float) -> Vector3:
	var d := to - from
	var reach := d.length()
	var length := minf(reach, upper + lower - 0.01)
	if length == 0.0:
		length = 0.01
	if reach == 0.0:
		reach = 0.01
	# distance along the limb to the joint, and how far it pokes out
	var x := (upper * upper - lower * lower + length * length) / (2.0 * length)
	var h := sqrt(maxf(0.0, upper * upper - x * x))
	var u := d / reach
	# perpendicular in the forward/up plane
	var pa := -u.z * bend
	var pz := u.x * bend
	var pl := Vector2(pa, pz).length()
	if pl == 0.0:
		pl = 1.0
	pa /= pl
	pz /= pl
	return Vector3(from.x + u.x * x + pa * h, from.y + u.y * x, from.z + u.z * x + pz * h)


# The figure's joints right now, plus where its weapon hand and weapon point:
# { joints: {name: Vector3}, weapon: { hand, dir } }.
func pose() -> Dictionary:
	var B := BODY
	var walk := minf(1.0, speed / 40.0)
	var bob := absf(sin(phase)) * 1.2 * walk
	# Knocked back on the heels by a blow; leaning in to a sprint or dash
	var tilt := -flinch * 3.0 + lean * 3.5
	var hip_z: float = seat_z if seated else (B.hip + bob - flinch * 1.5) * k
	var chest := Vector3(tilt * k, 0, hip_z + B.torso * k)
	var j := {}
	j.neck = chest + Vector3(tilt * 0.5 * k, 0, B.neck * 0.3 * k)
	j.head = chest + Vector3(tilt * 0.8 * k, 0, (B.neck + B.head) * k)

	for side in ["L", "R"]:
		var s := -1.0 if side == "L" else 1.0
		var leg_phase := phase + (PI if s > 0 else 0.0)
		var hip := Vector3(0, s * B.hip_w * k, hip_z)
		# Sitting: feet planted on the footboard in front
		var foot: Vector3
		if seated:
			foot = Vector3(6 * k, s * (B.hip_w + 0.5) * k, hip_z - 9 * k)
		else:
			foot = Vector3(sin(leg_phase) * B.stride * walk * k, s * B.hip_w * k, maxf(0.0, cos(leg_phase)) * B.lift * walk * k)
		j["hip" + side] = hip
		j["foot" + side] = foot
		j["knee" + side] = joint(hip, foot, B.thigh * k, B.shin * k, 1)
		var sh := Vector3(chest.x, s * B.shoulder_w * k, chest.z - 1 * k)
		j["sh" + side] = sh
		# Hanging, swinging opposite the legs (or holding the reins out in front)
		if seated:
			j["hand" + side] = Vector3(7 * k, s * 3 * k, hip_z + 6 * k)
		else:
			j["hand" + side] = Vector3(
				sh.x - sin(leg_phase) * 3.5 * walk * k + 1.5 * k,
				s * (B.shoulder_w + 1.2) * k,
				sh.z - (B.upper_arm + B.fore_arm - 2.5) * k)

	# Weapon hand (right)
	var held := _weapon_hand(j.shR)
	# (A seated driver with nothing in hand keeps it on the reins)
	if not (seated and not weapon and not move and not strike):
		j.handR = held.hand
	# Off hand (left): a bow held up to shoot, or a shield held before you
	if offhand == "shield":
		j.handL = Vector3(j.shL.x + 7 * k, -3 * k, j.shL.z - 4 * k)
	elif offhand and (aiming or offhand == "crossbow"):
		j.handL = Vector3(j.shL.x + (10 - kick * 2) * k, -1.5 * k, j.shL.z - 1 * k)
	# Drawing a bow: the right hand pulls the string back towards the cheek.
	# Spanning a crossbow: hauls the string back to the latch, then takes the
	# stock once it's cocked.
	var drawing: bool = aiming and not move and not strike
	if drawing and offhand == "bow":
		j.handR = j.handL + Vector3(-(2 + pull * 8) * k, 1 * k, (1 + pull) * k)
		held = {"hand": j.handR, "dir": held.dir}
	elif drawing and offhand == "crossbow":
		j.handR = j.handL + Vector3(-(pull * 6 if pull < 1 else 6.0) * k, 1.5 * k, (1.5 if pull < 1 else -1.0) * k)
		held = {"hand": j.handR, "dir": held.dir}
	# Waving: the right hand up above the head, swaying side to side
	if wave and not weapon:
		j.handR = Vector3(2 * k, (B.shoulder_w + 2.5 + sin(wave * 9) * 2.5) * k, chest.z + 8 * k)
	for side in ["L", "R"]:
		j["elb" + side] = joint(j["sh" + side], j["hand" + side], B.upper_arm * k, B.fore_arm * k, -1)
	return {"joints": j, "weapon": held}


static func _ease(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


# Where the weapon hand is and which way the weapon points, for the attack in
# progress (if any): { hand, dir }.
func _weapon_hand(sh: Vector3) -> Dictionary:
	# A sweep round the shoulder at angle alpha (0 = straight ahead, + = to the right)
	var sweep := func(alpha: float, lift: float, tilt: float) -> Dictionary:
		var R: float = (BODY.upper_arm + BODY.fore_arm - 1.5) * k
		return {
			"hand": sh + Vector3(cos(alpha) * R * 0.9, sin(alpha) * R * 0.9, -2 * k + lift * k),
			"dir": Vector3(cos(alpha), sin(alpha), tilt),
		}
	var rest := {
		"hand": sh + Vector3(3 * k, 1.5 * k, -(BODY.upper_arm + BODY.fore_arm - 4) * k),
		"dir": Vector3(0.55, 0.2, 0.81),
	}
	trail = null
	if strike:
		# A raider: wind up, swing through, recover
		var p: float = strike.p
		if strike.phase == "windup":
			return sweep.call(lerpf(0.6, 1.9, _ease(p)), 5 * p, 0.4 * p)
		if strike.phase == "swing":
			var alpha := lerpf(1.9, -1.0, p * p)
			trail = [1.9, alpha]
			return sweep.call(alpha, 5 - 6 * p, 0.05)
		return sweep.call(lerpf(-1.0, 0.6, _ease(p)), -1 + p, 0.05)
	if move:
		var T: float = MOVE_TIME[move.name]
		if move.name == "swing" or move.name == "slash":
			var p: float = move.t / T
			if p < 1:
				var from := -1.1 if move.back else 1.3
				var to := 1.3 if move.back else -1.1
				var alpha := lerpf(from, to, _ease(p))
				trail = [from, alpha]
				return sweep.call(alpha, 0.0, 0.05)
		elif move.name == "jab":
			var p: float = move.t / T
			if p < 1:
				var out := sin(p * PI)
				return {"hand": sh + Vector3((4 + 10 * out) * k, 0.5 * k, -3 * k), "dir": Vector3(1, -0.05, 0.02)}
		elif move.name == "heavy":
			if move.t < move.windup:
				var p := _ease(move.t / move.windup)
				return sweep.call(lerpf(0.6, 2.2, p), 9 * p, 0.9 * p)
			var p: float = (move.t - move.windup) / T
			if p < 1:
				var alpha := lerpf(2.2, -1.2, p * p)
				trail = [2.2, alpha]
				return sweep.call(alpha, 9 - 12 * p, 0.9 - 1.2 * p)
		move = null
	return rest


# --- Ragdoll ----------------------------------------------------------------

func _simulate(dt: float) -> void:
	if ragdoll.t > RAGDOLL_TIME:
		return
	ragdoll.t += dt
	var steps := 2
	var h := minf(dt, 1.0 / 30.0) / steps
	for s in steps:
		for part: Particle in ragdoll.parts.values():
			var v := (part.p - part.prev) * 0.99
			part.prev = part.p
			part.p += v
			part.p.z -= GRAVITY * h * h
			if part.p.z < 0:
				# Hit the ground: stop falling, and drag
				part.p.z = 0
				part.prev = Vector3(part.p.x - v.x * 0.55, part.p.y - v.y * 0.55, 0)
		for it in 6:
			for stick in ragdoll.sticks:
				var a: Particle = stick[0]
				var b: Particle = stick[1]
				var d := b.p - a.p
				var dist := maxf(d.length(), 0.001)
				var diff: Vector3 = d * ((dist - stick[2]) / dist / 2.0)
				a.p += diff
				b.p -= diff


# --- Drawing ----------------------------------------------------------------

# A thick line with round caps and joins.
func _round_line(points: PackedVector2Array, width: float, colour: Color) -> void:
	Draw.round_line(self, points, width, colour)


func _line(p: Vector2, q: Vector2, width: float, colour: Color) -> void:
	_round_line(PackedVector2Array([p, q]), width, colour)


func _ellipse(c: Vector2, rx: float, ry: float, colour: Color) -> void:
	Draw.ellipse(self, c, rx, ry, colour)


static func _quad_curve(a: Vector2, control: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for n in 9:
		var t := n / 8.0
		pts.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return pts


static func _xy(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y)


func _draw() -> void:
	var st := style
	# Screen position of each joint: Vector3(x, y, depth), depth higher is nearer
	var pts := {}
	var weapon_line: Variant = null
	var f := Vector2(cos(facing), sin(facing))
	var l := Vector2(-f.y, f.x)
	var proj := func(p: Vector3) -> Vector3:
		var x := f.x * p.x + l.x * p.y
		var y := f.y * p.x + l.y * p.y
		return Vector3(x, y - p.z, y)
	if ragdoll:
		for n in ragdoll.parts:
			var p: Vector3 = ragdoll.parts[n].p
			pts[n] = Vector3(p.x, p.y - p.z, p.y)
		if ragdoll.weapon:
			var hand: Vector3 = ragdoll.parts.handR.p
			var elb: Vector3 = ragdoll.parts.elbR.p
			weapon_line = _weapon_from(pts.handR, hand - elb, true)
	else:
		var joints: Dictionary = _frame.joints
		for n in joints:
			pts[n] = proj.call(joints[n])
		if weapon:
			var dir: Vector3 = _frame.weapon.dir
			weapon_line = _weapon_from(pts.handR, Vector3(f.x * dir.x + l.x * dir.y, f.y * dir.x + l.y * dir.y, dir.z))
		# A faint trail along the path of a swing
		if trail:
			var R: float = (BODY.upper_arm + BODY.fore_arm + WEAPON_LENGTH.get(weapon, 3.0)) * k
			var line := PackedVector2Array()
			for n in 9:
				var al := lerpf(trail[0], trail[1], n / 8.0)
				line.append(_xy(proj.call(joints.shR + Vector3(cos(al) * R, sin(al) * R, -2 * k))))
			draw_polyline(line, Color(C_FFF4D6, 0.6), 2.5)

	# Shadow on the ground under the body
	if not ragdoll and not seated:
		var c := Vector2((pts.hipL.x + pts.hipR.x) / 2, (pts.hipL.z + pts.hipR.z) / 2)
		_ellipse(c, 7 * k, 3 * k, Color(0, 0, 0, 0.25))

	# Parts, drawn far to near: [depth, what, detail] (no closures: this runs
	# for every figure in view, every frame it moves)
	var parts := [
		[(pts.hipL.z + pts.kneeL.z + pts.footL.z) / 3.0, PART_LIMB, LIMBS[0]],
		[(pts.hipR.z + pts.kneeR.z + pts.footR.z) / 3.0, PART_LIMB, LIMBS[1]],
		[(pts.shL.z + pts.elbL.z + pts.handL.z) / 3.0, PART_LIMB, LIMBS[2]],
		[(pts.shR.z + pts.elbR.z + pts.handR.z) / 3.0, PART_LIMB, LIMBS[3]],
	]
	var torso_depth: float = (pts.shL.z + pts.shR.z + pts.hipL.z + pts.hipR.z) / 4
	parts.append([torso_depth, PART_TORSO, null])
	if _has_extra("quiver"):
		parts.append([torso_depth - 2 * k * sin(facing), PART_QUIVER, null])
	parts.append([pts.head.z + 0.01, PART_HEAD, null])
	if weapon_line:
		parts.append([pts.handR.z + 0.02, PART_WEAPON, weapon_line])
	var off: Variant = null
	if offhand:
		off = ragdoll.offhand if ragdoll else offhand
	if off:
		parts.append([pts.handL.z + 0.02, PART_OFFHAND, off])
	for s in stuck:
		var d: float = lerpf(pts[s.a].z, pts[s.b].z, s.t) - sin(facing + s.rel) * 2
		parts.append([d, PART_SHAFT, s])

	parts.sort_custom(_nearer)
	for part in parts:
		match part[1]:
			PART_LIMB:
				var limb: Array = part[2]
				var end: Vector3 = pts[limb[2]]
				_round_line(PackedVector2Array([_xy(pts[limb[0]]), _xy(pts[limb[1]]), _xy(end)]), limb[3] * k, st[limb[4]])
				Draw.circle(self, _xy(end), limb[5] * k, st[limb[6]])
			PART_TORSO:
				_draw_torso(pts)
			PART_QUIVER:
				var x: float = (pts.shL.x + pts.shR.x) / 2 - cos(facing) * 3 * k
				var y: float = (pts.shL.y + pts.shR.y) / 2 - sin(facing) * 1.5 * k
				draw_rect(Rect2(x - 2 * k, y - 2 * k, 4 * k, 9 * k), QUIVER)
				draw_line(Vector2(x - 1 * k, y - 2 * k), Vector2(x - 1.5 * k, y - 5 * k), FLETCH, 1.0)
				draw_line(Vector2(x + 1 * k, y - 2 * k), Vector2(x + 1.5 * k, y - 5 * k), FLETCH, 1.0)
			PART_HEAD:
				_draw_head(_xy(pts.head))
			PART_WEAPON:
				_draw_weapon(part[2])
			PART_OFFHAND:
				_draw_offhand(pts, part[2])
			PART_SHAFT:
				_draw_shaft(pts, part[2])


static func _nearer(p: Array, q: Array) -> bool:
	return p[0] < q[0]


func _draw_torso(pts: Dictionary) -> void:
	var st := style
	var sh_l := _xy(pts.shL)
	var sh_r := _xy(pts.shR)
	var hip_l := _xy(pts.hipL)
	var hip_r := _xy(pts.hipR)
	var neck := _xy(pts.neck)
	_line((hip_l + hip_r) / 2, neck, 8 * k, st.shirt)
	_poly([sh_l, sh_r, hip_r, hip_l], st.shirt)
	# Belt
	_line(hip_l, hip_r, 2 * k, C_2B221C)
	if _has_extra("apron"):
		var lo := func(p: Vector2, t: float) -> Vector2:
			return Vector2(lerpf(neck.x, p.x, t), lerpf(neck.y, p.y, t) + 4 * k * t)
		_poly([sh_l.lerp(hip_l, 0.4), sh_r.lerp(hip_r, 0.4), lo.call(hip_r, 1.15), lo.call(hip_l, 1.15)], st.get("apron", C_D8CFB4))
	if _has_extra("cape"):
		var cape: Color = st.cape_colour
		cape.a = 0.9
		_poly([sh_l, sh_r, hip_r + Vector2(0, 3 * k), hip_l + Vector2(0, 3 * k)], cape)


# A filled polygon, skipping slivers that can't be triangulated.
func _poly(pts: Array, colour: Color) -> void:
	Draw.convex(self, PackedVector2Array(pts), colour)


func _draw_head(at: Vector2) -> void:
	var st := style
	var head: String = st.get("head", "")
	var r: float = BODY.head * k * (1.25 if head == "orc" else 1.15 if head == "goblin" else 1.0)
	var f := Vector2(cos(facing), sin(facing))
	var faces_us: bool = not ragdoll and f.y > -0.25 # can we see the face?
	var fx := f.x * r * 0.45
	var skin: Color = st.skin
	var ink := C_1C1714
	if head == "goblin" or _has_extra("ears"):
		_poly([at + Vector2(-r * 0.6, 0), at + Vector2(-r * 1.9, -r * 0.7), at + Vector2(-r * 0.4, -r * 0.3)], skin)
		_poly([at + Vector2(r * 0.6, 0), at + Vector2(r * 1.9, -r * 0.7), at + Vector2(r * 0.4, -r * 0.3)], skin)
	Draw.circle(self, at, r, skin)
	var eyes := func(colour: Color, size: float) -> void:
		if not faces_us:
			return
		for s in [-1.0, 1.0]:
			Draw.circle(self, at + Vector2(fx + s * r * 0.38 * absf(f.y), -r * 0.1), size * k, colour)
	match head:
		"straw":
			eyes.call(ink, 0.8)
			_ellipse(at - Vector2(0, r * 0.6), r * 1.9, r * 0.75, C_D4B25E)
			_ellipse(at - Vector2(0, r * 0.85), r * 1.0, r * 0.6, C_C29D48)
		"hood":
			Draw.circle(self, at - Vector2(0, r * 0.1), r * 1.12, st.head_colour)
			if faces_us:
				Draw.circle(self, at + Vector2(fx, r * 0.1), r * 0.7, skin)
				eyes.call(ink, 0.8)
				if st.has("mask"):
					draw_rect(Rect2(at.x + fx - r * 0.7, at.y + r * 0.15, r * 1.4, r * 0.45), st.mask)
		"helm":
			Draw.circle(self, at - Vector2(0, r * 0.1), r * 1.12, C_A6AEB7)
			if faces_us:
				draw_rect(Rect2(at.x + fx - r * 0.6, at.y - r * 0.15, r * 1.2, r * 0.22), ink)
			draw_rect(Rect2(at.x - r * 0.15, at.y - r * 1.2, r * 0.3, r * 0.6), C_7D8590)
		"hat":
			eyes.call(ink, 0.8)
			_ellipse(at - Vector2(0, r * 0.55), r * 2.1, r * 0.7, st.head_colour)
			_ellipse(at - Vector2(0, r * 0.85), r * 1.0, r * 0.65, st.head_colour)
			draw_rect(Rect2(at.x - r, at.y - r * 0.75, r * 2, r * 0.2), C_C9A227)
		"goblin":
			eyes.call(C_FFE14D, 1.0)
		"orc":
			eyes.call(C_FFCF3A, 1.0)
			if faces_us:
				for s in [-1.0, 1.0]:
					_poly([at + Vector2(fx + s * r * 0.35, r * 0.35), at + Vector2(fx + s * r * 0.5, -r * 0.15), at + Vector2(fx + s * r * 0.15, r * 0.3)], C_EFE6CF)
			draw_rect(Rect2(at.x - r * 0.9, at.y - r * 1.0, r * 1.8, r * 0.35), C_3A3620) # brow
		"hair":
			Draw.circle(self, at + Vector2(-fx * 0.4, -r * 0.25), r * 1.02, st.head_colour)
			if faces_us:
				Draw.circle(self, at + Vector2(fx, r * 0.12), r * 0.72, skin)
				eyes.call(ink, 0.8)
		"kerchief":
			if faces_us:
				eyes.call(ink, 0.8)
			_ellipse(at + Vector2(-fx * 0.3, -r * 0.45), r * 1.08, r * 0.7, st.head_colour)
		_:
			eyes.call(ink, 0.8)


# Where the weapon is drawn: from the hand along `dir` (screen x/y on the
# ground plus height z). Returns what _draw_weapon needs.
func _weapon_from(hand3: Vector3, dir: Vector3, fallen := false) -> Dictionary:
	var kind: Variant = ragdoll.weapon if ragdoll else weapon
	var length: float = WEAPON_LENGTH.get(kind, 3.0) * k
	var n := dir.length()
	if n == 0.0:
		n = 1.0
	var ux := dir.x / n
	var uy := (dir.y - (0.0 if fallen else dir.z)) / n
	return {"kind": kind, "hand": _xy(hand3), "u": Vector2(ux, uy), "length": length}


func _draw_weapon(w: Dictionary) -> void:
	var hand: Vector2 = w.hand
	var u: Vector2 = w.u
	var length: float = w.length
	var ux := u.x
	var uy := u.y
	var tip := hand + u * length
	var side := Vector2(-uy, ux) # across the blade
	match w.kind:
		"dagger":
			_line(hand, tip, 1.8 * k, C_C9C9C9)
		"sword":
			_line(hand, (hand + u * (length * 0.15)), 2.2 * k, C_5E3F22)
			_line((hand + u * (length * 0.15)), tip, 2.4 * k, C_D8DDE2)
			_line((hand + u * (length * 0.15)) + side * 3.5 * k, (hand + u * (length * 0.15)) - side * 3.5 * k, 1.8 * k, C_C9A227)
		"club":
			_line(hand, (hand + u * (length * 0.5)), 2.4 * k, C_6B4A2A)
			_line((hand + u * (length * 0.5)), tip, 4 * k, C_6B4A2A)
		"mace":
			_line(hand, (hand + u * (length * 0.75)), 2 * k, C_4A3220)
			Draw.circle(self, tip, 3.2 * k, C_8A9096)
		"cleaver":
			_line(hand, (hand + u * (length * 0.3)), 2.6 * k, C_4A3220)
			var blade := 4.5 * k
			_poly([(hand + u * (length * 0.3)), tip, tip + side * blade, (hand + u * (length * 0.3)) + side * blade], C_8A9096)
		"spear":
			_line(hand, tip, 1.8 * k, C_8B6236)
			_poly([tip + Vector2(ux, uy) * 5 * k, tip + side * 2.2 * k, tip - side * 2.2 * k], C_D8DDE2)
			_line(hand - Vector2(ux, uy) * 6 * k, hand, 1.8 * k, C_8B6236)
		"axe":
			_line(hand, tip, 2.2 * k, C_6B4A2A)
			var blade := 4.5 * k
			_poly([(hand + u * (length * 0.75)), tip, tip + side * blade + Vector2(ux, uy) * 2, (hand + u * (length * 0.75)) + side * blade], C_B9C0C8)


func _draw_offhand(pts: Dictionary, kind: String) -> void:
	var h := _xy(pts.handL)
	var f := Vector2(cos(facing), sin(facing))
	var string_colour := C_E8E0C8
	if kind == "shield":
		var c := h + Vector2(f.x * 2 * k, f.y * 1 * k)
		var rim := Sketch.ellipse_points(c, 5.5 * k, 7 * k)
		Draw.ellipse(self, c, 5.5 * k, 7 * k, C_6E4A28)
		rim.append(rim[0])
		draw_polyline(rim, C_A6AEB7, 1.5 * k)
		Draw.circle(self, c, 1.5 * k, C_A6AEB7)
	elif kind == "bow":
		# Held upright. While aiming, the string is drawn back with the arrow
		# nocked (`pull` 0..1); just after a shot it shivers.
		var drawn := pull if aiming else 0.0
		var bend := 5 + drawn * 2 # the limbs flex as it's drawn
		var top := Vector2(h.x - f.x * drawn * 1.5 * k, h.y - (10 - drawn) * k)
		var bottom := Vector2(h.x - f.x * drawn * 1.5 * k, h.y + (8 - drawn) * k)
		var bulge := Vector2(h.x + f.x * bend * k, h.y - 1 * k + f.y * 2 * k)
		_round_line(_quad_curve(top, bulge, bottom), 1.8 * k, C_8B6236)
		var shiver := sin(kick * 40) * kick * 2 if kick > 0 else 0.0
		var drawback := drawn * 9 - shiver
		var nock := Vector2(h.x - f.x * drawback * k, h.y - 1 * k - f.y * drawback * 0.5 * k)
		draw_line(top, nock, string_colour, 0.8)
		draw_line(nock, bottom, string_colour, 0.8)
		if aiming and loaded and drawn > 0.1:
			var tip := Vector2(nock.x + f.x * 14 * k, nock.y + f.y * 6 * k)
			draw_line(nock, tip, C_8B6236, 1.2 * k)
			Draw.circle(self, tip, 1.2 * k, C_D8DDE2)
	elif kind == "crossbow":
		# Spanned by hauling the string back to the latch; the bolt goes on once
		# it's cocked
		_line(Vector2(h.x - f.x * 4 * k, h.y - f.y * 2 * k), Vector2(h.x + f.x * 9 * k, h.y + f.y * 4 * k), 3 * k, C_6E4A28)
		var p := Vector2(h.x + f.x * 7 * k, h.y + f.y * 3 * k)
		var cocked := pull if aiming else 1.0
		var s := Vector2(p.x - f.x * cocked * 6 * k, p.y - f.y * cocked * 3 * k)
		var tip_l := Vector2(p.x - f.y * 7 * k, p.y + f.x * 3 * k - 1)
		var tip_r := Vector2(p.x + f.y * 7 * k, p.y - f.x * 3 * k - 1)
		_round_line(_quad_curve(tip_l, Vector2(p.x + f.x * 2 * k, p.y + f.y * 1 * k), tip_r), 2 * k, C_B9C0C8)
		draw_line(tip_l, s, string_colour, 0.8)
		draw_line(s, tip_r, string_colour, 0.8)
		if loaded and cocked >= 1:
			draw_line(s, Vector2(p.x + f.x * 3 * k, p.y + f.y * 1.5 * k), C_5E3F22, 1.4 * k)
	elif kind == "sling":
		# Whirled round the hand, faster as the throw comes
		var r := (4 + pull * 3 if aiming else 0.0) * k
		var p := Vector2(h.x + cos(spin) * r, h.y + (sin(spin) * r * 0.5 - 6 * k if aiming else 6 * k))
		draw_line(h, p, C_C9B28A, 0.8)
		_ellipse(p, 2 * k, 1.6 * k, C_6E4A28)
		if loaded:
			Draw.circle(self, p, 1.2 * k, C_9A968C)


func _draw_shaft(pts: Dictionary, s: Dictionary) -> void:
	var p := _xy(pts[s.a]).lerp(_xy(pts[s.b]), s.t)
	var ang: float = facing + s.rel
	var dir := Vector2(cos(ang), sin(ang))
	# What shows is the back end, pointing back the way it came
	var length := (5.0 if s.kind == "bolt" else 8.0) * k
	var end := Vector2(p.x - dir.x * length, p.y - dir.y * length - s.tilt * length)
	_line(p, end, 1.2 * k, C_5E3F22 if s.kind == "bolt" else C_8B6236)
	var feather := C_5E3F22 if s.kind == "bolt" else C_E8E0C8
	var nrm := Vector2(-dir.y * 1.6 * k, dir.x * 0.8 * k)
	var back := end + dir * 2.5 * k
	_poly([end, back + nrm, back - nrm], feather)
