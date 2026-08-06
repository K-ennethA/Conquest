extends GutTest

## CANTO on the REAL screen: Duskmaw's Shadow Dash, driven through the mounted
## GameUILayout's own UnitActionsPanel and UnitActionMenu, against a live board and a live
## turn system.
##
## WHY THIS SUITE IS MOUNTED RATHER THAN HELPER-LEVEL. The shipped defect was invisible to
## every non-mounted test: the Unit's own flags said "you may move again", and only the
## PANEL (asking the turn system `can_unit_act`) and the turn system's acted bookkeeping
## disagreed -- so the movement range went dark and the click on a reachable cell was
## refused while every unit-level assertion stayed green. This suite therefore asserts what
## the booted screen actually renders: the panel's command state, the tiles it published,
## and the literal buttons on the contextual action menu.
##
## THE RULE UNDER TEST (the user's decision): "they shouldn't be able to attack after
## dashing, simply move". After a dash the unit is done ACTING -- the action menu offers no
## moves at all -- but owes exactly ONE MOVEMENT, taken on a stride shortened by 2.

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Shadow Dash's slot in Duskmaw's authored moveset.
const DASH_SLOT: int = 3
## A throwaway enemy: one melee strike, no dash, nothing that could confuse the AI test.
const FODDER_ID: StringName = &"test_canto_fodder"

## Untyped on purpose (tests/README rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.set_setting().
var _guard

var _map_root: Node3D
var _prev_grid_size: Vector3


## The shared Grid resource, reached through a FUNCTION rather than CombatServices.GRID
## directly: GDScript refuses `SomeConst.size = ...` ("cannot assign a new value to a
## constant") even though the resource behind it is perfectly mutable -- which is exactly
## what a map load does to it (MapLoader._sync_grid_size).
func _grid() -> Grid:
	return CombatServices.GRID


func before_each() -> void:
	CombatServices.clear()
	_map_root = null
	_guard = Guard.new()
	_guard.set_setting("auto_end_turn", true)
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	_guard.set_setting("ai_difficulty", BotController.Difficulty.NORMAL)
	# The shared Grid resource is 5x5 by default (a map load resizes it); a dash needs a
	# lane plus somewhere to land, so widen it and put it back afterwards.
	_prev_grid_size = _grid().size
	_grid().size = Vector3(10, 0, 10)
	CharacterLibrary._cache[FODDER_ID] = _make_fodder()


func after_each() -> void:
	TurnSystemManager.active_turn_system = null
	CombatServices.clear()
	_grid().size = _prev_grid_size
	_map_root = null
	_guard.restore()
	CharacterLibrary.clear_cache()


# --- Fixtures ----------------------------------------------------------------

func _make_fodder() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = FODDER_ID
	c.display_name = "Fodder"
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = 200
	c.base_attack = 5
	c.base_defense = 8
	c.base_magic = 4
	c.base_magic_defense = 8
	c.base_speed = 4
	c.base_movement = 2
	c.attack_range = 1
	return c


func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(_grid(), []).cell_to_world(cell)


func _spawn(character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = character  # before add_child, so _ready() builds stats from it
	unit.position = _cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


## Board + turn system + the REAL HUD. Duskmaw stands at (1,1) with two enemies lined up
## east of it, so Shadow Dash pierces both and lands on the free cell beyond.
## [param duskmaw_is_ai] flips which side owns it (the AI-driver test).
## Returns {} -- a clean skip signal -- when the roster or the board is unavailable.
func _boot(duskmaw_is_ai: bool = false) -> Dictionary:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)

	var human := Player.new(0, "Human")
	var ai := Player.new(1, "AI")
	ai.is_ai = true

	var duskmaw := _spawn(&"monster", Vector2i(1, 1), ai if duskmaw_is_ai else human)
	var near := _spawn(FODDER_ID, Vector2i(2, 1), human if duskmaw_is_ai else ai)
	var far := _spawn(FODDER_ID, Vector2i(3, 1), human if duskmaw_is_ai else ai)
	if duskmaw == null or near == null or far == null:
		return {}

	await get_tree().process_frame
	CombatServices.rebuild(_map_root)
	if CombatServices.board() == null:
		return {}

	var ts := TraditionalTurnSystem.new()
	add_child_autofree(ts)
	# Duskmaw's owner is registered FIRST so the battle opens on its turn either way.
	ts.register_player(ai if duskmaw_is_ai else human)
	ts.register_player(human if duskmaw_is_ai else ai)
	ts.start_turn_system()
	TurnSystemManager.active_turn_system = ts

	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for _i in range(4):
		await get_tree().process_frame

	return {
		"duskmaw": duskmaw,
		"near": near,
		"far": far,
		"human": human,
		"ai": ai,
		"ts": ts,
		"board": CombatServices.board(),
		"panel": layout.unit_actions_panel,
	}


