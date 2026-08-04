extends GutTest

## The element matchup APPLIED: a move resolved end to end through [MoveExecutor], with
## the chart multiplier landing on the HP that actually comes off.
##
## Two things are pinned here that a chart-only test cannot reach:
##   1. the multiplier is in the LIVE damage path, not just in a lookup table;
##   2. it rounds the SAME way the rest of the damage math rounds -- one round() per
##      step, floored at 1 -- so a resisted hit can never quietly become a 0.
##
## Every move below uses accuracy 5.0 (hit% clamps to 100) and crit_chance 0.0 against a
## target with no evasion, so resolution is deterministic without depending on the seed:
## MoveContext.resolve_hit cannot miss at 100 and cannot crit at 0. The seeded RNG is
## passed anyway, because an unseeded generator in a test is a project rule violation.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

var _rng: RandomNumberGenerator


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260803


func after_each() -> void:
	ElementChart.reset_chart()


# --- Helpers -----------------------------------------------------------------


## A range-1 physical strike of [param element] for a flat [param power] (no stat
## scaling, so the arithmetic under test is only the element multiplier).
func _elemental_move(element: StringName, power: int) -> MoveResource:
	var move := MoveResource.new()
	move.move_id = &"test_elemental_strike"
	move.display_name = "Test Elemental Strike"
	move.category = CombatTypes.DamageCategory.PHYSICAL
	move.element = element
	move.accuracy = 5.0
	move.crit_chance = 0.0

	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 1
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern

	var damage := DamageEffect.new()
	damage.power = power
	damage.scaling_stat = ""   # flat power: no attack scaling in the way
	damage.category = CombatTypes.DamageCategory.PHYSICAL
	move.effects = [damage]
	return move


## An attacker at (0,0) and a defender of [param element] at (0,1), on a board that
## answers everything the pipeline asks. Returns { board, caster, target }.
func _fight(element: StringName) -> Dictionary:
	var caster := _ElementUnit.new(0, &"", 100)
	var target := _ElementUnit.new(1, element, 100)
	# TileEffectBoard, not CombatBoard: it ANSWERS tile_effects_at (with nothing), which
	# stops ElementChart falling back to the live CombatServices autoload. A unit test
	# that reaches an autoload is at the mercy of whatever the previous suite left there.
	var board := Doubles.TileEffectBoard.new()
	board.place(caster, Vector2i(0, 0))
	board.place(target, Vector2i(0, 1))
	return { "board": board, "caster": caster, "target": target }


## Resolve [param move] and return the HP the defender actually lost.
func _hp_lost(fight: Dictionary, move: MoveResource) -> int:
	var target = fight["target"]
	var before: int = target.hp
	var result: Dictionary = MoveExecutor.execute(
		move, fight["caster"], fight["board"], Vector2i(0, 1), _rng)
	assert_true(result.get("success", false),
		"the test move resolves; a rejected cast would make the damage assert vacuous")
	for event in result.get("events", []):
		if event.get("effect", "") == "damage":
			assert_false(bool(event.get("crit", false)),
				"a zero crit chance never crits -- if it did, this suite is not deterministic")
	return before - target.hp


# --- The multiplier reaches real HP ------------------------------------------


func test_a_strong_matchup_takes_more_hp() -> void:
	var fight := _fight(&"nature")
	assert_eq(_hp_lost(fight, _elemental_move(&"fire", 20)), 25,
		"fire into its opposite nature deals 20 x 1.25 = 25")


func test_a_resisted_matchup_takes_less_hp() -> void:
	var fight := _fight(&"fire")
	assert_eq(_hp_lost(fight, _elemental_move(&"fire", 20)), 15,
		"fire into fire deals 20 x 0.75 = 15 -- every element resists itself")


func test_a_neutral_matchup_is_untouched() -> void:
	var fight := _fight(&"holy")
	assert_eq(_hp_lost(fight, _elemental_move(&"fire", 20)), 20,
		"fire and holy have no authored matchup, so the hit lands unscaled")


func test_an_unknown_element_is_neutral_in_the_live_path() -> void:
	var fight := _fight(&"plasma")
	assert_eq(_hp_lost(fight, _elemental_move(&"fire", 20)), 20,
		"a target whose element the chart has never heard of takes plain damage")


