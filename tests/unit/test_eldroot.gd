extends GutTest

# Tests for Eldroot, the Hollow Crown -- the 2x2 grove-fortress boss -- and the
# four engine capabilities its kit needed:
#   1. OnTerrainTagCondition: an ability condition keyed on a tile TAG rather than
#      a single tile id, resolved across a multi-cell unit's whole footprint.
#   2. A DEFENDER-side damage modifier ("damage_taken_scale"), read by DamageEffect
#      from the TARGET's passives and mirrored in MoveExecutor.preview_vs.
#   3. CombatTypes.AreaShape.ARC: a 3-cell frontal sweep derived from the aim,
#      since units have no facing.
#   4. Two rule flags that change turn flow: "invulnerable" (take no damage) and
#      "stunned" (skip the next turn).
#
# Mock style mirrors test_petalfang.gd; the turn-flow tests build real Units,
# Players and turn systems because that is the machinery under test.

# --- Mocks -----------------------------------------------------------------

## A duck-typed unit, as in test_petalfang.gd. `status_controller` is optional and
## only stood up by the tests that need real rule-flag bookkeeping.
class MockUnit:
	var team: int
	var stats: Dictionary
	var base_stats: Dictionary
	var max_health: int
	var hp: int
	var ability_system = null
	var status_controller = null
	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		base_stats = p_stats.duplicate()
		max_health = stats.get("health", 100)
		hp = max_health
	func get_stat(n: String) -> int:
		return stats.get(n, 0)
	func get_base_stat(n: String) -> int:
		return base_stats.get(n, 0)
	func take_damage(n: int) -> void:
		hp -= n
	func get_ability_system():
		return ability_system
	func get_status_controller():
		return status_controller

## A board that reports terrain TAGS per cell and knows unit footprints, so the
## multi-cell reading of OnTerrainTagCondition can be pinned without a live map.
class MockBoard:
	var placements: Array = []          # { unit, cell, footprint }
	var tags: Dictionary = {}           # Vector2i -> Array[String]

	func place(unit, cell: Vector2i, footprint: Vector2i = Vector2i.ONE) -> void:
		placements.append({ "unit": unit, "cell": cell, "footprint": footprint })

	func set_tags(cell: Vector2i, cell_tags: Array) -> void:
		tags[cell] = cell_tags

	func tile_tags_at(cell: Vector2i) -> Array:
		var found = tags.get(cell, [])
		return found if found is Array else []

	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)

	## Footprint-aware, exactly like BoardAdapter.cells_of: every cell the unit covers.
	func cells_of(unit) -> Array:
		var out: Array = []
		for p in placements:
			if p.unit != unit:
				continue
			var anchor: Vector2i = p.cell
			var fp: Vector2i = p.footprint
			for dx in range(fp.x):
				for dy in range(fp.y):
					out.append(Vector2i(anchor.x + dx, anchor.y + dy))
		return out

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			var anchor: Vector2i = p.cell
			var fp: Vector2i = p.footprint
			if cell.x >= anchor.x and cell.x < anchor.x + fp.x \
				and cell.y >= anchor.y and cell.y < anchor.y + fp.y:
				out.append(p.unit)
		return out

	func are_enemies(a, b) -> bool:
		return a.team != b.team

	func are_allies(a, b) -> bool:
		return a.team == b.team

	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell

# --- Content loaders -------------------------------------------------------

func _grovebound() -> AbilityResource:
	return load("res://game/abilities/grovebound.tres") as AbilityResource

func _guarded() -> StatusCondition:
	return load("res://game/combat/status/guarded.tres") as StatusCondition

func _flinched() -> StatusCondition:
	return load("res://game/combat/status/flinched.tres") as StatusCondition

func _bough_sweep() -> MoveResource:
	return load("res://game/combat/moves/bough_sweep.tres") as MoveResource

func _heartwood_guard() -> MoveResource:
	return load("res://game/combat/moves/heartwood_guard.tres") as MoveResource

func _timberfall() -> MoveResource:
	return load("res://game/combat/moves/timberfall.tres") as MoveResource

## The Eldroot roster entry, or null when it cannot load (its .glb model has to be
## imported by the editor first). Callers mark themselves pending rather than
## failing the suite on a missing import -- same guard as test_blightcap.gd.
func _eldroot() -> CharacterResource:
	var path := "res://game/characters/roster/eldroot.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as CharacterResource

# --- Helpers ---------------------------------------------------------------

## An AbilitySystem holding [param ability], owned by [param unit].
func _ability_system_with(unit, ability: AbilityResource) -> AbilitySystem:
	var sys: AbilitySystem = autofree(AbilitySystem.new())
	sys.owner_unit = unit
	if ability != null:
		sys.add_ability(ability)
	return sys