## Resolve Shadow Dash through the PANEL's own command path -- pick the move, then click a
## legal aim cell -- which is exactly what the player does and therefore what the canto
## re-entry has to survive.
func _dash_through_the_panel(panel, duskmaw: Unit) -> void:
	panel._on_unit_selected(duskmaw, duskmaw.global_position)
	await get_tree().process_frame
	panel._on_move_selected(DASH_SLOT)
	# Aim at the first body in the lane (distance 1, inside the move's 1..3 reach).
	panel.handle_move_target_selected(Vector3(2, 0, 1))
	for _i in range(2):
		await get_tree().process_frame


## Every button label the mounted action menu is currently drawing, in row order.
func _menu_buttons(panel) -> Array:
	var out: Array = []
	# Untyped: `panel` is a Variant (the layout exposes it as a plain Control), so `:=`
	# has nothing to infer the node's type from.
	var card = panel.action_menu.get_node_or_null("Card")
	if card == null:
		return out
	_collect_buttons(card, out)
	return out


func _collect_buttons(node: Node, out: Array) -> void:
	for child in node.get_children():
		if child is Button:
			out.append(String((child as Button).text))
		_collect_buttons(child, out)


## The cells MovementResolver says [param unit] can reach right now, as the
## Vector3(col, 0, row) grid coords the panel publishes.
func _reachable_tiles(unit: Unit, board) -> Array[Vector3]:
	var cells: Array[Vector2i] = MovementResolver.new().reachable_cells(
		board.cell_of(unit), unit.get_movement_profile(), board, unit)
	var out: Array[Vector3] = []
	for c in cells:
		out.append(Vector3(c.x, 0, c.y))
	return out


# ===========================================================================
# The dash leaves the screen in MOVEMENT-ONLY selection
# ===========================================================================

func test_the_dash_lands_and_leaves_the_unit_under_canto() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]

	await _dash_through_the_panel(s["panel"], duskmaw)

	assert_eq(s["board"].cell_of(duskmaw), Vector2i(4, 1),
		"the dash ran through both bodies and landed on the free cell beyond")
	assert_true(duskmaw.has_canto(), "and left the unit owing exactly one movement")
	assert_false(duskmaw.can_act(), "it has spent its action -- no second strike")
	assert_true(duskmaw.can_move(), "but it may still MOVE")


func test_the_screen_stays_on_the_unit_with_its_movement_range_lit() -> void:
	# The reported bug, from the player's side: after the dash the range went dark and the
	# unit could not be sent anywhere. The panel must instead drop straight back into
	# movement-only selection rather than closing the command loop.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]

	await _dash_through_the_panel(panel, duskmaw)

	assert_eq(panel.get_selected_unit(), duskmaw,
		"the unit is still selected -- the command loop did not close on it")
	assert_eq(panel.get_command_state(), UnitActionsPanel.CommandState.UNIT_SELECTED,
		"and the panel is back in plain selection, awaiting a destination click")
	assert_false(panel.movement_range_tiles.is_empty(),
		"REGRESSION: the movement range was published EMPTY, so every reachable cell " +
		"read as unreachable and the click was refused")
	assert_eq(panel.movement_range_tiles, _reachable_tiles(duskmaw, s["board"]),
		"and it is exactly the resolver's reachable set from the landing cell")


