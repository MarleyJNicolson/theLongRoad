class_name Encounters
extends RefCounted

# Places goblin and bandit encounters along the roads, builds the towns, keeps
# trees out of their way, and alerts each group when the cart arrives (port of
# encounters/index.js, for a network of roads rather than one).
#
# An encounter is a Dictionary: { view, members, solids, loot, zones, trigger
# (Vector3 x, y, radius), animate(time, dt)?, engage()?, reward?, on_cleared()?,
# traders?, side_road?, road_views?, uprights, at, kind, cleared }.

const SIDE_ROAD_CHANCE := 0.16 # of an encounter being a turning to somewhere bigger
const SIDE_ROADS_FROM := 150.0 # metres

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
var net: RoadNet
var enemies: Enemies
var list: Array = []
var last: Variant = null # the kind placed last (never twice in a row)
var time := 0.0
var rewards: Array = [] # { gold, x, y, message? } earned by clearing out raids
var on_new_zones: Callable # called with zones that appear where scenery already is
# Places along the roads where something will be, made when the zone is:
# { road, i, enc (once built), spent (built and since cleared away) }
var slots: Array = []
var _built_towns := {} # town id -> its encounter
var _zones_cache: Variant = null # zones(), until the list of encounters changes
var _solids_cache: Variant = null # obstacles(), likewise

# Encounters are built as you come near (BUILD_NEAR) and cleared away once
# you're well past (DROP_FAR); one cleared away isn't built again. Towns are
# built from further off, and kept.
const BUILD_NEAR := 4600.0
const DROP_FAR := 9000.0
const TOWN_NEAR := 7000.0
const EW_SPACING := 0.8 # roads across the zone have more along them


# Encounters came or went: lists built from them need building again.
func _changed() -> void:
	_zones_cache = null
	_solids_cache = null


func _init(layer_: Node2D, upright_: Node2D, net_: RoadNet, enemies_: Enemies) -> void:
	layer = layer_
	upright = upright_
	net = net_
	enemies = enemies_


# Lay out where encounters will be along new roads (clear of the towns at
# either end).
func add_roads(roads: Array) -> void:
	var clear := ceili((Towns.CLEAR + 60) / Road.SEGMENT)
	for road: Road in roads:
		var i := clear + randi_range(0, 10)
		while i < road.points.size() - clear:
			slots.append({"road": road, "i": i, "enc": null, "spent": false})
			var metres := RoadNet.metres_at(road.points[i].y)
			var step: float = Threat.threat_at(metres).spacing * randf_range(0.85, 1.2)
			if road.kind == "ew":
				step *= EW_SPACING
			i += maxi(12, floori(step))


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


# Guards on duty (crossbowmen who shoot raiders that come near): towns', and
# villages' that aren't overrun.
func guards() -> Array:
	var out := []
	for e in list:
		for g in e.get("guards", []):
			if is_instance_valid(g) and g.visible:
				out.append(g)
	return out


# Folk in towns who'd come along with you, not yet taken on.
func hirelings() -> Array:
	var out := []
	for e in list:
		for h in e.get("hirelings", []):
			if not h.hired:
				out.append(h)
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


# Build the encounter for a slot.
func _build(slot: Dictionary) -> void:
	var road: Road = slot.road
	var i: int = slot.i
	var metres := RoadNet.metres_at(road.points[i].y)
	var threat := Threat.threat_at(metres)
	var biome: Dictionary = Threat.stage_at(metres).biome
	enemies.threat = threat
	var view := Node2D.new()
	layer.add_child(view)
	var b := Build.new(view, upright, road, i, zones() + net.town_circles(Towns.CLEAR), metres / 500.0, threat.extra_members, enemies)
	b.net = net
	b.metres = metres
	b.rich = road.kind == "ew"
	b.towns = net.town_circles(Towns.RADIUS)

	# Now and then, a turning off to a village or a big camp.
	var enc: Variant = null
	var entry: Variant = null
	if metres > SIDE_ROADS_FROM and randf() < SIDE_ROAD_CHANCE:
		enc = SideRoads.side_road(b)
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
	enc.uprights = b.uprights
	enc.kind = entry.kind if entry else "sideRoad"
	enc.cleared = false
	enc.at = road.points[i]
	for key in ["solids", "loot", "members"]:
		if not enc.has(key):
			enc[key] = []
	_reinforce(enc, threat.reinforce)
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
	slot.enc = enc
	_changed()
	if entry:
		last = entry


# More of them: copies of the rank and file already there (the leaders stay
# one of a kind), standing among them; those hiding share their hiding place.
func _reinforce(enc: Dictionary, share: float) -> void:
	var ranks: Array = enc.members.filter(func(m: Enemy) -> bool: return m.type != "captain" and m.type != "brute" and m.type != "orc")
	if ranks.is_empty() or share <= 0:
		return
	var extra := roundi(enc.members.size() * share)
	for n in extra:
		var m: Enemy = ranks[randi() % ranks.size()]
		var home: Dictionary = m.home.duplicate(true)
		var at := Vector2(home.x, home.y)
		if not home.get("hidden", false):
			at += Vector2.from_angle(randf() * TAU) * randf_range(14, 30)
		enc.members.append(enemies.add(m.type, at.x, at.y, home))


func _build_town(town: Dictionary) -> void:
	var view := Node2D.new()
	layer.add_child(view)
	var road: Road = town.roads[0]
	var b := Build.new(view, upright, road, 0, zones(), 0, 0, enemies)
	b.net = net
	b.metres = RoadNet.metres_at(town.pos.y)
	var enc := Towns.build(b, town)
	enc.view = view
	enc.uprights = b.uprights
	enc.kind = "town"
	enc.cleared = false
	enc.at = town.pos
	if on_new_zones.is_valid():
		on_new_zones.call(enc.zones)
	list.append(enc)
	_built_towns[town.id] = enc
	_changed()


# The built encounter for a town (null until you've come near it).
func town_encounter(id: int) -> Variant:
	return _built_towns.get(id)


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
func update(dt: float, player: Dictionary) -> void:
	time += dt
	var at := Vector2(player.x, player.y)
	# Build what you're coming near
	for town in net.towns:
		if not _built_towns.has(town.id) and town.zone >= net.zone - 1 and town.pos.distance_to(at) < TOWN_NEAR:
			_build_town(town)
	for slot in slots:
		if slot.enc == null and not slot.spent and slot.road.points[slot.i].distance_to(at) < BUILD_NEAR:
			_build(slot)

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

	# Clear away what's far behind (towns only once their zone is two back)
	var before := list.size()
	list = list.filter(func(enc: Dictionary) -> bool:
		if enc.has("town"):
			if enc.town.zone >= net.zone - 1:
				return true
			_built_towns.erase(enc.town.id)
		elif enc.at.distance_to(at) < DROP_FAR:
			return true
		_drop(enc)
		return false)
	if list.size() != before:
		for slot in slots:
			if slot.enc != null and slot.enc.is_empty():
				slot.enc = null
				slot.spent = true
		_changed()


func _drop(enc: Dictionary) -> void:
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


# Let go of everything (a restart, or quitting). A chest's functions refer
# back to the chest, so it has to be cleared to be freed.
func dispose() -> void:
	for enc in list:
		for l in enc.get("loot", []):
			l.clear()
		enc.clear()
	list.clear()
	_changed()
