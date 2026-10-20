class_name WarBands
extends RefCounted

# War bands, abroad only at night (not in the JS original). Each patrols a
# route along the road (now and then crossing it), led by someone with a
# torch, so you can see them coming. They only attack if they see you: they
# watch the way they're walking, and hear anything close. A "?" grows over
# the leader as they notice something; let it fill and they're on you. Break
# away from them for long enough and they give up and patrol on. At dawn, any
# that haven't found you melt away.
#
# The Meadows are the gentlest: one band at a time, smaller, short-sighted.

const MAX_BANDS := 2
const FIRST_DELAY := 8.0 # seconds after nightfall before the first appears
const EVERY := Vector2(20, 35) # seconds between new bands
const PATROL_SPEED := 30.0 # px/s (a walk: they keep in step at their idle pace)
const HUNT_LEASH := 3000.0 # how far they'll chase a cart from their patrol
const ELITE_BONUS := 0.15 # likelier elites than by day
const TOWN_GAP := 500.0 # px kept between a band's route and any town's walls

# Seeing you: how far, by how easy you are to spot
const SIGHT_CART := 460.0 # the cart, with its lantern lit
const SIGHT_SPRINT := 300.0 # on foot, running
const SIGHT_FOOT := 220.0 # on foot, in the dark
const HEARING := 70.0 # px all round: right up close they'll notice anyway
const HEARING_CART := 150.0 # hooves and wheels carry
const CONE := deg_to_rad(65) # how far either side of their way they look
const NOTICE := 0.9 # seconds of being seen before they come for you
const FORGET := 8.0 # seconds out of their sight before they give up
const MEADOWS_SIGHT := 0.7 # the Meadows: shorter sight

var enemies: Enemies
var road: Road
# { members, leader, home (shared), route, leg, ahead, heading, engaged,
#   suspicion, lost, query (the "?") }
var bands: Array = []
var timer := FIRST_DELAY


func _init(enemies_: Enemies, road_: Road) -> void:
	enemies = enemies_
	road = road_


