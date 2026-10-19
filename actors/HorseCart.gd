class_name HorseCart
extends RefCounted

# The player: a horse pulling a cart (port of cart.js). The horse is steered
# like a car; the cart trails behind on a hitch, so it cuts corners naturally.
# Drawn in three-quarter view: a walking, trotting, galloping horse, a cart
# with turning wheels, and the peasant on the driving bench.
#
# The horse, the cart and the shafts are separate nodes in the y-sorted layer,
# each positioned at the point it sorts by, so people can pass between them.

const MAX_SPEED := 150.0 # px/s on the road at a steady trot
const GALLOP_SPEED := 245.0 # px/s while boosting (Shift)
const MUD_SPEED := 55.0 # px/s off the road
const REVERSE_SPEED := 45.0
const ACCEL := 100.0
const GALLOP_ACCEL := 190.0
const BRAKE := 260.0
const DRAG := 25.0
const TURN_RATE := 1.9 # rad/s at walking pace
const HITCH_LENGTH := 46.0 # horse hitch point -> cart centre

# A dark bay, so it stands out against the dirt road
const HORSE := {
	"coat": Color("#5c3a22"),
	"shade": Color("#3d2516"),
	"light": Color("#7a4d2a"),
	"mane": Color("#1c1714"),
	"hoof": Color("#1c1714"),
	"tack": Color("#4a3220"),
}

# Leg timing for each gait, as phase offsets for [FL, FR, BL, BR]: a four-beat
# walk, a diagonal trot, a rolling gallop.
const GAITS := {
	"walk": [PI / 2, 3 * PI / 2, 0.0, PI],
	"trot": [0.0, PI, PI, 0.0],
	"gallop": [1.3, 1.8, 0.0, 0.45],
}

const CART := {
	"long": 20.0, # half length
	"wide": 14.0, # half width
	"floor": 12.0, # height of the bed
	"rim": 21.0, # height of the sides
	"wheel": 11.0, # wheel radius
	"wood": Color("#7a5230"),
	"inside": Color("#6e4a28"),
	"bed": Color("#8b6236"),
	"dark": Color("#4a3220"),
	"iron": Color("#3a2a1a"),
}


# Seen in three-quarter view like the people (see Rig): shapes are laid out in
# a frame facing `heading` (a forward, b to the right, z up) and drawn on the
# ground, lifted by their height. at() gives Vector3(x, y, depth): nearer the
# bottom of the screen is nearer the camera, and drawn later.
class View:
	var f: Vector2
	var l: Vector2

	func _init(heading: float) -> void:
		f = Vector2(cos(heading), sin(heading))
		l = Vector2(-f.y, f.x)

	func at(a: float, b: float, z := 0.0) -> Vector3:
		var x := f.x * a + l.x * b
		var y := f.y * a + l.y * b
		return Vector3(x, y - z, y)

	func xy(a: float, b: float, z := 0.0) -> Vector2:
		var p := at(a, b, z)
		return Vector2(p.x, p.y)


var x: float
var y: float
var heading: float
var cart_heading: float
var speed := 0.0
var stride := 0.0
var cart_x: float
var cart_y: float
var roll := 0.0 # how far the wheels have turned
var time := 0.0

var shafts: Painter
var cart: Node2D
var cart_back: Painter
var cart_front: Painter
var horse: Painter
var driver: Node2D # the seat the driver's rig sits on
var rig: Rig
var aim := 0.0 # where the driver is looking, relative to the cart


func _init(layer: Node2D, x_: float, y_: float, heading_: float) -> void:
	x = x_
	y = y_
	heading = heading_
	cart_heading = heading_
	cart_x = x - cos(heading) * (HITCH_LENGTH + 20)
	cart_y = y - sin(heading) * (HITCH_LENGTH + 20)

	shafts = Painter.new(_draw_shafts)
	cart = Node2D.new()
	cart_back = Painter.new(func(ci: CanvasItem) -> void: _draw_cart(ci, true))
	cart_front = Painter.new(func(ci: CanvasItem) -> void: _draw_cart(ci, false))
	# The driver on the bench: a seated peasant
	driver = Node2D.new()
	rig = Rig.new({"skin": "#d9b08c", "shirt": "#6b5b3e", "legs": "#4a3a2b", "head": "straw"})
	rig.seated = true
	rig.seat_z = CART.floor + 9
	driver.add_child(rig)
	cart.add_child(cart_back)
	cart.add_child(driver)
	cart.add_child(cart_front)
	horse = Painter.new(_draw_horse)
	layer.add_child(shafts)
	layer.add_child(cart)
	layer.add_child(horse)
	render()


