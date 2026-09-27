@tool
class_name GroveFlourish
extends Control

## Gilded vine flourishes in the four corners of a page -- the "illuminated grove"
## border every menu screen gets through [MenuBackdrop]. A corner is an L of two
## hairlines that fade out along the edges, a curling vine with leaves, and a gold
## diamond at the knot. Faint by design (it frames, never competes). Drawn once and
## cached by the canvas item; redraws only on resize.

@export var color: Color = Color(MenuTheme.GOLD, 0.34):
	set(v):
		color = v
		queue_redraw()
## Distance of the corner knot from the screen edges.
@export var inset: float = 12.0
## Length of each arm.
@export var arm: float = 130.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	if size.x < arm * 2.5 or size.y < arm * 2.0:
		return
	for sx in [1.0, -1.0]:
		for sy in [1.0, -1.0]:
			var origin := Vector2(inset if sx > 0.0 else size.x - inset, inset if sy > 0.0 else size.y - inset)
			draw_set_transform(origin, 0.0, Vector2(sx, sy))
			_corner()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _corner() -> void:
	var ci := get_canvas_item()
	# Fading arms along both edges.
	var n := 8
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var a := color.a * (1.0 - t0)
		draw_line(Vector2(arm * t0, 0), Vector2(arm * t1, 0), Color(color, a), 1.5, true)
		draw_line(Vector2(0, arm * 0.75 * t0), Vector2(0, arm * 0.75 * t1), Color(color, a), 1.5, true)
	# Second, inner hairline.
	draw_line(Vector2(9, 6), Vector2(arm * 0.55, 6), Color(color, color.a * 0.5), 1.0, true)
	draw_line(Vector2(6, 9), Vector2(6, arm * 0.4), Color(color, color.a * 0.5), 1.0, true)
	# A curling vine sweeping out of the knot.
	var pts := PackedVector2Array()
	var steps := 18
	for i in steps + 1:
		var t := float(i) / float(steps)
		var ang := lerpf(PI * 0.5, PI * 1.85, t)
		var r := lerpf(20.0, 5.0, t)
		pts.append(Vector2(18, 18) + Vector2(cos(ang), -sin(ang)) * r * Vector2(1.0, -1.0) + Vector2(t * 16.0, t * 4.0))
	draw_polyline(pts, Color(color, color.a * 0.9), 1.5, true)
	# Leaves along the arms and the vine.
	var leaf := Color(color, color.a * 0.95)
	for k in 3:
		var x := 30.0 + k * 26.0
		OrnateStyleBox.draw_leaf(ci, Vector2(x, 0), Vector2(1, 0.9 - k * 0.2), 13.0 - k * 2.0, 6.0 - k, leaf)
		OrnateStyleBox.draw_leaf(ci, Vector2(0, x * 0.8), Vector2(0.9 - k * 0.2, 1), 13.0 - k * 2.0, 6.0 - k, leaf)
	OrnateStyleBox.draw_leaf(ci, pts[steps], Vector2(1, 0.4), 12.0, 6.0, leaf)
	# The gold diamond at the knot.
	var s := 5.0
	draw_colored_polygon(PackedVector2Array([Vector2(0, -s), Vector2(s * 0.8, 0), Vector2(0, s),
		Vector2(-s * 0.8, 0)]), Color(color, minf(1.0, color.a * 1.8)))
