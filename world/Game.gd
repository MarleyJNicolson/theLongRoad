class_name Game
extends Node2D

# The main loop and glue (port of Game.js). Lives inside the world viewport,
# which renders at art resolution; Main scales it up and runs the pixel-art
# pass. So far: the layer stack, the road, the horse and cart, stamina,
# regions and the camera.
#
# Screen-space numbers from the JS (the camera margin, the pointer) were in CSS
# pixels; here the camera works in art pixels and converts with css_per_art.

const PX_PER_METRE := 20.0
const STAMINA_DRAIN := 1.0 / 4.0 # a full bar lasts 4 s of galloping
const STAMINA_REGEN := 1.0 / 7.0 # and refills in 7 s
const STAMINA_REGEN_DELAY := 0.8
const WINDED_UNTIL := 0.3 # once emptied, the horse must recover this much first
const KMH_PER_PX := 15.0 / 230.0
const STAGE_BANNER_TIME := 4.0
const CAMERA_MARGIN := 90.0 # closest the player gets to the screen edge (CSS px)
const MOUNT_REACH := 48.0 # how close to the cart to climb back on
const TOAST_TIME := 1.8
# On foot you can't stray too far from the cart: a warning past WARN_DISTANCE
# and no further than LEASH (px)
const WARN_DISTANCE := 1300.0 # (700 in the JS)
const LEASH := 1500.0 # (860 in the JS)
# The peasant's own stamina (the horse has its own): sprinting drains it, a
# dash takes a chunk at once, and it comes back after a short rest.
const SPRINT_DRAIN := 1.0 / 4.5 # a full bar lasts 4.5 s of sprinting
const DASH_COST := 0.3
const DASH_COOLDOWN := 0.45
const BREATH_REGEN := 1.0 / 3.0
const BREATH_REGEN_DELAY := 0.6
const MAX_HEALTH := 5 # the peasant's hearts, hurt only on foot
const MAX_CART_HEALTH := 10 # the cart takes the blows while you ride
const INVULNERABLE := 0.8 # seconds of grace after being hit
const CART_REACH := 22.0 # extra melee reach swinging down from the cart
const ITEM_CHANCE := 0.45 # chance a chest also holds armour or a weapon
const LOOT_REACH := 34.0 # how close to stand to search a container
const TRADE_REACH := 46.0 # how close to stand to a trader
const STORAGE_REACH := 90.0 # how close to stand to the cart to use its storage

# Set by Main: world units → art pixels, and CSS pixels per art pixel.
var art_zoom := PixelArt.WORLD_ZOOM / PixelArt.PIXEL_SIZE
var css_per_art := float(PixelArt.PIXEL_SIZE)
# The mouse, in art pixels over the world view (set by Main). `pointer_active`:
# it has been over the game at least once.
var pointer := Vector2.ZERO
var pointer_active := false
var pointer_inside := true # over the game right now (not off-window)
var pointer_over_ui := false # over a HUD panel: clicks there aren't attacks (set by Main)

var backdrop: Sprite2D
var ground: Node2D
var road_edge: Node2D
var road_fill: Node2D
var props: Node2D
var aim: Node2D
var fx: Node2D
var fallen: Node2D
var raiders: Node2D
var actors: Node2D
var canopy: Node2D
var air: Node2D

var road: Road
var scenery: Scenery
var encounters: Encounters
var solids := Obstacles.new() # everything solid, for quick lookups nearby
var trading: Variant = null # the trader whose wares are on show
var town: Variant = null # the town you're in, if any: { name, safe, inn }
var clock := 0.0 # seconds since the first morning (see DayNight)
var was_night := false
var sky: CanvasModulate # tints the whole world for the time of day
var war_bands: WarBands
var rest_fade := 0.0 # the screen fading back in after a night at the inn
var start_clock := 0.0 # debug: `--clock=N` starts N seconds into the day
var cart: HorseCart
var peasant: Peasant
var marker: Painter
var on_foot := false
var breath := 1.0 # the peasant's stamina, 0..1
var breath_rest := 0.0
var out_of_breath := false
var sprinting := false
var dash_cooldown := 0.0
var dash_guard := 0.0 # untouchable while dashing
var puffs: Array = [] # { g, t }
var interaction: Variant = null # what pressing E would do: { label, x, y, act }
var toast: Variant = null # { text, t }
var road_index := 3
var best := 0.0 # furthest progress along the main road (px)
var metres := 0
var stamina := 1.0
var stamina_rest := 0.0
var winded := false
var galloping := false
var time := 0.0
var stage: Dictionary
var banner: Variant = null # { title, sub, t }
var ground_colour: Color
var cam := Vector2.ZERO
var shake := 0.0

var enemies: Enemies
var missiles: Missiles
var blood: Blood
var enemy_arrows: EnemyArrows
var aim_line: Painter
var state := "playing" # or "over"
var over_reason := {} # { title, text }
var health := MAX_HEALTH
var cart_health := MAX_CART_HEALTH
var invulnerable := 0.0
var block_flash := 0.0
var kills := 0
var gold := 0
var equipment := {} # slot -> item (or null)
var active := "ranged" # which weapon is in hand: ranged or melee
var throw_cooldown := 0.0
var melee_cooldown := 0.0
var strikes: Array = [] # melee blows waiting to land (see _update_melee)
var swings: Array = [] # their visible strokes: { g, t, life }
var pickups: Array = [] # coins and hearts popping up: { g, kind, t }
var out_of_ammo_at := -9.0
var bag: Array = []
var cart_store: Array = []
var bag_open := false
var cart_open := false
var blocking := false # holding a shield up (right mouse)
var companions: Array = [] # who rides along to defend the cart (see Companion)
# Dev mode (F10): ammunition is never used up, and the debug keys are listed
var dev_mode := false
# The scoreboard: the run waiting to be signed (null once it's on the board),
# and what the game-over screen shows: { naming } or { rank, score, top }
var unsaved: Variant = null
var scoreboard: Dictionary = {}
var last_name := Scoreboard.last_name()
var typing := false # the name box has the keyboard (set by the HUD)
var _dressed_as: Array = [] # the armour the peasant was last drawn in


func _ready() -> void:
	Controls.setup()
	# The ground: a sheet of grass texture behind the world, anchored to it
	# and tinted to the region's colour. Resized to cover the view each frame.
	backdrop = Sprite2D.new()
	backdrop.texture = Textures.grass_texture()
	backdrop.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	backdrop.region_enabled = true
	backdrop.centered = false
	add_child(backdrop)
	sky = CanvasModulate.new()
	add_child(sky)
	reset()


func reset() -> void:
	# Restarting without signing still puts the run on the board
	if unsaved != null:
		save_run(last_name)
	scoreboard = {}
	_read_debug_args()
	if encounters:
		encounters.dispose()
	for layer in [ground, road_edge, road_fill, props, aim, fx, fallen, raiders, actors, canopy, air]:
		if layer:
			layer.queue_free()
	ground = _layer("Ground")
	road_edge = _layer("RoadEdge")
	road_fill = _layer("RoadFill")
	props = _layer("Props") # flat encounter decals
	aim = _layer("Aim")
	fx = _layer("Fx") # dust and such at ground level
	# The dead lie under all the living (the JS sorted them at y - 1e6; Godot's
	# z_index is global, so they get a layer of their own)
	fallen = _layer("Fallen")
	raiders = _layer("Raiders") # everything upright, sorted by where it meets the ground
	raiders.y_sort_enabled = true
	actors = _layer("Actors")
	canopy = _layer("Canopy")
	air = _layer("Air")

	road = Road.new(road_edge, road_fill)
	road.ensure_ahead(0)
	enemies = Enemies.new(raiders, fallen)
	encounters = Encounters.new(props, raiders, road, enemies)
	encounters.place() # before the scenery, so trees keep out of camps
	scenery = Scenery.new(ground, raiders, road, encounters.zones) # trees stand among the people
	encounters.on_new_zones = scenery.clear
	scenery.update(0)
	solids = Obstacles.new()
	solids.refresh(scenery.obstacles(), encounters.obstacles())
	trading = null
	town = null
	war_bands = WarBands.new(enemies, road)
	clock = start_clock
	was_night = DayNight.is_night(clock)
	rest_fade = 0.0
	missiles = Missiles.new(air)
	enemy_arrows = EnemyArrows.new(air)
	blood = Blood.new(fx, air)
	Blood.current = blood
	aim_line = Painter.new(_draw_aim)
	aim.add_child(aim_line)
	pickups = []

	var start := road.points[3]
	cart = HorseCart.new(raiders, start.x, start.y, -PI / 2) # depth-sorted with the people
	peasant = Peasant.new() # among the raiders, so they overlap by depth
	raiders.add_child(peasant)
	marker = Painter.new(_draw_marker)
	actors.add_child(marker)
	on_foot = false
	breath = 1.0
	breath_rest = 0.0
	out_of_breath = false
	dash_cooldown = 0.0
	dash_guard = 0.0
	puffs = []
	interaction = null
	toast = null
	road_index = 3
	best = Road.start_along
	metres = floori(best / PX_PER_METRE)
	stamina = 1.0
	stamina_rest = 0.0
	winded = false
	time = 0.0
	cam = start
	shake = 0.0
	stage = Threat.stage_at(metres)
	banner = {"title": stage.name, "sub": stage.biome.tagline, "t": STAGE_BANNER_TIME}
	ground_colour = stage.biome.ground
	backdrop.modulate = ground_colour

	state = "playing"
	over_reason = {}
	health = MAX_HEALTH
	cart_health = MAX_CART_HEALTH
	invulnerable = 0.0
	block_flash = 0.0
	kills = 0
	gold = 0
	equipment = {}
	for slot in Items.SLOTS:
		equipment[slot] = null
	active = "ranged"
	throw_cooldown = 0.0
	melee_cooldown = 0.0
	strikes = []
	swings = []
	out_of_ammo_at = -9.0
	companions = []
	_dressed_as = []
	bag = []
	bag.resize(Items.BAG_SIZE)
	cart_store = []
	cart_store.resize(Items.CART_SIZE)
	bag_open = false
	cart_open = false
	# Setting out with a few stones to throw
	bag[0] = {"type": "stones", "count": 20}
	cart_store[0] = {"type": "stones", "count": 30}
	# Debug: `--equip=Hunting Bow,Bearded Axe` starts with those (and ammo)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--equip="):
			for item_name in arg.trim_prefix("--equip=").split(","):
				var item := Items.named(item_name)
				equipment[item.slot] = item
				if item.slot == "ranged" or item.slot == "melee":
					active = item.slot
				if item.has("ammo"):
					stash(cart_store, item.ammo, 30)
		# `--give=Mail Shirt,poultice` puts gear (or supplies) in the bag
		elif arg.begins_with("--give="):
			for thing in arg.trim_prefix("--give=").split(","):
				if Items.CONSUMABLES.has(thing):
					add_to_bag({"type": thing, "count": 3})
				else:
					add_to_bag({"type": "gear", "item": Items.named(thing)})


