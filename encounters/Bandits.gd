class_name Bandits
extends RefCounted

# Bandit encounters (port of encounters/bandits.js). Each builder returns the
# encounter (see Encounters.place), or null if it doesn't fit here.


# Bandit camp: canvas lean-tos round a fire, stolen loot piled up, and a
# watchtower by the road whose lookout raises the alarm from far off. Out in
# the wilds, the camp is found by its smoke or the path to it, and the lookout
# watches the path instead of the road.
static func camp(b: Build) -> Variant:
	var offset := Road.ROAD_WIDTH / 2 + 150
	var spot: Variant = b.set_back(offset, 200)
	if spot == null:
		return null
	var side: float = spot.side
	var f := b.frame()
	var c := Vector2(spot.x, spot.y)
	# Positions around the camp: `along` the road's direction, `out` away from it
	var at_camp := func(along: float, out: float) -> Vector2: return c + f.d * along + f.n * side * out
	var edge := f.at(0, side * Road.ROAD_WIDTH / 2)

	b.draw_clearing(c, null if spot.deep else edge, Color("#8a7f55"))
	var path: Array = b.footpath(edge, c) if spot.deep else []

	var solids := [Vector3(c.x, c.y, 16)]
	var start := randf() * TAU
	var tents := randi_range(2, 3)
	for k in tents:
		var a := start + float(k) / tents * TAU
		var t := c + Vector2(cos(a) * 95, sin(a) * 82)
		b.stand(Structures.lean_to(a + PI), t.x, t.y, null, {"r": 28, "height": 36})
		solids.append(Vector3(t.x, t.y, 22))
	# Log benches round the fire
	for k in 3:
		var a := start + PI / tents + float(k) / 3 * TAU
		var bench := c + Vector2(cos(a), sin(a)) * 42
		b.stand(Structures.timber_log(28, 4.5, a + PI / 2), bench.x, bench.y)
	# Stolen goods
	var ch: Vector2 = at_camp.call(randf_range(-60, -30), 60)
	var loot := []
	Loot.maybe_add_chest(loot, b, ch, Build.DEEP_CHEST_CHANCE if spot.deep else Loot.CHEST_CHANCE)
	Loot.add_prop(b, "crate", ch + Vector2(22, 6), 15)
	Loot.add_prop(b, "barrel", ch + Vector2(-20, 10), 8)
	solids.append(Vector3(ch.x, ch.y, 12))
	var flicker := b.campfire(c.x, c.y)

	var tw: Vector2 = at_camp.call(40, -125.0 if spot.deep else -(offset - Road.ROAD_WIDTH / 2 - 55))
	var to_camp := (c - tw).angle()
	b.stand(Structures.watchtower(to_camp).g, tw.x, tw.y, null, {"r": 20, "height": 56})
	solids.append(Vector3(tw.x, tw.y, 20))

	# The lookout keeps watch at the foot of the ladder
	var lookout := tw + Vector2(cos(to_camp), sin(to_camp)) * 26
	var members := [b.enemies.add("archer", lookout.x, lookout.y, {"x": lookout.x, "y": lookout.y, "facing": to_camp + PI})]
	for k in mini(5 + b.extra, 2 + floori(b.difficulty)):
		var a := randf() * TAU
		var p := c + Vector2(cos(a), sin(a)) * 32
		members.append(b.enemies.add("bandit", p.x, p.y, {"x": p.x, "y": p.y, "facing": a + PI}))
	if b.difficulty >= 1 or randf() < 0.35:
		var p: Vector2 = at_camp.call(-20, 20)
		members.append(b.enemies.add("captain", p.x, p.y, {"x": p.x, "y": p.y, "facing": (c - p).angle()}))

	return {
		"members": members,
		"solids": solids,
		"loot": loot,
		"zones": [Vector3(c.x, c.y, 200)] + path,
		"trigger": Vector3(tw.x, tw.y, 360 if spot.deep else 470),
		"animate": flicker,
	}


# Bandit roadblock: a spiked log barricade right across the road. Getting
# round it means leaving the road for the mud while the bandits pile in.
static func roadblock(b: Build) -> Variant:
	var f := b.frame()
	var half := Road.ROAD_WIDTH / 2 + 36

	b.g.capsule(f.at(4, -half), f.at(4, half), 22, Color(0, 0, 0, 0.2))
	# Two logs across the road, overlapping in the middle
	var across := f.n.angle()
	var l1 := f.at(0, (-half + 14) / 2)
	var l2 := f.at(-3, (half - 14) / 2)
	b.stand(Structures.timber_log(half + 14, 8, across), l1.x, l1.y)
	b.stand(Structures.timber_log(half + 14, 8, across), l2.x, l2.y)
	# Sharpened stakes jutting out at oncoming traffic, each stood at its foot
	var ahead := f.d.angle()
	var l := -half + 6
	while l <= half - 6:
		var stake := Sketch.new()
		var foot := Iso.turn(Vector3(-20, randf_range(-3, 3), 0), ahead)
		var tip := Iso.project(Vector3(foot.x, foot.y, 13))
		stake.round_stroke(PackedVector2Array([Vector2(0, -3), tip]), 3.5, Color("#7a5a34"))
		stake.circle(tip, 1.6, Color("#c9b28a"))
		var at := f.at(-6, l)
		b.stand(stake, at.x, at.y)
		l += 13
	var side := Build.side_sign()
	var bx := f.at(36, side * (half + 10))
	var rx := f.at(58, side * (half + 18))
	var loot := []
	Loot.add_prop(b, "crate", bx)
	Loot.add_prop(b, "barrel", rx)
	Loot.maybe_add_chest(loot, b, f.at(46, side * (half + 30))) # the tolls they've taken

	var solids := []
	var s := -half
	while s <= half:
		var at := f.at(0, s)
		solids.append(Vector3(at.x, at.y, 10))
		s += 12
	solids.append(Vector3(bx.x, bx.y, 11))
	solids.append(Vector3(rx.x, rx.y, 9))

	# Bandits wait behind the logs and on the verges, watching the road.
	var facing := (-f.d).angle()
	var posts := [
		Vector2(randf_range(24, 40), randf_range(-30, 30)),
		Vector2(randf_range(-50, -30), -(half + randf_range(20, 40))),
		Vector2(randf_range(-50, -30), half + randf_range(20, 40)),
		Vector2(randf_range(30, 60), randf_range(-40, 40)),
		Vector2(randf_range(50, 80), -(half + randf_range(10, 30))),
	]
	var count := mini(5 + b.extra, 2 + floori(b.difficulty))
	# Any more than that wait further back up the road
	while posts.size() < count:
		posts.append(Vector2(randf_range(60, 120), randf_range(-half - 30, half + 30)))
	var members := []
	for post: Vector2 in posts.slice(0, count):
		var at := f.at(post.x, post.y)
		members.append(b.enemies.add("bandit", at.x, at.y, {"x": at.x, "y": at.y, "facing": facing}))

	var m := f.at(0, 0)
	return {
		"members": members,
		"solids": solids,
		"loot": loot,
		"zones": [Vector3(m.x, m.y, half + 130)],
		"trigger": Vector3(m.x, m.y, 430),
	}