func _controller_for(unit) -> StatusController:
	# autofree: StatusController is a Node -- an untracked one is a GUT orphan.
	var sc: StatusController = autofree(StatusController.new())
	sc.owner_unit = unit
	return sc

## Resolve a single DamageEffect from [param caster] onto [param target] through
## the shared pipeline. Returns the HP actually lost.
func _hit(effect: DamageEffect, board, caster, target) -> int:
	var cell: Vector2i = board.cell_of(target)
	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 5
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.move_id = &"test_hit"
	move.targeting = pattern
	var before: int = target.hp
	var ctx := MoveContext.new(caster, board, move, cell, [cell] as Array[Vector2i])
	effect.apply(ctx)
	return before - target.hp

func _damage_effect(power: int, category: CombatTypes.DamageCategory) -> DamageEffect:
	var e := DamageEffect.new()
	e.power = power
	e.scaling_stat = ""
	e.scale = 0.0
	e.category = category
	return e

func _arc_pattern() -> TargetingPattern:
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.ARC
	return p

## A real Unit with real stats bookkeeping plus a StatusController child, so rule
## flags resolve through the production path (Unit.has_status_rule_flag).
func _real_unit(display_name: String) -> Unit:
	var u := Unit.new()
	var res := UnitStatsResource.new()
	res.unit_name = display_name
	res.unit_type = "warrior"
	res.max_health = 100
	res.base_speed = 8
	res.movement_range = 3
	u.stats_resource = res
	add_child_autofree(u)
	var controller := StatusController.new()
	controller.name = "StatusController"
	controller.owner_unit = u
	u.add_child(controller)
	return u


# ===========================================================================
# GAP 1 -- OnTerrainTagCondition: terrain keyed by TAG, across a footprint
# ===========================================================================

func test_forest_tag_condition_holds_on_a_forest_tile():
	var unit := MockUnit.new(0, {})
	var board := MockBoard.new()
	board.place(unit, Vector2i(2, 2))
	board.set_tags(Vector2i(2, 2), ["forest"])

	var cond := OnTerrainTagCondition.new()
	cond.tag = &"forest"
	assert_true(cond.is_met(unit, board), "a unit standing on a forest-tagged tile is on forest")


func test_forest_tag_condition_fails_on_volcano_and_ice():
	# The whole point of a TAG condition: "forest" must not be satisfied by some
	# other biome just because both are terrain. Volcano tiles carry a SECOND tag
	# ("difficult"), which is also the case that the lossy single-tag board accessor
	# would get wrong -- so it is included deliberately.
	var unit := MockUnit.new(0, {})
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var cond := OnTerrainTagCondition.new()
	cond.tag = &"forest"

	board.set_tags(Vector2i(0, 0), ["volcano", "difficult"])
	assert_false(cond.is_met(unit, board), "volcano ground is not forest")

	board.set_tags(Vector2i(0, 0), ["ice", "slippery"])
	assert_false(cond.is_met(unit, board), "ice is not forest")

	board.set_tags(Vector2i(0, 0), [])
	assert_false(cond.is_met(unit, board), "an untagged tile is not forest")


func test_forest_tag_condition_matches_a_secondary_tag():
	# tile_tags_at reports the FULL list, so a rule may key on any tag the tile
	# carries -- not only its primary/biome one.
	var unit := MockUnit.new(0, {})
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	board.set_tags(Vector2i(0, 0), ["volcano", "hazard", "fire"])
	var cond := OnTerrainTagCondition.new()
	cond.tag = &"hazard"
	assert_true(cond.is_met(unit, board), "a non-primary tag still matches")


func test_forest_tag_condition_is_ANY_cell_for_a_multi_cell_unit():
	# THE DOCUMENTED DECISION: for a footprint larger than 1x1, the tag holds when
	# ANY covered cell carries it, not when ALL do. Eldroot is 2x2, so it straddles
	# biome boundaries constantly; ALL would make a large unit strictly worse at
	# using terrain than a small one and would flicker the passive on and off along
	# every edge. One root in the grove is enough.
	var eldroot := MockUnit.new(0, {})
	var board := MockBoard.new()
	board.place(eldroot, Vector2i(3, 3), Vector2i(2, 2))  # covers (3,3) (3,4) (4,3) (4,4)
	# Three cells of volcano, ONE corner of forest.
	board.set_tags(Vector2i(3, 3), ["volcano"])
	board.set_tags(Vector2i(3, 4), ["volcano"])
	board.set_tags(Vector2i(4, 3), ["volcano"])
	board.set_tags(Vector2i(4, 4), ["forest"])

	var cond := OnTerrainTagCondition.new()
	cond.tag = &"forest"
	assert_true(cond.is_met(eldroot, board),
		"ANY covered cell being forest is enough for a 2x2 unit")


