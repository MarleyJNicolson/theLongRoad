class_name Loot
extends RefCounted

# Treasure chests, arrow barrels and set-dressing crates (port of loot.js).
# A chest or barrel is a Dictionary the encounter keeps in its `loot` list:
# { kind, x, y, opened, animate: Callable(time), ... }.

# Chance that a point of interest has a treasure chest to search.
const CHEST_CHANCE := 0.5


# Always some gold; sometimes a healing poultice, tools to mend the cart, or a
# bundle of arrows or bolts.
static func _roll_chest() -> Dictionary:
	return {
		"gold": randi_range(3, 7),
		"health": 1 if randf() < 0.35 else 0,
		"repair": 2 if randf() < 0.35 else 0,
		"arrows": randi_range(8, 16) if randf() < 0.4 else 0,
		"bolts": randi_range(4, 8) if randf() < 0.15 else 0,
	}


# Crates and barrels are just set dressing.
static func add_prop(b: Build, kind: String, at: Vector2, size: float = -1) -> Node2D:
	var g: Node2D = Structures.crate(size if size > 0 else 18.0) if kind == "crate" else Structures.barrel(size if size > 0 else 9.0).g
	return b.stand(g, at.x, at.y)


# Maybe place a treasure chest here (CHEST_CHANCE unless told otherwise). If
# placed, it's added to the map and to the encounter's `list` of loot.
static func maybe_add_chest(list: Array, b: Build, at: Vector2, chance := CHEST_CHANCE) -> Variant:
	# Off the road north, across the zone, there's more to be found
	if b.rich:
		chance = minf(1.0, chance * 1.6)
	if randf() >= chance:
		return null
	var g := b.stand(Structures.chest(false), at.x, at.y) as Sketch
	var glint := Sketch.new()
	glint.round_stroke(PackedVector2Array([Vector2(-4, 0), Vector2(4, 0)]), 1.5, Color("#fff8d0"))
	glint.round_stroke(PackedVector2Array([Vector2(0, -4), Vector2(0, 4)]), 1.5, Color("#fff8d0"))
	b.stand(glint, at.x + 9, at.y - 14, at.y + 0.5)

	var chest := {"kind": "chest", "x": at.x, "y": at.y, "opened": false, "rich": b.rich}
	# A twinkle every so often to catch the player's eye.
	chest.animate = func(time: float) -> void:
		var t := fmod(time + at.x * 0.01, 2.5)
		glint.modulate.a = 0.0 if chest.opened else (sin(t / 0.4 * PI) if t < 0.4 else 0.0)
		glint.rotation = time * 2
	# Search it: returns what was inside, e.g. { gold: 4, health: 1, ... }.
	chest.open = func() -> Dictionary:
		chest.opened = true
		Structures.chest(true, g.clear())
		var found := _roll_chest()
		if chest.rich:
			found.gold *= 2
		return found
	list.append(chest)
	return chest


# A barrel of arrows kept by a camp's archers (and the odd bundle of bolts).
# Whatever doesn't fit in your bag stays in it for later.
static func add_arrow_barrel(list: Array, b: Build, at: Vector2) -> Dictionary:
	var g := b.stand(Sketch.new(), at.x, at.y) as Sketch
	var barrel := {"kind": "arrows", "x": at.x, "y": at.y, "opened": false,
		"contents": {"arrows": randi_range(12, 24), "bolts": randi_range(5, 10) if randf() < 0.3 else 0}}
	# Redraw to match what's left; empty means opened.
	barrel.update = func() -> void:
		var arrows: int = barrel.contents.arrows
		var bolts: int = barrel.contents.bolts
		barrel.opened = not arrows and not bolts
		var top: float = Structures.barrel(10, g.clear()).top
		g.ellipse(Vector2(0, -top), 6.5, 2.8, Color("#2a1f14"))
		# Fletchings poking out of the top
		var shafts := mini(7, ceili(arrows / 3.0))
		for k in shafts:
			var a := float(k) / maxi(1, shafts) * TAU
			var f := Vector2(cos(a) * 3.5, sin(a) * 1.5 - top)
			var tip := Vector2(f.x * 1.5, f.y - 8)
			g.line(f, tip, 1.5, Color("#8b6236"))
			g.circle(tip, 1.6, Color("#e8e0c8") if k % 2 else Color("#a3331f"))
		if bolts:
			g.rect(-2, -top - 3, 4, 4, Color("#5e3f22"))
	barrel.animate = func(_time: float) -> void: pass
	barrel.update.call()
	list.append(barrel)
	return barrel
