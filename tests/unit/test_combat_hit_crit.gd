extends GutTest

# Hit / evasion / crit resolution in the combat pipeline. Uses boundary chances
# (0% and 100%) so the rolls are deterministic without seeding the RNG:
#   hit%  = move.accuracy*100 - target evasion   (clamped 0..100)
#   crit% = move.crit_chance*100 + caster crit    (clamped 0..100)

# HpUnit answers get_hp(), which is the branch MoveExecutor takes for HP bookkeeping.
# See tests/helpers/test_doubles.gd.
const Doubles := preload("res://tests/helpers/test_doubles.gd")


func _strike(accuracy: float, crit_chance: float) -> MoveResource:
	# basic_strike is a melee physical hit, power 24 scaling "attack".
	var m: MoveResource = MoveLibrary.basic_strike()
	m.accuracy = accuracy
	m.crit_chance = crit_chance
	return m

# caster with attack 0 so basic_strike deals exactly its base power (24).
func _duel(target_stats: Dictionary, caster_stats: Dictionary = { "attack": 0 }) -> Array:
	var caster := Doubles.HpUnit.new(0, caster_stats)
	var target := Doubles.HpUnit.new(1, target_stats)
	var board := Doubles.MinimalBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(1, 0))
	return [caster, target, board]


func test_default_accuracy_always_hits_for_full_damage():
	var d := _duel({ "health": 100, "defense": 0 })
	var res: Dictionary = MoveExecutor.execute(_strike(1.0, 0.0), d[0], d[2], Vector2i(1, 0))
	assert_true(res.success, "move resolved")
	assert_eq(d[1].hp, 76, "target took the full 24 (100% hit, no crit)")
	var ev: Dictionary = res.events[0]
	assert_false(ev.get("missed", false), "not recorded as a miss")
	assert_false(ev.get("crit", false), "not a crit at 0% crit")
	assert_eq(ev.amount, 24, "logged 24 damage")

func test_high_evasion_forces_a_miss():
	# hit% = 100 - 999 -> clamped 0 -> always miss, deterministically.
	var d := _duel({ "health": 100, "defense": 0, "evasion": 999 })
	var res: Dictionary = MoveExecutor.execute(_strike(1.0, 0.0), d[0], d[2], Vector2i(1, 0))
	assert_eq(d[1].hp, 100, "an evaded attack deals no damage")
	assert_true(res.events[0].get("missed", false), "logged as a miss")
	assert_eq(res.events[0].amount, 0, "miss deals 0")

func test_guaranteed_crit_from_move_multiplies_damage():
	# crit% = 100 -> every hit crits: round(24 * 1.5) = 36.
	var d := _duel({ "health": 100, "defense": 0 })
	var res: Dictionary = MoveExecutor.execute(_strike(1.0, 1.0), d[0], d[2], Vector2i(1, 0))
	assert_eq(d[1].hp, 64, "crit dealt 36")
	assert_true(res.events[0].get("crit", false), "logged as a crit")
	assert_eq(res.events[0].amount, 36, "crit amount is base x1.5")

func test_crit_stat_on_caster_can_guarantee_a_crit():
	# move has 0 base crit, but the caster's crit stat pushes crit% to 100.
	var d := _duel({ "health": 100, "defense": 0 }, { "attack": 0, "crit": 100 })
	var res: Dictionary = MoveExecutor.execute(_strike(1.0, 0.0), d[0], d[2], Vector2i(1, 0))
	assert_true(res.events[0].get("crit", false), "caster crit stat produced a crit")
	assert_eq(d[1].hp, 64, "crit dealt 36")

func test_preview_reports_hit_crit_and_lethality():
	var caster := Doubles.HpUnit.new(0, { "attack": 0, "crit": 10 })
	var target := Doubles.HpUnit.new(1, { "health": 100, "defense": 0, "evasion": 20 })
	var pv := MoveExecutor.preview_vs(_strike(0.9, 0.1), caster, target)
	assert_almost_eq(pv.hit_pct, 70.0, 0.001, "hit% = 90 - 20 evasion")
	assert_almost_eq(pv.crit_pct, 20.0, 0.001, "crit% = 10 move + 10 caster")
	assert_eq(pv.damage, 24, "base predicted damage")
	assert_eq(pv.crit_damage, 36, "crit predicted damage")
	assert_eq(pv.remaining, 76, "100 - 24 HP remaining")
	assert_false(pv.lethal, "24 is not lethal vs 100 HP")

func test_preview_flags_a_lethal_blow():
	var caster := Doubles.HpUnit.new(0, { "attack": 0 })
	var target := Doubles.HpUnit.new(1, { "health": 20, "defense": 0 })
	var pv := MoveExecutor.preview_vs(_strike(1.0, 0.0), caster, target)
	assert_true(pv.lethal, "24 predicted vs 20 HP is lethal")
	assert_eq(pv.remaining, 0, "target would drop to 0")
