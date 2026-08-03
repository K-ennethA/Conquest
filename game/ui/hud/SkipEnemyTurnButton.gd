extends CanvasLayer

class_name SkipEnemyTurnButton

## The battle HUD's FAST-FORWARD ENEMY TURN control -- one button, plus the [constant HOTKEY].
##
## The player's complaint it answers: "there should be a way to skip the enemy turn and jump to
## mine -- they still do everything, we just don't show it per se." So this is emphatically NOT
## a skip. Pressing it arms [TurnFastForward], which shortens [BotTurnDriver]'s presentation
## beats and stands the camera down; the AI still plans and issues every command through the
## ordinary path, so the battle log, the replay, statuses and objectives all record exactly what
## they would have at full speed. The player can read the whole turn back in the battle log
## afterwards -- that is the deal this button makes.
##
## VISIBLE ONLY WHEN IT MEANS SOMETHING. The button is on screen during an ENEMY (AI) turn and
## nowhere else: there is nothing to fast-forward through on the player's own turn, and offering
## it there would just be a mystery button. It also stays hidden whenever
## [method TurnFastForward.can_arm] refuses -- a networked match (both peers share one clock, so
## shortening your own pacing is a real-time advantage) or a replay, which has its own transport
## bar with its own speed control ([ReplayHUD]).
##
## AUTO-DISARM. [method TurnFastForward.note_turn_started] drops the latch the instant a non-AI
## player is up, so fast-forward never bleeds into the player's own turn. This node rides the
## ACTIVE turn system's `turn_started` / `turn_ended` to do it -- never
## PlayerManager.player_turn_started, which does not fire on AI turns and would leave the latch
## armed for exactly the case it exists for (project convention; see CONQUEST.md rule 2).
##
## Mounted by [UILayoutManager] on its own CanvasLayer, exactly as [NetToast] and [ReplayHUD]
## are: coordinate-free, self-building, self-wiring, self-hiding. Styling is [ConquestTheme]
## (warm amber plate + cream text) so it reads as part of the same HUD. Null-safe headless (no
## GameSettings, no TurnSystemManager) -- every hook is guarded, so a test can mount it bare.

## Emitted whenever the latch flips, carrying its new state. Tests assert on this rather than
## scraping the button's label.
signal fast_forward_changed(active: bool)

## Group so anything that needs the live control can resolve it without a node path.
const GROUP := &"skip_enemy_turn_button"

## The latch this control drives (see [TurnFastForward]). Preloaded by PATH rather than
## referenced by its global class_name, exactly as [GameWorldManager] preloads its juice layers:
## a global class only resolves once the editor/engine has rescanned, and a fresh checkout would
## otherwise fail to compile this script. Every function on it is static, so this const IS the
## whole API.
const FAST_FORWARD = preload("res://game/ai/TurnFastForward.gd")

## Between the action banner (120) and the network toast (122): it is a persistent control, so
## it must sit above the banner it would otherwise hide behind, but below every notice and both
## cinematic layers (ultimate cut-in 124, turn wipe 128).
const OVERLAY_LAYER: int = 121

## The keyboard shortcut. A bare keycode rather than an InputMap action deliberately: the
## project has no action for this, and adding one would mean a project.godot edit for a single
## optional convenience key. F is free -- see [method _unhandled_key_input] for the guards that
## keep it from firing while the player is typing.
const HOTKEY: Key = KEY_F

## Clear of the top bar (pause + gear live there), hugging the right edge.
const TOP_OFFSET: float = 76.0
const RIGHT_MARGIN: float = 18.0
## The project's touch-target floor -- this has to be pressable on a phone too.
const MIN_SIZE: Vector2 = Vector2(216, 44)

const LABEL_IDLE := "▶▶  SKIP ENEMY TURN  (F)"
const LABEL_ACTIVE := "▶▶  FAST-FORWARDING…  (F)"
const TOOLTIP := ("Fast-forward the enemy turn (F). The AI still takes every action -- "
	+ "it is just not drawn out. Read it back in the battle log.")

