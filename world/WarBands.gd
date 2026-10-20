class_name WarBands
extends RefCounted

# Roaming war bands, abroad only at night (not in the JS original). They form
# out in the dark, ahead of you (now and then behind), well away from towns,
# and roam toward the road. Once one spots you it hunts you hard. At dawn,
# any that haven't found you melt away.

const MAX_BANDS := 2
const FIRST_DELAY := 8.0 # seconds after nightfall before the first appears
const EVERY := Vector2(20, 35) # seconds between new bands
const SPOT := 420.0 # px: how close before a band notices you
const ROAM_SPEED := 35.0 # px/s: the band's drift toward the road
const HUNT_LEASH := 3000.0 # how far they'll chase a cart from where they formed
const ELITE_BONUS := 0.15 # likelier elites than by day
const TOWN_GAP := 500.0 # px kept between a forming band and any town's walls

var enemies: Enemies
var road: Road
var bands: Array = [] # { members, home (shared by them all), target, engaged }
var timer := FIRST_DELAY


func _init(enemies_: Enemies, road_: Road) -> void:
	enemies = enemies_
	road = road_


# `night`: whether war bands are abroad. `towns`: Vector3(x, y, radius).
func update(dt: float, night: bool, player: Vector2, road_index: int, metres: float, towns: Array) -> void:
	if night:
		timer -= dt
		if timer <= 0 and bands.size() < MAX_BANDS:
			_spawn(player, road_index, metres, towns)
			timer = randf_range(EVERY.x, EVERY.y)
	else:
		timer = FIRST_DELAY

	var in_town := false
	for t: Vector3 in towns:
		if player.distance_to(Vector2(t.x, t.y)) < t.z:
			in_town = true
	for band in bands:
		var home: Dictionary = band.home
		var at := Vector2(home.x, home.y)
		if not band.engaged:
			# Drifting toward the road, milling about as they go
			var step: Vector2 = (band.target - at).limit_length(ROAM_SPEED * dt)
			home.x += step.x
			home.y += step.y
			home.wander.x = home.x
			home.wander.y = home.y
			if not in_town:
				for m: Enemy in band.members:
					if m.alive() and m.position.distance_to(player) < SPOT:
						_engage(band)
						break
	# Melt away at dawn unless they've found you; forget ones left far behind
	bands = bands.filter(func(band: Dictionary) -> bool:
		var far: float = Vector2(band.home.x, band.home.y).distance_to(player)
		var gone: bool = (not night and not band.engaged and far > 700) or far > 3000 \
			or band.members.all(func(m: Enemy) -> bool: return not m.alive())
		if gone:
			for m: Enemy in band.members:
				if m.alive():
					m.removed = true
		return not gone)


# Clear them all away (a night slept through at an inn).
func clear() -> void:
	for band in bands:
		for m: Enemy in band.members:
			if m.alive():
				m.removed = true
	bands.clear()
	timer = FIRST_DELAY


func _engage(band: Dictionary) -> void:
	band.engaged = true
	for m: Enemy in band.members:
		m.engage()


func _spawn(player: Vector2, road_index: int, metres: float, towns: Array) -> void:
	# Out in the dark beside the road, ahead (now and then behind)
	var ahead := randf() > 0.2
	var i := clampi(road_index + (randi_range(20, 35) if ahead else -randi_range(18, 26)), 1, road.points.size() - 2)
	var side := -1.0 if randf() < 0.5 else 1.0
	var road_at := road.points[i]
	var at := road_at + road.normal(i) * side * randf_range(320, 520)
	for t: Vector3 in towns:
		if at.distance_to(Vector2(t.x, t.y)) < t.z + TOWN_GAP or road_at.distance_to(Vector2(t.x, t.y)) < t.z + TOWN_GAP:
			return # (no gathering near a town; try again later)
	if at.distance_to(player) < SPOT + 100:
		return

	var biome: Dictionary = Threat.stage_at(metres).biome
	var faction := "goblin" if biome.name == "The Darkwood" else ("bandit" if biome.name == "The Barrens" else ("goblin" if randf() < 0.5 else "bandit"))
	var threat := Threat.threat_at(metres)
	threat.elite_chance = minf(0.6, threat.elite_chance + ELITE_BONUS)
	var km := metres / 1000.0
	var count := mini(10, 4 + threat.extra_members + floori(km / 2))
	var small := "goblin" if faction == "goblin" else "bandit"
	var heavy := "orc" if faction == "goblin" else "brute"
	var archer := "goblinArcher" if faction == "goblin" else "archer"
	var types := [archer]
	for k in count - 1:
		types.append(heavy if k % 4 == 3 else small)
	if faction == "bandit" and km > 2:
		types[0] = "captain" # someone has to lead them
		types.append(archer)

	var home := {"x": at.x, "y": at.y, "wander": {"x": at.x, "y": at.y, "min": 10.0, "max": 45.0}}
	var members := []
	var before: Variant = enemies.threat
	enemies.threat = threat
	for k in types.size():
		var a := float(k) / types.size() * TAU
		var e := enemies.add(types[k], at.x + cos(a) * 30, at.y + sin(a) * 30, home)
		e.leash = HUNT_LEASH
		members.append(e)
	enemies.threat = before
	bands.append({"members": members, "home": home, "target": road_at, "engaged": false})
