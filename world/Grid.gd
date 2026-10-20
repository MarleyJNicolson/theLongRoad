class_name Grid
extends RefCounted

# A spatial hash: things filed by the square cells they cover, so "what's
# near here?" only looks at a few cells instead of everything.

var cell: float
var _cells := {} # Vector2i -> Array


func _init(cell_: float) -> void:
	cell = cell_


func _key(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / cell), floori(at.y / cell))


# File `value` under every cell a circle of `radius` round `at` touches.
func add(at: Vector2, radius: float, value: Variant) -> void:
	var lo := _key(at - Vector2(radius, radius))
	var hi := _key(at + Vector2(radius, radius))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var key := Vector2i(cx, cy)
			if not _cells.has(key):
				_cells[key] = []
			_cells[key].append(value)


func remove(at: Vector2, radius: float, value: Variant) -> void:
	var lo := _key(at - Vector2(radius, radius))
	var hi := _key(at + Vector2(radius, radius))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var key := Vector2i(cx, cy)
			if _cells.has(key):
				_cells[key].erase(value)
				if _cells[key].is_empty():
					_cells.erase(key)


# Everything filed in the cells within `reach` of `at` (it may be further
# off than that; check the distance). A thing in several cells can turn up
# more than once.
func near(at: Vector2, reach: float) -> Array:
	var out := []
	var lo := _key(at - Vector2(reach, reach))
	var hi := _key(at + Vector2(reach, reach))
	for cx in range(lo.x, hi.x + 1):
		for cy in range(lo.y, hi.y + 1):
			var key := Vector2i(cx, cy)
			if _cells.has(key):
				out.append_array(_cells[key])
	return out


func clear() -> void:
	_cells.clear()
