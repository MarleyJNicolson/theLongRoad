class_name Destinations
extends RefCounted

# The big places at the end of side roads (port of encounters/destinations.js).
# Each builder gets the spot the side road arrives at and returns the
# encounter's contents.

const DEST_RADIUS := 240.0

const VILLAGES := ["Millbrook", "Ashford", "Hollowmere", "Thornby", "Wexley", "Barrowfield", "Oakhurst", "Fenwick", "Dunmere", "Coldharbour"]
const STRONGHOLDS := ["Redhand Stronghold", "The Crow’s Nest", "Blackfen Hold", "Gallows Keep", "Cutthroat Hold"]
const WARCAMPS := ["Gorefang Warcamp", "Skullpile Warcamp", "Grimtusk Camp", "The Bonepit", "Rotjaw Warcamp"]


static func _pick(arr: Array) -> Variant:
	return arr[randi() % arr.size()]


static func make(kind: String, b: Build, c: Vector2, entrance: float, metres: float, faction: String) -> Dictionary:
	match kind:
		"raided_village": return _raided_village(b, c, entrance, metres, faction)
		"bandit_stronghold": return _bandit_stronghold(b, c, entrance, metres / 1000.0)
		"goblin_warcamp": return _goblin_warcamp(b, c, entrance, metres / 1000.0)
	return _friendly_village(b, c, entrance, metres)


# --- Shared pieces -------------------------------------------------------

static func _ring(b: Build, c: Vector2, r: float, colour: Color, alpha := 0.55) -> void:
	var patch := b.merged(alpha)
	for k in 9:
		var a := float(k) / 9 * TAU
		patch.circle(c + Vector2(cos(a), sin(a)) * r * 0.45, r * 0.62, colour)


# Spread `count` things evenly round a circle, skipping the entrance:
# [{ a, at }] with `at` relative to the centre.
static func _around(count: int, radius: float, entrance: float, gap := 0.7, jitter := 0.15) -> Array:
	var spots := []
	var span := TAU - gap * 2
	for k in count:
		var a := entrance + gap + span * (k + 0.5) / count + randf_range(-jitter, jitter)
		spots.append({"a": a, "at": Vector2(cos(a), sin(a)) * radius})
	return spots


# A ring of sharpened stakes with a gate toward the side road.
static func _palisade(b: Build, c: Vector2, radius: float, entrance: float, colour: Color, solids: Array, skulls := false) -> void:
	var steps := floori(TAU * radius / 10)
	for k in steps:
		var a := float(k) / steps * TAU
		if absf(wrapf(a - entrance, -PI, PI)) < 0.32:
			continue
		var at := c + Vector2(cos(a), sin(a)) * radius
		b.stand(Structures.stake(colour, skulls and k % 10 == 0), at.x, at.y)
		if k % 2 == 0:
			solids.append(Vector3(at.x, at.y, 9))
	# Gate posts
	for s in [-1.0, 1.0]:
		var a: float = entrance + s * 0.34
		var post := Structures.stake(Color("#4a3220"))
		post.scale = Vector2(1.5, 1.5)
		var at := c + Vector2(cos(a), sin(a)) * radius
		b.stand(post, at.x, at.y)


static func _add_sign(b: Build, at: Vector2, text: String, hostile: bool) -> void:
	var sign := Node2D.new()
	var g := Sketch.new()
	g.line(Vector2(0, 6), Vector2(0, -14), 3, Color("#5e3f22"))
	var board := Sketch.round_rect_points(-100, -46, 200, 32, 3)
	g.poly(board, Color("#7a4a3a") if hostile else Color("#a8875c"))
	g.poly_stroke(board, 3, Color("#3d2f25"))
	sign.add_child(g)
	sign.add_child(Fonts.world_label(text, Vector2(0, -30), 20, Color("#f3e3c0") if hostile else Color("#2a1f14")))
	b.stand(sign, at.x, at.y)


