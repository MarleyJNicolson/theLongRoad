class_name Painter
extends Node2D

# A node redrawn every frame by a function: paint.call(self) from _draw. For
# things that move and change shape (the horse, the cart, the shafts).

var paint: Callable


func _init(paint_ := Callable()) -> void:
	paint = paint_


func _draw() -> void:
	if paint.is_valid():
		paint.call(self)
