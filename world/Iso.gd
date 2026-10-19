class_name Iso
extends RefCounted

# Building blocks for drawing solid things in the three-quarter view (port of
# iso.js): boxes, roofs, cones and cylinders described as faces in 3D (x and y
# on the ground, z up), drawn by lifting each point by its height. Faces turned
# away from the camera are skipped and the rest are lit from the top left, so
# everything built from these looks consistent.
#
# A face is { pts: PackedVector3Array, colour: Color, flat: bool }.

# Towards the camera (it looks down from the south) and towards the light:
# normalised (0, 1, 1.2) and (-0.55, -0.45, 1).
const VIEW := Vector3(0.0, 0.640184, 0.768221)
const LIGHT := Vector3(-0.448326, -0.366813, 0.815139)


# Lighten (k > 1) or darken (k < 1) a colour, rounded to whole 8-bit steps.
static func shade(c: Color, k: float) -> Color:
	return Color(
		clampf(roundf(c.r8 * k), 0, 255) / 255.0,
		clampf(roundf(c.g8 * k), 0, 255) / 255.0,
		clampf(roundf(c.b8 * k), 0, 255) / 255.0,
		c.a)


static func project(p: Vector3) -> Vector2:
	return Vector2(p.x, p.y - p.z)


static func project_all(pts: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(Vector2(p.x, p.y - p.z))
	return out


# Turn a footprint point by `angle` about the origin.
static func turn(p: Vector3, angle: float) -> Vector3:
	var c := cos(angle)
	var s := sin(angle)
	return Vector3(p.x * c - p.y * s, p.x * s + p.y * c, p.z)


static func face(pts: PackedVector3Array, colour: Color, flat := false) -> Dictionary:
	return {"pts": pts, "colour": colour, "flat": flat}


# The same faces moved by `offset`.
static func moved(faces: Array, offset: Vector3) -> Array:
	var out := []
	for f in faces:
		var pts := PackedVector3Array()
		for p in f.pts:
			pts.append(p + offset)
		out.append(face(pts, f.colour, f.flat))
	return out


static func _reversed(pts: PackedVector3Array) -> PackedVector3Array:
	var out := pts.duplicate()
	out.reverse()
	return out


# Draw a convex solid. Only faces turned towards the camera are drawn (so on a
# convex shape none of them overlap), each shaded by how much light it catches.
static func draw_solid(g: Sketch, faces: Array, outline: Variant = null) -> void:
	var centre := Vector3.ZERO
	var count := 0
	for f in faces:
		for p in f.pts:
			centre += p
			count += 1
	centre /= maxi(1, count)
	for f in faces:
		var n := _normal(f.pts, centre)
		if n.dot(VIEW) <= 0.02:
			continue
		var light := 1.0 if f.flat else 0.68 + 0.42 * maxf(0.0, n.dot(LIGHT))
		var pts := project_all(f.pts)
		g.poly(pts, shade(f.colour, light))
		if outline != null:
			var ink: Color = outline
			ink.a = 0.5
			g.poly_stroke(pts, 1.0, ink)


# Outward normal of a flat face (Newell's method), pointing away from the
# solid's centre.
static func _normal(pts: PackedVector3Array, centre: Vector3) -> Vector3:
	var n := Vector3.ZERO
	var mid := Vector3.ZERO
	for i in pts.size():
		var a := pts[i]
		var b := pts[(i + 1) % pts.size()]
		n += Vector3((a.y - b.y) * (a.z + b.z), (a.z - b.z) * (a.x + b.x), (a.x - b.x) * (a.y + b.y))
		mid += a
	n = n.normalized()
	mid /= pts.size()
	return -n if n.dot(mid - centre) < 0 else n


# Is a face with this outward normal turned towards the camera?
static func faces_camera(n: Vector3) -> bool:
	return n.normalized().dot(VIEW) > 0.02


# --- Shapes (all footprints centred on the origin, turned by `angle`) ---------

# A box `long` × `wide` on the ground, `high` tall, sitting at height `z0`.
static func box(long: float, wide: float, high: float, angle: float, colour: Color, z0 := 0.0, top: Variant = null) -> Array:
	var l := long / 2
	var w := wide / 2
	var b := PackedVector3Array()
	var t := PackedVector3Array()
	for c in [Vector2(-l, -w), Vector2(l, -w), Vector2(l, w), Vector2(-l, w)]:
		b.append(turn(Vector3(c.x, c.y, z0), angle))
		t.append(turn(Vector3(c.x, c.y, z0 + high), angle))
	return [
		face(t, colour if top == null else top),
		face(PackedVector3Array([b[0], b[1], t[1], t[0]]), colour),
		face(PackedVector3Array([b[1], b[2], t[2], t[1]]), colour),
		face(PackedVector3Array([b[2], b[3], t[3], t[2]]), colour),
		face(PackedVector3Array([b[3], b[0], t[0], t[3]]), colour),
		face(_reversed(b), colour),
	]


# A gabled roof: ridge along the long side, eaves overhanging by `over`.
static func gable(long: float, wide: float, rise: float, angle: float, colour: Color, z0 := 0.0, over := 2.0, ends: Variant = null) -> Array:
	var l := long / 2 + over
	var w := wide / 2 + over
	var e := PackedVector3Array()
	for c in [Vector2(-l, -w), Vector2(l, -w), Vector2(l, w), Vector2(-l, w)]:
		e.append(turn(Vector3(c.x, c.y, z0), angle))
	var r0 := turn(Vector3(-l, 0, z0 + rise), angle)
	var r1 := turn(Vector3(l, 0, z0 + rise), angle)
	var end_colour: Color = colour if ends == null else ends
	return [
		face(PackedVector3Array([e[0], e[1], r1, r0]), colour),
		face(PackedVector3Array([e[3], e[2], r1, r0]), colour),
		face(PackedVector3Array([e[0], r0, e[3]]), end_colour),
		face(PackedVector3Array([e[1], r1, e[2]]), end_colour),
		face(_reversed(e), colour),
	]


# A sloping roof (a lean-to): high along one long side, low along the other.
static func slope(long: float, wide: float, high: float, low: float, angle: float, colour: Color) -> Array:
	var l := long / 2
	var w := wide / 2
	var top := PackedVector3Array([
		turn(Vector3(-l, -w, high), angle), turn(Vector3(l, -w, high), angle),
		turn(Vector3(l, w, low), angle), turn(Vector3(-l, w, low), angle)])
	var under := PackedVector3Array()
	for p in top:
		under.append(p - Vector3(0, 0, 1.5))
	var edge := shade(colour, 0.8)
	return [
		face(top, colour),
		face(_reversed(under), shade(colour, 0.6)),
		face(PackedVector3Array([top[0], top[1], under[1], under[0]]), edge),
		face(PackedVector3Array([top[2], top[3], under[3], under[2]]), edge),
		face(PackedVector3Array([top[1], top[2], under[2], under[1]]), edge),
		face(PackedVector3Array([top[3], top[0], under[0], under[3]]), edge),
	]


# A cone (a hide tent): `sides`-sided, apex `high` above the ground.
static func cone(radius: float, high: float, colour: Color, sides := 8, angle := 0.0, z0 := 0.0) -> Array:
	var ring := PackedVector3Array()
	for k in sides:
		var a := angle + float(k) / sides * TAU
		ring.append(Vector3(cos(a) * radius, sin(a) * radius, z0))
	var apex := Vector3(0, 0, z0 + high)
	var faces := []
	for k in sides:
		faces.append(face(PackedVector3Array([ring[k], ring[(k + 1) % sides], apex]), colour))
	faces.append(face(_reversed(ring), colour))
	return faces


# An upright cylinder (a barrel, a well, a post), `sides`-sided.
static func cylinder(radius: float, high: float, colour: Color, sides := 10, z0 := 0.0, top: Variant = null) -> Array:
	var bottom := PackedVector3Array()
	var upper := PackedVector3Array()
	for k in sides:
		var a := float(k) / sides * TAU
		bottom.append(Vector3(cos(a) * radius, sin(a) * radius, z0))
		upper.append(Vector3(cos(a) * radius, sin(a) * radius, z0 + high))
	var faces := [face(upper, colour if top == null else top)]
	for k in sides:
		var n := (k + 1) % sides
		faces.append(face(PackedVector3Array([bottom[k], bottom[n], upper[n], upper[k]]), colour))
	faces.append(face(_reversed(bottom), colour))
	return faces


# A shadow on the ground beside something standing (the light is top left).
static func ground_shadow(g: Sketch, w: float, h: float, alpha := 0.22, dx := 0.25) -> void:
	g.ellipse(Vector2(w * dx, h * 0.25), w, h, Color(0, 0, 0, alpha))
