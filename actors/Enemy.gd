class_name Enemy
extends Node2D

# A raider (port of the Enemy class in enemies.js). It belongs to a home (camp
# or roadblock), idles there until alerted, chases the cart, and gives up once
# dragged too far from home. It's drawn as a jointed figure (see Rig) that
# walks, swings its weapon from the shoulder, flinches when hit and falls as a
# ragdoll. The node sits where the raider stands.

# `leash` is how far from home they'll chase a cart before giving up; a
# peasant on foot they chase forever.
const TYPES := {
	"goblin": {"hp": 2, "speed": 165.0, "radius": 10.0, "health_bar": true, "leash": 1300.0},
	"bandit": {"hp": 2, "speed": 125.0, "radius": 13.0, "health_bar": false, "leash": 1500.0},
	"captain": {"hp": 4, "speed": 115.0, "radius": 15.0, "health_bar": true, "leash": 1700.0},
	# Archers hang back at `keep` distance and shoot from up to `range`.
	"archer": {"hp": 2, "speed": 120.0, "radius": 12.0, "health_bar": false, "leash": 1500.0, "faction": "bandit",
		"shoots": {"range": 620.0, "keep": 430.0, "speed": 480.0, "aim": 0.75, "step": 80.0}},
	"goblinArcher": {"hp": 2, "speed": 150.0, "radius": 10.0, "health_bar": true, "leash": 1300.0, "faction": "goblin",
		"shoots": {"range": 540.0, "keep": 370.0, "speed": 450.0, "aim": 0.6, "step": 70.0}},
	# Heavies, found in the big camps down side roads. `armour` is taken off
	# every hit they take (always at least 1 gets through); `heavy` adds to the
	# damage they deal.
	"orc": {"hp": 7, "speed": 118.0, "radius": 17.0, "health_bar": true, "leash": 1500.0, "heavy": 1, "faction": "goblin"},
	"brute": {"hp": 6, "speed": 100.0, "radius": 15.0, "health_bar": true, "leash": 1600.0, "heavy": 1, "armour": 1, "faction": "bandit"},
}

# How each raider looks: build, clothes, head and what they carry.
const LOOKS := {
	"goblin": {"scale": 0.75, "skin": "#6fa83a", "shirt": "#5b4a2a", "legs": "#4a3a22", "head": "goblin", "weapon": "dagger"},
	"goblinArcher": {"scale": 0.75, "skin": "#6fa83a", "shirt": "#4a3a22", "legs": "#3d2f1e", "head": "goblin", "offhand": "bow", "extras": ["quiver"]},
	"bandit": {"scale": 1.0, "skin": "#c9a27a", "shirt": "#4a3b30", "legs": "#3a2f26", "head": "hood", "head_colour": "#2d2a26", "mask": "#8c2f22", "weapon": "club"},
	"archer": {"scale": 1.0, "skin": "#c9a27a", "shirt": "#4a5230", "legs": "#3a3f26", "head": "hood", "head_colour": "#3d4a2a", "offhand": "bow", "extras": ["quiver"]},
	"captain": {"scale": 1.12, "skin": "#c9a27a", "shirt": "#3d2e26", "legs": "#2a1f14", "head": "hat", "head_colour": "#2a1f14", "weapon": "sword", "extras": ["cape"], "cape_colour": "#7a1f1a"},
	"brute": {"scale": 1.1, "skin": "#c9a27a", "shirt": "#7d8590", "legs": "#575f6b", "boots": "#3c424d", "head": "helm", "weapon": "mace", "offhand": "shield"},
	"orc": {"scale": 1.35, "skin": "#5f7a4a", "shirt": "#4a3a2a", "legs": "#3d2f25", "head": "orc", "weapon": "cleaver"},
}

const BAR_WIDTH := 22.0
const BAR_HEIGHT := 4.0
const ALERT_TIME := 1.2

