class_name Hud
extends Control

# The HUD over the pixelated world (port of PixiStage.vue's markup), drawn in
# screen pixels: stats along the top, vitals top right, banners and toasts,
# what E would do, the controls bar, the cart arrow and "straying too far"
# warning, the equipment / bag / cart / trade panels, and the game-over
# screen with the scoreboard. Sizes from the CSS are in CSS pixels; `dpr`
# scales them to the screen.

const INK := Color("#1c1714")
const TEXT := Color("#f3e3c0")
const HEART := Color("#e0463a")
const CART_FILL := [Color("#b98a52"), Color("#8b6236")]
const STAMINA_FILL := [Color("#f0d36a"), Color("#c9a227")]
const BOOST_FILL := [Color("#ffe98a"), Color("#e8b923")]
const WINDED_FILL := Color("#8a7a5a")
const EMPTY := Color("#cf5528")
const FOOT_CONTROLS := "WASD walk · Shift sprint · Ctrl/Space dash · E interact · Click attack · Right mouse shield · R swap · B bag · C cart"
const CART_CONTROLS := "W/S speed · A/D steer · Shift gallop · E get off · Click attack · Right mouse shield · R swap · B bag · C cart"
const DEV_KEYS := "F2 / F3 weapons · F4 raiders · F5 huge wave\nF6 off hand · F7 archer · F8 armour\nF9 next town · F10 dev mode off\nF1 filter · 1-4 zoom (or scroll)"


# A control that draws itself with `paint` (bars, hearts, coins).
class Drawn:
	extends Control

	var paint: Callable

	func _init(min_size: Vector2, paint_: Callable) -> void:
		custom_minimum_size = min_size
		paint = paint_
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		paint.call(self)


var game: Game
var device_px := 2 # screen pixels per art pixel (set by Main)
var dpr := 1.0 # screen pixels per CSS pixel (set by Main)
var trade: TradePanel
var equipment: EquipmentPanel
var bag: InventoryPanel
var cart_store: InventoryPanel
var quiver: InventoryPanel
var _built_at := 0.0 # the dpr everything was built for
var _built: Array = [] # what _build made (freed on a rebuild)

# Top stats
var _stage_small: Label
var _stage: Label
var _distance: Label
var _speed: Label
var _kills: Label
var _gold: Label
var _day_small: Label
var _day: Label
var _dev: Label
# Vitals
var _vitals: PanelContainer
var _rows := {} # name -> the row (dimmed unless it's what's being hurt)
var _ammo_name: Label
var _ammo_count: Label
var _ammo_from: Label
var _crew: Label
# Messages
var _banner: VBoxContainer
var _banner_title: Label
var _banner_sub: Label
var _toast: PanelContainer
var _toast_text: Label
var _prompt: PanelContainer
var _prompt_text: Label
var _controls: PanelContainer
var _controls_text: Label
# Game over
var _overlay: Control
var _over_box: VBoxContainer
var _over_key := ""
var _name_box: LineEdit


func _init(game_: Game) -> void:
	game = game_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	trade = TradePanel.new(game)
	add_child(trade)


func _process(_delta: float) -> void:
	if dpr != _built_at:
		_build()
	equipment.refresh()
	bag.refresh()
	cart_store.refresh()
	quiver.refresh()
	trade.refresh(game.trade_view(), game.gold, dpr)
	_refresh()
	queue_redraw()


# --- Building ---------------------------------------------------------------------

func _label(text: String, size_: float, colour := TEXT, weight := 400) -> Label:
	return UiKit.label(text, size_, colour, dpr, weight)


func _panel(padding: Vector4, background := UiKit.PANEL, border := Color(0, 0, 0, 0)) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiKit.panel_style(border, dpr, padding, background))
	return p


func _add(node: Control, parent: Node = self) -> Control:
	parent.add_child(node)
	if parent == self:
		_built.append(node)
	return node


# A stat box along the top: a small caption over a big value.
func _stat(caption: String, min_width: float, colour := TEXT) -> Array:
	var box := _panel(Vector4(8, 14, 8, 14))
	box.custom_minimum_size.x = min_width * dpr
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	box.add_child(column)
	var small := _label(caption.to_upper(), 11, Color(colour, 0.7))
	column.add_child(small)
	var big := _label("", 20, colour)
	column.add_child(big)
	return [box, small, big, column]


