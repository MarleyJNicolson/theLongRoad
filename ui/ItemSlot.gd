class_name ItemSlot
extends Control

# One square slot on a panel: draws whatever `look_of` returns (an item, or
# null for empty, with a silhouette) and reports clicks, right-clicks, hovers
# and drags. The panel decides what they mean.
#
# look_of() -> { item, count?, silhouette?, edge?, faded?, badge?, glow?, label?, dashed?, background? }

signal clicked(shift: bool)
signal right_clicked
signal hovered(on: bool)

var look_of: Callable
var dpr: float
# Drag and drop (bag and cart slots): what this slot's drag carries, and
# what to do with something dropped on it.
var drag_data: Callable = Callable()
var on_drop: Callable = Callable()
var _hover := false
var _pressed := false


func _init(size_: float, dpr_: float, show_: Callable) -> void:
	dpr = dpr_
	look_of = show_
	custom_minimum_size = Vector2(size_, size_) * dpr
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func() -> void:
		_hover = true
		hovered.emit(true))
	mouse_exited.connect(func() -> void:
		_hover = false
		_pressed = false
		hovered.emit(false))


func _process(_dt: float) -> void:
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# On release, so starting a drag isn't also a click
			if event.pressed:
				_pressed = true
			elif _pressed:
				_pressed = false
				clicked.emit(event.shift_pressed)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			right_clicked.emit()
			accept_event()


func _get_drag_data(_at: Vector2) -> Variant:
	if not drag_data.is_valid():
		return null
	var data: Variant = drag_data.call()
	if data == null:
		return null
	_pressed = false
	# Carry a copy of the picture along
	var look: Dictionary = look_of.call()
	var preview := Control.new()
	var picture := Painter.new(func(ci: CanvasItem) -> void:
		ItemIcon.draw(ci, Rect2(Vector2.ZERO, Vector2(36, 36) * dpr), look.item))
	picture.position = -Vector2(18, 18) * dpr
	preview.add_child(picture)
	set_drag_preview(preview)
	hovered.emit(false)
	return data


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return on_drop.is_valid() and data is Dictionary and data.has("from")


func _drop_data(_at: Vector2, data: Variant) -> void:
	on_drop.call(data)


func _draw() -> void:
	var look: Dictionary = look_of.call()
	var rect := Rect2(Vector2.ZERO, size)
	var item: Variant = look.get("item")
	draw_rect(rect, look.get("background", Color(0, 0, 0, 0.35)))
	if _hover and (item or look.get("always_hover", false)):
		draw_rect(rect, Color(255 / 255.0, 244 / 255.0, 214 / 255.0, 0.08))
	if look.get("glow", false):
		# In hand: a bright ring round it
		var glow := rect.grow(4 * dpr)
		draw_rect(glow, Color(255 / 255.0, 244 / 255.0, 214 / 255.0, 0.25), false, 4 * dpr)
		draw_rect(rect.grow(2 * dpr), Color("#fff4d6"), false, 2 * dpr)
	var edge: Color = look.get("edge", Color(UiKit.TEXT, 0.2))
	if look.get("dashed", false):
		_dashed_rect(rect.grow(-dpr), edge, 2 * dpr)
	else:
		draw_rect(rect.grow(-dpr), edge, false, 2 * dpr)
	var label: String = look.get("label", "")
	var picture := Rect2(rect.position + Vector2(8, 4) * dpr, rect.size - Vector2(16, 16) * dpr) if label else rect.grow(-8 * dpr)
	ItemIcon.draw(self, picture, item, look.get("silhouette", ""), look.get("faded", 1.0))
	var font := Fonts.ui()
	if label:
		var fs := roundi(9 * dpr)
		var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, Vector2((size.x - w) / 2, size.y - 4 * dpr), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(UiKit.TEXT, 0.7))
	var count: int = look.get("count", 0)
	if count > 1:
		var fs := roundi(12 * dpr)
		var text := str(count)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(size.x - w - 4 * dpr, size.y - 4 * dpr)
		draw_string(Fonts.ui(700), at + Vector2(0, dpr), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.8))
		draw_string(Fonts.ui(700), at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#fff4d6"))
	var badge: String = look.get("badge", "")
	if badge:
		var fs := roundi(8 * dpr)
		var w := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var box := Rect2(Vector2((size.x - w) / 2 - 4 * dpr, -9 * dpr), Vector2(w + 8 * dpr, 11 * dpr))
		draw_rect(box, Color("#fff4d6"))
		draw_string(font, box.position + Vector2(4 * dpr, 9 * dpr), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#3a2a1a"))


func _dashed_rect(rect: Rect2, colour: Color, width: float) -> void:
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var length := a.distance_to(b)
		var dash := 4 * dpr
		var t := 0.0
		while t < length:
			draw_line(a.lerp(b, t / length), a.lerp(b, minf(t + dash, length) / length), colour, width)
			t += dash * 2
