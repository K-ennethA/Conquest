extends GutTest

## Fire-Emblem board UX pieces: objective wording, forecast matchup chips, the
## overlay pool / path arrow, the animator's walk route, fast-forward pacing and
## the map menu's pages. Headless: no GameWorld scene is loaded.

class MockOwner extends RefCounted:
	var id: int = 0


class MockUnit extends Node3D:
	var owner_player = null
	var hp: int = 10
	var element: StringName = &""
	var profile: MovementProfile = null
	func is_alive() -> bool:
		return hp > 0
	func get_movement_profile():
		return profile


# --- ObjectiveText -------------------------------------------------------------------

func test_chip_text_per_condition() -> void:
	assert_eq(ObjectiveText.chip_text(WinConditionLibrary.build_rules(["Eliminate All Enemies"])), "Rout the enemy")
	assert_eq(ObjectiveText.chip_text(WinConditionLibrary.build_rules(["Defeat Boss"])), "Defeat the boss")
	assert_eq(ObjectiveText.chip_text(WinConditionLibrary.build_rules(["Survive 8 Turns"]), 3), "Survive 3/8 turns")
	assert_eq(ObjectiveText.chip_text(WinConditionLibrary.build_rules(["Seize 7,5"])), "Seize the throne")
	assert_eq(ObjectiveText.chip_text(null), "")


func test_survive_progress_is_clamped() -> void:
	var rules := WinConditionLibrary.build_rules(["Survive 4 Turns"])
	assert_eq(ObjectiveText.chip_text(rules, 9), "Survive 4/4 turns")
	assert_eq(ObjectiveText.chip_text(rules, -2), "Survive 0/4 turns")


func test_multi_objective_joins_and_details() -> void:
	var rules := WinConditionLibrary.build_rules(["Defeat Boss", "Seize (2, 3)"])
	assert_eq(ObjectiveText.chip_text(rules), "Defeat the boss & Seize the throne")
	var lines := ObjectiveText.detail_lines(rules)
	assert_eq(lines[0], "Victory: Defeat the boss")
	assert_eq(lines[1], "  and Seize the throne at (2, 3)")
	assert_eq(lines[lines.size() - 1], "Defeat: Lose all of your units")


# --- Forecast chips ------------------------------------------------------------------

func _move(element: StringName) -> MoveResource:
	var m := MoveResource.new()
	m.element = element
	m.targeting = TargetingPattern.new()
	m.effects = [DamageEffect.new()]
	return m


func test_matchup_chips_effectiveness_and_height() -> void:
	var grid := Grid.new()
	grid.size = Vector3(6, 0, 6)
	var a := MockUnit.new()
	var d := MockUnit.new()
	autofree(a)
	autofree(d)
	d.element = ElementChart.NATURE
	a.position = Cells.cell_to_world(Vector3i(1, 1, 1))
	d.position = Cells.cell_to_world(Vector3i(2, 1, 0))
	var board := BoardAdapter.new(grid, [a, d])
	var chips := CombatForecastPanel.matchup_chips(a, d, _move(ElementChart.FIRE), board)
	assert_eq(chips["type"], "▲ Effective")
	assert_true(chips["type_good"])
	assert_eq(chips["height"], "▲ High ground")
	var chips2 := CombatForecastPanel.matchup_chips(d, a, _move(ElementChart.WIND), board)
	assert_eq(chips2["type"], "", "unelemented defender: neutral, no chip")
	assert_eq(chips2["height"], "▼ Low ground")
	assert_false(chips2["height_good"])
	# element_chart.tres: an element resists itself (fire into water is neutral in the merged chart).
	d.element = ElementChart.FIRE
	assert_eq(CombatForecastPanel.matchup_chips(a, d, _move(ElementChart.FIRE), null)["type"], "▼ Resisted")
	assert_eq(CombatForecastPanel.matchup_chips(a, d, _move(ElementChart.FIRE), null)["height"], "", "no board, no height chip")


# --- Overlay pool / arrow ------------------------------------------------------------

func test_cell_overlay_pool_reuses_meshes_and_sits_on_floor() -> void:
	var parent := Node3D.new()
	add_child_autofree(parent)
	var pool := CellOverlayPool.new(parent, CellOverlayPool.make_material(Color.RED), 0.2)
	pool.show_cells([Vector3(1, 0, 1), Vector3(2, 1, 1)])
	assert_eq(pool.count(), 2)
	assert_eq(parent.get_child_count(), 2)
	var upper: MeshInstance3D = null
	for c in parent.get_children():
		if c.visible and c.position.y > 1.0:
			upper = c
	assert_not_null(upper, "floor-1 quad is raised to its floor")
	assert_almost_eq(upper.position.y, Cells.floor_y(1) + 0.2, 0.001)
	pool.show_cells([Vector3i(3, 3, 0)])  # Vector3i cells are accepted too
	assert_eq(pool.count(), 1)
	assert_true(pool.has_cell(Vector3(3, 0, 3)))
	pool.clear()
	pool.show_cells([Vector3(0, 0, 0), Vector3(1, 0, 0)])
	assert_eq(parent.get_child_count(), 2, "hidden quads are reused, not re-created")