func _exit_tree() -> void:
	if encounters:
		encounters.dispose()


func _layer(layer_name: String) -> Node2D:
	var layer := Node2D.new()
	layer.name = layer_name
	add_child(layer)
	return layer


func _process(delta: float) -> void:
	var dt := minf(delta, 0.05)
	if state == "over":
		# (Just pressed, not held: a quick tap between frames must count; not
		# while typing your name, where Space is a space)
		if Controls.pressed("restart") and not typing:
			reset()
		return
	time += dt
	_mark("")
	_update_sky(dt)
	_mark("sky")
	if debug_autoaim:
		_debug_aim()
	if debug_goto and time > 0.3:
		_debug_goto()
	if _debug_spawn_pending and time > 0.5:
		_debug_spawn_pending = false
		debug_spawn()

	var keys := {
		"up": Controls.held("up"),
		"down": Controls.held("down"),
		"left": Controls.held("left"),
		"right": Controls.held("right"),
	}
	if debug_autodrive and not on_foot:
		var ahead := road.points[mini(road_index + 4, road.points.size() - 1)]
		var turn := wrapf((ahead - Vector2(cart.x, cart.y)).angle() - cart.heading, -PI, PI)
		keys.left = turn < -0.05
		keys.right = turn > 0.05
	keys.boost = _update_stamina(dt, keys)
	galloping = keys.boost
	if not on_foot:
		_update_breath(dt, keys)
	_update_puffs(dt)
	solids.refresh(scenery.obstacles(), encounters.obstacles())
	interaction = _interaction()
	_mark("obstacles")
	if Controls.pressed("interact") and interaction:
		interaction.act.call()
	if Controls.pressed("bag"):
		toggle_bag()
	if Controls.pressed("cart"):
		toggle_cart()
	if cart_open and not near_cart():
		cart_open = false
		say("You walk away from the cart")
	if Controls.pressed("close"):
		trading = null
		bag_open = false
		cart_open = false
	if Controls.pressed("swap"):
		swap_weapon()
	# A shield is up while right mouse is held (not over a panel, where
	# right-click sells), for as long as there's breath to block with
	blocking = shield() != null and Controls.held("block") and not pointer_over_ui and not out_of_breath

	_mark("input")
	var near := road.nearest(cart.x, cart.y, road_index)
	road_index = near.index
	var on_main_road: bool = near.dist < Road.ROAD_WIDTH / 2 + 4
	var on_road := on_main_road or encounters.on_side_road(Vector2(cart.x, cart.y))
	_mark("road.nearest")

	cart.update(dt, {} if on_foot else keys, on_road, solids.near(Vector2(cart.x, cart.y), 170), on_foot)
	if on_foot:
		var cart_solids := cart.bodies()
		sprinting = _update_breath(dt, keys)
		peasant.update(dt, keys, pointer_world(), solids.near(peasant.position, 60) + Array(cart_solids), sprinting, blocking)
		_keep_near_cart()
		if peasant.dashing() and randf() < 0.6:
			_puff(peasant.position)
	else:
		sprinting = false
	_mark("cart+peasant")

	if on_main_road:
		best = maxf(best, near.along)
	metres = floori(best / PX_PER_METRE)

	road.ensure_ahead(road_index)
	road.cull(road_index)
	_mark("road")
	encounters.place()
	_mark("encounters.place")
	scenery.update(road_index, 1) # (one stretch a frame: the road only needs ~8 a second)
	_mark("scenery.update")

	var from := player()
	_update_throwing(dt, from)
	Enemies.safe_zones = encounters.towns().map(func(t: Dictionary) -> Vector3: return t.safe)
	encounters.update(dt, from, road_index)
	_mark("encounters.update")
	var here: Variant = encounters.town_at(Vector2(from.x, from.y))
	if here and here != town:
		_arrive(here)
	town = here
	war_bands.update(dt, DayNight.is_night(clock), {"pos": Vector2(from.x, from.y), "on_cart": not on_foot, "sprinting": sprinting},
		road_index, metres, encounters.towns().map(func(t: Dictionary) -> Vector3: return t.safe))
	for message in war_bands.messages:
		say(message)
	war_bands.messages.clear()
	if war_bands.jolt > 0:
		shake = maxf(shake, war_bands.jolt)
		war_bands.jolt = 0.0
	_mark("war_bands")
	# On foot, the cart is just in the way and raiders go round it.
	var bodies := []
	for b in cart.bodies():
		bodies.append({"x": b.x, "y": b.y, "r": b.z, "slide": on_foot})
	if on_foot:
		bodies.append({"x": peasant.position.x, "y": peasant.position.y, "r": Peasant.RADIUS})
	# On foot they'll hunt you down however far you go; a cart can outrun them.
	# What raiders' weapons and arrows can hurt: you on foot, the horse and
	# cart while you ride.
	var targets: Array = [Vector3(peasant.position.x, peasant.position.y, Peasant.RADIUS)] if on_foot else Array(cart.bodies())
	var fight := enemies.update(dt, from, bodies, on_foot, targets)
	_mark("enemies")
	for v in fight.volleys:
		enemy_arrows.fire(v)
		Sfx.play("bow", Vector2(v.x, v.y), -5.0)
	for b in fight.blows:
		hurt(b.damage, b.faction, false, b.from)
	for h in enemy_arrows.update(dt, targets, solids):
		hurt(h.damage, h.faction, true, h.from)
	for c in companions:
		c.update(dt, cart.cart_heading, enemies, missiles)
	# The garrisons' crossbowmen, at their posts
	for guard in encounters.guards():
		guard.update(dt, guard.get_meta("post"), enemies, missiles)
	for e in missiles.update(dt, enemies):
		_on_kill(e)
	blood.update(dt)
	_mark("arrows+missiles")
	_update_melee(dt, from)
	_update_held_weapon(dt)
	_mark("melee+held")
	for reward in encounters.rewards:
		gold += reward.gold
		scatter("coin", reward.gold, reward.x, reward.y)
		say("%s: +%d gold" % [reward.get("message", "The farmer thanks you"), reward.gold], 1.5)
	encounters.rewards.clear()
	_update_pickups(dt)
	_update_attacks(dt)
	_mark("pickups+attacks")

	interaction = _interaction()
	marker.queue_redraw()
	_mark("interaction")

	_update_stage(dt)
	# Trees between you and the camera fade so you can see yourself
	var me := player()
	scenery.fade_around(me.x, me.y)
	encounters.fade_around(me.x, me.y)
	_mark("stage+fade")
	update_camera(dt)
	_mark("camera")
	if toast:
		toast.t -= dt
		if toast.t <= 0:
			toast = null


# Debug (`--prof`): how long each stage of the frame takes, averaged and
# printed every few seconds.
var _prof_on := "--prof" in OS.get_cmdline_user_args()
var _prof := {}
var _prof_last := 0
var _prof_frames := 0
var _prof_print := 0.0


func _mark(stage: String) -> void:
	if not _prof_on:
		return
	var now := Time.get_ticks_usec()
	if stage == "":
		_prof_frames += 1
		if time > _prof_print + 5:
			_prof_print = time
			var parts := []
			for k in _prof:
				parts.append("%s %.2f" % [k, _prof[k] / 1000.0 / maxi(1, _prof_frames)])
			print("ms/frame: ", ", ".join(parts))
			_prof.clear()
			_prof_frames = 0
	else:
		_prof[stage] = _prof.get(stage, 0) + now - _prof_last
	_prof_last = now


func say(text: String, extra := 0.0) -> void:
	toast = {"text": text, "t": TOAST_TIME + extra}


# --- Loot -------------------------------------------------------------------

