extends Node

# Hosts the pixelated world and the HUD (port of PixiStage.vue's setup).
#
#   Post (SubViewport, art resolution)
#     World (SubViewport, art resolution) ← the game world
#     Filter (TextureRect showing World, pixel_art.gdshader)
#   Screen (TextureRect showing Post, scaled up with nearest filtering)
#   HUD (CanvasLayer) ← not pixelated
#
# The filter runs once per art pixel, as in the JS, and the window is snapped
# to a whole number of art pixels so the grid never sits half a pixel out
# (which once showed as a diagonal seam).

const WORLD_SCENE := preload("res://world/World.tscn")
const PIXEL_SHADER := preload("res://fx/pixel_art.gdshader")

var world_view: SubViewport
var post_view: SubViewport
var filter_rect: TextureRect
var screen: TextureRect
var game: Game
var hud: CanvasLayer
var hud_view: Hud
var filter_on := true


func _ready() -> void:
	RenderingServer.set_default_clear_color(PixelArt.INK)

	post_view = _art_viewport("Post")
	add_child(post_view)
	# Nested inside Post, so it's rendered first each frame.
	world_view = _art_viewport("World")
	# Smooth sampling: with nearest, a pixel landing exactly between two
	# texture pixels can round differently on each triangle of a shape.
	world_view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	post_view.add_child(world_view)
	game = WORLD_SCENE.instantiate() as Game
	world_view.add_child(game)

	filter_rect = TextureRect.new()
	filter_rect.name = "Filter"
	filter_rect.texture = world_view.get_texture()
	filter_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	filter_rect.stretch_mode = TextureRect.STRETCH_SCALE
	filter_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var material := ShaderMaterial.new()
	material.shader = PIXEL_SHADER
	material.set_shader_parameter("palette", PixelArt.palette_vectors())
	filter_rect.material = material
	post_view.add_child(filter_rect)

	screen = TextureRect.new()
	screen.name = "Screen"
	screen.texture = post_view.get_texture()
	screen.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	screen.stretch_mode = TextureRect.STRETCH_SCALE
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(screen)

	hud = CanvasLayer.new()
	hud.name = "HUD"
	add_child(hud)
	hud_view = Hud.new(game)
	hud.add_child(hud_view)

	get_viewport().size_changed.connect(_fit)
	_fit()


func _art_viewport(view_name: String) -> SubViewport:
	var view := SubViewport.new()
	view.name = view_name
	view.disable_3d = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return view


# Size everything to a whole number of art pixels.
func _fit() -> void:
	var window := get_viewport().get_visible_rect().size
	var dpr := PixelArt.device_scale()
	var device_px := maxi(1, roundi(PixelArt.PIXEL_SIZE * dpr)) # device pixels per art pixel
	var cols := maxi(1, floori(window.x / device_px))
	var rows := maxi(1, floori(window.y / device_px))
	world_view.size = Vector2i(cols, rows)
	post_view.size = Vector2i(cols, rows)
	filter_rect.position = Vector2.ZERO
	filter_rect.size = Vector2(cols, rows)
	screen.position = Vector2.ZERO
	screen.size = Vector2(cols * device_px, rows * device_px)
	game.art_zoom = PixelArt.WORLD_ZOOM * dpr / device_px
	game.css_per_art = device_px / dpr
	_device_px = device_px
	hud_view.device_px = device_px
	hud_view.dpr = dpr


var _device_px := PixelArt.PIXEL_SIZE


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and not "--nomouse" in OS.get_cmdline_user_args():
		game.pointer_active = true


func _notification(what: int) -> void:
	if not game:
		return
	if what == NOTIFICATION_WM_MOUSE_ENTER:
		game.pointer_inside = true
	elif what == NOTIFICATION_WM_MOUSE_EXIT:
		game.pointer_inside = false


func _unhandled_key_input(event: InputEvent) -> void:
	# Debug: F1 toggles the pixel-art pass to compare before / after.
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		filter_on = not filter_on
		screen.texture = post_view.get_texture() if filter_on else world_view.get_texture()
		return
	# The world viewport isn't in a container, so it gets no input events of
	# its own: hand the game its (debug) keys from here.
	game.debug_key(event)


var _frames := 0


func _process(_delta: float) -> void:
	# The mouse, in art pixels over the world view
	game.pointer = get_viewport().get_mouse_position() / _device_px
	game.pointer_over_ui = get_viewport().gui_get_hovered_control() != null

	# Debug: `-- --screenshot=<path> [--frame=N]` saves frame N (30) and quits;
	# `--hold=up,boost` holds those actions down from the start.
	_frames += 1
	var args := OS.get_cmdline_user_args()
	var shot_at := 30
	for arg in args:
		if arg.begins_with("--frame="):
			shot_at = int(arg.trim_prefix("--frame="))
		elif arg.begins_with("--hold=") and _frames == 1:
			for action in arg.trim_prefix("--hold=").split(","):
				Input.action_press(action)
		elif arg.begins_with("--press=") and _frames == 20:
			# Real key presses through the input pipeline, e.g. --press=F2,F4
			for key in arg.trim_prefix("--press=").split(","):
				var press := InputEventKey.new()
				press.keycode = OS.find_keycode_from_string(key)
				press.pressed = true
				Input.parse_input_event(press)
		elif arg == "--nofilter" and _frames == 1:
			filter_on = false
			screen.texture = world_view.get_texture()
	if _frames == shot_at:
		for arg in args:
			if arg.begins_with("--screenshot="):
				get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--screenshot="))
				get_tree().quit()