func test_an_unelemented_move_is_unchanged() -> void:
	var fight := _fight(&"nature")
	assert_eq(_hp_lost(fight, _elemental_move(&"", 20)), 20,
		"a move authored before elements existed still deals exactly its power")


func test_an_unelemented_target_is_unchanged() -> void:
	var fight := _fight(&"")
	assert_eq(_hp_lost(fight, _elemental_move(&"fire", 20)), 20,
		"a unit with no element is neutral against everything")


# --- Rounding ----------------------------------------------------------------


func test_the_multiplier_rounds_like_the_rest_of_the_damage_math() -> void:
	assert_eq(_hp_lost(_fight(&"nature"), _elemental_move(&"fire", 13)), 16,
		"13 x 1.25 = 16.25 rounds to 16, the same round() every damage step uses")
	assert_eq(_hp_lost(_fight(&"fire"), _elemental_move(&"fire", 13)), 10,
		"13 x 0.75 = 9.75 rounds to 10")


func test_a_resisted_hit_never_falls_to_zero() -> void:
	assert_eq(_hp_lost(_fight(&"fire"), _elemental_move(&"fire", 1)), 1,
		"1 x 0.75 = 0.75 floors at 1 -- a resisted hit still hurts")


# --- Preview == reality, on the same board -----------------------------------


func test_the_forecast_matches_what_the_move_actually_does() -> void:
	for element in [&"nature", &"fire", &"holy", &"", &"plasma"]:
		var fight := _fight(element)
		var move := _elemental_move(&"fire", 17)
		var forecast: Dictionary = MoveExecutor.preview_vs(
			move, fight["caster"], fight["target"], fight["board"])
		var actual: int = _hp_lost(fight, move)
		assert_eq(int(forecast["damage"]), actual,
			"the forecast against a %s target is the damage the move deals" % element)
		assert_eq(int(forecast["total"]), actual,
			"and the pinned 'total' key is that same number")


func test_the_forecast_reports_the_matchup_it_applied() -> void:
	var fight := _fight(&"nature")
	var forecast: Dictionary = MoveExecutor.preview_vs(
		_elemental_move(&"fire", 20), fight["caster"], fight["target"], fight["board"])
	assert_almost_eq(float(forecast["element_mult"]), 1.25, 0.001,
		"the forecast hands back the multiplier it used, not just the result")
	assert_eq(forecast["element_label"], ElementChart.LABEL_STRONG,
		"and labels it so a panel does not have to re-derive the verdict")
	assert_eq(int(forecast["base"]), 20,
		"'base' is the mitigated damage BEFORE the element multiplier")


func test_the_forecast_labels_a_resisted_matchup() -> void:
	var fight := _fight(&"fire")
	var forecast: Dictionary = MoveExecutor.preview_vs(
		_elemental_move(&"fire", 20), fight["caster"], fight["target"], fight["board"])
	assert_eq(forecast["element_label"], ElementChart.LABEL_RESISTED,
		"fire into fire is labelled resisted")


func test_the_forecast_labels_a_neutral_matchup() -> void:
	var fight := _fight(&"holy")
	var forecast: Dictionary = MoveExecutor.preview_vs(
		_elemental_move(&"fire", 20), fight["caster"], fight["target"], fight["board"])
	assert_eq(forecast["element_label"], ElementChart.LABEL_NEUTRAL,
		"an unauthored pairing is labelled neutral")
	assert_eq(int(forecast["ability_bonus_percent"]), 0,
		"a caster with no passives reports no conditional bonus")
	assert_eq(forecast["ability_notes"], [],
		"and offers no explanation, because there is nothing to explain")


# --- Local doubles -----------------------------------------------------------


## A combat target that carries an ELEMENT. Local rather than added to the shared
## doubles: `get_element` is a method the production code branches on, so adding it to a
## shared double would reroute every suite that uses it.
class _ElementUnit:
	var team: int
	var element: StringName
	var hp: int

	func _init(p_team: int, p_element: StringName, p_hp: int) -> void:
		team = p_team
		element = p_element
		hp = p_hp

	func get_element() -> StringName:
		return element

	func get_stat(stat_name: String) -> int:
		return hp if stat_name == "health" else 0

	func get_hp() -> int:
		return hp

	func take_damage(amount: int) -> void:
		hp -= amount

	func heal(amount: int) -> void:
		hp += amount
