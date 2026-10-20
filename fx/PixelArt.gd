class_name PixelArt
extends RefCounted

# The game is drawn with ordinary shapes, then a post-process turns the whole
# frame into grim medieval pixel art: it runs at a reduced resolution (see
# PIXEL_SIZE), snaps every colour to a limited palette with a touch of ordered
# dithering, and inks dark outlines along strong edges (pixel_art.gdshader).

# Screen pixels per art pixel.
const PIXEL_SIZE := 2

# How far the camera zooms in on the world, so sprites get enough art pixels
# to read clearly.
const WORLD_ZOOM := 1.0 # (1.3 in the JS: this shows 30% more)

# A muted, earthy palette with warm accents: soot and bone, moss, stone and
# steel, then blood, rust, fire and gold.
const PALETTE := [
	# soot, earth and bone
	"#0e0b0a", "#1c1714", "#2b221c", "#3d2f25", "#4a3a2b", "#54402f", "#6e553c", "#7c6045", "#8a6c4b", "#98795a",
	"#a88a62", "#b89a70", "#c9ad80", "#d6bf94", "#e6d3a8",
	# moss and leaf
	"#121a12", "#1d2a1a", "#2a3b22", "#33452a", "#3a4f2b", "#46592f", "#4f6634", "#5d7339", "#6a7f42", "#7a8c4c",
	"#8a9a55", "#9fab66",
	# dry grass and straw
	"#3a3620", "#5c5530", "#706638", "#857a45", "#988b50", "#ab9c5c", "#c4b373",
	# stone, steel and snow
	"#16181e", "#262a33", "#2f343d", "#3c424d", "#4a515c", "#575f6b", "#69717c", "#7c848f", "#8f97a1", "#a7aeb6",
	"#c0c6cc", "#d9dee2", "#eef1f2",
	# dusk blues
	"#1d2836", "#33475a", "#4d6478",
	# blood, rust, fire and gold
	"#2a0e0e", "#4a1514", "#76201a", "#a3331f", "#cf5528", "#ee8a36", "#f6c25a", "#fdf0a6",
]

# PALETTE[0], the outline ink.
const INK := Color(14 / 255.0, 11 / 255.0, 10 / 255.0)


# The palette as shader-ready colour vectors.
static func palette_vectors() -> PackedVector3Array:
	var out := PackedVector3Array()
	for hex in PALETTE:
		var c := Color.html(hex)
		out.append(Vector3(c.r, c.g, c.b))
	return out


# Physical pixels per logical (CSS-style) pixel, like window.devicePixelRatio.
# Windows reports a screen scale of 1, so fall back to the DPI there.
static func device_scale() -> float:
	var scale := DisplayServer.screen_get_scale()
	if is_equal_approx(scale, 1.0) and OS.get_name() == "Windows":
		scale = DisplayServer.screen_get_dpi() / 96.0
	return maxf(1.0, scale)