# Open a chest: gold goes in the purse; poultices, planks and gear go in the
# bag. Better gear is put on straight away (the old piece is bagged).
func search(chest: Dictionary) -> void:
	var found: Dictionary = chest.open.call()
	var parts := []
	var purse := {"coins": found.gold}
	var stow := func(entry: Dictionary, label: String) -> void:
		if add_to_bag(entry):
			parts.append(label)
		else:
			purse.coins += value_of(entry)
			parts.append("%s (bag full, sold)" % label)
	if found.health:
		stow.call({"type": "poultice", "count": 1}, "a healing poultice")
	if found.repair:
		stow.call({"type": "planks", "count": 1}, "planks & nails")
	for kind in ["arrows", "bolts"]:
		if not found[kind]:
			continue
		var lost := stash_ammo(kind, found[kind])
		if lost:
			parts.append("%d %s (bag full, %d left behind)" % [found[kind] - lost, kind, lost])
		else:
			parts.append("%d %s" % [found[kind], kind])

	var note := ""
	if randf() < ITEM_CHANCE:
		var item := Items.roll_item(best / PX_PER_METRE)
		var worn: Variant = equipment[item.slot]
		if not worn or item.tier > worn.tier:
			equipment[item.slot] = item
			parts.append("a %s" % item.name)
			note = " – equipped"
			if worn:
				if add_to_bag({"type": "gear", "item": worn}):
					note += ", %s put in your bag" % worn.name
				else:
					purse.coins += Items.sell_value(worn)
					note += ", sold your %s (bag full)" % worn.name
		else:
			stow.call({"type": "gear", "item": item}, "a %s" % item.name)
	gold += purse.coins
	scatter("coin", purse.coins, chest.x, chest.y)
	parts.push_front("%d gold" % purse.coins)
	var listed: String = parts[0] if parts.size() == 1 else ", ".join(parts.slice(0, -1)) + " and " + parts[-1]
	say("Found %s%s" % [listed, note], 2)


# E at an arrow barrel: take what fits, leave the rest in the barrel.
func raid_barrel(barrel: Dictionary) -> void:
	var took := []
	for kind in ["arrows", "bolts"]:
		var have: int = barrel.contents[kind]
		if not have:
			continue
		var left := stash_ammo(kind, have)
		if have - left:
			took.append("%d %s" % [have - left, kind])
		barrel.contents[kind] = left
	barrel.update.call()
	if took.is_empty():
		say("Your bag is full")
		return
	say("Took %s%s" % [" and ".join(took), "" if barrel.opened else " – your bag is full, some are left"])


# E at a rock or boulder: prise out what stones your bag has room for.
func gather(rock: Dictionary) -> void:
	var take := mini(rock.gather, ammo_room("stones"))
	if not take:
		say("Your bag has no room for more stones")
		return
	stash_ammo("stones", take)
	scenery.quarry(rock, take)
	var left := ""
	if rock.gather:
		left = " – your bag is full, %d left" % rock.gather
	say("Gathered %d stones%s" % [take, left])


# What an entry in the bag is worth to a merchant.
func value_of(entry: Dictionary) -> int:
	if entry.type == "gear":
		# (a quiver goes with whatever's in it)
		var worth := Items.sell_value(entry.item)
		for e in entry.item.get("contents", []):
			if e:
				worth += value_of(e)
		return worth
	var info: Dictionary = Items.CONSUMABLES[entry.type]
	return floori(entry.count / 10.0 * info.value) if info.has("ammo") else info.value


# Stack consumables, otherwise take the first free slot. False if full.
func add_to_bag(entry: Dictionary) -> bool:
	if entry.type != "gear":
		if room_for(bag, entry.type) < entry.get("count", 1):
			return false
		stash(bag, entry.type, entry.get("count", 1))
		return true
	var free := bag.find(null)
	if free < 0:
		return false
	bag[free] = entry.duplicate()
	return true


# --- Towns ------------------------------------------------------------------

# Into a town: safe from raiders, and the townsfolk mend the cart, bind your
# wounds and rest the horse, free of charge.
func _arrive(place: Dictionary) -> void:
	var mended := health < MAX_HEALTH or cart_health < MAX_CART_HEALTH
	health = MAX_HEALTH
	cart_health = MAX_CART_HEALTH
	stamina = 1.0
	winded = false
	breath = 1.0
	out_of_breath = false
	banner = {"title": place.name, "sub": Towns.MOTTO, "t": STAGE_BANNER_TIME}
	if mended:
		say("The folk of %s mend your cart and bind your wounds" % place.name, 1.5)
	else:
		say("You rest awhile in %s" % place.name, 1.5)


# --- Day and night -------------------------------------------------------------

# Which day it is (from 1).
func day() -> int:
	return floori(clock / DayNight.CYCLE) + 1


# Time passes: the world darkens toward night and lights come up; nightfall
# and dawn are announced.
func _update_sky(dt: float) -> void:
	clock += dt
	rest_fade = maxf(0.0, rest_fade - dt / 1.5)
	var dark := DayNight.darkness(clock)
	sky.color = DayNight.tint(clock)
	Glow.shine(get_tree(), dark)
	var night := DayNight.is_night(clock)
	if night and not was_night:
		banner = {"title": "Nightfall", "sub": "War bands roam the dark · make for a garrison", "t": STAGE_BANNER_TIME}
	elif was_night and not night:
		banner = {"title": "Dawn", "sub": "Day %d" % day(), "t": STAGE_BANNER_TIME}
	was_night = night


# E at the inn, by night: sleep until morning, waking healed with the cart
# mended, and the war bands gone.
func rest_until_dawn() -> void:
	if not town:
		return
	clock = (floorf(clock / DayNight.CYCLE) + 1) * DayNight.CYCLE
	was_night = false
	rest_fade = 1.0
	war_bands.clear()
	health = MAX_HEALTH
	cart_health = MAX_CART_HEALTH
	stamina = 1.0
	winded = false
	breath = 1.0
	out_of_breath = false
	banner = {"title": "Day %d" % day(), "sub": "You wake rested at the inn of %s" % town.name, "t": STAGE_BANNER_TIME}


# --- Bag and cart storage ----------------------------------------------------

func toggle_bag() -> void:
	bag_open = not bag_open


# The cart's storage can only be reached from the cart or right beside it.
func near_cart() -> bool:
	if not on_foot:
		return true
	return Vector2(cart.cart_x, cart.cart_y).distance_to(peasant.position) < STORAGE_REACH


func toggle_cart() -> void:
	if cart_open:
		cart_open = false
		return
	if not near_cart():
		say("You need to be at the cart")
		return
	cart_open = true
	bag_open = true # so there's somewhere to move things to


func container(container_name: String) -> Array:
	if container_name == "quiver":
		var q: Variant = quiver()
		return q if q != null else []
	return cart_store if container_name == "cart" else bag


# Pour a stack of supplies into any part-filled stacks of the same kind.
# Returns how many are left over.
func _top_up(list: Array, entry: Dictionary) -> int:
	var top: int = Items.CONSUMABLES[entry.type].stack
	for other in list:
		if not entry.count:
			break
		if is_same(other, entry) or not other or other.type != entry.type:
			continue
		var moved := mini(top - other.count, entry.count)
		other.count += moved
		entry.count -= moved
	return entry.count


# Move something between (or within) the bag and the cart. With a slot `j` it
# goes there (swapping with whatever is in it); with j = -1, it goes wherever
# it fits. Anything involving the cart needs you to be at it.
func move_item(from: String, i: int, to: String, j := -1) -> void:
	if state == "over":
		return
	if (from == "cart" or to == "cart") and not (cart_open and near_cart()):
		say("You need to be at the cart")
		return
	var src := container(from)
	var dst := container(to)
	if i >= src.size() or j >= dst.size():
		return
	var entry: Variant = src[i]
	if not entry or (from == to and (j == -1 or j == i)):
		return
	if to == "quiver" and not Items.CONSUMABLES.get(entry.type, {}).has("ammo"):
		say("Only arrows, bolts and stones go in the quiver")
		return
	if from == "quiver" and j != -1 and dst[j] and not Items.CONSUMABLES.get(dst[j].type, {}).has("ammo"):
		say("Only arrows, bolts and stones go in the quiver")
		return
	if j != -1:
		var there: Variant = dst[j]
		if there and there.type == entry.type and entry.type != "gear":
			# Same supplies: stack them, leaving any overflow where it was
			var moved := mini(Items.CONSUMABLES[entry.type].stack - there.count, entry.count)
			there.count += moved
			entry.count -= moved
			if not entry.count:
				src[i] = null
		else:
			dst[j] = entry
			src[i] = there
		return
	if entry.type != "gear" and _top_up(dst, entry) == 0:
		src[i] = null
		return
	var free := dst.find(null)
	if free < 0:
		say("The cart is full" if to == "cart" else "Your bag is full")
		return
	dst[free] = entry
	src[i] = null


# Click on a bag slot: put gear on (swapping with what's worn), or use a
# poultice or planks.
func use_bag_item(i: int) -> void:
	var entry: Variant = bag[i]
	if not entry or state == "over":
		return
	if entry.type == "gear":
		var item: Dictionary = entry.item
		var worn: Variant = equipment[item.slot]
		equipment[item.slot] = item
		bag[i] = {"type": "gear", "item": worn} if worn else null
		say("Equipped %s" % item.name)
		return
	if Items.CONSUMABLES[entry.type].has("ammo"):
		if quiver() != null:
			move_item("bag", i, "quiver")
		else:
			say("Ammunition is used up as you shoot")
		return
	if entry.type == "poultice":
		if health >= MAX_HEALTH:
			say("You are already in good health")
			return
		health += 1
		var me := player()
		_drop("heart", me.x, me.y)
		say("You bind your wounds (+1 ♥)")
	else:
		if cart_health >= MAX_CART_HEALTH:
			say("The cart needs no mending")
			return
		cart_health = mini(MAX_CART_HEALTH, cart_health + 2)
		_drop("plank", cart.cart_x, cart.cart_y)
		say("You patch up the cart (+2)")
	entry.count -= 1
	if entry.count <= 0:
		bag[i] = null


