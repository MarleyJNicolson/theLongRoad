class_name Hud
extends Control

# The HUD over the pixelated world (from PixiStage.vue), drawn in screen pixels.
# So far: a stand-in status line, the cart arrow at the screen edge and the
# "straying too far" warning, the equipment, bag, cart and trade panels.
# Sizes from the CSS are in CSS pixels; `dpr` scales them to the screen.

const INK := Color("#1c1714")

var game: Game
var device_px := 2 # screen pixels per art pixel (set by Main)
var dpr := 1.0 # screen pixels per CSS pixel (set by Main)
var status: Label
var trade: TradePanel
var equipment: EquipmentPanel
var bag: InventoryPanel
var cart_store: InventoryPanel
var _built_at := 0.0 # the dpr the panels were built for


func _init(game_: Game) -> void:
	game = game_
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	status = Label.new()
	status.position = Vector2(12, 8)
	var settings := LabelSettings.new()
	settings.font = Fonts.ui(500)
	settings.font_size = 16
	settings.outline_size = 4
	settings.outline_color = INK
	status.label_settings = settings
	add_child(status)
	trade = TradePanel.new(game)
	add_child(trade)


func _process(_delta: float) -> void:
	status.text = _status_text()
	if dpr != _built_at:
		_build_panels()
	equipment.refresh()
	bag.refresh()
	cart_store.refresh()
	trade.refresh(game.trade_view(), game.gold, dpr)
	queue_redraw()


# (Re)build the panels at the current scale.
func _build_panels() -> void:
	for panel in [equipment, bag, cart_store]:
		if panel:
			panel.queue_free()
	equipment = EquipmentPanel.new(game, dpr)
	bag = InventoryPanel.new(game, "bag", dpr)
	cart_store = InventoryPanel.new(game, "cart", dpr)
	for panel in [equipment, bag, cart_store]:
		add_child(panel)
	_built_at = dpr


# Stand-in until the real HUD panels are ported.
func _status_text() -> String:
	var g := game
	var lines := []
	var line := "%s · %d m" % [g.stage.name, g.metres]
	if g.on_foot:
		line += " · on foot · breath %d%%%s · cart %d m away" % [roundi(g.breath * 100), " (out of breath)" if g.out_of_breath else "", roundi(g.cart_distance() / Game.PX_PER_METRE)]
	else:
		line += " · %d km/h · horse %d%%%s" % [g.speed_kmh(), roundi(g.stamina * 100), " (winded)" if g.winded else (" (galloping)" if g.galloping else "")]
	var change := DayNight.until_change(g.clock)
	line += " · Day %d, %s (%s in %d:%02d)" % [g.day(), DayNight.phase(g.clock),
		"dawn" if DayNight.is_night(g.clock) or DayNight.phase(g.clock) == "dusk" else "dusk", floori(change / 60), floori(change) % 60]
	if g.banner and g.banner.t > 0:
		line += "   ·   %s — %s" % [g.banner.title, g.banner.sub]
	lines.append(line)
	var weapon: Dictionary = g.ranged() if g.active == "ranged" else g.melee()
	var ammo := ""
	if g.active == "ranged":
		ammo = " · %d %s (%s)" % [g.ammo_count(weapon.ammo), weapon.ammo, "bag" if g.on_foot else "cart + bag"]
	lines.append("hearts %d/%d · cart %d/%d · %s in hand%s · felled %d · gold %d" % [
		g.health, Game.MAX_HEALTH, g.cart_health, Game.MAX_CART_HEALTH, weapon.name, ammo, g.kills, g.gold])
	if g.state == "over":
		lines.append("%s — %s.   Space / R to try again" % [g.over_reason.title, g.over_reason.text])
	elif g.on_foot:
		lines.append("WASD walk · Shift sprint · Ctrl/Space dash · E climb on (at the cart) · click attack · Q swap")
	else:
		lines.append("W/S drive · A/D steer · Shift gallop · E get down · click attack · Q swap")
	lines.append("Debug: F2 ranged weapon · F3 melee weapon · F4 raiders · 1-4 zoom · F1 filter")
	if g.interaction and g.interaction.label:
		lines.append(g.interaction.label)
	if g.toast:
		lines.append(g.toast.text)
	return "\n".join(lines)


func _draw() -> void:
	# Waking at the inn: the screen fades back in
	if game.rest_fade > 0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, game.rest_fade))
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
	draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color("#ffb3a8") if warn else Color("#f3e3c0"))


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