# How each raider fights hand to hand: the `windup` (the weapon drawn back:
# your chance to get clear), the `swing` (when it can actually hit), and the
# `cooldown` between attacks. Damage only counts if the drawn weapon (or fist)
# actually passes through you during the swing.
const ATTACKS := {
	"goblin": {"windup": 0.25, "swing": 0.13, "cooldown": 0.9}, # dagger stab
	"bandit": {"windup": 0.35, "swing": 0.17, "cooldown": 1.2}, # club
	"captain": {"windup": 0.3, "swing": 0.15, "cooldown": 1.0}, # sword
	"orc": {"windup": 0.55, "swing": 0.22, "cooldown": 1.6}, # cleaver
	"brute": {"windup": 0.45, "swing": 0.2, "cooldown": 1.4}, # mace
	"archer": {"windup": 0.3, "swing": 0.14, "cooldown": 1.1}, # a punch
	"goblinArcher": {"windup": 0.25, "swing": 0.13, "cooldown": 1.0},
}
const RECOVER := 0.2 # seconds to bring the arm back
# Archers fight hand to hand inside this distance (from their edge), and go
# back to the bow once you're beyond MELEE_LEAVE.
const MELEE_ENTER := 34.0
const MELEE_LEAVE := 80.0
const RECOVER_TIME := 0.35 # pause after loosing an arrow

var type: String
var hp: int
var max_hp: int
var speed: float
var radius: float
var health_bar: bool
var leash: float
var faction: String
var shoots: Variant = null # { range, keep, speed, aim, step }
var heavy := 0
var armour := 0
var damage: int
var elite: bool
var gold: int
var home: Dictionary # { x, y, facing, wander?: { x, y, min, max }, hidden? }
var state := "idle" # idle, chase, return
var vx := 0.0
var vy := 0.0
var wander_target: Variant = null
var wander_timer: float
var attack_cooldown := 0.0
var flash := 0.0
var alert := 0.0
var dying := 0.0
var provoked := false
var in_hiding: bool # lying in wait, unseen and unhittable
var facing: float
var last_hit := {"x": 0.0, "y": 0.0, "force": 1.0}
var archery: Variant = null # { mode, timer, to }
var attack: Dictionary
var blow: Variant = null # { phase: windup | swing | recover, t, landed }
var wants_shot := false
var removed := false # cleared away (its camp left far behind)
var slide_side := 0

var rig: Rig
var figure: Node2D
var bar: Painter
var marker: Sketch
var pool: Sketch
var aura: Sketch # an elite's ring
var fallen_layer: Node2D # where the body goes when it falls (under the living)


# `threat` (see Threat.threat_at) toughens raiders the further along the road
# they're found; some turn up as elites.
func _init(type_: String, x: float, y: float, home_: Dictionary, threat: Variant = null, fallen_layer_: Node2D = null) -> void:
	var t: Dictionary = TYPES[type_]
	type = type_
	position = Vector2(x, y)
	hp = t.hp
	radius = t.radius
	health_bar = t.health_bar
	leash = t.leash
	shoots = t.get("shoots")
	heavy = t.get("heavy", 0)
	armour = t.get("armour", 0)
	speed = t.speed * randf_range(0.85, 1.1) * (threat.speed_mult if threat else 1.0)
	hp += threat.hp_bonus if threat else 0
	damage = (threat.damage if threat else 1) + heavy
	faction = t.get("faction", "goblin" if type == "goblin" else "bandit")
	elite = randf() < (threat.elite_chance if threat else 0.0)
	if elite:
		hp = ceili(hp * 1.8)
		radius = roundf(radius * 1.2)
		health_bar = true
	gold = (3 if elite else 1) + (2 if heavy else 0)
	max_hp = hp
	home = home_
	wander_timer = randf_range(0, 3)
	in_hiding = home.get("hidden", false)
	facing = home.get("facing", PI / 2)
	fallen_layer = fallen_layer_

	var look: Dictionary = LOOKS[type].duplicate()
	look.scale = look.scale * (1.15 if elite else 1.0)
	rig = Rig.new(look)
	rig.facing = facing

	# The figure, and markers above its head (an elite's ring at its feet)
	if elite:
		# A smouldering red ring at their feet marks out the tough ones.
		aura = Sketch.new()
		aura.ellipse(Vector2.ZERO, radius + 5, (radius + 5) * 0.5, Color("#c0392b", 0.2))
		aura.ellipse_stroke(Vector2.ZERO, radius + 5, (radius + 5) * 0.5, 2, Color("#e8b923", 0.8))
		add_child(aura)
	figure = Node2D.new()
	figure.add_child(rig)
	var top := -rig.height()
	bar = Painter.new(_draw_bar)
	bar.position.y = top - 8
	bar.visible = health_bar
	marker = Sketch.new()
	marker.poly(Sketch.round_rect_points(-2, -14, 4, 9, 1.5), Color("#e0463a"))
	marker.circle(Vector2(0, -1.5), 2.2, Color("#e0463a"))
	marker.position.y = top - 12
	marker.visible = false
	if shoots:
		archery = {"mode": "decide", "timer": 0.0}
	attack = ATTACKS[type]
	add_child(figure)
	add_child(bar)
	add_child(marker)


