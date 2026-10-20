class_name Raids
extends RefCounted

# Farms under attack (port of encounters/raids.js), and the cottages, fences
# and farmer that villages share.

const REWARD := 5 # gold the grateful farmer gives for driving the raiders off


# A fence from a to b, stood up in short runs so each sorts properly against
# whoever is beside it.
static func fence_line(b: Build, a: Vector2, c: Vector2, broken := false) -> void:
	var runs := maxi(1, roundi(a.distance_to(c) / 36))
	for k in runs:
		var p := a.lerp(c, float(k) / runs)
		var q := a.lerp(c, float(k + 1) / runs)
		b.stand(Structures.fence(Vector2.ZERO, q - p, broken), p.x, p.y, (p.y + q.y) / 2)


# A cottage at `at` with its door towards `facing`; returns how tall it is.
static func house(b: Build, at: Vector2, facing: float, charred := false) -> float:
	var built := Structures.cottage(facing, charred)
	b.stand(built.g, at.x, at.y, null, {"r": 40, "height": built.roof + 6})
	return built.roof


# The farmer, who comes out to thank you once the raiders are gone.
static func make_farmer(b: Build, at: Vector2, facing: float) -> Folk:
	var farmer := Folk.new(Folk.look("farmer"), at.x, at.y, facing)
	b.stand(farmer, at.x, at.y)
	farmer.visible = false
	return farmer


# A thatched farmhouse in its fenced yard, set back from the road. `farm.pt`
# maps house-local coordinates (+x towards the road) to world coordinates; the
# vegetable rows and path go on the ground, the house and fence stand.
static func _draw_farmstead(b: Build, farm: Dictionary, broken_fence: bool, charred: bool) -> float:
	var pt: Callable = farm.pt
	# Vegetable rows behind the house
	for row in 4:
		for k in range(-3, 4):
			b.g.ellipse(pt.call(-50 - row * 9, k * 9), 3.5, 2.5, Color("#4f8a38"))
	# Fence round the plot, with a gap for the gate facing the road
	for side in [[-88, -62, 50, -62], [-88, 62, 50, 62], [-88, -62, -88, 62], [50, -62, 50, -16], [50, 16, 50, 62]]:
		fence_line(b, pt.call(side[0], side[1]), pt.call(side[2], side[3]), broken_fence)
	# Path from the door to the gate
	b.g.poly(PackedVector2Array([pt.call(28, -7), pt.call(50, -7), pt.call(50, 7), pt.call(28, 7)]), Color("#b9925e", 0.8))
	return house(b, pt.call(0, 0), farm.facing, charred)


# A homestead beside the road, or out in the wilds at the end of a cart track
# (`deep`).
static func _set_up_farm(b: Build) -> Variant:
	var spot: Variant = b.set_back(Road.ROAD_WIDTH / 2 + 130, 170)
	if spot == null:
		return null
	var side: float = spot.side
	var f := b.frame()
	var h := Vector2(spot.x, spot.y)
	var facing := (-f.n * side).angle()
	var pt := func(fx: float, fy: float) -> Vector2: return h + Vector2(fx, fy).rotated(facing)
	var solids := []
	for fy in [-24.0, 0.0, 24.0]:
		var s: Vector2 = pt.call(0, fy)
		solids.append(Vector3(s.x, s.y, 31))
	var yard: Vector2 = pt.call(70, 0) # the yard between house and road
	var road_at := f.at(0, 0)
	# Where the raid is noticed: from the road if it's beside it, else close by
	var trigger := Vector3(yard.x, yard.y, 320) if spot.deep else Vector3(road_at.x, road_at.y, 380)
	return {"pt": pt, "h": h, "yard": yard, "facing": facing, "solids": solids, "deep": spot.deep,
		"edge": f.at(0, side * Road.ROAD_WIDTH / 2), "trigger": trigger}


