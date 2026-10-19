class_name Structures
extends RefCounted

# Buildings and props in the three-quarter view, built from Iso (port of
# structures.js). Each is drawn standing at the origin (where it meets the
# ground) and returns its Sketch; the caller places it and sorts it by depth
# with the people. `angle` is the way it faces (its door or open side).

const WOOD := Color("#7a5230")
const WOOD_DARK := Color("#4a3220")
const STONE := Color("#8a857a")
const THATCH := Color("#a8822f")
const WALL := Color("#ddd0ad")


static func _v3(u: float, v: float, z: float, angle: float) -> Vector3:
	return Iso.turn(Vector3(u, v, z), angle)


# Footprint point, turned and projected to the screen.
static func _p(u: float, v: float, z: float, angle: float) -> Vector2:
	return Iso.project(Iso.turn(Vector3(u, v, z), angle))


# Turned footprint point on the ground (no height), as a 2D point.
static func _xy(u: float, v: float, angle: float) -> Vector2:
	var p := Iso.turn(Vector3(u, v, 0), angle)
	return Vector2(p.x, p.y)


static func _faces_way(dir: Vector2, angle: float, z := 0.0) -> bool:
	var d := _xy(dir.x, dir.y, angle)
	return Iso.faces_camera(Vector3(d.x, d.y, z))


# A flat decal (door, window, plank) on a wall: corners given as
# Vector2(along the wall, height) on the face whose outward direction is `out`.
static func _on_wall(g: Sketch, angle: float, out: Vector2, at: Vector2, corners: Array, colour: Color) -> void:
	if not _faces_way(out, angle):
		return
	var pts := PackedVector2Array()
	for c in corners:
		pts.append(_p(at.x - c.x * out.y, at.y + c.x * out.x, c.y, angle))
	g.poly(pts, colour)


# Four corners from s0..s1 along the wall, z0..z1 up it.
static func _quad(s0: float, z0: float, s1: float, z1: float) -> Array:
	return [Vector2(s0, z0), Vector2(s1, z0), Vector2(s1, z1), Vector2(s0, z1)]


# --- Homes ---------------------------------------------------------------------

# A thatched cottage: lime-washed walls framed in timber, a door and windows on
# the front, a stone chimney. `charred`: the thatch is burnt through in places.
# Returns { g, roof, eaves }.
static func cottage(angle: float, charred := false, deep := 54.0, front := 84.0, walls := 30.0) -> Dictionary:
	var g := Sketch.new()
	var rise := 26.0
	Iso.ground_shadow(g, front * 0.62, deep * 0.45, 0.25, 0.35)
	Iso.draw_solid(g, Iso.box(deep, front, walls, angle, WALL))
	var out := Vector2(1, 0)
	var at := Vector2(deep / 2 + 0.3, 0)
	# Timber frame: corner posts and a beam under the eaves
	for s in [-front / 2 + 1.5, front / 2 - 1.5]:
		_on_wall(g, angle, out, at, _quad(s - 1.5, 0, s + 1.5, walls), WOOD_DARK)
	_on_wall(g, angle, out, at, _quad(-front / 2, walls - 3, front / 2, walls), WOOD_DARK)
	# Door and windows on the front (+u); a window on each end
	_on_wall(g, angle, out, at, _quad(-7, 0, 7, 21), Color("#5a3a1e"))
	_on_wall(g, angle, out, at, _quad(-5.5, 0, 5.5, 19), Color("#3a2614"))
	for s in [-25.0, 25.0]:
		_on_wall(g, angle, out, at, _quad(s - 7, 11, s + 7, 22), WOOD_DARK)
		_on_wall(g, angle, out, at, _quad(s - 5.5, 12.5, s + 5.5, 20.5), Color("#24303a"))
	for end in [-1.0, 1.0]:
		var end_at := Vector2(0, end * (front / 2 + 0.3))
		_on_wall(g, angle, Vector2(0, end), end_at, _quad(-6, 11, 6, 21), WOOD_DARK)
		_on_wall(g, angle, Vector2(0, end), end_at, _quad(-4.5, 12.5, 4.5, 19.5), Color("#24303a"))
	# Chimney, then the thatch over the long side. (The chimney starts at the
	# eaves: from the ground, its front face showed through the end wall when
	# the cottage faced sideways, as it does in the JS.)
	var chimney := _v3(-deep / 5, front / 3, 0, angle)
	Iso.draw_solid(g, Iso.moved(Iso.box(9, 9, rise + 8, angle, STONE, walls, Color("#5a5650")), chimney))
	Iso.draw_solid(g, Iso.gable(front, deep, rise, angle + PI / 2, THATCH, walls, 4.0, WALL))
	# Straw courses along each roof face, and the ridge
	var ridge := angle + PI / 2
	var l := front / 2 + 4
	var w := deep / 2 + 4
	for side in [-1.0, 1.0]:
		if not _faces_way(Vector2(0, side * rise), ridge, w):
			continue
		for t in [0.3, 0.6]:
			var a := _p(-l, side * w * (1 - t), walls + rise * t, ridge)
			var b := _p(l, side * w * (1 - t), walls + rise * t, ridge)
			g.line(a, b, 1.0, _alpha(Iso.shade(THATCH, 0.75), 0.7))
	g.line(_p(-l, 0, walls + rise, ridge), _p(l, 0, walls + rise, ridge), 2.5, Color("#7a5a22"))
	if charred:
		for k in 6:
			var c := _p(randf_range(-l * 0.8, l * 0.8), randf_range(-w * 0.6, w * 0.6), walls + rise * randf_range(0.3, 0.8), ridge)
			var r := randf_range(4, 7)
			g.ellipse(c, r, r * 0.55, Color("#2a1f16", 0.75))
			g.ellipse(c - Vector2(r * 0.2, r * 0.1), r * 0.5, r * 0.3, Color("#14100c", 0.8))
	return {"g": g, "roof": walls + rise, "eaves": walls}


