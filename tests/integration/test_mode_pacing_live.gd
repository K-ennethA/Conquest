extends GutTest

## PER-MODE PACING, on the live wiring: the boosted MOV chip as the REAL HUD draws it, and
## placed-trap expiry against the REAL [CombatServices] applied-effect layer.
##
## The unit suite (`unit/test_mode_pacing.gd`) pins the surface and the arithmetic. This one
## pins the three places the numbers have to actually LAND:
##
##   * the mounted [GameUILayout]'s MOV chip -- not a helper's return value, the text the
##     rendered chip carries for the selected unit (the lesson of
##     `test_battle_hud_live_unit_info.gd`: a helper-static assertion passed while the live
##     screen was wrong);
##   * the board, where an expired trap has to be gone from [method CombatServices.tile_effects_at]
##     AND to have raised [signal CombatServices.tile_effects_changed] so the overlay pulls its
##     marker -- the same two things a SPRUNG trap does, because it is the same removal path;
##   * both turn systems, because the round the whole schedule runs on is derived differently
##     in each (CONQUEST.md rule 2).
##
## GLOBAL STATE. [ModeTuning]'s registration and CombatServices' applied-effect layer are both
## process-wide, so both are cleared in `after_each` -- which GUT runs even when a test FAILS
## (tests/README rule 3).

const LAYOUT := preload("res://game/ui/layout/GameUILayout.tscn")

const DESIGN := Vector2i(1280, 720)
const BASE_MOVEMENT := 3
const TRAP_CELL := Vector2i(4, 4)

var _prev_window_size: Vector2i

## The tile_effects_changed listener a test connected, so `after_each` can take it back off the
## autoload even when an assertion failed mid-test (tests/README rule 3).
var _effect_sink: Callable = Callable()


func before_all() -> void:
	var root := get_tree().root
	_prev_window_size = root.size
	root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_window_size


func after_each() -> void:
	ModeTuning.clear()
	if CombatServices != null:
		if _effect_sink.is_valid() and CombatServices.tile_effects_changed.is_connected(_effect_sink):
			CombatServices.tile_effects_changed.disconnect(_effect_sink)
		_effect_sink = Callable()
		CombatServices.clear()
	# Re-populating the HUD detaches and queue_free()s the previous unit's cards; queue_free is
	# deferred and GUT counts orphans before the frame ends.
	await get_tree().process_frame
	await get_tree().process_frame


# --- Doubles / fixtures --------------------------------------------------------

class FakeBoard extends RefCounted:
	var cells: Dictionary = {}

	func place(unit, cell: Vector2i) -> void:
		cells[unit] = cell

	func cell_of(unit) -> Vector2i:
		return cells.get(unit, Vector2i(-999, -999))

	func all_units() -> Array:
		return cells.keys()


class FakeMap extends RefCounted:
	var lanes: Array = []
	var base_cells: Dictionary = {}


func _character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"petalfang"
	c.display_name = "Petalfang"
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 15
	c.base_speed = 12
	c.base_movement = BASE_MOVEMENT
	return c


func _unit(player_id: int = 0) -> Unit:
	var u := Unit.new()
	u.character_resource = _character()
	var p := Player.new()
	p.player_id = player_id
	u.owner_player = p
	add_child_autofree(u)
	return u


func _map() -> FakeMap:
	var m := FakeMap.new()
	m.lanes = [[Vector2i(1, 1), Vector2i(5, 1), Vector2i(9, 1)]]
	m.base_cells = {0: Vector2i(0, 0), 1: Vector2i(10, 10)}
	return m


## An armed Siege whose ruleset carries [param expiry] rounds of trap lifetime.
func _armed_siege(hero_bonus: int = 2, creep_bonus: int = 1, expiry: int = 6) -> SiegeController:
	var rs := SiegeRuleset.new()
	rs.creeps_per_lane = 0          # no waves; this suite is about pacing, not spawning
	rs.hero_move_bonus = hero_bonus
	rs.creep_move_bonus = creep_bonus
	rs.trap_expiry_rounds = expiry

	var c := SiegeController.new()
	c.name = "ModePacingLiveController"
	add_child_autofree(c)
	c.set_ruleset(rs)
	c.set_armed(true)
	c.configure_from_map(_map())
	c.set_board_override(FakeBoard.new())
	return c


## The authored Vine Trap, or a code-built stand-in with the same shape.
func _trap_resource() -> TileEffectResource:
	var path := "res://game/tiles/effects/resources/vine_trap.tres"
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is TileEffectResource:
			return res as TileEffectResource
	var te := TileEffectResource.new()
	te.id = &"vine_trap"
	te.display_name = "Vine Trap"
	te.trigger = TileEffectResource.Trigger.ON_ENTER
	te.springs_on_pass = true
	return te