# Flames and smoke rising off roofs: `spots` are [at (world, on the roof),
# depth (to sort them at, just in front of their house)]. Returns
# { animate(time, dt), douse() }.
static func _burning(b: Build, spots: Array) -> Dictionary:
	var fires := []
	var deepest := 0.0
	for spot in spots:
		var at: Vector2 = spot[0]
		var flame := b.stand(Structures.flames(), at.x, at.y, spot[1])
		flame.add_child(Glow.light(90, Color("#ff8a2c"), 1.0))
		fires.append({"g": flame, "at": at, "seed": randf_range(0, 10)})
		deepest = maxf(deepest, spot[1])
	var smoke := b.stand(Node2D.new(), 0, 0, deepest + 1)
	var puffs := []
	var state := {"next_puff": 0.0, "dousing": false}
	var animate := func(time: float, dt: float) -> void:
		for f in fires:
			if state.dousing:
				f.g.modulate.a = maxf(0.0, f.g.modulate.a - dt * 0.5)
			f.g.scale = Vector2(1.3 + sin(time * 7 + f.seed) * 0.1, 1.3 + sin(time * 15 + f.seed) * 0.2 + sin(time * 6 + f.seed) * 0.12)
			f.g.skew = sin(time * 4 + f.seed) * 0.15
		if time > state.next_puff and not fires.is_empty() and fires[0].g.modulate.a > 0.1:
			var src: Dictionary = _pick(fires)
			var puff := Sketch.new().circle(Vector2.ZERO, 9, Color("#5a5550", 0.5))
			puff.position = src.at - Vector2(0, 14)
			smoke.add_child(puff)
			puffs.append({"g": puff, "life": 0.0})
			state.next_puff = time + 0.15
		Raids._drift_smoke(puffs, dt)
	var douse := func() -> void: state.dousing = true
	return {"animate": animate, "douse": douse}


# --- Traders ---------------------------------------------------------------

static func _make_trader(b: Build, at: Vector2, facing: float, trader_name: String, stock: Array, role: String) -> Dictionary:
	var figure := Folk.new(Folk.look(role), at.x, at.y, facing)
	b.stand(figure, at.x, at.y)
	return {"name": trader_name, "x": at.x, "y": at.y, "stock": stock, "figure": figure, "open": true}


# What a village sells. Gear is one of a kind; everything else is endless.
static func _stock_for(metres: float) -> Dictionary:
	var smith := []
	for k in 4:
		var item := Items.roll_item(metres)
		smith.append({"kind": "gear", "item": item, "price": item.tier * 10 + randi_range(0, 4)})
	var store := [
		{"kind": "consumable", "type": "poultice", "price": 6},
		{"kind": "consumable", "type": "planks", "price": 6},
		{"kind": "consumable", "type": "arrows", "qty": 15, "price": 9},
		{"kind": "consumable", "type": "bolts", "qty": 10, "price": 10},
		{"kind": "consumable", "type": "stones", "qty": 30, "price": 3},
		{"kind": "service", "type": "repair", "name": "Mend the cart fully", "price": 2, "per": "cart point"},
		{"kind": "service", "type": "heal", "name": "See the healer", "price": 4, "per": "heart"},
	]
	return {"smith": smith, "store": store}


# --- Villages --------------------------------------------------------------

static func _village(b: Build, c: Vector2, entrance: float, metres: float, raid: bool) -> Dictionary:
	var village_name: String = _pick(VILLAGES)
	_ring(b, c, DEST_RADIUS * 0.9, Color("#a89466"), 0.45)
	b.g.circle(c, 70, Color("#b9a57a", 0.7)) # the square

	var solids := []
	var roofs := []
	for spot in _around(5, 150, entrance, 0.55):
		var h: Vector2 = c + spot.at
		var facing: float = spot.a + PI # door toward the square
		var charred := raid and randf() < 0.6
		var roof := Raids.house(b, h, facing, charred)
		for fy in [-24.0, 0.0, 24.0]:
			var s: Vector2 = h + Vector2(0, fy).rotated(facing)
			solids.append(Vector3(s.x, s.y, 31))
		if charred:
			for k in 2:
				var at: Vector2 = h + Vector2(randf_range(-10, 10), randf_range(-22, 22)).rotated(facing)
				roofs.append([Vector2(at.x, at.y - (roof - randf_range(2, 10))), h.y + 30])
	# The well
	b.stand(Structures.well(), c.x, c.y, null, {"r": 14, "height": 44})
	solids.append(Vector3(c.x, c.y, 16))

	# Two market stalls on the square: the smith and the general store
	var stock := _stock_for(metres)
	var traders := []
	var stall_spots := _around(2, 52, entrance + PI / 2, 0.2, 0)
	var stalls := [["Blacksmith", stock.smith, Color("#7d8590"), "smith"], ["General store", stock.store, Color("#c0392b"), "merchant"]]
	for k in 2:
		var a: float = stall_spots[k].a
		var at := c + Vector2(cos(a), sin(a)) * 52
		b.stand(Structures.stall(a + PI, stalls[k][2]), at.x, at.y)
		solids.append(Vector3(at.x, at.y, 14))
		traders.append(_make_trader(b, c + Vector2(cos(a), sin(a)) * 70, a + PI, stalls[k][0], stalls[k][1], stalls[k][3]))

	# Villagers about the square
	var villagers := []
	for spot in _around(4, 95, entrance, 0.4, 0.4):
		var at: Vector2 = c + spot.at
		var v := Folk.new(Folk.look(), at.x, at.y, spot.a + PI, 22)
		b.stand(v, at.x, at.y)
		villagers.append(v)

	_add_sign(b, c + Vector2(cos(entrance), sin(entrance)) * (DEST_RADIUS - 20), village_name, false)
	var fire: Variant = _burning(b, roofs) if raid else null

	# While raided, the villagers are hiding and the stalls are shut.
	var set_peace := func(peaceful: bool) -> void:
		for t in traders:
			t.open = peaceful
			t.figure.visible = peaceful
		for v in villagers:
			v.visible = peaceful
	# Once freed, they come out cheering
	var state := {"cheering": false, "until": -1.0}
	var cheer := func() -> void:
		set_peace.call(true)
		for v in villagers:
			v.waving(true)
		state.cheering = true
	set_peace.call(not raid)

	var animate := func(time: float, dt: float) -> void:
		if fire:
			fire.animate.call(time, dt)
		for v in villagers:
			v.update(dt)
		for t in traders:
			t.figure.update(dt)
		if state.cheering:
			if state.until < 0:
				state.until = time + 6
			elif time > state.until:
				for v in villagers:
					v.waving(false)
				state.cheering = false
	var douse := func() -> void:
		if fire:
			fire.douse.call()
	return {"name": village_name, "solids": solids, "traders": traders, "cheer": cheer, "animate": animate, "douse": douse}


