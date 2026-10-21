class_name Perks
extends RefCounted

# What gems buy from the captain at the gate north of each region (not in
# the JS original). They last the run. `max`: how many times one can be had.

const LIST := [
	{"id": "volley", "name": "Volley", "desc": "Loose three shots at once, for one shot's ammunition", "cost": 8},
	{"id": "tough", "name": "Tough as old boots", "desc": "One more heart", "cost": 5, "max": 2},
	{"id": "lungs", "name": "Deep lungs", "desc": "Sprinting, dashing and blocking take a third less breath", "cost": 4},
	{"id": "nimble", "name": "Nimble", "desc": "Dash a third further, and again sooner", "cost": 4},
	{"id": "quick", "name": "Quick hands", "desc": "Draw and reload a fifth faster", "cost": 5},
	{"id": "horse", "name": "Sturdy horse", "desc": "The horse gallops half again as long", "cost": 3},
	{"id": "wheels", "name": "Iron-shod wheels", "desc": "The cart takes four more blows", "cost": 4},
]


static func named(id: String) -> Dictionary:
	for p in LIST:
		if p.id == id:
			return p
	return {}