## Slightly translucent plate, like [NetToast]: the control floats over the board.
const PLATE_BG: Color = Color(0.173, 0.129, 0.078, 0.92)

var _root: Control = null
var _button: Button = null

## The turn system whose signals are currently hooked. Re-wired whenever the manager activates
## a different one (Traditional <-> Speed First), so this never listens to a dead system.
var _watched_ts = null
var _turn_system_manager: Node = null


func _ready() -> void:
	layer = OVERLAY_LAYER
	add_to_group(GROUP)
	_build_ui()
	_wire_turn_system()
	_refresh()


func _exit_tree() -> void:
	# TurnSystemManager and the turn systems outlive this battle HUD, so drop the hooks rather
	# than leaving them holding a reference to a node that is going away.
	_unhook_turn_system()
	if _turn_system_manager != null and is_instance_valid(_turn_system_manager) \
			and _turn_system_manager.has_signal("turn_system_activated") \
			and _turn_system_manager.turn_system_activated.is_connected(_on_turn_system_activated):
		_turn_system_manager.turn_system_activated.disconnect(_on_turn_system_activated)
	# The latch is process-wide static state and the battle it belonged to is over: leaving it
	# armed would fast-forward the FIRST enemy turn of the next battle without being asked.
	FAST_FORWARD.disarm()


# --- UI construction ----------------------------------------------------------

func _build_ui() -> void:
	_root = Control.new()
	_root.name = "SkipRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Only the button itself takes clicks; everywhere else the board and camera keep theirs.
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_button = Button.new()
	_button.name = "SkipEnemyTurn"
	_button.text = LABEL_IDLE
	_button.tooltip_text = TOOLTIP
	_button.custom_minimum_size = MIN_SIZE
	_button.mouse_filter = Control.MOUSE_FILTER_STOP
	# Top-right, hugging its own text, below the top bar.
	_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_button.offset_top = TOP_OFFSET
	_button.offset_right = -RIGHT_MARGIN
	_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_button.grow_vertical = Control.GROW_DIRECTION_END
	_button.add_theme_font_size_override("font_size", 18)
	_button.add_theme_color_override("font_color", ConquestTheme.CREAM)
	_button.add_theme_color_override("font_hover_color", ConquestTheme.AMBER_LITE)
	_button.add_theme_stylebox_override("normal", _plate_box(ConquestTheme.AMBER))
	_button.add_theme_stylebox_override("hover", _plate_box(ConquestTheme.AMBER_LITE))
	_button.add_theme_stylebox_override("pressed", _plate_box(ConquestTheme.AMBER_DK))
	_button.pressed.connect(_on_pressed)
	_root.add_child(_button)


