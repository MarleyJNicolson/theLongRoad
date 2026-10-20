class_name Sfx
extends Node

# Sound effects (not in the JS original, which was silent). The sounds are
# made by tools/make_sounds.py. Play one with Sfx.play(name, where): it's
# quieter the further it is from the middle of the view, a little higher or
# lower each time so repeats don't grate, and only so many of one sound play
# at once (a wave of three hundred raiders shouldn't be a wall of noise).
# M mutes.

const NAMES := ["bow", "crossbow", "sling", "swing", "swing_heavy", "hit", "hit_heavy", "hit_arrow",
	"thunk", "block", "fall", "hurt", "coin", "horn"]
const VOICES := 24 # players in the pool
const PER_SOUND := 4 # most of one sound at once
const NEAR := 250.0 # px: full volume this close to the middle of the view
const FAR := 1600.0 # px: silent beyond this
const LEVELS := {"horn": 4.0, "coin": -6.0, "thunk": -8.0, "fall": -4.0, "swing": -4.0, "swing_heavy": -2.0}

static var _self: Sfx
static var listener := Vector2.ZERO # the middle of the view (set by Game)
static var muted := false

var _streams := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	_self = self
	for n in NAMES:
		var stream: Variant = load("res://sounds/%s.wav" % n)
		if stream:
			_streams[n] = stream
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


# Play `sound` from `at` (world px; INF: no place, full volume). `gain` in dB.
static func play(sound: String, at := Vector2.INF, gain := 0.0, wobble := 0.08) -> void:
	if muted or _self == null or not _self._streams.has(sound):
		return
	var db: float = gain + LEVELS.get(sound, 0.0)
	if at != Vector2.INF:
		var d := at.distance_to(listener)
		if d > FAR:
			return
		db -= maxf(0.0, d - NEAR) / (FAR - NEAR) * 24.0
	_self._start(sound, db, wobble)


func _start(sound: String, db: float, wobble: float) -> void:
	var stream: AudioStream = _streams[sound]
	var same := 0
	var free: AudioStreamPlayer = null
	var oldest: AudioStreamPlayer = null
	for p in _players:
		if p.playing:
			if p.stream == stream:
				same += 1
				if oldest == null or p.get_playback_position() > oldest.get_playback_position():
					oldest = p
		elif free == null:
			free = p
	var player := free
	if same >= PER_SOUND:
		player = oldest # cut off the oldest of its kind
	if player == null:
		return
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = 1.0 + randf_range(-wobble, wobble)
	player.play()
