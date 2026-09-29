extends CanvasLayer
class_name NetMatchBar

## The ONLINE match corner for screens without the battle HUD (the online duel stage): the
## host's TURN CLOCK ([TurnTimer] in network mode -- both seats see the countdown, "YOUR TURN"
## / "OPPONENT", urgent under 5s) and a always-visible FORFEIT button. The button opens the
## screen's [PauseMenu] straight onto its forfeit confirm ([method PauseMenu.request_forfeit]),
## so the semantics are exactly the pause menu's FORFEIT MATCH ([method
## NetSessionNode.forfeit_match], a loss); without a pause menu it asks with its own confirm.
##
## Self-contained and self-styled (grove chip + HUD command button), built in code. Tests
## inject [member session] / [member pause_menu] before adding it.

## Emitted when the player confirmed the forfeit here (no pause menu to hand it to).
signal forfeit_confirmed()

const LAYER := 60
const LABEL_FORFEIT := "Forfeit"

## The network session (default: the NetSession autoload).
var session: Node = null
## The screen's pause menu (its forfeit confirm is reused), or null.
var pause_menu: Node = null

var timer: TurnTimer = null
var forfeit_button: Button = null
var _confirm: ConfirmationDialog = null


func _ready() -> void:
	layer = LAYER
	if session == null:
		session = get_node_or_null("/root/NetSession")
	var root := Control.new()
	root.name = "NetMatchBarRoot"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.theme = ConquestTheme.build()
	add_child(root)

	var box := VBoxContainer.new()
	box.name = "Corner"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.offset_left = -176
	box.offset_right = -16
	box.offset_top = 16
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.add_theme_constant_override("separation", 8)
	root.add_child(box)

	timer = TurnTimer.new()
	timer.name = "TurnTimer"
	timer.session = session
	timer.size_flags_horizontal = Control.SIZE_SHRINK_END
	box.add_child(timer)

	forfeit_button = Button.new()
	forfeit_button.name = "ForfeitButton"
	forfeit_button.text = LABEL_FORFEIT
	forfeit_button.tooltip_text = "Concede this online match (a loss)."
	forfeit_button.theme_type_variation = &"HudCommand"
	forfeit_button.custom_minimum_size = Vector2(140, 44)
	forfeit_button.size_flags_horizontal = Control.SIZE_SHRINK_END
	forfeit_button.focus_mode = Control.FOCUS_NONE
	forfeit_button.pressed.connect(request_forfeit)
	box.add_child(forfeit_button)


## The Forfeit button: the pause menu's forfeit confirm, or our own.
func request_forfeit() -> void:
	if pause_menu != null and is_instance_valid(pause_menu) and pause_menu.has_method("request_forfeit"):
		pause_menu.request_forfeit()
		return
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.name = "ForfeitConfirm"
		_confirm.title = "Forfeit Match?"
		_confirm.dialog_text = "You will lose this match."
		_confirm.ok_button_text = LABEL_FORFEIT
		_confirm.confirmed.connect(_on_confirmed)
		add_child(_confirm)
	_confirm.popup_centered()


func _on_confirmed() -> void:
	if session != null and session.has_method("forfeit_match"):
		session.forfeit_match()
	forfeit_confirmed.emit()
