class_name OverworldHUD
extends CanvasLayer

## The overworld's thin HUD (docs/design/OVERWORLD.md §4.10), all grove kit (docs/UI_STYLE.md):
##   * the LOCATION POPUP (top right) -- a small name chip that slides in on entering a new place;
##   * the INTERACTION PROMPT (bottom centre) -- "[Space] Talk" in the live binding's glyph,
##     shown while the hero faces something usable;
##   * TOASTS (top right) -- gold ribbons for quests, items and gold, stacked, self-dismissing;
##     quest transitions (started / new objective / complete) get a small card with a kicker;
##   * the QUEST TRACKER (top left) -- the tracked quest's title and current objective, plus where
##     it is ("Here" when the hero stands in the objective's area); hidden with nothing to track;
##   * a MENU hint (bottom right) and, on touch devices, "A" / "Menu" buttons.
## Presentation only: the controller tells it what to show.

const LAYER_INDEX: int = 20
const POPUP_HOLD: float = 2.0
const POPUP_TOP: float = 22.0
const POPUP_MARGIN: float = 22.0
const POPUP_MIN_WIDTH: float = 150.0
const TOAST_HOLD: float = 2.6
const QUEST_TOAST_HOLD: float = 3.4
const TRACKER_WIDTH: float = 280.0

signal touch_confirm_pressed
signal touch_menu_pressed

var _root: Control = null
var _ribbon: PanelContainer = null
var _prompt: PanelContainer = null
var _prompt_row: HBoxContainer = null
var _toasts: VBoxContainer = null
var _menu_hint: HBoxContainer = null
var _tracker: PanelContainer = null
var _tracker_kind: Label = null
var _tracker_title: Label = null
var _tracker_objective: Label = null
var _tracker_place: Label = null
var _tracked_id: String = ""


func _ready() -> void:
	layer = LAYER_INDEX
	_root = Control.new()
	_root.name = "HUDRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = ConquestTheme.build()
	add_child(_root)
	_build_prompt()
	_build_tracker()
	_build_toasts()
	_build_menu_hint()
	if _is_touch():
		_build_touch_buttons()


func _is_touch() -> bool:
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile")


# --- Location popup -----------------------------------------------------------------

## The classic-Pokemon LOCATION POPUP: a small name chip that slides in at the top-right corner,
## holds for [constant POPUP_HOLD] and slides out again. Pure presentation -- it never takes input
## and never pauses the hero (mouse_filter IGNORE; no script, no overlay). WHEN to show it is
## [PlaceAnnouncer]'s rule.
func show_area_name(text: String) -> void:
	if _ribbon != null and is_instance_valid(_ribbon):
		_ribbon.queue_free()
	_ribbon = ConquestTheme.title_ribbon(text.to_upper(), MenuTheme.GOLD_DK, MenuTheme.FS_BODY)
	_ribbon.name = "AreaPopup"
	_ribbon.anchor_left = 1.0
	_ribbon.anchor_right = 1.0
	_ribbon.offset_top = POPUP_TOP
	_root.add_child(_ribbon)
	var w: float = maxf(_ribbon.get_combined_minimum_size().x, POPUP_MIN_WIDTH)
	var shown_right: float = -POPUP_MARGIN
	_ribbon.offset_left = shown_right - w
	_ribbon.offset_right = shown_right
	if not _anims_on():
		# No slide: it simply stays for its hold, then goes.
		get_tree().create_timer(POPUP_HOLD).timeout.connect(_ribbon.queue_free)
		return
	var slide: float = w + POPUP_MARGIN + 8.0
	_ribbon.offset_left += slide
	_ribbon.offset_right += slide
	var tw := _ribbon.create_tween()
	tw.tween_method(_set_popup_slide.bind(_ribbon, w, shown_right), slide, 0.0, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(POPUP_HOLD)
	tw.tween_method(_set_popup_slide.bind(_ribbon, w, shown_right), 0.0, slide, 0.3) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_callback(_ribbon.queue_free)


## One frame of the popup's slide: [param slide] is the pixels still to travel off-screen.
func _set_popup_slide(slide: float, chip: Control, w: float, shown_right: float) -> void:
	if chip == null or not is_instance_valid(chip):
		return
	chip.offset_left = shown_right - w + slide
	chip.offset_right = shown_right + slide


## The location popup while it is showing, else null.
func area_popup() -> PanelContainer:
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


## A QUEST TRANSITION toast ([QuestTracker] event): a small card with a gold kicker ("NEW QUEST",
## "NEW OBJECTIVE", "QUEST COMPLETE"), the quest's title and, for a new objective, its line.
func quest_toast(event: Dictionary) -> void:
	var kind: String = String(event.get("kind", ""))
	var main: bool = String(event.get("category", "")) == QuestLog.MAIN
	var accent: Color = MenuTheme.GOLD if main else MenuTheme.SUCCESS
	var kicker: String = "NEW QUEST"
	match kind:
		QuestTracker.ADVANCED:
			kicker = "NEW OBJECTIVE"
		QuestTracker.COMPLETED:
			kicker = "QUEST COMPLETE"
			accent = MenuTheme.GOLD_LITE
	var card := PanelContainer.new()
	card.name = "QuestToast"
	card.set_meta(&"quest_event", kind)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	card.custom_minimum_size = Vector2(TRACKER_WIDTH, 0)
	var sb := MenuTheme.accented_card(accent, SIDE_LEFT, MenuTheme.PANEL, 0.95)
	card.add_theme_stylebox_override("panel", sb)
	ConquestTheme.keep_style(card)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(col)
	var k := MenuKit.label(kicker, &"SectionLabel")
	k.add_theme_color_override("font_color", accent)
	k.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(k)
	var t := MenuKit.label(String(event.get("title", "")), &"SubheadingLabel", true)
	t.name = "QuestToastTitle"
	t.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	t.custom_minimum_size = Vector2(TRACKER_WIDTH - 44, 0)
	col.add_child(t)
	var obj: String = String(event.get("objective", ""))
	if kind != QuestTracker.COMPLETED and not obj.is_empty():
		var o := MenuKit.label(obj, &"DimLabel", true)
		o.custom_minimum_size = Vector2(TRACKER_WIDTH - 44, 0)
		o.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
		col.add_child(o)
	_toasts.add_child(card)
	if not _anims_on():
		card.set_meta(&"toast", true)
		get_tree().create_timer(QUEST_TOAST_HOLD).timeout.connect(card.queue_free)
		return
	card.modulate.a = 0.0
	var tw := card.create_tween()
	tw.tween_property(card, "modulate:a", 1.0, 0.25)
	tw.tween_interval(QUEST_TOAST_HOLD)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)