# (Re)build everything at the current scale.
func _build() -> void:
	for node in _built:
		node.queue_free()
	_built = []
	for panel in [equipment, bag, cart_store, quiver]:
		if panel:
			panel.queue_free()
	_name_box = null
	_over_key = ""

	# Stats along the top
	var stats := HBoxContainer.new()
	stats.add_theme_constant_override("separation", roundi(12 * dpr))
	stats.position = Vector2(16, 16) * dpr
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_add(stats)
	var s := _stat("Stage", 190)
	_stage_small = s[1]
	_stage = s[2]
	stats.add_child(s[0])
	s = _stat("Distance", 120)
	_distance = s[2]
	stats.add_child(s[0])
	s = _stat("Speed", 120)
	_speed = s[2]
	stats.add_child(s[0])
	s = _stat("Raiders felled", 120)
	_kills = s[2]
	stats.add_child(s[0])
	s = _stat("Gold", 120, UiKit.GOLD)
	_gold = s[2]
	var coin_row := HBoxContainer.new()
	coin_row.add_theme_constant_override("separation", roundi(6 * dpr))
	s[3].remove_child(_gold)
	s[3].add_child(coin_row)
	coin_row.add_child(Drawn.new(Vector2(14, 22) * dpr, _draw_coin))
	coin_row.add_child(_gold)
	stats.add_child(s[0])
	s = _stat("Day", 150)
	_day_small = s[1]
	_day = s[2]
	# The sun-and-moon disc beside it
	var clock_row := HBoxContainer.new()
	clock_row.add_theme_constant_override("separation", roundi(10 * dpr))
	var box: PanelContainer = s[0]
	box.remove_child(s[3])
	box.add_child(clock_row)
	var dial := Drawn.new(Vector2(40, 40) * dpr, _draw_dial)
	dial.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	clock_row.add_child(dial)
	clock_row.add_child(s[3])
	stats.add_child(box)
	_dev = _label("", 12, Color("#ffb3a8"))
	_dev.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_add(_dev)

	# Vitals, top right
	_vitals = _panel(Vector4(8, 12, 8, 12))
	_add(_vitals)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", roundi(8 * dpr))
	_vitals.add_child(rows)
	_rows.you = _row(rows, "You", Drawn.new(Vector2(5 * 20, 20) * dpr, _draw_hearts))
	_rows.cart = _row(rows, "Cart", Drawn.new(Vector2(130, 12) * dpr, _draw_cart_bar))
	_rows.breath = _row(rows, "Stamina", Drawn.new(Vector2(130, 12) * dpr, func(c: Control) -> void:
		_draw_bar(c, game.breath, WINDED_FILL if game.out_of_breath else (BOOST_FILL if game.sprinting else STAMINA_FILL))))
	_rows.horse = _row(rows, "Horse", Drawn.new(Vector2(130, 12) * dpr, func(c: Control) -> void:
		_draw_bar(c, game.stamina, WINDED_FILL if game.winded else (BOOST_FILL if game.galloping else STAMINA_FILL))))
	var ammo := HBoxContainer.new()
	ammo.add_theme_constant_override("separation", roundi(5 * dpr))
	ammo.alignment = BoxContainer.ALIGNMENT_END
	rows.add_child(ammo)
	_ammo_name = _label("", 11, Color(TEXT, 0.7))
	ammo.add_child(_ammo_name)
	ammo.add_child(Drawn.new(Vector2(12, 18) * dpr, _draw_pebble))
	_ammo_count = _label("", 18, TEXT, 500)
	_ammo_count.custom_minimum_size.x = 26 * dpr
	_ammo_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ammo.add_child(_ammo_count)
	_ammo_from = _label("", 10, Color(TEXT, 0.6))
	ammo.add_child(_ammo_from)
	_crew = _label("", 11, Color(TEXT, 0.85))
	_crew.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rows.add_child(_crew)

	# The region / nightfall banner
	_banner = VBoxContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.add_theme_constant_override("separation", roundi(4 * dpr))
	_add(_banner)
	_banner_title = _shadowed(Fonts.title(), 64, Color("#fff4d6"))
	_banner.add_child(_banner_title)
	_banner_sub = _shadowed(Fonts.ui(), 16, Color("#fff4d6", 0.85))
	_banner.add_child(_banner_sub)

	# Toast, prompt, controls
	_toast = _panel(Vector4(8, 16, 8, 16), Color(120 / 255.0, 88 / 255.0, 20 / 255.0, 0.85))
	_toast_text = _label("", 18, Color("#ffe9a8"))
	_toast.add_child(_toast_text)
	_add(_toast)
	_prompt = _panel(Vector4(8, 16, 8, 16), UiKit.PANEL, Color("#fff4d6", 0.4))
	_prompt_text = _label("", 17, Color("#fff4d6"))
	_prompt.add_child(_prompt_text)
	_add(_prompt)
	_controls = _panel(Vector4(6, 14, 6, 14))
	_controls_text = _label("", 14)
	_controls.add_child(_controls_text)
	_add(_controls)

	# The panels
	equipment = EquipmentPanel.new(game, dpr)
	bag = InventoryPanel.new(game, "bag", dpr)
	cart_store = InventoryPanel.new(game, "cart", dpr)
	quiver = InventoryPanel.new(game, "quiver", dpr)
	quiver.above = bag
	for panel in [equipment, bag, cart_store, quiver]:
		add_child(panel)
	move_child(trade, -1)

	# Game over, over everything
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.visible = false
	_add(_overlay)
	var shade := ColorRect.new()
	shade.color = Color(30 / 255.0, 20 / 255.0, 10 / 255.0, 0.6)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(shade)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(centre)
	_over_box = VBoxContainer.new()
	_over_box.add_theme_constant_override("separation", roundi(10 * dpr))
	_over_box.alignment = BoxContainer.ALIGNMENT_CENTER
	centre.add_child(_over_box)
	_built_at = dpr


