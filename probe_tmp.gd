extends SceneTree

var t := 0.0
var next_log := 6.0

func _initialize() -> void:
	root.add_child(load("res://main.tscn").instantiate())

func _process(dt: float) -> bool:
	t += dt
	if t > next_log:
		next_log += 8
		var game: Game = root.get_node("Main").game
		print("%4.0fs fps %d  process %.1f ms  draw calls %d  canvas items %d  nodes %d  items %d  obstacles %d" % [t,
			Performance.get_monitor(Performance.TIME_FPS), Performance.get_monitor(Performance.TIME_PROCESS) * 1000,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT), game.scenery.items.size(), game.scenery.obstacles().size()])
	return t > 30
