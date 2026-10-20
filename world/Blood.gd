class_name Blood
extends RefCounted

# Blood (not in the JS original, which left a pool under the dead): little
# red droplets thrown out by a hit, flying along the blow and spattering on
# the ground, where they stay as dots and slowly fade. A shot gives a puff
# out of the far side; a killing slash, a spray along the cut.
#
# Plain data, all drawn by two nodes: droplets in the air over everything,
# and the spatter on the ground under the living.

const GRAVITY := 620.0
const STAIN_TIME := 25.0 # seconds a spatter lasts before it's gone
const MAX_STAINS := 2500 # the oldest go first
const COLOURS := [Color("#9a1414"), Color("#b01c1c"), Color("#7a0e0e")]
const STAIN := Color("#8c1212")
# Now and then a body, once down, spouts blood up from the neck in pulses,
# weaker each time, like a fountain running dry
const SPOUT_CHANCE := 0.4
const SPOUT_TIME := Vector2(1.6, 3.2) # seconds
const SPOUT_EVERY := 0.17 # seconds between pulses

static var current: Blood # the one in play (set by Game), for whoever draws blood

var drops: Array = [] # { pos: Vector2 (on the ground), z, vel: Vector3, r, colour }
var stains: Array = [] # { pos, r, t }
var spouts: Array = [] # { body: Enemy, t, length, next }
var _air: Painter
var _ground: Painter


func _init(ground_layer: Node2D, air_layer: Node2D) -> void:
	_ground = Painter.new(_draw_ground)
	ground_layer.add_child(_ground)
	_air = Painter.new(_draw_air)
	air_layer.add_child(_air)


# A hit at `at` (where they stand), struck along `dir`: a few droplets out of
# the far side at chest height. More if it killed.
func hit(at: Vector2, dir: Vector2, killed := false) -> void:
	var d := dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	for n in (randi_range(14, 20) if killed else randi_range(6, 10)):
		var a := d.angle() + randf_range(-0.6, 0.6)
		var speed := randf_range(50, 150)
		_drop(at + d * 3, randf_range(11, 17), Vector3(cos(a) * speed, sin(a) * speed, randf_range(10, 70)))


# A killing slash: a spray thrown along the cut (`sweep`, the way the blade
# was travelling) and away from the blow (`dir`).
func spray(at: Vector2, dir: Vector2, sweep: Vector2) -> void:
	var main := (dir.normalized() * 0.5 + sweep.normalized()).normalized()
	for n in randi_range(32, 44):
		var a := main.angle() + randf_range(-0.55, 0.55)
		var speed := randf_range(90, 260)
		_drop(at, randf_range(13, 20), Vector3(cos(a) * speed, sin(a) * speed, randf_range(30, 110)))
	hit(at, dir, true)


# A body that's just come down: maybe it spouts (see SPOUT_CHANCE).
func maybe_spout(body: Enemy) -> void:
	if randf() < SPOUT_CHANCE:
		spouts.append({"body": body, "t": 0.0, "length": randf_range(SPOUT_TIME.x, SPOUT_TIME.y), "next": 0.0,
			"lean": Vector2.from_angle(randf() * TAU) * randf_range(8, 30)})


func _drop(at: Vector2, z: float, vel: Vector3) -> void:
	drops.append({"pos": at, "z": z, "vel": vel, "r": randf_range(0.6, 1.3), "colour": COLOURS[randi() % COLOURS.size()]})


func update(dt: float) -> void:
	_update_spouts(dt)
	if not drops.is_empty():
		var landed := false
		for d in drops:
			d.vel.z -= GRAVITY * dt
			d.pos += Vector2(d.vel.x, d.vel.y) * dt
			d.z += d.vel.z * dt
			if d.z <= 0:
				# Spattered: a dot on the ground, smeared a little along its flight
				stains.append({"pos": d.pos, "r": d.r * randf_range(1.2, 1.7), "t": 0.0,
					"smear": Vector2(d.vel.x, d.vel.y).normalized() * minf(2.5, Vector2(d.vel.x, d.vel.y).length() / 70)})
				landed = true
		if landed:
			drops = drops.filter(func(d: Dictionary) -> bool: return d.z > 0)
			_ground.queue_redraw()
		_air.queue_redraw() # (the last frame of a burst clears it)
	# Old spatter fades away
	if not stains.is_empty():
		var faded := false
		for s in stains:
			s.t += dt
			faded = faded or s.t > STAIN_TIME
		if faded or stains.size() > MAX_STAINS:
			stains = stains.filter(func(s: Dictionary) -> bool: return s.t <= STAIN_TIME)
			if stains.size() > MAX_STAINS:
				stains = stains.slice(stains.size() - MAX_STAINS)
		# (fading shows a little at a time: redraw now and then, not every frame)
		if Engine.get_process_frames() % 20 == 0 or faded:
			_ground.queue_redraw()


func _update_spouts(dt: float) -> void:
	if spouts.is_empty():
		return
	for s in spouts:
		s.t += dt
		s.next -= dt
		var body: Variant = s.body
		if not is_instance_valid(body) or s.t > s.length or not body.rig.ragdoll:
			s.t = INF
			continue
		if s.next > 0:
			continue
		s.next = SPOUT_EVERY * randf_range(0.8, 1.3)
		# From the neck, straight up and a little to one side
		var neck: Vector3 = body.rig.ragdoll.parts.neck.p
		var at: Vector2 = body.position + Vector2(neck.x, neck.y)
		var strength: float = 1.0 - s.t / s.length * 0.8
		var lean: Vector2 = s.lean
		for n in randi_range(4, 7):
			var spread := Vector2.from_angle(randf() * TAU) * randf_range(0, 18)
			_drop(at, neck.z + 2, Vector3(lean.x + spread.x, lean.y + spread.y, randf_range(130, 230) * strength))
	spouts = spouts.filter(func(s: Dictionary) -> bool: return s.t <= s.length)


func _draw_air(ci: CanvasItem) -> void:
	for d in drops:
		Draw.circle(ci, d.pos - Vector2(0, d.z), d.r, d.colour)


func _draw_ground(ci: CanvasItem) -> void:
	for s in stains:
		var alpha := clampf((STAIN_TIME - s.t) / 5.0, 0, 1)
		var colour := Color(STAIN, alpha)
		Draw.circle(ci, s.pos, s.r, colour)
		if s.smear != Vector2.ZERO:
			Draw.circle(ci, s.pos + s.smear, s.r * 0.7, colour)