# One row of the vitals: a caption, then the bar (or hearts).
func _row(rows: VBoxContainer, caption: String, widget: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", roundi(11 * dpr))
	row.alignment = BoxContainer.ALIGNMENT_END
	var c := _label(caption.to_upper(), 11, Color(TEXT, 0.7))
	c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(c)
	widget.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(widget)
	rows.add_child(row)
	return row


func _shadowed(font: Font, size_: float, colour: Color) -> Label:
	var l := Label.new()
	var settings := LabelSettings.new()
	settings.font = font
	settings.font_size = roundi(size_ * dpr)
	settings.font_color = colour
	settings.shadow_color = Color(0, 0, 0, 0.7)
	settings.shadow_offset = Vector2(0, 2) * dpr
	settings.shadow_size = roundi(6 * dpr)
	l.label_settings = settings
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# --- Each frame -------------------------------------------------------------------

static func _put(label: Label, text: String) -> void:
	if label.text != text:
		label.text = text


func _refresh() -> void:
	var g := game
	var over: bool = g.state == "over"
	var W := size.x
	var H := size.y

	_put(_stage_small, "STAGE %d · THREAT %.1f" % [g.stage.number, Threat.threat_at(g.metres).level])
	_put(_stage, g.stage.name)
	_put(_distance, "%d m" % g.metres)
	_put(_speed, "%d km/h" % (0 if g.on_foot else g.speed_kmh()))
	_put(_kills, str(g.kills))
	_put(_gold, str(g.gold))
	var change := DayNight.until_change(g.clock)
	var next := "Dawn" if DayNight.is_night(g.clock) or DayNight.phase(g.clock) == "dusk" else "Dusk"
	_put(_day_small, "DAY %d · %s" % [g.day(), DayNight.phase(g.clock).to_upper()])
	_put(_day, "%s in %d:%02d" % [next, floori(change / 60), floori(change) % 60])
	_put(_dev, ("DEV MODE · infinite ammunition\n" + DEV_KEYS) if g.dev_mode else "")

	# Vitals: whichever of you or the cart is taking the hits stands out
	for name in _rows:
		var active: bool = g.on_foot if name == "you" or name == "breath" else not g.on_foot
		_rows[name].modulate.a = 1.0 if active else 0.85
	var weapon: Dictionary = g.ranged()
	var count := g.ammo_count(weapon.ammo)
	_put(_ammo_name, String(weapon.ammo).to_upper())
	_put(_ammo_count, "∞" if g.dev_mode else str(count))
	_ammo_count.label_settings.font_color = EMPTY if count == 0 and not g.dev_mode else TEXT
	var sources := []
	if g.quiver() != null:
		sources.append("quiver")
	if not g.on_foot:
		sources.append("cart")
	sources.append("bag")
	_put(_ammo_from, "from " + " + ".join(sources))
	_put(_crew, "" if g.companions.is_empty() else "RIDING WITH YOU   " + " · ".join(g.companions.map(func(c: Companion) -> String: return c.title())))
	_crew.visible = not g.companions.is_empty()
	_vitals.reset_size()
	_vitals.position = Vector2(W - 16 * dpr - _vitals.size.x, 16 * dpr)
	_dev.visible = g.dev_mode
	if g.dev_mode:
		_dev.reset_size()
		_dev.position = Vector2(W - 16 * dpr - _dev.size.x, _vitals.position.y + _vitals.size.y + 8 * dpr)

	# The banner fades in and out over 0.8 s
	var b: Variant = g.banner
	_banner.visible = b != null and b.t > 0 and not over
	if _banner.visible:
		_put(_banner_title, b.title)
		_put(_banner_sub, String(b.sub).to_upper())
		_banner.modulate.a = clampf(minf(b.t, Game.STAGE_BANNER_TIME - b.t) / 0.8, 0, 1)
		_banner.reset_size()
		_banner.position = Vector2((W - _banner.size.x) / 2, H * 0.22)

	_toast.visible = g.toast != null
	if _toast.visible:
		_put(_toast_text, g.toast.text)
		_toast.reset_size()
		_toast.position = Vector2((W - _toast.size.x) / 2, 84 * dpr)
	var prompt: String = g.interaction.label if g.interaction and not over else ""
	_prompt.visible = prompt != ""
	if _prompt.visible:
		_put(_prompt_text, prompt)
		_prompt.reset_size()
		_prompt.position = Vector2((W - _prompt.size.x) / 2, H - 60 * dpr - _prompt.size.y)
	_put(_controls_text, FOOT_CONTROLS if g.on_foot else CART_CONTROLS)
	_controls.visible = not over
	_controls.reset_size()
	# Centred in the room right of the equipment panel
	var from := equipment.position.x + equipment.size.x + 12 * dpr
	_controls.position = Vector2(maxf(from, from + (W - from - _controls.size.x) / 2), H - 16 * dpr - _controls.size.y)

	_overlay.visible = over
	if over:
		_refresh_over()
	g.typing = over and _name_box != null and is_instance_valid(_name_box) and _name_box.has_focus()


# The game-over screen: rebuilt whenever what it shows changes.
func _refresh_over() -> void:
	var g := game
	var board: Dictionary = g.scoreboard
	var key := str(board) + str(g.over_reason)
	if key == _over_key:
		return
	_over_key = key
	for child in _over_box.get_children():
		child.queue_free()
	_name_box = null
	var centred := func(l: Label) -> Label:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_over_box.add_child(l)
		return l
	var title := _shadowed(Fonts.title(), 72, EMPTY)
	title.label_settings.shadow_color = Color(0, 0, 0, 0)
	title.text = g.over_reason.get("title", "")
	_over_box.add_child(title)
	centred.call(_label("You reached %s – stage %d" % [g.stage.name, g.stage.number], 16))
	centred.call(_label("You travelled %d m and felled %d raiders before %s." % [g.metres, g.kills, g.over_reason.get("text", "")], 16))
	centred.call(_label("%d gold was lost along with everything else." % g.gold, 16))

	var scores := _panel(Vector4(10, 18, 10, 18), Color(20 / 255.0, 14 / 255.0, 8 / 255.0, 0.6), Color("#5e4a33"))
	scores.get_theme_stylebox("panel").set_border_width_all(roundi(2 * dpr))
	scores.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_over_box.add_child(scores)
	if board.get("naming", false):
		var sign := HBoxContainer.new()
		sign.add_theme_constant_override("separation", roundi(10 * dpr))
		scores.add_child(sign)
		var caption := _label("Sign the scoreboard", 16)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		sign.add_child(caption)
		_name_box = _name_entry()
		sign.add_child(_name_box)
		var save := Button.new()
		save.text = "Save"
		save.focus_mode = Control.FOCUS_NONE
		save.add_theme_font_override("font", Fonts.ui())
		save.add_theme_font_size_override("font_size", roundi(16 * dpr))
		for state in ["normal", "hover", "pressed"]:
			var box := UiKit.panel_style(Color("#5e3f22"), dpr, Vector4(4, 14, 4, 14), Color("#d4a32a") if state != "hover" else Color("#e8b923"))
			box.set_border_width_all(roundi(2 * dpr))
			save.add_theme_stylebox_override(state, box)
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			save.add_theme_color_override(state, Color("#2a1f14"))
		save.pressed.connect(_sign)
		sign.add_child(save)
		_name_box.call_deferred("grab_focus")
	elif board.has("score"):
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", roundi(6 * dpr))
		scores.add_child(column)
		var line: String = "Score %d" % board.score + (" · #%d on the board" % board.rank if board.rank else "")
		column.add_child(_label(line, 22, UiKit.GOLD))
		var table := GridContainer.new()
		table.columns = 6
		table.add_theme_constant_override("h_separation", roundi(20 * dpr))
		table.add_theme_constant_override("v_separation", roundi(4 * dpr))
		column.add_child(table)
		var top: Array = board.top
		for k in mini(5, top.size()):
			var run: Dictionary = top[k]
			var colour := UiKit.GOLD if k + 1 == board.rank else TEXT
			var cells := ["%d." % (k + 1), run.name, str(run.score), "%d m" % run.distance, "%d felled" % run.kills, run.region]
			for c in cells.size():
				var cell := _label(cells[c], 14, colour)
				if c == 2:
					cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
				table.add_child(cell)
	var hint := "Enter to save · click away and press Space to try again" if board.get("naming", false) else "Press Space to try again"
	var h: Label = centred.call(_label(hint, 16, Color(TEXT, 0.8)))
	h.custom_minimum_size.y = 28 * dpr
	h.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM


func _name_entry() -> LineEdit:
	var box := LineEdit.new()
	box.text = game.last_name
	box.placeholder_text = "Your name"
	box.max_length = 20
	box.custom_minimum_size.x = 220 * dpr
	box.caret_blink = true
	box.add_theme_font_override("font", Fonts.ui())
	box.add_theme_font_size_override("font_size", roundi(18 * dpr))
	box.add_theme_color_override("font_color", Color("#2a1f14"))
	box.add_theme_color_override("font_placeholder_color", Color("#2a1f14", 0.45))
	box.add_theme_color_override("caret_color", Color("#2a1f14"))
	var normal := UiKit.panel_style(Color("#5e4a33"), dpr, Vector4(4, 8, 4, 8), TEXT)
	normal.set_border_width_all(roundi(2 * dpr))
	var focus := normal.duplicate()
	focus.border_color = UiKit.GOLD
	box.add_theme_stylebox_override("normal", normal)
	box.add_theme_stylebox_override("focus", focus)
	box.text_submitted.connect(func(_t: String) -> void: _sign())
	return box


func _sign() -> void:
	if _name_box and is_instance_valid(_name_box):
		var name := _name_box.text
		_name_box.release_focus()
		game.save_run(name.replace("|", ""))


# --- Drawing ------------------------------------------------------------------------

func _draw_bar(c: Control, fill: float, colours: Variant) -> void:
	var r := Rect2(Vector2.ZERO, c.size)
	c.draw_rect(r, Color(0, 0, 0, 0.45))
	var w := r.size.x * clampf(fill, 0, 1)
	if colours is Color:
		c.draw_rect(Rect2(0, 0, w, r.size.y), colours)
	else:
		# A two-tone gradient, light on top
		c.draw_rect(Rect2(0, 0, w, r.size.y / 2), colours[0])
		c.draw_rect(Rect2(0, r.size.y / 2, w, r.size.y / 2), colours[1])


func _draw_cart_bar(c: Control) -> void:
	_draw_bar(c, float(game.cart_health) / Game.MAX_CART_HEALTH, CART_FILL)
	for i in range(1, Game.MAX_CART_HEALTH):
		var x := roundf(c.size.x * i / Game.MAX_CART_HEALTH)
		c.draw_rect(Rect2(x, 0, maxf(1, dpr), c.size.y), Color(0, 0, 0, 0.4))


func _draw_hearts(c: Control) -> void:
	var s := c.size.y
	for i in Game.MAX_HEALTH:
		var colour := HEART if i < game.health else Color(HEART, 0.2)
		var o := Vector2(i * s + s * 0.5, s * 0.5)
		var r := s * 0.24
		c.draw_circle(o + Vector2(-r, -r * 0.4), r, colour)
		c.draw_circle(o + Vector2(r, -r * 0.4), r, colour)
		c.draw_colored_polygon(PackedVector2Array([o + Vector2(-r * 1.95, -r * 0.1), o + Vector2(r * 1.95, -r * 0.1), o + Vector2(0, r * 2.0)]), colour)


# The time of day as a disc that turns through the day: the sky's colour all
# round it (day, dusk, night, dawn), the sun in the middle of the day and the
# moon in the middle of the night, now at the marker on top.
func _draw_dial(c: Control) -> void:
	var r := minf(c.size.x, c.size.y) / 2 - 1 * dpr
	var o := c.size / 2
	var now := fposmod(game.clock, DayNight.CYCLE)
	# Where the wheel puts time t: now straight up, later times to the left
	# (it turns clockwise, bringing them up)
	var at := func(t: float, radius: float) -> Vector2:
		return o + Vector2.from_angle(-PI / 2 + (t - now) / DayNight.CYCLE * TAU) * radius
	c.draw_circle(o, r + 1 * dpr, Color("#5e4a33"))
	var steps := 72
	for k in steps:
		var t0 := float(k) / steps * DayNight.CYCLE
		var t1 := float(k + 1) / steps * DayNight.CYCLE
		var dark := DayNight.darkness((t0 + t1) / 2)
		var sky := Color("#7ec0e8").lerp(Color("#1d2448"), dark).lerp(Color("#f0a050"), sin(dark * PI) * 0.7)
		c.draw_colored_polygon(PackedVector2Array([o, at.call(t0, r), at.call(t1 + 0.5, r)]), sky)
	# Stars across the night
	for t in [510.0, 545.0, 600.0, 640.0, 665.0, 560.0]:
		c.draw_circle(at.call(t, r * (0.82 if int(t) % 2 else 0.4)), 0.8 * dpr, Color("#fff4d6", 0.85))
	# The sun, mid-morning to mid-afternoon
	var sun: Vector2 = at.call((DayNight.DAY - DayNight.DUSK) / 2, r * 0.58)
	for k in 8:
		var a := k * TAU / 8
		c.draw_line(sun + Vector2.from_angle(a) * r * 0.24, sun + Vector2.from_angle(a) * r * 0.36, Color("#ffd75e"), maxf(1, 1.2 * dpr))
	c.draw_circle(sun, r * 0.2, Color("#ffd75e"))
	c.draw_circle(sun - Vector2(1, 1) * r * 0.05, r * 0.12, Color("#fff1a8"))
	# The moon, a crescent, in the dead of night
	var moon: Vector2 = at.call(DayNight.DAY + (DayNight.NIGHT - DayNight.DAWN) / 2, r * 0.58)
	c.draw_circle(moon, r * 0.19, Color("#e8e0c8"))
	c.draw_circle(moon + Vector2(r * 0.09, -r * 0.05), r * 0.16, Color("#1d2448"))
	# The rim and the marker for now
	c.draw_arc(o, r, 0, TAU, 48, Color("#2a1f14"), maxf(1, 1.5 * dpr), true)
	var tip := o + Vector2(0, -r + 5 * dpr)
	c.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-4, -7) * dpr, tip + Vector2(4, -7) * dpr]), UiKit.GILT)
	c.draw_polyline(PackedVector2Array([tip, tip + Vector2(-4, -7) * dpr, tip + Vector2(4, -7) * dpr, tip]), INK, maxf(1, dpr))


