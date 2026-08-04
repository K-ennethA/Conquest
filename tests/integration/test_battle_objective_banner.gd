extends GutTest

## The OBJECTIVE line as it is actually DRAWN, in the real booted battle HUD.
##
## WHY THIS SUITE EXISTS IN THIS SHAPE. The wording is pinned as pure statics in
## `unit/test_objective_banner.gd`; none of that proves a player can SEE it. This project
## has twice shipped a HUD element that passed a string-reading suite while the screen was
## wrong -- a chip laid out 11px wide with its text trimmed off, and a glyph the font
## cannot draw rendering as an empty box. So everything here mounts the shipped
## `GameUILayout.tscn` and asserts on the RENDERED tree:
##
##   * the row is mounted, visible, and drawn WIDE ENOUGH for the line it carries;
##   * a defeat-boss MAP puts its own objective on screen, read through the same
##     WinConditionLibrary the runtime scores;
##   * a survive objective really counts DOWN, driven by the ACTIVE turn system's
##     turn_ended -- and NOT by PlayerManager's, which does not fire on AI turns
##     (CONQUEST.md convention 2, the bug this wiring exists to avoid);
##   * the row does not collide with the turn chip above it or the ActionAnnouncer banner
##     below it, measured rather than eyeballed;
##   * a replay still shows it -- it is context, not transport chrome;
##   * and every character the top band prints is one the font can actually draw, which
##     covers the pause / settings buttons this change had to de-tofu as well.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")

const DESIGN := Vector2i(1280, 720)

var _prev_window_size: Vector2i

## Turn systems built by a test. Registered with the manager (which is an autoload, so it
## outlives the suite) and never parented, so this suite frees them itself.
var _systems: Array = []

## Scratch node standing in as `current_scene` while a turn system is activated:
## TurnSystemManager.switch_to_turn_system() walks the current scene looking for units to
## register, and a `-s script` run has no scene at all. Torn down in after_each.
var _scratch_scene: Node = null


# =====================================================================================
#  Fixtures
# =====================================================================================

## Stand-in for the battle's MapLoader: the banner asks the world manager for
## `map_loader.get_current_map()`, and that is the whole surface it uses.
class MapLoaderStub extends Node:
	var map: Resource = null

	func get_current_map() -> Resource:
		return map


## Stand-in for GameWorldManager, found the way the banner finds it: by group.
class WorldStub extends Node:
	var map_loader: Node = null


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func after_each() -> void:
	ReplayPlayback.end_playback()
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


# =====================================================================================
#  Mounting
# =====================================================================================

## Boot the real HUD and let every deferred re-fit settle.
func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for i in range(8):
		await get_tree().process_frame
	return layout


## Mount a fake battle world declaring [param conditions] as its map's authored
## objectives, BEFORE the HUD -- which is the real ordering (the world manager boots the
## map, then the HUD mounts on top of it) and the one the banner resolves against.
func _mount_map_with(conditions: Array[String]) -> void:
	var map := MapResource.new()
	map.map_name = "Objective Fixture"
	map.victory_conditions = conditions

	var loader := MapLoaderStub.new()
	loader.name = "MapLoaderStub"
	loader.map = map

	var world := WorldStub.new()
	world.name = "WorldStub"
	world.add_child(loader)
	world.map_loader = loader
	world.add_to_group("game_world_manager")
	add_child_autofree(world)
	await get_tree().process_frame


## A REAL turn system, registered and made active through TurnSystemManager -- so the
## banner subscribes through the same `turn_system_activated` signal a battle boot fires.
##
## [param speed_first] picks the OTHER shipped system, which matters in exactly one test:
## registering a second system of the same TYPE replaces it in the manager's slot and the
## manager FREES the instance it dropped (TurnSystemManager.register_turn_system), so a
## same-type switch leaves nothing to assert the old subscription against.
func _activate_turn_system(speed_first: bool = false) -> TurnSystemBase:
	if get_tree().current_scene == null:
		_scratch_scene = Node.new()
		_scratch_scene.name = "ObjectiveBannerScratchScene"
		get_tree().root.add_child(_scratch_scene)
		get_tree().current_scene = _scratch_scene
	var system: TurnSystemBase = \
			SpeedFirstTurnSystem.new() if speed_first else TraditionalTurnSystem.new()
	_systems.append(system)
	TurnSystemManager.register_turn_system(system)
	TurnSystemManager.switch_to_turn_system(system)
	await get_tree().process_frame
	return system