# Right-click on a bag (or cart) slot: sell one of it.
func sell_bag_item(i: int, from := "bag") -> void:
	var list := container(from)
	var entry: Variant = list[i]
	if not entry or state == "over":
		return
	if from == "cart" and not (cart_open and near_cart()):
		return
	var value := value_of(entry)
	gold += value
	var thing: String
	var ammo := false
	if entry.type == "gear":
		thing = entry.item.name
	else:
		var info: Dictionary = Items.CONSUMABLES[entry.type]
		ammo = info.has("ammo")
		thing = "%d %s" % [entry.count, info.name.to_lower()] if ammo else info.name
	# Ammunition goes as a whole stack; everything else one at a time
	if entry.type == "gear" or ammo:
		list[i] = null
	else:
		entry.count -= 1
		if entry.count <= 0:
			list[i] = null
	say("Sold %s for %d gold" % [thing, value])


# Click on an equipped slot: take it off and put it in the bag.
func unequip(slot: String) -> void:
	var item: Variant = equipment[slot]
	if not item or state == "over":
		return
	if not add_to_bag({"type": "gear", "item": item}):
		say("Your bag is full")
		return
	equipment[slot] = null
	say("Took off %s" % item.name)


# The item a bag or cart entry is (gear, or the consumable it's a stack of).
static func entry_item(entry: Dictionary) -> Dictionary:
	return entry.item if entry.type == "gear" else Items.CONSUMABLES[entry.type]


# --- Trading -----------------------------------------------------------------

# What the open trader's stall looks like to the HUD, or null:
# { name, offers: [{ i, kind, type, name, item, price, sold, why }] }.
func trade_view() -> Variant:
	var t: Variant = trading
	if not t:
		return null
	# Walking off (or climbing on the cart) ends the conversation.
	if not on_foot or not t.open or Vector2(t.x, t.y).distance_to(peasant.position) > TRADE_REACH + 40:
		trading = null
		return null
	# Stalls shut at nightfall
	if DayNight.is_night(clock):
		trading = null
		say("The %s shuts up shop for the night" % t.name.to_lower())
		return null
	var offers := []
	for i in t.stock.size():
		var offer: Dictionary = t.stock[i]
		var price := price_of(offer)
		var item: Variant = null
		if offer.kind == "gear":
			item = offer.item
		elif offer.kind == "consumable":
			item = Items.CONSUMABLES[offer.type]
		var offer_name: String
		if offer.has("qty"):
			offer_name = "%d %s" % [offer.qty, item.name]
		else:
			offer_name = item.name if item else offer.name
		offers.append({"i": i, "kind": offer.kind, "type": offer.get("type", ""), "name": offer_name, "item": item,
			"price": price, "sold": offer.get("sold", false), "why": cannot_buy(offer, price)})
	return {"name": t.name, "offers": offers}


func price_of(offer: Dictionary) -> int:
	if offer.get("type") == "repair":
		return offer.price * (MAX_CART_HEALTH - cart_health)
	if offer.get("type") == "heal":
		return offer.price * (MAX_HEALTH - health)
	return offer.price


# Why an offer can't be bought right now, or "" if it can.
func cannot_buy(offer: Dictionary, price: int) -> String:
	if offer.get("sold", false):
		return "Sold"
	if offer.get("type") == "repair" and cart_health >= MAX_CART_HEALTH:
		return "Cart is sound"
	if offer.get("type") == "heal" and health >= MAX_HEALTH:
		return "Already hale"
	if price > gold:
		return "Not enough gold"
	if offer.kind == "gear" and not bag.has(null):
		return "Bag full"
	if offer.kind == "consumable" and (ammo_room(offer.type) if Items.CONSUMABLES[offer.type].has("ammo") else room_for(bag, offer.type)) < offer.get("qty", 1):
		return "Bag full"
	return ""


func buy(i: int) -> void:
	if not trading or i >= trading.stock.size():
		return
	var offer: Dictionary = trading.stock[i]
	var price := price_of(offer)
	if cannot_buy(offer, price):
		return
	gold -= price
	if offer.kind == "gear":
		add_to_bag({"type": "gear", "item": offer.item})
		offer.sold = true
		say("Bought %s – it's in your bag" % offer.item.name)
	elif offer.kind == "consumable":
		var how_many: String = str(offer.qty) if offer.has("qty") else "a"
		if Items.CONSUMABLES[offer.type].has("ammo"):
			stash_ammo(offer.type, offer.get("qty", 1))
		else:
			stash(bag, offer.type, offer.get("qty", 1))
		say("Bought %s %s" % [how_many, Items.CONSUMABLES[offer.type].name])
	elif offer.type == "repair":
		cart_health = MAX_CART_HEALTH
		say("The wheelwright sets your cart to rights")
	elif offer.type == "heal":
		health = MAX_HEALTH
		say("The healer binds your wounds")


# --- Ammunition -------------------------------------------------------------

# On the cart, ammo comes from cart storage then the bag; on foot, the bag.
# A quiver comes before either.
func _ammo_sources() -> Array:
	var sources := [bag] if on_foot else [cart_store, bag]
	var q: Variant = quiver()
	if q != null:
		sources.push_front(q)
	return sources


# The quiver's stacks, if one is worn (or null).
func quiver() -> Variant:
	var item: Variant = equipment.get("offhand")
	if not item or item.get("kind") != "quiver":
		return null
	if not item.has("contents"):
		item.contents = []
		item.contents.resize(item.slots)
	return item.contents


# The shield, if one is worn (or null).
func shield() -> Variant:
	var item: Variant = equipment.get("offhand")
	return item if item and item.get("kind") == "shield" else null


# Put ammunition away: the quiver first, then the bag. Returns how many
# didn't fit.
func stash_ammo(type: String, count: int) -> int:
	var q: Variant = quiver()
	if q != null:
		count = stash(q, type, count)
	return stash(bag, type, count)


func ammo_room(type: String) -> int:
	var q: Variant = quiver()
	return room_for(bag, type) + (room_for(q, type) if q != null else 0)


# Is there a shot to loose? (Always, in dev mode.)
func has_ammo(kind: String) -> bool:
	return dev_mode or ammo_count(kind) > 0


func ammo_count(kind: String) -> int:
	var n := 0
	for list in _ammo_sources():
		for e in list:
			if e and e.type == kind:
				n += e.count
	return n


# Spend one round from the first stack found. False if there's none.
func _take_ammo(kind: String) -> bool:
	if dev_mode:
		return true
	for list in _ammo_sources():
		for k in range(list.size() - 1, -1, -1):
			var e: Variant = list[k]
			if not e or e.type != kind:
				continue
			e.count -= 1
			if e.count <= 0:
				list[k] = null
			return true
	return false


# Put `count` of a stackable into a bag or cart: topping up part stacks first,
# then filling empty slots. Returns how many didn't fit.
func stash(list: Array, type: String, count: int) -> int:
	var top: int = Items.CONSUMABLES[type].stack
	for e in list:
		if not count:
			break
		if not e or e.type != type or e.count >= top:
			continue
		var moved := mini(top - e.count, count)
		e.count += moved
		count -= moved
	while count > 0:
		var free := list.find(null)
		if free < 0:
			break
		var moved := mini(top, count)
		list[free] = {"type": type, "count": moved}
		count -= moved
	return count


# How many more of a stackable would fit.
func room_for(list: Array, type: String) -> int:
	var top: int = Items.CONSUMABLES[type].stack
	var n := 0
	for e in list:
		if e == null:
			n += top
		elif e.type == type:
			n += top - e.count
	return n


# --- Fighting ---------------------------------------------------------------

func ranged() -> Dictionary:
	return equipment.ranged if equipment.ranged else Items.BARE.ranged


func melee() -> Dictionary:
	return equipment.melee if equipment.melee else Items.BARE.melee


# Show the equipped weapons in hand, on foot or on the driver's bench: melee in
# the right hand, a bow, crossbow or sling in the left. Only the weapon in hand
# is drawn; the other is slung on your back.
func _update_held_weapon(_dt: float) -> void:
	# Armour shows on the peasant (and the driver, the same person)
	var worn := [equipment.helmet, equipment.shoulders, equipment.body, equipment.legs]
	if worn != _dressed_as:
		_dressed_as = worn
		var look := Peasant.dressed(equipment)
		peasant.rig.restyle(look)
		cart.rig.restyle(look)
	var stocked := has_ammo(ranged().ammo)
	# The next shot is drawn back as the weapon reloads: full draw = ready
	var draw := clampf(1 - throw_cooldown / ranged().cooldown, 0, 1)
	var ranged_in_hand: Variant = equipment.ranged if active == "ranged" else null
	var melee_in_hand: Variant = equipment.melee if active == "melee" else null
	# The left hand: a shield when it's raised, or held beside a melee weapon;
	# otherwise whatever ranged weapon is in hand
	var left: Variant = ranged_in_hand
	if shield() and (blocking or active == "melee"):
		left = shield()
	peasant.set_weapon(melee_in_hand)
	cart.set_weapon(melee_in_hand)
	peasant.set_bow(left, stocked, draw)
	cart.set_bow(left, stocked and draw >= 1)
	if not on_foot:
		var at := pointer_world()
		cart.aim = atan2(at.y - cart.cart_y, at.x - cart.cart_x) - cart.cart_heading


