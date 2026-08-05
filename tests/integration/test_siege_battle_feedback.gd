extends GutTest

## Siege's in-battle feedback ON THE REAL MOUNTED HUD: the respawn row, the capture alarm,
## the objective banner's live capture progress, the post-match line, and the left column's
## 720p budget with the new row on screen.
##
## Everything here boots the shipped `GameUILayout.tscn` and asserts on RENDERED nodes and
## MEASURED rects. The project rule exists because it has twice shipped a HUD element that
## passed a string-reading suite while the screen was wrong -- a chip laid out 11px wide with
## its text trimmed off, and a glyph the font cannot draw rendering as an empty box. The pure
## wording rules are pinned separately in `unit/test_siege_feedback.gd`.
##
## THE CONTROLLER IS A STAND-IN, and the last test in this file is what keeps that honest:
## it asserts the REAL [SiegeController] still declares every method this HUD calls, so a
## stub that drifts from the shipped mode fails here rather than passing while the game is
## blank. Driving the real controller instead would need lanes, base cells and a live board
## -- the mode workstream's own suites cover that; this one covers the screen.
##
## Every countdown here is driven by the ACTIVE turn system's own signals, never by
## PlayerManager's -- CONQUEST.md convention 2, and the bug that would matter most in a push
## mode, where the enemy is acting for half the battle.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const GAME_OVER := preload("res://game/ui/screens/GameOverScreen.tscn")

const DESIGN := Vector2i(1280, 720)

## Real roster ids -- the row resolves display names through CharacterLibrary, exactly as
## every other unit-naming surface in the game does, so a made-up id would prove nothing.
const ID_PETALFANG := "petalfang"
const ID_BLIGHTCAP := "blightcap"

var _prev_window_size: Vector2i

## Turn systems built by a test. Registered with the manager (an autoload, so it outlives
## the suite) and never parented, so this suite frees them itself.
var _systems: Array = []

## Scratch node standing in as `current_scene` while a turn system is activated:
## TurnSystemManager.switch_to_turn_system() walks the current scene looking for units.
var _scratch_scene: Node = null


# =====================================================================================
#  Fixtures
# =====================================================================================

## Stand-in for [SiegeController], exposing exactly the surface this HUD asks of it -- and
## in exactly its shapes: a respawn queue of {player_id, character_id, round}, a round
## counter, the authored ruleset, and the capture latch as a SIDE id.
class SiegeControllerStub extends Node:
	var active: bool = true
	var rounds: int = 0
	var queue: Array = []
	var capturing: int = -1
	var captured: int = -1
	var rules: SiegeRuleset = SiegeRuleset.new()

	func _init() -> void:
		# The suite's wording pins ("respawns in 2 turns" -> "1 turn") assume an
		# opening delay of 2; the shipped default escalates from 1, so the fixture
		# authors its own base. The knob IS the data - this is authoring, not drift.
		rules.respawn_base_delay = 2

	func is_active() -> bool:
		return active

	func rounds_elapsed() -> int:
		return rounds

	func ruleset() -> SiegeRuleset:
		return rules

	func respawn_queue() -> Array:
		# Mirror the real controller's read shape: entries carry the frozen "delay"
		# stamped at death, and a LIVE "rounds_remaining" derived from the round clock.
		var out: Array = []
		for entry in queue:
			var e: Dictionary = (entry as Dictionary).duplicate(true)
			var d: int = int(e.get("delay", 0))
			e["rounds_remaining"] = maxi(0, d - (rounds - int(e.get("round", 0))))
			out.append(e)
		return out

	func capturing_by() -> int:
		return capturing

	func captured_by() -> int:
		return captured

	func down(character_id: String, player_id: int = 0) -> void:
		# Stamp the frozen escalated delay at death, exactly as SiegeController does;
		# rounds_remaining is derived live in respawn_queue() above.
		queue.append({"player_id": player_id, "character_id": character_id, "round": rounds,
			"delay": rules.respawn_delay_for_round(rounds)})