# A canvas lean-to: a sloping roof on four posts, open towards `angle`.
static func lean_to(angle: float, colour := Color("#c8b994")) -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 30, 16, 0.2)
	var poly := func(pts: Array, fill: Color) -> void:
		var out := PackedVector2Array()
		for p in pts:
			out.append(_p(p.x, p.y, p.z, angle))
		g.poly(out, fill)
	# The shade inside: the back wall seen from within, and a bedroll
	poly.call([Vector3(-14, -22, 0), Vector3(-14, 22, 0), Vector3(-14, 22, 8), Vector3(-14, -22, 8)], Iso.shade(colour, 0.45))
	g.ellipse(_p(-2, 4, 0, angle), 8, 4, Color("#7d4a3a"))
	# Canvas walls at each end (the far one first), then the posts
	var ends := [-22.0, 22.0]
	ends.sort_custom(func(p, q): return _p(0, p, 0, angle).y < _p(0, q, 0, angle).y)
	for v in ends:
		var lit := _faces_way(Vector2(0, signf(v)), angle)
		poly.call([Vector3(-14, v, 0), Vector3(14, v, 0), Vector3(14, v, 34), Vector3(-14, v, 8)], Iso.shade(colour, 0.9 if lit else 0.6))
	for post in [Vector3(14, -22, 34), Vector3(14, 22, 34)]:
		var base := _xy(post.x, post.y, angle)
		g.line(base, base - Vector2(0, post.z), 2.5, WOOD_DARK)
	# The sloping roof: tall at the open front, low at the back
	Iso.draw_solid(g, Iso.slope(52, 34, 34, 8, angle + PI / 2, colour))
	return g


# A goblin hide tent: a cone of stitched skins, the flap open towards `angle`.
static func hide_tent(angle: float) -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 26, 12, 0.22)
	Iso.draw_solid(g, Iso.cone(22, 42, Color("#8b7355"), 7, angle + 0.4))
	# The flap (if it faces us), poles poking out of the top
	if Iso.faces_camera(Vector3(cos(angle), sin(angle), 0.6)):
		g.poly(PackedVector2Array([_p(19, -7, 0, angle), _p(19, 7, 0, angle), _p(9, 0, 24, angle)]), Color("#2a1f14"))
	for a in [0.3, 2.4, 4.4]:
		g.line(Vector2(0, -40), Vector2(cos(a) * 5, -48 + sin(a) * 2), 1.5, WOOD_DARK)
	return g


