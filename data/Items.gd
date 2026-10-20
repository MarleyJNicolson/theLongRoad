class_name Items
extends RefCounted

# Equipment the peasant can find in treasure chests (port of items.js).

const SLOTS := ["helmet", "shoulders", "body", "legs", "ranged", "melee", "offhand"]

const SLOT_NAMES := {
	"helmet": "Helmet",
	"shoulders": "Shoulders",
	"body": "Upper body",
	"legs": "Legs",
	"ranged": "Ranged weapon",
	"melee": "Melee weapon",
	"offhand": "Off-hand",
}

# Each kind of ranged weapon uses its own ammunition, carried as stacks in the
# bag or the cart (see CONSUMABLES). It doesn't come back on its own: gather
# stones from rocks, buy or loot arrows and bolts.
const AMMO := {
	"stones": {"name": "Stones"},
	"arrows": {"name": "Arrows"},
	"bolts": {"name": "Bolts"},
}

const BLOCK_PER_ARMOUR := 0.05 # chance to block a blow, per point
const MAX_BLOCK := 0.6

# What you fight with when the slot is empty.
const BARE := {
	"ranged": {"name": "Thrown stones", "icon": "stone", "tier": 0, "damage": 1, "range": 460.0, "cooldown": 0.3, "speed": 560.0, "shot": "stone", "ammo": "stones"},
	"melee": {"name": "Fists", "icon": "fist", "tier": 0, "damage": 1, "reach": 20.0, "cooldown": 0.5, "style": "swing", "arc": 1.1},
}

const ITEMS := [
	{"slot": "helmet", "icon": "helmet", "name": "Leather Cap", "tier": 1, "armour": 1},
	{"slot": "helmet", "icon": "helmet", "name": "Iron Pot Helm", "tier": 2, "armour": 2},
	{"slot": "helmet", "icon": "helmet", "name": "Steel Bascinet", "tier": 3, "armour": 3},
	{"slot": "shoulders", "icon": "shoulders", "name": "Padded Mantle", "tier": 1, "armour": 1},
	{"slot": "shoulders", "icon": "shoulders", "name": "Leather Pauldrons", "tier": 2, "armour": 2},
	{"slot": "shoulders", "icon": "shoulders", "name": "Steel Spaulders", "tier": 3, "armour": 3},
	{"slot": "body", "icon": "body", "name": "Padded Gambeson", "tier": 1, "armour": 1},
	{"slot": "body", "icon": "body", "name": "Mail Shirt", "tier": 2, "armour": 2},
	{"slot": "body", "icon": "body", "name": "Steel Breastplate", "tier": 3, "armour": 3},
	{"slot": "legs", "icon": "legs", "name": "Leather Breeches", "tier": 1, "armour": 1},
	{"slot": "legs", "icon": "legs", "name": "Mail Chausses", "tier": 2, "armour": 2},
	{"slot": "legs", "icon": "legs", "name": "Steel Greaves", "tier": 3, "armour": 3},

	{"slot": "ranged", "icon": "sling", "name": "Shepherd’s Sling", "tier": 1, "damage": 1, "range": 600.0, "cooldown": 0.22, "speed": 660.0, "shot": "stone", "ammo": "stones"},
	{"slot": "ranged", "icon": "bow", "name": "Hunting Bow", "tier": 2, "damage": 2, "range": 650.0, "cooldown": 0.36, "speed": 820.0, "shot": "arrow", "ammo": "arrows"},
	{"slot": "ranged", "icon": "crossbow", "name": "Crossbow", "tier": 3, "damage": 3, "range": 720.0, "cooldown": 0.8, "speed": 980.0, "shot": "bolt", "ammo": "bolts"},

	# Melee `style`s (see Game._update_melee): swing – one sweep; double – two
	# quick cuts, `damage` each; jab – a narrow thrust that can run through
	# `pierce` foes; heavy – a wound-up wide blow that knocks foes flying.
	# `arc` is how far either side of the aim line it reaches (radians).
	{"slot": "melee", "icon": "club", "name": "Cudgel", "tier": 1, "damage": 1, "reach": 30.0, "cooldown": 0.4, "style": "swing", "arc": 1.1},
	{"slot": "melee", "icon": "sword", "name": "Short Sword", "tier": 2, "damage": 1, "reach": 32.0, "cooldown": 0.45, "style": "double", "arc": 1.0, "gap": 0.13},
	{"slot": "melee", "icon": "spear", "name": "Boar Spear", "tier": 2, "damage": 2, "reach": 70.0, "cooldown": 0.5, "style": "jab", "arc": 0.22, "pierce": 2},
	{"slot": "melee", "icon": "axe", "name": "Bearded Axe", "tier": 3, "damage": 3, "reach": 36.0, "cooldown": 0.9, "style": "heavy", "arc": 1.5, "windup": 0.2, "force": 2.2},

	# The off hand (not in the JS original): a shield, held up with the right
	# mouse button, blocks arrows and blows within `arc` degrees either side of
	# where you aim, each block costing `cost` of your breath; or a quiver,
	# `slots` more stacks of ammunition, drawn on first.
	{"slot": "offhand", "icon": "shield", "kind": "shield", "name": "Wooden Buckler", "tier": 1, "arc": 50.0, "cost": 0.12},
	{"slot": "offhand", "icon": "shield", "kind": "shield", "name": "Iron-rimmed Shield", "tier": 2, "arc": 65.0, "cost": 0.09},
	{"slot": "offhand", "icon": "shield", "kind": "shield", "name": "Kite Shield", "tier": 3, "arc": 80.0, "cost": 0.07},
	{"slot": "offhand", "icon": "quiver", "kind": "quiver", "name": "Leather Quiver", "tier": 1, "slots": 2},
	{"slot": "offhand", "icon": "quiver", "kind": "quiver", "name": "Hunter’s Quiver", "tier": 2, "slots": 3},
	{"slot": "offhand", "icon": "quiver", "kind": "quiver", "name": "Great Quiver", "tier": 3, "slots": 4},
]

