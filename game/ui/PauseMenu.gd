extends CanvasLayer

class_name PauseMenu

## The in-battle PAUSE menu -- the one surface that answers "how do I get out of this
## battle?".
##
## Register: the sleeker DARK "Pokemon Legends" menu look ([MenuTheme]), deliberately
## NOT the amber battle-HUD cascade -- pausing steps OUT of the battle frame, so it
## should read like a menu rather than another HUD panel.
##
## Layering: its own CanvasLayer at [constant OVERLAY_LAYER] (above the turn wipe at
## 128 and the ultimate cut-in at 124), so nothing in the battle can draw over it.
##
## Pausing: opening sets [code]get_tree().paused = true[/code]. This node is
## PROCESS_MODE_ALWAYS, so it (and the Settings overlay it owns) keeps running while
## everything else is frozen -- same trick [GameOverScreen] uses. Battle SFX/music are
## deliberately left running: [AudioManager] is a PAUSABLE autoload, so opening the
## menu temporarily promotes it to ALWAYS and restores its previous mode on close.
##
## CONTEXT is everything. The row list is not fixed -- a live networked match must not
## offer a save or a quiet bail-out (leaving IS a loss), an Arena run has no save either
## (abandoning ends the run), and a solo battle gets both a save and a no-save fallback.
## That decision is a PURE function, [method rows_for_context], so the whole matrix is
## testable without a scene tree; [method _context] is the only place that reads live
## autoloads.
##
## SAVING is a CONTRACT, not a dependency. The battle save manager is discovered at
## open time (autoload node named "BattleSaveManager", or a node in the
## "battle_save_manager" group) and called through has_method() probes:
##   * can_save_now() -> bool
##   * save_and_quit() -> bool   (it saves the battle AND routes to the menu itself)
## When it is absent the Save row is shown DISABLED with a reason, and the plain
## "Quit to Menu" fallback still works -- the menu never hard-depends on it.

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

## Above TurnTransition (128) / UltimateCutIn (124) / ActionAnnouncer (120).
const OVERLAY_LAYER: int = 140

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

## Autoload node name AND (lower-cased) group name the save contract may be published under.
const SAVE_MANAGER_NODE := "BattleSaveManager"
const SAVE_MANAGER_GROUP := "battle_save_manager"

## The contextual rows. Order of the enum is not the display order -- see [method rows_for_context].
enum Row {
	RESUME,
	SETTINGS,
	SAVE_AND_QUIT,
	ABANDON_RUN,
	FORFEIT_MATCH,
	QUIT_TO_MENU,
	QUIT_GAME,
}

const LABEL_RESUME := "RESUME"
const LABEL_SETTINGS := "SETTINGS"
const LABEL_SAVE_AND_QUIT := "SAVE & QUIT"
const LABEL_ABANDON_RUN := "ABANDON RUN"
const LABEL_FORFEIT_MATCH := "FORFEIT MATCH"
const LABEL_QUIT_TO_MENU := "QUIT TO MENU"
const LABEL_QUIT_GAME := "QUIT GAME"

## Shown under SAVE & QUIT in a CHALLENGE battle: a paused challenge is still on the
## clock, and the player has to know that before they walk away from it.
const CHALLENGE_EOD_CAPTION := "Paused challenges must be finished by end of day (UTC) or the attempt is forfeit."

const TOOLTIP_NO_SAVE := "Saving unavailable"
const TOOLTIP_CANNOT_SAVE_NOW := "Saving unavailable right now"

const CONFIRM_FORFEIT := "You will lose this match."
const CONFIRM_ABANDON := "Your Arena run ends here. Progress in this run is lost."
const CONFIRM_UNSAVED := "Unsaved progress will be lost."
const CONFIRM_QUIT_GAME := "Quit Conquest?"

## Fade-in duration for the backdrop + card (skipped entirely when animations are off).
const FADE_TIME := 0.14

