class_name SpriteBank
extends Node

# Sprite sheets baked from the rigs, so crowds draw cheaply (not in the JS
# original). The first time a look is wanted (a raider type, its gear, its
# size), it's posed in every way a crowd needs, all at once in a hidden
# viewport, and the result kept as one texture. A Rig in sprite mode then just
# shows the nearest frame (see Rig.update): one image instead of dozens of
# shapes. Deaths and arrows stuck in a body still use the live rig.
#
# Sheet: a row per facing (FACINGS round the compass), and along each row:
#   0          standing
#   1..8       walking, through the stride
#   9..15      a strike: windup ×2, swing ×4 (with its trail), recover
#   16..18     drawing a bow: slack, half, full
#   19         flinching from a blow

const FACINGS := 8
const WALK := 8
const COLUMNS := 20
const STAND := 0
const WALK_AT := 1
const STRIKE_AT := 9
const AIM_AT := 16
const FLINCH := 19
const CELL := 100.0 # px per frame for a figure of scale 1 (world units)
const FEET := 0.72 # how far down its cell a figure stands

static var instance: SpriteBank

var sheets := {} # look key -> { texture, cell }
var _wanted: Array = [] # [key, rig] waiting to be baked
var _baking := false


func _init() -> void:
	instance = self


# The sheet for this rig's look, or null while it's still being baked (it's
# asked for here the first time).
static func sheet_for(rig: Rig) -> Variant:
	if not instance:
		return null
	var key := key_of(rig)
	if instance.sheets.has(key):
		return instance.sheets[key]
	if not instance._wanted.any(func(w: Array) -> bool: return w[0] == key):
		instance._wanted.append([key, rig.style.duplicate(), rig.weapon, rig.offhand])
	return null


static func key_of(rig: Rig) -> String:
	if not rig.has_meta("sheet_key"): # (worked out once per figure)
		rig.set_meta("sheet_key", "%s|%s|%s|%s|%s|%s|%.2f" % [rig.style.get("head"), rig.style.get("skin"), rig.style.get("shirt"),
			rig.style.get("head_colour"), rig.weapon, rig.offhand, rig.k])
	return rig.get_meta("sheet_key")


# Which cell shows this rig's current state: Vector2i(column, row).
static func frame_of(rig: Rig) -> Vector2i:
	var row := posmod(roundi(rig.facing / (TAU / FACINGS)), FACINGS)
	if rig.strike:
		var p: float = rig.strike.p
		match rig.strike.phase:
			"windup":
				return Vector2i(STRIKE_AT + (0 if p < 0.75 else 1), row)
			"swing":
				return Vector2i(STRIKE_AT + 2 + clampi(ceili(p * 4) - 1, 0, 3), row)
			_:
				return Vector2i(STRIKE_AT + 6, row)
	if rig.aiming:
		return Vector2i(AIM_AT + clampi(roundi(rig.pull * 2), 0, 2), row)
	if rig.flinch > 0.5:
		return Vector2i(FLINCH, row)
	if rig.speed > 5:
		var step := posmod(floori(fposmod(rig.phase, TAU) / TAU * WALK + 0.5), WALK)
		return Vector2i(WALK_AT + step, row)
	return Vector2i(STAND, row)


func _process(_dt: float) -> void:
	if _baking or _wanted.is_empty():
		return
	_bake(_wanted.pop_front())


# Pose a figure in every cell, render the lot once, keep the picture.
func _bake(wanted: Array) -> void:
	_baking = true
	var key: String = wanted[0]
	var style: Dictionary = wanted[1]
	var cell := ceilf(CELL * style.get("scale", 1.0))
	var view := SubViewport.new()
	view.size = Vector2i(roundi(cell * COLUMNS), roundi(cell * FACINGS))
	view.transparent_bg = true
	view.disable_3d = true
	view.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	for row in FACINGS:
		for column in COLUMNS:
			var rig := Rig.new(style)
			rig.weapon = wanted[2]
			rig.offhand = wanted[3]
			rig.always = true
			rig.position = Vector2((column + 0.5) * cell, (row + FEET) * cell)
			rig.facing = row * TAU / FACINGS
			_pose(rig, column)
			view.add_child(rig)
	# Drawn this frame, rendered by the next
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := view.get_texture().get_image()
	sheets[key] = {"texture": ImageTexture.create_from_image(image), "cell": cell}
	view.queue_free()
	_baking = false


static func _pose(rig: Rig, column: int) -> void:
	rig.speed = 0.0
	rig.loaded = true
	if column >= WALK_AT and column < WALK_AT + WALK:
		rig.speed = 60.0
		rig.phase = float(column - WALK_AT) / WALK * TAU
	elif column >= STRIKE_AT and column < STRIKE_AT + 7:
		var n := column - STRIKE_AT
		if n < 2:
			rig.set_strike("windup", 0.5 if n == 0 else 1.0)
		elif n < 6:
			rig.set_strike("swing", (n - 1) / 4.0)
		else:
			rig.set_strike("recover", 0.5)
	elif column >= AIM_AT and column < AIM_AT + 3:
		rig.aiming = rig.offhand != null
		rig.pull = (column - AIM_AT) / 2.0
	elif column == FLINCH:
		rig.flinch = 1.0
	rig._frame = rig.pose()
	rig.queue_redraw()