# Things that stack in the bag and get used up.
const CONSUMABLES := {
	"poultice": {"name": "Healing Poultice", "icon": "poultice", "tier": 1, "desc": "Click to restore 1 heart", "stack": 5, "value": 1},
	"planks": {"name": "Planks & Nails", "icon": "planks", "tier": 1, "desc": "Click to mend 2 cart damage", "stack": 5, "value": 1},
	# Ammunition: `value` is per 10, and the whole stack sells at once.
	"stones": {"name": "Stones", "icon": "stones", "tier": 0, "desc": "For throwing by hand or with a sling", "stack": 30, "value": 1, "ammo": true},
	"arrows": {"name": "Arrows", "icon": "arrows", "tier": 1, "desc": "For a bow", "stack": 30, "value": 3, "ammo": true},
	"bolts": {"name": "Bolts", "icon": "bolts", "tier": 2, "desc": "For a crossbow", "stack": 30, "value": 4, "ammo": true},
}

const BAG_SIZE := 6
const CART_SIZE := 12 # the cart holds more, but only while you're at it


# Gold a merchant would give for an item you don't need.
static func sell_value(item: Dictionary) -> int:
	return item.tier * 3


# The item with this name (a copy).
static func named(item_name: String) -> Dictionary:
	for item in ITEMS:
		if item.name == item_name:
			return item.duplicate()
	return {}


# Better gear turns up further along the road.
static func roll_item(metres: float) -> Dictionary:
	var luck := randf() + metres / 2500.0
	var tier := 3 if luck > 1.15 else (2 if luck > 0.75 else 1)
	var weapon := randf() < 0.4
	var pool := ITEMS.filter(func(it: Dictionary) -> bool: return it.tier == tier and (it.has("armour") != weapon))
	return pool[randi() % pool.size()].duplicate()


static func total_armour(equipment: Dictionary) -> int:
	var sum := 0
	for slot in SLOTS:
		if equipment.get(slot):
			sum += equipment[slot].get("armour", 0)
	return sum


static func block_chance(equipment: Dictionary) -> float:
	return minf(MAX_BLOCK, total_armour(equipment) * BLOCK_PER_ARMOUR)


# Colours and names for each quality of gear (0 = bare hands / empty).
const TIER_COLOURS := [
	{"fill": Color("#7d725c"), "edge": Color(243 / 255.0, 227 / 255.0, 192 / 255.0, 0.25), "name": ""},
	{"fill": Color("#a87a48"), "edge": Color("#a87a48"), "name": "Common"},
	{"fill": Color("#a6b0bb"), "edge": Color("#7fa0c8"), "name": "Sturdy"},
	{"fill": Color("#e3e9ef"), "edge": Color("#d4a32a"), "name": "Fine"},
]

# How each melee weapon fights.
const STYLES := {
	"swing": "A single sweeping blow",
	"double": "A fast double slash",
	"jab": "A long jab – can skewer two",
	"heavy": "One heavy, wide blow – knocks foes flying",
}


# Stat lines for an item's tooltip (port of describe.js).
static func describe(item: Dictionary) -> Array:
	if item.has("desc"):
		return [item.desc]
	if item.get("kind") == "shield":
		return ["Hold right mouse to raise", "Blocks arrows and blows within %d° of your aim" % roundi(item.arc),
			"Each block costs %d%% of your breath" % roundi(item.cost * 100), "You move slower behind it"]
	if item.get("kind") == "quiver":
		return ["Holds %d more stacks of ammunition" % item.slots, "Arrows, bolts and stones: used first"]
	if item.has("armour"):
		return ["+%d armour" % item.armour]
	if item.has("range"):
		return ["Damage %d" % item.damage, "Range %d m" % roundi(item.range / 20.0),
			"%.1f shots / s" % (1.0 / item.cooldown), "Uses %s" % item.ammo]
	var reach := "long" if item.reach >= 45 else ("medium" if item.reach >= 30 else "short")
	var damage := "Damage %d × 2" % item.damage if item.style == "double" else "Damage %d" % item.damage
	return [STYLES.get(item.style, STYLES.swing), damage, "Reach %s" % reach, "%.1f attacks / s" % (1.0 / item.cooldown)]