func alive() -> bool:
	return hp > 0


func _draw_bar(ci: CanvasItem) -> void:
	var fill := maxf(0.0, float(hp) / max_hp)
	ci.draw_rect(Rect2(-BAR_WIDTH / 2 - 1, -1, BAR_WIDTH + 2, BAR_HEIGHT + 2), Color("#1a1008", 0.8))
	ci.draw_rect(Rect2(-BAR_WIDTH / 2, 0, BAR_WIDTH * fill, BAR_HEIGHT), Color("#7ccf3a") if fill > 0.5 else Color("#e0463a"))


func engage() -> void:
	if not alive() or state == "chase":
		return
	if state == "idle":
		alert = ALERT_TIME
	state = "chase"
	if archery:
		archery.mode = "decide"
	if in_hiding:
		# Burst out of hiding toward the road.
		in_hiding = false
		var f: float = home.get("facing", 0.0)
		vx = cos(f) * 220
		vy = sin(f) * 220


# `target` is who they're after ({ x, y, vx, vy }); `relentless` means they
# won't give up the chase however far it leads them; `victims` are the bodies
# their weapons can hurt (Vector3(x, y, r)).
func update(dt: float, target: Dictionary, relentless: bool, victims: Array = []) -> void:
	attack_cooldown -= dt
	flash -= dt
	alert -= dt
	# Aim a little ahead of the target so chasers try to cut it off.
	var tx: float = target.x + target.vx * 0.4
	var ty: float = target.y + target.vy * 0.4

	if not alive():
		if not dying:
			_fall()
		dying += dt
		pool.scale = Vector2.ONE * minf(1.0, dying / 1.5)
		# The blood gathers under the body wherever it came to rest
		var parts: Dictionary = rig.ragdoll.parts
		var hips: Vector3 = (parts.hipL.p + parts.hipR.p) / 2
		pool.position = Vector2(hips.x, hips.y)
	elif state == "chase":
		if not relentless and position.distance_to(Vector2(home.x, home.y)) > leash:
			state = "return"
		# Nobody follows you into a town
		for z: Vector3 in Enemies.safe_zones:
			if Vector2(target.x, target.y).distance_to(Vector2(z.x, z.y)) < z.z + 40:
				state = "return"
		# Archers only use their fists in a brawl
		var brawling: bool = not shoots or archery.mode == "melee"
		if blow:
			_fight_on(dt, target, victims)
		elif shoots:
			_skirmish(dt, target, tx, ty)
		else:
			seek(dt, tx, ty, speed)
		if brawling and not blow and attack_cooldown <= 0 and _in_reach(victims):
			_start_blow(target)
	elif state == "return":
		if blow:
			drop_blow()
		var d := seek(dt, home.x, home.y, speed * 0.6)
		if d < 12:
			state = "idle"
	else:
		_idle(dt)

	rig.aiming = alive() and state == "chase" and archery != null and archery.mode == "aim"
	if archery:
		# Drawing the bow slowly through the aim: the shot comes at full draw
		rig.pull = clampf(1 - archery.timer / shoots.aim, 0, 1) if archery.mode == "aim" else 0.0
		rig.loaded = archery.mode == "aim"
	rig.update(dt, facing, Vector2(vx, vy).length())
	visible = not in_hiding
	if alive():
		figure.modulate = Color("#ff7766") if flash > 0 else Color.WHITE
	marker.visible = alive() and alert > 0
	marker.scale = Vector2.ONE * (1 + maxf(0.0, alert - ALERT_TIME + 0.2) * 3)


