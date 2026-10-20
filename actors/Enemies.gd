class_name Enemies
extends RefCounted

# All the raiders on the road (port of the Enemies class in enemies.js).

const MAX_CORPSES := 120

var layer: Node2D # the y-sorted layer the living stand in
var fallen_layer: Node2D # where the dead lie, under the living
var list: Array = [] # Array of Enemy
var threat: Variant = null # set by whoever is spawning (see Encounters.place)
# Towns: Vector3(x, y, radius). Raiders won't follow you in.
static var safe_zones: Array = []


func _init(layer_: Node2D, fallen_layer_: Node2D) -> void:
	layer = layer_
	fallen_layer = fallen_layer_


func living() -> Array:
	return list.filter(func(e: Enemy) -> bool: return e.alive())


# Ordinary goblins and bandits are sometimes archers instead (more so further
# down the road).
func add(type: String, x: float, y: float, home: Dictionary) -> Enemy:
	if (type == "goblin" or type == "bandit") and randf() < (threat.archer_chance if threat else 0.12):
		type = "goblinArcher" if type == "goblin" else "archer"
	var enemy := Enemy.new(type, x, y, home, threat, fallen_layer)
	layer.add_child(enemy)
	list.append(enemy)
	return enemy


# `target` is who they're after ({ x, y, vx, vy }); `bodies` are solid circles
# they can't walk through (the horse, the cart, the peasant):
# { x, y, r, slide }. `victims` are the bodies raiders' weapons can hurt
# (Vector3(x, y, r)). Returns the arrows loosed and melee blows landed this
# frame: { volleys, blows }.
func update(dt: float, target: Dictionary, bodies: Array, relentless := false, victims: Array = []) -> Dictionary:
	var volleys := []
	var blows := []
	var awake := Rig.view.grow(400)
	# How crowded the view is decides how often figures redraw (see Rig)
	var in_view := 0
	for e: Enemy in list:
		if e.alive() and Rig.view.has_point(e.position):
			in_view += 1
	Rig.crowd_step = 1 if in_view <= 60 else (2 if in_view <= 150 else 3)
	for e: Enemy in list:
		if e.removed:
			continue
		# Level of detail: the settled dead need nothing; out of sight, the idle
		# think a few times a second and the hunting every few frames.
		var interval := 0.0
		if not e.alive():
			if e.dying > 2.0:
				continue
		elif not Rig.view.has_point(e.position):
			interval = 0.05 if e.state == "chase" else (0.25 if not awake.has_point(e.position) else 0.1)
		e.held += dt
		if e.held < interval:
			continue
		var step := e.held
		e.held = 0.0
		var landed_before: bool = e.blow != null and e.blow.landed
		e.update(step, target, relentless, victims)
		if e.blow != null and e.blow.landed and not landed_before:
			blows.append({"damage": e.damage, "faction": e.faction})
		if e.wants_shot:
			e.wants_shot = false
			var dist := Vector2(target.x, target.y).distance_to(e.position)
			if e.alive() and dist <= e.shoots.range:
				# Lead the target by the arrow's flight time.
				var t: float = dist / e.shoots.speed
				volleys.append({
					"x": e.position.x,
					"y": e.position.y,
					"aim_x": target.x + target.vx * t,
					"aim_y": target.y + target.vy * t,
					"speed": e.shoots.speed,
					"range": e.shoots.range + 80,
					"damage": e.damage,
					"faction": e.faction,
				})
	_file()
	_separate()
	_keep_off(bodies)
	_clear_away()
	return {"volleys": volleys, "blows": blows}


# The fallen stay where they lie (until their camp is left far behind), but
# only so many: the oldest are cleared away first. (Only rebuilds the list
# when something actually goes.)
func _clear_away() -> void:
	var corpses := 0
	var gone := 0
	for e: Enemy in list:
		if e.removed:
			gone += 1
		elif not e.alive():
			corpses += 1
	if gone == 0 and corpses <= MAX_CORPSES:
		return
	var kept := []
	for e: Enemy in list:
		var drop := e.removed
		if not drop and not e.alive() and corpses > MAX_CORPSES:
			drop = true
			corpses -= 1
		if drop:
			e.queue_free()
		else:
			kept.append(e)
	list = kept


# --- Who's near whom -----------------------------------------------------------

const CELL := 48.0 # wider than any two raiders side by side
var _cells := {} # Vector2i -> Array of the living, refiled every frame


func _file() -> void:
	_cells.clear()
	for e: Enemy in list:
		if e.removed or not e.alive():
			continue
		var key := Vector2i(floori(e.position.x / CELL), floori(e.position.y / CELL))
		if _cells.has(key):
			_cells[key].append(e)
		else:
			_cells[key] = [e]


# The living within about `reach` of `at` (some may be a little further).
func near(at: Vector2, reach: float) -> Array:
	var out := []
	var lo := Vector2i(floori((at.x - reach) / CELL), floori((at.y - reach) / CELL))
	var hi := Vector2i(floori((at.x + reach) / CELL), floori((at.y + reach) / CELL))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var key := Vector2i(cx, cy)
			if _cells.has(key):
				out.append_array(_cells[key])
	return out


# The horse and cart (and peasant) are solid: push raiders out to their edge
# and stop them pressing inward, so they crowd round instead of walking
# through.
func _keep_off(bodies: Array) -> void:
	for b in bodies:
		for e: Enemy in near(Vector2(b.x, b.y), b.r + 25):
			if e.in_hiding:
				continue
			var d := e.position - Vector2(b.x, b.y)
			var dist := d.length()
			if dist == 0.0:
				dist = 1.0
			var overlap: float = e.radius + b.r - dist
			if overlap <= 0:
				continue
			var n := d / dist
			e.position += n * overlap
			var inward := e.vx * n.x + e.vy * n.y
			if inward < 0:
				e.vx -= inward * n.x
				e.vy -= inward * n.y
			# Something in the way of where they're going (`slide`): work round
			# it instead of pressing into it.
			if b.get("slide", false):
				if not e.slide_side:
					e.slide_side = -1 if randf() < 0.5 else 1
				var along := e.vx * -n.y + e.vy * n.x
				var side := signf(along) if absf(along) > 10 else float(e.slide_side)
				var pace := maxf(absf(along), e.speed * 0.9)
				e.vx = -n.y * side * pace
				e.vy = n.x * side * pace


# Raiders don't stand in each other: each pair that overlaps is pushed apart.
# (Pairs are only looked for among neighbouring cells, not every raider
# against every other.)
const _AHEAD := [Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]


func _separate() -> void:
	for key: Vector2i in _cells:
		var here: Array = _cells[key]
		for a in here.size():
			var e1: Enemy = here[a]
			if e1.in_hiding:
				continue
			for b in range(a + 1, here.size()):
				_push_apart(e1, here[b])
			for step: Vector2i in _AHEAD:
				var next: Variant = _cells.get(key + step)
				if next:
					for e2: Enemy in next:
						_push_apart(e1, e2)


static func _push_apart(e1: Enemy, e2: Enemy) -> void:
	if e2.in_hiding:
		return
	var d := e2.position - e1.position
	var reach := e1.radius + e2.radius
	if absf(d.x) >= reach or absf(d.y) >= reach:
		return
	var dist := d.length()
	if dist == 0.0:
		dist = 1.0
	var overlap := reach - dist
	if overlap > 0:
		var push := d / dist * overlap * 0.5
		e1.position -= push
		e2.position += push
