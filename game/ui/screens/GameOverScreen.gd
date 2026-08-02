extends Control

class_name GameOverScreen

# Animated end-of-battle overlay: a full-screen VICTORY / DEFEAT card that drops
# in when a player is eliminated and the game is decided. Offers Rematch (reload
# the battle), Main Menu, and Quit.
#
# Code-built like TerrainInfoPanel / CombatForecastPanel: the .tscn is just a
# full-rect Control shell with this script attached, and _ready() builds the
# backdrop, result card, banner, and buttons, then themes them with the amber
# battle HUD look (ConquestTheme). Hidden by default; GameWorldManager decides
# the outcome and calls show_victory()/show_defeat() (or show_result()).
#
# Idempotent: once shown it ignores further calls (`_shown`), so multiple
# elimination signals arriving in the same frame never restack the reveal.
#
# Runs while the tree is paused: the whole node is PROCESS_MODE_ALWAYS and the
# reveal Tween is TWEEN_PAUSE_PROCESS, so pausing gameplay on game over does not
# freeze the animation or block the buttons.
#
# RESULTS SUMMARY (beneath the banner): a dark gold-headed stat card showing
# rounds taken, the human's own units lost vs enemies defeated, and the current
# PlayerProfile points balance. Rounds come from TurnSystemManager's active turn
# system; the tally is latched HERE off GameEvents.unit_eliminated -- this screen
# is mounted (hidden) for the whole battle, so it can hear every elimination as
# it happens rather than reconstructing history at reveal time. Sides are read
# off the dying unit's owner Player at the moment of death (player_id 0 == the
# human; is_neutral is excluded from both tallies, mirroring PlayerProfile /
# ChallengeController); a per-unit instance-id latch makes a double-fired
# elimination signal (a known occurrence elsewhere in this codebase) cost
# nothing extra. Challenge score and item-drop display are NOT shown: neither
# ChallengeController nor the items feature exposes a public hook a foreign
# screen can read the just-finished run's result from (see the class-level
# comment in [ChallengeController] and [ItemSystem] -- both are read-only for
# this work). The card's own entrance fade honours [member GameSettings.
# animations_enabled] (see [method _animations_on]); everything else on this
# screen already ignores the toggle, unchanged.
#
# INPUT: ESC (ui_cancel) goes to the Main Menu while the screen is shown --
# Enter/Space already "press" the focused Rematch button via Godot's built-in
# ui_accept handling on a focused Button, so no extra wiring is needed for that.

# --- Tunables ---------------------------------------------------------------
const CARD_WIDTH := 560.0
const REVEAL_SCALE_FROM := 0.6   # banner/card starts small then pops to 1.0
const REVEAL_SLIDE_PX := 26.0    # card starts this many px high and settles down

# Banner accents: bright gold for a win, desaturated red for a loss.
const VICTORY_GOLD := Color("f5c95a")
const DEFEAT_RED := Color("c15a48")

# Outcome tags (also used by GameWorldManager for the neutral versus banner).
const OUTCOME_VICTORY := &"victory"
const OUTCOME_DEFEAT := &"defeat"

# Idempotency guard -- true once the screen has been revealed.
var _shown: bool = false

# Nodes built in _create_ui().
var _backdrop: ColorRect
var _card: PanelContainer
var _banner_label: Label
var _subtitle_label: Label
var _summary_card: PanelContainer
var _summary_headers: Array[Label] = []
var _rounds_value: Label
var _lost_value: Label
var _defeated_value: Label
var _points_value: Label
var _button_box: VBoxContainer
var _rematch_button: Button
var _menu_button: Button
var _quit_button: Button
var _reveal_tween: Tween

# --- Results tally (latched off GameEvents.unit_eliminated all battle) ------
var _friendlies_lost: int = 0
var _enemies_defeated: int = 0
# instance_id -> true, so a duplicate elimination signal for the same unit
# (documented elsewhere in this codebase, e.g. player_eliminated) never counts twice.
var _counted_unit_ids: Dictionary = {}