# ---------------------------------------------------------------------------
# Nodes (built in code -- no .tscn, like SettingsPanel)
# ---------------------------------------------------------------------------

var _root: Control = null
var _backdrop: ColorRect = null
var _card: PanelContainer = null
var _rows_box: VBoxContainer = null
var _status_label: Label = null

## Confirm sheet (a second card that covers the rows while a destructive row waits
## for a yes/no). Deliberately in-panel rather than an AcceptDialog: a native dialog
## is a separate Window that does not inherit this layer, this theme, or the pause.
var _confirm_layer: Control = null
var _confirm_label: Label = null
var _confirm_yes: Button = null
var _confirm_no: Button = null
## The Row awaiting confirmation, or -1 when the confirm sheet is closed.
var _pending_row: int = -1

## This menu's OWN settings overlay. SettingsPanel is a plain Control, so an instance
## mounted by the battle HUD lives on canvas layer 0 and would draw UNDER this layer.
## The class is a stateless front-end over the GameSettings autoload (MainMenu already
## mounts its own second instance), so owning one here is the cheap, correct way to get
## the panel to open ABOVE the pause menu.
var _settings: SettingsPanel = null

## The row buttons in display order (used for up/down keyboard navigation).
var _row_buttons: Array[Button] = []

var _open: bool = false
var _tween: Tween = null
## AudioManager's process mode before we promoted it to ALWAYS, restored on close.
var _prev_audio_process_mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT
var _audio_promoted: bool = false


# ---------------------------------------------------------------------------
# Pure row decision (the whole context matrix, testable with no tree)
# ---------------------------------------------------------------------------

## The rows this menu should show for [param ctx], in display order.
##
## [param ctx] keys (all optional, default false):
##   networked      -- a live networked match (NetSession.is_networked_match())
##   arena          -- an Arena run is active (ArenaController.is_active())
##   challenge      -- this battle is a challenge attempt being captured
##   save_contract  -- a BattleSaveManager was found
##   can_save_now   -- that manager answered can_save_now() == true
##
## Each entry is a Dictionary: { id: Row, label: String, enabled: bool,
## tooltip: String, confirm: String (empty = act immediately), caption: String }.
##
## The three exclusive branches are the point of this function:
##   * NETWORKED -- no save, and no plain "quit to menu": walking out of a live match
##     IS a loss, so the only way out is FORFEIT (confirmed).
##   * ARENA -- no save either; the run is abandoned (confirmed), then to the menu.
##   * SOLO (skirmish / campaign / challenge) -- SAVE & QUIT plus the no-save
##     QUIT TO MENU fallback, so a missing save contract never traps the player.
static func rows_for_context(ctx: Dictionary) -> Array:
	var networked: bool = bool(ctx.get("networked", false))
	var arena: bool = bool(ctx.get("arena", false))
	var challenge: bool = bool(ctx.get("challenge", false))
	var save_contract: bool = bool(ctx.get("save_contract", false))
	var can_save_now: bool = bool(ctx.get("can_save_now", false))

	var rows: Array = []
	rows.append(_make_row(Row.RESUME, LABEL_RESUME))
	rows.append(_make_row(Row.SETTINGS, LABEL_SETTINGS))

	if networked:
		var forfeit: Dictionary = _make_row(Row.FORFEIT_MATCH, LABEL_FORFEIT_MATCH)
		forfeit["confirm"] = CONFIRM_FORFEIT
		rows.append(forfeit)
	elif arena:
		var abandon: Dictionary = _make_row(Row.ABANDON_RUN, LABEL_ABANDON_RUN)
		abandon["confirm"] = CONFIRM_ABANDON
		rows.append(abandon)
	else:
		var save_row: Dictionary = _make_row(Row.SAVE_AND_QUIT, LABEL_SAVE_AND_QUIT)
		if not save_contract:
			# The contract is absent entirely (no save manager in this build/scene).
			save_row["enabled"] = false
			save_row["tooltip"] = TOOLTIP_NO_SAVE
		elif not can_save_now:
			# Present, but this moment is not savable (mid-animation, mid-resolution...).
			save_row["enabled"] = false
			save_row["tooltip"] = TOOLTIP_CANNOT_SAVE_NOW
		if challenge:
			save_row["caption"] = CHALLENGE_EOD_CAPTION
		rows.append(save_row)

		var to_menu: Dictionary = _make_row(Row.QUIT_TO_MENU, LABEL_QUIT_TO_MENU)
		to_menu["confirm"] = CONFIRM_UNSAVED
		rows.append(to_menu)

	var quit_game: Dictionary = _make_row(Row.QUIT_GAME, LABEL_QUIT_GAME)
	quit_game["confirm"] = CONFIRM_QUIT_GAME
	rows.append(quit_game)
	return rows


