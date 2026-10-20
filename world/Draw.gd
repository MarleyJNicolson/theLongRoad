class_name Draw
extends RefCounted

# Quick shapes. In Godot 4.7, anything drawn as a polygon (draw_circle,
# draw_colored_polygon, draw_polyline...) costs about 25 µs a call, while
# rects, textured rects, lines and four-point primitives are batched and cost
# well under 1 µs. Figures and scenery draw hundreds of circles and shapes, so
# they're built from the cheap kind here: a disc texture for circles and
# ellipses, quads for convex shapes, line segments for strokes. The same flat
# look (the pixel-art pass sees to the edges).

static var _disc: Texture2D


# A white disc, tinted to whatever colour it's drawn in.
static func disc() -> Texture2D:
	if not _disc:
		var size := 64
		var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
		var half := size / 2.0
		for y in size:
			for x in size:
				var d := Vector2(x + 0.5 - half, y + 0.5 - half).length()
				img.set_pixel(x, y, Color(1, 1, 1, clampf(half - d, 0.0, 1.0)))
		_disc = ImageTexture.create_from_image(img)
	return _disc


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, colour: Color) -> void:
	ci.draw_texture_rect(disc(), Rect2(c.x - rx, c.y - ry, rx * 2, ry * 2), false, colour)


static func circle(ci: CanvasItem, c: Vector2, r: float, colour: Color) -> void:
	ci.draw_texture_rect(disc(), Rect2(c.x - r, c.y - r, r * 2, r * 2), false, colour)


# A convex polygon (or near enough: a fan from the first point), as quads.
static func convex(ci: CanvasItem, pts: PackedVector2Array, colour: Color) -> void:
	var count := pts.size()
	if count < 3:
		return
	var colours := PackedColorArray([colour])
	var none := PackedVector2Array()
	var n := 1
	while n + 2 < count:
		ci.draw_primitive(PackedVector2Array([pts[0], pts[n], pts[n + 1], pts[n + 2]]), colours, none)
		n += 2
	if n + 1 < count:
		ci.draw_primitive(PackedVector2Array([pts[0], pts[n], pts[n + 1]]), colours, none)


# A thick line through `points` with round caps and joins. (Translucent ones
# skip the round bits, which would show as darker dots where they overlap.)
static func round_line(ci: CanvasItem, points: PackedVector2Array, width: float, colour: Color) -> void:
	# Translucent curves (swing trails: rare and brief) as one polyline, so the
	# segments don't darken where they overlap
	if colour.a < 1.0 and points.size() > 2:
		ci.draw_polyline(points, colour, width)
		return
	for n in points.size() - 1:
		ci.draw_line(points[n], points[n + 1], colour, width)
	if colour.a >= 1.0:
		for p in points:
			circle(ci, p, width / 2, colour)
