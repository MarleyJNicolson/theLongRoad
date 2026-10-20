class_name TradePanel
extends PanelContainer

# A trader's stall (port of TradePanel.vue): what's for sale, the price, and
# why you can't buy it if you can't. Sits at the right, halfway down. Sizes
# are CSS pixels scaled by `dpr`.

const TEXT := Color("#f3e3c0")
const GOLD := Color("#ffd75e")
const BUY := Color("#d4a32a")
# Services have no item of their own; they're shown with a fitting one.
const SERVICE_ICON := {"repair": "planks", "heal": "poultice"}

var game: Game
var dpr := 1.0
var _shown := "" # what's on display, to rebuild only when it changes
var _rows: VBoxContainer
var _title: Label
var _purse: Label


func _init(game_: Game) -> void:
	game = game_
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#1c1714f0")
	panel.border_color = Color(BUY, 0.6)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(12 * dpr)
	add_theme_stylebox_override("panel", panel)
	custom_minimum_size.x = 340 * dpr

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(6 * dpr))
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(12 * dpr))
	column.add_child(head)
	_title = _label("", 13, TEXT)
	head.add_child(_title)
	_purse = _label("", 14, GOLD)
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_purse)
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.tooltip_text = "Close (Esc)"
	close.add_theme_font_override("font", Fonts.ui())
	close.add_theme_font_size_override("font_size", roundi(18 * dpr))
	close.add_theme_color_override("font_color", Color(TEXT, 0.7))
	close.pressed.connect(func() -> void: game.trading = null)
	head.add_child(close)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", roundi(6 * dpr))
	column.add_child(_rows)


func _label(text: String, size: float, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	var settings := LabelSettings.new()
	settings.font = Fonts.ui()
	settings.font_size = roundi(size * dpr)
	settings.font_color = colour
	label.label_settings = settings
	return label


# Show the stall (`view` from Game.trade_view), or hide when it's null.
func refresh(view: Variant, gold: int, dpr_: float) -> void:
	visible = view != null
	if not view:
		_shown = ""
		return
	var key := "%s|%d|%s|%s" % [dpr_, gold, view.name, view.offers]
	if key == _shown:
		return
	if dpr_ != dpr or not _rows:
		dpr = dpr_
		_build()
	_shown = key
	_title.text = view.name.to_upper()
	_purse.text = "● %d gold" % gold
	for child in _rows.get_children():
		child.queue_free()
	for offer in view.offers:
		_rows.add_child(_row(offer))
	# Right-hand side, halfway down
	reset_size()
	var screen := get_viewport_rect().size
	position = Vector2(screen.x - size.x - 16 * dpr, (screen.y - size.y) / 2)


func _row(offer: Dictionary) -> Control:
	var row := PanelContainer.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.25)
	back.set_content_margin_all(6 * dpr)
	row.add_theme_stylebox_override("panel", back)
	if offer.sold:
		row.modulate.a = 0.45
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", roundi(10 * dpr))
	row.add_child(line)

	# The item's picture, edged in its quality colour if it's gear
	var item: Dictionary = offer.item if offer.item else {"icon": SERVICE_ICON.get(offer.type, ""), "tier": 1}
	var edge: Color = Items.TIER_COLOURS[clampi(item.get("tier", 1), 0, 3)].edge if offer.kind == "gear" else Color(TEXT, 0.2)
	var icon := Painter.new(func(ci: CanvasItem) -> void:
		ci.draw_rect(Rect2(Vector2.ZERO, Vector2(40, 40) * dpr).grow(-dpr), edge, false, 2 * dpr)
		ItemIcon.draw(ci, Rect2(Vector2(5, 5) * dpr, Vector2(30, 30) * dpr), item))
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(40, 40) * dpr
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(icon)
	line.add_child(holder)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(_label(offer.name, 14, TEXT))
	var detail := _label(_detail(offer), 11, Color(TEXT, 0.7))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 180 * dpr
	text.add_child(detail)
	if offer.why and not offer.sold:
		text.add_child(_label(offer.why, 9, Color(TEXT, 0.6)))
	line.add_child(text)

	var buy := Button.new()
	buy.text = "Sold" if offer.sold else "● %d" % offer.price
	buy.disabled = offer.why != ""
	buy.tooltip_text = offer.why
	buy.custom_minimum_size = Vector2(58, 0) * dpr
	buy.add_theme_font_override("font", Fonts.ui())
	buy.add_theme_font_size_override("font_size", roundi(14 * dpr))
	buy.add_theme_color_override("font_color", Color("#ffe9a8"))
	buy.add_theme_color_override("font_hover_color", Color("#ffe9a8"))
	buy.add_theme_color_override("font_disabled_color", Color(TEXT, 0.5))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.set_border_width_all(1)
		box.set_content_margin_all(6 * dpr)
		if state == "disabled":
			box.border_color = Color(TEXT, 0.25)
			box.bg_color = Color(0, 0, 0, 0)
		else:
			box.border_color = BUY
			box.bg_color = Color(BUY, 0.4 if state == "hover" or state == "pressed" else 0.2)
		buy.add_theme_stylebox_override(state, box)
	var i: int = offer.i
	buy.pressed.connect(func() -> void: game.buy(i))
	line.add_child(buy)
	return row


static func _detail(offer: Dictionary) -> String:
	if offer.kind == "service":
		return "Price depends on the damage"
	var lines := Items.describe(offer.item)
	if offer.kind == "gear":
		lines.push_front(Items.TIER_COLOURS[offer.item.tier].name)
	return " · ".join(lines)