func test_forest_tag_condition_false_when_no_covered_cell_is_forest():
	# The other side of the ANY rule: with the footprint entirely off the grove it
	# must be false, or the passive would simply never turn off.
	var eldroot := MockUnit.new(0, {})
	var board := MockBoard.new()
	board.place(eldroot, Vector2i(3, 3), Vector2i(2, 2))
	for cell in [Vector2i(3, 3), Vector2i(3, 4), Vector2i(4, 3), Vector2i(4, 4)]:
		board.set_tags(cell, ["volcano", "difficult"])

	var cond := OnTerrainTagCondition.new()
	cond.tag = &"forest"
	assert_false(cond.is_met(eldroot, board),
		"a 2x2 unit fully off the grove is not on forest")


func test_forest_tag_condition_covers_the_whole_biome():
	# The reason this condition exists: ONE authored tag covers every forest tile,
	# including ones added later. Asserted against the real tile resources.
	var unit := MockUnit.new(0, {})
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	var cond := OnTerrainTagCondition.new()
	cond.tag = &"forest"

	var forest_tiles := [
		"grass_plains", "tall_grass", "tree", "sacred_meadow", "forest_dirt",
	]
	for tile_name in forest_tiles:
		var path := "res://game/tiles/resources/forest/%s.tres" % tile_name
		if not ResourceLoader.exists(path):
			continue
		var res := load(path) as TileResource
		board.set_tags(Vector2i(0, 0), res.special_properties)
		assert_true(cond.is_met(unit, board),
			"%s is tagged forest, so one condition covers it" % tile_name)


func test_forest_tag_condition_fails_closed_without_a_board():
	var unit := MockUnit.new(0, {})
	var cond := OnTerrainTagCondition.new()
	cond.tag = &"forest"
	assert_false(cond.is_met(unit, null), "no board -> no terrain answer -> false")
	assert_false(cond.is_met(null, MockBoard.new()), "no unit -> false")


# ===========================================================================
# GAP 2 -- defender-side damage reduction, and forecast/resolution agreement
# ===========================================================================

## An Eldroot-like defender standing in the grove, carrying Grovebound.
func _grove_defender(defense: int = 0) -> Array:
	var attacker := MockUnit.new(0, {})
	var defender := MockUnit.new(1, { "health": 100, "defense": defense })
	defender.ability_system = _ability_system_with(defender, _grovebound())
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0), Vector2i(2, 2))
	for cell in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 0), Vector2i(2, 1)]:
		board.set_tags(cell, ["forest"])
	return [attacker, defender, board]


func test_grovebound_reduces_incoming_damage():
	var parts := _grove_defender()
	var attacker = parts[0]
	var defender = parts[1]
	var board = parts[2]

	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, attacker, defender)
	assert_eq(dealt, 14, "20 damage scaled by Grovebound's 0.7 = 14")


func test_grovebound_does_nothing_off_the_grove():
	var parts := _grove_defender()
	var attacker = parts[0]
	var defender = parts[1]
	var board: MockBoard = parts[2]
	# Same defender, same passive -- but every covered cell is now volcano, so the
	# condition is unmet and the reduction must not apply.
	for cell in [Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 0), Vector2i(2, 1)]:
		board.set_tags(cell, ["volcano"])

	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, attacker, defender)
	assert_eq(dealt, 20, "off the grove the boss takes the plain 20")


func test_forecast_and_resolution_agree_on_the_defender_reduction():
	# THE PROPERTY THAT MATTERS. A forecast that over-reports damage against a
	# defender with a reduction teaches the player the wrong thing and makes the
	# boss feel broken rather than tough. Preview and resolution share one helper
	# (DamageEffect.damage_taken_scale_for) precisely so they cannot drift.
	var parts := _grove_defender()
	var attacker = parts[0]
	var defender = parts[1]
	var board = parts[2]

	var effect := _damage_effect(20, CombatTypes.DamageCategory.PHYSICAL)
	var move := MoveResource.new()
	move.effects = [effect] as Array[MoveEffect]

	# The board is passed explicitly: Grovebound's condition is terrain-keyed, and
	# without a board it would fail closed and the forecast would under-report the
	# boss's toughness. That is exactly why preview_vs takes an optional board.
	var forecast: Dictionary = MoveExecutor.preview_vs(move, attacker, defender, board)
	assert_eq(int(forecast["damage"]), 14, "forecast shows the reduced number")

	var dealt := _hit(effect, board, attacker, defender)
	assert_eq(int(forecast["damage"]), dealt, "forecast and resolution must agree")


