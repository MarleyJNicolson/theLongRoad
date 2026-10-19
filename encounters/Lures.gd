class_name Lures
extends RefCounted

# Ambushes out in the wilds, away from the road (port of encounters/lures.js):
# a treasure chest left glinting in a little clearing, there for the taking.
# It's bait. Bandits lie in the thicket round it (or goblins in their burrows)
# and spring out once you're close enough to reach for it. Worth it if you're
# ready: the chest is always there, and well stocked.

const SPRING := 95.0 # how close to the chest before they jump you


static func bandit(b: Build) -> Variant:
	return _lure(b, "bandit")


static func goblin(b: Build) -> Variant:
	return _lure(b, "goblin")


static func _lure(b: Build, faction: String) -> Variant:
	var spot: Variant = b.set_back(Road.ROAD_WIDTH / 2 + 160, 140, true, 260)
	if spot == null:
		return null
	var c := Vector2(spot.x, spot.y)
	var biome: Dictionary = Threat.stage_at(Road.along(b.i) / 20.0).biome

	# A small clearing, and whatever its last visitor left behind
	var clearing := b.merged(0.4)
	for k in 5:
		var a := float(k) / 5 * TAU
		clearing.circle(c + Vector2(cos(a) * 22, sin(a) * 16), randf_range(34, 44), Color("#6f6a3a") if faction == "goblin" else Color("#8a7f55"))
	var loot := []
	Loot.maybe_add_chest(loot, b, c, 1)
	if faction == "goblin":
		b.scatter_bones(c, Vector2(45, 35), 6)
		Loot.add_prop(b, "barrel", c + Vector2(26, -10), 8)
	else:
		# A dead fire, a bedroll and a pack: someone camped here and never left
		b.g.ellipse(c + Vector2(-30, 14), 9, 6, Color("#2a1f14"))
		b.g.ellipse(c + Vector2(24, 18), 9, 4, Color("#6e4a3a"))
		b.stand(Structures.timber_log(26, 4.5, randf() * PI), c.x - 34, c.y - 18)
		Loot.add_prop(b, "crate", c + Vector2(28, -12), 14)

	# Hiding places in a ring round the clearing
	var count := mini(6 + b.extra, 3 + floori(b.difficulty))
	var hides := []
	var members := []
	var start := randf() * TAU
	for k in count:
		var a := start + float(k) / count * TAU + randf_range(-0.2, 0.2)
		var d := randf_range(70, 95)
		var at := c + Vector2(cos(a) * d, sin(a) * d * 0.85)
		var home := {"x": at.x, "y": at.y, "facing": a + PI, "hidden": true}
		if faction == "goblin":
			# A burrow mound with a dark mouth
			b.g.ellipse(at, 17, 13, Color("#7a5c3a"))
			b.g.ellipse(at - Vector2(3, 3), 9, 7, Color("#8c6b45"))
			b.g.ellipse(at, 7, 6, Color("#1a1008"))
			members.append(b.enemies.add("goblinArcher" if randf() < 0.2 else "goblin", at.x, at.y, home))
		else:
			var bush := Scenery.bush(randf_range(20, 25), biome)
			b.stand(bush, at.x, at.y)
			hides.append(bush)
			members.append(b.enemies.add("captain" if k == 0 and b.difficulty >= 1 else "bandit", at.x, at.y, home))
	# Fill out the thicket so the hiding bushes don't stand out
	if faction != "goblin":
		for k in randi_range(4, 6):
			var a := randf() * TAU
			var d := randf_range(100, 130)
			b.stand(Scenery.bush(randf_range(14, 22), biome), c.x + cos(a) * d, c.y + sin(a) * d * 0.85)

	var state := {"rustle": randf_range(1, 3), "shaking": null}
	var animate := func(time: float, dt: float) -> void:
		# Now and then a hiding bush gives itself away with a rustle
		state.rustle -= dt
		if state.rustle <= 0 and not hides.is_empty():
			state.shaking = {"bush": hides[randi() % hides.size()], "until": time + 0.5}
			state.rustle = randf_range(2.5, 5)
		for k in hides.size():
			var shaking: bool = state.shaking != null and state.shaking.bush == hides[k] and time < state.shaking.until and members[k].in_hiding
			hides[k].rotation = sin(time * 40) * 0.12 if shaking else 0.0
	return {
		"members": members,
		"solids": [],
		"loot": loot,
		"zones": [Vector3(c.x, c.y, 150)],
		"trigger": Vector3(c.x, c.y, SPRING),
		"animate": animate,
	}
