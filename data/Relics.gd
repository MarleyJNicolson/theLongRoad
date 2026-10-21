class_name Relics
extends RefCounted

# Relics of the old people who raised the stone circles (not in the JS
# original). Now and then one is left on a circle's altar, glowing; take it
# and it rides in the cart (a crate's room; it doesn't break), and any town's
# quartermaster pays gems for it, more the further north it was found.

const CHANCE := 0.4 # of a stone circle holding one
const NAMES := ["Sun-disc of the Old Kings", "Bronze torc", "Rune-carved horn", "Crown of antlers",
	"Moonstone idol", "Gilded skull", "Serpent armlet", "Bone flute", "Amber eye", "Star-iron blade",
	"Antler comb", "Silver bough"]
const GOLD := Color("#c9a227")
const SHINE := Color("#f6c25a")
const GEM := Color("#7aa8ec")


# A relic found `metres` north: { name, value (gems) }.
static func roll(metres: float) -> Dictionary:
	return {"name": NAMES[randi() % NAMES.size()], "value": randi_range(3, 6) + floori(metres / 1500.0)}


# The relic floating over the altar: a gold disc set with a blue stone in a
# faint halo, and a light that shows at night. Bobs and pulses.
static func view() -> Node2D:
	var holder := Node2D.new()
	var g := Sketch.new()
	g.ellipse(Vector2(0, 0), 7, 3, Color(GEM, 0.25)) # its glow on the altar
	var float_at := Vector2(0, -16)
	g.circle(float_at, 9, Color(GEM, 0.18))
	g.circle(float_at, 5, GOLD)
	g.circle(float_at - Vector2(1, 1), 3.4, SHINE)
	g.circle(float_at, 1.8, GEM)
	holder.add_child(g)
	var light := Glow.light(110, Color("#8fb8ff"), 1.1)
	light.position = float_at
	holder.add_child(light)
	return holder


# Set it bobbing and pulsing (once it's in the tree).
static func animate(relic_view: Node2D) -> void:
	var g: Node2D = relic_view.get_child(0)
	var bob := g.create_tween().set_loops()
	bob.tween_property(g, "position:y", -3.0, 1.1).set_trans(Tween.TRANS_SINE)
	bob.tween_property(g, "position:y", 0.0, 1.1).set_trans(Tween.TRANS_SINE)
	var pulse := relic_view.create_tween().set_loops()
	pulse.tween_property(relic_view, "modulate:a", 0.75, 0.9).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(relic_view, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
