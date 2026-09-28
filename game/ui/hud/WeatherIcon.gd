extends Control
class_name WeatherIcon

## Small vector weather glyph drawn with primitives (no font / texture dependency):
## sun, rain cloud, sand gusts, bloom flower, or a clear-sky ring. Keyed on
## [member WeatherResource.fx_kind].

var kind: StringName = &"clear":
	set(v):
		kind = v
		queue_redraw()
var color: Color = Color(1, 1, 1):
	set(v):
		color = v
		queue_redraw()


func _init(p_kind: StringName = &"clear", p_color: Color = Color(1, 1, 1), px: float = 22.0) -> void:
	kind = p_kind
	color = p_color
	custom_minimum_size = Vector2(px, px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var s := minf(size.x, size.y)
	var c := size * 0.5
	var r := s * 0.5
	var w := maxf(1.5, s * 0.08)
	match kind:
		&"sun":
			draw_circle(c, r * 0.42, color)
			for i in 8:
				var a := TAU * float(i) / 8.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c + d * r * 0.6, c + d * r * 0.95, color, w, true)
		&"rain":
			var cloud := color.lightened(0.25)
			draw_circle(c + Vector2(-r * 0.3, -r * 0.2), r * 0.32, cloud)
			draw_circle(c + Vector2(r * 0.1, -r * 0.35), r * 0.38, cloud)
			draw_circle(c + Vector2(r * 0.45, -r * 0.15), r * 0.28, cloud)
			draw_rect(Rect2(c + Vector2(-r * 0.6, -r * 0.2), Vector2(r * 1.3, r * 0.3)), cloud)
			for i in 3:
				var x := -r * 0.4 + float(i) * r * 0.4
				draw_line(c + Vector2(x, r * 0.3), c + Vector2(x - r * 0.15, r * 0.85), color, w, true)
		&"sand":
			for i in 3:
				var y := -r * 0.5 + float(i) * r * 0.5
				var pts := PackedVector2Array()
				for k in 9:
					var t := float(k) / 8.0
					pts.append(c + Vector2(-r * 0.9 + t * r * 1.8, y + sin(t * TAU + float(i)) * r * 0.12))
				draw_polyline(pts, color, w, true)
		&"bloom":
			for i in 5:
				var a := TAU * float(i) / 5.0 - PI / 2.0
				draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.45, r * 0.3, color)
			draw_circle(c, r * 0.24, Color(1.0, 0.9, 0.45))
		_:
			draw_arc(c, r * 0.6, 0.0, TAU, 24, color, w, true)
