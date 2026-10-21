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

# War horns: from the Darkwood on, some bands carry a hornblower. Once they've
# seen you, the horn is raised; kill the hornblower within HORN_TIME or it
# sounds and a horde closes in from all round.
const HORN_FROM := 2500.0 # metres (the Darkwood)
const HORN_CHANCE := 0.45
const HORN_TIME := 5.0
const HORDE_RING := Vector2(650, 950) # px from you that the horde comes in from

var enemies: Enemies
var net: RoadNet
# { members, leader, home (shared), route, leg, ahead, heading, engaged,
#   suspicion, lost, query (the "?") }
var bands: Array = []
var timer := FIRST_DELAY
var messages: Array = [] # things to tell you (Game shows them)
var jolt := 0.0 # a shake of the screen, asked for (the horn)


func _init(enemies_: Enemies, net_: RoadNet) -> void:
	enemies = enemies_
	net = net_


# `night`: whether war bands are abroad. `me`: { pos, on_cart, sprinting }.
# `towns`: Vector3(x, y, radius).
func update(dt: float, night: bool, me: Dictionary, metres: float, towns: Array) -> void:
	var meadows: bool = Threat.stage_at(metres).biome.name == "The Meadows"
	if night:
		timer -= dt
		if timer <= 0 and bands.size() < (1 if meadows else MAX_BANDS):
			_spawn(me.pos, metres, towns, meadows)
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
			_update_horn(band, dt, me.pos, metres)
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
	# The horn goes up
	var horn: Variant = band.get("horn")
	if horn != null and horn.alive() and band.horn_t < 0 and band.blast == null:
		band.horn_t = HORN_TIME
		horn.rooted = true
		horn.rig.blowing = 1.0
		band.horn_ring.visible = true
		messages.append("A war horn is raised! Kill the hornblower before it sounds")


# The horn's count: it sounds unless the hornblower is cut down first.
func _update_horn(band: Dictionary, dt: float, me: Vector2, metres: float) -> void:
	var horn: Variant = band.get("horn")
	if band.blast_t > 0:
		# The blast rolling out
		band.blast_t -= dt
		var wave: Variant = band.blast
		if is_instance_valid(wave):
			var t: float = 1.0 - band.blast_t / 1.4
			wave.scale = Vector2.ONE * (1 + t * 14)
			wave.modulate.a = 1 - t
		if band.blast_t <= 0:
			if is_instance_valid(wave):
				wave.queue_free()
			if horn != null and is_instance_valid(horn):
				horn.rig.blowing = 0.0
				horn.rooted = false
		return
	if horn == null or band.horn_t < 0:
		return
	if not horn.alive():
		band.horn_t = -1.0
		band.horn = null
		band.horn_ring.visible = false
		messages.append("The hornblower falls – the horn is silent")
		return
	horn.facing = (me - horn.position).angle()
	band.horn_t -= dt
	band.horn_ring.queue_redraw()
	if band.horn_t <= 0:
		_sound_horn(band, me, metres)


func _sound_horn(band: Dictionary, me: Vector2, metres: float) -> void:
	var horn: Enemy = band.horn
	band.horn_t = -1.0
	band.horn_ring.visible = false
	band.blast_t = 1.4
	var wave := Sketch.new()
	wave.ellipse_stroke(Vector2.ZERO, 20, 10, 2.5, Color("#f6c25a"))
	wave.position = Vector2(0, -6)
	horn.add_child(wave)
	band.blast = wave
	jolt = 0.6
	Sfx.play("horn", Vector2.INF, 0.0, 0.0) # (heard wherever you are)
	messages.append("The war horn sounds! A horde is coming")
	# The horde: from all round, out of sight, straight for you
	var km := metres / 1000.0
	var threat := Threat.threat_at(metres)
	var count := mini(60, 18 + floori(km * 3))
	var small := "goblin" if horn.faction == "goblin" else "bandit"
	var heavy := "orc" if horn.faction == "goblin" else "brute"
	var archer := "goblinArcher" if horn.faction == "goblin" else "archer"
	var types := []
	for k in count:
		types.append(heavy if k % 7 == 3 else (archer if k % 5 == 1 else small))
	var horde := _make_band(me, types, threat, [me], false)
	horde.engaged = true
	for m: Enemy in horde.members:
		m.position = me + Vector2.from_angle(randf() * TAU) * randf_range(HORDE_RING.x, HORDE_RING.y)
		m.leash = HUNT_LEASH + 1000
		m.engage()
	bands.append(horde)


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


