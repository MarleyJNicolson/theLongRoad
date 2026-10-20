class_name Encounters
extends RefCounted

# Places goblin and bandit encounters along the road ahead, keeps trees out of
# their way, and alerts each group when the cart arrives (port of
# encounters/index.js).
#
# An encounter is a Dictionary: { view, members, solids, loot, zones, trigger
# (Vector3 x, y, radius), animate(time, dt)?, engage()?, reward?, on_cleared()?,
# traders?, side_road?, road_views?, uprights, index, kind, cleared }.

const FIRST_AT := 45 # road point index of the first encounter
const SIDE_ROAD_CHANCE := 0.22 # of an encounter being a turning to somewhere bigger
const SIDE_ROADS_FROM := 300.0 # metres
const FIRST_SIDE_ROAD_BY := 450.0 # metres: there's always one early on
const MAX_SIDE_ROAD_GAP := 600.0 # metres: never longer than this without one

# Some encounters need room beside the road and can fail to fit; each
# faction's fallback always fits.
const TABLE := [
	{"kind": "goblinCamp", "make": "goblin_camp", "faction": "goblin", "weight": 20},
	{"kind": "goblinBurrows", "make": "goblin_burrows", "faction": "goblin", "weight": 16},
	{"kind": "goblinLooters", "make": "goblin_looters", "faction": "goblin", "weight": 16},
	{"kind": "goblinHouseRaid", "make": "goblin_raid", "faction": "goblin", "weight": 13},
	{"kind": "banditCamp", "make": "bandit_camp", "faction": "bandit", "weight": 14},
	{"kind": "banditAmbush", "make": "bandit_ambush", "faction": "bandit", "weight": 20},
	{"kind": "banditRoadblock", "make": "bandit_roadblock", "faction": "bandit", "weight": 14},
	{"kind": "banditHouseRaid", "make": "bandit_raid", "faction": "bandit", "weight": 13},
	# Off in the wilds: a chest left as bait
	{"kind": "banditLure", "make": "bandit_lure", "faction": "bandit", "weight": 11},
	{"kind": "goblinLure", "make": "goblin_lure", "faction": "goblin", "weight": 9},
]
const FALLBACK := {"goblin": 2, "bandit": 5} # goblinLooters, banditAmbush

var layer: Node2D # flat ground decals
var upright: Node2D # the depth-sorted layer shared with the people
var road: Road
var enemies: Enemies
var list: Array = []
var next_index := FIRST_AT
var last: Variant = null # the kind placed last (never twice in a row)
var time := 0.0
var rewards: Array = [] # { gold, x, y, message? } earned by clearing out raids
var on_new_zones: Callable # called with zones that appear where scenery already is
var last_side_road := FIRST_SIDE_ROAD_BY - MAX_SIDE_ROAD_GAP # metres
var next_town := Towns.next_along(Road.start_along + 1) # px along the road
var _zones_cache: Variant = null # zones(), until the list of encounters changes
var _solids_cache: Variant = null # obstacles(), likewise


# Encounters came or went: lists built from them need building again.
func _changed() -> void:
	_zones_cache = null
	_solids_cache = null


func _init(layer_: Node2D, upright_: Node2D, road_: Road, enemies_: Enemies) -> void:
	layer = layer_
	upright = upright_
	road = road_
	enemies = enemies_


# Towns on the road so far: { name, safe: Vector3(x, y, radius) }.
func towns() -> Array:
	var out := []
	for e in list:
		if e.has("town"):
			out.append(e.town)
	return out


# The town whose walls `at` is inside, or null.
func town_at(at: Vector2) -> Variant:
	for t in towns():
		if at.distance_to(Vector2(t.safe.x, t.safe.y)) < t.safe.z:
			return t
	return null


# Every encounter's zones. The same array is handed out until encounters
# come or go (scenery uses that to know when to refile them).
func zones() -> Array:
	if _zones_cache == null:
		var out := []
		for e in list:
			out.append_array(e.zones)
		_zones_cache = out
	return _zones_cache