# A lookout's tower: four posts, a railed platform and a ladder up the front.
# Returns { g, height }.
static func watchtower(angle: float) -> Dictionary:
	var g := Sketch.new()
	var h := 44.0
	Iso.ground_shadow(g, 22, 10, 0.25, 0.6)
	var corners := [Vector2(-12, -12), Vector2(12, -12), Vector2(12, 12), Vector2(-12, 12)]
	var posts := []
	for c in corners:
		posts.append(_xy(c.x, c.y, angle))
	# Back posts first, then the front ones
	posts.sort_custom(func(p, q): return p.y < q.y)
	for p in posts:
		g.line(p, p - Vector2(0, h), 3.0, WOOD_DARK)
	Iso.draw_solid(g, Iso.box(30, 30, 3, angle, WOOD, h, Color("#8b6236")))
	# Railing
	var rail := PackedVector2Array()
	for c in corners:
		rail.append(_p(c.x * 1.25, c.y * 1.25, h + 8, angle))
	g.poly_stroke(rail, 1.5, WOOD_DARK)
	for c in corners:
		g.line(_p(c.x * 1.25, c.y * 1.25, h + 3, angle), _p(c.x * 1.25, c.y * 1.25, h + 8, angle), 1.5, WOOD_DARK)
	# Ladder on the front
	for v in [-4.0, 4.0]:
		g.line(_p(17, v, 0, angle), _p(15, v, h + 3, angle), 1.5, WOOD)
	for z in range(4, int(h), 5):
		g.line(_p(16.5, -4, z, angle), _p(16.5, 4, z, angle), 1.0, WOOD)
	return {"g": g, "height": h + 3}


# A stone well with a little roof on two posts.
static func well() -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 15, 7, 0.22)
	Iso.draw_solid(g, Iso.cylinder(12, 9, STONE, 10, 0.0, Color("#6f6b63")))
	g.ellipse(Vector2(0, -9), 8, 5, Color("#1d2a33"))
	for v in [-11.0, 11.0]:
		g.line(Vector2(v, -9), Vector2(v, -36), 2.0, WOOD_DARK)
	g.line(Vector2(-11, -31), Vector2(11, -31), 1.5, WOOD_DARK)
	g.line(Vector2(0, -31), Vector2(0, -16), 1.0, Color("#c9b28a"))
	Iso.draw_solid(g, Iso.gable(26, 14, 8, 0, Color("#6e4a28"), 35.0, 1.0))
	return g


# A market stall: a counter under a striped awning, open towards `angle`.
static func stall(angle: float, colour: Color) -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 18, 9, 0.2)
	for c in [Vector2(-8, -15), Vector2(-8, 15), Vector2(8, -15), Vector2(8, 15)]:
		var base := _xy(c.x, c.y, angle)
		g.line(base, base - Vector2(0, 42 if c.x < 0 else 36), 2.0, WOOD_DARK)
	Iso.draw_solid(g, Iso.moved(Iso.box(8, 30, 14, angle, WOOD, 0.0, Color("#8b6236")), _v3(6, 0, 0, angle)))
	# Goods on the counter
	for k in range(-2, 3):
		g.circle(_p(6, k * 5, 15, angle), 2, Color("#c0392b") if k % 2 else Color("#d9b44a"))
	# Striped awning, in strips
	for k in 6:
		var s := -16.0 + k * (32.0 / 6)
		var strip := Iso.slope(32.0 / 6, 18, 43, 36, angle - PI / 2, Color("#f3e3c0") if k % 2 else colour)
		Iso.draw_solid(g, Iso.moved(strip, _v3(0, s + 16.0 / 6, 0, angle)))
	return g


# --- Camps and fortifications ----------------------------------------------------

# One sharpened stake of a palisade; `skull`: one of a goblin camp's trophies.
static func stake(colour := Color("#6e4a28"), skull := false) -> Sketch:
	var g := Sketch.new()
	var h := randf_range(30, 38)
	Iso.ground_shadow(g, 7, 3, 0.25, 0.6)
	Iso.draw_solid(g, Iso.cylinder(4.5, h, colour, 6, 0.0, Iso.shade(colour, 1.2)))
	Iso.draw_solid(g, Iso.cone(4.5, 6, Iso.shade(colour, 1.1), 6, 0.0, h))
	if skull:
		g.circle(Vector2(0, -h - 7), 3.5, Color("#e8e0c8"))
		g.circle(Vector2(-1.2, -h - 7.5), 0.9, Color("#1c1714"))
		g.circle(Vector2(1.2, -h - 7.5), 0.9, Color("#1c1714"))
	return g