static func _friendly_village(b: Build, c: Vector2, entrance: float, metres: float) -> Dictionary:
	var v := _village(b, c, entrance, metres, false)
	return {
		"title": "%s – traders" % v.name,
		"hostile": false,
		"members": [],
		"solids": v.solids,
		"traders": v.traders,
		"loot": [],
		"animate": v.animate,
	}


static func _raided_village(b: Build, c: Vector2, entrance: float, metres: float, faction: String) -> Dictionary:
	var km := metres / 1000.0
	var v := _village(b, c, entrance, metres, true)
	var members := []
	var wander := {"x": c.x, "y": c.y, "min": 20.0, "max": 110.0}
	var small := "goblin" if faction == "goblin" else "bandit"
	var big := "orc" if faction == "goblin" else "brute"
	for k in mini(14, 6 + b.extra * 2):
		var a := randf() * TAU
		members.append(b.enemies.add(small, c.x + cos(a) * 80, c.y + sin(a) * 80, {"x": c.x, "y": c.y, "wander": wander}))
	for k in mini(4, 1 + floori(km / 4)):
		members.append(b.enemies.add(big, c.x + randf_range(-40, 40), c.y + randf_range(-40, 40), {"x": c.x, "y": c.y, "wander": wander}))
	var loot := []
	Loot.maybe_add_chest(loot, b, c + Vector2(randf_range(-30, 30), 110), 1)
	var douse: Callable = v.douse
	var cheer: Callable = v.cheer
	var on_cleared := func() -> void:
		douse.call()
		cheer.call()
	return {
		"title": "%s – under attack!" % v.name,
		"hostile": true,
		"members": members,
		"solids": v.solids,
		"traders": v.traders,
		"loot": loot,
		"trigger_radius": 380.0,
		"reward": {"gold": 15 + floori(km * 2), "x": c.x, "y": c.y, "message": "The people of %s reward you" % v.name},
		"on_cleared": on_cleared,
		"animate": v.animate,
	}


# --- Bandit stronghold -----------------------------------------------------