# --- Melee ------------------------------------------------------------------

# How far the weapon (or fist) can reach from the middle of the body.
func reach() -> float:
	var B := Rig.BODY
	return ((B.upper_arm + B.fore_arm) * 0.85 + B.shoulder_w + Rig.WEAPON_LENGTH.get(rig.weapon, 3.0)) * rig.k


# Close enough that the weapon would reach one of the victims?
func _in_reach(victims: Array) -> bool:
	for v: Vector3 in victims:
		if Vector2(v.x, v.y).distance_to(position) < reach() + v.z - 2:
			return true
	return false


func _start_blow(target: Dictionary) -> void:
	blow = {"phase": "windup", "t": 0.0, "landed": false}
	facing = atan2(target.y - position.y, target.x - position.x)


# One attack: draw the weapon back (still turning to track you), swing it
# through (committed), then recover. Damage only if the weapon itself passes
# through a victim during the swing.
func _fight_on(dt: float, target: Dictionary, victims: Array) -> void:
	blow.t += dt
	# Barely moving while attacking
	seek(dt, target.x, target.y, speed * 0.2, false, true)
	if blow.phase == "windup":
		facing = atan2(target.y - position.y, target.x - position.x)
		rig.set_strike("windup", minf(1.0, blow.t / attack.windup))
		if blow.t >= attack.windup:
			blow.phase = "swing"
			blow.t = 0.0
	elif blow.phase == "swing":
		var p := minf(1.0, blow.t / attack.swing)
		rig.set_strike("swing", p)
		if not blow.landed and _weapon_hits(victims):
			blow.landed = true
		if p >= 1:
			blow.phase = "recover"
			blow.t = 0.0
	else:
		rig.set_strike("recover", minf(1.0, blow.t / RECOVER))
		if blow.t >= RECOVER:
			drop_blow()
			attack_cooldown = attack.cooldown * (0.85 + randf() * 0.3)


# Does the weapon, as drawn right now, pass through a victim?
func _weapon_hits(victims: Array) -> bool:
	for p in rig.weapon_points():
		for v: Vector3 in victims:
			if Vector2(v.x, v.y).distance_to(position + p) < v.z + 3:
				return true
	return false


# Interrupted (killed, or giving up the chase): put the weapon down.
func drop_blow() -> void:
	blow = null
	rig.set_strike(null)


# An archer's fight, one step at a time:
#   advance – walk in until within bow range
#   aim     – stand still, arrow nocked, for `aim` seconds, then loose
#   recover – a short pause after the shot
#   step    – if you're too close, back off one `step` (slightly to the side)
#             and stop again, so you can close the gap
#   melee   – if you get right up to them, drop the bow and fight
# They never shoot on the move. Sets `wants_shot` when an arrow is loosed.
func _skirmish(dt: float, target: Dictionary, tx: float, ty: float) -> void:
	var a: Dictionary = archery
	var d := Vector2(target.x, target.y) - position
	var dist := d.length()
	if dist == 0.0:
		dist = 1.0
	var gap := dist - radius
	a.timer -= dt

	if gap < MELEE_ENTER:
		a.mode = "melee"
	if a.mode == "melee" and gap > MELEE_LEAVE:
		a.mode = "decide"
	if a.mode == "decide":
		a.mode = "advance" if dist > shoots.range * 0.85 else "aim"
		a.timer = shoots.aim

	match a.mode:
		"melee":
			seek(dt, tx, ty, speed)
		"advance":
			seek(dt, tx, ty, speed)
			if dist <= shoots.range * 0.75:
				a.mode = "aim"
				a.timer = shoots.aim
		"aim":
			seek(dt, position.x, position.y, 0, true)
			facing = d.angle()
			if a.timer <= 0:
				vx = 0.0 # planted feet for the shot
				vy = 0.0
				wants_shot = true
				rig.loose()
				a.mode = "recover"
				a.timer = RECOVER_TIME
		"recover":
			seek(dt, position.x, position.y, 0, true)
			facing = d.angle()
			if a.timer > 0:
				return
			if dist < shoots.keep:
				# One measured step back, angled off to one side
				var away := (-d).angle() + (-1.0 if randf() < 0.5 else 1.0) * (0.3 + randf() * 0.4)
				a.to = position + Vector2(cos(away), sin(away)) * shoots.step
				a.mode = "step"
				a.timer = 1.5 # give up on the step if something's in the way
			else:
				a.mode = "decide"
		"step":
			if seek(dt, a.to.x, a.to.y, speed * 0.85, true) < 8 or a.timer <= 0:
				a.mode = "aim"
				a.timer = shoots.aim