func test_defender_reduction_applies_after_mitigation():
	# ORDER: mitigation first, then the scale -- so the reduction shaves what the
	# defender ACTUALLY takes rather than the raw power. 20 - 10 defense = 10,
	# then x0.7 = 7. (Scaling first would give (20 x 0.7) - 10 = 4.)
	var parts := _grove_defender(10)
	var attacker = parts[0]
	var defender = parts[1]
	var board = parts[2]

	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, attacker, defender)
	assert_eq(dealt, 7, "mitigate to 10, then scale by 0.7")


func test_a_defender_without_the_passive_is_unaffected():
	var attacker := MockUnit.new(0, {})
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0))
	board.set_tags(Vector2i(1, 0), ["forest"])

	var dealt := _hit(_damage_effect(20, CombatTypes.DamageCategory.PHYSICAL), board, attacker, defender)
	assert_eq(dealt, 20, "standing on forest does nothing without Grovebound")


# ===========================================================================
# GAP 4a -- the "invulnerable" rule flag
# ===========================================================================

func test_invulnerable_zeroes_damage():
	var attacker := MockUnit.new(0, {})
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	defender.status_controller = autofree(_controller_for(defender))
	defender.status_controller.add_status(_guarded())
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0))

	var dealt := _hit(_damage_effect(50, CombatTypes.DamageCategory.PHYSICAL), board, attacker, defender)
	assert_eq(dealt, 0, "Guarded negates the hit entirely")
	assert_eq(defender.hp, 100, "and no HP was lost")


func test_invulnerable_beats_true_damage_too():
	# TRUE damage bypasses mitigation and has a maxi(1, ...) floor, so if the
	# invulnerability check were placed anywhere later in the pipeline it would leak
	# a point of chip damage. It short-circuits ahead of everything.
	var attacker := MockUnit.new(0, {})
	var defender := MockUnit.new(1, { "health": 100 })
	defender.status_controller = autofree(_controller_for(defender))
	defender.status_controller.add_status(_guarded())
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0))

	var dealt := _hit(_damage_effect(999, CombatTypes.DamageCategory.TRUE), board, attacker, defender)
	assert_eq(dealt, 0, "not even TRUE damage gets through")


func test_invulnerable_hit_is_logged_as_negated():
	# The combat log must be able to explain a 0, or it reads as a bug.
	var attacker := MockUnit.new(0, {})
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	defender.status_controller = autofree(_controller_for(defender))
	defender.status_controller.add_status(_guarded())
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0))

	var move := MoveResource.new()
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 5
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.move_id = &"test_hit"
	move.targeting = pattern
	var cell := Vector2i(1, 0)
	var ctx := MoveContext.new(attacker, board, move, cell, [cell] as Array[Vector2i])
	_damage_effect(30, CombatTypes.DamageCategory.PHYSICAL).apply(ctx)

	assert_eq(ctx.results.size(), 1, "one damage event was logged")
	var event: Dictionary = ctx.results[0]
	assert_eq(int(event["amount"]), 0, "the event reports 0 damage")
	assert_true(bool(event.get("negated", false)), "and flags it as NEGATED, not merely zero")


func test_forecast_shows_zero_against_an_invulnerable_target():
	# A forecast promising 30 damage into a Guarded boss is a lie the player acts on.
	var attacker := MockUnit.new(0, {})
	var defender := MockUnit.new(1, { "health": 100, "defense": 0 })
	defender.status_controller = autofree(_controller_for(defender))
	defender.status_controller.add_status(_guarded())
	var board := MockBoard.new()
	board.place(attacker, Vector2i(0, 0))
	board.place(defender, Vector2i(1, 0))

	var effect := _damage_effect(30, CombatTypes.DamageCategory.PHYSICAL)
	var move := MoveResource.new()
	move.effects = [effect] as Array[MoveEffect]

	var forecast: Dictionary = MoveExecutor.preview_vs(move, attacker, defender, board)
	assert_eq(int(forecast["damage"]), 0, "forecast reports 0 against an invulnerable target")
	assert_false(bool(forecast["lethal"]), "and never calls it lethal")
	assert_eq(int(forecast["damage"]), _hit(effect, board, attacker, defender),
		"forecast and resolution agree on the zero")


# ===========================================================================
# GAP 3 -- the 3-cell frontal arc
# ===========================================================================