static func _make_row(id: int, label: String) -> Dictionary:
	return {
		"id": id,
		"label": label,
		"enabled": true,
		"tooltip": "",
		"confirm": "",
		"caption": "",
	}


## Locate the battle save contract, or null. Checked in two places so the save agent can
## publish it either way: an autoload node named [constant SAVE_MANAGER_NODE], or any node
## in the [constant SAVE_MANAGER_GROUP] group. A candidate only counts when it actually
## exposes BOTH contract methods -- a partial implementation must read as "absent" rather
## than crash the menu.
static func find_save_manager(tree: SceneTree) -> Node:
	if tree == null:
		return null
	var candidates: Array[Node] = []
	if tree.root != null:
		var autoloaded: Node = tree.root.get_node_or_null(SAVE_MANAGER_NODE)
		if autoloaded != null:
			candidates.append(autoloaded)
	# Both spellings of the group name, so the contract's owner can pick either.
	for group in [SAVE_MANAGER_GROUP, SAVE_MANAGER_NODE]:
		var grouped: Node = tree.get_first_node_in_group(group)
		if grouped != null:
			candidates.append(grouped)
	for c in candidates:
		if c.has_method("can_save_now") and c.has_method("save_and_quit"):
			return c
	return null


# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	layer = OVERLAY_LAYER
	# Must keep running while the tree it just paused is frozen.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_build_settings()
	visible = false


func _build_ui() -> void:
	_root = Control.new()
	_root.name = "PauseRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# STOP: swallow every click while the menu is up so nothing reaches the board.
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = MenuTheme.build()
	add_child(_root)

	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(MenuTheme.DARK.r, MenuTheme.DARK.g, MenuTheme.DARK.b, 0.72)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.add_child(_backdrop)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(center)

	_card = PanelContainer.new()
	_card.name = "PauseCard"
	_card.custom_minimum_size = Vector2(340, 0)
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(_card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	_card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	margin.add_child(vbox)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", MenuTheme.FONT_TITLE)
	title.add_theme_color_override("font_color", MenuTheme.GOLD)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(title)

	var sep := HSeparator.new()
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(sep)

	_rows_box = VBoxContainer.new()
	_rows_box.name = "Rows"
	_rows_box.add_theme_constant_override("separation", 8)
	_rows_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_rows_box)

	# Transient one-line feedback (e.g. a save that failed), hidden until it has text.
	_status_label = Label.new()
	_status_label.name = "Status"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
	_status_label.add_theme_color_override("font_color", MenuTheme.GOLD)
	_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_label.visible = false
	vbox.add_child(_status_label)

	_build_confirm_sheet()