func _draw_coin(c: Control) -> void:
	var r := 7 * dpr
	var o := Vector2(r, c.size.y / 2 + 1 * dpr)
	c.draw_circle(o, r, Color("#9c7412"))
	c.draw_circle(o - Vector2(1, 1) * dpr, r - 1.5 * dpr, Color("#e8b923"))


# The ammunition: a pebble, or an arrow / bolt standing upright.
func _draw_pebble(c: Control) -> void:
	var kind: String = game.ranged().ammo
	var mid := c.size / 2
	if kind == "stones":
		c.draw_circle(mid, 5 * dpr, Color("#77736a"))
		c.draw_circle(mid - Vector2(1, 1) * dpr, 4 * dpr, Color("#a9a59a"))
		return
	var bolt := kind == "bolts"
	var h := (12 if bolt else 16) * dpr
	var w := (5 if bolt else 4) * dpr
	var top := Vector2(mid.x - w / 2, mid.y - h / 2)
	var head := 0.25 if bolt else 0.22
	var tail := 0.82 if bolt else 0.8
	c.draw_rect(Rect2(top, Vector2(w, h * head)), Color("#b9c0c8"))
	c.draw_rect(Rect2(top + Vector2(0, h * head), Vector2(w, h * (tail - head))), Color("#6e4a28") if bolt else Color("#8b6236"))
	c.draw_rect(Rect2(top + Vector2(0, h * tail), Vector2(w, h * (1 - tail))), Color("#5e3f22") if bolt else Color("#e8e0c8"))