func test_arc_resolves_three_cells_for_each_cardinal_aim():
	var pattern := _arc_pattern()
	var origin := Vector2i(5, 5)

	# Aiming NORTH (-Y) sweeps the three cells across the north face.
	var north := pattern.resolve_cells(origin, Vector2i(5, 4))
	assert_eq(north.size(), 3, "the arc is exactly three cells")
	for cell in [Vector2i(5, 4), Vector2i(4, 4), Vector2i(6, 4)]:
		assert_true(cell in north, "north sweep covers %s" % cell)

	# EAST (+X): the three cells down the east face.
	var east := pattern.resolve_cells(origin, Vector2i(6, 5))
	assert_eq(east.size(), 3, "the arc is exactly three cells")
	for cell in [Vector2i(6, 5), Vector2i(6, 4), Vector2i(6, 6)]:
		assert_true(cell in east, "east sweep covers %s" % cell)

	# SOUTH (+Y).
	var south := pattern.resolve_cells(origin, Vector2i(5, 6))
	assert_eq(south.size(), 3, "the arc is exactly three cells")
	for cell in [Vector2i(5, 6), Vector2i(4, 6), Vector2i(6, 6)]:
		assert_true(cell in south, "south sweep covers %s" % cell)

	# WEST (-X).
	var west := pattern.resolve_cells(origin, Vector2i(4, 5))
	assert_eq(west.size(), 3, "the arc is exactly three cells")
	for cell in [Vector2i(4, 5), Vector2i(4, 4), Vector2i(4, 6)]:
		assert_true(cell in west, "west sweep covers %s" % cell)


func test_arc_never_includes_the_casters_own_cell():
	# "In front of" must never mean "on top of me" -- a self-hitting sweep would
	# make the boss kill itself with its own bread-and-butter attack.
	var pattern := _arc_pattern()
	var origin := Vector2i(5, 5)
	for aim in [Vector2i(5, 4), Vector2i(6, 5), Vector2i(5, 6), Vector2i(4, 5)]:
		var cells := pattern.resolve_cells(origin, aim)
		assert_false(origin in cells, "aiming %s never covers the origin" % aim)


func test_arc_snaps_a_diagonal_aim_to_its_dominant_axis():
	# DOCUMENTED CHOICE: a diagonal aim collapses to the dominant axis (ties favour
	# X), sharing _cardinal_dir with the LINE shape so the two direction-derived
	# shapes can never disagree about what a diagonal means. The arc still centres
	# on the cell actually aimed at -- only the FACING is snapped.
	var pattern := _arc_pattern()
	var origin := Vector2i(5, 5)

	# Perfectly diagonal: |dx| == |dy|, so the tie resolves to the X axis, giving a
	# vertical flank pair.
	var tied := pattern.resolve_cells(origin, Vector2i(6, 4))
	assert_eq(tied.size(), 3, "still exactly three cells")
	for cell in [Vector2i(6, 4), Vector2i(6, 3), Vector2i(6, 5)]:
		assert_true(cell in tied, "a tied diagonal sweeps the X face at %s" % cell)

	# Y-dominant: the facing is south, so the flanks run along X.
	var y_dominant := pattern.resolve_cells(origin, Vector2i(6, 8))
	for cell in [Vector2i(6, 8), Vector2i(5, 8), Vector2i(7, 8)]:
		assert_true(cell in y_dominant, "a Y-dominant aim sweeps the Y face at %s" % cell)


func test_arc_is_reusable_by_any_move_not_just_eldroot():
	# The shape lives on TargetingPattern, so any authored move can take it. Pinned
	# so a later refactor cannot quietly special-case it back into one boss.
	var pattern := TargetingPattern.new()
	pattern.area_shape = CombatTypes.AreaShape.ARC
	pattern.affects_caster_tile = true
	var cells := pattern.resolve_cells(Vector2i(0, 0), Vector2i(1, 0))
	assert_eq(cells.size(), 3, "ARC works on a bare pattern with no move attached")


func test_arc_hits_three_opponents_at_once():
	# End to end: three enemies lined up across one face all take the hit.
	var caster := MockUnit.new(0, {})
	var board := MockBoard.new()
	board.place(caster, Vector2i(5, 5))
	var victims: Array = []
	for cell in [Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]:
		var v := MockUnit.new(1, { "health": 100, "defense": 0 })
		board.place(v, cell)
		victims.append(v)
	# One ally standing behind, to prove the sweep is directional and ENEMY-keyed.
	var bystander := MockUnit.new(1, { "health": 100, "defense": 0 })
	board.place(bystander, Vector2i(5, 6))

	var move := MoveResource.new()
	move.move_id = &"test_arc"
	move.targeting = _arc_pattern()
	var aim := Vector2i(5, 4)
	var ctx := MoveContext.new(caster, board, move, aim, move.targeting.resolve_cells(Vector2i(5, 5), aim))
	_damage_effect(10, CombatTypes.DamageCategory.PHYSICAL).apply(ctx)

	for v in victims:
		assert_eq(v.hp, 90, "every unit on the swept face is hit")
	assert_eq(bystander.hp, 100, "a unit behind the caster is untouched")


