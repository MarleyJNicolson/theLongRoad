class_name Missions
extends RefCounted

# Supply runs (not in the JS original). A town's quartermaster wants crates
# carried to another town in the region; you're paid in gold and gems when
# they arrive, for as many as arrive (raiders' blows on the cart smash them).
# The towns off the road north are further and need it more: more gems.

const OFFERS := 3


# What a town's quartermaster offers: { to_id, to_name, from_name, crates,
# gold, gems, taken }.
static func offers_for(town: Dictionary, net: RoadNet) -> Array:
	var others: Array = net.towns.filter(func(t: Dictionary) -> bool:
		return t.zone == town.zone and t.id != town.id and t.kind != "start")
	var out := []
	if others.is_empty():
		return out
	for n in OFFERS:
		# Towns off the road north are asked for twice as often
		var pool := []
		for t in others:
			pool.append(t)
			if t.side != "c":
				pool.append(t)
		var to: Dictionary = pool[randi() % pool.size()]
		# Mostly a few crates; now and then a load for a wagon
		var crates := randi_range(1, 3) + (randi_range(1, 3) if randf() < 0.35 else 0)
		var metres: float = town.pos.distance_to(to.pos) / RoadNet.PX_PER_METRE
		var gold := crates * (2 + roundi(metres / 150.0))
		var gems := maxi(1, roundi(crates * (0.25 + metres / 1800.0) * (1.5 if to.side != "c" else 1.0)))
		out.append({"to_id": to.id, "to_name": to.name, "from_name": town.name, "crates": crates,
			"gold": gold, "gems": gems, "taken": false})
	return out


# Which way, roughly, from `from` to `to`: "north", "east", "south-west"...
static func compass(from: Vector2, to: Vector2) -> String:
	var a := (to - from).angle()
	var names := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
	return names[posmod(roundi(a / (TAU / 8)), 8)]
