@tool
class_name GroveRule
extends Control

## A filigree divider: a gold diamond with a leaf, trailing a hairline that fades out
## -- the "illuminated grove" replacement for plain accent bars and separators.
##
## [member centered] = true draws a symmetric rule (diamond in the middle, lines both
## ways) for centred headers / dialogs; otherwise the diamond sits at the left and the
## line runs right. Redraws only on resize / property change.

@export var color: Color = MenuTheme.GOLD:
	set(v):
		color = v
		queue_redraw()
@export var centered: bool = false:
	set(v):
		centered = v
		queue_redraw()
## Length of the visible line (the control may be wider; 0 = fill the width).
@export var length: float = 0.0:
	set(v):
		length = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(72, 10)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var h := size.y
	var y := h * 0.5
	var s := clampf(h * 0.42, 3.0, 5.5)
	var w := size.x if length <= 0.0 else minf(length, size.x)
	if centered:
		var cx := size.x * 0.5
		_line(Vector2(cx + s * 1.6, y), Vector2(cx + w * 0.5, y))
		_line(Vector2(cx - s * 1.6, y), Vector2(cx - w * 0.5, y))
		_diamond(Vector2(cx, y), s)
		OrnateStyleBox.draw_leaf(get_canvas_item(), Vector2(cx + s * 1.0, y), Vector2(1, -0.55), s * 2.2, s * 0.9, Color(color, 0.85))
		OrnateStyleBox.draw_leaf(get_canvas_item(), Vector2(cx - s * 1.0, y), Vector2(-1, -0.55), s * 2.2, s * 0.9, Color(color, 0.85))
	else:
		_diamond(Vector2(s, y), s)
		OrnateStyleBox.draw_leaf(get_canvas_item(), Vector2(s * 1.8, y), Vector2(1, -0.6), s * 2.3, s * 0.95, Color(color, 0.85))
		_line(Vector2(s * 2.2, y), Vector2(w, y))


func _diamond(c: Vector2, s: float) -> void:
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.8, 0),
		c + Vector2(0, s), c + Vector2(-s * 0.8, 0)]), color)


func _line(a: Vector2, b: Vector2) -> void:
	# A hairline that fades from the accent colour to clear.
	var n := 6
	for i in n:
		var t0 := float(i) / float(n)
		var t1 := float(i + 1) / float(n)
		var alpha := color.a * (1.0 - t0 * 0.9)
		draw_line(a.lerp(b, t0), a.lerp(b, t1), Color(color, alpha), 1.5, true)
