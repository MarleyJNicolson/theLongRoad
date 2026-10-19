class_name Sketch
extends Node2D

# A recorded drawing, the stand-in for a Pixi Graphics: shapes are added once
# (fills, strokes, circles, ellipses) and replayed in _draw. Most props are
# drawn once at creation and never change; call clear() and draw again to
# change one (e.g. a chest opening).

const ELLIPSE_SEGMENTS := 24

var _ops: Array = []


func clear() -> Sketch:
	_ops.clear()
	queue_redraw()
	return self


# A filled polygon.
func poly(pts: PackedVector2Array, colour: Color) -> Sketch:
	_ops.append([&"poly", pts, colour])
	queue_redraw()
	return self


# A polygon outline (closed) or polyline (open).
func poly_stroke(pts: PackedVector2Array, width: float, colour: Color, closed := true) -> Sketch:
	var line := pts.duplicate()
	if closed and pts.size() > 1:
		line.append(pts[0])
	_ops.append([&"stroke", line, width, colour])
	queue_redraw()
	return self


func line(a: Vector2, b: Vector2, width: float, colour: Color) -> Sketch:
	return poly_stroke(PackedVector2Array([a, b]), width, colour, false)


# A polyline with round caps and joins (cap: 'round' in Pixi).
func round_stroke(pts: PackedVector2Array, width: float, colour: Color) -> Sketch:
	_ops.append([&"round", pts, width, colour])
	queue_redraw()
	return self


func circle(c: Vector2, r: float, colour: Color) -> Sketch:
	_ops.append([&"circle", c, r, colour])
	queue_redraw()
	return self


# rx, ry are radii, as in Pixi's ellipse().
func ellipse(c: Vector2, rx: float, ry: float, colour: Color) -> Sketch:
	return poly(ellipse_points(c, rx, ry), colour)


func ellipse_stroke(c: Vector2, rx: float, ry: float, width: float, colour: Color) -> Sketch:
	return poly_stroke(ellipse_points(c, rx, ry), width, colour)


# A thick line with round ends (a stroke with cap: 'round'), as one shape, so
# a translucent one doesn't darken where the caps overlap.
func capsule(a: Vector2, b: Vector2, width: float, colour: Color) -> Sketch:
	return poly(capsule_points(a, b, width), colour)


# Triangles (`indices` into `points`), optionally textured with `texture`
# anchored to the world (UV = position / texture size), like a Pixi pattern fill.
func triangles(points: PackedVector2Array, indices: PackedInt32Array, colour: Color, texture: Texture2D = null) -> Sketch:
	_ops.append([&"tris", points, indices, colour, texture])
	queue_redraw()
	return self


func rect(x: float, y: float, w: float, h: float, colour: Color) -> Sketch:
	return poly(PackedVector2Array([Vector2(x, y), Vector2(x + w, y), Vector2(x + w, y + h), Vector2(x, y + h)]), colour)


static func ellipse_points(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in ELLIPSE_SEGMENTS:
		var a := TAU * k / ELLIPSE_SEGMENTS
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


static func round_rect_points(x: float, y: float, w: float, h: float, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var corners := [Vector2(x + w - r, y + r), Vector2(x + w - r, y + h - r), Vector2(x + r, y + h - r), Vector2(x + r, y + r)]
	for c in 4:
		for n in 5:
			var t := -PI / 2 + PI / 2 * c + PI / 2 * n / 4.0
			pts.append(corners[c] + Vector2(cos(t), sin(t)) * r)
	return pts


static func capsule_points(a: Vector2, b: Vector2, width: float) -> PackedVector2Array:
	var r := width / 2
	var dir := (b - a).normalized() if a != b else Vector2.RIGHT
	var base := dir.angle()
	var pts := PackedVector2Array()
	for n in 9: # round end at b
		var t := base - PI / 2 + PI * n / 8.0
		pts.append(b + Vector2(cos(t), sin(t)) * r)
	for n in 9: # round end at a
		var t := base + PI / 2 + PI * n / 8.0
		pts.append(a + Vector2(cos(t), sin(t)) * r)
	return pts


# A point on a quadratic curve from a to b pulled towards `control`, sampled.
static func quad_curve(a: Vector2, control: Vector2, b: Vector2, steps := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for n in steps + 1:
		var t := float(n) / steps
		pts.append(a.lerp(control, t).lerp(control.lerp(b, t), t))
	return pts


# A thick polyline with round caps and joins, drawn on `ci` (from its _draw).
# Translucent lines skip the round bits, which would show as darker dots.
static func round_line(ci: CanvasItem, points: PackedVector2Array, width: float, colour: Color) -> void:
	if points.size() < 2:
		return
	ci.draw_polyline(points, colour, width)
	if colour.a >= 1.0:
		for p in points:
			ci.draw_circle(p, width / 2, colour)


func _draw() -> void:
	for op in _ops:
		match op[0]:
			&"poly":
				fill(self, op[1], op[2])
			&"stroke":
				draw_polyline(op[1], op[3], op[2])
			&"circle":
				draw_circle(op[1], op[2], op[3])
			&"round":
				round_line(self, op[1], op[2], op[3])
			&"tris":
				var points: PackedVector2Array = op[1]
				var colours := PackedColorArray()
				colours.resize(points.size())
				colours.fill(op[3])
				var uvs := PackedVector2Array()
				var tex_rid := RID()
				var texture: Texture2D = op[4]
				if texture:
					tex_rid = texture.get_rid()
					var size := texture.get_size()
					for p in points:
						uvs.append(p / size)
				RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), op[2], points, colours, uvs,
					PackedInt32Array(), PackedFloat32Array(), tex_rid)


# Fill a polygon on `ci` (call from its _draw). Pixi fills anything, but Godot
# can't triangulate slivers or self-crossing shapes (a twisted ragdoll torso):
# slivers are skipped and crossed shapes drawn as a triangle fan.
static func fill(ci: CanvasItem, pts: PackedVector2Array, colour: Color) -> void:
	if absf(_area(pts)) <= 0.01:
		return
	if pts.size() == 3 or not Geometry2D.triangulate_polygon(pts).is_empty():
		ci.draw_colored_polygon(pts, colour)
		return
	for i in range(1, pts.size() - 1):
		var tri := PackedVector2Array([pts[0], pts[i], pts[i + 1]])
		if absf(_area(tri)) > 0.01:
			ci.draw_colored_polygon(tri, colour)


static func _area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return a * 0.5
