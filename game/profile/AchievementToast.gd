extends CanvasLayer

## A self-contained "achievement unlocked" banner, owned and mounted by [PlayerProfile] on
## its own CanvasLayer so it appears in EVERY scene (menus and battle alike) without any
## scene needing to know about it. Banners are a bottom-centre gold chip that slides up,
## holds ~2.5s, then fades; multiple unlocks QUEUE so a burst (e.g. a retroactive load that
## unlocks several at once) plays one after another rather than stacking on top of itself.
##
## Purely presentational and defensive: it draws its own look (no theme dependency) and is
## only ever mounted when there is a real viewport, so a headless test run never builds it.

const HOLD_TIME := 2.5
const SLIDE_TIME := 0.35
const CHIP_WIDTH := 360.0

# Gold-on-dark, matching the menu register (kept local so this node has no import coupling).
const GOLD := Color("e6a64b")
const CREAM := Color("f2ead6")
const CREAM_DIM := Color("b7adc6")
const PANEL := Color("1c1930")
const BORDER := Color("e6a64b")

var _queue: Array = []
var _showing: bool = false
var _root: Control = null


func _ready() -> void:
	layer = 128  # above battle HUD and menus
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


## Queue a banner for [param title] with a badge [param icon]. Safe to spam; banners play
## in order. [param subtitle] is a small dim line under the title (e.g. "Achievement unlocked").
func enqueue(title: String, icon: String = "★", subtitle: String = "Achievement Unlocked") -> void:
	_queue.append({ "title": title, "icon": icon, "subtitle": subtitle })
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var data: Dictionary = _queue.pop_front()
	_present(data)


func _present(data: Dictionary) -> void:
	var chip := PanelContainer.new()
	chip.custom_minimum_size = Vector2(CHIP_WIDTH, 0.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(PANEL.r, PANEL.g, PANEL.b, 0.96)
	sb.set_corner_radius_all(10)
	sb.set_border_width_all(2)
	sb.border_color = BORDER
	sb.set_content_margin_all(12)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 8
	chip.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)

	var badge := Label.new()
	badge.text = String(data.get("icon", "★"))
	badge.add_theme_font_size_override("font_size", 30)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var cap := Label.new()
	cap.text = String(data.get("subtitle", "Achievement Unlocked")).to_upper()
	cap.add_theme_font_size_override("font_size", 11)
	cap.add_theme_color_override("font_color", GOLD)
	col.add_child(cap)

	var name_label := Label.new()
	name_label.text = String(data.get("title", ""))
	name_label.add_theme_font_size_override("font_size", 18)
	name_label.add_theme_color_override("font_color", CREAM)
	col.add_child(name_label)

	_root.add_child(chip)

	# Anchor bottom-centre, then slide up from just below the edge.
	chip.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	await get_tree().process_frame  # let the chip compute its size
	var size: Vector2 = chip.size
	var target_x: float = -size.x * 0.5
	var rest_y: float = -size.y - 48.0
	var start_y: float = 40.0
	chip.position = Vector2(target_x, start_y)
	chip.modulate.a = 0.0

	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(chip, "position:y", rest_y, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(chip, "modulate:a", 1.0, SLIDE_TIME)
	tw.set_parallel(false)
	tw.tween_interval(HOLD_TIME)
	tw.tween_property(chip, "modulate:a", 0.0, SLIDE_TIME)
	tw.tween_callback(func() -> void:
		chip.queue_free()
		_show_next()
	)