# `night`: whether war bands are abroad. `me`: { pos, on_cart, sprinting }.
# `towns`: Vector3(x, y, radius).
func update(dt: float, night: bool, me: Dictionary, road_index: int, metres: float, towns: Array) -> void:
	var meadows: bool = Threat.stage_at(metres).biome.name == "The Meadows"
	if night:
		timer -= dt
		if timer <= 0 and bands.size() < (1 if meadows else MAX_BANDS):
			_spawn(me.pos, road_index, metres, towns, meadows)
			timer = randf_range(EVERY.x, EVERY.y)
	else:
		timer = FIRST_DELAY

	var safe := false
	for t: Vector3 in towns:
		if me.pos.distance_to(Vector2(t.x, t.y)) < t.z:
			safe = true
	var sight: float = SIGHT_CART if me.on_cart else (SIGHT_SPRINT if me.sprinting else SIGHT_FOOT)
	if meadows:
		sight *= MEADOWS_SIGHT
	var hearing: float = HEARING_CART if me.on_cart else (HEARING * 1.5 if me.sprinting else HEARING)

	for band in bands:
		var living: Array = band.members.filter(func(m: Enemy) -> bool: return m.alive())
		# The torch goes out with whoever carried it
		if not band.leader.alive() and is_instance_valid(band.torch):
			band.torch.queue_free()
			band.query.visible = false
		if living.is_empty():
			continue
		if band.engaged:
			# Hunting: until they've lost you for long enough
			var near := living.any(func(m: Enemy) -> bool: return m.position.distance_to(me.pos) < sight * 1.5)
			band.lost = 0.0 if near and not safe else band.lost + dt
			if band.lost > FORGET:
				_give_up(band)
			continue
		var seen := not safe and _sees(band, living, me.pos, sight, hearing)
		var provoked := living.any(func(m: Enemy) -> bool: return m.provoked)
		if seen:
			# Stop and stare: the closer you are, the quicker they're sure
			var nearest: float = living.map(func(m: Enemy) -> float: return m.position.distance_to(me.pos)).min()
			band.suspicion += dt / NOTICE * (2.0 if nearest < sight * 0.5 else 1.0)
			band.heading = (me.pos - Vector2(band.home.x, band.home.y)).angle()
		else:
			band.suspicion = maxf(0.0, band.suspicion - dt * 0.4)
			_patrol(band, dt)
		if band.suspicion >= 1.0 or provoked:
			_engage(band)
		_show_query(band)

	# Melt away at dawn unless they're on to you; forget ones left far behind
	bands = bands.filter(func(band: Dictionary) -> bool:
		var far: float = Vector2(band.home.x, band.home.y).distance_to(me.pos)
		var gone: bool = (not night and not band.engaged and far > 700) or far > 3500 \
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


# Does any of them see (or hear) you? They look the way the band is heading.
func _sees(band: Dictionary, living: Array, at: Vector2, sight: float, hearing: float) -> bool:
	for m: Enemy in living:
		var to := at - m.position
		var dist := to.length()
		if dist < hearing:
			return true
		if dist < sight and absf(wrapf(to.angle() - band.heading, -PI, PI)) < CONE:
			return true
	return false


# Walk the route, back and forth, the band keeping together round its home.
func _patrol(band: Dictionary, dt: float) -> void:
	var home: Dictionary = band.home
	var at := Vector2(home.x, home.y)
	var goal: Vector2 = band.route[band.leg]
	if at.distance_to(goal) < 12:
		# On to the next point, turning back at either end
		if band.leg + band.ahead < 0 or band.leg + band.ahead >= band.route.size():
			band.ahead = -band.ahead
		band.leg += band.ahead
		goal = band.route[band.leg]
	var step := (goal - at).limit_length(PATROL_SPEED * dt)
	if step.length() > 0.01:
		band.heading = step.angle()
	home.x += step.x
	home.y += step.y
	home.wander.x = home.x
	home.wander.y = home.y


func _engage(band: Dictionary) -> void:
	band.engaged = true
	band.suspicion = 0.0
	band.lost = 0.0
	band.query.visible = false
	for m: Enemy in band.members:
		m.engage()


# Lost you: back to the patrol, from wherever they've got to.
func _give_up(band: Dictionary) -> void:
	band.engaged = false
	band.lost = 0.0
	var living: Array = band.members.filter(func(m: Enemy) -> bool: return m.alive())
	var centre := Vector2.ZERO
	for m: Enemy in living:
		centre += m.position
	centre /= maxi(1, living.size())
	band.home.x = centre.x
	band.home.y = centre.y
	band.home.wander.x = centre.x
	band.home.wander.y = centre.y
	# Pick up the patrol at its nearest point
	var nearest := 0
	for k in band.route.size():
		if band.route[k].distance_to(centre) < band.route[nearest].distance_to(centre):
			nearest = k
	band.leg = nearest
	for m: Enemy in living:
		m.drop_blow()
		m.state = "return"


func _show_query(band: Dictionary) -> void:
	var q: Node2D = band.query
	if not is_instance_valid(q):
		return
	q.visible = band.suspicion > 0.05
	q.modulate.a = clampf(0.35 + band.suspicion, 0, 1)
	q.scale = Vector2.ONE * (1 + band.suspicion * 0.4)


func _spawn(player: Vector2, road_index: int, metres: float, towns: Array, meadows: bool) -> void:
	# A stretch of road ahead (now and then behind) to patrol beside
	var ahead := randf() > 0.2
	var start := road_index + (randi_range(24, 40) if ahead else -randi_range(30, 40))
	var length := 26
	if start < 1 or start + length >= road.points.size() - 1:
		return
	var side := -1.0 if randf() < 0.5 else 1.0
	var route: Array[Vector2] = []
	var lateral := randf_range(180, 420)
	for k in range(0, length + 1, 3):
		var i := start + k
		# Drifting in and out, and now and then across the road
		lateral = clampf(lateral + randf_range(-90, 90), 150, 480)
		if randf() < 0.12:
			side = -side
		route.append(road.points[i] + road.normal(i) * side * lateral)
	for p in route:
		for t: Vector3 in towns:
			if p.distance_to(Vector2(t.x, t.y)) < t.z + TOWN_GAP:
				return # (no patrols near a town; try again later)
	var at: Vector2 = route[0]
	if at.distance_to(player) < SIGHT_CART + 100:
		return

	var biome: Dictionary = Threat.stage_at(metres).biome
	var faction := "goblin" if biome.name == "The Darkwood" else ("bandit" if biome.name == "The Barrens" else ("goblin" if randf() < 0.5 else "bandit"))
	var threat := Threat.threat_at(metres)
	threat.elite_chance = minf(0.6, threat.elite_chance + ELITE_BONUS)
	var km := metres / 1000.0
	var count := mini(10, 4 + threat.extra_members + floori(km / 2) - (1 if meadows else 0))
	var small := "goblin" if faction == "goblin" else "bandit"
	var heavy := "orc" if faction == "goblin" else "brute"
	var archer := "goblinArcher" if faction == "goblin" else "archer"
	var types := [small, archer]
	for k in count - 2:
		types.append(heavy if k % 4 == 2 else small)
	if faction == "bandit" and km > 2:
		types[0] = "captain" # someone has to lead them

	var home := {"x": at.x, "y": at.y, "wander": {"x": at.x, "y": at.y, "min": 8.0, "max": 34.0}}
	var members := []
	var before: Variant = enemies.threat
	enemies.threat = threat
	for k in types.size():
		var a := float(k) / types.size() * TAU
		var e := enemies.add(types[k], at.x + cos(a) * 26, at.y + sin(a) * 26, home)
		e.leash = HUNT_LEASH
		members.append(e)
	enemies.threat = before

	# The leader carries a torch (you can see them coming), and shows what
	# they've noticed
	var leader: Enemy = members[0]
	var top := -leader.rig.height()
	var torch := Sketch.new()
	torch.line(Vector2(9, -14), Vector2(11, top + 4), 2, Color("#4a3220"))
	torch.poly(PackedVector2Array([Vector2(8, top + 4), Vector2(11, top - 6), Vector2(14, top + 4)]), Color("#ee8a36"))
	torch.poly(PackedVector2Array([Vector2(10, top + 3), Vector2(11, top - 2), Vector2(12, top + 3)]), Color("#fdf0a6"))
	var flame := Glow.light(150, Color("#ff9a3c"), 1.1)
	flame.position = Vector2(11, top)
	torch.add_child(flame)
	leader.figure.add_child(torch)
	var query := Fonts.world_label("?", Vector2.ZERO, 22, Color("#f6c25a"))
	var holder := Node2D.new() # (scaled about the "?" itself)
	holder.position = Vector2(0, top - 22)
	holder.add_child(query)
	holder.visible = false
	leader.add_child(holder)

	bands.append({"members": members, "leader": leader, "home": home, "route": route, "leg": 1, "ahead": 1,
		"heading": (route[1] - route[0]).angle(), "engaged": false, "suspicion": 0.0, "lost": 0.0, "query": holder,
		"torch": torch})
