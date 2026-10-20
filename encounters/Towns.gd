class_name Towns
extends RefCounted

# Towns the main road runs straight through: milestones along the way, safe
# from raiders, where you're mended and rested for free and can trade. (Not in
# the JS original.)
#
# The first is at FIRST m; after that the gaps grow by GAP_GROWTH each time
# (1000, 2500, 4500, 7000, 10000 m...). The road straightens as it nears one,
# enters through a gate in the palisade and leaves by the opposite gate.

const FIRST := 1000.0 # metres
const FIRST_GAP := 1500.0 # metres from the first town to the second
const GAP_GROWTH := 500.0 # each gap after that is this much longer
const RADIUS := 300.0 # px, the palisade
const STRAIGHT := RADIUS + 200.0 # px either side of the centre the road runs straight
const CLEAR := RADIUS + 320.0 # px either side of the centre with no encounters
const PX_PER_METRE := 20.0

const NAMES := ["Kingsbridge", "Harrowgate", "Stonehaven", "Ravensford", "Eastmarch", "Greywall",
	"Brackenholm", "Wyvernhold", "Aldermoor", "Thistlecross", "Highmere", "Saltcombe"]
const MOTTO := "An imperial garrison holds · rest and trade"
const CRIMSON := Color("#7a1f1f")
const GOLD := Color("#c9a227")


# Where the kth town (from 0) stands along the road, in metres.
static func metres_of(k: int) -> float:
	var at := FIRST
	for j in k:
		at += FIRST_GAP + GAP_GROWTH * j
	return at


# The first town at or beyond `px` along the road: its distance along (px), or
# -1 if there's none within reach (never: they go on for ever).
static func next_along(px: float) -> float:
	var k := 0
	while metres_of(k) * PX_PER_METRE < px:
		k += 1
	return metres_of(k) * PX_PER_METRE


# Is the road `px` along within a town's straight stretch?
static func straight_at(px: float) -> bool:
	var k := 0
	while metres_of(k) * PX_PER_METRE + STRAIGHT < px:
		k += 1
	return absf(metres_of(k) * PX_PER_METRE - px) <= STRAIGHT


# Which town (from 0) is nearest `along_px`.
static func index_of(along_px: float) -> int:
	var k := 0
	while absf(metres_of(k + 1) * PX_PER_METRE - along_px) < absf(metres_of(k) * PX_PER_METRE - along_px):
		k += 1
	return k


# The name of the town nearest `along_px` (its road point may be a little
# either side of the exact distance).
static func town_name(along_px: float) -> String:
	var k := 0
	while absf(metres_of(k + 1) * PX_PER_METRE - along_px) < absf(metres_of(k) * PX_PER_METRE - along_px):
		k += 1
	return NAMES[k % NAMES.size()] + ("" if k < NAMES.size() else " %d" % (k / NAMES.size() + 1))


# The Empire's banner on a pole: crimson with a gold sun, tattered at the
# fly. `h`: the pole's height.
static func banner(h := 64.0, torn := true) -> Sketch:
	var g := Sketch.new()
	g.ellipse(Vector2.ZERO, 5, 2, Color(0, 0, 0, 0.25))
	g.line(Vector2.ZERO, Vector2(0, -h), 2.5, Color("#4a3220"))
	g.circle(Vector2(0, -h - 1.5), 2.2, GOLD)
	var top := -h + 3
	var cloth := PackedVector2Array([Vector2(1, top), Vector2(26, top + 2), Vector2(25, top + 22)])
	if torn: # ragged along the bottom
		cloth.append_array([Vector2(20, top + 19), Vector2(17, top + 26), Vector2(12, top + 21), Vector2(7, top + 27), Vector2(1, top + 24)])
	else:
		cloth.append(Vector2(1, top + 26))
	g.poly(cloth, CRIMSON)
	g.line(Vector2(1, top + 4), Vector2(25.5, top + 6), 1.2, GOLD)
	g.circle(Vector2(13, top + 13), 4, GOLD)
	g.circle(Vector2(13, top + 13), 2.4, CRIMSON)
	return g