func _ready() -> void:
	name = "GameOverScreen"

	# Animate + accept clicks even when gameplay pauses on game over (see file note).
	process_mode = Node.PROCESS_MODE_ALWAYS

	set_anchors_preset(Control.PRESET_FULL_RECT)

	# Swallow clicks once shown so the board underneath can't be commanded. While
	# hidden (visible = false) a Control receives no input, so this never blocks
	# the board during normal play or at boot.
	mouse_filter = Control.MOUSE_FILTER_STOP

	# Draw above every HUD panel in the shared "UI" CanvasLayer.
	z_as_relative = false
	z_index = 4096

	_create_ui()
	visible = false

	# Tally subscription: this screen exists (hidden) for the whole battle, so it
	# hears every elimination as it happens rather than reconstructing history later.
	_connect_tally()


func _create_ui() -> void:
	# Dimmed backdrop covering the whole viewport; fades in with the reveal and,
	# with mouse_filter STOP, catches any click outside the card.
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.04, 0.02, 0.0, 0.72)
	_backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)

	# Centered result card. Anchors pinned to the viewport centre with grow BOTH
	# means it is sized to its content's minimum and centred, no CenterContainer
	# needed -- leaving its transform (scale/position) free for the pop animation.
	_card = PanelContainer.new()
	_card.name = "ResultCard"
	_card.anchor_left = 0.5
	_card.anchor_right = 0.5
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_card.grow_vertical = Control.GROW_DIRECTION_BOTH
	_card.custom_minimum_size = Vector2(CARD_WIDTH, 0)
	# Keep the scale pivot at the card's centre as it lays out, so the pop scales
	# from the middle rather than the top-left corner.
	_card.resized.connect(_recenter_pivot)
	add_child(_card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	_card.add_child(vb)

	_banner_label = Label.new()
	_banner_label.name = "BannerLabel"
	_banner_label.text = "VICTORY"
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 64)
	vb.add_child(_banner_label)

	_subtitle_label = Label.new()
	_subtitle_label.name = "SubtitleLabel"
	_subtitle_label.text = "All enemies defeated!"
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(_subtitle_label)

	# RESULTS summary: rounds / units lost / enemies defeated / points balance.
	# Structure only here -- colours and the dark plate stylebox are applied in
	# _style_summary_card() AFTER ConquestTheme.apply_to() below, because apply_to's
	# recursive _restyle() would otherwise strip a Label colour override set before it
	# and repaint any PanelContainer back to the bright amber panel_box() (see that
	# method's own banner/subtitle colours, set the same way, for precedent).
	_summary_card = _build_summary_card()
	vb.add_child(_summary_card)

	var sep := HSeparator.new()
	vb.add_child(sep)

	_button_box = VBoxContainer.new()
	_button_box.name = "Buttons"
	_button_box.add_theme_constant_override("separation", 10)
	vb.add_child(_button_box)

	_rematch_button = _make_button("Rematch")
	_rematch_button.pressed.connect(_on_rematch_pressed)
	_button_box.add_child(_rematch_button)

	_menu_button = _make_button("Main Menu")
	_menu_button.pressed.connect(_on_main_menu_pressed)
	_button_box.add_child(_menu_button)

	_quit_button = _make_button("Quit")
	_quit_button.pressed.connect(_on_quit_pressed)
	_button_box.add_child(_quit_button)

	# Amber HUD look. apply_to strips baked font_color overrides, so the banner
	# outline / subtitle tint / per-outcome banner colour are all set AFTER it so
	# they survive.
	ConquestTheme.apply_to(self)

	# Punchy dark outline on the big banner, and a muted subtitle.
	_banner_label.add_theme_constant_override("outline_size", 8)
	_banner_label.add_theme_color_override("font_outline_color", ConquestTheme.BROWN_DK)
	_subtitle_label.add_theme_color_override("font_color", ConquestTheme.INK_SOFT)

	_style_summary_card()