## The yes/no sheet shown over the rows for a destructive choice.
func _build_confirm_sheet() -> void:
	_confirm_layer = Control.new()
	_confirm_layer.name = "ConfirmSheet"
	_confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.visible = false
	_root.add_child(_confirm_layer)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_confirm_layer.add_child(center)

	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(340, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(card)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 18)
	card.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	margin.add_child(vbox)

	_confirm_label = Label.new()
	_confirm_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_confirm_label.add_theme_font_size_override("font_size", MenuTheme.FONT_BODY)
	_confirm_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_confirm_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(buttons)

	# CANCEL first and focused by default: a destructive sheet should never be one
	# reflexive Enter away from ending the match.
	_confirm_no = Button.new()
	_confirm_no.name = "ConfirmNo"
	_confirm_no.text = "CANCEL"
	_confirm_no.custom_minimum_size = Vector2(0, 44)
	_confirm_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_no.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_no.pressed.connect(_close_confirm)
	buttons.add_child(_confirm_no)

	_confirm_yes = Button.new()
	_confirm_yes.name = "ConfirmYes"
	_confirm_yes.text = "CONFIRM"
	_confirm_yes.custom_minimum_size = Vector2(0, 44)
	_confirm_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_confirm_yes.mouse_filter = Control.MOUSE_FILTER_STOP
	_confirm_yes.add_theme_color_override("font_color", MenuTheme.GOLD)
	_confirm_yes.pressed.connect(_on_confirm_yes)
	buttons.add_child(_confirm_yes)


func _build_settings() -> void:
	_settings = SettingsPanel.new()
	_settings.name = "PauseSettingsPanel"
	# Added to the CanvasLayer directly (a sibling of _root) so it draws OVER the
	# pause card rather than inside its dark-themed subtree.
	add_child(_settings)


# ---------------------------------------------------------------------------
# Open / close
# ---------------------------------------------------------------------------

func is_open() -> bool:
	return _open


func open() -> void:
	if _open:
		return
	_open = true
	_close_confirm()
	_set_status("")
	_rebuild_rows()
	visible = true
	_root.move_to_front()

	var tree := get_tree()
	if tree != null:
		tree.paused = true
	_promote_audio()
	_fade_in()
	_focus_first_enabled_row()


func close() -> void:
	if not _open:
		return
	_open = false
	_close_confirm()
	if _settings != null and _settings.is_open():
		_settings.close()
	_kill_tween()
	visible = false
	_restore_audio()
	var tree := get_tree()
	if tree != null:
		tree.paused = false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


## Battle SFX/music must keep playing through a pause. AudioManager is a PAUSABLE
## autoload, so a paused tree would silence it; promote it for the duration and put
## the previous mode back on close (so no other screen's pause behaviour changes).
func _promote_audio() -> void:
	if _audio_promoted:
		return
	var audio: Node = _audio_manager()
	if audio == null:
		return
	_prev_audio_process_mode = audio.process_mode
	audio.process_mode = Node.PROCESS_MODE_ALWAYS
	_audio_promoted = true


func _restore_audio() -> void:
	if not _audio_promoted:
		return
	var audio: Node = _audio_manager()
	if audio != null:
		audio.process_mode = _prev_audio_process_mode
	_audio_promoted = false


func _audio_manager() -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("AudioManager")


func _fade_in() -> void:
	_kill_tween()
	if not _animations_on():
		_root.modulate.a = 1.0
		return
	_root.modulate.a = 0.0
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", 1.0, _scaled(FADE_TIME))


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null
	if _root != null:
		_root.modulate.a = 1.0


func _animations_on() -> bool:
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		return false
	return GameSettings.animations_on()


func _scaled(seconds: float) -> float:
	if typeof(GameSettings) == TYPE_OBJECT and GameSettings != null:
		return GameSettings.scaled_time(seconds)
	return seconds


# ---------------------------------------------------------------------------
# Row construction
# ---------------------------------------------------------------------------