static func _bandit_stronghold(b: Build, c: Vector2, entrance: float, km: float) -> Dictionary:
	_ring(b, c, DEST_RADIUS * 0.85, Color("#8a7f55"))
	var solids := []
	_palisade(b, c, 200, entrance, Color("#6e4a28"), solids)

	for spot in _around(4, 130, entrance, 0.6):
		var at: Vector2 = c + spot.at
		b.stand(Structures.lean_to(spot.a + PI), at.x, at.y, null, {"r": 28, "height": 36})
		solids.append(Vector3(at.x, at.y, 22))
	var towers := []
	for s in [-0.6, 0.6]:
		var a: float = entrance + s
		var at := c + Vector2(cos(a), sin(a)) * 168
		var to_yard := (c - at).angle()
		b.stand(Structures.watchtower(to_yard).g, at.x, at.y, null, {"r": 20, "height": 56})
		solids.append(Vector3(at.x, at.y, 20))
		# Archers keep watch at the foot of the ladder
		towers.append(at + Vector2(cos(to_yard), sin(to_yard)) * 26)
	var flicker := b.campfire(c.x, c.y)
	solids.append(Vector3(c.x, c.y, 16))

	# Their hoard, piled at the back
	var loot := []
	var back := entrance + PI
	for s in [-0.35, 0.0, 0.35]:
		Loot.maybe_add_chest(loot, b, c + Vector2(cos(back + s), sin(back + s)) * 95, 1)
	Loot.add_prop(b, "crate", c + Vector2(cos(back), sin(back)) * 125)
	Loot.add_prop(b, "barrel", c + Vector2(cos(back + 0.2), sin(back + 0.2)) * 128)

	var members := []
	for t: Vector2 in towers:
		members.append(b.enemies.add("archer", t.x, t.y, {"x": t.x, "y": t.y, "facing": entrance}))
	var yard := {"x": c.x, "y": c.y, "min": 30.0, "max": 120.0}
	for k in mini(16, 6 + b.extra * 2 + floori(km)):
		var a := randf() * TAU
		members.append(b.enemies.add("bandit", c.x + cos(a) * 70, c.y + sin(a) * 70, {"x": c.x, "y": c.y, "wander": yard}))
	for k in mini(5, 2 + floori(km / 3)):
		var a := entrance + randf_range(-0.4, 0.4)
		var at := c + Vector2(cos(a), sin(a)) * 120
		members.append(b.enemies.add("brute", at.x, at.y, {"x": at.x, "y": at.y, "facing": entrance}))
	var captain := c + Vector2(cos(back), sin(back)) * 60
	members.append(b.enemies.add("captain", captain.x, captain.y, {"x": c.x, "y": c.y, "facing": entrance}))
	if km > 5:
		members.append(b.enemies.add("captain", c.x, c.y + 40, {"x": c.x, "y": c.y, "facing": entrance}))

	return {
		"title": _pick(STRONGHOLDS),
		"hostile": true,
		"members": members,
		"solids": solids,
		"loot": loot,
		"trigger_radius": 430.0,
		"reward": {"gold": 20 + floori(km * 3), "x": c.x, "y": c.y, "message": "The stronghold has fallen"},
		"animate": flicker,
	}


# --- Goblin warcamp ----------------------------------------------------------

static func _goblin_warcamp(b: Build, c: Vector2, entrance: float, km: float) -> Dictionary:
	_ring(b, c, DEST_RADIUS * 0.85, Color("#6f6a3a"))
	var solids := []
	_palisade(b, c, 200, entrance, Color("#3a2a1a"), solids, true)

	for spot in _around(5, 130, entrance, 0.6):
		var at: Vector2 = c + spot.at
		b.stand(Structures.hide_tent(spot.a + PI), at.x, at.y, null, {"r": 24, "height": 48})
		solids.append(Vector3(at.x, at.y, 22))
	# Cages for their captives
	for s in [-0.9, 0.9]:
		var a: float = entrance + PI + s
		var at := c + Vector2(cos(a), sin(a)) * 80
		b.stand(Structures.cage(), at.x, at.y)
		solids.append(Vector3(at.x, at.y, 14))
	b.scatter_bones(c, Vector2(140, 140), 18)
	for s in [-0.5, 0.5]:
		var at := c + Vector2(cos(entrance + s), sin(entrance + s)) * 215
		b.stand(Structures.skull_totem(), at.x, at.y)
	var flicker := b.campfire(c.x, c.y)
	solids.append(Vector3(c.x, c.y, 16))

	var loot := []
	var back := entrance + PI
	for s in [-0.3, 0.3, 0.0]:
		Loot.maybe_add_chest(loot, b, c + Vector2(cos(back + s), sin(back + s)) * 100, 0.6 if s == 0.0 else 1.0)

	var members := []
	var yard := {"x": c.x, "y": c.y, "min": 30.0, "max": 125.0}
	for k in mini(18, 8 + b.extra * 2 + floori(km)):
		var a := randf() * TAU
		members.append(b.enemies.add("goblin", c.x + cos(a) * 80, c.y + sin(a) * 80, {"x": c.x, "y": c.y, "wander": yard}))
	for k in mini(5, 2 + floori(km / 3)):
		var a := randf() * TAU
		members.append(b.enemies.add("orc", c.x + cos(a) * 50, c.y + sin(a) * 50, {"x": c.x, "y": c.y, "wander": {"x": c.x, "y": c.y, "min": 10.0, "max": 60.0}}))

	return {
		"title": _pick(WARCAMPS),
		"hostile": true,
		"members": members,
		"solids": solids,
		"loot": loot,
		"trigger_radius": 430.0,
		"reward": {"gold": 20 + floori(km * 3), "x": c.x, "y": c.y, "message": "The warcamp is broken"},
		"animate": flicker,
	}
