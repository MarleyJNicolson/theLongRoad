class_name Textures
extends RefCounted

# Textures painted in code when the game starts: tileable noise-based dirt and
# grass, so the road and ground aren't flat colour. Everything here is grey and
# gets tinted to each region's colours where it's used (via modulate, so unlike
# the JS version there is no need to bake a copy per colour).
#
# Painting happens in a float brightness buffer (all the marks are grey) with
# simple coverage-based antialiasing standing in for the browser canvas.

const SIZE := 256

static var _cache := {}


# Seeded random, so the textures are the same every run (same sequence as JS).
class Lcg:
	var s: int

	func _init(seed: int) -> void:
		s = seed

	func next() -> float:
		s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
		return s / 4294967296.0


# Tileable value noise: a lattice of random values that wraps at the edges,
# blended smoothly between points.
class NoiseLayer:
	var cells: int
	var lattice := PackedFloat32Array()

	func _init(random: Lcg, cells_: int) -> void:
		cells = cells_
		lattice.resize(cells * cells)
		for k in cells * cells:
			lattice[k] = random.next()

	# Adds this layer × weight into every pixel of buf.
	func add_into(buf: PackedFloat32Array, weight: float) -> void:
		var size := Textures.SIZE
		for py in size:
			var fy := float(py) / size * cells
			var y0 := floori(fy)
			var ty := fy - y0
			ty = ty * ty * (3.0 - 2.0 * ty)
			var row0 := (y0 % cells) * cells
			var row1 := ((y0 + 1) % cells) * cells
			for px in size:
				var fx := float(px) / size * cells
				var x0 := floori(fx)
				var tx := fx - x0
				tx = tx * tx * (3.0 - 2.0 * tx)
				var x1 := (x0 + 1) % cells
				x0 = x0 % cells
				var top := lattice[row0 + x0] + (lattice[row0 + x1] - lattice[row0 + x0]) * tx
				var bottom := lattice[row1 + x0] + (lattice[row1 + x1] - lattice[row1 + x0]) * tx
				buf[py * size + px] += (top + (bottom - top) * ty) * weight


# Several octaves of noise added together, broad patches plus fine grain,
# normalised to 0..1. octaves: [[cells, weight], ...]
static func _fractal(random: Lcg, octaves: Array) -> PackedFloat32Array:
	var layers := []
	var total := 0.0
	for o in octaves:
		layers.append(NoiseLayer.new(random, o[0]))
		total += o[1]
	var buf := PackedFloat32Array()
	buf.resize(SIZE * SIZE)
	for k in layers.size():
		layers[k].add_into(buf, octaves[k][1] / total)
	return buf


# Blend a grey tone into one pixel (wrapping round the tile).
static func _blend(buf: PackedFloat32Array, x: int, y: int, tone: float, alpha: float) -> void:
	var k := posmod(y, SIZE) * SIZE + posmod(x, SIZE)
	buf[k] = buf[k] * (1.0 - alpha) + tone * alpha


# A filled ellipse (rx × 0.8 rx), wrapping round the edges so speckles cross
# the tile edges seamlessly.
static func _dab(buf: PackedFloat32Array, x: float, y: float, r: float, tone: float, alpha: float) -> void:
	var ry := r * 0.8
	for py in range(floori(y - ry), ceili(y + ry) + 1):
		for px in range(floori(x - r), ceili(x + r) + 1):
			# 4×4 supersampled coverage
			var hits := 0
			for sy in 4:
				for sx in 4:
					var dx := (px + (sx + 0.5) / 4.0 - x) / r
					var dy := (py + (sy + 0.5) / 4.0 - y) / ry
					if dx * dx + dy * dy <= 1.0:
						hits += 1
			if hits > 0:
				_blend(buf, px, py, tone, alpha * hits / 16.0)