# Traders open for business (villages at the end of side roads).
func traders() -> Array:
	var out := []
	for e in list:
		for t in e.get("traders", []):
			if t.open:
				out.append(t)
	return out


# Is `at` on any side road?
func on_side_road(at: Vector2) -> bool:
	for e in list:
		if e.has("side_road") and SideRoads.on_side_road(e, at):
			return true
	return false


# Everything solid in the encounters (the same array until they change).
func obstacles() -> Array:
	if _solids_cache == null:
		var out := []
		for e in list:
			out.append_array(e.solids)
		_solids_cache = out
	return _solids_cache


# Unopened treasure chests (and arrow barrels with something left).
func loot() -> Array:
	var out := []
	for e in list:
		for l in e.loot:
			if not l.opened:
				out.append(l)
	return out


# Weighted pick, leaning toward whatever the region is known for.
static func _pick(exclude: Variant, biome: Dictionary) -> Dictionary:
	var options := TABLE.filter(func(t: Dictionary) -> bool: return t != exclude)
	var weight := func(t: Dictionary) -> float: return t.weight * biome.weights.get(t.kind, 1.0)
	var total := 0.0
	for t in options:
		total += weight.call(t)
	var roll := randf() * total
	for t in options:
		roll -= weight.call(t)
		if roll < 0:
			return t
	return options[0]


static func _make(entry: Dictionary, b: Build) -> Variant:
	match entry.make:
		"goblin_camp": return Goblins.camp(b)
		"goblin_burrows": return Goblins.burrows(b)
		"goblin_looters": return Goblins.looters(b)
		"goblin_raid": return Raids.goblin_raid(b)
		"bandit_camp": return Bandits.camp(b)
		"bandit_ambush": return Bandits.ambush(b)
		"bandit_roadblock": return Bandits.roadblock(b)
		"bandit_raid": return Raids.bandit_raid(b)
		"bandit_lure": return Lures.bandit(b)
		"goblin_lure": return Lures.goblin(b)
	return null


# Place new encounters as soon as their stretch of road exists. Call this
# before the scenery fills that stretch in, so trees are kept clear.
func place() -> void:
	while next_index < road.points.size() - 5:
		var i := next_index
		# A town ahead: nothing is placed near it, and it waits until the road
		# runs right through it
		var town_i := roundi((next_town - Road.start_along) / Road.SEGMENT)
		var clear := ceili(Towns.CLEAR / Road.SEGMENT)
		if i >= town_i - clear:
			if town_i + clear >= road.points.size() - 5:
				return
			if town_i >= 3: # (not one behind where the road starts)
				_place_town(town_i)
			next_town = Towns.next_along(next_town + 1)
			next_index = maxi(i, town_i + clear)
			continue
		# No turning off just before a town: what's down it would crowd the walls
		var town_soon := i >= town_i - clear - ceili((Towns.RADIUS + Destinations.DEST_RADIUS + 400) / Road.SEGMENT)
		# Raiders are as tough as the stretch of road they're found on.
		var metres := Road.along(i) / 20.0
		var threat := Threat.threat_at(metres)
		var biome: Dictionary = Threat.stage_at(metres).biome
		enemies.threat = threat
		var view := Node2D.new()
		layer.add_child(view)
		var b := Build.new(view, upright, road, i, zones(), metres / 500.0, threat.extra_members, enemies)
		b.towns = towns().map(func(t: Dictionary) -> Vector3: return t.safe)

		# Now and then, a turning off to a village or a big camp. Its road runs
		# back alongside existing road, so clear any trees already there.
		var enc: Variant = null
		var entry: Variant = null
		var overdue := metres - last_side_road >= MAX_SIDE_ROAD_GAP
		if metres > SIDE_ROADS_FROM and not town_soon and (overdue or randf() < SIDE_ROAD_CHANCE):
			enc = SideRoads.side_road(b)
			if enc != null:
				last_side_road = metres
		if enc == null:
			# Never the same kind twice in a row.
			entry = _pick(last, biome)
			enc = _make(entry, b)
			if enc == null:
				# Didn't fit: undo whatever it stood up, and fall back
				b.clear_uprights()
				for child in view.get_children():
					child.queue_free()
				b.g = Sketch.new()
				view.add_child(b.g)
				entry = TABLE[FALLBACK[entry.faction]]
				enc = _make(entry, b)
		enc.view = view
		enc.index = i
		enc.uprights = b.uprights
		enc.kind = entry.kind if entry else "sideRoad"
		enc.cleared = false
		for key in ["solids", "loot", "members"]:
			if not enc.has(key):
				enc[key] = []
		# Clear any trees already standing in its way (side roads, paths in the wilds)
		if on_new_zones.is_valid():
			on_new_zones.call(enc.zones)
		# Wherever archers are posted, their spare arrows are kept to hand.
		for m: Enemy in enc.members:
			if m.shoots:
				var a := randf() * TAU
				Loot.add_arrow_barrel(enc.loot, b, Vector2(m.home.x + cos(a) * 30, m.home.y + sin(a) * 30))
				break
		list.append(enc)
		_changed()
		if entry:
			last = entry
		next_index += floori(threat.spacing * randf_range(0.85, 1.2))


