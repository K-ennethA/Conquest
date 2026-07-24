extends GutTest

# Tests for the traveling-hazard system (Forest Barrage's crawling vine): the pure
# advance math + damage of a single [TravelingHazard], and the [HazardManager]
# lifecycle that ticks vines forward and drops the expired ones.
#
# Mock style mirrors test_eldroot.gd / test_ai_behavior.gd: duck-typed units and a
# lightweight board with just the queries the hazard reads (units_at, are_enemies,
# are_allies). No autoloads, no live scene -- TravelingHazard.advance takes the board
# directly, and HazardManager exposes initialize()/register()/process_turn() so its
# lifecycle drives with explicit calls.

# --- Mocks -----------------------------------------------------------------

class MockUnit:
	var team: int
	var hp: int = 100
	var defense: int = 0
	var invuln: bool = false
	var taken_scale: float = 1.0

	func _init(p_team: int, p_hp: int = 100) -> void:
		team = p_team
		hp = p_hp

	func get_stat(n: String) -> int:
		if n == "defense":
			return defense
		return 0

	func take_damage(n: int) -> void:
		hp -= n

	# Duck-typed hooks DamageEffect reads: invulnerability (Guarded) and the
	# defender-side "damage_taken_scale" passive (Grovebound). A unit left at its
	# defaults exposes neither in effect.
	func is_invulnerable() -> bool:
		return invuln

	func passive_modifiers(_unit, _board) -> Dictionary:
		if is_equal_approx(taken_scale, 1.0):
			return {}
		return { "damage_taken_scale": taken_scale }


class MockBoard:
	var placements: Array = []  # { unit, cell }

	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out

	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)

	func are_enemies(a, b) -> bool:
		return a.team != b.team

	func are_allies(a, b) -> bool:
		return a.team == b.team


# --- Helpers ---------------------------------------------------------------

const EAST := Vector2i(1, 0)

## An east-crawling vine from (0,0): width 5 (half_width 2), speed 2, range 6.
func _vine(source, damage: int, affiliation: int) -> TravelingHazard:
	return TravelingHazard.new(Vector2i(0, 0), EAST, 2, 2, 6, damage,
		CombatTypes.DamageCategory.PHYSICAL, affiliation, source)


# ===========================================================================
# TravelingHazard -- advance cadence
# ===========================================================================

func test_vine_advances_three_ticks_then_expires():
	var source := MockUnit.new(0)
	var board := MockBoard.new()
	var vine := _vine(source, 10, CombatTypes.TargetKind.ANY_UNIT)

	assert_false(vine.is_expired(), "a fresh range-6 vine is not expired")
	vine.advance(board)
	assert_eq(vine.remaining, 4, "tick 1 consumes 2 of 6 rows")
	assert_false(vine.is_expired())
	vine.advance(board)
	assert_eq(vine.remaining, 2, "tick 2 consumes another 2")
	assert_false(vine.is_expired())
	vine.advance(board)
	assert_eq(vine.remaining, 0, "tick 3 consumes the last 2")
	assert_true(vine.is_expired(), "range 6 / speed 2 -> exactly 3 ticks")

	# A 4th advance is an inert no-op (no negative remaining, no cells).
	var extra: Dictionary = vine.advance(board)
	assert_true(bool(extra["expired"]))
	assert_eq((extra["cells"] as Array).size(), 0, "an expired vine enters no more cells")


# ===========================================================================
# TravelingHazard -- damages only the newly-entered band
# ===========================================================================

func test_each_advance_damages_only_the_newly_entered_band():
	var source := MockUnit.new(0)
	var board := MockBoard.new()
	board.place(source, Vector2i(-5, -5))          # source well out of the lane
	var front_unit := MockUnit.new(1, 100)          # depth 1 (entered tick 1)
	var deep_unit := MockUnit.new(1, 100)           # depth 3 (entered tick 2)
	board.place(front_unit, Vector2i(1, 0))
	board.place(deep_unit, Vector2i(3, 0))
	var vine := _vine(source, 10, CombatTypes.TargetKind.ANY_UNIT)

	vine.advance(board)  # rows 1-2
	assert_eq(front_unit.hp, 90, "a unit in the first band is hit")
	assert_eq(deep_unit.hp, 100, "a unit still ahead of the vine is untouched")

	vine.advance(board)  # rows 3-4
	assert_eq(deep_unit.hp, 90, "the deeper unit is hit once the vine reaches it")
	assert_eq(front_unit.hp, 90, "a unit already passed is NOT re-hit")


func test_the_source_unit_is_never_damaged():
	var source := MockUnit.new(0, 100)
	var board := MockBoard.new()
	board.place(source, Vector2i(1, 1))  # squarely inside the first band
	var vine := _vine(source, 10, CombatTypes.TargetKind.ANY_UNIT)

	vine.advance(board)
	assert_eq(source.hp, 100, "the vine never damages its own caster")


# ===========================================================================
# TravelingHazard -- damage reuses DamageEffect (guarded / Grovebound)
# ===========================================================================

