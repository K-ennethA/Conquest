class_name OverworldHUD
extends CanvasLayer

## The overworld's thin HUD (docs/design/OVERWORLD.md §4.10), all grove kit (docs/UI_STYLE.md):
##   * the AREA RIBBON (top centre) -- a swallow-tailed title ribbon that fades in on arrival;
##   * the INTERACTION PROMPT (bottom centre) -- "[Space] Talk" in the live binding's glyph,
##     shown while the hero faces something usable;
##   * TOASTS (top right) -- gold ribbons for quests, items and gold, stacked, self-dismissing;
##   * a MENU hint (bottom right) and, on touch devices, "A" / "Menu" buttons.
## Presentation only: the controller tells it what to show.

const LAYER_INDEX: int = 20
const RIBBON_HOLD: float = 2.4
const TOAST_HOLD: float = 2.6

signal touch_confirm_pressed
signal touch_menu_pressed

var _root: Control = null
var _ribbon: PanelContainer = null
var _prompt: PanelContainer = null
var _prompt_row: HBoxContainer = null
var _toasts: VBoxContainer = null
var _menu_hint: HBoxContainer = null


func _ready() -> void:
	layer = LAYER_INDEX
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = ConquestTheme.build()
	add_child(_root)
	_build_prompt()
	_build_toasts()
	_build_menu_hint()
	if _is_touch():
		_build_touch_buttons()


func _is_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


# --- Area ribbon ------------------------------------------------------------------

func show_area_name(text: String) -> void:
	if _ribbon != null and is_instance_valid(_ribbon):
		_ribbon.queue_free()
	_ribbon = ConquestTheme.title_ribbon(text.to_upper(), MenuTheme.GOLD_DK, MenuTheme.FS_HEADING)
	_ribbon.name = "AreaRibbon"
	_ribbon.custom_minimum_size = Vector2(320, 0)
	_ribbon.anchor_left = 0.5
	_ribbon.anchor_right = 0.5
	_ribbon.offset_top = 22
	_ribbon.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.add_child(_ribbon)
	_ribbon.offset_left = -160
	_ribbon.offset_right = 160
	if not _anims_on():
		return
	_ribbon.modulate.a = 0.0
	var tw := _ribbon.create_tween()
	tw.tween_property(_ribbon, "modulate:a", 1.0, 0.35)
	tw.tween_interval(RIBBON_HOLD)
	tw.tween_property(_ribbon, "modulate:a", 0.0, 0.6)


func area_ribbon() -> PanelContainer:
	return _ribbon if _ribbon != null and is_instance_valid(_ribbon) else null


# --- Interaction prompt ------------------------------------------------------------

func _build_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.name = "InteractPrompt"
	_prompt.add_theme_stylebox_override("panel", ConquestTheme.chip_box(MenuTheme.GOLD_DK, 0.94))
	ConquestTheme.keep_style(_prompt)
	_prompt.anchor_left = 0.5
	_prompt.anchor_right = 0.5
	_prompt.anchor_top = 1.0
	_prompt.anchor_bottom = 1.0
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_prompt.offset_bottom = -34
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.visible = false
	_root.add_child(_prompt)
	_prompt_row = HBoxContainer.new()
	_prompt_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_prompt.add_child(_prompt_row)


## Show "[key] <verb>" (the live CONFIRM binding) or hide with an empty verb.
func set_prompt(verb: String) -> void:
	if verb.is_empty():
		_prompt.visible = false
		return
	for c in _prompt_row.get_children():
		_prompt_row.remove_child(c)
		c.queue_free()
	var key: String = ConquestTheme.action_glyph(InputActions.CONFIRM)
	if key.is_empty():
		key = "Space"
	_prompt_row.add_child(ConquestTheme.key_hint(key, verb))
	_prompt.visible = true
	# Re-centre on the new width.
	_prompt.reset_size()
	var w: float = _prompt.get_combined_minimum_size().x
	_prompt.offset_left = -w * 0.5
	_prompt.offset_right = w * 0.5


