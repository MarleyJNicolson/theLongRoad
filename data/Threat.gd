class_name Threat
extends RefCounted

# How dangerous the road is at a given distance, and which region it runs
# through (port of threat.js). Everything here keeps rising for as long as the
# road goes on.

const STAGE_LENGTH := 2500 # metres per region

# Regions repeat in this order; each time round they come back harder.
# `weights` scale how often each encounter kind turns up there.
const BIOMES := [
	{
		"name": "The Meadows",
		"tagline": "Farmland and open road",
		"ground": Color("#5f9a45"),
		"road": {"edge": Color("#6f5130"), "fill": Color("#b9925e"), "rut": Color("#9c7646"), "crown": Color("#c4a06c")},
		"trees": [Color("#2f6b2a"), Color("#386f2e"), Color("#2b5e30")],
		"leaf": Color("#4c8a3a"),
		"bush": [Color("#467a32"), Color("#4f8a38"), Color("#3f7030")],
		"grass": Color("#4e8a36"),
		"weights": {},
	},
	{
		"name": "The Darkwood",
		"tagline": "Goblin country",
		"ground": Color("#3f6e34"),
		"road": {"edge": Color("#4a3620"), "fill": Color("#8a6c45"), "rut": Color("#6e5435"), "crown": Color("#977852")},
		"trees": [Color("#1f4a22"), Color("#24502a"), Color("#1b3f1f")],
		"leaf": Color("#2f6530"),
		"bush": [Color("#2f5a28"), Color("#356530"), Color("#294f24")],
		"grass": Color("#356a2c"),
		"weights": {"goblinCamp": 1.8, "goblinBurrows": 1.8, "goblinLooters": 1.5, "goblinHouseRaid": 1.2, "goblinLure": 1.6, "banditLure": 0.5, "banditCamp": 0.5, "banditRoadblock": 0.5, "banditAmbush": 0.6, "banditHouseRaid": 0.4},
	},
	{
		"name": "The Barrens",
		"tagline": "Bandit country",
		"ground": Color("#a89a5a"),
		"road": {"edge": Color("#7a5c38"), "fill": Color("#d0b07a"), "rut": Color("#b59460"), "crown": Color("#dcc08e")},
		"trees": [Color("#6b7a3a"), Color("#5e6e34"), Color("#75803e")],
		"leaf": Color("#8a9448"),
		"bush": [Color("#8a8a48"), Color("#7d7d40"), Color("#96904e")],
		"grass": Color("#8c8442"),
		"weights": {"banditCamp": 1.8, "banditRoadblock": 1.6, "banditAmbush": 1.5, "banditHouseRaid": 1.3, "banditLure": 1.6, "goblinLure": 0.5, "goblinCamp": 0.5, "goblinBurrows": 0.5, "goblinLooters": 0.6, "goblinHouseRaid": 0.4},
	},
	{
		"name": "The Frostmarch",
		"tagline": "Cold hills where everything is hungry",
		"ground": Color("#c9d3cf"),
		# slush, with mud in the ruts
		"road": {"edge": Color("#7c848f"), "fill": Color("#a7aeb6"), "rut": Color("#6e553c"), "crown": Color("#d9dee2")},
		"trees": [Color("#2e4a3e"), Color("#35543f"), Color("#2a4438")],
		"leaf": Color("#e8eef0"),
		"bush": [Color("#7d8c84"), Color("#8a998f"), Color("#71807a")],
		"grass": Color("#9aa8a0"),
		"weights": {"goblinCamp": 1.3, "banditCamp": 1.3, "banditRoadblock": 1.2, "goblinBurrows": 1.1},
	},
]

const NUMERALS := ["", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX", " X"]


# { index, number, biome, name }
static func stage_at(metres: float) -> Dictionary:
	var index := floori(maxf(0.0, metres) / STAGE_LENGTH)
	var biome: Dictionary = BIOMES[index % BIOMES.size()]
	var lap := index / BIOMES.size()
	var numeral: String = NUMERALS[lap] if lap < NUMERALS.size() else " %d" % (lap + 1)
	return {"index": index, "number": index + 1, "biome": biome, "name": biome.name + numeral}


# Scaling applied to raiders and encounters at a given distance.
static func threat_at(metres: float) -> Dictionary:
	var km := maxf(0.0, metres) / 1000.0
	return {
		"level": km,
		# Extra hit points for every 2.5 km travelled
		"hp_bonus": floori(km / 2.5),
		# A little quicker each km, but never faster than a galloping horse
		# (fastest goblin: 165 × 1.1 × 1.25 ≈ 227 px/s vs a 245 px/s gallop)
		"speed_mult": 1.0 + minf(0.25, km * 0.03),
		# Blows land harder deeper in
		"damage": 1 + floori(km / 6.0),
		# Share of ordinary raiders who carry bows instead
		"archer_chance": minf(0.3, 0.12 + km * 0.02),
		# Bigger, tougher raiders worth more gold
		"elite_chance": minf(0.45, maxf(0.0, km - 1.0) * 0.05),
		# Room for bigger groups than the base caps allow
		"extra_members": floori(km / 3.0),
		# Road points between encounters: closer together, but never on top of each other
		"spacing": maxf(22.0, 60.0 - km * 5.0),
	}
