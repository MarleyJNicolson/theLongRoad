class_name Carts
extends RefCounted

# What you can drive (not in the JS original). The wainwright in a town will
# sell you a bigger one: more room for supply crates and for hands to ride
# along, and sturdier. The war wagon is only built in the towns off the road
# north. `size` scales how it's drawn (and how much of the road it takes).

const LIST := [
	{"name": "Farm cart", "crates": 3, "seats": 1, "health": 10, "size": 1.0, "price": 0},
	{"name": "Trader’s wagon", "crates": 5, "seats": 2, "health": 13, "size": 1.18, "price": 60},
	{"name": "War wagon", "crates": 8, "seats": 3, "health": 16, "size": 1.36, "price": 150, "rare": true},
]


static func describe(cart: Dictionary) -> String:
	return "%d crates · %d %s · takes %d blows" % [cart.crates, cart.seats, "seat" if cart.seats == 1 else "seats", cart.health]