# --- Quest tracker ----------------------------------------------------------------------

func _build_tracker() -> void:
	_tracker = PanelContainer.new()
	_tracker.name = "QuestTracker"
	_tracker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker.offset_left = 22
	_tracker.offset_top = 22
	_tracker.custom_minimum_size = Vector2(TRACKER_WIDTH, 0)
	_tracker.visible = false
	_root.add_child(_tracker)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tracker.add_child(col)
	_tracker_kind = MenuKit.label("", &"SectionLabel")
	_tracker_kind.name = "TrackerKind"
	_tracker_kind.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(_tracker_kind)
	_tracker_title = MenuKit.label("", &"SubheadingLabel", true)
	_tracker_title.name = "TrackerTitle"
	_tracker_title.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	# A fixed wrap width: an autowrapped label measured at width 0 asks for one line per word.
	_tracker_title.custom_minimum_size = Vector2(TRACKER_WIDTH - 44, 0)
	col.add_child(_tracker_title)
	_tracker_objective = MenuKit.label("", &"", true)
	_tracker_objective.custom_minimum_size = Vector2(TRACKER_WIDTH - 44, 0)
	_tracker_objective.name = "TrackerObjective"
	_tracker_objective.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(_tracker_objective)
	_tracker_place = MenuKit.label("", &"DimLabel")
	_tracker_place.name = "TrackerPlace"
	_tracker_place.add_theme_font_size_override("font_size", MenuTheme.FS_CAPTION)
	col.add_child(_tracker_place)


## Show [param entry] (a [QuestLog] entry; {} hides the tracker). [param place] names where the
## objective is ("" = say nothing); [param here] = the hero is already in its area.
func set_tracked_quest(entry: Dictionary, place: String = "", here: bool = false) -> void:
	if entry.is_empty() or String(entry.get("objective", "")).is_empty():
		_tracker.visible = false
		_tracked_id = ""
		return
	var main: bool = String(entry.get("category", "")) == QuestLog.MAIN
	var accent: Color = MenuTheme.GOLD if main else MenuTheme.SUCCESS
	_tracker.add_theme_stylebox_override("panel", MenuTheme.accented_card(accent, SIDE_LEFT, MenuTheme.PANEL, 0.86))
	ConquestTheme.keep_style(_tracker)
	_tracked_id = String(entry.get("id", ""))
	_tracker_kind.text = "MAIN QUEST" if main else "SIDE QUEST"
	_tracker_kind.add_theme_color_override("font_color", accent)
	_tracker_title.text = String(entry.get("title", ""))
	_tracker_objective.text = "◆ " + String(entry.get("objective", ""))
	_tracker_place.text = "Here" if here else ("→ " + place if not place.is_empty() else "")
	_tracker_place.visible = not _tracker_place.text.is_empty()
	_tracker.visible = true
	_tracker.size = Vector2.ZERO
	_tracker.reset_size.call_deferred()


func tracker_visible() -> bool:
	return _tracker.visible


func tracked_quest_id() -> String:
	return _tracked_id


func tracker_title() -> String:
	return _tracker_title.text


func tracker_objective() -> String:
	return _tracker_objective.text.trim_prefix("◆ ")


func tracker_place() -> String:
	return _tracker_place.text


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
