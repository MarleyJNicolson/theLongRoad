class_name Obstacles
extends RefCounted

# Everything solid in the world (scenery and encounters), as Vector3(x, y,
# radius), filed in a grid so a moving thing only checks what's near it. It's
# refiled only when either source list changes (they hand out the same array
# until then).

var list: Array = []
var _grid := Grid.new(96)
var _from: Array = [null, null] # the source arrays it was built from


# Bring it up to date with the scenery's and encounters' solids.
func refresh(scenery_solids: Array, encounter_solids: Array) -> void:
	if is_same(scenery_solids, _from[0]) and is_same(encounter_solids, _from[1]):
		return
	_from = [scenery_solids, encounter_solids]
	list = scenery_solids + encounter_solids
	_grid.clear()
	for o: Vector3 in list:
		_grid.add(Vector2(o.x, o.y), o.z, o)


# The solids that might be within `reach` of `at`.
func near(at: Vector2, reach: float) -> Array:
	return _grid.near(at, reach)


# Is `at` inside any of them (grown by `extra`)?
func hits(at: Vector2, extra := 0.0) -> bool:
	for o: Vector3 in _grid.near(at, extra):
		if Vector2(o.x, o.y).distance_to(at) < o.z + extra:
			return true
	return false