## Stands in for the [CaptureBase] objective in the ONE test that proves the banner carries
## capture progress. It reproduces that objective's contract -- describe_progress reporting a
## capture in flight -- without this suite owning the sentence, which is the mode's.
class CaptureObjectiveStub extends WinCondition:
	var progressing: bool = false

	func describe() -> String:
		return "Capture the enemy base"

	func describe_progress(_state: Dictionary) -> String:
		return "Capturing - survive 1 turn!" if progressing else describe()


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func after_each() -> void:
	if TurnSystemManager != null:
		TurnSystemManager.reset_for_new_game()
	for system in _systems:
		if system != null and is_instance_valid(system) and system.get_parent() == null:
			system.free()
	_systems.clear()
	if _scratch_scene != null and is_instance_valid(_scratch_scene):
		if get_tree().current_scene == _scratch_scene:
			get_tree().current_scene = null
		get_tree().root.remove_child(_scratch_scene)
		_scratch_scene.free()
	_scratch_scene = null
	# Static registry -- shared with every other suite in the run.
	CharacterLibrary.clear_cache()


# =====================================================================================
#  Mounting
# =====================================================================================

## The mode controller, mounted BEFORE the HUD -- the real ordering (the map boots the mode,
## then the HUD mounts on top of it) and the one the row resolves against.
func _mount_controller() -> SiegeControllerStub:
	var ctrl := SiegeControllerStub.new()
	ctrl.name = "SiegeControllerStub"
	ctrl.add_to_group(&"siege_controller")
	add_child_autofree(ctrl)
	return ctrl


func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for i in range(8):
		await get_tree().process_frame
	return layout


## A REAL turn system, registered and made active through TurnSystemManager -- so the row
## subscribes through the same `turn_system_activated` signal a battle boot fires.
func _activate_turn_system() -> TurnSystemBase:
	if get_tree().current_scene == null:
		_scratch_scene = Node.new()
		_scratch_scene.name = "SiegeFeedbackScratchScene"
		get_tree().root.add_child(_scratch_scene)
		get_tree().current_scene = _scratch_scene
	var system: TurnSystemBase = TraditionalTurnSystem.new()
	_systems.append(system)
	TurnSystemManager.register_turn_system(system)
	TurnSystemManager.switch_to_turn_system(system)
	await get_tree().process_frame
	return system


func _make_unit(display: String) -> Unit:
	var character := CharacterResource.new()
	character.character_id = StringName(display.to_lower())
	character.display_name = display
	var unit := Unit.new()
	unit.character_resource = character
	add_child_autofree(unit)
	return unit


func _settle() -> void:
	for i in range(6):
		await get_tree().process_frame


func _row_of(layout: Control) -> SiegeFeedback:
	return layout.siege_feedback as SiegeFeedback


func _rect_of(node: Control) -> Rect2:
	return Rect2(node.global_position, node.size)


func _vp() -> Vector2:
	var vp := get_viewport()
	return vp.get_visible_rect().size if vp != null else Vector2(DESIGN)


# =====================================================================================
#  It is mounted, and it stays out of the way
# =====================================================================================

func test_the_respawn_row_is_a_row_of_the_left_column_not_an_overlay() -> void:
	var layout: Control = await _build_hud()
	var row: SiegeFeedback = _row_of(layout)

	assert_not_null(row, "the HUD mounts a Siege respawn row")
	if row == null:
		return
	assert_eq(row.get_parent(), layout.left_sidebar,
			"it is a ROW of the LeftSidebar VBox, which is what makes overlapping the "
			+ "battle log and the unit card structurally impossible")
	assert_eq(layout.left_sidebar.get_children().find(row), 1,
			"directly under the battle log -- a fallen squad member belongs with the "
			+ "running account of the battle")


func test_a_battle_that_is_not_a_siege_never_shows_it() -> void:
	# No controller mounted at all: Skirmish, Campaign, versus. The column must be the
	# column it always was, and a hidden BoxContainer child costs neither height nor the
	# VBox's separation.
	var layout: Control = await _build_hud()
	var row: SiegeFeedback = _row_of(layout)
	assert_false(row.visible, "no Siege, no respawn row")

	# Measured against a VISIBLE card: an invisible BoxContainer child is not laid out at
	# all, so its rect would say nothing about the column's spacing either way.
	layout.unit_info_panel._on_unit_selected(_make_unit("Vineweave"), Vector3.ZERO)
	await _settle()

	var log_rect: Rect2 = _rect_of(layout.battle_log)
	var card_top: float = layout.unit_info_panel.global_position.y
	gut.p("log bottom  : %.1f    card top: %.1f" % [log_rect.end.y, card_top])
	assert_almost_eq(card_top - log_rect.end.y, UILayoutManager.COLUMN_SEPARATION, 1.0,
			"the card sits exactly ONE column separation under the log -- the hidden row "
			+ "contributed neither height nor a second separation, so every non-Siege "
			+ "battle's left column is the one it always was")