const SHOT_SOUNDS := {"arrow": "bow", "bolt": "crossbow", "stone": "sling"}


# R: put away one weapon and take out the other.
func swap_weapon() -> void:
	active = "melee" if active == "ranged" else "ranged"
	say("%s in hand" % (ranged() if active == "ranged" else melee()).name)


func _on_kill(enemy: Enemy) -> void:
	kills += 1
	gold += enemy.gold
	scatter("coin", enemy.gold, enemy.position.x, enemy.position.y)


func _update_throwing(dt: float, from: Dictionary) -> void:
	throw_cooldown -= dt
	var weapon := ranged()
	var target := pointer_world()
	var loaded := has_ammo(weapon.ammo)
	var in_hand := active == "ranged"
	var down := Controls.held("attack") and not pointer_over_ui and not blocking
	if in_hand and down and not loaded and time - out_of_ammo_at > 2:
		out_of_ammo_at = time
		say("Out of %s%s!" % [Items.AMMO[weapon.ammo].name.to_lower(), " in your bag" if on_foot else ""])
	if in_hand and down and throw_cooldown <= 0 and loaded:
		missiles.throw(Vector2(from.x, from.y), target, Vector2(from.vx, from.vy), weapon)
		Sfx.play(SHOT_SOUNDS.get(weapon.shot, "sling"), Vector2(from.x, from.y))
		_take_ammo(weapon.ammo)
		if on_foot:
			peasant.fire()
		else:
			cart.fire()
		throw_cooldown = weapon.cooldown
	# Dotted aim line out to the throwing range, only while the mouse is over
	# the game (otherwise there's nothing to aim at)
	_aim_state = {"from": Vector2(from.x, from.y), "to": target, "range": weapon.range, "loaded": loaded} if in_hand and pointer_inside else {}
	aim_line.queue_redraw()


var _aim_state := {}


func _draw_aim(ci: CanvasItem) -> void:
	if _aim_state.is_empty():
		return
	var from: Vector2 = _aim_state.from
	var d: Vector2 = _aim_state.to - from
	var length := d.length()
	if length == 0.0:
		length = 1.0
	var u := d / length
	var reach := minf(_aim_state.range, length)
	var dot := Color("#fff4d6", 0.55 if _aim_state.loaded else 0.15)
	var k := 30.0
	while k < reach:
		Draw.circle(ci, from + u * k, 1.8, dot)
		k += 18
	ci.draw_arc(from + u * reach, 7, 0, TAU, 20, Color("#fff4d6", 0.7), 1.5)


# Attacking with the melee weapon in hand. Each weapon fights its own way (its
# `style`): a single swing; a fast double cut; a long, narrow jab that can run
# through two foes; or a wound-up heavy blow. A click lines up one or more
# strikes, each landing when the animation does.
func _update_melee(dt: float, from: Dictionary) -> void:
	melee_cooldown -= dt
	var weapon := melee()
	var holder: Variant = peasant if on_foot else cart
	if active == "melee" and Controls.held("attack") and not pointer_over_ui and not blocking and melee_cooldown <= 0:
		melee_cooldown = weapon.cooldown
		var at := pointer_world()
		var blow := {"facing": atan2(at.y - from.y, at.x - from.x), "reach": weapon.reach, "arc": weapon.arc, "damage": weapon.damage}
		var line_up := func(extra: Dictionary) -> void:
			var s := blow.duplicate()
			s.merge(extra, true)
			strikes.append(s)
		match weapon.style:
			"double":
				line_up.call({"at": 0.0, "fx": "slash", "anim": func() -> void: holder.play("slash")})
				line_up.call({"at": weapon.gap, "fx": "slash", "back": true, "anim": func() -> void: holder.play("slash", true)})
			"jab":
				holder.play("jab")
				line_up.call({"at": 0.07, "fx": "jab", "pierce": weapon.pierce})
			"heavy":
				holder.play("heavy", false, weapon.windup)
				line_up.call({"at": weapon.windup, "fx": "heavy", "force": weapon.force})
			_:
				line_up.call({"at": 0.0, "fx": "swing", "anim": func() -> void: holder.play("swing")})

	for s in strikes:
		s.at -= dt
		if s.at <= 0:
			if s.has("anim"):
				s.anim.call()
			_strike(player(), s)
	strikes = strikes.filter(func(s: Dictionary) -> bool: return s.at > 0)

	swings = swings.filter(func(s: Dictionary) -> bool:
		s.t += dt
		s.g.modulate.a = maxf(0.0, 1 - s.t / s.life)
		s.g.scale = Vector2.ONE * (0.85 + s.t / s.life * 0.22)
		if s.t < s.life:
			return true
		s.g.queue_free()
		return false)


# Land one blow: hit whatever is in its reach and arc (a jab: in a narrow line,
# the nearest `pierce` of them), and show it.
func _strike(from: Dictionary, s: Dictionary) -> void:
	var reach: float = s.reach + (Peasant.RADIUS if on_foot else CART_REACH)
	var ax := cos(s.facing)
	var ay := sin(s.facing)
	var targets := []
	for e: Enemy in enemies.list:
		if not e.alive() or e.in_hiding:
			continue
		var dx: float = e.position.x - from.x
		var dy: float = e.position.y - from.y
		var dist := Vector2(dx, dy).length()
		if dist > reach + e.radius:
			continue
		if s.fx == "jab":
			# A line, not a wedge: ahead of you and close to the shaft
			var along := dx * ax + dy * ay
			var across := absf(dx * -ay + dy * ax)
			if along < 0 or across > e.radius + 6:
				continue
		else:
			var off := wrapf(atan2(dy, dx) - s.facing, -PI, PI)
			if absf(off) > s.arc + 0.1:
				continue
		targets.append({"e": e, "dist": dist, "dx": dx, "dy": dy})
	targets.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.dist < b.dist)
	var hit: Array = targets.slice(0, s.pierce) if s.has("pierce") else targets
	var here := Vector2(from.x, from.y)
	Sfx.play("swing_heavy" if s.fx == "heavy" else "swing", here)
	for t in hit:
		var d: float = t.dist if t.dist else 1.0
		# A shield facing you takes it (an axe's heavy blow twice over)
		if t.e.blocks(Vector2(-t.dx, -t.dy)):
			t.e.hit_shield(s.damage * (2 if s.fx == "heavy" else 1), t.dx / d, t.dy / d)
			Sfx.play("block", t.e.position)
			continue
		Sfx.play("hit_heavy" if s.fx == "heavy" else "hit", t.e.position)
		t.e.hit(t.dx / d, t.dy / d, s.damage, s.get("force", 1.0))
		# A killing cut sprays blood along the swing of the blade
		if not t.e.alive() and (s.fx == "slash" or s.fx == "heavy"):
			var sweep := Vector2(-ay, ax) * (-1.0 if s.get("back", false) else 1.0)
			blood.spray(t.e.position, Vector2(t.dx, t.dy), sweep)
		if not t.e.alive():
			_on_kill(t.e)
	if s.fx == "heavy" and not hit.is_empty():
		shake = maxf(shake, 0.15)

	# The visible stroke of the blow
	var g := Sketch.new()
	var paint := Color("#fff4d6")
	if s.fx == "jab":
		g.round_stroke(PackedVector2Array([Vector2(reach * 0.35, 0), Vector2(reach, 0)]), 3, Color(paint, 0.85))
		g.poly(PackedVector2Array([Vector2(reach + 6, 0), Vector2(reach - 3, -4), Vector2(reach - 3, 4)]), Color(paint, 0.9))
	elif s.fx == "heavy":
		g.round_stroke(_arc_points(reach, -s.arc, s.arc), 9, Color(paint, 0.85))
		g.round_stroke(_arc_points(reach * 0.72, -s.arc * 0.85, s.arc * 0.85), 3, Color(paint, 0.45))
		for k in 5:
			var a: float = s.arc * (k / 2.0 - 1)
			g.circle(Vector2(cos(a), sin(a)) * reach * 1.08, 2.5, Color("#c9ad80", 0.7))
	else:
		# A cut: brighter at the end it finishes on
		var a1: float = -s.arc if s.get("back", false) else s.arc
		g.round_stroke(_arc_points(reach, -s.arc, s.arc), 3.0 if s.fx == "slash" else 5.0, Color(paint, 0.75))
		g.circle(Vector2(cos(a1), sin(a1)) * reach, 3, Color(paint, 0.9))
	g.position = Vector2(from.x, from.y)
	g.rotation = s.facing
	air.add_child(g)
	swings.append({"g": g, "t": 0.0, "life": 0.28 if s.fx == "heavy" else (0.14 if s.fx == "jab" else 0.16)})


