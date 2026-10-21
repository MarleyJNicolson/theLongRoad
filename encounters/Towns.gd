class_name Towns
extends RefCounted

# The towns where the roads meet (not in the JS original): safe from raiders,
# garrisoned by what's left of the Empire, where you're mended and rested for
# free, can trade, take on hands, and (see Missions) carry supplies between
# them. Each is a palisade round a plaza where its roads come in, through a
# gate apiece; its buildings stand round the plaza in the gaps between the
# gates. Which towns there are and where is RoadNet's business; here they're
# built, when you come near one.

const RADIUS := 300.0 # px, the palisade
const CLEAR := RADIUS + 320.0 # px round the middle kept free of encounters
const PX_PER_METRE := 20.0
const RING := 212.0 # px out to the buildings round the plaza
const INNER := 128.0 # px out to the market stalls
const GATE_GAP := 0.42 # rad either side of a gate kept clear of buildings

const NAMES := ["Kingsbridge", "Harrowgate", "Stonehaven", "Ravensford", "Eastmarch", "Greywall",
	"Brackenholm", "Wyvernhold", "Aldermoor", "Thistlecross", "Highmere", "Saltcombe",
	"Dunmere", "Coldharbour", "Ashby", "Marrowfield", "Oakhurst", "Blackwater", "Fenwick", "Redcliffe"]
const MOTTO := "An imperial garrison holds · rest and trade"
const GATE_MOTTO := "The gate north · the last garrison of the region"
const CRIMSON := Color("#7a1f1f")
const GOLD := Color("#c9a227")


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


# Angles round the middle that aren't in front of a gate, `count` of them
# spread evenly (as near as the gates allow), starting from `offset`.
static func _free_angles(gates: Array, count: int, offset: float, gap := GATE_GAP) -> Array:
	var out := []
	var steps := count * 4
	for k in steps:
		var a := offset + float(k) / steps * TAU
		var clear := true
		for g: float in gates:
			if absf(wrapf(a - g, -PI, PI)) < gap:
				clear = false
				break
		if clear:
			out.append(a)
	# Thin to `count`, evenly through what's free
	var picked := []
	for k in mini(count, out.size()):
		picked.append(out[floori(float(k) * out.size() / mini(count, out.size()))])
	return picked