## Read the live autoloads ONCE and hand the plain flags to [method rows_for_context].
## Everything in here is null-guarded so the menu is safe in a headless / minimal scene.
func _context() -> Dictionary:
	# Untyped on purpose: the save manager is a CONTRACT discovered by has_method(), not a
	# class this file may depend on. A `Node`-typed local would make the static analyser
	# reject `save_manager.can_save_now()` with "not found in base Node".
	var save_manager = find_save_manager(get_tree())
	var can_save: bool = false
	if save_manager != null:
		can_save = bool(save_manager.can_save_now())
	return {
		"networked": _is_networked_match(),
		"arena": _is_arena_run(),
		"challenge": _is_challenge_battle(),
		"save_contract": save_manager != null,
		"can_save_now": can_save,
	}


func _is_networked_match() -> bool:
	if typeof(NetSession) != TYPE_OBJECT or NetSession == null:
		return false
	return NetSession.has_method("is_networked_match") and NetSession.is_networked_match()


func _is_arena_run() -> bool:
	if typeof(ArenaController) != TYPE_OBJECT or ArenaController == null:
		return false
	return ArenaController.has_method("is_active") and ArenaController.is_active()


## True while this battle is a CHALLENGE attempt. ChallengeController's "armed for
## capture" state is currently only exposed privately (`_is_capturing()`), so we probe
## the public name FIRST -- if/when it grows a public `is_capturing()` this picks it up
## with no change here -- and fall back to the private one.
func _is_challenge_battle() -> bool:
	if typeof(ChallengeController) != TYPE_OBJECT or ChallengeController == null:
		return false
	if ChallengeController.has_method("is_capturing"):
		return bool(ChallengeController.call("is_capturing"))
	if ChallengeController.has_method("_is_capturing"):
		return bool(ChallengeController.call("_is_capturing"))
	return false


func _rebuild_rows() -> void:
	for child in _rows_box.get_children():
		_rows_box.remove_child(child)
		child.queue_free()
	_row_buttons.clear()

	for spec in rows_for_context(_context()):
		var row: Dictionary = spec
		var button := Button.new()
		button.text = String(row.get("label", ""))
		button.name = "Row%d" % int(row.get("id", -1))
		# 44px: the touch-target floor this project uses for phone-viable UI.
		button.custom_minimum_size = Vector2(0, 44)
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.disabled = not bool(row.get("enabled", true))
		button.tooltip_text = String(row.get("tooltip", ""))
		button.set_meta("row_id", int(row.get("id", -1)))
		button.set_meta("confirm", String(row.get("confirm", "")))
		button.pressed.connect(_on_row_pressed.bind(button))
		_rows_box.add_child(button)
		if not button.disabled:
			_row_buttons.append(button)

		var caption: String = String(row.get("caption", ""))
		if not caption.is_empty():
			var lbl := Label.new()
			lbl.text = caption
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lbl.add_theme_font_size_override("font_size", MenuTheme.FONT_CAPTION)
			lbl.add_theme_color_override("font_color", MenuTheme.CREAM_DIM)
			lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_rows_box.add_child(lbl)

	UIFeedback.attach_sfx(_rows_box)


func _focus_first_enabled_row() -> void:
	if not _row_buttons.is_empty():
		_row_buttons[0].grab_focus()


# ---------------------------------------------------------------------------
# Row actions
# ---------------------------------------------------------------------------

func _on_row_pressed(button: Button) -> void:
	var row_id: int = int(button.get_meta("row_id", -1))
	var confirm: String = String(button.get_meta("confirm", ""))
	if confirm.is_empty():
		_perform(row_id)
	else:
		_open_confirm(row_id, confirm)


func _open_confirm(row_id: int, message: String) -> void:
	_pending_row = row_id
	_confirm_label.text = message
	_confirm_layer.visible = true
	_confirm_layer.move_to_front()
	_confirm_no.grab_focus()


func _close_confirm() -> void:
	_pending_row = -1
	if _confirm_layer != null:
		_confirm_layer.visible = false


func _on_confirm_yes() -> void:
	var row_id: int = _pending_row
	_close_confirm()
	if row_id != -1:
		_perform(row_id)