func test_a_silenced_controller_shows_nothing_either() -> void:
	# SiegeController is installed once and silenced on every other map, so mere existence
	# must never be mistaken for "this is a Siege".
	var ctrl: SiegeControllerStub = _mount_controller()
	ctrl.active = false
	ctrl.down(ID_PETALFANG)
	var layout: Control = await _build_hud()
	await _activate_turn_system()
	await _settle()
	assert_false(_row_of(layout).visible,
			"a disarmed mode is not a Siege, whatever is left in its queue")


# =====================================================================================
#  The comeback
# =====================================================================================

func test_a_fallen_squad_unit_appears_on_the_row_with_its_clock() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	await _activate_turn_system()
	var row: SiegeFeedback = _row_of(layout)

	# A real death: the mode queues it, and the roster bus is what tells the HUD to look.
	ctrl.down(ID_PETALFANG)
	GameEvents.unit_eliminated.emit(_make_unit("Petalfang"), null)
	await _settle()

	gut.p("row text    : \"%s\"" % row.text())
	gut.p("row rect    : %s" % _rect_of(row))
	assert_true(row.visible, "losing a unit in Siege puts the comeback on screen")
	assert_true(row.text().contains("Petalfang"),
			"and names who went down, resolved through the same roster the rest of the UI "
			+ "names units from")
	assert_true(row.text().contains("respawns in 2 turns"),
			"with the mode's own respawn delay on it")


func test_the_row_is_drawn_wide_enough_for_the_line_it_carries() -> void:
	# The bug this guards: a Label with clip_text reports a 1px minimum, so a row that is
	# not laid out against its text is drawn as a stub with the text trimmed away.
	var ctrl: SiegeControllerStub = _mount_controller()
	ctrl.down(ID_PETALFANG)
	var layout: Control = await _build_hud()
	await _activate_turn_system()
	await _settle()
	var row: SiegeFeedback = _row_of(layout)

	var label: Label = row.get_node_or_null(SiegeFeedback.LABEL_NAME) as Label
	assert_not_null(label, "the row carries a label")
	if label == null:
		return
	var font: Font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var text_width: float = font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font_size")).x
	gut.p("label       : \"%s\"  text width=%.1f  row=%s"
			% [label.text, text_width, _rect_of(row)])

	assert_true(row.visible, "the row is on screen for this measurement")
	assert_true(row.size.x >= text_width,
			"the plate is at least as wide as the text it draws, so nothing is elided")
	assert_almost_eq(row.size.y, SiegeFeedback.ROW_HEIGHT, 4.0,
			"and it occupies the declared row height the column's budget spends")


func test_the_clock_counts_down_on_real_turn_ends() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	var system: TurnSystemBase = await _activate_turn_system()
	var row: SiegeFeedback = _row_of(layout)

	ctrl.down(ID_PETALFANG)
	GameEvents.unit_eliminated.emit(_make_unit("Petalfang"), null)
	await _settle()
	assert_true(row.text().contains("respawns in 2 turns"), "two rounds to go")

	# The mode's round clock advances, and the ONLY thing that tells the row to look again
	# is the ACTIVE turn system's own signal -- which fires on the enemy's turn too, unlike
	# PlayerManager's. A row that were not listening would still be reading "2 turns".
	ctrl.rounds = 1
	system.turn_ended.emit(null)
	await _settle()
	gut.p("after 1 round: \"%s\"" % row.text())
	assert_true(row.text().contains("respawns in 1 turn"),
			"a round elapsed, so one fewer is left -- on screen, not just in the model")
	assert_false(row.text().contains("1 turns"),
			"and the last beat before the comeback is singular")