func test_an_invulnerable_unit_in_the_path_takes_zero():
	var source := MockUnit.new(0)
	var board := MockBoard.new()
	var guarded := MockUnit.new(1, 100)
	guarded.invuln = true
	board.place(guarded, Vector2i(1, 0))
	var vine := _vine(source, 50, CombatTypes.TargetKind.ANY_UNIT)

	var result: Dictionary = vine.advance(board)
	assert_eq(guarded.hp, 100, "an invulnerable (Guarded) unit takes 0 from the vine")
	# The hit is still recorded, as amount 0, so a log can explain the pass-through.
	assert_eq((result["damaged"] as Array).size(), 1, "the guarded unit is still a resolved target")
	assert_eq(int((result["damaged"] as Array)[0]["amount"]), 0)


func test_a_grovebound_style_reduction_applies_to_the_vine():
	var source := MockUnit.new(0)
	var board := MockBoard.new()
	var tough := MockUnit.new(1, 100)
	tough.taken_scale = 0.5  # "damage_taken_scale" passive, like Grovebound
	board.place(tough, Vector2i(1, 0))
	var vine := _vine(source, 20, CombatTypes.TargetKind.ANY_UNIT)

	vine.advance(board)
	assert_eq(tough.hp, 90, "20 raw -> mitigate 20 -> x0.5 defender scale = 10 lost")


# ===========================================================================
# TravelingHazard -- per-move affiliation filter
# ===========================================================================

func test_enemy_affiliation_spares_allies_but_hits_enemies():
	var source := MockUnit.new(0)
	var board := MockBoard.new()
	var ally := MockUnit.new(0, 100)   # same team as source
	var enemy := MockUnit.new(1, 100)  # opposing team
	board.place(ally, Vector2i(1, 0))
	board.place(enemy, Vector2i(1, 1))
	var vine := _vine(source, 10, CombatTypes.TargetKind.ENEMY)

	vine.advance(board)
	assert_eq(ally.hp, 100, "an ENEMY-affiliation vine spares the source's allies")
	assert_eq(enemy.hp, 90, "and damages the source's enemies")


func test_any_unit_affiliation_is_indiscriminate():
	var source := MockUnit.new(0)
	var board := MockBoard.new()
	var ally := MockUnit.new(0, 100)
	var enemy := MockUnit.new(1, 100)
	board.place(ally, Vector2i(1, 0))
	board.place(enemy, Vector2i(1, 1))
	var vine := _vine(source, 10, CombatTypes.TargetKind.ANY_UNIT)

	vine.advance(board)
	assert_eq(ally.hp, 90, "an ANY_UNIT vine damages the source's allies too (indiscriminate)")
	assert_eq(enemy.hp, 90, "and its enemies")


# ===========================================================================
# TravelingHazard -- geometry (5-wide band, perpendicular to travel)
# ===========================================================================

func test_the_band_is_five_wide_perpendicular_to_travel():
	var source := MockUnit.new(0)
	var vine := _vine(source, 10, CombatTypes.TargetKind.ANY_UNIT)
	# First tick enters depths 1 and 2, each 5 cells wide -> 10 cells.
	var band: Array = vine.next_band_cells()
	assert_eq(band.size(), 10, "two rows x five wide")
	# The width runs perpendicular to the east heading -> along Y, offsets -2..+2.
	for k in [-2, -1, 0, 1, 2]:
		assert_true(Vector2i(1, k) in band, "depth-1 band covers (1,%d)" % k)


# ===========================================================================
# HazardManager -- lifecycle (advance, drop expired, telegraph)
# ===========================================================================

func test_manager_advances_and_drops_expired_hazards():
	var hm: HazardManager = autofree(HazardManager.new())
	hm.initialize()
	var source := MockUnit.new(0)
	hm.register(_vine(source, 10, CombatTypes.TargetKind.ANY_UNIT))
	assert_eq(hm.active_count(), 1, "the registered vine is live")

	# Board resolves via CombatServices (null in a headless test), so process_turn
	# ticks the vine forward without landing damage -- lifecycle only here; damage is
	# proven against a mock board in the TravelingHazard tests above.
	hm.process_turn()
	assert_eq(hm.active_count(), 1, "still travelling after 1 tick")
	hm.process_turn()
	assert_eq(hm.active_count(), 1, "still travelling after 2 ticks")
	hm.process_turn()
	assert_eq(hm.active_count(), 0, "range 6 / speed 2 -> dropped after exactly 3 ticks")


func test_manager_telegraphs_advance_and_expiry():
	var hm: HazardManager = autofree(HazardManager.new())
	hm.initialize()
	var source := MockUnit.new(0)
	hm.register(_vine(source, 10, CombatTypes.TargetKind.ANY_UNIT))

	watch_signals(GameEvents)
	hm.process_turn()
	assert_signal_emitted(GameEvents, "hazard_advanced", "each advance telegraphs its band")
	hm.process_turn()
	hm.process_turn()
	assert_signal_emitted(GameEvents, "hazard_expired", "the vine announces when it expires")


func test_manager_ignores_a_null_registration():
	var hm: HazardManager = autofree(HazardManager.new())
	hm.initialize()
	hm.register(null)
	assert_eq(hm.active_count(), 0, "a null hazard is never adopted")