## Plant a trap on [param cell] through the REAL placement path -- [ApplyTileEffect], which is
## what a move that lays one runs. Returns the placed copy now on the board.
func _plant_trap(caster: Unit, cell: Vector2i = TRAP_CELL) -> TileEffectResource:
	var effect := ApplyTileEffect.new()
	effect.effect = _trap_resource()
	var cells: Array[Vector2i] = [cell]
	var ctx := MoveContext.new(caster, null, null, cell, cells)
	effect.apply(ctx)
	var applied: Array = CombatServices.applied_tile_effects_at(cell)
	if applied.is_empty():
		return null
	return applied[0] as TileEffectResource


func _placed_count(cell: Vector2i = TRAP_CELL) -> int:
	return CombatServices.applied_tile_effects_at(cell).size()


# ==============================================================================
# 1. The MOV chip, as the real HUD draws it
# ==============================================================================

func _build_hud() -> Control:
	var layout: Control = LAYOUT.instantiate()
	add_child_autofree(layout)
	for i in range(8):
		await get_tree().process_frame
	return layout


func _select(unit: Unit) -> void:
	GameEvents.unit_selected.emit(unit, Vector3.ZERO)
	for i in range(6):
		await get_tree().process_frame


## The rendered text of the card's MOV chip ("" when there is no such chip).
func _mov_chip_text(layout: Control) -> String:
	var card: Node = layout.unit_info_panel
	if card == null:
		return ""
	var chip: Node = card.find_child("StatChipMOV", true, false)
	if chip == null:
		return ""
	var value := chip.get_node_or_null("Value") as Label
	return value.text if value != null else ""


func test_the_live_mov_chip_shows_the_mode_granted_movement() -> void:
	var layout: Control = await _build_hud()
	var siege := _armed_siege(2, 1, 0)
	var hero := _unit(0)

	await _select(hero)
	assert_string_contains(_mov_chip_text(layout), "MOV %d" % BASE_MOVEMENT,
		"before the grant the chip quotes the character's own movement")

	siege.grant_march_bonus(hero)
	await _select(hero)

	var text: String = _mov_chip_text(layout)
	gut.p("MOV chip reads: %s" % text)
	assert_string_contains(text, "MOV %d" % (BASE_MOVEMENT + 2),
		"the mounted HUD's MOV chip shows the BOOSTED value -- the chip reads the same "
		+ "get_stat('movement') the mode moved, so the player can see the pace they have")
	assert_string_contains(text, MoveStatVisuals.UP_ARROW,
		"and marks it as a buff, so the boost reads as a modifier rather than as the base stat")


# ==============================================================================
# 2. The grant rides EITHER turn system's round signal
# ==============================================================================

func test_a_traditional_turn_start_paces_the_board() -> void:
	var siege := _armed_siege()
	var board := FakeBoard.new()
	siege.set_board_override(board)
	var hero := _unit(0)
	board.place(hero, Vector2i(2, 2))

	var ts := TraditionalTurnSystem.new()
	ts.name = "TradTS"
	add_child_autofree(ts)
	ts.current_turn = 1

	var player := Player.new()
	player.player_id = 0
	siege.handle_turn_started(player, ts)

	assert_eq(int(hero.get_stat("movement")), BASE_MOVEMENT + 2,
		"Traditional derives its round from current_turn, and the grant rides that boundary")


func test_a_speed_first_turn_start_paces_the_board() -> void:
	var siege := _armed_siege()
	var board := FakeBoard.new()
	siege.set_board_override(board)
	var hero := _unit(0)
	board.place(hero, Vector2i(2, 2))

	var ts := SpeedFirstTurnSystem.new()
	ts.name = "SpeedTS"
	add_child_autofree(ts)
	ts.round_number = 1

	var player := Player.new()
	player.player_id = 0
	siege.handle_turn_started(player, ts)

	assert_eq(int(hero.get_stat("movement")), BASE_MOVEMENT + 2,
		"Speed First keeps a real round_number, and the same grant rides that boundary -- the "
		+ "mode never listens to PlayerManager, which is silent on AI turns")


# ==============================================================================
# 3. Placed-trap expiry
# ==============================================================================

func test_a_trap_planted_in_siege_records_the_round_and_its_frozen_expiry() -> void:
	var siege := _armed_siege(0, 0, 6)
	siege.observe_round(1)
	siege.observe_round(2)

	var placed := _plant_trap(_unit(0))
	assert_not_null(placed, "the placement path put a trap on the cell")
	if placed == null:
		return
	assert_eq(placed.placed_round, 2, "the placement records the round it went down")
	assert_eq(placed.expires_on_round, 8, "and freezes its expiry at placed + the mode's 6")


func test_a_frozen_expiry_survives_a_mid_match_retune() -> void:
	var siege := _armed_siege(0, 0, 6)
	siege.observe_round(1)
	var placed := _plant_trap(_unit(0))
	assert_not_null(placed, "the trap went down")
	if placed == null:
		return
	assert_eq(placed.expires_on_round, 7, "planted on round 1 with a lifetime of 6")

	siege.ruleset().trap_expiry_rounds = 20
	assert_eq(placed.expires_on_round, 7,
		"retuning the ruleset cannot move a trap that is already down -- the number was frozen "
		+ "at cast time, which is what keeps two lockstep peers agreeing on when it goes")