## Typed as the banner itself (rather than the Control the layout stores it in) so the
## calls below are statically resolved -- an untyped `banner.set_objectives()` would be an
## unsafe call this suite has no reason to make.
func _banner_of(layout: Control) -> ObjectiveBanner:
	return layout.objective_banner as ObjectiveBanner


func _label_of(banner: Control) -> Label:
	return banner.get_node_or_null("ObjectiveLabel") as Label


func _rect_of(node: Control) -> Rect2:
	return Rect2(node.global_position, node.size)


# =====================================================================================
#  It is on screen
# =====================================================================================

func test_the_objective_row_is_mounted_in_the_top_band_and_visible() -> void:
	var layout: Control = await _build_hud()
	var banner: ObjectiveBanner = _banner_of(layout)

	assert_not_null(banner, "the HUD mounts an objective row")
	if banner == null:
		return
	assert_true(banner.is_visible_in_tree(), "and it is drawn, not built and hidden")
	assert_eq(banner.get_parent(), layout.center_top_container,
			"it is a ROW of the top-centre column, which is what makes overlapping the turn "
			+ "chip structurally impossible rather than a tuned offset")


func test_the_row_is_drawn_wide_enough_for_the_line_it_carries() -> void:
	# The bug this guards: a Label with clip_text reports a 1px minimum, so a row that does
	# not fit itself to its text is drawn as a stub with the objective trimmed away.
	var layout: Control = await _build_hud()
	var banner: ObjectiveBanner = _banner_of(layout)
	var label: Label = _label_of(banner)
	assert_not_null(label, "the row carries a label")
	if label == null:
		return

	var font: Font = label.get_theme_font("font")
	if font == null:
		font = ThemeDB.fallback_font
	var text_width: float = font.get_string_size(
			label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			label.get_theme_font_size("font_size")).x
	gut.p("objective   : \"%s\"" % label.text)
	gut.p("row rect    : %s   text width=%.1f" % [_rect_of(banner), text_width])

	assert_gt(banner.size.x, text_width,
			"the plate is wider than the text it draws, so nothing is elided")
	assert_almost_eq(banner.size.y, ObjectiveBanner.ROW_HEIGHT, 8.0,
			"and it occupies the declared row height the top band budgets against")


func test_a_battle_with_no_map_still_says_what_winning_is() -> void:
	var layout: Control = await _build_hud()
	var label: Label = _label_of(_banner_of(layout))
	assert_eq(label.text, ObjectiveBanner.PREFIX + ObjectiveBanner.FALLBACK_TEXT,
			"no map, no rules -- the honest floor is still on screen, not a blank row")


# =====================================================================================
#  The map's own objective
# =====================================================================================

func test_a_defeat_boss_map_puts_its_objective_on_screen() -> void:
	var conditions: Array[String] = ["Defeat Boss"]
	await _mount_map_with(conditions)
	var layout: Control = await _build_hud()
	var label: Label = _label_of(_banner_of(layout))

	gut.p("drawn line  : \"%s\"" % label.text)
	assert_eq(label.text, ObjectiveBanner.PREFIX + "Defeat the boss",
			"the line the map authored, compiled by the library the runtime scores")


func test_a_multi_objective_map_shows_one_and_counts_the_rest_in_its_tooltip() -> void:
	var conditions: Array[String] = ["Defeat Boss", "Destroy Enemy Base"]
	await _mount_map_with(conditions)
	var layout: Control = await _build_hud()
	var banner: ObjectiveBanner = _banner_of(layout)
	var label: Label = _label_of(banner)

	gut.p("drawn line  : \"%s\"" % label.text)
	gut.p("tooltip     : \"%s\"" % banner.tooltip_text)
	assert_true(label.text.contains("Defeat the boss"), "the primary objective is shown")
	assert_true(label.text.contains("+1 more"), "and the other is counted, not crammed in")
	assert_true(banner.tooltip_text.contains("Destroy the enemy base"),
			"the objective that did not fit is in the tooltip")
	assert_eq(banner.mouse_filter, Control.MOUSE_FILTER_PASS,
			"and the row is hit-testable, or that tooltip could never be shown")


# =====================================================================================
#  It counts down, off the RIGHT signal
# =====================================================================================

