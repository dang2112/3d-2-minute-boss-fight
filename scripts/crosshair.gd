extends Control

@export var crosshair_size: int = 12
@export var thickness: int = 2
@export var color: Color = Color(1, 0.9, 0.2, 1)

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

func _notification(what):
	if what == NOTIFICATION_DRAW:
		_draw_crosshair()

func _draw_crosshair():
	var center = size * 0.5
	var half = crosshair_size * 0.5
	# horizontal line
	draw_rect(Rect2(center + Vector2(-half, -thickness/2.0), Vector2(crosshair_size, thickness)), color)
	# vertical line
	draw_rect(Rect2(center + Vector2(-thickness/2.0, -half), Vector2(thickness, crosshair_size)), color)
