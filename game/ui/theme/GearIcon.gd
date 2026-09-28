@tool
class_name GearIcon
extends Control

## A drawn settings gear: eight trapezoid teeth on a ring with an open hub, drawn with
## canvas primitives so it is crisp at any stretch scale and never depends on a font.
##
## WHY DRAWN. Neither the theme fonts (Cinzel / the body face) nor Godot's fallback font
## has a glyph for the gear U+2699 -- it only rendered where the OS happened to supply a
## fallback, and drew as an empty tofu box everywhere else. The Latin-1 stand-in that
## replaced it ("¤") read as a placeholder, not a gear. A drawn mark is the one choice
## that is right on every machine.
##
## Usage: add as a child of a Button (it fills the button, centred, and ignores the
## mouse). By default it takes the button's CURRENT font colour -- normal / hover /
## pressed / focus / disabled, from the button's own theme -- so it tints exactly as a
## text label on that button would. Set [member color_override] to pin a colour instead.
##
##   var gear := GearIcon.attach(settings_button)

## Number of teeth.
@export_range(5, 16) var teeth: int = 8:
	set(v):
		teeth = v
		queue_redraw()
## Tip-to-tip diameter as a fraction of the control's smaller side.
@export_range(0.2, 1.0) var diameter_fraction: float = 0.5:
	set(v):
		diameter_fraction = v
		queue_redraw()
## A fixed colour; alpha 0 (the default) means "follow the parent button's font colour".
@export var color_override: Color = Color(0, 0, 0, 0):
	set(v):
		color_override = v
		queue_redraw()


## Make a GearIcon, add it to [param button] filling it, and return it.
static func attach(button: Control) -> GearIcon:
	var gear := GearIcon.new()
	gear.name = "GearIcon"
	button.add_child(gear)
	gear.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return gear


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE


func _ready() -> void:
	# Follow the parent button's state so the tint tracks hover / press / focus.
	var b := get_parent() as BaseButton
	if b == null:
		return
	for sig in [&"mouse_entered", &"mouse_exited", &"focus_entered", &"focus_exited",
			&"button_down", &"button_up", &"toggled", &"theme_changed"]:
		if b.has_signal(sig):
			b.connect(sig, _on_parent_state_changed.unbind(1) if sig == &"toggled" else _on_parent_state_changed)


func _on_parent_state_changed() -> void:
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED or what == NOTIFICATION_THEME_CHANGED:
		queue_redraw()


## The colour the gear is drawn in right now.
func current_color() -> Color:
	if color_override.a > 0.0:
		return color_override
	var b := get_parent() as Button
	if b == null:
		return get_theme_color(&"font_color", &"Button")
	var slot: StringName = &"font_color"
	match b.get_draw_mode():
		BaseButton.DRAW_DISABLED:
			slot = &"font_disabled_color"
		BaseButton.DRAW_PRESSED:
			slot = &"font_pressed_color"
		BaseButton.DRAW_HOVER:
			slot = &"font_hover_color"
		BaseButton.DRAW_HOVER_PRESSED:
			slot = &"font_hover_pressed_color"
		_:
			if b.has_focus():
				slot = &"font_focus_color"
	return b.get_theme_color(slot)


## Tip radius of the gear as currently laid out (0 before the control has a size).
func outer_radius() -> float:
	return minf(size.x, size.y) * diameter_fraction * 0.5


func _draw() -> void:
	var r_tip := outer_radius()
	if r_tip < 2.0:
		return
	var c := size * 0.5
	var col := current_color()
	var r_body := r_tip * 0.74
	var r_hole := r_tip * 0.30
	# The ring: one thick antialiased arc from the hub hole out to the tooth roots.
	var ring_w := r_body - r_hole
	draw_arc(c, r_hole + ring_w * 0.5, 0.0, TAU, 48, col, ring_w, true)
	# The teeth: trapezoids from just inside the ring out to the tips, with an AA edge.
	var n := maxi(teeth, 3)
	var half_base := PI / float(n) * 0.52
	var half_tip := PI / float(n) * 0.36
	var r_root := r_body - 0.5
	for i in n:
		var a := TAU * float(i) / float(n) - PI * 0.5
		var pts := PackedVector2Array([
			c + Vector2.from_angle(a - half_base) * r_root,
			c + Vector2.from_angle(a - half_tip) * r_tip,
			c + Vector2.from_angle(a + half_tip) * r_tip,
			c + Vector2.from_angle(a + half_base) * r_root,
		])
		draw_colored_polygon(pts, col)
		var edge := PackedVector2Array(pts)
		edge.append(pts[0])
		draw_polyline(edge, col, 1.0, true)