# A cage of lashed poles for the goblins' captives.
static func cage() -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 15, 7, 0.22)
	var corners := PackedVector2Array([Vector2(-12, -10), Vector2(12, -10), Vector2(12, 10), Vector2(-12, 10)])
	g.poly(corners, Color("#2a1f14", 0.6))
	# Back bars, then front ones
	var bars := []
	for x in range(-12, 13, 6):
		bars.append(Vector2(x, -10))
		bars.append(Vector2(x, 10))
	for y in range(-10, 11, 5):
		bars.append(Vector2(-12, y))
		bars.append(Vector2(12, y))
	bars.sort_custom(func(p, q): return p.y < q.y)
	for b in bars:
		g.line(b, b - Vector2(0, 30), 2.0, Color("#5e3f22"))
	var top := PackedVector2Array()
	for c in corners:
		top.append(c - Vector2(0, 30))
	g.poly_stroke(top, 2.0, Color("#4a3220"))
	return g


# A skull on a pole to warn travellers off.
static func skull_totem() -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 5, 2.5, 0.25, 0.8)
	g.line(Vector2(0, 0), Vector2(0, -24), 3.0, Color("#5a3a1a"))
	g.line(Vector2(-6, -20), Vector2(6, -20), 2.0, Color("#5a3a1a"))
	g.circle(Vector2(0, -27), 5, Color("#e8e0c8"))
	g.circle(Vector2(-1.8, -28), 1.3, Color("#1c1714"))
	g.circle(Vector2(1.8, -28), 1.3, Color("#1c1714"))
	g.rect(-1.5, -24, 3, 1.5, Color("#1c1714"))
	return g


# A log lying on the ground along `angle` (a bench, or part of a barricade).
static func timber_log(length: float, radius: float, angle: float) -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, length * 0.5, radius, 0.2, 0.15)
	var a := PackedVector3Array()
	var b := PackedVector3Array()
	for k in 8:
		var t := float(k) / 8 * TAU
		var v := cos(t) * radius
		var z := radius + sin(t) * radius
		a.append(_v3(-length / 2, v, z, angle))
		b.append(_v3(length / 2, v, z, angle))
	var a_rev := a.duplicate()
	a_rev.reverse()
	var faces := [Iso.face(a_rev, Color("#a8875c")), Iso.face(b, Color("#a8875c"))]
	for k in 8:
		var n := (k + 1) % 8
		faces.append(Iso.face(PackedVector3Array([a[k], a[n], b[n], b[k]]), Color("#5e3f22")))
	Iso.draw_solid(g, faces)
	return g


# A fence along a line (relative to the origin): posts with two rails;
# `broken` leaves gaps.
static func fence(from: Vector2, to: Vector2, broken := false) -> Sketch:
	var g := Sketch.new()
	var posts := maxi(2, roundi(from.distance_to(to) / 12) + 1)
	var pts := []
	var standing := []
	for k in posts:
		pts.append(from.lerp(to, float(k) / (posts - 1)))
		standing.append(not broken or randf() > 0.3)
	for k in posts - 1:
		if not standing[k] or not standing[k + 1]:
			continue
		for z in [4.0, 8.0]:
			g.line(pts[k] - Vector2(0, z), pts[k + 1] - Vector2(0, z), 1.5, Color("#6e4a28"))
	for k in posts:
		if standing[k]:
			g.line(pts[k], pts[k] - Vector2(0, 10), 2.5, WOOD_DARK)
	return g


# --- Containers and carts --------------------------------------------------------

static func crate(size := 16.0) -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, size * 0.7, size * 0.3, 0.25)
	Iso.draw_solid(g, Iso.box(size, size, size * 0.85, 0.15, Color("#8b6236"), 0.0, Color("#a8875c")))
	var h := size * 0.85
	g.line(Vector2(-size / 2 + 1, -1), Vector2(size / 2 - 1, -h + 1), 1.2, Color("#5e3f22", 0.8))
	return g