## Dark inset plate (ConquestTheme.plate_box()) holding four stat blocks in a
## row: ROUNDS, LOST, DEFEATED, POINTS. Each block stacks a small gold header
## over a bigger cream value (16 / 24 font-size rhythm). Values start at "0"
## and are filled in by [method _populate_summary] right before the reveal.
func _build_summary_card() -> PanelContainer:
	var card := PanelContainer.new()
	card.name = "SummaryCard"

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	card.add_child(margin)

	var row := HBoxContainer.new()
	row.name = "StatRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	margin.add_child(row)

	_rounds_value = _add_stat_block(row, "ROUNDS")
	_lost_value = _add_stat_block(row, "LOST")
	_defeated_value = _add_stat_block(row, "DEFEATED")
	_points_value = _add_stat_block(row, "POINTS")

	return card


## One stat block: a centred 16px header label over a centred 24px value label.
## Returns the value label (callers keep that reference; headers are collected
## in [member _summary_headers] for the post-apply_to colour pass).
func _add_stat_block(row: HBoxContainer, header_text: String) -> Label:
	var block := VBoxContainer.new()
	block.alignment = BoxContainer.ALIGNMENT_CENTER
	block.add_theme_constant_override("separation", 2)
	row.add_child(block)

	var header := Label.new()
	header.text = header_text
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 16)
	block.add_child(header)
	_summary_headers.append(header)

	var value := Label.new()
	value.text = "0"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.add_theme_font_size_override("font_size", 24)
	block.add_child(value)

	return value


## Dark plate + gold headers / cream values. Called AFTER ConquestTheme.apply_to()
## -- see the comment where _summary_card is built in _create_ui().
func _style_summary_card() -> void:
	if _summary_card == null:
		return
	_summary_card.add_theme_stylebox_override("panel", ConquestTheme.plate_box())
	for header in _summary_headers:
		header.add_theme_color_override("font_color", ConquestTheme.EL_HOLY)
	for value in [_rounds_value, _lost_value, _defeated_value, _points_value]:
		if value != null:
			value.add_theme_color_override("font_color", ConquestTheme.CREAM)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 44)
	b.focus_mode = Control.FOCUS_ALL
	return b


# --- Public API --------------------------------------------------------------

## True once the screen has been revealed (used by callers to avoid re-triggering).
func is_shown() -> bool:
	return _shown


## Reveal a win for the local human ("VICTORY", gold).
func show_victory() -> void:
	show_result(OUTCOME_VICTORY, "VICTORY", "All enemies defeated!")


## Reveal a loss for the local human ("DEFEAT", red).
func show_defeat() -> void:
	show_result(OUTCOME_DEFEAT, "DEFEAT", "Your forces have fallen.")


## Reveal the end screen with an explicit banner. Idempotent -- the first call
## wins and later calls are ignored, so repeated elimination signals never
## restack the animation. Pauses gameplay while the (pause-immune) reveal runs.
func show_result(outcome: StringName, title: String, subtitle: String) -> void:
	if _shown:
		return
	_shown = true

	_banner_label.text = title
	_subtitle_label.text = subtitle

	var accent: Color = VICTORY_GOLD if outcome == OUTCOME_VICTORY else DEFEAT_RED
	_banner_label.add_theme_color_override("font_color", accent)

	_populate_summary()

	visible = true

	# Freeze gameplay. Safe because this node is PROCESS_MODE_ALWAYS and the reveal
	# tween is TWEEN_PAUSE_PROCESS, so the screen keeps animating and its buttons
	# keep working while the tree is paused.
	get_tree().paused = true

	_play_reveal_animation()
	_play_sting(outcome)

	# Give the primary action keyboard/controller focus.
	_rematch_button.grab_focus()


# --- Reveal animation --------------------------------------------------------

func _recenter_pivot() -> void:
	if _card != null:
		_card.pivot_offset = _card.size / 2.0


