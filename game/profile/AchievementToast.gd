extends CanvasLayer

## A self-contained "achievement unlocked" banner, owned and mounted by [PlayerProfile] on
## its own CanvasLayer so it appears in EVERY scene (menus and battle alike) without any
## scene needing to know about it. Banners are a bottom-centre grove card (gold edge +
## crest -- an unlock is a hero moment, see docs/UI_STYLE.md) that slides up, holds ~2.5s,
## then fades; multiple unlocks QUEUE so a burst (e.g. a retroactive load that unlocks
## several at once) plays one after another rather than stacking on top of itself.
##
## Purely presentational and defensive: it styles itself from the shared [MenuTheme]
## factories (no scene theme needed -- the layer sits outside every screen's theme), and is
## only ever mounted when there is a real viewport, so a headless test run never builds it.

const HOLD_TIME := 2.5
const SLIDE_TIME := 0.35
const CHIP_WIDTH := 380.0

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

	var sb := MenuTheme.accented_card(MenuTheme.GOLD, SIDE_LEFT, MenuTheme.PANEL, 0.97, true)
	sb.border_color = MenuTheme.GOLD_DK
	sb.content_margin_left = 20.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 16.0
	sb.content_margin_bottom = 12.0
	chip.add_theme_stylebox_override("panel", sb)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)

	var badge := Label.new()
	badge.text = String(data.get("icon", "★"))
	badge.add_theme_font_size_override("font_size", 30)
	badge.add_theme_color_override("font_color", MenuTheme.GOLD_LITE)
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	# Gold small caps over a Cinzel name: the grove's "SectionLabel over heading" pairing.
	var cap := Label.new()
	cap.text = String(data.get("subtitle", "Achievement Unlocked")).to_upper()
	cap.add_theme_font_override("font", MenuTheme.heading_font(2))
	cap.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	cap.add_theme_color_override("font_color", MenuTheme.GOLD)
	col.add_child(cap)

	var name_label := Label.new()
	name_label.text = String(data.get("title", ""))
	name_label.add_theme_font_override("font", MenuTheme.heading_font(1))
	name_label.add_theme_font_size_override("font_size", MenuTheme.FS_SUBHEADING)
	name_label.add_theme_color_override("font_color", MenuTheme.CREAM)
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