func max_speed() -> float:
	return GALLOP_SPEED


# --- The driver's weapons (what Game uses, as for the peasant on foot) ---

func set_weapon(item: Variant) -> void:
	rig.weapon = Peasant.MELEE.get(item.icon) if item else null


func play(move: String, back := false, windup := 0.0) -> void:
	rig.play(move, back, windup)


func set_bow(item: Variant, loaded: bool) -> void:
	rig.offhand = Peasant.RANGED.get(item.icon) if item else null
	rig.loaded = loaded
	rig.aiming = rig.offhand != null
	rig.pull = 1.0 if loaded else 0.3


func fire() -> void:
	rig.loose()


# With nobody holding the reins (`parked`) the horse pulls up and waits.
# input: { up, down, left, right, boost }; obstacles: Vector3(x, y, radius).
func update(dt: float, input: Dictionary, on_road: bool, obstacles: Array = [], parked := false) -> void:
	# Galloping only helps on the road; in the mud the horse just flounders.
	var galloping: bool = input.get("boost", false) and on_road
	var limit := (GALLOP_SPEED if galloping else MAX_SPEED) if on_road else MUD_SPEED

	if parked:
		speed -= signf(speed) * minf(absf(speed), BRAKE * dt)
		input = {}
	elif input.get("up", false):
		# Speed up to the current limit; anything above it eases off below.
		if speed < limit:
			var accel := BRAKE if speed < 0 else (GALLOP_ACCEL if galloping else ACCEL)
			speed = minf(limit, speed + accel * dt)
	elif input.get("down", false):
		speed -= (BRAKE if speed > 0 else ACCEL * 0.5) * dt
	else:
		speed -= signf(speed) * minf(absf(speed), DRAG * dt)
	# Easing off from a gallop is gradual; hitting mud is not.
	var slowdown := 110.0 if on_road else 320.0
	if speed > limit:
		speed = maxf(limit, speed - slowdown * dt)
	speed = maxf(-REVERSE_SPEED, speed)

	# Steering needs movement, and gets a little heavier at a gallop.
	var pace := absf(speed)
	# A horse straining against the reins can still turn slowly when blocked.
	var throttle := int(input.get("up", false)) - int(input.get("down", false))
	var grip := minf(1.0, pace / 60.0) * (1.0 - 0.35 * minf(1.0, pace / GALLOP_SPEED))
	if throttle and grip < 0.35:
		grip = 0.35
	var direction := signf(speed) if pace > 5 else float(throttle)
	var steer := int(input.get("right", false)) - int(input.get("left", false))
	heading += steer * TURN_RATE * grip * direction * dt

	var step := speed * dt
	x += cos(heading) * step
	y += sin(heading) * step
	stride += step

	# Cart follows the hitch point behind the horse.
	var old := Vector2(cart_x, cart_y)
	var hitch := Vector2(x - cos(heading) * 20, y - sin(heading) * 20)
	var d := hitch - old
	var length := d.length()
	if length == 0.0:
		length = 1.0
	cart_x = hitch.x - d.x / length * HITCH_LENGTH
	cart_y = hitch.y - d.y / length * HITCH_LENGTH
	cart_heading = atan2(d.y, d.x)
	roll += Vector2(cart_x, cart_y).distance_to(old) / 11.0 * (signf(speed) if speed != 0 else 1.0)

	collide(obstacles)
	render(dt)


# Circles covering the horse's body, its head, and the cart: Vector3(x, y, r).
func bodies() -> Array[Vector3]:
	var h := Vector2(cos(heading), sin(heading))
	return [
		Vector3(x, y, 13),
		Vector3(x + h.x * 28, y + h.y * 28, 7),
		Vector3(cart_x, cart_y, 23),
	]


