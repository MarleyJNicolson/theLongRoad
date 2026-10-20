class_name EquipmentPanel
extends PanelContainer

# What the peasant is wearing and carrying (port of EquipmentPanel.vue): a
# paper doll of armour slots, the two weapon slots (the one in hand lit up),
# and buttons for the bag and the cart. Bottom left.

const SLOT := 52.0
const ROWS := [
	["", "helmet", "bag"],
	["shoulders", "body", "cart"],
	["", "legs", ""],
	["ranged", "swap", "melee"],
]

var game: Game
var dpr: float
var tip: UiKit.Tip
var _totals: Label


func _init(game_: Game, dpr_: float) -> void:
	game = game_
	dpr = dpr_
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiKit.panel_style(Color(0, 0, 0, 0), dpr, Vector4(10, 12, 12, 12)))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(8 * dpr))
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(12 * dpr))
	column.add_child(head)
	head.add_child(UiKit.label("EQUIPMENT", 11, Color(UiKit.TEXT, 0.85), dpr))
	_totals = UiKit.label("", 11, Color(UiKit.TEXT, 0.7), dpr)
	_totals.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_totals)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", roundi(6 * dpr))
	grid.add_theme_constant_override("v_separation", roundi(6 * dpr))
	column.add_child(grid)
	for row in ROWS:
		for cell in row:
			grid.add_child(_cell(cell))
	tip = UiKit.Tip.new(dpr, 190)
	add_child(tip)


func _cell(cell: String) -> Control:
	match cell:
		"":
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(SLOT, SLOT) * dpr
			gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
			return gap
		"swap":
			var hint := UiKit.label("⇄\nQ", 11, Color(UiKit.TEXT, 0.6), dpr)
			hint.custom_minimum_size = Vector2(SLOT, SLOT) * dpr
			hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			return hint
		"bag":
			var bag := ItemSlot.new(SLOT, dpr, func() -> Dictionary:
				return _button_look("bag", "Bag (B)", game.bag_open, true))
			bag.tooltip_text = "Bag (B)"
			bag.clicked.connect(func(_shift: bool) -> void: game.toggle_bag())
			return bag
		"cart":
			var cart := ItemSlot.new(SLOT, dpr, func() -> Dictionary:
				return _button_look("cart", "Cart (C)", game.cart_open, game.near_cart()))
			cart.clicked.connect(func(_shift: bool) -> void: game.toggle_cart())
			cart.hovered.connect(func(on: bool) -> void:
				cart.tooltip_text = "Cart storage (C)" if game.near_cart() else "Cart storage – get closer to the cart")
			return cart
	var slot := ItemSlot.new(SLOT, dpr, func() -> Dictionary: return _slot_look(cell))
	slot.clicked.connect(func(_shift: bool) -> void: game.unequip(cell))
	slot.hovered.connect(func(on: bool) -> void: _hover(cell if on else ""))
	return slot


# The bag and cart buttons: dashed until open; the cart's dim when out of reach.
func _button_look(icon: String, text: String, open: bool, reachable: bool) -> Dictionary:
	return {
		"item": {"icon": icon, "tier": 0},
		"label": text,
		"dashed": not open,
		"edge": UiKit.GILT if open else Color(UiKit.TEXT, 0.35),
		"background": Color(UiKit.GILT, 0.15) if open else Color(0, 0, 0, 0.35),
		"faded": 1.0 if reachable else 0.4,
		"always_hover": true,
	}


# An equipment slot: what's worn (or the bare-handed stand-in for a weapon),
# edged in its quality colour, the weapon in hand lit up.
func _slot_look(slot: String) -> Dictionary:
	var worn: Variant = game.equipment[slot]
	var shown: Variant = worn if worn else Items.BARE.get(slot)
	var weapon := slot == "ranged" or slot == "melee"
	var in_hand: bool = slot == game.active
	var faded := 1.0
	if not worn:
		faded = 0.35
	elif weapon and not in_hand:
		faded = 0.45
	return {
		"item": shown,
		"silhouette": slot,
		"label": Items.SLOT_NAMES[slot].split(" ")[0],
		"edge": Items.TIER_COLOURS[shown.tier if shown else 0].edge,
		"background": Color(60 / 255.0, 40 / 255.0, 20 / 255.0, 0.55) if weapon else Color(0, 0, 0, 0.35),
		"faded": faded,
		"badge": "IN HAND" if in_hand else "",
		"glow": in_hand,
		"always_hover": true,
	}


func _hover(slot: String) -> void:
	if not slot:
		tip.hide_tip()
		return
	var worn: Variant = game.equipment[slot]
	var shown: Variant = worn if worn else Items.BARE.get(slot)
	var label: String = Items.SLOT_NAMES[slot]
	var at := global_position + Vector2(size.x + 8 * dpr, size.y)
	if not shown:
		tip.show_tip(label, "", ["Empty – find armour in treasure chests"], Color(UiKit.TEXT, 0.25), at, true)
		return
	var tier: Dictionary = Items.TIER_COLOURS[shown.tier]
	var sub := label if not worn else "%s · %s" % [tier.name, label]
	var lines := Items.describe(shown)
	if worn:
		lines.append("Click to take off")
	tip.show_tip(shown.name, sub, lines, tier.edge, at, true)


func refresh() -> void:
	var armour := Items.total_armour(game.equipment)
	_totals.text = "Armour %d · Block %d%%" % [armour, roundi(Items.block_chance(game.equipment) * 100)]
	reset_size()
	position = Vector2(16 * dpr, get_viewport_rect().size.y - 16 * dpr - size.y)