# Build the town at main-road point `b.i`. Returns the encounter (with
# `town` set: its name and the safe circle).
static func build(b: Build) -> Dictionary:
	var f := b.frame()
	var c := f.p
	var town := town_name(Road.along(b.i))
	var side_of := func(along: float, lateral: float) -> Vector2: return f.at(along, lateral)
	var solids := []

	# The ground inside the walls, a cobbled square beside the road
	var ground := b.merged(0.45)
	for k in 10:
		var a := float(k) / 10 * TAU
		ground.circle(c + Vector2(cos(a), sin(a)) * RADIUS * 0.45, RADIUS * 0.66, Color("#a89466"))
	var square: Vector2 = side_of.call(0, -165)
	b.g.ellipse(square, 105, 80, Color("#b9a57a", 0.7))

	# The palisade, with a gate where the road comes in and where it leaves
	var gates := [f.d.angle(), (-f.d).angle()]
	var steps := floori(TAU * RADIUS / 10)
	for k in steps:
		var a := float(k) / steps * TAU
		var in_gate := false
		for g in gates:
			if absf(wrapf(a - g, -PI, PI)) < 0.24:
				in_gate = true
		if in_gate:
			continue
		var at := c + Vector2(cos(a), sin(a)) * RADIUS
		b.stand(Structures.stake(Color("#6e4a28")), at.x, at.y)
		if k % 2 == 0:
			solids.append(Vector3(at.x, at.y, 9))
	for g in gates:
		for s in [-1.0, 1.0]:
			var a: float = g + s * 0.26
			var post := Structures.stake(Color("#4a3220"))
			post.scale = Vector2(1.5, 1.5)
			var at := c + Vector2(cos(a), sin(a)) * RADIUS
			b.stand(post, at.x, at.y)
		# The town's name over each gate, on the verge outside
		var outside := c + Vector2(cos(g), sin(g)) * (RADIUS + 40) + f.n * (Road.ROAD_WIDTH / 2 + 60)
		Destinations._add_sign(b, outside, town, false)

	# Cottages along both sides of the road, doors towards it; the square
	# side has fewer, round the market
	var homes := [Vector2(-185, 135), Vector2(75, 195), Vector2(190, 125),
		Vector2(-200, -120), Vector2(200, -120)]
	for h in homes:
		var at: Vector2 = side_of.call(h.x, h.y)
		var facing := (-f.n * signf(h.y)).angle()
		Raids.house(b, at, facing)
		for fy in [-24.0, 0.0, 24.0]:
			var s: Vector2 = at + Vector2(0, fy).rotated(facing)
			solids.append(Vector3(s.x, s.y, 31))

	# The inn, bigger than the cottages, its sign and lantern by the door. At
	# night you can sleep there until dawn.
	var inn_at: Vector2 = side_of.call(-55, 200)
	var inn_facing := (-f.n).angle()
	var inn := Structures.cottage(inn_facing, false, 62.0, 108.0, 32.0)
	b.stand(inn.g, inn_at.x, inn_at.y, null, {"r": 52, "height": inn.roof + 6})
	for fy in [-36.0, -12.0, 12.0, 36.0]:
		var s: Vector2 = inn_at + Vector2(0, fy).rotated(inn_facing)
		solids.append(Vector3(s.x, s.y, 33))
	var door := inn_at + Vector2(31 + 22, 0).rotated(inn_facing)
	var sign_at := inn_at + Vector2(31 + 18, 34).rotated(inn_facing)
	var sign := Glow.lantern_post(30)
	var board := Sketch.new()
	var plate := Sketch.round_rect_points(-20, -52, 40, 18, 2)
	board.poly(plate, Color("#a8875c")).poly_stroke(plate, 2, Color("#3d2f25"))
	sign.add_child(board)
	sign.add_child(Fonts.world_label("Inn", Vector2(0, -43), 14, Color("#2a1f14")))
	b.stand(sign, sign_at.x, sign_at.y)

	# Lanterns by both gates, and on the square
	for g in gates:
		for s in [-1.0, 1.0]:
			var at: Vector2 = c + Vector2(cos(g), sin(g)) * (RADIUS - 30) + f.n * s * (Road.ROAD_WIDTH / 2 + 18)
			b.stand(Glow.lantern_post(), at.x, at.y)
	var lamp: Vector2 = side_of.call(0, -95)
	b.stand(Glow.lantern_post(), lamp.x, lamp.y)

	# The market: a well, two stalls and their keepers (more stock than a village)
	b.stand(Structures.well(), square.x, square.y, null, {"r": 14, "height": 44})
	solids.append(Vector3(square.x, square.y, 16))
	var metres := Road.along(b.i) / PX_PER_METRE
	var stock := Destinations._stock_for(metres)
	for k in 2:
		stock.smith.append({"kind": "gear", "item": Items.roll_item(metres), "price": 0})
	for offer in stock.smith:
		offer.price = offer.item.tier * 10 + randi_range(0, 4)
	var traders := []
	var stalls := [["Blacksmith", stock.smith, Color("#7d8590"), "smith", -62.0], ["General store", stock.store, Color("#c0392b"), "merchant", 62.0]]
	var to_road := f.n.angle() # stalls open towards the road
	for st in stalls:
		var at: Vector2 = side_of.call(st[4], -150)
		b.stand(Structures.stall(to_road, st[2]), at.x, at.y)
		solids.append(Vector3(at.x, at.y, 14))
		traders.append(Destinations._make_trader(b, side_of.call(st[4], -118), to_road, st[0], st[1], st[3]))
	Loot.add_prop(b, "crate", side_of.call(-100, -128), 15)
	Loot.add_prop(b, "barrel", side_of.call(100, -130), 8)

	# Townsfolk about the square and the street
	var folk := []
	for spot in [Vector2(-40, -200), Vector2(40, -210), Vector2(-120, -90), Vector2(130, -85), Vector2(-120, 85), Vector2(140, 90)]:
		var at: Vector2 = side_of.call(spot.x, spot.y)
		var v := Folk.new(Folk.look(), at.x, at.y, (c - at).angle(), 24)
		b.stand(v, at.x, at.y)
		folk.append(v)

	# Someone by the inn looking for work: an archer who'll ride with you and
	# defend the cart. The first town's comes along for nothing; later ones
	# want paying.
	var hirelings := []
	var k := index_of(Road.along(b.i))
	var hire_at: Vector2 = side_of.call(30, 135)
	var hand := Folk.new(Companion.KINDS.archer.look, hire_at.x, hire_at.y, (-f.n).angle(), 0)
	hand.rig.offhand = "bow"
	b.stand(hand, hire_at.x, hire_at.y)
	solids.append(Vector3(hire_at.x, hire_at.y, 8))
	hirelings.append({"kind": "archer", "who": Companion.NAMES[(k * 3 + randi() % 3) % Companion.NAMES.size()],
		"price": 0 if k == 0 else 20 + 15 * k, "x": hire_at.x, "y": hire_at.y, "figure": hand, "hired": false})

	# The garrison. At each gate: spearmen either side of the road, a
	# watchtower with a crossbowman at its foot, the Empire's banners on the
	# gateposts, and spiked barricades out front.
	var guards := []
	for gi in gates.size():
		var g: float = gates[gi]
		var out := Vector2.from_angle(g)
		for s in [-1.0, 1.0]:
			var at: Vector2 = c + out * (RADIUS - 14) + f.n * s * (Road.ROAD_WIDTH / 2 + 6)
			var sentry := Folk.spearman(at.x, at.y, g)
			b.stand(sentry, at.x, at.y)
			folk.append(sentry)
			solids.append(Vector3(at.x, at.y, 8))
			var pole: Vector2 = c + Vector2.from_angle(g + s * 0.33) * (RADIUS - 8)
			b.stand(banner(), pole.x, pole.y)
		var side := 1.0 if gi == 0 else -1.0
		var tower_at: Vector2 = c + out * (RADIUS - 50) + f.n * side * (Road.ROAD_WIDTH / 2 + 42)
		var tower_facing := (-f.n * side).angle() # ladder towards the road
		b.stand(Structures.watchtower(tower_facing).g, tower_at.x, tower_at.y, null, {"r": 20, "height": 56})
		solids.append(Vector3(tower_at.x, tower_at.y, 20))
		guards.append(Destinations.guard(b, tower_at + Vector2.from_angle(tower_facing) * 26, g))
		# Barricades either side of the road outside: a log on stakes
		for s in [-1.0, 1.0]:
			var mid: Vector2 = c + out * (RADIUS + 70) + f.n * s * (Road.ROAD_WIDTH / 2 + 55)
			b.stand(Structures.timber_log(64, 4.5, f.n.angle()), mid.x, mid.y)
			for t in [-24.0, 0.0, 24.0]:
				var stake: Vector2 = mid + f.n * t
				b.stand(Structures.stake(Color("#4a3220")), stake.x, stake.y + 1)
				solids.append(Vector3(stake.x, stake.y, 9))

	# Soldiers' tents behind the market, a banner over the square, and a
	# pair on their rounds
	for tx in [-110.0, 110.0]:
		var tent: Vector2 = side_of.call(tx, -228)
		b.stand(Structures.lean_to(f.n.angle(), Color("#b8a47e")), tent.x, tent.y, null, {"r": 30, "height": 40})
		solids.append(Vector3(tent.x, tent.y, 24))
		var crate: Vector2 = side_of.call(tx + (28 if tx > 0 else -28), -200)
		b.stand(Structures.crate(14), crate.x, crate.y)
		solids.append(Vector3(crate.x, crate.y, 10))
	var flag: Vector2 = side_of.call(0, -228)
	var standard := banner(84, false)
	b.stand(standard, flag.x, flag.y)
	for beat in [Vector2(-90, 45), Vector2(90, -45)]:
		var at: Vector2 = side_of.call(beat.x, beat.y)
		var walker := Folk.spearman(at.x, at.y, f.d.angle(), 80)
		b.stand(walker, at.x, at.y)
		folk.append(walker)
	# Each stall has a crossbowman guarding it
	for st in stalls:
		var at: Vector2 = side_of.call(st[4] + (36 if st[4] > 0 else -36), -122)
		guards.append(Destinations.guard(b, at, to_road))

	# A fingerpost on the way in
	var post_at: Vector2 = side_of.call(-(RADIUS + 260), Road.ROAD_WIDTH / 2 + 70)
	SideRoads._signpost(b, post_at, false, town, roundi((RADIUS + 260) / PX_PER_METRE), false)

	var animate := func(_time: float, dt: float) -> void:
		for v in folk:
			v.update(dt)
		for t in traders:
			t.figure.update(dt)
		for h in hirelings:
			if not h.hired:
				h.figure.update(dt)
	return {
		"members": [],
		"solids": solids,
		"loot": [],
		"traders": traders,
		"hirelings": hirelings,
		"guards": guards,
		"zones": [Vector3(c.x, c.y, RADIUS + 20)],
		"trigger": Vector3(c.x, c.y, 0),
		"animate": animate,
		"town": {"name": town, "safe": Vector3(c.x, c.y, RADIUS), "inn": door},
	}