func test_the_countdown_is_not_wired_to_playermanagers_turn_signals() -> void:
	# CONQUEST.md convention 2. PlayerManager's turn signals DO NOT FIRE on AI turns, so a
	# respawn clock hung off them freezes for most of a push mode's battle. Asserted by
	# reading LIVE connection lists rather than by emitting, because firing an autoload's
	# turn signals with no battle behind them would drive every other subscriber in the game.
	_mount_controller()
	var layout: Control = await _build_hud()
	var system: TurnSystemBase = await _activate_turn_system()
	var row: SiegeFeedback = _row_of(layout)

	for signal_name in ["player_turn_started", "player_turn_ended"]:
		for connection in PlayerManager.get_signal_connection_list(signal_name):
			assert_ne(connection["callable"].get_object(), row,
				"the respawn row is NOT listening to PlayerManager.%s" % signal_name)

	var listened: Array[String] = []
	for signal_name in ["turn_started", "turn_ended"]:
		for connection in system.get_signal_connection_list(signal_name):
			if connection["callable"].get_object() == row:
				listened.append(signal_name)
	gut.p("row listens to the active system's: %s" % ", ".join(listened))
	assert_eq(listened.size(), 2,
			"it rides the ACTIVE turn system's own turn_started and turn_ended instead")


func test_the_row_vanishes_the_moment_the_unit_walks_back_out() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	await _activate_turn_system()
	var row: SiegeFeedback = _row_of(layout)

	ctrl.down(ID_PETALFANG)
	GameEvents.unit_eliminated.emit(_make_unit("Petalfang"), null)
	await _settle()
	assert_true(row.visible, "down")

	# The mode returned it and cleared its own queue. The row follows the MODE, not a clock
	# of its own -- which is the whole reason it keeps no bookkeeping.
	ctrl.queue.clear()
	GameEvents.unit_spawned.emit(_make_unit("Petalfang"), true)
	await _settle()
	gut.p("after respawn: visible=%s text=\"%s\"" % [row.visible, row.text()])
	assert_false(row.visible,
			"a unit standing on the board is never listed as still waiting to respawn")


func test_extra_casualties_are_counted_and_the_tooltip_lists_them() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	await _activate_turn_system()
	var row: SiegeFeedback = _row_of(layout)

	ctrl.down(ID_PETALFANG)
	ctrl.down(ID_BLIGHTCAP)
	GameEvents.unit_eliminated.emit(_make_unit("Petalfang"), null)
	await _settle()

	gut.p("row text    : \"%s\"" % row.text())
	gut.p("tooltip     : \"%s\"" % row.tooltip_text.replace("\n", " | "))
	assert_true(row.text().contains("+1 more"), "the second casualty is counted, not crammed in")
	assert_true(row.tooltip_text.contains("Blightcap"), "and named in the tooltip")
	assert_eq(row.mouse_filter, Control.MOUSE_FILTER_PASS,
			"the row is hit-testable, or that tooltip could never be shown")
	assert_almost_eq(row.size.y, SiegeFeedback.ROW_HEIGHT, 4.0,
			"and two casualties are still ONE row -- the column's budget does not grow")


func test_the_enemys_losses_are_not_the_players_comeback() -> void:
	# Creeps never reach the queue at all (the mode drops them), so the one filter the HUD
	# owns is the SIDE -- a row that mixed both sides could not answer the one question it
	# exists for.
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	await _activate_turn_system()

	ctrl.down(ID_BLIGHTCAP, 1)
	GameEvents.unit_eliminated.emit(_make_unit("Blightcap"), null)
	await _settle()

	var row: SiegeFeedback = _row_of(layout)
	gut.p("row text    : \"%s\"  visible=%s" % [row.text(), row.visible])
	assert_false(row.visible, "the other side rebuilding is not the player's comeback")


# =====================================================================================
#  Creeps read as minor units
# =====================================================================================