func _idle(dt: float) -> void:
	var w: Variant = home.get("wander")
	if not w:
		seek(dt, home.x, home.y, 40, true)
		return
	# Mill about the camp, facing its centre when standing still.
	wander_timer -= dt
	if wander_timer <= 0:
		var a := randf() * TAU
		var r := randf_range(w.min, w.max)
		wander_target = Vector2(w.x + cos(a) * r, w.y + sin(a) * r)
		wander_timer = randf_range(2.5, 6)
	var t: Vector2 = wander_target if wander_target != null else position
	if seek(dt, t.x, t.y, 35, true) < 6:
		facing = atan2(w.y - position.y, w.x - position.x)


# Accelerate toward a point; returns the remaining distance. Turns to face the
# way it's going (unless `keep_facing`).
func seek(dt: float, tx: float, ty: float, top: float, arrive := false, keep_facing := false) -> float:
	var d := Vector2(tx, ty) - position
	var dist := d.length()
	if dist == 0.0:
		dist = 1.0
	var want := 0.0 if arrive and dist < 6 else top
	var k := 1.0 - exp(-dt * 5)
	vx += (d.x / dist * want - vx) * k
	vy += (d.y / dist * want - vy) * k
	position += Vector2(vx, vy) * dt
	if not keep_facing:
		var moving := Vector2(vx, vy).length()
		if moving > 8:
			facing = atan2(vy, vx)
		elif not home.has("wander") and state == "idle":
			facing = home.get("facing", facing)
	return dist


# Go down: the body goes limp and falls as a ragdoll, flung by the blow that
# killed it, darkening, in a slowly spreading pool of blood.
func _fall() -> void:
	rig.die(last_hit.x, last_hit.y, last_hit.force)
	vx = 0.0
	vy = 0.0
	figure.modulate = Color("#8a7e72")
	pool = Sketch.new()
	pool.ellipse(Vector2.ZERO, radius * 1.3, radius * 0.7, Color("#4a1514", 0.85))
	pool.ellipse(Vector2(radius * 0.4, radius * 0.1), radius * 0.6, radius * 0.3, Color("#76201a", 0.6))
	pool.scale = Vector2.ZERO
	add_child(pool)
	move_child(pool, 0)
	in_hiding = false # killed in their hiding place: they tumble out
	drop_blow()
	bar.visible = false
	marker.visible = false
	# (The JS left an elite's ring where it fell, though the body may be flung
	# well clear of it)
	if aura:
		aura.visible = false
	# The dead lie under all the living
	if fallen_layer:
		reparent(fallen_layer)


# `force` scales the knockback (a heavy axe blow sends them flying).
func hit(dir_x: float, dir_y: float, dmg := 1, force := 1.0) -> void:
	hp -= maxi(1, dmg - armour)
	provoked = true
	last_hit = {"x": dir_x, "y": dir_y, "force": force}
	bar.queue_redraw()
	if not alive():
		bar.visible = false
	flash = 0.15
	rig.hit_by()
	# Heavies barely budge.
	var shove := (90.0 if heavy else 260.0) * force
	vx = dir_x * shove
	vy = dir_y * shove
