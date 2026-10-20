class_name InventoryPanel
extends PanelContainer

# One panel for both the bag and the cart's storage (port of
# InventoryPanel.vue). Click to use or equip (in the cart: to take into the
# bag), shift-click to stow in the cart, right-click to sell, and drag between
# (or within) them.

const SLOT := 52.0

var game: Game
var container_name: String # "bag" or "cart"
var dpr: float
var tip: UiKit.Tip
var _purse: Label
var _hint: Label


func _init(game_: Game, container_name_: String, dpr_: float) -> void:
	game = game_
	container_name = container_name_
	dpr = dpr_
	var is_cart := container_name == "cart"
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	add_theme_stylebox_override("panel", UiKit.panel_style(
		Color(168 / 255.0, 135 / 255.0, 92 / 255.0, 0.7) if is_cart else Color(UiKit.GILT, 0.5), dpr, Vector4(10, 12, 10, 12)))

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(6 * dpr))
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(12 * dpr))
	column.add_child(head)
	head.add_child(UiKit.label("CART STORAGE" if is_cart else "BAG", 11, UiKit.TEXT, dpr))
	_purse = UiKit.label("", 14, UiKit.GOLD, dpr)
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_purse)
	head.add_child(UiKit.close_button(dpr, "Close (C)" if is_cart else "Close (B)", func() -> void:
		if is_cart:
			game.toggle_cart()
		else:
			game.toggle_bag()))

	var grid := GridContainer.new()
	grid.columns = 4 if is_cart else 3
	grid.add_theme_constant_override("h_separation", roundi(6 * dpr))
	grid.add_theme_constant_override("v_separation", roundi(6 * dpr))
	column.add_child(grid)
	var count := Items.CART_SIZE if is_cart else Items.BAG_SIZE
	for i in count:
		grid.add_child(_slot(i))

	# Wraps to the grid's width, as the CSS did
	_hint = UiKit.label("", 10, Color(UiKit.TEXT, 0.6), dpr)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.x = grid.columns * (SLOT + 6) * dpr - 6 * dpr
	column.add_child(_hint)
	tip = UiKit.Tip.new(dpr, 200)
	add_child(tip)


func _slot(i: int) -> ItemSlot:
	var look := func() -> Dictionary:
		var entry: Variant = game.container(container_name)[i]
		if not entry:
			return {"item": null}
		var item := Game.entry_item(entry)
		return {"item": item, "count": entry.get("count", 0), "edge": Items.TIER_COLOURS[item.tier].edge}
	var slot := ItemSlot.new(SLOT, dpr, look)
	slot.clicked.connect(func(shift: bool) -> void: _click(i, shift))
	slot.right_clicked.connect(func() -> void:
		if game.container(container_name)[i]:
			game.sell_bag_item(i, container_name))
	slot.hovered.connect(func(on: bool) -> void: _hover(i if on else -1))
	slot.drag_data = func() -> Variant:
		return {"from": container_name, "i": i} if game.container(container_name)[i] else null
	slot.on_drop = func(data: Dictionary) -> void: game.move_item(data.from, data.i, container_name, i)
	return slot


func _click(i: int, shift: bool) -> void:
	if not game.container(container_name)[i]:
		return
	if container_name == "cart":
		game.move_item("cart", i, "bag")
	elif shift and game.cart_open:
		game.move_item("bag", i, "cart")
	else:
		game.use_bag_item(i)


func _hover(i: int) -> void:
	var entry: Variant = game.container(container_name)[i] if i >= 0 else null
	if not entry:
		tip.hide_tip()
		return
	var item := Game.entry_item(entry)
	var gear: bool = entry.type == "gear"
	var tier: Dictionary = Items.TIER_COLOURS[item.tier]
	var lines := Items.describe(item)
	if gear:
		var worn: Variant = game.equipment[item.slot]
		lines.append("Wearing: %s" % worn.name if worn else "%s slot is empty" % Items.SLOT_NAMES[item.slot])
	if container_name == "cart":
		lines.append("Click to take it into your bag")
	else:
		if gear:
			lines.append("Click to equip")
		if game.cart_open:
			lines.append("Shift-click to stow it in the cart")
	lines.append("Right-click to sell (%d gold)" % game.value_of(entry))
	tip.show_tip(item.name, tier.name if gear else "Supplies", lines, tier.edge, global_position + Vector2(size.x + 8 * dpr, 0))


# Keep it up to date: shown while open (and not after the run ends).
func refresh() -> void:
	var open := game.cart_open if container_name == "cart" else game.bag_open
	visible = open and game.state != "over"
	if not visible:
		tip.hide_tip()
		return
	_purse.text = "" if container_name == "cart" else "● %d gold" % game.gold
	if container_name == "cart":
		_hint.text = "Click to take · Drag to move · Right-click to sell"
	elif game.cart_open:
		_hint.text = "Click to use · Shift-click or drag to the cart"
	else:
		_hint.text = "Click to use or equip · Right-click to sell"
	# Above the equipment, the cart's beside the bag
	reset_size()
	var screen := get_viewport_rect().size
	position = Vector2((228 if container_name == "cart" else 16) * dpr, screen.y - 300 * dpr - size.y)