# ===========================================================================
# GAP 4b -- "stunned" skips a turn in BOTH turn systems and for the AI,
#           and the stun still EXPIRES so the unit is never locked out
# ===========================================================================

## A player owning one real Unit, both registered with [param ts].
func _register_one_unit(ts: TurnSystemBase, unit: Unit, ai: bool = false) -> Player:
	var player := Player.new(1, "Test Player")
	player.is_ai = ai
	player.add_unit(unit)
	ts.register_player(player)
	return player

## Drive the turn-start tick the way a live turn system does, then run the status
## tick with an explicit board.
##
## _tick_unit_turn_start() calls StatusController.tick_all() only when
## CombatServices.board() is non-null, and there is no live board in a headless
## test -- so the status tick is invoked here with a mock board instead. Everything
## being tested (the ORDER: latch the stun, then tick it away) is unchanged; only
## the source of the board differs.
func _open_turn_for(ts: TurnSystemBase, unit: Unit, board) -> void:
	ts._tick_unit_turn_start(unit)
	var controller = unit.get_status_controller()
	if controller != null:
		controller.tick_all(board)


func test_traditional_turn_system_skips_a_stunned_unit():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Flinched One")
	var player := _register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))

	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	assert_true(ts.can_unit_act(unit), "baseline: an unstunned unit can act")

	unit.get_status_controller().add_status(_flinched())
	_open_turn_for(ts, unit, board)

	assert_false(ts.can_unit_act(unit), "Traditional skips a stunned unit")
	assert_false(unit in ts.get_active_units(), "and it is not in get_active_units()")


func test_speed_first_turn_system_skips_a_stunned_unit():
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var unit := _real_unit("Flinched One")
	_register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))

	ts.is_active = true
	ts.is_turn_in_progress = true
	ts.current_acting_unit = unit

	assert_true(ts.can_unit_act(unit), "baseline: an unstunned unit can act")

	unit.get_status_controller().add_status(_flinched())
	_open_turn_for(ts, unit, board)

	assert_false(ts.can_unit_act(unit), "Speed First skips a stunned unit")
	assert_false(unit in ts.get_active_units(), "and it is not in get_active_units()")


func test_the_stun_expires_during_the_turn_it_skips():
	# THE LOCKOUT BUG, PINNED. A stun that prevented its own expiry -- by dropping
	# the unit from the turn order, or by skipping its tick -- would take the unit
	# out of the match permanently. The unit must be skipped for exactly one turn
	# and be actable on the next one.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Flinched One")
	var player := _register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))

	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	unit.get_status_controller().add_status(_flinched())
	assert_true(unit.is_stunned(), "the flinch is on")

	# Turn N: skipped, and the stun ticks away DURING it.
	_open_turn_for(ts, unit, board)
	assert_false(ts.can_unit_act(unit), "turn N: skipped")
	assert_false(unit.is_stunned(), "the stun expired during the turn it cost")

	# Turn N+1: nothing to latch, so the unit acts again.
	ts.current_turn += 1
	unit.reset_turn_actions()
	_open_turn_for(ts, unit, board)
	assert_true(ts.can_unit_act(unit), "turn N+1: actable again -- no permanent lockout")


func test_the_stun_expires_in_speed_first_too():
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	var unit := _real_unit("Flinched One")
	_register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))

	ts.is_active = true
	ts.is_turn_in_progress = true
	ts.current_acting_unit = unit

	unit.get_status_controller().add_status(_flinched())
	_open_turn_for(ts, unit, board)
	assert_false(ts.can_unit_act(unit), "round N: skipped")
	assert_false(unit.is_stunned(), "and the stun ran out during it")

	ts.current_turn += 1
	unit.reset_turn_actions()
	ts.current_acting_unit = unit
	_open_turn_for(ts, unit, board)
	assert_true(ts.can_unit_act(unit), "round N+1: actable again")


func test_a_stunned_unit_stays_registered_so_it_can_still_tick():
	# The mechanism behind the no-lockout guarantee: the unit is gated OUT of
	# acting, never removed from the turn system. Removing it is the tempting
	# implementation and the one that bricks the unit.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Flinched One")
	var player := _register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	unit.get_status_controller().add_status(_flinched())
	_open_turn_for(ts, unit, board)

	assert_true(unit in ts.registered_units, "still registered with the turn system")
	assert_true(unit in ts.get_units_for_player(player), "still one of the player's units")