func _draw() -> void:
	# Waking at the inn: the screen fades back in
	if game.rest_fade > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, game.rest_fade))
	if game.state == "over":
		return
	var tether := _tether_view()
	if tether.is_empty():
		return
	var pulse := 1.0
	if tether.warn:
		# 0.6 s each way between full and 55% (tether-pulse)
		pulse = lerpf(1.0, 0.55, (1 - cos(PI * game.time / 0.6)) / 2)
	if tether.has("arrow"):
		_draw_arrow(tether.arrow, tether.angle, tether.metres, tether.warn, pulse)
	if tether.warn:
		var text := ("You can go no further from your cart" if tether.at_limit else "You are straying too far from your cart") + " – head back!"
		_draw_warning(text, pulse)


# On foot: a warning when straying too far, and an arrow at the screen edge
# pointing back to the cart whenever it's out of sight (port of tetherView).
# Returns {} when there's nothing to show.
func _tether_view() -> Dictionary:
	if not game.on_foot:
		return {}
	var d := game.cart_distance()
	# Point at the cart, not its wheels
	var at_art := game.get_viewport().canvas_transform * Vector2(game.cart.cart_x, game.cart.cart_y - 20)
	var s := at_art * device_px
	var W := size.x
	var H := size.y
	# Keep clear of the HUD along the top and bottom
	var left := 48 * dpr
	var right := W - 48 * dpr
	var top := 110 * dpr
	var bottom := H - 110 * dpr
	var off_screen := s.x < left or s.x > right or s.y < top or s.y > bottom
	var warn := d > Game.WARN_DISTANCE
	if not off_screen and not warn:
		return {}
	var out := {"warn": warn, "at_limit": d > Game.LEASH - 10, "metres": roundi(d / Game.PX_PER_METRE)}
	if off_screen:
		# Where the line from the middle of the screen to the cart leaves the box
		var mid := Vector2(W / 2, (top + bottom) / 2)
		var v := s - mid
		var k := INF
		if v.x > 0:
			k = minf(k, (right - mid.x) / v.x)
		elif v.x < 0:
			k = minf(k, (left - mid.x) / v.x)
		if v.y > 0:
			k = minf(k, (bottom - mid.y) / v.y)
		elif v.y < 0:
			k = minf(k, (top - mid.y) / v.y)
		out.arrow = (mid + v * k).round()
		out.angle = v.angle()
	return out