func test_a_survive_objective_counts_down_on_real_turn_ends() -> void:
	var layout: Control = await _build_hud()
	var banner: ObjectiveBanner = _banner_of(layout)
	var system: TurnSystemBase = await _activate_turn_system()

	var survive := SurviveTurns.new()
	survive.turns = 6
	survive.faction = WinConditionLibrary.HUMAN_FACTION
	banner.set_objectives([survive])
	await get_tree().process_frame

	var label: Label = _label_of(banner)
	assert_eq(label.text, ObjectiveBanner.PREFIX + "Survive 6 more turns",
			"nothing survived yet, so the whole target is still to go")

	# The real signal, emitted by the ACTIVE turn system.
	system.turn_ended.emit(null)
	system.turn_ended.emit(null)
	await get_tree().process_frame

	gut.p("after 2 ends: \"%s\"" % label.text)
	assert_eq(label.text, ObjectiveBanner.PREFIX + "Survive 4 more turns",
			"two turns ended, so two fewer are left -- on screen, not just in the model")
	assert_eq(banner.turns_elapsed(), 2, "and the row counted both of them")


func test_the_countdown_is_not_wired_to_playermanagers_turn_signals() -> void:
	# CONQUEST.md convention 2. PlayerManager's turn signals DO NOT FIRE on AI turns, so a
	# countdown hung off them freezes the moment the enemy starts acting -- the player
	# watches "Survive 6 more turns" sit still for the whole battle. Asserted by reading
	# the LIVE connection lists of the mounted banner rather than by emitting, because
	# firing an autoload's turn signals with no battle behind them would drive every other
	# subscriber in the game as a side effect.
	var layout: Control = await _build_hud()
	var banner: ObjectiveBanner = _banner_of(layout)
	var system: TurnSystemBase = await _activate_turn_system()

	for signal_name in ["player_turn_started", "player_turn_ended"]:
		for connection in PlayerManager.get_signal_connection_list(signal_name):
			assert_ne(connection["callable"].get_object(), banner,
				"the objective row is NOT listening to PlayerManager.%s" % signal_name)

	var listened: Array[String] = []
	for signal_name in ["turn_started", "turn_ended"]:
		for connection in system.get_signal_connection_list(signal_name):
			if connection["callable"].get_object() == banner:
				listened.append(signal_name)
	gut.p("banner listens to the active system's: %s" % ", ".join(listened))
	assert_eq(listened.size(), 2,
			"it rides the ACTIVE turn system's own turn_started and turn_ended instead")


func test_a_fresh_turn_system_restarts_the_countdown() -> void:
	var layout: Control = await _build_hud()
	var banner: ObjectiveBanner = _banner_of(layout)
	var first: TurnSystemBase = await _activate_turn_system()

	var survive := SurviveTurns.new()
	survive.turns = 6
	banner.set_objectives([survive])
	first.turn_ended.emit(null)
	await get_tree().process_frame
	assert_eq(banner.turns_elapsed(), 1, "the first battle's turn counted")

	# The OTHER shipped system, so the manager keeps both instances alive (see
	# _activate_turn_system) and "the old one was really dropped" is assertable -- and so
	# that this is the switch a real session makes: Traditional -> Speed First.
	var second: TurnSystemBase = await _activate_turn_system(true)
	await get_tree().process_frame
	assert_eq(banner.turns_elapsed(), 0, "a new battle starts the countdown over")

	# And the OLD system is no longer listened to, or the two would double-count.
	first.turn_ended.emit(null)
	await get_tree().process_frame
	assert_eq(banner.turns_elapsed(), 0, "the replaced system was dropped, not left live")
	second.turn_ended.emit(null)
	await get_tree().process_frame
	assert_eq(banner.turns_elapsed(), 1, "and the active one is the one being counted")


# =====================================================================================
#  Placement: measured, not eyeballed
# =====================================================================================

func test_the_objective_row_never_overlaps_the_turn_chip() -> void:
	var conditions: Array[String] = ["Defeat Boss"]
	await _mount_map_with(conditions)
	var layout: Control = await _build_hud()

	var row: Rect2 = _rect_of(_banner_of(layout))
	var chip: Rect2 = _rect_of(layout.turn_indicator)
	gut.p("turn chip   : %s" % chip)
	gut.p("objective   : %s" % row)

	assert_false(row.intersects(chip), "the objective row and the turn chip are disjoint")
	assert_true(row.position.y >= chip.end.y,
			"the objective hangs UNDER the chip -- they are siblings in the top column, so "
			+ "the container owns this arithmetic")


