class_name Folk
extends Node2D

# Ordinary folk (villagers, traders, the farmer) on the same jointed figure as
# everyone else (port of folk.js). They stand about, now and then stroll a few
# steps, and wave when there's something to be glad about. The node sits where
# they stand.

const SKINS := ["#e0b896", "#d9b08c", "#c9a27a", "#a87b56", "#8a5f3e"]
const SHIRTS := ["#6b5b3e", "#7d4a3a", "#4a5a6e", "#5e6b3a", "#8a7a5a", "#6e3f4a", "#9a8a6a"]
const LEGS := ["#4a3a2b", "#3d3a33", "#5a4632", "#3a3f4a"]
const HAIR := ["#2b221c", "#5a3a1a", "#8a6a3a", "#c9a24a", "#9a948a"]
const KERCHIEFS := ["#a3331f", "#c9b28a", "#4a5a6e", "#e8e0c8"]

const STROLL := 22.0 # px/s

var rig: Rig
var home: Vector2
var facing: float
var rest_facing: float
var wander: float
var target: Variant = null
var idle: float


static func _pick(arr: Array) -> Variant:
	return arr[randi() % arr.size()]


static func look(role := "villager") -> Dictionary:
	var base := {"skin": _pick(SKINS), "shirt": _pick(SHIRTS), "legs": _pick(LEGS)}
	var extra: Dictionary
	match role:
		"farmer":
			extra = {"head": "straw", "shirt": "#7a5a3a"}
		"smith":
			extra = {"head": "hair", "head_colour": _pick(HAIR), "shirt": "#5a4a3e", "extras": ["apron"], "apron": "#3a2f26"}
		"merchant":
			extra = {"head": "hat", "head_colour": _pick(["#5e3f22", "#3a4a2a", "#6e3f4a"]), "extras": ["apron"]}
		_:
			extra = _pick([
				{"head": "hair", "head_colour": _pick(HAIR)},
				{"head": "kerchief", "head_colour": _pick(KERCHIEFS)},
				{"head": "straw"},
				{"head": "hair", "head_colour": _pick(HAIR), "extras": ["apron"]},
			])
	base.merge(extra, true)
	return base


# `wander`: how far from home they stroll (0 to stay put).
func _init(look_: Dictionary, x: float, y: float, facing_: float, wander_ := 0.0, scale_ := 1.0) -> void:
	var style := look_.duplicate()
	style.scale = scale_
	rig = Rig.new(style)
	add_child(rig)
	position = Vector2(x, y)
	home = position
	facing = facing_
	rest_facing = facing_
	wander = wander_
	idle = randf_range(1, 5)
	rig.update(0, facing, 0)


func waving(on: bool) -> void:
	rig.wave = (rig.wave if rig.wave else 0.001) if on else 0.0


func update(dt: float) -> void:
	if not visible:
		return
	var speed := 0.0
	if target != null:
		var d: Vector2 = target - position
		if d.length() < 2:
			target = null
			idle = randf_range(2, 6)
		else:
			speed = STROLL
			facing = d.angle()
			position += d.normalized() * speed * dt
	elif wander:
		idle -= dt
		if idle <= 0:
			# Off for a few steps, or back home to face the way they were
			var a := randf() * TAU
			var r := 0.0 if randf() < 0.4 else randf_range(0.3, 1) * wander
			target = home + Vector2(cos(a), sin(a)) * r
		elif position.distance_to(home) < 2:
			facing = rest_facing
	rig.update(dt, facing, speed)