# Push the whole rig out of any obstacle it overlaps, and bleed off the part
# of its speed that drives into the obstacle so it can slide along.
func collide(obstacles: Array) -> void:
	var h := Vector2(cos(heading), sin(heading))
	var all := bodies()
	for ob: Vector3 in obstacles:
		for b in all:
			var d := Vector2(b.x - ob.x, b.y - ob.y)
			var dist := d.length()
			if dist == 0.0:
				dist = 1.0
			var overlap := ob.z + b.z - dist
			if overlap <= 0:
				continue
			var n := d / dist
			for k in all.size():
				all[k] += Vector3(n.x, n.y, 0) * overlap
			x += n.x * overlap
			y += n.y * overlap
			cart_x += n.x * overlap
			cart_y += n.y * overlap
			var into := h.dot(n) * signf(speed)
			if into < 0:
				speed *= 1 + into * 0.9


func render(dt := 0.0) -> void:
	time += dt
	horse.position = Vector2(x, y)
	horse.queue_redraw()
	cart.position = Vector2(cart_x, cart_y)
	cart_back.queue_redraw()
	cart_front.queue_redraw()
	driver.position = View.new(cart_heading).xy(12, 0)
	rig.update(dt, cart_heading + aim, 0)
	# Nearer the bottom of the screen draws in front
	shafts.position = Vector2((x + cart_x) / 2, (y + cart_y) / 2)
	shafts.queue_redraw()


# --- The horse ------------------------------------------------------------------

func _draw_horse(ci: CanvasItem) -> void:
	var P := View.new(heading)
	var pace := absf(speed)
	var gait := "gallop" if pace > 170 else "trot" if pace > 70 else "walk"
	var moving := minf(1.0, pace / 30.0)
	var reach := (7.0 if gait == "gallop" else 5.5 if gait == "trot" else 4.0) * moving
	var lift := (6.0 if gait == "gallop" else 4.0) * moving
	var phase := stride / (9.0 if gait == "gallop" else 7.0)
	var bob := absf(sin(phase)) * (0.6 if gait == "walk" else 1.4) * moving
	var pitch := sin(phase) * 1.5 if gait == "gallop" else 0.0 # rocking at a gallop
	var near := P.at(0, 1).z # > 0 when the horse's right side faces us

	# Ground shadow
	var shadow := PackedVector2Array()
	for n in 16:
		var t := n * PI / 8
		shadow.append(P.xy(cos(t) * 20, sin(t) * 6))
	Sketch.fill(ci, shadow, Color(0, 0, 0, 0.22))

	var parts := []
	var legs := [[10.0, -3.6, -1.0], [10.0, 3.6, -1.0], [-11.0, -3.6, 1.0], [-11.0, 3.6, 1.0]]
	for i in 4:
		var a0: float = legs[i][0]
		var b: float = legs[i][1]
		var ph: float = phase + GAITS[gait][i]
		var top := Vector3(a0, b, 19 + bob + (pitch if a0 > 0 else -pitch))
		var foot := Vector3(a0 + sin(ph) * reach, b, maxf(0.0, cos(ph)) * lift)
		var knee := Rig.joint(top, foot, 10.5, 10.5, legs[i][2])
		var t := P.at(top.x, top.y, top.z)
		var k := P.at(knee.x, knee.y, knee.z)
		var f := P.at(foot.x, foot.y, foot.z)
		var upper: Color = HORSE.coat if b * near > 0 else HORSE.shade
		parts.append([(t.z + f.z) / 2, func() -> void:
			Sketch.round_line(ci, PackedVector2Array([Vector2(t.x, t.y), Vector2(k.x, k.y)]), 4, upper)
			Sketch.round_line(ci, PackedVector2Array([Vector2(k.x, k.y), Vector2(f.x, f.y)]), 2.4, HORSE.shade)
			ci.draw_circle(Vector2(f.x, f.y), 1.9, HORSE.hoof)])

	var z := 21 + bob
	var rump := P.at(-14, 0, z + 1 - pitch)
	var chest := P.at(11, 0, z + pitch)
	var withers := P.at(9, 0, z + 4 + pitch)
	var poll := P.at(18, 0, z + 14 + pitch * 1.5)
	var muzzle := P.at(25, 0, z + 7 + pitch * 1.5)
	var tail_end := P.xy(-19 + sin(time * 3) * 1.5, sin(time * 2.3) * 2, 11)
	var xy := func(p: Vector3) -> Vector2: return Vector2(p.x, p.y)
	var body := func() -> void:
		var r: Vector2 = xy.call(rump)
		var c: Vector2 = xy.call(chest)
		Sketch.round_line(ci, PackedVector2Array([r, c]), 13, HORSE.coat)
		# Back lit, belly shaded
		ci.draw_line(r - Vector2(0, 4), c - Vector2(0, 4), Color(HORSE.light, 0.7), 3)
		ci.draw_line(r + Vector2(0, 4), c + Vector2(0, 4), Color(HORSE.shade, 0.7), 3)
		# Collar and the harness strap round the girth
		ci.draw_arc(P.xy(10.5, 0, z + 4 + pitch), 5.5, 0, TAU, 16, HORSE.tack, 2.5)
		var girth := P.xy(-2, 0, z)
		ci.draw_line(girth - Vector2(0, 6), girth + Vector2(0, 6), HORSE.tack, 2.5)
	var head := func() -> void:
		var w: Vector2 = xy.call(withers)
		var p: Vector2 = xy.call(poll)
		var m: Vector2 = xy.call(muzzle)
		Sketch.round_line(ci, PackedVector2Array([w, p]), 7, HORSE.coat)
		Sketch.round_line(ci, PackedVector2Array([w - Vector2(0, 3), p - Vector2(0, 3)]), 2.5, HORSE.mane)
		Sketch.round_line(ci, PackedVector2Array([p, m]), 5.5, HORSE.coat)
		ci.draw_circle(m, 2.6, HORSE.shade)
		var ear := P.xy(17, 0, z + 18 + pitch * 1.5)
		Sketch.fill(ci, PackedVector2Array([p + Vector2(-1.5, -1), ear, p + Vector2(1.5, -1)]), HORSE.shade)
		ci.draw_circle(P.xy(20, 1.6 if near > 0 else -1.6, z + 12 + pitch * 1.5), 0.9, Color("#0e0b0a"))
		# Bridle
		ci.draw_line(p, m, Color(HORSE.tack, 0.9), 1)
	var tail := func() -> void:
		var r: Vector2 = xy.call(rump)
		Sketch.round_line(ci, Sketch.quad_curve(r, Vector2(r.x + (tail_end.x - r.x) * 0.3, r.y), tail_end), 3.2, HORSE.mane)
	parts.append([0.0, body])
	parts.append([maxf(withers.z, poll.z) + 0.5, head])
	parts.append([rump.z - 0.5, tail])
	parts.sort_custom(func(p, q): return p[0] < q[0])
	for p in parts:
		p[1].call()