func test_a_trap_expires_exactly_on_its_frozen_round_and_leaves_the_board() -> void:
	var siege := _armed_siege(0, 0, 3)
	siege.observe_round(1)
	var placed := _plant_trap(_unit(0))
	assert_not_null(placed, "the trap went down")
	if placed == null:
		return
	assert_eq(placed.expires_on_round, 4, "1 + 3")

	# Watch the signal the overlay restacks a cell on. An ARRAY, because a GUT lambda captures
	# by VALUE -- an int counter incremented in here would never come back out.
	var changed: Array = []
	_effect_sink = func(cell: Vector2i) -> void: changed.append(cell)
	CombatServices.tile_effects_changed.connect(_effect_sink)

	siege.observe_round(2)
	assert_eq(_placed_count(), 1, "round 2: still armed")
	siege.observe_round(3)
	assert_eq(_placed_count(), 1, "round 3: still armed, one round short of its expiry")

	siege.observe_round(4)
	assert_eq(_placed_count(), 0, "round 4 is its frozen expiry round, so it is swept")
	assert_false(_trap_present_in_effects(), "and it is gone from tile_effects_at -- the lookup "
		+ "every movement, preview and AI path reads, so nothing can still spring it")
	assert_true(TRAP_CELL in changed,
		"and the removal raised tile_effects_changed for its cell, which is what pulls the "
		+ "marker off the board -- the SAME removal path a sprung trap takes")


## True while the trap is still in the cell's merged (base + applied) effect list.
func _trap_present_in_effects() -> bool:
	for te in CombatServices.tile_effects_at(TRAP_CELL):
		if te != null and te.has_method("is_runtime_placement") and te.is_runtime_placement():
			return true
	return false


func test_map_authored_terrain_is_never_swept_however_long_the_battle_runs() -> void:
	# The authored-vs-placed line, stated as behaviour: the sweep walks the APPLIED layer only,
	# so a base effect derived from the tile type is not even enumerated. Lava stays lava.
	var siege := _armed_siege(0, 0, 1)
	var authored := _trap_resource()
	assert_false(authored.is_runtime_placement(),
		"the shared authored resource carries no placement record")
	assert_false(authored.is_expired_on(9999),
		"so no round can ever expire it, whatever lifetime the mode declares")

	for r in range(1, 12):
		siege.observe_round(r)
	assert_eq(authored.expires_on_round, -1,
		"and eleven rounds of sweeping never stamped one onto it (CONQUEST.md rule 7)")


func test_a_trap_planted_in_a_plain_skirmish_never_expires() -> void:
	ModeTuning.clear()
	var placed := _plant_trap(_unit(0))
	assert_not_null(placed, "the trap goes down exactly as it always did")
	if placed == null:
		return
	assert_false(placed.expires(), "with no mode armed it carries no clock at all")

	for r in range(1, 40):
		TileEffectSystem.expire_placed_effects(r)
	assert_eq(_placed_count(), 1,
		"so forty rounds of the engine's own sweep leave it on the board -- a skirmish behaves "
		+ "exactly as it did before trap expiry existed")


func test_two_identical_runs_expire_their_traps_on_the_same_rounds() -> void:
	var runs: Array = []
	for run in range(2):
		CombatServices.clear()
		ModeTuning.clear()
		var siege := _armed_siege(0, 0, 4)
		var caster := _unit(0)
		var sig: Array = []
		for r in range(1, 13):
			siege.observe_round(r)
			if r == 1 or r == 3 or r == 6:
				var placed := _plant_trap(caster, Vector2i(r, r))
				sig.append("plant %d -> %d" % [r, placed.expires_on_round if placed != null else -99])
			sig.append("%d:%d,%d,%d" % [r,
				CombatServices.applied_tile_effects_at(Vector2i(1, 1)).size(),
				CombatServices.applied_tile_effects_at(Vector2i(3, 3)).size(),
				CombatServices.applied_tile_effects_at(Vector2i(6, 6)).size()])
		runs.append(sig)

	assert_gt((runs[0] as Array).size(), 0, "the run produced a timeline to compare")
	assert_eq(runs[0], runs[1],
		"same ruleset + same round sequence => the same traps expire on the same rounds; no "
		+ "RNG and no wall clock anywhere in the placement or the sweep")


func test_the_sweep_is_inert_before_the_first_round() -> void:
	var siege := _armed_siege(0, 0, 1)
	_plant_trap(_unit(0))
	assert_eq(TileEffectSystem.expire_placed_effects(0).size(), 0,
		"round 0 is 'the battle has not opened', so nothing is swept")
	assert_eq(_placed_count(), 1, "and the trap is untouched")
	assert_eq(siege.rounds_elapsed(), 0, "the mode's clock has not started either")