func test_the_canto_range_is_the_shortened_two_cell_leash() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]
	var base_movement: int = duskmaw.get_base_stat("movement")

	await _dash_through_the_panel(s["panel"], duskmaw)

	assert_eq(duskmaw.get_stat("movement"), base_movement - 2,
		"Void Surge pays for the free step with exactly 2 movement")

	# THE CANTO STEP IS WORTH (stat - 2) CELLS, and that is now literally what the board
	# hands over. The -2 used to be applied to the shared profile's range-3 instead of to
	# the character's own stride, so a 5-movement Duskmaw took its canto on a ONE-cell
	# leash. Measured as a distance off the landing cell rather than as a cell count, so it
	# says what the leash IS rather than merely that it shrank.
	var board = s["board"]
	var landing: Vector2i = board.cell_of(duskmaw)
	var leash: int = 0
	for tile in s["panel"].movement_range_tiles:
		var cell := Vector2i(int(round(tile.x)), int(round(tile.z)))
		leash = maxi(leash, absi(cell.x - landing.x) + absi(cell.y - landing.y))
	assert_eq(leash, base_movement - 2,
		"the canto leash is the DEBUFFED STAT (%d), not the shared profile's range"
			% [base_movement - 2])

	# And the debuff is genuinely visible in the tiles the screen lit: a (stat-2) flood on
	# open ground reaches strictly fewer cells than a full-stat one.
	var shortened: int = s["panel"].movement_range_tiles.size()
	# Untyped: get_status_controller() is declared -> Node, and remove_status() is not a
	# member of Node (the same reason Unit's own accessors keep their handles untyped).
	var controller = duskmaw.get_status_controller()
	controller.remove_status(&"void_surge")
	var unshortened: int = _reachable_tiles(duskmaw, s["board"]).size()
	assert_lt(shortened, unshortened,
		"and the range the player is offered is genuinely smaller for it (%d vs %d)"
			% [shortened, unshortened])


# ===========================================================================
# The action menu offers MOVEMENT ONLY
# ===========================================================================

func test_the_action_menu_offers_no_moves_at_all_after_a_dash() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]

	await _dash_through_the_panel(panel, duskmaw)
	# Click a reachable cell: the FE loop stages the step and opens the contextual menu.
	panel.handle_movement_destination_selected(Vector3(5, 0, 1))
	for _i in range(3):
		await get_tree().process_frame

	assert_eq(panel.get_command_state(), UnitActionsPanel.CommandState.ACTION_MENU,
		"clicking a reachable cell stages the canto step and opens the menu")
	assert_true(panel.action_menu.visible, "which is on screen")
	assert_eq(_menu_buttons(panel), ["Wait", "Cancel"],
		"and the ONLY rows are Wait and Cancel -- the move rows are not built at all, " +
		"because after a dash there is nothing left to pick but where to stand")

	var rendered: Array = _menu_buttons(panel)
	for move in duskmaw.get_moveset():
		if move == null:
			continue
		var move_name: String = String(move.display_name)
		assert_false(move_name in rendered,
			"'%s' is not offered -- canto is movement only" % move_name)


func test_completing_the_canto_step_truly_ends_the_units_turn() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]
	var ts: TraditionalTurnSystem = s["ts"]

	await _dash_through_the_panel(panel, duskmaw)
	panel.handle_movement_destination_selected(Vector3(5, 0, 1))
	await get_tree().process_frame
	panel._on_action_menu_wait_chosen()

	# Asserted BEFORE yielding a frame: Duskmaw is this side's only unit here, so the
	# deferred auto-end fires on the next idle frame and the next turn's
	# reset_all_unit_actions() legitimately clears these per-turn flags again.
	assert_eq(s["board"].cell_of(duskmaw), Vector2i(5, 1),
		"the unit is standing where the canto step took it")
	assert_false(duskmaw.has_canto(), "with nothing owed")
	assert_true(duskmaw.has_acted_this_turn, "and its turn is over")
	assert_false(ts.can_unit_act(duskmaw), "the turn system agrees it is done")


