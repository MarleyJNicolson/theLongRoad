class_name Goblins
extends RefCounted

# Goblin encounters (port of encounters/goblins.js). Each builder returns the
# encounter (see Encounters.place), or null if it doesn't fit here.


# Goblin camp: hide tents round a campfire in a clearing, either just off the
# road or out in the wilds down a trodden path (a skull on a pole marks where
# it leaves the road). The goblins mill about until you come into view, then
# swarm.
static func camp(b: Build) -> Variant:
	var spot: Variant = b.set_back(Road.ROAD_WIDTH / 2 + 125, 190)
	if spot == null:
		return null
	var side: float = spot.side
	var f := b.frame()
	var c := Vector2(spot.x, spot.y)
	var edge := f.at(0, side * Road.ROAD_WIDTH / 2)

	b.draw_clearing(c, null if spot.deep else edge)
	var path: Array = b.footpath(edge, c, Color("#8f8a52")) if spot.deep else []

	var solids := [Vector3(c.x, c.y, 16)]
	var tents := randi_range(2, 3)
	var start := randf() * TAU
	for k in tents:
		var a := start + float(k) / tents * TAU + randf_range(-0.3, 0.3)
		var t := c + Vector2(cos(a) * 92, sin(a) * 80)
		b.stand(Structures.hide_tent(a + PI), t.x, t.y, null, {"r": 24, "height": 48})
		solids.append(Vector3(t.x, t.y, 22))
	b.scatter_bones(c, Vector2(70, 60), 5)
	var totem := f.at(-20, side * (Road.ROAD_WIDTH / 2 + 22))
	b.stand(Structures.skull_totem(), totem.x, totem.y)
	var flicker := b.campfire(c.x, c.y)
	# Stolen goods stacked beside a tent
	var loot := []
	var la := start + PI / tents
	var l := c + Vector2(cos(la) * 100, sin(la) * 86)
	Loot.add_prop(b, "crate", l, 16)
	Loot.maybe_add_chest(loot, b, l + Vector2(-6, 22), Build.DEEP_CHEST_CHANCE if spot.deep else Loot.CHEST_CHANCE)
	if randf() < 0.6:
		Loot.add_prop(b, "barrel", l + Vector2(20, 8), 8)
	solids.append(Vector3(l.x, l.y, 10))

	var wander := {"x": c.x, "y": c.y, "min": 32.0, "max": 70.0}
	var members := []
	for k in mini(7 + b.extra, 3 + floori(b.difficulty * 1.5)):
		var a := randf() * TAU
		var r := randf_range(32, 65)
		members.append(b.enemies.add("goblin", c.x + cos(a) * r, c.y + sin(a) * r, {"x": c.x, "y": c.y, "wander": wander}))

	return {
		"members": members,
		"solids": solids,
		"loot": loot,
		"zones": [Vector3(c.x, c.y, 190)] + path,
		"trigger": Vector3(c.x, c.y, 330 if spot.deep else 430),
		"animate": flicker,
	}


