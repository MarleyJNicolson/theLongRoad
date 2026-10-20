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
	for e: Enemy in list:
		var landed_before: bool = e.blow != null and e.blow.landed
		e.update(dt, target, relentless, victims)
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
	_separate()
	_keep_off(bodies)

	# The fallen stay where they lie (until their camp is left far behind), but
	# only so many: the oldest are cleared away first.
	var corpses := list.filter(func(e: Enemy) -> bool: return not e.alive()).size()
	list = list.filter(func(e: Enemy) -> bool:
		var gone := e.removed or (not e.alive() and corpses > MAX_CORPSES)
		if not e.alive() and not e.removed and gone:
			corpses -= 1
		if not gone:
			return true
		e.queue_free()
		return false)
	return {"volleys": volleys, "blows": blows}


# The horse and cart (and peasant) are solid: push raiders out to their edge
# and stop them pressing inward, so they crowd round instead of walking
# through.
func _keep_off(bodies: Array) -> void:
	for e: Enemy in list:
		if e.in_hiding or not e.alive():
			continue
		for b in bodies:
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


func _separate() -> void:
	var alive := living()
	for a in alive.size():
		for b in range(a + 1, alive.size()):
			var e1: Enemy = alive[a]
			var e2: Enemy = alive[b]
			var d := e2.position - e1.position
			var dist := d.length()
			if dist == 0.0:
				dist = 1.0
			var overlap := e1.radius + e2.radius - dist
			if overlap > 0:
				var push := d / dist * overlap * 0.5
				e1.position -= push
				e2.position += push