func _play_reveal_animation() -> void:
	_recenter_pivot()

	# Defensive: show_result is idempotent so there is normally no prior tween.
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()

	# Initial hidden pose: dim backdrop, small/transparent card lifted slightly,
	# invisible buttons.
	_backdrop.modulate.a = 0.0
	_card.modulate.a = 0.0
	_card.scale = Vector2(REVEAL_SCALE_FROM, REVEAL_SCALE_FROM)
	var rest_y: float = _card.position.y
	_card.position.y = rest_y - REVEAL_SLIDE_PX
	for child in _button_box.get_children():
		var ctl := child as Control
		if ctl != null:
			ctl.modulate.a = 0.0

	_reveal_tween = create_tween()
	# Keep animating while gameplay is paused (see show_result).
	_reveal_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_reveal_tween.set_parallel(true)

	# Backdrop dims in.
	_reveal_tween.tween_property(_backdrop, "modulate:a", 1.0, 0.28) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	# Card pops: scale overshoot (TRANS_BACK) + fade + gentle slide down to rest.
	_reveal_tween.tween_property(_card, "modulate:a", 1.0, 0.26) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	_reveal_summary_card()
	_reveal_tween.tween_property(_card, "scale", Vector2.ONE, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_card, "position:y", rest_y, 0.42) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Buttons fade in staggered after the card has mostly landed. Total reveal
	# stays under ~0.75s so it reads snappy (reduced-motion friendly).
	var delay: float = 0.30
	for child in _button_box.get_children():
		var ctl := child as Control
		if ctl == null:
			continue
		_reveal_tween.tween_property(ctl, "modulate:a", 1.0, 0.18) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(delay)
		delay += 0.08


## The summary card's own entrance, gated on [member GameSettings.animations_enabled]
## (see [method _animations_on]). Animations ON: fades in once the card has mostly
## landed, just ahead of the button stagger. Animations OFF: snaps straight to fully
## visible with NO tween ever created for it -- the rule every animating system in
## this codebase follows (see e.g. [ItemToast._animations_on]).
func _reveal_summary_card() -> void:
	if _summary_card == null:
		return
	if not _animations_on():
		_summary_card.modulate.a = 1.0
		return
	_summary_card.modulate.a = 0.0
	_reveal_tween.tween_property(_summary_card, "modulate:a", 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT).set_delay(0.26)


## True when the player has animations enabled (defaults to on when GameSettings is
## absent, e.g. a bare test harness) -- mirrors [method ItemToast._animations_on].
func _animations_on() -> bool:
	if typeof(GameSettings) != TYPE_OBJECT or GameSettings == null:
		return true
	if not GameSettings.has_method("animations_on"):
		return true
	return bool(GameSettings.animations_on())


func _play_sting(outcome: StringName) -> void:
	# Optional audio: play a victory/defeat sting if AudioManager exposes play_sfx.
	# Unknown/unassigned events no-op inside the manager, so this is always safe.
	var audio := get_node_or_null("/root/AudioManager")
	if audio == null or not audio.has_method("play_sfx"):
		return
	var event_name: StringName = &"sfx_victory" if outcome == OUTCOME_VICTORY else &"sfx_defeat"
	audio.play_sfx(event_name)


# --- Button handlers ---------------------------------------------------------
# Every handler unpauses the tree first: get_tree().paused persists across a
# scene change, so leaving it true would freeze the reloaded battle / the menu.

func _on_rematch_pressed() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_main_menu_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menus/MainMenu.tscn")


func _on_quit_pressed() -> void:
	get_tree().paused = false
	get_tree().quit()


# --- Input --------------------------------------------------------------------

## ESC goes to the Main Menu while the screen is shown. Enter/Space already
## "press" the focused Rematch button through Godot's own ui_accept handling on a
## focused Button (see show_result -> grab_focus), so nothing else is needed for
## that. Mirrors UILayoutManager's ui_cancel handling: consume the event so it
## cannot also fall through to a board handler underneath (harmless here since
## gameplay is paused, but consuming it is the established pattern).
func _unhandled_input(event: InputEvent) -> void:
	if not _shown or not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_main_menu_pressed()


# --- Results data ---------------------------------------------------------------