# The cart track out to a farm in the wilds (zones to keep trees off it).
static func _farm_track(b: Build, farm: Dictionary) -> Array:
	return b.footpath(farm.edge, farm.pt.call(58, 0), Color("#9a8254")) if farm.deep else []


static func _farmer_reward(b: Build, farm: Dictionary) -> Dictionary:
	var at: Vector2 = farm.pt.call(40, 0)
	var farmer := make_farmer(b, at, farm.facing)
	var on_cleared := func() -> void:
		farmer.visible = true
		farmer.waving(true)
	var wave := func(_time: float, dt: float) -> void: farmer.update(dt)
	return {"reward": {"gold": REWARD, "x": at.x, "y": at.y}, "on_cleared": on_cleared, "wave": wave}


# Bandit house raid: the door kicked in, the family's goods hauled out to a
# waiting cart, and bandits picking over the yard.
static func bandit_raid(b: Build) -> Variant:
	var farm: Variant = _set_up_farm(b)
	if farm == null:
		return null
	var pt: Callable = farm.pt
	var track := _farm_track(b, farm)
	_draw_farmstead(b, farm, false, false)
	# Broken door planks on the step
	b.g.round_stroke(PackedVector2Array([pt.call(34, -6), pt.call(44, -12)]), 4, Color("#6e4a28"))
	b.g.round_stroke(PackedVector2Array([pt.call(36, 4), pt.call(46, 10)]), 4, Color("#6e4a28"))
	# Loot heaped in the yard and a bandit cart to carry it off
	for c in [Vector2(62, -26), Vector2(70, -18), Vector2(58, -14)]:
		b.g.ellipse(pt.call(c.x, c.y), 7, 6, Color("#c9b28a"))
	var k: Vector2 = pt.call(99, -25)
	b.stand(Structures.loot_cart(farm.facing + PI / 2), k.x, k.y)
	var loot := []
	Loot.add_prop(b, "crate", pt.call(66, 26), 15)
	Loot.add_prop(b, "barrel", pt.call(80, 34), 7)
	Loot.maybe_add_chest(loot, b, pt.call(60, -40), Build.DEEP_CHEST_CHANCE if farm.deep else Loot.CHEST_CHANCE) # the family strongbox, dragged out

	var thanks := _farmer_reward(b, farm)
	var yard: Vector2 = farm.yard
	var wander := {"x": yard.x, "y": yard.y, "min": 10.0, "max": 42.0}
	var members := []
	for n in mini(6 + b.extra, 3 + floori(b.difficulty)):
		var a := randf() * TAU
		members.append(b.enemies.add("bandit", yard.x + cos(a) * 30, yard.y + sin(a) * 30, {"x": yard.x, "y": yard.y, "wander": wander}))
	if b.difficulty >= 1.5 and randf() < 0.5:
		var at: Vector2 = pt.call(50, 0)
		members.append(b.enemies.add("captain", at.x, at.y, {"x": at.x, "y": at.y, "facing": farm.facing}))

	return {
		"members": members,
		"solids": farm.solids + [Vector3(k.x, k.y, 18)],
		"loot": loot,
		"zones": [Vector3(farm.h.x, farm.h.y, 170)] + track,
		"trigger": farm.trigger,
		"reward": thanks.reward,
		"on_cleared": thanks.on_cleared,
		"animate": thanks.wave,
	}