func test_the_action_banner_still_parks_below_the_whole_top_bar() -> void:
	# The row grows the TopBar, and ActionAnnouncer already measures the LIVE bar
	# (banner_top of the measured bar bottom). Adding a row therefore pushes the action
	# banner down for free -- but only if the bar really did grow, which is what this
	# measures.
	var conditions: Array[String] = ["Defeat Boss"]
	await _mount_map_with(conditions)
	var layout: Control = await _build_hud()

	var bar: Control = layout.top_bar
	var bar_bottom: float = bar.global_position.y + bar.size.y
	var row: Rect2 = _rect_of(_banner_of(layout))
	var announcer_top: float = ActionAnnouncer.banner_top(bar_bottom)

	gut.p("top bar     : bottom=%.1f height=%.1f" % [bar_bottom, bar.size.y])
	gut.p("objective   : %s" % row)
	gut.p("action bnr  : top=%.1f" % announcer_top)

	assert_true(row.end.y <= bar_bottom + 1.0,
			"the objective row is INSIDE the top bar, so the bar's measured bottom already "
			+ "accounts for it")
	assert_gt(announcer_top, row.end.y,
			"and the action banner starts below the objective row, never over it")
	assert_gt(bar.size.y, ObjectiveBanner.ROW_HEIGHT,
			"the bar measures the chip AND the row, not just one of them")


func test_the_whole_top_band_still_fits_the_720p_window() -> void:
	var conditions: Array[String] = ["Defeat Boss", "Destroy Enemy Base"]
	await _mount_map_with(conditions)
	var layout: Control = await _build_hud()

	var viewport: Vector2 = get_viewport().get_visible_rect().size
	var row: Rect2 = _rect_of(_banner_of(layout))
	gut.p("viewport    : %s" % viewport)
	gut.p("objective   : %s" % row)

	assert_true(row.position.x >= 0.0 and row.end.x <= viewport.x,
			"the row is inside the window horizontally, even on a two-objective map")
	assert_true(row.size.x <= ObjectiveBanner.MAX_WIDTH + 1.0,
			"and it can never stretch the top bar across the whole screen")


# =====================================================================================
#  Replays
# =====================================================================================

func test_a_replay_still_shows_the_objective() -> void:
	# The transport chrome (ReplayHUD) is a control surface and belongs only to a watcher;
	# the objective is CONTEXT -- "what was this player trying to do?" is exactly what a
	# watcher needs -- so it is never hidden.
	ReplayPlayback.begin_playback()
	var conditions: Array[String] = ["Defeat Boss"]
	await _mount_map_with(conditions)
	var layout: Control = await _build_hud()

	var banner: ObjectiveBanner = _banner_of(layout)
	assert_true(banner.is_visible_in_tree(), "the objective line survives into a replay")
	assert_eq(_label_of(banner).text, ObjectiveBanner.PREFIX + "Defeat the boss",
			"and it still says what the recorded player was trying to do")


# =====================================================================================
#  Glyphs the top band prints
# =====================================================================================

## Every character the mounted top band puts on screen from a self-styled control: the
## objective line, and the two 44px chrome buttons beside it.
func _top_band_strings(layout: Control) -> Array[String]:
	return [
		_label_of(_banner_of(layout)).text,
		layout.pause_button.text,
		layout.settings_button.text,
	]


func test_every_character_the_top_band_prints_is_one_the_font_can_draw() -> void:
	# The tofu pin. ⚑ (banner), ⏸ (pause) and ⚙ (settings) all drew as empty boxes in
	# Godot's default font -- see the probe table in unit/test_status_feedback.gd. This is
	# the assertion that stops any of the three coming back.
	var layout: Control = await _build_hud()
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "there is a fallback font to measure against")
	if font == null:
		return

	for text in _top_band_strings(layout):
		for i in range(text.length()):
			var code: int = text.unicode_at(i)
			if code == 32:
				continue
			assert_true(font.has_char(code),
				"the top band's \"%s\" is drawable ('%s' U+%04X)" % [text, text[i], code])


func test_the_pause_and_settings_marks_fit_inside_their_44px_squares() -> void:
	# The other half of the glyph decision: a mark the font CAN draw is still wrong if it
	# overflows the touch target. Both buttons are 44x44 with a 22px font.
	var layout: Control = await _build_hud()
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return

	for button in [layout.pause_button, layout.settings_button]:
		var size: int = button.get_theme_font_size("font_size")
		var width: float = font.get_string_size(
				button.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		gut.p("%-14s: '%s' width@%dpx=%.1f  button=%s"
				% [button.name, button.text, size, width, button.size])
		assert_gt(width, 0.0, "%s really draws something" % button.name)
		assert_lt(width, button.size.x,
				"%s's mark fits inside its own square" % button.name)
		assert_false(button.tooltip_text.is_empty(),
				"%s still says in words what it does" % button.name)
