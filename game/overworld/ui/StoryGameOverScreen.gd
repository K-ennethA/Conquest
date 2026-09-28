class_name StoryGameOverScreen
extends CanvasLayer

## THE STORY GAME OVER card (docs/design/DECISIONS.md #29 refinements): a battle ended the
## journey -- the hero fell, a unit the mission said to protect fell, or (Classic) nobody is left.
## Grove look: the deep-navy veil, a gold-framed card with a red "GAME OVER" ribbon, the reason,
## and the two ways on: LOAD LAST SAVE (the pre-battle autosave -- nothing of the lost battle is
## kept) or RETURN TO TITLE. Keyboard / pad: the first button has focus, left / right moves,
## Confirm picks; Esc / B does nothing (there is no "back" from a game over).
##
## StoryController opens it for a duel (the tactical end screen offers the same two actions on
## its own card) and listens to [signal action_chosen].

const NODE_NAME := "StoryGameOverScreen"
## Above everything, the story dialogue (135) included: a game over is the last word.
const LAYER_INDEX: int = 140
const ACTION_LOAD_SAVE := "load_save"
const ACTION_TITLE := "title"

signal action_chosen(action_id: String)

var _message: String = ""
var _root: Control = null
var _message_label: Label = null
var _buttons: Array[Button] = []
var _chosen: bool = false


## Open the card under [param parent] with [param message] (why the journey ended).
static func open(parent: Node, message: String) -> StoryGameOverScreen:
	var s := StoryGameOverScreen.new()
	s.name = NODE_NAME
	s._message = message
	parent.add_child(s)
	return s


func _ready() -> void:
	layer = LAYER_INDEX
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.name = "GameOverRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = ConquestTheme.build()
	_root.add_to_group(InputActions.OVERLAY_GROUP)
	add_child(_root)

	var veil := ColorRect.new()
	veil.color = Color(MenuTheme.BG_DEEP, 0.86)
	veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(veil)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	var card := PanelContainer.new()
	card.name = "GameOverCard"
	card.custom_minimum_size = Vector2(560, 0)
	var sb := MenuTheme.card_box(MenuTheme.PANEL, MenuTheme.GOLD_DK)
	sb.crest = true
	sb.set_content_margin_all(28)
	sb.content_margin_top = 34
	card.add_theme_stylebox_override("panel", sb)
	ConquestTheme.keep_style(card)
	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", MenuTheme.SP_L)
	card.add_child(col)

	var ribbon := ConquestTheme.title_ribbon("GAME OVER", MenuTheme.TEAM_RED, MenuTheme.FS_HEADING)
	ribbon.name = "Title"
	ribbon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ribbon)

	var rule := GroveRule.new()
	rule.color = MenuTheme.GOLD
	rule.custom_minimum_size = Vector2(160, 10)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(rule)

	_message_label = MenuKit.label(_message, &"SubheadingLabel", true)
	_message_label.name = "Message"
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", MenuTheme.FS_BODY)
	_message_label.custom_minimum_size = Vector2(500, 0)
	col.add_child(_message_label)

	var hint := MenuKit.label("Load your last save to take up the journey from just before this battle.",
		&"DimLabel", true)
	hint.name = "Hint"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", MenuTheme.FS_SMALL)
	hint.custom_minimum_size = Vector2(500, 0)
	col.add_child(hint)

	var row := HBoxContainer.new()
	row.name = "Actions"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", MenuTheme.SP_L)
	col.add_child(row)
	var load_b := MenuKit.button("Load Last Save", MenuKit.PRIMARY, 220)
	load_b.name = "LoadSaveButton"
	load_b.pressed.connect(choose.bind(ACTION_LOAD_SAVE))
	row.add_child(load_b)
	var title_b := MenuKit.button("Return to Title", MenuKit.GHOST, 220)
	title_b.name = "TitleButton"
	title_b.pressed.connect(choose.bind(ACTION_TITLE))
	row.add_child(title_b)
	_buttons = [load_b, title_b]
	load_b.focus_neighbor_right = load_b.get_path_to(title_b)
	title_b.focus_neighbor_left = title_b.get_path_to(load_b)
	MenuNav.focus_deferred(load_b)


## Pick [param action_id] ("load_save" / "title"). Only the first pick counts.
func choose(action_id: String) -> void:
	if _chosen:
		return
	_chosen = true
	action_chosen.emit(action_id)


func buttons() -> Array[Button]:
	return _buttons


func message() -> String:
	return _message


func _unhandled_input(event: InputEvent) -> void:
	# Modal: nothing behind the card reacts (a game over has no "back").
	if _root != null and _root.visible and (event is InputEventKey or event is InputEventJoypadButton):
		if MenuNav.is_back_event(event):
			get_viewport().set_input_as_handled()


func _exit_tree() -> void:
	if _root != null:
		_root.remove_from_group(InputActions.OVERLAY_GROUP)