# Bandit ambush: bandits crouched in thick roadside bushes. Watch for the
# tells: hoods peeking out, a glint of steel, trampled grass and rustling. A
# stone into a bush will flush them out early.
static func ambush(b: Build) -> Variant:
	var f := b.frame()
	var spots := []
	var members := []
	var count := mini(5 + b.extra, 2 + floori(b.difficulty))
	var sides := [1.0, -1.0] if randf() < 0.5 else [Build.side_sign()]
	var biome: Dictionary = Threat.stage_at(b.metres).biome # bushes blend in with the local scrub
	for k in count:
		var side: float = sides[k % sides.size()]
		var along := float(k) / count * maxf(110, count * 24) + randf_range(-10, 10)
		var r := randf_range(22, 27)
		var at := f.at(along, side * (Road.ROAD_WIDTH / 2 + randf_range(36, 60)))
		# Trampled, darker grass and boot prints leading out of the bush
		b.g.ellipse(at, r + 14, r + 10, Color("#4a6b30", 0.35))
		for s in 4:
			b.g.ellipse(f.at(along + (5 if s % 2 else -5), side * (Road.ROAD_WIDTH / 2 + 6 + s * 9)), 3, 2, Color("#3a2a1a", 0.45))

		var bush := Scenery.bush(r, biome)
		b.stand(bush, at.x, at.y)
		# A hood peeking over the top on the road side, and a blade that catches
		# the light
		var to_road := -f.n * side
		var peek := Sketch.new()
		peek.circle(Vector2.ZERO, 6.5, Color("#2d2a26"))
		peek.circle(Vector2(to_road.x * 2.5, 1), 2.5, Color("#8c2f22"))
		b.stand(peek, at.x + to_road.x * r * 0.45, at.y - r * 1.1, at.y + 0.4)
		var glint := Sketch.new()
		glint.round_stroke(PackedVector2Array([Vector2(-5, 0), Vector2(5, 0)]), 2, Color.WHITE)
		glint.round_stroke(PackedVector2Array([Vector2(0, -5), Vector2(0, 5)]), 2, Color.WHITE)
		glint.circle(Vector2.ZERO, 2, Color.WHITE)
		b.stand(glint, at.x + to_road.x * r * 0.9, at.y - r * 0.6, at.y + 0.5)
		glint.modulate.a = 0.0
		spots.append({"bush": bush, "peek": peek, "glint": glint, "next_glint": randf_range(0.5, 2.5), "glint_start": -9.0})

		members.append(b.enemies.add("bandit", at.x, at.y, {"x": at.x, "y": at.y, "facing": to_road.angle(), "hidden": true}))
	# Their stash, stowed further back from the road
	var loot := []
	Loot.maybe_add_chest(loot, b, f.at(55, sides[0] * (Road.ROAD_WIDTH / 2 + 95)))

	var m := f.at(55, 0)
	var state := {"rustle": randf_range(0.5, 1.5), "shaking": null}
	var animate := func(time: float, dt: float) -> void:
		state.rustle -= dt
		if state.rustle <= 0:
			state.shaking = {"spot": spots[randi() % spots.size()], "until": time + 0.6}
			state.rustle = randf_range(1, 2.5)
		for k in spots.size():
			var spot: Dictionary = spots[k]
			var lurking: bool = members[k].in_hiding
			spot.peek.visible = lurking
			spot.bush.rotation = 0.0
			if state.shaking and state.shaking.spot == spot and time < state.shaking.until and lurking:
				spot.bush.rotation = sin(time * 40) * 0.14
			spot.next_glint -= dt
			if spot.next_glint <= 0 and lurking:
				spot.glint_start = time
				spot.next_glint = randf_range(1.5, 3.5)
			var t: float = time - spot.glint_start
			spot.glint.modulate.a = sin(t / 0.35 * PI) if lurking and t < 0.35 else 0.0
			spot.glint.rotation = t * 3
	return {
		"members": members,
		"solids": [],
		"loot": loot,
		"zones": [Vector3(m.x, m.y, Road.ROAD_WIDTH / 2 + 110)],
		"trigger": Vector3(m.x, m.y, 210),
		"animate": animate,
	}