func prompt_visible() -> bool:
	return _prompt.visible


func prompt_text() -> String:
	var out: String = ""
	for l in _prompt_row.find_children("*", "Label", true, false):
		out += (l as Label).text + " "
	return out.strip_edges()


# --- Toasts --------------------------------------------------------------------------

func _build_toasts() -> void:
	_toasts = VBoxContainer.new()
	_toasts.name = "Toasts"
	_toasts.anchor_left = 1.0
	_toasts.anchor_right = 1.0
	_toasts.offset_left = -380
	_toasts.offset_right = -22
	_toasts.offset_top = 88
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 8)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_toasts)


## A gold ribbon toast. [param kind]: "quest" (gold edge + kicker), "item", "gold", "info".
func toast(text: String, kind: String = "info") -> void:
	var accent: Color = MenuTheme.GOLD if kind == "quest" else MenuTheme.GOLD_DK
	if kind == "item":
		accent = MenuTheme.EL_NATURE
	var r := ConquestTheme.title_ribbon(text, accent, MenuTheme.FS_BODY)
	r.name = "Toast"
	r.size_flags_horizontal = Control.SIZE_SHRINK_END
	_toasts.add_child(r)
	if not _anims_on():
		r.set_meta(&"toast", true)
		# A bound method (not a lambda capturing r): the connection dies with the ribbon.
		get_tree().create_timer(TOAST_HOLD).timeout.connect(r.queue_free)
		return
	r.modulate.a = 0.0
	var tw := r.create_tween()
	tw.tween_property(r, "modulate:a", 1.0, 0.25)
	tw.tween_interval(TOAST_HOLD)
	tw.tween_property(r, "modulate:a", 0.0, 0.5)
	tw.tween_callback(r.queue_free)


func toast_count() -> int:
	return _toasts.get_child_count()


# --- Menu hint / touch ------------------------------------------------------------------

func _build_menu_hint() -> void:
	_menu_hint = HBoxContainer.new()
	_menu_hint.name = "MenuHint"
	_menu_hint.anchor_left = 1.0
	_menu_hint.anchor_right = 1.0
	_menu_hint.anchor_top = 1.0
	_menu_hint.anchor_bottom = 1.0
	_menu_hint.offset_left = -260
	_menu_hint.offset_right = -22
	_menu_hint.offset_top = -52
	_menu_hint.offset_bottom = -22
	_menu_hint.alignment = BoxContainer.ALIGNMENT_END
	_menu_hint.add_theme_constant_override("separation", 14)
	_menu_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var menu_key: String = ConquestTheme.action_glyph(InputActions.MAP_MENU)
	_menu_hint.add_child(ConquestTheme.key_hint(menu_key if not menu_key.is_empty() else "Esc", "Journey"))
	var run_key: String = ConquestTheme.action_glyph(InputActions.FAST_FORWARD)
	_menu_hint.add_child(ConquestTheme.key_hint(run_key if not run_key.is_empty() else "Shift", "Run"))
	_root.add_child(_menu_hint)


func _build_touch_buttons() -> void:
	var box := HBoxContainer.new()
	box.name = "TouchButtons"
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -250
	box.offset_right = -22
	box.offset_top = -150
	box.offset_bottom = -64
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 14)
	_root.add_child(box)
	var menu := Button.new()
	menu.text = "Menu"
	menu.custom_minimum_size = Vector2(96, 64)
	menu.pressed.connect(func() -> void: touch_menu_pressed.emit())
	box.add_child(menu)
	var a := Button.new()
	a.text = "A"
	a.theme_type_variation = &"PrimaryButton"
	a.custom_minimum_size = Vector2(80, 80)
	a.pressed.connect(func() -> void: touch_confirm_pressed.emit())
	box.add_child(a)


func _anims_on() -> bool:
	var gs := get_node_or_null("/root/GameSettings")
	if gs == null or not gs.has_method("animations_on"):
		return true
	return bool(gs.animations_on())
