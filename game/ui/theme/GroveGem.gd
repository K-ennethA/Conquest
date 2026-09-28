@tool
class_name GroveGem
extends Control

## A small cut gem (faceted diamond) in [member color] -- the element marker used
## beside move names, in the forecast title and anywhere a flat colour swatch would
## otherwise sit. Upper facets lighter, lower darker, a thin dark rim; redraws only
## when the colour or size changes.

@export var color: Color = MenuTheme.GOLD:
	set(v):
		if v == color:
			return
		color = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(14, 18)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var hw := minf(size.x, size.y * 0.8) * 0.5
	var hh := minf(size.y, size.x * 1.25) * 0.5
	var top := c + Vector2(0, -hh)
	var right := c + Vector2(hw, 0)
	var bottom := c + Vector2(0, hh)
	var left := c + Vector2(-hw, 0)
	var mid := c + Vector2(0, -hh * 0.15)
	# Four facets: light upper-left, mid upper-right, darker lower halves.
	draw_colored_polygon(PackedVector2Array([top, mid, left]), color.lightened(0.35))
	draw_colored_polygon(PackedVector2Array([top, right, mid]), color.lightened(0.1))
	draw_colored_polygon(PackedVector2Array([left, mid, bottom]), color.darkened(0.15))
	draw_colored_polygon(PackedVector2Array([mid, right, bottom]), color.darkened(0.4))
	draw_polyline(PackedVector2Array([top, right, bottom, left, top]), Color(0, 0, 0, 0.55), 1.0, true)
