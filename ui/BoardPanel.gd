class_name BoardPanel
extends PanelContainer

# A town board (not in the JS original): the quartermaster's supply runs, the
# wainwright's carts, the gate captain's upgrades. Rows of what's on offer, each
# with a button; the game says what's offered (Game.board_view) and what a
# press does (Game.board_act). Styled like the trader's stall (TradePanel),
# at the right, halfway down.

const TEXT := Color("#f3e3c0")
const GOLD := Color("#ffd75e")
const EDGE := Color("#d4a32a")

var game: Game
var dpr := 1.0
var _shown := ""
var _rows: VBoxContainer
var _title: Label
var _purse: Label
var _note: Label


func _init(game_: Game) -> void:
	game = game_
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP


func _build() -> void:
	for child in get_children():
		child.queue_free()
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("#1c1714f0")
	panel.border_color = Color(EDGE, 0.6)
	panel.set_border_width_all(1)
	panel.set_content_margin_all(12 * dpr)
	add_theme_stylebox_override("panel", panel)
	custom_minimum_size.x = 380 * dpr

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", roundi(6 * dpr))
	add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", roundi(12 * dpr))
	column.add_child(head)
	_title = UiKit.label("", 13, TEXT, dpr)
	head.add_child(_title)
	_purse = UiKit.label("", 14, GOLD, dpr)
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_purse.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	head.add_child(_purse)
	head.add_child(UiKit.close_button(dpr, "Close (Esc)", func() -> void: game.board = null))
	_note = UiKit.label("", 11, Color(TEXT, 0.7), dpr)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 340 * dpr
	column.add_child(_note)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", roundi(6 * dpr))
	column.add_child(_rows)


# Show the board (`view`: { title, purse, note, rows: [{ name, detail, button,
# why, done }] }), or hide when it's null.
func refresh(view: Variant, dpr_: float) -> void:
	visible = view != null
	if not view:
		_shown = ""
		return
	var key := "%s|%s" % [dpr_, view]
	if key == _shown:
		return
	if dpr_ != dpr or not _rows:
		dpr = dpr_
		_build()
	_shown = key
	_title.text = view.title.to_upper()
	_purse.text = view.purse
	_note.text = view.get("note", "")
	_note.visible = _note.text != ""
	for child in _rows.get_children():
		child.queue_free()
	for i in view.rows.size():
		_rows.add_child(_row(i, view.rows[i]))
	reset_size()
	var screen := get_viewport_rect().size
	position = Vector2(screen.x - size.x - 16 * dpr, (screen.y - size.y) / 2)


func _row(i: int, row: Dictionary) -> Control:
	var box := PanelContainer.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0, 0, 0, 0.25)
	back.set_content_margin_all(6 * dpr)
	box.add_theme_stylebox_override("panel", back)
	if row.get("done", false):
		box.modulate.a = 0.45
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", roundi(10 * dpr))
	box.add_child(line)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 0)
	text.add_child(UiKit.label(row.name, 14, TEXT, dpr))
	var detail := UiKit.label(row.detail, 11, Color(TEXT, 0.7), dpr)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size.x = 240 * dpr
	text.add_child(detail)
	if row.why != "" and not row.get("done", false):
		text.add_child(UiKit.label(row.why, 10, Color("#ffb3a8"), dpr))
	line.add_child(text)

	var press := Button.new()
	press.text = row.button
	press.disabled = row.why != "" or row.get("done", false)
	press.tooltip_text = row.why
	press.focus_mode = Control.FOCUS_NONE
	press.custom_minimum_size = Vector2(64, 0) * dpr
	press.add_theme_font_override("font", Fonts.ui())
	press.add_theme_font_size_override("font_size", roundi(14 * dpr))
	press.add_theme_color_override("font_color", Color("#ffe9a8"))
	press.add_theme_color_override("font_hover_color", Color("#ffe9a8"))
	press.add_theme_color_override("font_disabled_color", Color(TEXT, 0.5))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var sb := StyleBoxFlat.new()
		sb.set_border_width_all(1)
		sb.set_content_margin_all(6 * dpr)
		if state == "disabled":
			sb.border_color = Color(TEXT, 0.25)
			sb.bg_color = Color(0, 0, 0, 0)
		else:
			sb.border_color = EDGE
			sb.bg_color = Color(EDGE, 0.4 if state == "hover" or state == "pressed" else 0.2)
		press.add_theme_stylebox_override(state, sb)
	press.pressed.connect(func() -> void: game.board_act(i))
	line.add_child(press)
	return box