func test_the_ai_driver_skips_a_stunned_unit():
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Flinched Bot")
	var player := _register_one_unit(ts, unit, true)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))

	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	var driver: BotTurnDriver = add_child_autofree(BotTurnDriver.new())
	assert_eq(driver._next_actable_ai_unit(ts, player), unit,
		"baseline: the AI picks up an unstunned unit")

	unit.get_status_controller().add_status(_flinched())
	_open_turn_for(ts, unit, board)

	assert_null(driver._next_actable_ai_unit(ts, player),
		"the AI driver will not act a stunned unit")

	# ... and once the stun has run out, the AI picks it up again next turn.
	ts.current_turn += 1
	unit.reset_turn_actions()
	_open_turn_for(ts, unit, board)
	assert_eq(driver._next_actable_ai_unit(ts, player), unit,
		"the AI is not locked out of the unit either")


func test_turn_tick_state_is_cleared_on_reset():
	# current_turn rewinds to 1 on reset, so a stale skip recorded on the PREVIOUS
	# battle's turn 1 would otherwise read as a live skip in the new one.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	var unit := _real_unit("Flinched One")
	var player := _register_one_unit(ts, unit)
	var board := MockBoard.new()
	board.place(unit, Vector2i(0, 0))
	ts.is_active = true
	ts.current_player = player
	ts.is_turn_in_progress = true

	unit.get_status_controller().add_status(_flinched())
	_open_turn_for(ts, unit, board)
	assert_true(ts.is_turn_skipped(unit), "skip is latched")

	ts.clear_turn_tick_state()
	assert_false(ts.is_turn_skipped(unit), "reset clears the latch")


# ===========================================================================
# CONTENT -- the authored statuses, moves, ability and character
# ===========================================================================

func test_guarded_status_is_authored_as_a_one_turn_invulnerability():
	var guarded := _guarded()
	assert_eq(guarded.id, &"guarded")
	assert_eq(guarded.duration_turns, 1, "one turn of immunity, not a permanent wall")
	assert_true(bool(guarded.rule_flags.get("invulnerable", false)),
		"it declares the invulnerable rule flag")


func test_flinched_status_is_authored_as_a_one_turn_stun():
	var flinched := _flinched()
	assert_eq(flinched.id, &"flinched")
	assert_eq(flinched.duration_turns, 1, "exactly one skipped turn")
	assert_true(bool(flinched.rule_flags.get("stunned", false)),
		"it declares the stunned rule flag")


func test_bough_sweep_is_an_uncooled_adjacent_arc():
	var move := _bough_sweep()
	assert_eq(move.move_id, &"bough_sweep")
	assert_eq(move.cooldown, 0, "the bread-and-butter swing has no cooldown")
	assert_eq(move.targeting.area_shape, CombatTypes.AreaShape.ARC, "it uses the frontal arc")
	assert_eq(move.targeting.max_range, 1, "adjacent only")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.ENEMY)
	# Three cells, so a moderate per-target number rather than a single-target one.
	assert_eq(move.targeting.resolve_cells(Vector2i(0, 0), Vector2i(1, 0)).size(), 3)


func test_heartwood_guard_is_a_self_buff_on_cooldown():
	var move := _heartwood_guard()
	assert_eq(move.move_id, &"heartwood_guard")
	assert_eq(move.cooldown, 2, "cannot be chained into permanent invulnerability")
	assert_eq(move.targeting.target_kind, CombatTypes.TargetKind.SELF)
	var applies_guarded := false
	var buffs_defense := false
	# Deliberately untyped: move.effects is Array[MoveEffect], so a typed loop
	# variable cannot reach the subclass fields (`condition`, `stat_name`, ...).
	for e in move.effects:
		var fx = e
		if fx is ApplyStatusEffect and fx.condition != null and fx.condition.id == &"guarded":
			applies_guarded = true
		if fx is StatModifierEffect and fx.stat_name == "defense":
			buffs_defense = true
			assert_gt(fx.amount, 0, "the defence modifier is a buff")
			assert_eq(fx.duration, 3, "and lasts 3 turns")
	assert_true(applies_guarded, "it applies Guarded")
	assert_true(buffs_defense, "and a lasting defence buff")