# A chunky arrowhead turned towards the cart, with "Cart · N m" under it.
func _draw_arrow(at: Vector2, angle: float, metres: int, warn: bool, pulse: float) -> void:
	var colour := Color("#e0463a") if warn else Color("#e8b923")
	colour.a = pulse
	var head := at - Vector2(0, 10 * dpr)
	var pts := PackedVector2Array()
	for p in [Vector2(-15, -16), Vector2(15, 0), Vector2(-15, 16)]:
		pts.append(head + (p * dpr).rotated(angle))
	var shadow := PackedVector2Array()
	for p in pts:
		shadow.append(p + Vector2(2, 2) * dpr)
	draw_colored_polygon(shadow, Color(INK, pulse))
	draw_colored_polygon(pts, colour)
	var font := Fonts.ui(400)
	var font_size := roundi(15 * dpr)
	var text := "Cart · %d m" % metres
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var base := Vector2(at.x - width / 2, at.y + 26 * dpr)
	draw_string_outline(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, roundi(2 * dpr), INK)
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#ffb3a8") if warn else TEXT)


# A red banner under the top of the screen.
func _draw_warning(text: String, pulse: float) -> void:
	var font := Fonts.ui(400)
	var font_size := roundi(16 * dpr)
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var pad := Vector2(16, 6) * dpr
	var box := Rect2(Vector2(size.x / 2 - text_size.x / 2 - pad.x, 96 * dpr), text_size + pad * 2)
	draw_rect(box, Color(90 / 255.0, 24 / 255.0, 16 / 255.0, 0.85 * pulse))
	draw_rect(box, Color("#e0463a", pulse), false, 2 * dpr)
	draw_string(font, box.position + Vector2(pad.x, pad.y + font.get_ascent(font_size)), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#ffe2d8", pulse))