## Fill the summary card's value labels from the latched tally + live reads.
## Safe to call more than once (show_result already guards re-entry via _shown).
func _populate_summary() -> void:
	if _rounds_value != null:
		_rounds_value.text = str(_rounds_taken())
	if _lost_value != null:
		_lost_value.text = str(_friendlies_lost)
	if _defeated_value != null:
		_defeated_value.text = str(_enemies_defeated)
	if _points_value != null:
		_points_value.text = str(_points_balance())


## Rounds taken so far, read off the ACTIVE turn system (both TraditionalTurnSystem
## and SpeedFirstTurnSystem keep TurnSystemBase.current_turn in sync with their own
## round counter -- see each system's advance_turn -- so this one field covers
## either mode). Null-safe: 0 before any system has activated (also covers a bare
## test harness with no live battle).
func _rounds_taken() -> int:
	if typeof(TurnSystemManager) != TYPE_OBJECT or TurnSystemManager == null:
		return 0
	var active: TurnSystemBase = TurnSystemManager.active_turn_system
	if active == null:
		return 0
	return int(active.current_turn)


## The player's current spendable balance (PlayerProfile.get_points()). REAL data --
## PlayerProfile grants a battle's win points off PlayerManager.player_eliminated
## before this screen's own reveal runs (that autoload connects in its _ready, this
## screen's host connects during battle scene setup, so the grant lands first). Note
## for future work: that grant only fires on a player-eliminated win; a map-objective
## win (e.g. "defeat the boss" while grunts remain) does not eliminate a player and so
## is not yet paid -- a PlayerProfile-side gap, out of scope here. Null-safe: 0 when
## the autoload or the method is unexpectedly missing.
func _points_balance() -> int:
	if typeof(PlayerProfile) != TYPE_OBJECT or PlayerProfile == null:
		return 0
	if not PlayerProfile.has_method("get_points"):
		return 0
	return int(PlayerProfile.get_points())


# --- Results tally ------------------------------------------------------------

## Subscribe to GameEvents.unit_eliminated for the WHOLE battle (this screen is
## mounted hidden from battle start), so the tally is built from events as they
## happen rather than reconstructed at reveal time. Guarded so a second _ready
## (should never happen for a scene-instantiated node, but mirrors every other
## GameEvents subscriber in this codebase) can never double-connect.
func _connect_tally() -> void:
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return
	if not GameEvents.has_signal("unit_eliminated"):
		return
	if not GameEvents.unit_eliminated.is_connected(_on_unit_eliminated_tally):
		GameEvents.unit_eliminated.connect(_on_unit_eliminated_tally)


## Tally one elimination. FREED-SAFE: everything this needs (the owner's player_id /
## is_neutral) is read out of the live objects right here, in the same call the
## signal handed them to us in -- nothing is stored but plain ints, so a unit or
## Player freed later can never be touched through a stale reference.
##
## Side is determined by the dying unit's owner: player_id == 0 is the human, every
## other id is an enemy. A neutral owner (a dormant wild camp) counts toward
## NEITHER tally, mirroring PlayerProfile._on_unit_eliminated and
## ChallengeController's own neutral guards elsewhere in this file's siblings.
##
## Idempotent per unit via [member _counted_unit_ids] (an instance-id latch): the
## same elimination signal firing twice for one unit (unit.gd's own _is_dead guard
## should prevent that in production, but a mocked/duplicated event in a test, or a
## future call site, must not double-count) tallies once.
func _on_unit_eliminated_tally(unit, _eliminator) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var uid: int = unit.get_instance_id()
	if _counted_unit_ids.has(uid):
		return

	var owner = null
	if unit.has_method("get_owner_player"):
		owner = unit.get_owner_player()
	elif "owner_player" in unit:
		owner = unit.owner_player
	if owner == null or not ("player_id" in owner):
		return
	if "is_neutral" in owner and bool(owner.is_neutral):
		return

	_counted_unit_ids[uid] = true
	if int(owner.player_id) == 0:
		_friendlies_lost += 1
	else:
		_enemies_defeated += 1