func test_a_lane_creep_reads_as_background_in_the_battle_log() -> void:
	# Nothing else in the game tells an ally creep from a squad hero -- same world-space
	# HealthBar, same portrait entitlement, same turn-queue entry. In a mode that pushes a
	# wave down every lane every few rounds, the log is where that stops being cosmetic:
	# "Barkling was defeated" at full ally tint reads exactly like losing one of your own.
	_mount_controller()
	var layout: Control = await _build_hud()
	var log_panel: BattleLog = layout.battle_log

	var hero: Unit = _make_unit("Petalfang")
	var creep: Unit = _make_unit("Barkling")
	CaptureBase.mark_creep(creep)

	gut.p("hero tint   : %s" % log_panel._tint(hero))
	gut.p("creep tint  : %s" % log_panel._tint(creep))
	assert_eq(log_panel._tint(creep), BattleLog.DIM_COLOR,
			"a creep's lines are dimmed, so a wave arriving and dying reads as the "
			+ "background it is")
	assert_ne(log_panel._tint(hero), BattleLog.DIM_COLOR,
			"and a squad unit's do not -- otherwise the marker would say nothing")


func test_nothing_is_dimmed_in_a_battle_with_no_creeps() -> void:
	# The branch must be invisible outside Siege: no unit carries the mark, so every
	# existing battle's log is tinted exactly as it always was.
	var layout: Control = await _build_hud()
	assert_ne(layout.battle_log._tint(_make_unit("Petalfang")), BattleLog.DIM_COLOR,
			"an ordinary battle's log is untouched by the creep marker")


# =====================================================================================
#  The capture alarm
# =====================================================================================

func _announcer_text(layout: Control) -> String:
	var label: Label = layout.action_announcer._main_label
	return label.text if label != null else ""


func test_a_capture_starting_is_announced_through_the_existing_action_banner() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	var system: TurnSystemBase = await _activate_turn_system()

	ctrl.capturing = 1  # the AI side is standing on OUR base
	system.turn_started.emit(null)
	await _settle()

	gut.p("announcer   : \"%s\"" % _announcer_text(layout))
	assert_eq(_announcer_text(layout), SiegeFeedback.ANNOUNCE_ENEMY_CAPTURE,
			"the alarm lands on the ActionAnnouncer the player already reads every move on, "
			+ "not on a second toast layer")
	assert_true(layout.action_announcer.get_node("AnnouncerRoot").visible,
			"and it is actually on screen")


func test_the_alarm_names_which_way_the_capture_is_going() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	var system: TurnSystemBase = await _activate_turn_system()

	ctrl.capturing = 0  # our own side, on THEIR base
	system.turn_started.emit(null)
	await _settle()
	assert_eq(_announcer_text(layout), SiegeFeedback.ANNOUNCE_ALLY_CAPTURE,
			"a capture we are making reads as the opportunity it is, not as an alarm")


func test_the_alarm_fires_once_per_capture_not_once_per_turn() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	var layout: Control = await _build_hud()
	var system: TurnSystemBase = await _activate_turn_system()

	ctrl.capturing = 1
	system.turn_started.emit(null)
	await _settle()
	assert_eq(_announcer_text(layout), SiegeFeedback.ANNOUNCE_ENEMY_CAPTURE, "it fired")

	# Blank the banner ourselves, then keep the capture running for two more beats. Anything
	# that reappears is a re-fire.
	layout.action_announcer._main_label.text = ""
	system.turn_ended.emit(null)
	system.turn_started.emit(null)
	await _settle()
	gut.p("after 2 more beats: \"%s\"" % _announcer_text(layout))
	assert_eq(_announcer_text(layout), "",
			"a capture that is still running does not re-announce itself every turn")

	# Broken, then started again -- a NEW event, so the alarm re-arms.
	ctrl.capturing = -1
	system.turn_ended.emit(null)
	await _settle()
	ctrl.capturing = 1
	system.turn_started.emit(null)
	await _settle()
	gut.p("after re-arm : \"%s\"" % _announcer_text(layout))
	assert_eq(_announcer_text(layout), SiegeFeedback.ANNOUNCE_ENEMY_CAPTURE,
			"a capture broken and restarted is a new event and is announced again")


func test_a_battle_with_no_capture_running_is_never_interrupted() -> void:
	_mount_controller()
	var layout: Control = await _build_hud()
	var system: TurnSystemBase = await _activate_turn_system()

	system.turn_started.emit(null)
	system.turn_ended.emit(null)
	await _settle()
	assert_eq(_announcer_text(layout), "",
			"no capture, no banner -- the alarm is an event, not a status line")


# =====================================================================================
#  Capture PROGRESS is the banner's job, and it does it
# =====================================================================================

