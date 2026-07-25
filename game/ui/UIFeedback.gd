class_name UIFeedback
extends RefCounted

## Tiny UI-audio helper for the battle HUD. The command buttons were silent; this
## wires a themed button's `pressed` (and, optionally, `mouse_entered`) to the
## shared AudioManager UI click so pressing one gives feedback.
##
## Reuses the EXISTING &"sfx_ui_click" slot -- no new audio files -- and plays a
## few dB down so it sits under gameplay SFX rather than over them. play_sfx is a
## no-op when that slot is empty, so this is always safe to call.
##
## Static + idempotent: each button is flagged with meta the first time it is
## wired, so repeated theme/rebuild passes never stack duplicate connections.
## Panels that rebuild their buttons on the fly (e.g. UnitActionsPanel) can call
## [method attach_sfx] again after a rebuild to pick up the new buttons.

const CLICK_EVENT := &"sfx_ui_click"
## A few dB down so the HUD click sits under gameplay SFX rather than over them.
const CLICK_VOLUME_DB := -6.0
## Hover is quieter still -- a faint tick that is easy to ignore.
const HOVER_VOLUME_DB := -14.0

const _WIRED_META := "ui_sfx_wired"


## Connect every Button in [param root]'s subtree to the click SFX. When
## [param with_hover] is true, also ticks on mouse-enter. Pass [param skip] a
## node whose subtree should be left alone (e.g. a noisy, frequently-rebuilt
## TurnQueue). Buttons already wired are skipped, so this is cheap to re-run.
static func attach_sfx(root: Node, with_hover: bool = false, skip: Node = null) -> void:
	if root == null:
		return
	if skip != null and root == skip:
		return
	if root is Button:
		_wire_button(root as Button, with_hover)
	for child in root.get_children():
		attach_sfx(child, with_hover, skip)


static func _wire_button(button: Button, with_hover: bool) -> void:
	if bool(button.get_meta(_WIRED_META, false)):
		return
	button.set_meta(_WIRED_META, true)
	button.pressed.connect(UIFeedback._play_click)
	if with_hover:
		button.mouse_entered.connect(UIFeedback._play_hover)


static func _play_click() -> void:
	_play(CLICK_VOLUME_DB)


static func _play_hover() -> void:
	_play(HOVER_VOLUME_DB)


## Route through the AudioManager autoload if it is present. Looked up via the
## SceneTree (this is a RefCounted, not a Node) so the helper stays global.
static func _play(volume_db: float) -> void:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		var am := (loop as SceneTree).root.get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("play_sfx"):
			am.play_sfx(CLICK_EVENT, volume_db)