# A one-pixel stroke along a polyline, blended once (overlaps don't darken).
# Clipped to the tile unless wrap is set.
static func _stroke(buf: PackedFloat32Array, points: PackedVector2Array, tone: float, alpha: float, wrap := false) -> void:
	var cover := {}
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		for py in range(floori(minf(a.y, b.y)) - 1, ceili(maxf(a.y, b.y)) + 1):
			for px in range(floori(minf(a.x, b.x)) - 1, ceili(maxf(a.x, b.x)) + 1):
				if not wrap and (px < 0 or py < 0 or px >= SIZE or py >= SIZE):
					continue
				var c := Vector2(px + 0.5, py + 0.5)
				var d := c.distance_to(Geometry2D.get_closest_point_to_segment(c, a, b))
				var cov := clampf(1.0 - d, 0.0, 1.0)
				var key := Vector2i(px, py)
				if cov > cover.get(key, 0.0):
					cover[key] = cov
	for key in cover:
		_blend(buf, key.x, key.y, tone, alpha * cover[key])


# Brightness buffer → texture. (Rounded to bytes as the canvas would.)
static func _to_texture(buf: PackedFloat32Array) -> ImageTexture:
	var bytes := PackedByteArray()
	bytes.resize(SIZE * SIZE * 3)
	for k in SIZE * SIZE:
		var v := clampi(roundi(buf[k] * 255.0), 0, 255)
		bytes[k * 3] = v
		bytes[k * 3 + 1] = v
		bytes[k * 3 + 2] = v
	var image := Image.create_from_data(SIZE, SIZE, false, Image.FORMAT_RGB8, bytes)
	return ImageTexture.create_from_image(image)


# Fill every pixel from base + noise × spread, rounded to bytes.
static func _shade(noise: PackedFloat32Array, base: float, spread: float) -> PackedFloat32Array:
	var buf := PackedFloat32Array()
	buf.resize(SIZE * SIZE)
	for k in SIZE * SIZE:
		buf[k] = clampi(roundi((base + noise[k] * spread) * 255.0), 0, 255) / 255.0
	return buf


# Packed earth: mottled, gritty, with pebbles and the odd crack.
static func dirt_texture() -> ImageTexture:
	if _cache.has("dirt"):
		return _cache["dirt"]
	var random := Lcg.new(7)
	var buf := _shade(_fractal(random, [[4, 3.0], [12, 2.0], [40, 1.2], [128, 0.8]]), 0.72, 0.32)
	for k in 260:
		var r := 0.6 + random.next() * 1.8
		var tone := floorf(120.0 + random.next() * 110.0) / 255.0
		var x := random.next() * SIZE
		var y := random.next() * SIZE
		_dab(buf, x, y, r, tone, 0.85)
	# Hairline cracks
	for k in 14:
		var p := Vector2(random.next() * SIZE, random.next() * SIZE)
		var path := PackedVector2Array([p])
		for s in 4:
			p.x += (random.next() - 0.5) * 18.0
			p.y += (random.next() - 0.5) * 18.0
			path.append(p)
		_stroke(buf, path, 70.0 / 255.0, 0.35)
	_cache["dirt"] = _to_texture(buf)
	return _cache["dirt"]


# Meadow grass: patchy light and shade with a scatter of blade marks.
static func grass_texture() -> ImageTexture:
	if _cache.has("grass"):
		return _cache["grass"]
	var random := Lcg.new(19)
	var buf := _shade(_fractal(random, [[3, 3.0], [9, 2.0], [32, 1.0], [96, 0.7]]), 0.8, 0.24)
	for k in 900:
		var x := random.next() * SIZE
		var y := random.next() * SIZE
		var light := random.next() < 0.5
		var tone := 1.0 if light else 0.0
		var alpha := 0.22 if light else 0.16
		# Drawn nine times round the tile edges; each copy gets its own random
		# tip, as in the JS (keeps the random sequence identical).
		for dx in [-SIZE, 0, SIZE]:
			for dy in [-SIZE, 0, SIZE]:
				var a := Vector2(x + dx, y + dy)
				var b := Vector2(a.x + (random.next() - 0.5) * 3.0, a.y - 2.0 - random.next() * 4.0)
				_stroke(buf, PackedVector2Array([a, b]), tone, alpha)
	_cache["grass"] = _to_texture(buf)
	return _cache["grass"]