func _place_town(i: int) -> void:
	var view := Node2D.new()
	layer.add_child(view)
	var b := Build.new(view, upright, road, i, zones(), 0, 0, enemies)
	var town := Towns.build(b)
	town.view = view
	town.index = i
	town.uprights = b.uprights
	town.kind = "town"
	town.cleared = false
	if on_new_zones.is_valid():
		on_new_zones.call(town.zones)
	list.append(town)
	_changed()


# Buildings you're standing behind fade, so you never lose sight of yourself.
func fade_around(x: float, y: float) -> void:
	for enc in list:
		for u in enc.uprights:
			if not u.has("fade"):
				continue
			var f: Dictionary = u.fade
			var hidden: bool = y < f.y and y > f.y - f.height and absf(x - f.x) < f.r
			u.node.modulate.a += ((0.45 if hidden else 1.0) - u.node.modulate.a) * 0.2


# `player` is wherever the peasant is: on the cart or on foot ({ x, y, ... }).
func update(dt: float, player: Dictionary, road_index: int) -> void:
	time += dt
	var at := Vector2(player.x, player.y)
	for enc in list:
		if enc.has("animate"):
			enc.animate.call(time, dt)
		for chest in enc.loot:
			chest.animate.call(time)
		var trigger: Vector3 = enc.trigger
		var near := at.distance_to(Vector2(trigger.x, trigger.y)) < trigger.z
		var provoked: bool = enc.members.any(func(m: Enemy) -> bool: return m.provoked)
		if near or provoked:
			if enc.has("engage"):
				enc.engage.call()
			else:
				for m: Enemy in enc.members:
					m.engage()
			for m: Enemy in enc.members:
				m.provoked = false
		if enc.has("reward") and not enc.cleared and enc.members.all(func(m: Enemy) -> bool: return not m.alive()):
			enc.cleared = true
			if enc.has("on_cleared"):
				enc.on_cleared.call()
			rewards.append(enc.reward)

	var before := list.size()
	list = list.filter(func(enc: Dictionary) -> bool:
		if enc.index >= road_index - 70:
			return true
		enc.view.queue_free()
		for u in enc.uprights:
			u.node.queue_free()
		for v in enc.get("road_views", []):
			v.queue_free()
		for m: Enemy in enc.members:
			m.removed = true
		# A chest's functions refer back to the chest: clear it so both go
		for l in enc.loot:
			l.clear()
		enc.clear()
		return false)
	if list.size() != before:
		_changed()


# Let go of everything (a restart, or quitting). A chest's functions refer
# back to the chest, so it has to be cleared to be freed.
func dispose() -> void:
	for enc in list:
		for l in enc.get("loot", []):
			l.clear()
		enc.clear()
	list.clear()
	_changed()