# Goblin burrows: dirt mounds right beside the road. Goblins pop out of the
# holes one after another as the cart rolls past.
static func burrows(b: Build) -> Variant:
	var f := b.frame()
	var sides := [1.0, -1.0] if randf() < 0.4 else [Build.side_sign()]
	var holes := randi_range(3, 4)
	var members := []
	for k in holes:
		var side: float = sides[k % sides.size()]
		var h := f.at(float(k) / holes * 140 + randf_range(-10, 10), side * (Road.ROAD_WIDTH / 2 + randf_range(30, 70)))
		b.g.ellipse(h + Vector2(3, 3), 19, 16, Color(0, 0, 0, 0.15))
		b.g.ellipse(h, 18, 15, Color("#7a5c3a"))
		b.g.ellipse(h - Vector2(3, 3), 10, 8, Color("#8c6b45"))
		b.g.ellipse(h, 8, 7, Color("#1a1008"))
		for s in 6:
			b.g.circle(h + Vector2(randf_range(-28, 28), randf_range(-24, 24)), randf_range(1.5, 3.5), Color("#7a5c3a"))
		var facing := (-f.n * side).angle()
		var count := (2 if k < mini(4, 1 + floori(b.difficulty)) else 1) + mini(2, b.extra / 2)
		for n in count:
			members.append(b.enemies.add("goblin", h.x, h.y, {"x": h.x, "y": h.y, "facing": facing, "hidden": true}))
	b.scatter_bones(f.at(70, 0), Vector2(40, Road.ROAD_WIDTH / 2 + 60), 3)
	var loot := []
	Loot.maybe_add_chest(loot, b, f.at(70, sides[0] * (Road.ROAD_WIDTH / 2 + 105))) # their hoard

	var m := f.at(70, 0)
	var state := {"started": false, "next_pop": 0.0}
	var engage := func() -> void:
		state.started = true
		for e: Enemy in members:
			if not e.in_hiding:
				e.engage()
	var animate := func(time: float, _dt: float) -> void:
		if not state.started or time < state.next_pop:
			return
		for e: Enemy in members:
			if e.in_hiding and e.alive():
				e.engage()
				break
		state.next_pop = time + 0.3
	return {
		"members": members,
		"solids": [],
		"loot": loot,
		"zones": [Vector3(m.x, m.y, Road.ROAD_WIDTH / 2 + 120)],
		"trigger": Vector3(m.x, m.y, 280),
		"engage": engage,
		"animate": animate,
	}


# Goblin looters: a merchant's wagon overturned at the roadside, goods strewn
# everywhere. The goblins are busy picking it over and slow to notice you.
static func looters(b: Build) -> Variant:
	var f := b.frame()
	var side := Build.side_sign()
	var lateral := side * (Road.ROAD_WIDTH / 2 - 4)
	var w := f.at(0, lateral)
	var angle := f.d.angle() + randf_range(-0.35, 0.35)
	var pt := func(fx: float, fy: float) -> Vector2: return w + Vector2(fx, fy).rotated(angle)

	# Upturned wagon: we see its dark underside, axles and one wheel left on.
	b.stand(Structures.overturned_wagon(angle), w.x, w.y, null, {"r": 34, "height": 26})
	# A loose wheel, the broken shaft and the spilled load
	var l := f.at(-50, lateral + side * 40)
	b.g.ellipse_stroke(l, 13, 13, 3, Color("#3a2a1a"))
	for k in 4:
		var a := float(k) / 4 * PI
		var d := Vector2(cos(a), sin(a)) * 12
		b.g.line(l - d, l + d, 2, Color("#3a2a1a"))
	b.g.round_stroke(PackedVector2Array([pt.call(32, 6), pt.call(62, 14)]), 4, Color("#6e4a28"))
	for k in 10:
		b.g.circle(f.at(randf_range(-60, 60), lateral + randf_range(-50, 30) * side), 3, Color("#c0392b"))
	for k in 6:
		b.g.ellipse(f.at(randf_range(-50, 50), lateral + randf_range(-40, 30) * side), 5, 4, Color("#c9b28a"))
	var loot := []
	Loot.add_prop(b, "crate", f.at(28, lateral + side * 30), 16)
	Loot.add_prop(b, "crate", f.at(-36, lateral - side * 14), 14)
	Loot.add_prop(b, "barrel", f.at(40, lateral - side * 6), 8)
	Loot.maybe_add_chest(loot, b, f.at(-10, lateral - side * 40)) # the merchant's strongbox

	var solids := []
	for fx in [-22.0, 0.0, 22.0]:
		var s: Vector2 = pt.call(fx, 0)
		solids.append(Vector3(s.x, s.y, 19))

	var wander := {"x": w.x, "y": w.y, "min": 34.0, "max": 58.0}
	var members := []
	for k in mini(6 + b.extra, 3 + floori(b.difficulty)):
		var a := randf() * TAU
		members.append(b.enemies.add("goblin", w.x + cos(a) * 45, w.y + sin(a) * 40, {"x": w.x, "y": w.y, "wander": wander}))

	return {
		"members": members,
		"solids": solids,
		"loot": loot,
		"zones": [Vector3(w.x, w.y, 140)],
		"trigger": Vector3(w.x, w.y, 230),
	}