func test_the_objective_banner_carries_the_live_capture_progress_line() -> void:
	# This is a VERIFICATION, not a new surface: the whole reason SiegeFeedback draws no
	# progress of its own is that ObjectiveBanner re-derives every objective's
	# describe_progress on the ACTIVE turn system's beats. If that ever stops being true,
	# capture progress silently disappears from the game -- so it is pinned here.
	_mount_controller()
	var layout: Control = await _build_hud()
	var system: TurnSystemBase = await _activate_turn_system()

	var objective := CaptureObjectiveStub.new()
	layout.objective_banner.set_objectives([objective])
	await _settle()

	var label: Label = layout.objective_banner.get_node_or_null("ObjectiveLabel") as Label
	assert_not_null(label, "the banner draws a label")
	if label == null:
		return
	gut.p("banner idle : \"%s\"" % label.text)
	assert_true(label.text.contains("Capture the enemy base"),
			"the objective is on screen before anything is happening")

	objective.progressing = true
	system.turn_ended.emit(null)
	await _settle()

	gut.p("banner live : \"%s\"" % label.text)
	assert_true(label.text.contains("Capturing"),
			"and a capture in progress updates the SAME row, off the banner's existing "
			+ "refresh beats -- nothing here duplicates it")
	assert_true(label.text.contains("survive 1 turn"),
			"including the countdown the objective itself phrases")


# =====================================================================================
#  The post-match card
# =====================================================================================

## The summary screen, mounted but NOT revealed -- show_result() pauses the whole tree, and
## the two things under test here (which mode this was, and what its outcome line says) are
## resolved before any of that.
func _game_over() -> GameOverScreen:
	var screen: GameOverScreen = GAME_OVER.instantiate() as GameOverScreen
	add_child_autofree(screen)
	await get_tree().process_frame
	return screen


func test_a_capture_win_is_reported_as_a_capture_not_as_a_body_count() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	ctrl.captured = 0
	var screen: GameOverScreen = await _game_over()

	assert_eq(screen._mode_outcome_line(
				GameOverScreen.OUTCOME_VICTORY, GameOverScreen.SUBTITLE_VICTORY),
			GameOverScreen.SUBTITLE_SIEGE_VICTORY,
			"you took their base -- the card says so, not 'all enemies defeated'")

	screen._apply_mode_name()
	gut.p("mode label  : \"%s\" visible=%s" % [screen._mode_label.text, screen._mode_label.visible])
	assert_true(screen._mode_label.visible, "and the card names the mode that was played")
	assert_eq(screen._mode_label.text, "SIEGE",
			"read off the mode's own ruleset, not spelled again here")


func test_a_capture_loss_does_not_claim_your_forces_have_fallen() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	ctrl.captured = 1
	var screen: GameOverScreen = await _game_over()
	assert_eq(screen._mode_outcome_line(
				GameOverScreen.OUTCOME_DEFEAT, GameOverScreen.SUBTITLE_DEFEAT),
			GameOverScreen.SUBTITLE_SIEGE_DEFEAT,
			"a player whose squad is still standing must not be told it has fallen")


func test_a_siege_decided_by_a_wipe_keeps_the_ordinary_line() -> void:
	var ctrl: SiegeControllerStub = _mount_controller()
	ctrl.captured = -1  # nobody captured anything; the field was cleared instead
	var screen: GameOverScreen = await _game_over()
	assert_eq(screen._mode_outcome_line(
				GameOverScreen.OUTCOME_VICTORY, GameOverScreen.SUBTITLE_VICTORY),
			GameOverScreen.SUBTITLE_VICTORY,
			"the card never claims a base fell when none did")


func test_every_other_battles_summary_is_exactly_the_one_it_always_was() -> void:
	var screen: GameOverScreen = await _game_over()
	assert_eq(screen._mode_outcome_line(
				GameOverScreen.OUTCOME_VICTORY, GameOverScreen.SUBTITLE_VICTORY),
			GameOverScreen.SUBTITLE_VICTORY,
			"no live mode -- the shipped default, unchanged")
	screen._apply_mode_name()
	assert_false(screen._mode_label.visible,
			"and no mode line is added to a Skirmish's card")


# =====================================================================================
#  The 720p budget, with the row on screen
# =====================================================================================

