class_name UiKit
extends RefCounted

# Shared pieces for the HUD panels, styled after the Vue components' CSS.
# Sizes are CSS pixels, scaled by `dpr`.

const TEXT := Color("#f3e3c0")
const PANEL := Color("#1c1714f0")
const GOLD := Color("#ffd75e")
const GILT := Color("#d4a32a")
const INK := Color("#1c1714")


static func label(text: String, size: float, colour: Color, dpr: float, weight := 400) -> Label:
	var l := Label.new()
	l.text = text
	var settings := LabelSettings.new()
	settings.font = Fonts.ui(weight)
	settings.font_size = roundi(size * dpr)
	settings.font_color = colour
	l.label_settings = settings
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func panel_style(border: Color, dpr: float, padding := Vector4(10, 12, 10, 12), background := PANEL) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = background
	box.border_color = border
	box.set_border_width_all(1 if border.a > 0 else 0)
	box.content_margin_top = padding.x * dpr
	box.content_margin_right = padding.y * dpr
	box.content_margin_bottom = padding.z * dpr
	box.content_margin_left = padding.w * dpr
	return box


# The × in a panel's corner.
static func close_button(dpr: float, tip: String, on_press: Callable) -> Button:
	var close := Button.new()
	close.text = "×"
	close.flat = true
	close.tooltip_text = tip
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_override("font", Fonts.ui())
	close.add_theme_font_size_override("font_size", roundi(18 * dpr))
	close.add_theme_color_override("font_color", Color(TEXT, 0.7))
	close.add_theme_color_override("font_hover_color", TEXT)
	close.pressed.connect(on_press)
	return close


# A tooltip box: a title, a subtitle and lines of detail, edged in the item's
# quality colour. It floats free of its panel's layout (top_level).
class Tip:
	extends PanelContainer

	var dpr: float
	var _lines: VBoxContainer
	var _width: float

	func _init(dpr_: float, width: float) -> void:
		dpr = dpr_
		_width = width
		top_level = true
		visible = false
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 2
		_lines = VBoxContainer.new()
		_lines.add_theme_constant_override("separation", roundi(2 * dpr))
		add_child(_lines)

	# `at` is where its anchor corner goes (global); `from_bottom` puts its
	# bottom edge there instead of its top.
	func show_tip(title: String, sub: String, lines: Array, colour: Color, at: Vector2, from_bottom := false) -> void:
		var box := UiKit.panel_style(colour, dpr, Vector4(8, 10, 8, 10), Color(30 / 255.0, 20 / 255.0, 10 / 255.0, 0.95))
		add_theme_stylebox_override("panel", box)
		for child in _lines.get_children():
			child.queue_free()
		_lines.add_child(UiKit.label(title, 15, UiKit.TEXT, dpr, 600))
		if sub:
			_lines.add_child(UiKit.label(sub, 11, Color(UiKit.TEXT, 0.7), dpr))
		for line in lines:
			var l := UiKit.label(line, 13, UiKit.TEXT, dpr)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			l.custom_minimum_size.x = (_width - 20) * dpr
			_lines.add_child(l)
		custom_minimum_size.x = _width * dpr
		reset_size()
		visible = true
		# (Its size settles once the labels are laid out)
		await get_tree().process_frame
		if not is_instance_valid(self):
			return
		reset_size()
		global_position = at - Vector2(0, size.y if from_bottom else 0)

	func hide_tip() -> void:
		visible = false