func test_timberfall_is_a_big_single_target_hit_with_a_flinch_chance():
	var move := _timberfall()
	assert_eq(move.move_id, &"timberfall")
	assert_eq(move.cooldown, 2)
	assert_eq(move.targeting.area_shape, CombatTypes.AreaShape.SINGLE, "single target")
	assert_eq(move.targeting.max_range, 1, "melee")
	# Deliberately untyped, as above: Array[MoveEffect] elements cannot be read as
	# their subclasses through a typed variable.
	var damage = null
	var flinch = null
	for e in move.effects:
		var fx = e
		if fx is DamageEffect:
			damage = fx
		if fx is ApplyStatusEffect:
			flinch = fx
	assert_not_null(damage, "it deals damage")
	assert_not_null(flinch, "it can flinch")

	var sweep_damage = null
	for e in _bough_sweep().effects:
		var fx = e
		if fx is DamageEffect:
			sweep_damage = fx
	assert_gt(damage.power, sweep_damage.power,
		"Timberfall hits harder than the no-cooldown sweep")

	assert_eq(flinch.condition.id, &"flinched")
	assert_lt(flinch.chance, 1.0, "the stun is a CHANCE, not guaranteed -- a guaranteed "
		+ "one-turn stun on a 2-turn cooldown would lock a target out half the match")
	assert_gt(flinch.chance, 0.0)


func test_grovebound_is_a_passive_forest_damage_reduction():
	var ability := _grovebound()
	assert_eq(ability.id, &"grovebound")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.PASSIVE)
	# Untyped: `condition` is AbilityCondition, so `tag` is only reachable dynamically.
	var cond = ability.condition
	assert_true(cond is OnTerrainTagCondition, "gated on the tile TAG condition")
	assert_eq(cond.tag, &"forest")
	var scale: float = float(ability.rule_modifiers.get("damage_taken_scale", 1.0))
	assert_lt(scale, 1.0, "below 1.0 means it TAKES less")
	assert_gt(scale, 0.0, "but not immunity")


func test_eldroot_loads_as_a_2x2_boss_with_four_moves_and_one_ability():
	var eldroot := _eldroot()
	if eldroot == null:
		pending("eldroot.tres could not load (its .glb needs an editor import); skipping.")
		return
	assert_eq(eldroot.character_id, &"eldroot")
	assert_eq(eldroot.display_name, "Eldroot, the Hollow Crown")
	assert_true(eldroot.is_boss, "is_boss drives BossController")
	assert_eq(eldroot.footprint, Vector2i(2, 2), "a 2x2 footprint")
	# Forest Barrage fills the 4th slot (MAX_MOVES == 4): the boss's ranged answer to
	# being kited, added without disturbing the original three.
	assert_eq(eldroot.moveset.size(), 4, "four moves")
	assert_eq(eldroot.abilities.size(), 1, "one ability")
	assert_ne(eldroot.description, "", "it has a description")

	var move_ids: Array = []
	for m in eldroot.moveset:
		move_ids.append(m.move_id)
	for expected in [&"bough_sweep", &"heartwood_guard", &"timberfall", &"forest_barrage"]:
		assert_true(expected in move_ids, "moveset contains %s" % expected)
	assert_eq(eldroot.abilities[0].id, &"grovebound")


func test_eldroot_is_statted_as_an_immovable_fortress():
	var eldroot := _eldroot()
	if eldroot == null:
		pending("eldroot.tres could not load (its .glb needs an editor import); skipping.")
		return
	# The design constraint: a slow wall that punishes anyone in its grove, NOT a
	# fast bruiser that chases. Compared against the roster's front-line bruiser so
	# these stay meaningful if the whole game is retuned.
	var hero := load("res://game/characters/roster/vineweave.tres") as CharacterResource
	if hero != null:
		assert_gt(eldroot.base_health, hero.base_health, "boss-tier health")
		assert_gt(eldroot.base_defense, hero.base_defense, "boss-tier defence")
		assert_lt(eldroot.base_speed, hero.base_speed, "slower than a front-liner")
	assert_lte(eldroot.base_movement, 2, "movement 1-2: it does not chase")
	assert_gte(eldroot.base_movement, 1)
	assert_eq(eldroot.attack_range, 1, "melee")


# --- Anchored boss: leash 0 keeps it on its grove ----------------------------
# Eldroot is a 2x2 boss on a 2x2 sacred meadow; ANY step drags it partly off its
# area, so it must be a true turret -- default leash 0. It still attacks in range
# (melee adjacency + its ranged lane hazard), it just never walks off.

func test_eldroot_is_anchored_with_zero_leash() -> void:
	var eldroot := load("res://game/characters/roster/eldroot.tres") as CharacterResource
	assert_not_null(eldroot, "eldroot character resource should load")
	assert_true(eldroot.is_boss, "eldroot is a boss")
	assert_eq(eldroot.get_default_leash_radius(), 0,
		"the boss must be anchored (leash 0) so it can never be dragged off its grove")
