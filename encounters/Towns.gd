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
const MOTTO := "A safe haven · rest and trade"


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


# The name of the town nearest `along_px` (its road point may be a little
# either side of the exact distance).
static func town_name(along_px: float) -> String:
	var k := 0
	while absf(metres_of(k + 1) * PX_PER_METRE - along_px) < absf(metres_of(k) * PX_PER_METRE - along_px):
		k += 1
	return NAMES[k % NAMES.size()] + ("" if k < NAMES.size() else " %d" % (k / NAMES.size() + 1))


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

	# A fingerpost on the way in
	var post_at: Vector2 = side_of.call(-(RADIUS + 260), Road.ROAD_WIDTH / 2 + 70)
	SideRoads._signpost(b, post_at, false, town, roundi((RADIUS + 260) / PX_PER_METRE), false)

	var animate := func(_time: float, dt: float) -> void:
		for v in folk:
			v.update(dt)
		for t in traders:
			t.figure.update(dt)
	return {
		"members": [],
		"solids": solids,
		"loot": [],
		"traders": traders,
		"zones": [Vector3(c.x, c.y, RADIUS + 20)],
		"trigger": Vector3(c.x, c.y, 0),
		"animate": animate,
		"town": {"name": town, "safe": Vector3(c.x, c.y, RADIUS), "inn": door},
	}