func _perform(row_id: int) -> void:
	match row_id:
		Row.RESUME:
			close()
		Row.SETTINGS:
			if _settings != null:
				_settings.open()
		Row.SAVE_AND_QUIT:
			_save_and_quit()
		Row.ABANDON_RUN:
			if typeof(ArenaController) == TYPE_OBJECT and ArenaController != null \
					and ArenaController.has_method("abort_run"):
				ArenaController.abort_run()
			_quit_to_menu()
		Row.FORFEIT_MATCH:
			if typeof(NetSession) == TYPE_OBJECT and NetSession != null \
					and NetSession.has_method("forfeit_match"):
				NetSession.forfeit_match()
			_quit_to_menu()
		Row.QUIT_TO_MENU:
			_quit_to_menu()
		Row.QUIT_GAME:
			_unpause()
			get_tree().quit()
		_:
			pass


## Hand off to the save contract. It owns BOTH halves (write the battle, route to the
## menu), so on success there is nothing left to do here. On a refusal we stay put with
## a reason rather than dropping the player into the menu with no save.
func _save_and_quit() -> void:
	var save_manager = find_save_manager(get_tree())   # untyped: see _context()
	if save_manager == null:
		_set_status(TOOLTIP_NO_SAVE)
		return
	# Hand the manager an UNPAUSED tree -- it changes scene itself, and a paused flag
	# survives a scene change (the menu it lands on would be frozen).
	_unpause()
	if bool(save_manager.save_and_quit()):
		visible = false
		return
	# The save was REFUSED. Put the pause, the audio promotion and this menu's own open
	# state back exactly as they were, so the player is left where they started rather
	# than in a half-torn-down battle.
	_set_status("Save failed. Use Quit to Menu to leave without saving.")
	_open = true
	_promote_audio()
	var tree := get_tree()
	if tree != null:
		tree.paused = true


func _quit_to_menu() -> void:
	_unpause()
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


## get_tree().paused survives a scene change, so every exit path must clear it or the
## menu we land on is frozen. (Same rule GameOverScreen's handlers follow.)
func _unpause() -> void:
	_open = false
	_restore_audio()
	var tree := get_tree()
	if tree != null:
		tree.paused = false


func _set_status(text: String) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.visible = not text.is_empty()


# ---------------------------------------------------------------------------
# Keyboard
# ---------------------------------------------------------------------------

## Handled in `_input` (not `_unhandled_input`) so the events we consume never reach the
## board's own ui_cancel handling underneath, and so the viewport's built-in focus
## navigation does not ALSO move the selection on the same press.
func _input(event: InputEvent) -> void:
	if not _open:
		return

	# The Settings overlay is modal over this menu: ESC only closes it.
	if _settings != null and _settings.is_open():
		if event.is_action_pressed("ui_cancel"):
			_settings.close()
			_focus_first_enabled_row()
			get_viewport().set_input_as_handled()
		return

	# The confirm sheet is modal over the rows: ESC cancels it (never the whole menu).
	if _pending_row != -1:
		if event.is_action_pressed("ui_cancel"):
			_close_confirm()
			_focus_first_enabled_row()
			get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_cancel"):
		# ESC on the pause menu means RESUME -- the same key that opened it closes it.
		close()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("ui_down"):
		_move_focus(1)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_move_focus(-1)
		get_viewport().set_input_as_handled()


## Move the focused row by [param step], wrapping. Disabled rows are not in
## [member _row_buttons], so navigation skips them automatically.
func _move_focus(step: int) -> void:
	if _row_buttons.is_empty():
		return
	var viewport: Viewport = get_viewport()
	var focused: Control = viewport.gui_get_focus_owner() if viewport != null else null
	var idx: int = _row_buttons.find(focused)
	if idx == -1:
		idx = 0 if step > 0 else _row_buttons.size() - 1
	else:
		idx = wrapi(idx + step, 0, _row_buttons.size())
	_row_buttons[idx].grab_focus()