# Build `town` (see RoadNet.towns). Returns the encounter (with `town` set:
# its name, the safe circle, the inn door...).
static func build(b: Build, town: Dictionary) -> Dictionary:
	var c: Vector2 = town.pos
	var gates: Array = town.gates
	var final: bool = town.kind == "final"
	var at_angle := func(a: float, r: float) -> Vector2: return c + Vector2.from_angle(a) * r
	var solids := []

	# The ground inside the walls, and the cobbled plaza where the roads meet
	var ground := b.merged(0.45)
	for k in 10:
		var a := float(k) / 10 * TAU
		ground.circle(c + Vector2(cos(a), sin(a)) * RADIUS * 0.45, RADIUS * 0.66, Color("#a89466"))
	b.g.ellipse(c, 118, 96, Color("#b9a57a", 0.7))
	for k in 40:
		var at := c + Vector2.from_angle(randf() * TAU) * randf_range(10, 105) * Vector2(1, 0.82)
		b.g.ellipse(at, randf_range(5, 9), randf_range(3, 5), Color("#9a8a62", 0.5))

	# The palisade, with a gate for each road
	var steps := floori(TAU * RADIUS / 10)
	for k in steps:
		var a := float(k) / steps * TAU
		var in_gate := false
		for g: float in gates:
			if absf(wrapf(a - g, -PI, PI)) < 0.24:
				in_gate = true
		if in_gate:
			continue
		var at: Vector2 = at_angle.call(a, RADIUS)
		b.stand(Structures.stake(Color("#6e4a28")), at.x, at.y)
		if k % 2 == 0:
			solids.append(Vector3(at.x, at.y, 9))

	var folk := []
	var guards := []
	for gi in gates.size():
		var g: float = gates[gi]
		var out := Vector2.from_angle(g)
		var n := out.orthogonal()
		# Gateposts, with the Empire's banners
		for s in [-1.0, 1.0]:
			var post := Structures.stake(Color("#4a3220"))
			post.scale = Vector2(1.5, 1.5)
			var at: Vector2 = at_angle.call(g + s * 0.26, RADIUS)
			b.stand(post, at.x, at.y)
			var pole: Vector2 = at_angle.call(g + s * 0.33, RADIUS - 8)
			b.stand(banner(), pole.x, pole.y)
		# The town's name over the gate, on the verge outside
		var sign_at: Vector2 = c + out * (RADIUS + 40) + n * (Road.ROAD_WIDTH / 2 + 60)
		Destinations._add_sign(b, sign_at, town.name, false)
		# Lanterns either side of the road just inside
		for s in [-1.0, 1.0]:
			var at: Vector2 = c + out * (RADIUS - 30) + n * s * (Road.ROAD_WIDTH / 2 + 18)
			b.stand(Glow.lantern_post(), at.x, at.y)
		# Spearmen either side of the gate
		for s in [-1.0, 1.0]:
			var at: Vector2 = c + out * (RADIUS - 14) + n * s * (Road.ROAD_WIDTH / 2 + 6)
			var sentry := Folk.spearman(at.x, at.y, g)
			b.stand(sentry, at.x, at.y)
			folk.append(sentry)
			solids.append(Vector3(at.x, at.y, 8))
		# A watchtower beside the first two gates, a crossbowman at its foot
		if gi < 2:
			var side := 1.0 if gi == 0 else -1.0
			var tower_at: Vector2 = c + out * (RADIUS - 50) + n * side * (Road.ROAD_WIDTH / 2 + 42)
			var tower_facing := (-n * side).angle() # ladder towards the road
			b.stand(Structures.watchtower(tower_facing).g, tower_at.x, tower_at.y, null, {"r": 20, "height": 56})
			solids.append(Vector3(tower_at.x, tower_at.y, 20))
			guards.append(Destinations.guard(b, tower_at + Vector2.from_angle(tower_facing) * 26, g))
		# Barricades either side of the road outside: a log on stakes
		for s in [-1.0, 1.0]:
			var mid: Vector2 = c + out * (RADIUS + 70) + n * s * (Road.ROAD_WIDTH / 2 + 55)
			b.stand(Structures.timber_log(64, 4.5, n.angle()), mid.x, mid.y)
			for t in [-24.0, 0.0, 24.0]:
				var stake: Vector2 = mid + n * t
				b.stand(Structures.stake(Color("#4a3220")), stake.x, stake.y + 1)
				solids.append(Vector3(stake.x, stake.y, 9))

	# Round the plaza, in the gaps between the gates: the inn first, then the
	# soldiers' tents and cottages
	var ring := _free_angles(gates, 9, randf() * TAU)
	var inn_door := c
	for k in ring.size():
		var a: float = ring[k]
		var at: Vector2 = at_angle.call(a, RING)
		var facing := (c - at).angle() # doors towards the plaza
		if k == 0:
			# The inn, bigger than the cottages, its sign and lantern by the door.
			# At night you can sleep there until dawn.
			var inn := Structures.cottage(facing, false, 62.0, 108.0, 32.0)
			b.stand(inn.g, at.x, at.y, null, {"r": 52, "height": inn.roof + 6})
			for fy in [-36.0, -12.0, 12.0, 36.0]:
				var s: Vector2 = at + Vector2(0, fy).rotated(facing)
				solids.append(Vector3(s.x, s.y, 33))
			inn_door = at + Vector2(31 + 22, 0).rotated(facing)
			var sign_at := at + Vector2(31 + 18, 34).rotated(facing)
			var post := Glow.lantern_post(30)
			var board := Sketch.new()
			var plate := Sketch.round_rect_points(-20, -52, 40, 18, 2)
			board.poly(plate, Color("#a8875c")).poly_stroke(plate, 2, Color("#3d2f25"))
			post.add_child(board)
			post.add_child(Fonts.world_label("Inn", Vector2(0, -43), 14, Color("#2a1f14")))
			b.stand(post, sign_at.x, sign_at.y)
		elif k <= 2:
			var tent_at: Vector2 = at_angle.call(a, RING + 20)
			b.stand(Structures.lean_to(facing, Color("#b8a47e")), tent_at.x, tent_at.y, null, {"r": 30, "height": 40})
			solids.append(Vector3(tent_at.x, tent_at.y, 24))
			var crate := tent_at + Vector2.from_angle(a + PI / 2) * 40
			b.stand(Structures.crate(14), crate.x, crate.y)
			solids.append(Vector3(crate.x, crate.y, 10))
		else:
			Raids.house(b, at, facing)
			for fy in [-24.0, 0.0, 24.0]:
				var s: Vector2 = at + Vector2(0, fy).rotated(facing)
				solids.append(Vector3(s.x, s.y, 31))

	# The market nearer in: a blacksmith and a general store, each with its
	# crossbowman, and a well. (Side towns, off the road north, keep more and
	# better stock.)
	var metres := RoadNet.metres_at(c.y)
	var rich: bool = town.side != "c"
	var stock := Destinations._stock_for(metres + (600.0 if rich else 0.0))
	for k in (4 if rich else 2):
		stock.smith.append({"kind": "gear", "item": Items.roll_item(metres + (900.0 if rich else 0.0)), "price": 0})
	for offer in stock.smith:
		offer.price = offer.item.tier * 10 + randi_range(0, 4)
	var inner := _free_angles(gates, 6, ring[0] + PI if not ring.is_empty() else 0.0, 0.5)
	var traders := []
	var stalls := [["Blacksmith", stock.smith, Color("#7d8590"), "smith"], ["General store", stock.store, Color("#c0392b"), "merchant"]]
	for k in mini(stalls.size(), inner.size()):
		var st: Array = stalls[k]
		var a: float = inner[k]
		var at: Vector2 = at_angle.call(a, INNER + 22)
		var to_plaza := (c - at).angle()
		b.stand(Structures.stall(to_plaza, st[2]), at.x, at.y)
		solids.append(Vector3(at.x, at.y, 14))
		traders.append(Destinations._make_trader(b, at_angle.call(a, INNER - 10), to_plaza, st[0], st[1], st[3]))
		guards.append(Destinations.guard(b, at + Vector2.from_angle(a + PI / 2) * 34, to_plaza))
	var spots := inner.slice(stalls.size())
	var well_at: Vector2 = at_angle.call(spots[0] if spots.size() > 0 else 0.0, INNER)
	b.stand(Structures.well(), well_at.x, well_at.y, null, {"r": 14, "height": 44})
	solids.append(Vector3(well_at.x, well_at.y, 16))
	var flag: Vector2 = at_angle.call(spots[1] if spots.size() > 1 else PI, INNER + 30)
	b.stand(banner(84, false), flag.x, flag.y)
	Loot.add_prop(b, "barrel", well_at + Vector2(24, 8), 8)

	# Someone by the inn looking for work: an archer who'll ride with you and
	# defend the cart. The very first town's comes along for nothing; later
	# ones want paying.
	var hirelings := []
	var hire_at := inn_door + (c - inn_door).normalized() * 40 + (c - inn_door).normalized().orthogonal() * 30
	var hand := Folk.new(Companion.KINDS.archer.look, hire_at.x, hire_at.y, (c - hire_at).angle(), 0)
	hand.rig.offhand = "bow"
	b.stand(hand, hire_at.x, hire_at.y)
	solids.append(Vector3(hire_at.x, hire_at.y, 8))
	hirelings.append({"kind": "archer", "who": Companion.NAMES[(town.number * 3 + randi() % 3) % Companion.NAMES.size()],
		"price": 0 if town.number == 0 else 20 + 15 * town.number, "x": hire_at.x, "y": hire_at.y, "figure": hand, "hired": false})

	# Townsfolk about the plaza, and spearmen on their rounds
	for n in 6:
		var spot: Vector2 = at_angle.call(randf() * TAU, randf_range(60, 170))
		var v := Folk.new(Folk.look(), spot.x, spot.y, (c - spot).angle(), 24)
		b.stand(v, spot.x, spot.y)
		folk.append(v)
	for n in 2:
		var spot: Vector2 = at_angle.call(randf() * TAU, 150)
		var walker := Folk.spearman(spot.x, spot.y, randf() * TAU, 80)
		b.stand(walker, spot.x, spot.y)
		folk.append(walker)

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
		"town": {"name": town.name, "safe": Vector3(c.x, c.y, RADIUS), "inn": inn_door, "id": town.id, "kind": town.kind,
			"zone": town.zone, "side": town.side},
	}