func _plate_box(border: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PLATE_BG
	box.set_corner_radius_all(8)
	box.set_content_margin_all(8)
	box.content_margin_left = 16.0
	box.content_margin_right = 16.0
	box.border_width_left = 2
	box.border_width_top = 2
	box.border_width_right = 2
	box.border_width_bottom = 2
	box.border_color = border
	box.shadow_color = Color(0.0, 0.0, 0.0, 0.5)
	box.shadow_size = 6
	return box


# --- Turn wiring --------------------------------------------------------------

## Subscribe to the ACTIVE turn system (via the manager, so a mid-battle system switch is
## followed). Looked up by node path rather than by the bare autoload identifier so this control
## can be mounted in a stripped test scene with no TurnSystemManager at all.
func _wire_turn_system() -> void:
	_turn_system_manager = get_node_or_null("/root/TurnSystemManager")
	if _turn_system_manager == null:
		return
	if _turn_system_manager.has_signal("turn_system_activated") \
			and not _turn_system_manager.turn_system_activated.is_connected(_on_turn_system_activated):
		_turn_system_manager.turn_system_activated.connect(_on_turn_system_activated)
	if _turn_system_manager.has_method("has_active_turn_system") \
			and _turn_system_manager.has_active_turn_system():
		_on_turn_system_activated(_turn_system_manager.get_active_turn_system())


func _on_turn_system_activated(ts) -> void:
	if _watched_ts == ts:
		return
	_unhook_turn_system()
	_watched_ts = ts
	if ts == null or not is_instance_valid(ts):
		return
	if ts.has_signal("turn_started") and not ts.turn_started.is_connected(_on_turn_started):
		ts.turn_started.connect(_on_turn_started)
	if ts.has_signal("turn_ended") and not ts.turn_ended.is_connected(_on_turn_ended):
		ts.turn_ended.connect(_on_turn_ended)
	_refresh()


func _unhook_turn_system() -> void:
	if _watched_ts == null or not is_instance_valid(_watched_ts):
		_watched_ts = null
		return
	if _watched_ts.has_signal("turn_started") and _watched_ts.turn_started.is_connected(_on_turn_started):
		_watched_ts.turn_started.disconnect(_on_turn_started)
	if _watched_ts.has_signal("turn_ended") and _watched_ts.turn_ended.is_connected(_on_turn_ended):
		_watched_ts.turn_ended.disconnect(_on_turn_ended)
	_watched_ts = null


## A turn began. AUTO-DISARM first (the latch is scoped to the enemy turn it was armed on), then
## redraw -- which is what makes the button appear for an AI turn and vanish for the player's.
func _on_turn_started(player) -> void:
	FAST_FORWARD.note_turn_started(player)
	_refresh()


## A turn ended. The next one has not begun yet, so nothing may be fast-forwarded until it does;
## disarming here means the latch can never span the gap between two enemy turns unattended.
func _on_turn_ended(_player = null) -> void:
	FAST_FORWARD.disarm()
	_refresh()


# --- Input --------------------------------------------------------------------

## The [constant HOTKEY] shortcut. `_unhandled_key_input` (not `_input`) so any focused UI --
## the pause menu, a text field, the settings panel -- consumes the key first and this never
## fires underneath an open menu. Additionally gated on the button actually being offered, so F
## does nothing on the player's own turn or in a networked match.
func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != HOTKEY:
		return
	if not is_offered():
		return
	get_viewport().set_input_as_handled()
	_toggle()


func _on_pressed() -> void:
	_toggle()


## Flip the latch and redraw. Routed through [method TurnFastForward.toggle], which refuses to arm in
## a networked match / a replay by returning false -- so a refusal is a value here, never an
## engine error, and the label simply stays on IDLE.
func _toggle() -> void:
	var active: bool = FAST_FORWARD.toggle()
	_refresh()
	fast_forward_changed.emit(active)


# --- State --------------------------------------------------------------------

## True when the button should be on screen: an AI player is up in the live turn system, and
## fast-forward is permitted in this session at all. Null-safe end to end -- no turn system
## means no enemy turn, which means nothing to offer.
func is_offered() -> bool:
	if not FAST_FORWARD.can_arm():
		return false
	return FAST_FORWARD.is_ai_player(_current_player())


## True while the fast-forward is running. The readable state, for tests.
func is_fast_forwarding() -> bool:
	return FAST_FORWARD.is_armed()


## The button's visible label ("" while it is hidden) -- the readable state, for tests.
func button_text() -> String:
	if _button == null or not _button.visible:
		return ""
	return _button.text


func _current_player():
	var ts = _watched_ts
	if ts == null or not is_instance_valid(ts):
		if _turn_system_manager != null and is_instance_valid(_turn_system_manager) \
				and _turn_system_manager.has_method("has_active_turn_system") \
				and _turn_system_manager.has_active_turn_system():
			ts = _turn_system_manager.get_active_turn_system()
	if ts == null or not is_instance_valid(ts) or not ts.has_method("get_current_active_player"):
		return null
	return ts.get_current_active_player()


## Redraw visibility + label from the live state. Cheap and idempotent, so every seam that can
## change the state simply calls it.
func _refresh() -> void:
	if _button == null:
		return
	_button.visible = is_offered()
	_button.text = LABEL_ACTIVE if FAST_FORWARD.is_armed() else LABEL_IDLE
