extends GutTest

## [MoveStatVisuals] -- the vocabulary the move buttons and the combat forecast share for
## "how far has this recharged" and "is this number still the authored one".
##
## Two rules carry the whole file and both are pinned here:
##
##  1. NO BOOST -> NO DECORATION. An unmodified stat must render exactly as it did before
##     any of this existed: empty suffix, plain "Range 3", neutral colour. A panel that
##     decorates every stat teaches the player to ignore the decoration.
##  2. AN EFFECTIVE VALUE IS READ THROUGH THE GAMEPLAY HELPER. `range_info` must come back
##     with what MoveResource.effective_max_range says, not with a bonus the UI added up
##     itself -- otherwise a button advertises a reach the executor then rejects.


# --- Stubs -------------------------------------------------------------------
# Deliberately minimal duck-types rather than real Units: these tests are about
# MoveStatVisuals' own arithmetic and formatting, not about the stat pipeline.

class RangeCaster:
	extends RefCounted
	var bonus: int = 0

	func _init(p_bonus: int = 0) -> void:
		bonus = p_bonus

	func get_stat(stat_name: String) -> int:
		return bonus if stat_name == "range_bonus" else 0


class ModifiedUnit:
	extends RefCounted
	var base: Dictionary = {}
	var effective: Dictionary = {}

	func _init(p_base: Dictionary, p_effective: Dictionary) -> void:
		base = p_base
		effective = p_effective

	func get_stat(stat_name: String) -> int:
		return int(effective.get(stat_name, 0))

	func get_base_stat(stat_name: String) -> int:
		return int(base.get(stat_name, 0))


func _move(min_range: int, max_range: int) -> MoveResource:
	var pattern := TargetingPattern.new()
	pattern.min_range = min_range
	pattern.max_range = max_range
	var move := MoveResource.new()
	move.move_id = &"test_move"
	move.display_name = "Test Move"
	move.targeting = pattern
	return move


# --- Recharge arithmetic ------------------------------------------------------

func test_a_ready_move_reads_as_fully_charged() -> void:
	assert_eq(MoveStatVisuals.recharge_fraction(0, 3), 1.0,
		"0 turns remaining is a fully recharged move")


func test_a_move_with_no_cooldown_is_always_fully_charged() -> void:
	assert_eq(MoveStatVisuals.recharge_fraction(0, 0), 1.0,
		"a move that never goes on cooldown must render a full bar, not an empty one")


func test_a_freshly_spent_move_reads_as_empty() -> void:
	assert_eq(MoveStatVisuals.recharge_fraction(3, 3), 0.0,
		"the turn a 3-turn cooldown is spent, none of it has recharged")


func test_the_bar_fills_as_the_cooldown_counts_down() -> void:
	assert_almost_eq(MoveStatVisuals.recharge_fraction(2, 3), 1.0 / 3.0, 0.001,
		"one turn of a three-turn cooldown has passed -> one third charged")
	assert_almost_eq(MoveStatVisuals.recharge_fraction(1, 3), 2.0 / 3.0, 0.001,
		"two turns passed -> two thirds charged")


func test_out_of_range_counts_are_clamped_not_rejected() -> void:
	# A restored mid-battle save can carry a count from an older cooldown value.
	assert_eq(MoveStatVisuals.recharge_fraction(9, 3), 0.0,
		"a remaining count larger than the total floors at empty, it does not go negative")
	assert_eq(MoveStatVisuals.recharge_fraction(-2, 3), 1.0,
		"a negative remaining count is a ready move")


# --- Cooldown wording ---------------------------------------------------------

func test_a_ready_move_has_no_cooldown_text_at_all() -> void:
	assert_eq(MoveStatVisuals.cooldown_label(0), "",
		"a ready move prints nothing, so the caller omits the badge instead of blanking it")
	assert_eq(MoveStatVisuals.cooldown_badge(0, 3), "")


func test_cooldown_label_pluralises() -> void:
	assert_eq(MoveStatVisuals.cooldown_label(1), "1 turn", "one turn must not say 'turns'")
	assert_eq(MoveStatVisuals.cooldown_label(2), "2 turns")


func test_cooldown_badge_shows_the_wait_and_its_length() -> void:
	assert_eq(MoveStatVisuals.cooldown_badge(2, 3), "CD 2/3",
		"the player needs how long is left AND how long the wait was, to plan a rotation")
	assert_eq(MoveStatVisuals.cooldown_badge(2, 0), "CD 2",
		"with no authored total there is nothing to be 2 out of")


# --- The ready transition -----------------------------------------------------