func test_the_left_column_still_clears_the_terrain_card_with_the_respawn_row_up() -> void:
	# The worst case the column can be in: a unit selected (228px card), the battle log
	# EXPANDED (158px), and the respawn row visible (24px) -- which is the case this change
	# had to prove, because the row is spending the 46px of slack the column had.
	var ctrl: SiegeControllerStub = _mount_controller()
	ctrl.down(ID_PETALFANG)
	var layout: Control = await _build_hud()
	await _activate_turn_system()

	layout.unit_info_panel._on_unit_selected(_make_unit("Vineweave"), Vector3.ZERO)
	layout.battle_log._toggle_expanded()
	await _settle()
	await _settle()

	var row: SiegeFeedback = _row_of(layout)
	var log_rect: Rect2 = _rect_of(layout.battle_log)
	var row_rect: Rect2 = _rect_of(row)
	var card_rect: Rect2 = _rect_of(layout.unit_info_panel)
	var reserve_top: float = _vp().y - UILayoutManager.BOTTOM_RESERVE

	gut.p("log         : %s" % log_rect)
	gut.p("respawn row : %s" % row_rect)
	gut.p("unit card   : %s" % card_rect)
	gut.p("card bottom %.1f  vs terrain reserve top %.1f  -> %.1f px clear"
			% [card_rect.end.y, reserve_top, reserve_top - card_rect.end.y])

	assert_true(row.visible, "the row really is on screen for this measurement")
	assert_true(layout.battle_log.is_showing_scrollback(),
			"and the log really is expanded -- otherwise this is not the worst case")
	assert_false(log_rect.intersects(row_rect), "the log and the respawn row do not overlap")
	assert_false(row_rect.intersects(card_rect), "nor do the row and the unit card")
	assert_true(card_rect.end.y <= reserve_top + 0.5,
			"log + respawn row + card together still stop short of the terrain card's band")


func test_the_respawn_row_does_not_steal_the_battle_logs_budget() -> void:
	# _rebudget_left_column is deliberately untouched: the log is still handed
	# `usable - card_claim`, and the row's 24px comes out of the headroom that arithmetic
	# already left over. If the row ever started competing for the log's rows, the log would
	# fall back to its 30px chip while a unit is selected -- the exact regression the compact
	# battle card was built to fix.
	var ctrl: SiegeControllerStub = _mount_controller()
	ctrl.down(ID_PETALFANG)
	var layout: Control = await _build_hud()
	await _activate_turn_system()

	layout.unit_info_panel._on_unit_selected(_make_unit("Vineweave"), Vector3.ZERO)
	layout.battle_log._toggle_expanded()
	await _settle()
	await _settle()

	gut.p("log height  : %.1f  (full %.1f)"
			% [layout.battle_log.size.y, BattleLog.PANEL_HEIGHT])
	assert_true(_row_of(layout).visible, "the row is up for this measurement")
	assert_true(layout.battle_log.is_showing_scrollback(),
			"the log still shows its scrollback beside a selected unit AND the respawn row")
	assert_true(layout.battle_log.size.y >= BattleLog.MIN_EXPANDED_HEIGHT,
			"at no less than the height that makes an expanded log worth its rows")


# =====================================================================================
#  The stub cannot drift from the shipped mode
# =====================================================================================

func test_the_real_controller_still_answers_everything_this_hud_asks_it() -> void:
	# Without this, a rename in SiegeController would leave every test above green (the stub
	# still answers) while the live HUD went blank -- has-method guards fail SILENTLY, which
	# is exactly what makes them safe to ship and dangerous to test with.
	# A bare instance, never added to the tree (so _ready / the bus wiring never runs) and
	# autofreed, which is what keeps this off the orphan count -- tests/README rule 2.
	var controller: Node = autofree(SiegeController.new())
	for method in ["is_active", "rounds_elapsed", "ruleset", "respawn_queue",
			"capturing_by", "captured_by"]:
		assert_true(controller.has_method(method),
				"SiegeController still declares %s(), which the Siege HUD calls" % method)

	var rules := SiegeRuleset.new()
	assert_true(rules.has_method("respawn_delay"),
			"and its ruleset still answers respawn_delay(), the row's countdown")
	assert_true("display_name" in rules and "id" in rules,
			"and still carries the id + display name the summary card labels the mode with")