# --- The cart -------------------------------------------------------------------

# One wheel standing up at (a, b), turned by `roll`.
func _draw_wheel(ci: CanvasItem, P: View, a: float, b: float) -> void:
	var r: float = CART.wheel
	var rim := PackedVector2Array()
	for n in 21:
		var t := n * PI / 10
		rim.append(P.xy(a + cos(t) * r, b, CART.wheel + sin(t) * r))
	var hub := P.xy(a, b, CART.wheel)
	for s in 6:
		var t := roll + s / 6.0 * TAU
		ci.draw_line(hub, P.xy(a + cos(t) * r, b, CART.wheel + sin(t) * r), Color("#5e3f22"), 1.5)
	# As separate segments: seen edge-on the rim doubles back on itself, and a
	# polyline's joints balloon at those turns
	var segments := PackedVector2Array()
	for n in rim.size() - 1:
		segments.append(rim[n])
		segments.append(rim[n + 1])
	ci.draw_multiline(segments, CART.iron, 2.5)
	ci.draw_circle(hub, 2, CART.iron)


# The cart is split around the driver: wheels, walls and cargo behind them
# (`behind`), then the walls and wheel in front.
func _draw_cart(ci: CanvasItem, behind: bool) -> void:
	var P := View.new(cart_heading)
	var long: float = CART.long
	var wide: float = CART.wide
	var floor_z: float = CART.floor
	var rim: float = CART.rim
	var near_side := 1.0 if P.at(0, 1).z > 0 else -1.0 # which side faces the camera
	var near_end := 1.0 if P.at(1, 0).z > 0 else -1.0 # front or back end towards us

	var quad := func(pts: Array, colour: Color) -> void:
		var out := PackedVector2Array()
		for p in pts:
			out.append(P.xy(p.x, p.y, p.z))
		Sketch.fill(ci, out, colour)
	# Walls as quads: corners along the bottom, raised to the rim
	var wall := func(c: Array, colour: Color) -> void:
		quad.call([Vector3(c[0], c[1], floor_z), Vector3(c[2], c[3], floor_z), Vector3(c[2], c[3], rim), Vector3(c[0], c[1], rim)], colour)
		Sketch.round_line(ci, PackedVector2Array([P.xy(c[0], c[1], rim), P.xy(c[2], c[3], rim)]), 2, CART.dark)
		var mid := (floor_z + rim) / 2
		ci.draw_line(P.xy(c[0], c[1], mid), P.xy(c[2], c[3], mid), Color(CART.dark, 0.6), 1)
	var walls := {
		"left": [long, -wide, -long, -wide],
		"right": [-long, wide, long, wide],
		"front": [long, wide, long, -wide],
		"back": [-long, -wide, -long, wide],
	}

	if behind:
		# Shadow, the far wheel, the far walls' inner faces, the bed, cargo, the bench
		quad.call([Vector3(long + 2, wide + 3, 0), Vector3(-long - 2, wide + 3, 0), Vector3(-long - 2, -wide - 3, 0), Vector3(long + 2, -wide - 3, 0)], Color(0, 0, 0, 0.22))
		_draw_wheel(ci, P, -2, -near_side * (wide + 2))
		wall.call(walls["left" if near_side > 0 else "right"], CART.inside)
		wall.call(walls["back" if near_end > 0 else "front"], CART.inside)
		quad.call([Vector3(long, wide, floor_z), Vector3(-long, wide, floor_z), Vector3(-long, -wide, floor_z), Vector3(long, -wide, floor_z)], CART.bed)
		var a := -long + 6
		while a < long:
			ci.draw_line(P.xy(a, -wide, floor_z), P.xy(a, wide, floor_z), CART.inside, 1)
			a += 7
		# Cargo: a heap of hay and two sacks
		var hay := P.xy(-9, -3, floor_z + 5)
		ci.draw_colored_polygon(Sketch.ellipse_points(hay, 10, 7), Color("#d9b44a"))
		ci.draw_colored_polygon(Sketch.ellipse_points(hay - Vector2(2, 2), 5, 3.5), Color("#e6c766"))
		for s in [Vector2(-12, 8), Vector2(-3, -9)]:
			var sack := P.xy(s.x, s.y, floor_z + 4)
			ci.draw_colored_polygon(Sketch.ellipse_points(sack, 5, 4.5), Color("#c9b28a"))
			ci.draw_colored_polygon(Sketch.ellipse_points(sack - Vector2(1, 1.5), 2, 1.5), Color("#d6c49c"))
		# The driver's bench
		quad.call([Vector3(15, -wide + 1, floor_z + 8), Vector3(9, -wide + 1, floor_z + 8), Vector3(9, wide - 1, floor_z + 8), Vector3(15, wide - 1, floor_z + 8)], CART.dark)
	else:
		# In front: the near walls' outer faces and the near wheel
		wall.call(walls["right" if near_side > 0 else "left"], CART.wood)
		wall.call(walls["front" if near_end > 0 else "back"], CART.wood)
		_draw_wheel(ci, P, -2, near_side * (wide + 2))


# Shafts from the cart to the horse's flanks, and the reins. Drawn relative to
# the shafts node, which sits halfway between horse and cart.
func _draw_shafts(ci: CanvasItem) -> void:
	var origin := Vector2((x + cart_x) / 2, (y + cart_y) / 2)
	var cart_at := Vector2(cart_x, cart_y) - origin
	var horse_at := Vector2(x, y) - origin
	var P := View.new(cart_heading)
	var H := View.new(heading)
	for side in [-1.0, 1.0]:
		Sketch.round_line(ci, PackedVector2Array([cart_at + P.xy(CART.long, side * 11, 15), horse_at + H.xy(-3, side * 6.5, 19)]), 2.5, Color("#5a3a1a"))
	if driver.visible:
		for side in [-1.0, 1.0]:
			ci.draw_line(cart_at + P.xy(19, side * 3, CART.floor + 15), horse_at + H.xy(22, side * 1.5, 30), Color("#2a180c"), 0.8)
