class_name Fonts
extends RefCounted

# The game's two typefaces (as in index.html / style.css): Pixelify Sans for
# the UI and labels, Jacquard 24 (blackletter) for titles and banners.

const PIXELIFY := preload("res://fonts/PixelifySans.ttf")
const JACQUARD := preload("res://fonts/Jacquard24.ttf")

static var _ui: Dictionary = {}


# Pixelify Sans at a given weight (it's a variable font, 400-700).
static func ui(weight := 400) -> Font:
	if not _ui.has(weight):
		var font := FontVariation.new()
		font.base_font = PIXELIFY
		font.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): weight}
		_ui[weight] = font
	return _ui[weight]


static func title() -> Font:
	return JACQUARD


# A line of text standing in the world (milestones, signposts), centred on
# `centre`, in Pixelify Sans semibold. Big enough to stay legible once drawn
# at pixel-art resolution.
static func world_label(text: String, centre: Vector2, size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	var settings := LabelSettings.new()
	settings.font = ui(600)
	settings.font_size = size
	settings.font_color = colour
	label.label_settings = settings
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size = Vector2(320, size * 2)
	label.position = centre - label.size / 2
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