func test_became_ready_only_fires_on_the_transition() -> void:
	assert_true(MoveStatVisuals.became_ready(1, 0), "charging -> ready is the flash")
	assert_false(MoveStatVisuals.became_ready(0, 0),
		"a move that was already ready must not flash every time the panel repopulates")
	assert_false(MoveStatVisuals.became_ready(3, 2), "still charging is not ready")
	assert_false(MoveStatVisuals.became_ready(0, 3), "going ON cooldown is not a ready flash")


# --- No boost -> no decoration ------------------------------------------------

func test_an_unmodified_stat_gets_no_decoration() -> void:
	assert_false(MoveStatVisuals.is_modified(3, 3), "equal values are not modified")
	assert_eq(MoveStatVisuals.delta_suffix(3, 3), "",
		"an unbuffed stat renders exactly as it did before boosts were shown at all")
	assert_eq(MoveStatVisuals.stat_text("Range", 3, 3), "Range 3",
		"no arrow, no before/after -- just the number")
	assert_eq(MoveStatVisuals.delta_color(3, 3, Color.BLACK), Color.BLACK,
		"an unmodified stat keeps the caller's own ink")


func test_a_boost_reads_as_a_change_not_a_number() -> void:
	assert_eq(MoveStatVisuals.stat_text("Range", 3, 5), "Range 3 → 5",
		"the question is 'did something change my reach', so both values are shown")
	assert_eq(MoveStatVisuals.delta_suffix(3, 5), " ▲+2", "and the delta is signed and up")
	assert_eq(MoveStatVisuals.delta_color(3, 5), MoveStatVisuals.BUFF_COLOR,
		"a boost is the buff colour")


func test_a_cut_reads_as_a_loss() -> void:
	assert_eq(MoveStatVisuals.stat_text("Attack", 12, 8), "Attack 12 → 8")
	assert_eq(MoveStatVisuals.delta_suffix(12, 8), " ▼-4", "a reduction points down")
	assert_eq(MoveStatVisuals.delta_color(12, 8), MoveStatVisuals.NERF_COLOR)


# --- Reading the live values --------------------------------------------------

func test_range_info_reports_the_authored_reach_when_nothing_boosts_it() -> void:
	var info: Dictionary = MoveStatVisuals.range_info(_move(1, 3), RangeCaster.new(0))
	assert_eq(int(info["base"]), 3, "base is the authored max_range")
	assert_eq(int(info["effective"]), 3, "with no bonus, effective equals base")
	assert_false(bool(info["modified"]), "so nothing is decorated")
	assert_eq(String(info["suffix"]), "")


func test_range_info_reads_the_boost_through_the_gameplay_helper() -> void:
	var move := _move(1, 3)
	var caster := RangeCaster.new(2)
	var info: Dictionary = MoveStatVisuals.range_info(move, caster)
	assert_eq(int(info["effective"]), move.effective_max_range(caster),
		"the UI must report exactly what the executor and the targeting highlight use")
	assert_eq(int(info["effective"]), 5, "3 authored + 2 range_bonus")
	assert_true(bool(info["modified"]))
	assert_eq(String(info["text"]), "Range 3 → 5")


func test_range_info_survives_a_move_with_nothing_to_read() -> void:
	var bare := MoveResource.new()  # no targeting pattern at all
	var info: Dictionary = MoveStatVisuals.range_info(bare, null)
	assert_eq(int(info["effective"]), 0, "a patternless move reports 0 reach, not an error")
	assert_false(bool(info["modified"]))
	assert_false(MoveStatVisuals.range_info(null, null).is_empty(),
		"a null move still returns a usable descriptor")


func test_range_phrase_substitutes_the_live_reach_into_the_authored_wording() -> void:
	assert_eq(MoveStatVisuals.range_phrase(_move(1, 3), RangeCaster.new(2)), "range 1-5",
		"the button must never advertise a reach the cast would reject")
	assert_eq(MoveStatVisuals.range_phrase(_move(2, 2), RangeCaster.new(0)), "range 2",
		"a fixed-distance move keeps its single-number wording")
	assert_eq(MoveStatVisuals.range_phrase(null, null), "")


func test_stat_info_compares_effective_against_base() -> void:
	var buffed := ModifiedUnit.new({"attack": 10}, {"attack": 14})
	var info: Dictionary = MoveStatVisuals.stat_info(buffed, "attack", "Attack")
	assert_true(bool(info["modified"]), "10 base vs 14 effective is a buffed attack")
	assert_eq(String(info["text"]), "Attack 10 → 14")
	assert_eq(String(info["suffix"]), " ▲+4")


func test_stat_info_on_a_unit_that_cannot_answer_reports_unmodified() -> void:
	var info: Dictionary = MoveStatVisuals.stat_info(null, "attack")
	assert_false(bool(info["modified"]),
		"a unit with no stat accessors must never look buffed")
	assert_eq(String(info["suffix"]), "")