# Returns { g, top }. Pass `g` to draw onto an existing sketch.
static func barrel(r := 9.0, g: Sketch = null) -> Dictionary:
	if g == null:
		g = Sketch.new()
	Iso.ground_shadow(g, r * 1.1, r * 0.45, 0.25)
	var h := r * 1.8
	Iso.draw_solid(g, Iso.cylinder(r, h, Color("#6e4a28"), 10, 0.0, Color("#8b6236")))
	for z in [h * 0.2, h * 0.8]:
		g.ellipse_stroke(Vector2(0, -z), r, r * 0.35, 1.2, Color("#2a1f14", 0.8))
	g.ellipse_stroke(Vector2(0, -h), r * 0.7, r * 0.3, 1.0, Color("#3a2a1a"))
	return {"g": g, "top": h}


# A treasure chest: iron-banded with a gold lock; open, the lid thrown back.
static func chest(open: bool, g: Sketch = null) -> Sketch:
	if g == null:
		g = Sketch.new()
	Iso.ground_shadow(g, 15, 6, 0.28)
	Iso.draw_solid(g, Iso.box(16, 24, 10, PI / 2, Color("#7a4a22"), 0.0, Color("#2a1f14") if open else Color("#8b5a2b")))
	if open:
		Iso.draw_solid(g, Iso.moved(Iso.box(4, 24, 10, PI / 2, Color("#5e3f22")), Vector3(0, -9, 6)))
		g.circle(Vector2(-3, -11), 2.2, Color("#e8b923"))
		g.circle(Vector2(3, -10), 2.2, Color("#e8b923"))
	else:
		Iso.draw_solid(g, Iso.gable(24, 16, 5, 0, Color("#8b5a2b"), 10.0, 0.0))
		g.rect(-1.5, -12, 3, 4, Color("#ffd75e"))
	for x in [-7.0, 7.0]:
		g.line(Vector2(x, 8), Vector2(x, -2 if open else -14), 1.5, Color("#3a3a3a"))
	g.rect(-12, -4, 24, 1.5, Color("#d4a32a"))
	return g


# The bed of a merchant's wagon tipped over: its underside, axles and the one
# wheel still on.
static func overturned_wagon(angle: float) -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 34, 16, 0.25)
	Iso.draw_solid(g, Iso.box(60, 34, 12, angle, Color("#5e3f22"), 0.0, Color("#3a2a1a")))
	for u in [-18.0, 18.0]:
		g.line(_p(u, -17, 12, angle), _p(u, 17, 12, angle), 3.0, Color("#2a1f14"))
	# A wheel sticking up off one axle
	var hub := _p(-18, -17, 14, angle)
	g.ellipse_stroke(hub - Vector2(0, 9), 4, 11, 2.5, Color("#3a2a1a"))
	return g


# The bandits' cart, loaded with plunder.
static func loot_cart(angle: float) -> Sketch:
	var g := Sketch.new()
	Iso.ground_shadow(g, 18, 9, 0.22)
	Iso.draw_solid(g, Iso.box(30, 22, 8, angle, Color("#5e3f22"), 8.0, Color("#6e4a28")))
	for v in [-12.0, 12.0]:
		g.ellipse_stroke(_p(0, v, 8, angle), 2.5, 8, 2.5, Color("#3a2a1a"))
	for c in [Vector2(-6, -4), Vector2(4, 3), Vector2(-2, 6)]:
		g.ellipse(_p(c.x, c.y, 18, angle), 5, 4, Color("#c9b28a"))
	g.circle(_p(2, -5, 18, angle), 2.5, Color("#e8b923"))
	return g


# A flickering campfire (on top of the ring of stones drawn on the ground).
static func flames() -> Sketch:
	var g := Sketch.new()
	g.poly(PackedVector2Array([Vector2(-7, 0), Vector2(0, -18), Vector2(7, 0)]), Color("#e8641e", 0.9))
	g.poly(PackedVector2Array([Vector2(-4, 0), Vector2(0, -12), Vector2(4, 0)]), Color("#ffb02e"))
	g.poly(PackedVector2Array([Vector2(-2, 0), Vector2(0, -6), Vector2(2, 0)]), Color("#fff1a8"))
	return g


static func _alpha(c: Color, a: float) -> Color:
	c.a = a
	return c