func test_waiting_without_moving_also_ends_the_turn() -> void:
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var duskmaw: Unit = s["duskmaw"]
	var ts: TraditionalTurnSystem = s["ts"]

	await _dash_through_the_panel(panel, duskmaw)
	var landing: Vector2i = s["board"].cell_of(duskmaw)
	panel._on_action_menu_wait_chosen()
	await get_tree().process_frame

	assert_eq(s["board"].cell_of(duskmaw), landing, "it stayed where the dash left it")
	assert_false(duskmaw.has_canto(), "having given the owed movement up")
	assert_false(ts.can_unit_act(duskmaw), "and the turn closed all the same")


func test_the_players_turn_auto_ends_once_the_canto_is_spent() -> void:
	# Duskmaw is the human side's ONLY unit here, so the all-acted sweep is entirely about
	# it: it must NOT fire while the step is owed, and must fire the moment it is not.
	var s: Dictionary = await _boot()
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var panel = s["panel"]
	var ts: TraditionalTurnSystem = s["ts"]
	var human: Player = s["human"]

	await _dash_through_the_panel(panel, s["duskmaw"])
	for _i in range(3):
		await get_tree().process_frame
	assert_eq(ts.get_current_active_player(), human,
		"REGRESSION: the dash auto-ended the whole player turn on top of the owed step")

	panel._on_action_menu_wait_chosen()
	for _i in range(3):
		await get_tree().process_frame
	assert_ne(ts.get_current_active_player(), human,
		"and once the canto is spent the turn advances on its own")


# ===========================================================================
# The AI takes its canto and never stalls
# ===========================================================================

func test_an_ai_duskmaw_finishes_its_canto_and_hands_the_turn_on() -> void:
	# BotTurnDriver has no End Turn button to fall back on: both turn systems now hold the
	# turn open for an owed canto, so a driver that did not resolve it would wedge the
	# match. The dash itself is resolved exactly as BotTurnDriver._execute_move_decision
	# does (perform_move, then mark_action_completed) so the test does not depend on the
	# planner happening to pick slot 3.
	var s: Dictionary = await _boot(true)
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]
	var ts: TraditionalTurnSystem = s["ts"]
	var board = s["board"]

	var cast: Dictionary = duskmaw.perform_move(DASH_SLOT, Vector2i(2, 1), board)
	assert_true(bool(cast.get("success", false)),
		"the AI's dash resolved: %s" % str(cast.get("reason", "")))
	duskmaw.mark_action_completed("move")
	assert_true(duskmaw.has_canto(), "leaving the AI unit owing its movement")

	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	if driver._timer != null:
		driver._timer.stop()

	var acted: bool = await driver.act_for_turn_system(ts)

	assert_true(acted, "the driver RESOLVED the canto rather than sitting inert on it")
	assert_false(duskmaw.has_canto(),
		"the owed movement is spent -- either taken or given up, never left hanging")
	assert_false(ts.can_unit_act(duskmaw), "so the unit's turn is closed and the match moves on")


func test_the_ai_never_gets_a_second_strike_out_of_its_canto() -> void:
	var s: Dictionary = await _boot(true)
	if s.is_empty():
		pending("Could not build the live board / roster; skipping.")
		return
	var duskmaw: Unit = s["duskmaw"]
	var ts: TraditionalTurnSystem = s["ts"]
	var board = s["board"]
	var victims: Array = [s["near"], s["far"]]

	duskmaw.perform_move(DASH_SLOT, Vector2i(2, 1), board)
	duskmaw.mark_action_completed("move")
	var hp_after_dash: Array = []
	for v in victims:
		hp_after_dash.append((v as Unit).get_hp())

	var driver := BotTurnDriver.new()
	add_child_autofree(driver)
	if driver._timer != null:
		driver._timer.stop()
	await driver.act_for_turn_system(ts)

	for i in range(victims.size()):
		assert_eq((victims[i] as Unit).get_hp(), hp_after_dash[i],
			"nobody took a second hit -- the canto is movement, never another attack")
