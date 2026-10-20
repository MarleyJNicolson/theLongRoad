class_name Glow
extends RefCounted

# Lights that shine at night (fires, lanterns): 2D point lights whose
# brightness Game fades in with the dark (they're in the "night_lights"
# group, with their full energy kept as meta "energy").

const GROUP := &"night_lights"

static var _texture: GradientTexture2D


# A soft round light `radius` px across, of `colour`.
static func light(radius: float, colour: Color, energy := 1.0) -> PointLight2D:
	if not _texture:
		_texture = GradientTexture2D.new()
		_texture.width = 256
		_texture.height = 256
		_texture.fill = GradientTexture2D.FILL_RADIAL
		_texture.fill_from = Vector2(0.5, 0.5)
		_texture.fill_to = Vector2(1.0, 0.5)
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.45, Color(1, 1, 1, 0.45))
		_texture.gradient = gradient
	var l := PointLight2D.new()
	l.texture = _texture
	l.texture_scale = radius * 2 / 256.0
	l.color = colour
	l.energy = 0.0
	l.set_meta("energy", energy)
	l.add_to_group(GROUP)
	return l


# Set every light's brightness for how dark it is.
static func shine(tree: SceneTree, darkness: float) -> void:
	for l: PointLight2D in tree.get_nodes_in_group(GROUP):
		l.energy = l.get_meta("energy", 1.0) * darkness
		l.visible = darkness > 0.01


# A lantern on a post: drawn, with its light at the lamp.
static func lantern_post(height := 26.0) -> Node2D:
	var post := Sketch.new()
	post.ellipse(Vector2(2, 1), 4, 2, Color(0, 0, 0, 0.25))
	post.line(Vector2(0, 0), Vector2(0, -height), 2.5, Color("#3a2a1a"))
	post.line(Vector2(0, -height), Vector2(5, -height), 2, Color("#3a2a1a"))
	post.rect(3, -height + 1, 4, 5, Color("#f6c25a"))
	var l := light(110, Color("#ffcf7a"), 1.1)
	l.position = Vector2(5, -height + 3)
	post.add_child(l)
	return post