func test_path_arrow_pieces_follow_the_path() -> void:
	var arrow := PathArrow.new()
	add_child_autofree(arrow)
	arrow.show_path([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(2, 1, 0)])
	assert_true(arrow.is_showing())
	var visible_count := 0
	for c in arrow.get_children():
		if c.visible:
			visible_count += 1
	# 2 joints x (disc + outline) + 2 segments x (box + outline) + head x 2.
	assert_eq(visible_count, 10)
	arrow.show_path([Vector3(0, 0, 0)])
	assert_false(arrow.is_showing())
	for c in arrow.get_children():
		assert_false(c.visible, "a one-cell path hides every piece")


# --- Walk route -------------------------------------------------------------------------

func test_walk_path_routes_around_an_enemy_and_through_an_ally() -> void:
	var grid := Grid.new()
	grid.size = Vector3(5, 0, 3)
	var p0 := MockOwner.new()
	var p1 := MockOwner.new()
	p1.id = 1
	var mover := MockUnit.new()
	var ally := MockUnit.new()
	var foe := MockUnit.new()
	for u in [mover, ally, foe]:
		autofree(u)
	mover.owner_player = p0
	ally.owner_player = p0
	foe.owner_player = p1
	mover.profile = MovementProfile.create(&"g", "g", CombatTypes.MovementKind.GROUND, 4, MovementProfile.Shape.ORTHOGONAL)
	# Mover already relocated to (3,1) (UnitAnimator runs after the board move).
	mover.position = Cells.cell_to_world(Vector3i(3, 1, 0))
	ally.position = Cells.cell_to_world(Vector3i(1, 1, 0))
	foe.position = Cells.cell_to_world(Vector3i(2, 1, 0))
	var board := BoardAdapter.new(grid, [mover, ally, foe])
	var animator = load("res://game/visuals/UnitAnimator.gd").new()
	autofree(animator)
	var route: Array[Vector3i] = animator.resolve_walk_path(mover, Vector3i(0, 1, 0), board)
	assert_eq(route[0], Vector3i(0, 1, 0))
	assert_eq(route[route.size() - 1], Vector3i(3, 1, 0))
	assert_true(route.has(Vector3i(1, 1, 0)), "walks through the ally")
	assert_false(route.has(Vector3i(2, 1, 0)), "detours around the enemy")
	assert_eq(route.size(), 6, "0,1 -> 1,1 -> (1,0|1,2) -> (2,..) -> (3,..) -> 3,1")


# --- Fast-forward --------------------------------------------------------------------

func test_fast_forward_divides_ai_beats() -> void:
	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	var gs = get_tree().root.get_node("GameSettings")
	gs.set_fast_forward(false)
	var wait := driver._effective_wait()
	var dwell := driver._effective_dwell()
	var move_dwell := driver._effective_move_dwell()
	gs.set_fast_forward(true)
	assert_almost_eq(driver._effective_wait(), wait / GameSettings.FAST_FORWARD_MULTIPLIER, 0.0001)
	assert_almost_eq(driver._effective_dwell(), dwell / GameSettings.FAST_FORWARD_MULTIPLIER, 0.0001)
	assert_almost_eq(driver._effective_move_dwell(), move_dwell / GameSettings.FAST_FORWARD_MULTIPLIER, 0.0001)
	assert_almost_eq(gs.scaled_time(1.0) * GameSettings.FAST_FORWARD_MULTIPLIER, 1.0 / clampf(gs.battle_speed, 0.5, 3.0) if gs.animations_enabled else 0.0, 0.0001)
	gs.set_fast_forward(false)
	assert_almost_eq(driver._effective_wait(), wait, 0.0001, "releasing restores normal pacing")


func test_fast_forward_shortens_the_beat_in_flight() -> void:
	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	var gs = get_tree().root.get_node("GameSettings")
	gs.set_fast_forward(false)
	driver._timer.stop()
	driver._timer.start(2.0)
	gs.set_fast_forward(true)
	assert_lt(driver._timer.time_left, 0.6, "the running 2s beat drops to ~0.5s")
	gs.set_fast_forward(false)


# --- Map menu -------------------------------------------------------------------------

func test_map_menu_pages_and_back() -> void:
	var menu := MapMenu.new()
	add_child_autofree(menu)
	menu.open()
	assert_true(menu.is_open())
	assert_eq(menu.button_texts(), PackedStringArray(["Units", "Objective", "Encyclopedia", "Settings", "End Turn", "Return to Title"]))
	menu.show_page(MapMenu.Page.OBJECTIVE)
	await get_tree().process_frame
	assert_eq(menu.button_texts(), PackedStringArray(["Back"]))
	menu.show_page(MapMenu.Page.CONFIRM_TITLE)
	await get_tree().process_frame
	assert_eq(menu.button_texts(), PackedStringArray(["Return to Title", "Cancel"]))
	assert_true(InputActions.gameplay_input_blocked(get_tree()), "board input is blocked while open")
	menu.close()
	assert_false(menu.is_open())
	assert_false(InputActions.gameplay_input_blocked(get_tree()))


func test_map_menu_end_turn_is_refused_off_the_local_turn() -> void:
	# No active turn system / players in the unit-test tree: nobody is the local
	# human, so End Turn must never fire and the menu may not open.
	var menu := MapMenu.new()
	add_child_autofree(menu)
	assert_false(menu.can_open())
	menu._on_end_turn()
	assert_false(menu.is_open(), "the End Turn confirm is not even offered")