func _spawn(player: Vector2, metres: float, towns: Array, meadows: bool) -> void:
	# A stretch of the road you're on (or nearest), one way or the other, to
	# patrol beside
	var near := net.nearest(player, 3000.0)
	if near.road == null:
		return
	var road: Road = near.road
	var start: int = near.index + (randi_range(24, 40) if randf() < 0.5 else -randi_range(30, 40) - 26)
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
	# Bigger the further you go (the Meadows' stay small enough to slip past)
	var count := mini(18, 6 + threat.extra_members + floori(km) - (2 if meadows else 0))
	var small := "goblin" if faction == "goblin" else "bandit"
	var heavy := "orc" if faction == "goblin" else "brute"
	var archer := "goblinArcher" if faction == "goblin" else "archer"
	var types := [small, archer]
	for k in count - 2:
		types.append(heavy if k % 4 == 2 else small)
	if faction == "bandit" and km > 2:
		types[0] = "captain" # someone has to lead them

	# Some carry a war horn
	if metres >= HORN_FROM and not meadows and randf() < HORN_CHANCE:
		types[types.size() - 1] = "goblinHorn" if faction == "goblin" else "hornblower"
	bands.append(_make_band(at, types, threat, route, true))


# Stand a band up at `at`: the members round a shared home, the first of them
# leading (with a torch, if `torch_lit`). Returns the band (not yet added).
func _make_band(at: Vector2, types: Array, threat: Dictionary, route: Array, torch_lit: bool) -> Dictionary:
	var home := {"x": at.x, "y": at.y, "wander": {"x": at.x, "y": at.y, "min": 8.0, "max": 34.0}}
	var members := []
	var before: Variant = enemies.threat
	enemies.threat = threat
	for k in types.size():
		var a := float(k) / types.size() * TAU
		var spread := 18.0 + types.size() * 2.5
		var e := enemies.add(types[k], at.x + cos(a) * spread, at.y + sin(a) * spread, home)
		e.leash = HUNT_LEASH
		members.append(e)
	enemies.threat = before

	# The leader carries a torch (you can see them coming), and shows what
	# they've noticed
	var leader: Enemy = members[0]
	var top := -leader.rig.height()
	var torch: Variant = null
	if torch_lit:
		torch = Sketch.new()
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

	var band := {"members": members, "leader": leader, "home": home, "route": route, "leg": mini(1, route.size() - 1), "ahead": 1,
		"heading": (route[1] - route[0]).angle() if route.size() > 1 else 0.0, "engaged": false, "suspicion": 0.0, "lost": 0.0,
		"query": holder, "torch": torch, "horn": null, "horn_t": -1.0, "horn_ring": null, "blast_t": 0.0, "blast": null}
	# A hornblower: the count to the blast shows as a ring filling over their head
	for m: Enemy in members:
		if m.type == "hornblower" or m.type == "goblinHorn":
			band.horn = m
			var ring := Painter.new(func(ci: CanvasItem) -> void:
				var left: float = clampf(band.horn_t / HORN_TIME, 0, 1)
				var c := Vector2(0, -m.rig.height() - 16)
				Draw.circle(ci, c, 8, Color(0, 0, 0, 0.55))
				ci.draw_arc(c, 6.5, -PI / 2, -PI / 2 + TAU * (1 - left), 24, Color("#e0463a"), 2.5, true)
				ci.draw_arc(c, 6.5, -PI / 2 + TAU * (1 - left), -PI / 2 + TAU, 24, Color("#f6c25a", 0.35), 2.5, true))
			ring.visible = false
			m.add_child(ring)
			band.horn_ring = ring
			break
	return band


# Debug: a band with a hornblower right by you, already on to you.
func debug_horn_band(me: Vector2, metres: float) -> void:
	var faction := "goblin" if randf() < 0.5 else "bandit"
	var small := "goblin" if faction == "goblin" else "bandit"
	var types := [small, small, small, "goblinHorn" if faction == "goblin" else "hornblower"]
	var at := me + Vector2.from_angle(randf() * TAU) * 260
	var band := _make_band(at, types, Threat.threat_at(maxf(metres, HORN_FROM)), [at], true)
	bands.append(band)
	_engage(band)