# Goblin house raid: the thatch is ablaze, smoke pours off the roof and the
# goblins caper round the yard, whooping.
static func goblin_raid(b: Build) -> Variant:
	var farm: Variant = _set_up_farm(b)
	if farm == null:
		return null
	var pt: Callable = farm.pt
	var h: Vector2 = farm.h
	var track := _farm_track(b, farm)
	var roof := _draw_farmstead(b, farm, true, true)
	# Torches dropped in the yard
	for c in [Vector2(60, -30), Vector2(74, 22)]:
		b.g.round_stroke(PackedVector2Array([pt.call(c.x, c.y), pt.call(c.x + 10, c.y + 4)]), 3, Color("#5e3f22"))
		b.g.circle(pt.call(c.x + 10, c.y + 4), 3, Color("#e8641e"))

	# Flames along the thatch, drawn in front of the house; smoke above all
	var fires := []
	for n in randi_range(3, 4):
		var at: Vector2 = pt.call(randf_range(-14, 14), randf_range(-28, 28))
		var top := at.y - roof + randf_range(2, 10)
		var flame := b.stand(Structures.flames(), at.x, top, h.y + 30)
		flame.scale = Vector2.ONE * 1.3
		flame.add_child(Glow.light(90, Color("#ff8a2c"), 1.0))
		fires.append({"g": flame, "at": Vector2(at.x, top), "seed": randf_range(0, 10)})
	var glow := Sketch.new().circle(Vector2.ZERO, 110, Color("#ff8a2c", 0.14))
	glow.position = h
	var smoke := b.stand(Node2D.new(), 0, 0, h.y + 31)
	var loot := []
	Loot.add_prop(b, "barrel", pt.call(64, 34), 8)
	Loot.maybe_add_chest(loot, b, pt.call(-60, -50), Build.DEEP_CHEST_CHANCE if farm.deep else Loot.CHEST_CHANCE) # buried in the vegetable patch
	b.layer.add_child(glow)

	var thanks := _farmer_reward(b, farm)
	var yard: Vector2 = farm.yard
	var wander := {"x": yard.x, "y": yard.y, "min": 12.0, "max": 50.0}
	var members := []
	for n in mini(8 + b.extra, 4 + floori(b.difficulty * 1.5)):
		var a := randf() * TAU
		members.append(b.enemies.add("goblin", yard.x + cos(a) * 35, yard.y + sin(a) * 35, {"x": yard.x, "y": yard.y, "wander": wander}))

	var puffs := []
	var state := {"next_puff": 0.0}
	var wave: Callable = thanks.wave
	var animate := func(time: float, dt: float) -> void:
		wave.call(time, dt)
		for fire in fires:
			fire.g.scale = Vector2(1.3 + sin(time * 7 + fire.seed) * 0.1, 1.3 + sin(time * 15 + fire.seed) * 0.2 + sin(time * 6 + fire.seed) * 0.12)
			fire.g.skew = sin(time * 4 + fire.seed) * 0.15
		glow.modulate.a = 0.85 + sin(time * 9) * 0.15
		# Smoke drifts off the roof, swelling and thinning as it goes.
		if time > state.next_puff:
			var src: Dictionary = fires[randi() % fires.size()]
			var puff := Sketch.new().circle(Vector2.ZERO, 9, Color("#5a5550", 0.5))
			# (the smoke node sorts at h.y + 31 but its origin is the world's)
			puff.position = src.at - Vector2(0, 14)
			smoke.add_child(puff)
			puffs.append({"g": puff, "life": 0.0})
			state.next_puff = time + 0.12
		_drift_smoke(puffs, dt)
	return {
		"members": members,
		"solids": farm.solids,
		"loot": loot,
		"zones": [Vector3(h.x, h.y, 170)] + track,
		"trigger": farm.trigger,
		"reward": thanks.reward,
		"on_cleared": thanks.on_cleared,
		"animate": animate,
	}


# Smoke off burning roofs: drifting, swelling and thinning as it goes.
static func _drift_smoke(puffs: Array, dt: float) -> void:
	for k in range(puffs.size() - 1, -1, -1):
		var p: Dictionary = puffs[k]
		p.life += dt
		if not is_instance_valid(p.g):
			puffs.remove_at(k)
			continue
		p.g.position += Vector2(22, -30) * dt
		p.g.scale = Vector2.ONE * (1 + p.life * 1.4)
		p.g.modulate.a = maxf(0.0, 1 - p.life / 2.6)
		if p.life > 2.6:
			p.g.queue_free()
			puffs.remove_at(k)