static func _arc_points(r: float, from: float, to: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for n in 17:
		var a := lerpf(from, to, n / 16.0)
		pts.append(Vector2(cos(a), sin(a)) * r)
	return pts


# A coin or heart pops up, spinning upward as it fades.
func _drop(kind: String, x: float, y: float) -> void:
	var g := Sketch.new()
	if kind == "coin":
		g.circle(Vector2.ZERO, 7, Color("#e8b923"))
		g.ellipse_stroke(Vector2.ZERO, 7, 7, 1.5, Color("#9c7412"))
		g.circle(Vector2(-2, -2), 2.2, Color("#fff4b0", 0.8))
	elif kind == "plank":
		g.poly(Sketch.round_rect_points(-11, -7, 22, 5, 1), Color("#a8875c"))
		g.poly(Sketch.round_rect_points(-11, 1, 22, 5, 1), Color("#8b6236"))
		for c in [Vector2(-7, -4.5), Vector2(7, -4.5), Vector2(-7, 3.5), Vector2(7, 3.5)]:
			g.circle(c, 1, Color("#d0d0d0"))
	else:
		g.circle(Vector2(-4, -2), 5, Color("#e0463a"))
		g.circle(Vector2(4, -2), 5, Color("#e0463a"))
		g.poly(PackedVector2Array([Vector2(-8.5, 0), Vector2(8.5, 0), Vector2(0, 9)]), Color("#e0463a"))
		g.circle(Vector2(-5, -4), 1.6, Color(1, 1, 1, 0.7))
	g.position = Vector2(x, y)
	air.add_child(g)
	pickups.append({"g": g, "kind": kind, "t": 0.0})


func scatter(kind: String, count: int, x: float, y: float) -> void:
	if kind == "coin" and count > 0:
		Sfx.play("coin", Vector2(x, y))
	for k in count:
		var a := float(k) / count * TAU
		var spread := 14.0 if count > 1 else 0.0
		_drop(kind, x + cos(a) * spread, y + sin(a) * spread)


func _update_pickups(dt: float) -> void:
	pickups = pickups.filter(func(p: Dictionary) -> bool:
		p.t += dt
		p.g.position.y -= dt * 45
		if p.kind == "coin":
			p.g.scale.x = cos(p.t * 10)
		else:
			p.g.scale = Vector2.ONE * (1 + sin(p.t * 12) * 0.12)
		p.g.modulate.a = maxf(0.0, 1 - maxf(0.0, p.t - 0.5) / 0.5)
		if p.t < 1:
			return true
		p.g.queue_free()
		return false)


# Flash whatever was hit, blink it while it can't be hurt, and flash the
# peasant steel-blue when armour turns a blow aside. (Blows themselves land in
# Enemies.update, only when a weapon connects.)
func _update_attacks(dt: float) -> void:
	invulnerable -= dt
	var hurting := invulnerable > INVULNERABLE - 0.2
	var blink := 0.6 if invulnerable > 0 and floori(invulnerable * 12) % 2 else 1.0
	var victims: Array = [peasant] if on_foot else [cart.horse, cart.cart]
	for v: Node2D in [peasant, cart.horse, cart.cart]:
		var hit := v in victims
		v.modulate = Color("#ff6655") if hit and hurting else Color.WHITE
		v.modulate.a = blink if hit else 1.0
	block_flash -= dt
	if block_flash > 0:
		peasant.modulate = Color("#9cc8ff", peasant.modulate.a)


# A blow or an arrow lands: on foot it's you, on the cart it's the cart.
func hurt(dmg: int, faction: String, arrow: bool, from := Vector2.INF) -> void:
	if invulnerable > 0 or state == "over":
		return
	if on_foot and dash_guard > 0:
		return # dashed clear of it
	# A raised shield turns aside what comes from where you're facing, for a
	# little breath (on the cart too: the driver shields the cart)
	if blocking and from != Vector2.INF and _shield_covers(from):
		breath = maxf(0.0, breath - shield().cost)
		breath_rest = 0.0
		if breath <= 0:
			out_of_breath = true
		block_flash = 0.25
		Sfx.play("block")
		return
	# Armour only protects the peasant, not the cart.
	if on_foot and randf() < Items.block_chance(equipment):
		block_flash = 0.25
		Sfx.play("block", Vector2.INF, -4.0)
		return
	invulnerable = INVULNERABLE
	Sfx.play("hurt" if on_foot else "thunk", Vector2.INF, 0.0 if on_foot else 4.0)
	shake = 0.3
	var goblins := faction == "goblin"
	if on_foot:
		health = maxi(0, health - dmg)
		var struck := peasant.position - from if from != Vector2.INF else Vector2.from_angle(randf() * TAU)
		blood.hit(peasant.position, struck, health <= 0)
		if health > 0:
			return
		if arrow:
			end("Shot down", "a goblin arrow found its mark" if goblins else "a bandit archer shot you down")
		elif goblins:
			end("Overrun by goblins", "the goblins caught you on foot")
		else:
			end("Robbed by bandits", "the bandits cut you down by the road")
	else:
		cart_health = maxi(0, cart_health - dmg)
		if cart_health <= 0:
			if goblins:
				end("Cart torn apart", "the goblins hacked your cart to kindling")
			else:
				end("Cart smashed", "the bandits smashed your cart and took the horse")


# Is `from` within the raised shield's arc (round where you're aiming)?
func _shield_covers(from: Vector2) -> bool:
	var me := Vector2(player().x, player().y)
	var aim := pointer_world() - me
	var toward := from - me
	if aim == Vector2.ZERO or toward == Vector2.ZERO:
		return true
	return absf(aim.angle_to(toward)) < deg_to_rad(shield().arc)


# The run is over. (Signing the scoreboard comes with the game-over screen.)
func end(title: String, text: String) -> void:
	if state == "over":
		return
	state = "over"
	cart.speed = 0.0
	over_reason = {"title": title, "text": text}
	# Held until you sign your name to it (see save_run)
	unsaved = {"distance": floori(best / PX_PER_METRE), "kills": kills, "gold": gold,
		"region": "%s (stage %d)" % [stage.name, stage.number], "fate": title}
	scoreboard = {"naming": true}
	_aim_state = {}
	aim_line.queue_redraw()
	interaction = null
	marker.queue_redraw()


# Put the finished run on the scoreboard under `name` and show where it placed.
func save_run(name: String) -> void:
	if unsaved == null:
		return
	var run: Dictionary = unsaved
	unsaved = null
	name = name.strip_edges()
	if name != "":
		last_name = name
		Scoreboard.remember_name(name)
	run.name = name
	var placed := Scoreboard.add(run)
	scoreboard = {"rank": placed.rank, "score": placed.entry.score, "top": placed.top}


# --- On foot ----------------------------------------------------------------

# What pressing E would do right now, if anything: { label, x, y, act }.
# (On the cart it's listed in the controls bar, so it has no label or spot.)
func _interaction() -> Variant:
	if state == "over":
		return null
	if not on_foot:
		return {"label": "", "act": dismount}
	var p := peasant.position
	var best_loot: Variant = null
	var best_dist := LOOT_REACH
	for l in encounters.loot():
		var d := Vector2(l.x, l.y).distance_to(p)
		if d < best_dist:
			best_loot = l
			best_dist = d
	if best_loot and best_loot.kind == "arrows":
		return {"label": "E – Take arrows from the barrel", "x": best_loot.x, "y": best_loot.y, "act": func() -> void: raid_barrel(best_loot)}
	if best_loot:
		return {"label": "E – Open the treasure chest", "x": best_loot.x, "y": best_loot.y, "act": func() -> void: search(best_loot)}
	for h in encounters.hirelings():
		if Vector2(h.x, h.y).distance_to(p) < TRADE_REACH:
			var offer: String = "Take on %s the %s" % [h.who, h.kind] if h.price == 0 else "Hire %s the %s for %d gold" % [h.who, h.kind, h.price]
			return {"label": "E – " + offer, "x": h.x, "y": h.y, "act": func() -> void: hire(h)}
	for t in encounters.traders():
		if Vector2(t.x, t.y).distance_to(p) < TRADE_REACH:
			if DayNight.is_night(clock):
				return {"label": "The %s is shut for the night – come back at dawn" % t.name.to_lower(), "x": t.x, "y": t.y,
					"act": func() -> void: say("Closed until dawn. You could sleep at an inn")}
			var open: bool = trading == t
			var label: String = "E – Stop trading" if open else "E – Trade with the %s" % t.name.to_lower()
			return {"label": label, "x": t.x, "y": t.y, "act": func() -> void: trading = null if open else t}
	var rock: Variant = scenery.gatherable_near(p.x, p.y, LOOT_REACH)
	if rock:
		return {"label": "E – Gather stones", "x": rock.x, "y": rock.y, "act": func() -> void: gather(rock)}
	if town and DayNight.is_night(clock) and p.distance_to(town.inn) < 44:
		return {"label": "E – Sleep at the inn until dawn", "x": town.inn.x, "y": town.inn.y, "act": rest_until_dawn}
	if Vector2(cart.cart_x, cart.cart_y).distance_to(p) < MOUNT_REACH:
		return {"label": "E – Climb back on the cart", "x": cart.cart_x, "y": cart.cart_y, "act": mount}
	return null


# Take on a hireling: they leave their spot and ride in the back of the cart.
func hire(h: Dictionary) -> void:
	if companions.size() >= HorseCart.SEATS.size():
		say("There's no room left on the cart")
		return
	if gold < h.price:
		say("%s wants %d gold – you have %d" % [h.who, h.price, gold])
		return
	gold -= h.price
	h.hired = true
	h.figure.visible = false
	var c := Companion.new(h.kind, h.who)
	c.seat = companions.size()
	cart.add_rider(c)
	companions.append(c)
	say("%s climbs onto the cart, bow in hand" % h.who)


func dismount() -> void:
	# Step down on whichever side of the cart is clear.
	var obstacles := solids.near(Vector2(cart.cart_x, cart.cart_y), 80)
	var sides: Array[Vector2] = []
	for side in [1.0, -1.0]:
		var a: float = cart.cart_heading + side * PI / 2
		sides.append(Vector2(cart.cart_x + cos(a) * 36, cart.cart_y + sin(a) * 36))
	var spot := sides[0]
	for s in sides:
		var clear := true
		for o: Vector3 in obstacles:
			if Vector2(o.x, o.y).distance_to(s) <= o.z + Peasant.RADIUS:
				clear = false
				break
		if clear:
			spot = s
			break
	peasant.place(spot.x, spot.y)
	cart.driver.visible = false
	on_foot = true


func mount() -> void:
	peasant.hide_peasant()
	cart.driver.visible = true
	on_foot = false


# Breath: sprinting drains it, a dash spends a chunk; it comes back after a
# short rest. Returns whether the peasant is sprinting now.
func _update_breath(dt: float, keys: Dictionary) -> bool:
	dash_cooldown -= dt
	dash_guard -= dt
	var moving: bool = keys.up or keys.down or keys.left or keys.right
	var spent := false
	if on_foot and not blocking and Controls.pressed("dash") and dash_cooldown <= 0 and not peasant.dashing():
		if breath >= DASH_COST:
			# Along the keys held, or towards the mouse if standing still
			var toward := pointer_world() - peasant.position
			var dx: float = (int(keys.right) - int(keys.left)) if moving else toward.x
			var dy: float = (int(keys.down) - int(keys.up)) if moving else toward.y
			peasant.dash(dx, dy)
			breath -= DASH_COST
			dash_cooldown = DASH_COOLDOWN
			dash_guard = Peasant.DASH_TIME + 0.05
			spent = true
			for k in 4:
				_puff(peasant.position)
		else:
			say("Too out of breath to dash")
	var sprint: bool = on_foot and not blocking and Controls.held("boost") and moving and not out_of_breath and breath > 0
	if sprint:
		breath = maxf(0.0, breath - SPRINT_DRAIN * dt)
		spent = true
	if spent:
		breath_rest = 0.0
		if breath <= 0:
			out_of_breath = true
	else:
		if not blocking: # (no getting your breath back behind a raised shield)
			breath_rest += dt
		if breath_rest > BREATH_REGEN_DELAY:
			breath = minf(1.0, breath + BREATH_REGEN * dt)
		if out_of_breath and breath >= 0.33:
			out_of_breath = false
	return sprint


# Dust kicked up from the feet.
func _puff(at: Vector2) -> void:
	var g := Sketch.new().circle(Vector2.ZERO, 2.5 + randf() * 2, Color("#c9ad80", 0.6))
	g.position = at + Vector2((randf() - 0.5) * 10, (randf() - 0.5) * 6)
	fx.add_child(g)
	puffs.append({"g": g, "t": 0.0})


func _update_puffs(dt: float) -> void:
	puffs = puffs.filter(func(p: Dictionary) -> bool:
		p.t += dt
		p.g.scale = Vector2.ONE * (1 + p.t * 3)
		p.g.modulate.a = maxf(0.0, 1 - p.t / 0.45)
		if p.t < 0.45:
			return true
		p.g.queue_free()
		return false)


# You can't stray more than LEASH from the cart: held at the edge, losing only
# the outward part of the step so you can slide along it.
func _keep_near_cart() -> void:
	var c := Vector2(cart.cart_x, cart.cart_y)
	var d := peasant.position - c
	var dist := d.length()
	if dist <= LEASH:
		return
	var u := d / dist
	peasant.position = c + u * LEASH
	var out := peasant.vx * u.x + peasant.vy * u.y
	if out > 0:
		peasant.vx -= u.x * out
		peasant.vy -= u.y * out


# How far the peasant has strayed from the cart (px), or 0 on the cart.
func cart_distance() -> float:
	return peasant.position.distance_to(Vector2(cart.cart_x, cart.cart_y)) if on_foot else 0.0


# Pulsing ring round whatever E would act on.
func _draw_marker(ci: CanvasItem) -> void:
	if not interaction or not interaction.has("x"):
		return
	var r := 16 + sin(time * 6) * 2.5
	ci.draw_arc(Vector2(interaction.x, interaction.y), r, 0, TAU, 32, Color("#fff4d6", 0.8), 2)


# Shift gallops while the horse has wind; empty the bar and it's winded until
# it has recovered a little. Returns whether it's galloping now.
func _update_stamina(dt: float, keys: Dictionary) -> bool:
	var gallop: bool = Controls.held("boost") and not on_foot and not winded and keys.up and cart.speed > 20
	if gallop:
		stamina = maxf(0.0, stamina - STAMINA_DRAIN * dt)
		stamina_rest = 0.0
		if stamina == 0.0:
			winded = true
	else:
		stamina_rest += dt
		if stamina_rest > STAMINA_REGEN_DELAY:
			stamina = minf(1.0, stamina + STAMINA_REGEN * dt)
		if winded and stamina >= WINDED_UNTIL:
			winded = false
	return gallop


# Crossing into a new region: announce it and fade the land to its colour.
func _update_stage(dt: float) -> void:
	var now := Threat.stage_at(metres)
	if now.index != stage.index:
		stage = now
		banner = {"title": now.name, "sub": "Stage %d · %s" % [now.number, now.biome.tagline], "t": STAGE_BANNER_TIME}
	if banner:
		banner.t -= dt
	var target: Color = now.biome.ground
	if ground_colour != target:
		ground_colour = _mix_colour(ground_colour, target, 1.0 - exp(-dt * 1.5))
		backdrop.modulate = ground_colour


# Blend two colours a byte at a time; snaps to `b` once close enough.
static func _mix_colour(a: Color, b: Color, t: float) -> Color:
	var r := roundi(lerpf(a.r8, b.r8, t))
	var g := roundi(lerpf(a.g8, b.g8, t))
	var bl := roundi(lerpf(a.b8, b.b8, t))
	if absi(b.r8 - r) <= 1 and absi(b.g8 - g) <= 1 and absi(b.b8 - bl) <= 1:
		return b
	return Color8(r, g, bl)


# Where the peasant is right now, and how they're moving: { x, y, vx, vy }.
func player() -> Dictionary:
	if on_foot:
		return {"x": peasant.position.x, "y": peasant.position.y, "vx": peasant.vx, "vy": peasant.vy}
	return {"x": cart.cart_x, "y": cart.cart_y, "vx": cos(cart.heading) * cart.speed, "vy": sin(cart.heading) * cart.speed}


# Where the mouse is, in world coordinates.
func pointer_world() -> Vector2:
	return get_viewport().canvas_transform.affine_inverse() * pointer


func speed_kmh() -> int:
	return 0 if on_foot else roundi(maxf(0.0, cart.speed) * KMH_PER_PX)


# --- Camera ---------------------------------------------------------------

# Debug: keys 1-4 zoom in to inspect detail. Also `-- --zoom=N`, and
# `--metres=N` to start that far along the road.
var debug_zoom := 1.0


func _read_debug_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--zoom="):
			debug_zoom = float(arg.trim_prefix("--zoom="))
		elif arg.begins_with("--clock="):
			start_clock = float(arg.trim_prefix("--clock="))
		elif arg.begins_with("--metres="):
			Road.start_along = float(arg.trim_prefix("--metres=")) * PX_PER_METRE
		elif arg.begins_with("--visit="):
			var which := arg.trim_prefix("--visit=")
			debug_visit = -2 if which == "town" else int(which)
		elif arg.begins_with("--goto="):
			debug_goto = arg.trim_prefix("--goto=")
		elif arg == "--autodrive":
			debug_autodrive = true
		elif arg == "--autoaim":
			debug_autoaim = true
		elif arg == "--spawn":
			_debug_spawn_pending = true


# Debug (`--autoaim`): the mouse follows the nearest living raider, for
# testing fights without a hand on the mouse.
var debug_autoaim := false
var debug_autodrive := false # `--autodrive`: steer the cart along the road
var debug_visit := -1 # `--visit=N`: the camera looks at the Nth encounter instead
var debug_goto := "" # `--goto=trader|chest`: park by the first one, get down and press E


func _debug_goto() -> void:
	var spot: Variant = null
	if debug_goto == "trader" and not encounters.traders().is_empty():
		spot = encounters.traders()[0]
	elif debug_goto == "chest" and not encounters.loot().is_empty():
		spot = encounters.loot()[0]
	if spot == null:
		return
	print("debug: went to the ", debug_goto)
	debug_goto = ""
	var at := Vector2(spot.x, spot.y)
	# Park the cart a little way off (with nobody on it, it stays put)
	cart.x = at.x + 80
	cart.y = at.y + 60
	cart.cart_x = at.x + 80
	cart.cart_y = at.y + 120
	cam = at
	dismount()
	peasant.place(at.x + 20, at.y + 10)
	var act: Variant = _interaction()
	if act:
		act.act.call()
var _debug_spawn_pending := false # `--spawn`: F4 once, half a second in


func _debug_aim() -> void:
	var me := player()
	var best_e: Enemy = null
	for e: Enemy in enemies.list:
		if e.alive() and not e.in_hiding and (not best_e or e.position.distance_to(Vector2(me.x, me.y)) < best_e.position.distance_to(Vector2(me.x, me.y))):
			best_e = e
	if best_e:
		pointer = get_viewport().canvas_transform * best_e.position


# Debug keys, passed on by Main (the world viewport gets no input events).
func debug_key(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_M:
		Sfx.muted = not Sfx.muted
		say("Sound off" if Sfx.muted else "Sound on")
	elif event.keycode >= KEY_1 and event.keycode <= KEY_4:
		debug_zoom = event.keycode - KEY_0
	elif event.keycode == KEY_F2:
		_debug_cycle("ranged", ["Shepherd’s Sling", "Hunting Bow", "Crossbow"])
	elif event.keycode == KEY_F3:
		_debug_cycle("melee", ["Cudgel", "Short Sword", "Boar Spear", "Bearded Axe"])
	elif event.keycode == KEY_F4:
		debug_spawn()
	elif event.keycode == KEY_F5:
		debug_wave(300)
	elif event.keycode == KEY_F11:
		war_bands.debug_horn_band(Vector2(player().x, player().y), metres)
		say("Debug: a war band with a hornblower")
	elif event.keycode == KEY_F9:
		debug_next_town()
	elif event.keycode == KEY_F10:
		dev_mode = not dev_mode
		say("Dev mode on: ammunition is never used up" if dev_mode else "Dev mode off")
	elif event.keycode == KEY_F7:
		hire({"kind": "archer", "who": Companion.NAMES[randi() % Companion.NAMES.size()], "price": 0, "figure": Node2D.new(), "hired": false})
	elif event.keycode == KEY_F8:
		_debug_dress()
	elif event.keycode == KEY_F6:
		_debug_cycle("offhand", ["Wooden Buckler", "Iron-rimmed Shield", "Kite Shield", "Leather Quiver", "Hunter’s Quiver", "Great Quiver"])


# Debug, until chests and traders exist: F2 / F3 cycle the ranged / melee
# weapon (bare-handed, then each in turn), with ammo for it in the cart.
func _debug_cycle(slot: String, names: Array) -> void:
	var now: Variant = equipment[slot]
	var i: int = names.find(now.name) if now else -1
	equipment[slot] = Items.named(names[i + 1]) if i + 1 < names.size() else null
	if slot == "offhand":
		say("%s in your off hand" % (equipment.offhand.name if equipment.offhand else "Nothing"))
		return
	active = slot
	var item := ranged() if slot == "ranged" else melee()
	if slot == "ranged" and ammo_count(item.ammo) < 10:
		stash(cart_store, item.ammo, 30)
		stash(bag, item.ammo, 30)
	say("%s in hand" % item.name)


# Debug: F5 sends a huge wave at you from all sides, to feel the scale: the
# region's raiders, with archers and heavies among them.
# F9: skip ahead to just outside the next town's gate, cart, companions, gear
# and all (on foot, you're put back on the cart). The road between is passed
# over: nothing is placed on it.
func debug_next_town() -> void:
	if state == "over":
		return
	var town_px := Towns.next_along(Road.along(road_index) + Towns.CLEAR)
	var town_i := roundi((town_px - Road.start_along) / Road.SEGMENT)
	var i := town_i - ceili((Towns.RADIUS + 160) / Road.SEGMENT)
	if i <= road_index:
		return
	road.ensure_ahead(town_i + 40)
	encounters.skip_to(i)
	scenery.placed_up_to = maxi(scenery.placed_up_to, i - 60)
	if on_foot:
		mount()
	var p: Vector2 = road.points[i]
	cart.place_at(p.x, p.y, road.direction(i).angle())
	road_index = i
	best = maxf(best, Road.along(i))
	metres = floori(best / PX_PER_METRE)
	cam = p
	trading = null
	encounters.place()
	scenery.update(i)
	road.cull(i)
	say("You press on to %s" % Towns.town_name(town_px))


# F8: put on the next tier of every piece of armour (then none again).
func _debug_dress() -> void:
	var tier: int = equipment.body.tier + 1 if equipment.body else 1
	for slot in ["helmet", "shoulders", "body", "legs"]:
		equipment[slot] = null
		if tier <= 3:
			for item in Items.ITEMS:
				if item.slot == slot and item.tier == tier:
					equipment[slot] = item.duplicate()
	say("Tier %d armour" % tier if tier <= 3 else "No armour")


func debug_wave(count: int) -> void:
	var me := player()
	var biome: Dictionary = Threat.stage_at(metres).biome
	var goblins: bool = biome.name == "The Darkwood" or (biome.name != "The Barrens" and randf() < 0.5)
	var types := ["goblin", "goblin", "goblin", "goblinArcher", "orc"] if goblins else ["bandit", "bandit", "bandit", "archer", "brute"]
	enemies.threat = Threat.threat_at(metres)
	for k in count:
		var a := randf() * TAU
		var at := Vector2(me.x, me.y) + Vector2(cos(a), sin(a)) * randf_range(500, 900)
		var home := {"x": at.x, "y": at.y}
		var e := enemies.add(types[k % types.size()], at.x, at.y, home)
		e.leash = 4000.0
		e.engage()
	say("Debug: a wave of %d %s" % [count, "goblins" if goblins else "bandits"])


# Debug: F4 sends a mixed band of raiders at you from up ahead.
func debug_spawn() -> void:
	var me := player()
	var ahead := Vector2(cos(cart.heading), sin(cart.heading)) if not on_foot else Vector2.from_angle(peasant.facing)
	var centre := Vector2(me.x, me.y) + ahead * 320
	var faction := "goblin" if randf() < 0.5 else "bandit"
	var types := ["goblin", "goblin", "goblinArcher", "orc"] if faction == "goblin" else ["bandit", "archer", "captain", "brute"]
	enemies.threat = Threat.threat_at(metres)
	for k in types.size():
		var a := float(k) / types.size() * TAU
		var spot := centre + Vector2(cos(a), sin(a)) * 40
		var home := {"x": centre.x, "y": centre.y, "facing": (-ahead).angle(), "wander": {"x": centre.x, "y": centre.y, "min": 10.0, "max": 50.0}}
		enemies.add(types[k], spot.x, spot.y, home).engage()
	say("Debug: a band of %ss" % faction)


# The scroll wheel zooms in and out (eased towards `zoom_target`).
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.0
var zoom_target := 1.0
var view_zoom := 1.0


func zoom_by(factor: float) -> void:
	zoom_target = clampf(zoom_target * factor, ZOOM_MIN, ZOOM_MAX)


func update_camera(dt: float) -> void:
	view_zoom = lerpf(view_zoom, zoom_target, 1.0 - exp(-dt * 12))
	if absf(view_zoom - zoom_target) < 0.002:
		view_zoom = zoom_target
	var zoom := art_zoom * debug_zoom * view_zoom
	var half := Vector2(get_viewport().size) / 2.0
	# Half the view, and the edge margin, in world units
	var view_half := half / zoom
	var margin := CAMERA_MARGIN / css_per_art / zoom

	# Follow the peasant on foot; on the cart, look ahead along the road.
	var target: Vector2
	var keep: Array[Vector2]
	if on_foot:
		target = peasant.position
		keep = [peasant.position]
	else:
		var lead := maxf(0.0, cart.speed) * 0.7
		target = Vector2(cart.x + cos(cart.heading) * lead, cart.y + sin(cart.heading) * lead)
		keep = [Vector2(cart.x, cart.y), Vector2(cart.cart_x, cart.cart_y)]

	var visiting := debug_visit
	if debug_visit == -2: # the first town
		visiting = encounters.list.find_custom(func(e: Dictionary) -> bool: return e.has("town"))
	if visiting >= 0 and visiting < encounters.list.size():
		var t: Vector3 = encounters.list[visiting].trigger
		target = Vector2(t.x, t.y)
		keep = [target]
		cam = target
	# Pan toward the mouse: at the edge of the screen the view shifts as far as
	# it can while still keeping the player in shot.
	if pointer_active:
		target.x += clampf((pointer.x - half.x) / half.x, -1, 1) * (view_half.x - margin)
		target.y += clampf((pointer.y - half.y) / half.y, -1, 1) * (view_half.y - margin)

	cam += (target - cam) * (1.0 - exp(-dt * 4))

	var reach := Vector2(maxf(0.0, view_half.x - margin), maxf(0.0, view_half.y - margin))
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in keep:
		lo = lo.min(p)
		hi = hi.max(p)
	cam = Vector2(clampf(cam.x, hi.x - reach.x, lo.x + reach.x), clampf(cam.y, hi.y - reach.y, lo.y + reach.y))

	shake = maxf(0.0, shake - dt)
	var jolt := shake * 20.0 / css_per_art
	# Snap to whole art pixels so the picture doesn't shimmer as it scrolls.
	var origin := (half - cam * zoom + Vector2(randf() - 0.5, randf() - 0.5) * jolt).round()
	get_viewport().canvas_transform = Transform2D(0.0, Vector2(zoom, zoom), 0.0, origin)
	Sfx.listener = cam
	# What's in view (with room for a raider's height and a weapon's reach)
	Rig.view = Rect2(-origin / zoom, half * 2 / zoom).grow(120)

	# Cover the view with grass, anchored to world coordinates.
	var top_left := (-origin / zoom - Vector2(8, 8)).floor()
	backdrop.position = top_left
	backdrop.region_rect = Rect2(top_left, half * 2 / zoom + Vector2(16, 16))
