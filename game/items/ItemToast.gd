extends CanvasLayer
class_name ItemToast

## A modest "item acquired" banner: a bottom-centre plate naming the item the player just
## won, its rarity, and what it does.
##
## Self-contained and disposable. It styles itself from the shared [MenuTheme] factories
## (a grove card whose edge is the item's rarity colour -- docs/UI_STYLE.md; no scene theme
## needed), mounts itself on its own CanvasLayer above the battle HUD, and frees itself when
## it is done -- so the only thing a caller ever needs is [method present]. Modelled on the
## profile's achievement banner, minus the queue: a battle pays out at most one drop, so
## there is nothing to queue.
##
## DEFENSIVE ABOUT THE THINGS THAT BREAK BANNERS:
##   * HEADLESS -- a test / CI run has no viewport, so [method present] returns before
##     building anything. A drop is still granted and saved; only the visual is skipped.
##   * ANIMATIONS OFF -- [GameSettings.animations_on] is honoured. With animations off the
##     plate simply appears, holds, and disappears: no slide, no fade. It is never skipped
##     entirely, because the banner is the ONLY feedback that a drop happened.
##   * PAUSE -- the end-of-battle screen pauses the tree, and a drop lands exactly then, so
##     the layer runs with PROCESS_MODE_ALWAYS or the banner would freeze mid-slide.

const HOLD_TIME: float = 3.0
const SLIDE_TIME: float = 0.35
const PLATE_WIDTH: float = 400.0
const OVERLAY_LAYER: int = 126

# Rarity accents from the grove palette: gold for common, info blue for rare, blight violet
# for epic.
const AMBER: Color = MenuTheme.GOLD
const RARE_BLUE: Color = MenuTheme.ACCENT
const EPIC_PURPLE: Color = MenuTheme.EL_DARK

var _root: Control = null


## Show a banner for [param item], mounted relative to [param host] (any node already in the
## tree). A null / detached host, or a headless run, is a silent no-op. This is the only
## entry point callers need.
static func present(item: ItemResource, host: Node) -> void:
	if item == null:
		return
	if DisplayServer.get_name() == "headless":
		return
	if host == null or not host.is_inside_tree():
		return
	var tree: SceneTree = host.get_tree()
	if tree == null or tree.root == null:
		return
	var toast := ItemToast.new()
	tree.root.add_child(toast)
	toast.show_item(item)


func _ready() -> void:
	layer = OVERLAY_LAYER
	# The end screen pauses the tree the same frame a drop lands; without this the banner
	# would freeze half-way through its slide and never free itself.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)


## Build and play the banner for [param item], then free this layer.
func show_item(item: ItemResource) -> void:
	if item == null:
		queue_free()
		return

	var accent: Color = _rarity_color(item.rarity)
	var plate := PanelContainer.new()
	plate.custom_minimum_size = Vector2(PLATE_WIDTH, 0.0)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var box := MenuTheme.accented_card(accent, SIDE_LEFT, MenuTheme.PANEL, 0.97)
	box.content_margin_left = 20.0
	box.content_margin_right = 18.0
	box.content_margin_top = 14.0
	box.content_margin_bottom = 12.0
	plate.add_theme_stylebox_override("panel", box)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", MenuTheme.SP_M)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.add_child(row)

	var badge := Label.new()
	badge.text = item.icon_hint if not item.icon_hint.strip_edges().is_empty() else "*"
	badge.add_theme_font_size_override("font_size", 30)
	badge.add_theme_color_override("font_color", accent.lightened(0.25))
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(badge)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)

	var caption := Label.new()
	caption.text = "%s ITEM FOUND" % item.rarity_name().to_upper()
	caption.add_theme_font_override("font", MenuTheme.heading_font(2))
	caption.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	caption.add_theme_color_override("font_color", accent.lightened(0.2))
	col.add_child(caption)

	var title := Label.new()
	title.text = item.display_name
	title.add_theme_font_override("font", MenuTheme.heading_font(1))
	title.add_theme_font_size_override("font_size", MenuTheme.FS_SUBHEADING)
	title.add_theme_color_override("font_color", MenuTheme.CREAM)
	col.add_child(title)

	var effect := Label.new()
	effect.text = item.effect_summary()
	effect.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	effect.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	effect.add_theme_color_override("font_color", MenuTheme.TEXT_DIM)
	col.add_child(effect)

	_root.add_child(plate)
	plate.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	await get_tree().process_frame  # let the plate compute its size before positioning
	# A drop toast is raised on a KILL, so a battle-ending kill can free the whole overlay
	# during the awaited frame; everything below touches `plate` and `self`.
	if not is_instance_valid(self) or not is_inside_tree() or not is_instance_valid(plate):
		return

	var plate_size: Vector2 = plate.size
	var rest_y: float = -plate_size.y - 48.0
	plate.position = Vector2(-plate_size.x * 0.5, rest_y)

	if not _animations_on():
		# Animations off: appear, hold, gone. Still shown -- this banner is the only feedback
		# that a drop happened at all.
		await get_tree().create_timer(HOLD_TIME, true, false, true).timeout
		# HOLD_TIME is seconds long -- easily long enough to span a scene change, which
		# would leave this resuming on a freed toast.
		if not is_instance_valid(self):
			return
		queue_free()
		return

	plate.position.y = 40.0
	plate.modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(plate, "position:y", rest_y, SLIDE_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(plate, "modulate:a", 1.0, SLIDE_TIME)
	tween.set_parallel(false)
	tween.tween_interval(HOLD_TIME)
	tween.tween_property(plate, "modulate:a", 0.0, SLIDE_TIME)
	tween.tween_callback(queue_free)


## Accent colour per rarity: gold for common, blue for rare, violet for epic.
func _rarity_color(rarity: int) -> Color:
	match rarity:
		ItemResource.Rarity.RARE:
			return RARE_BLUE
		ItemResource.Rarity.EPIC:
			return EPIC_PURPLE
		_:
			return AMBER


## True when the player has animations enabled (defaults to on when GameSettings is absent,
## e.g. a bare test harness).
func _animations_on() -> bool:
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		return true
	if not GameSettings.has_method("animations_on"):
		return true
	return bool(GameSettings.animations_on())
