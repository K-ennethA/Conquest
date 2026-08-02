extends GutTest

## [ItemSystem] is the battle-side half of the item feature. Two things it does are worth
## pinning hard, because both fail silently:
##
##   1. APPLICATION IS IDEMPOTENT. The equip sweep runs on EVERY turn boundary (that is the
##      only signal that fires for human and AI turns alike), so a unit that could be stamped
##      twice would gain +5 Max HP per turn forever. Application must land exactly once.
##   2. THE DROP ODDS ARE THE QUOTED ODDS. Epic 2% / Rare 8% / Common 25% / nothing 65%, from
##      ONE roll over cumulative bands rather than three independent ones. Driven by a seeded
##      generator here so the distribution is checkable at all.
##
## It also pins the two aggregation rules the item channels follow: regen SUMS across items
## (a heal is a resource), damage reduction takes the STRONGEST only (reductions refresh,
## never compound).

const TEMP_SAVE_PATH := "user://test_item_system.json"

const UNIT_ITEM := "heartwood_charm"      # +5 Max HP, common, unit-scope
const TEAM_ITEM := "elderroot_standard"   # +2 Defense, epic, team-scope
const REGEN_UNIT_ITEM := "sagebloom_poultice"  # heal 5/turn, rare, unit-scope
const REGEN_TEAM_ITEM := "verdant_banner"      # heal 2/turn, epic, team-scope
const WARD_ITEM := "hollowbark_ward"      # -15% damage taken, rare, unit-scope


# --- Mocks ------------------------------------------------------------------

## A unit that implements only what the item application actually touches: the stat write
## path ArenaAugmentApplier uses (modify_stat), a health accessor, and a StatusController for
## the regen / ward channels. set_meta / has_meta come free from Object, which is exactly why
## the applied-latch lives there.
class MockUnit extends RefCounted:
	var stats: Dictionary = { "health": 20, "attack": 5, "defense": 3, "movement": 3 }
	## ArenaAugmentApplier reads this for stats UnitStats has no setter branch for; a mock
	## without one simply skips those, which is the documented null-safe behaviour.
	var unit_stats = null
	var ctrl: StatusController = null

	func modify_stat(stat_name: String, amount: int, _is_permanent: bool = false) -> void:
		stats[stat_name] = int(stats.get(stat_name, 0)) + amount

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))

	func get_base_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))

	func heal(amount: int) -> void:
		stats["health"] = int(stats.get("health", 0)) + amount

	func get_status_controller():
		return ctrl


func _mock_unit() -> MockUnit:
	var unit := MockUnit.new()
	var controller: StatusController = autofree(StatusController.new())
	controller.owner_unit = unit
	unit.ctrl = controller
	return unit


func before_all() -> void:
	ItemInventory.set_save_path(TEMP_SAVE_PATH)
	ItemLibrary.rescan()


func before_each() -> void:
	ItemInventory.reset()


func after_all() -> void:
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
	ItemInventory.reset()


# --- Which items apply to whom ----------------------------------------------

func test_loadout_is_the_worn_item_plus_every_team_item():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)

	var loadout: Array[ItemResource] = ItemSystem.loadout_for("vineweave")
	assert_eq(loadout.size(), 2, "the worn item and the team item both apply")
	assert_eq(String(loadout[0].id), UNIT_ITEM, "the personal item leads")


func test_team_items_apply_to_a_character_wearing_nothing():
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)
	var loadout: Array[ItemResource] = ItemSystem.loadout_for("blightcap")
	assert_eq(loadout.size(), 1, "team items are squad-wide, not opt-in")


func test_another_characters_item_does_not_leak():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	assert_eq(ItemSystem.loadout_for("blightcap").size(), 0, "blightcap gets nothing")


# --- Stat application -------------------------------------------------------

func test_equipped_item_raises_the_stat():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var unit := _mock_unit()

	assert_true(ItemSystem.apply_loadout(unit, "vineweave"), "the loadout was applied")
	assert_eq(unit.get_stat("health"), 25, "+5 Max HP landed on base 20")


func test_unit_and_team_stats_both_land():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)
	var unit := _mock_unit()

	ItemSystem.apply_loadout(unit, "vineweave")
	assert_eq(unit.get_stat("health"), 25, "the personal +5 Max HP landed")
	assert_eq(unit.get_stat("defense"), 5, "the team-wide +2 Defense landed too")


func test_a_character_with_no_items_is_untouched():
	var unit := _mock_unit()
	assert_false(ItemSystem.apply_loadout(unit, "vineweave"), "nothing to apply")
	assert_eq(unit.get_stat("health"), 20, "stats are exactly as spawned")


# --- IDEMPOTENCE (the sweep runs every turn) --------------------------------

func test_applying_twice_applies_once():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var unit := _mock_unit()

	assert_true(ItemSystem.apply_loadout(unit, "vineweave"), "the first call does the work")
	assert_false(ItemSystem.apply_loadout(unit, "vineweave"), "the second reports no-op")
	assert_eq(unit.get_stat("health"), 25, "and the bonus is NOT doubled")


func test_ten_turn_sweeps_still_apply_once():
	# The real sweep runs at every turn boundary for the whole battle; this is the failure
	# that would compound into an unkillable unit by turn 10.
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var unit := _mock_unit()
	for _i in range(10):
		ItemSystem.apply_loadout(unit, "vineweave")
	assert_eq(unit.get_stat("health"), 25, "still exactly +5 after ten sweeps")


func test_the_status_channels_are_installed_once_too():
	ItemInventory.grant(REGEN_UNIT_ITEM)
	ItemInventory.equip("vineweave", REGEN_UNIT_ITEM)
	var unit := _mock_unit()
	ItemSystem.apply_loadout(unit, "vineweave")
	ItemSystem.apply_loadout(unit, "vineweave")
	assert_eq(unit.ctrl.stack_count(ItemSystem.REGEN_STATUS_ID), 1, "exactly one regen status")


# --- Regen SUMS, reduction takes the STRONGEST ------------------------------

func test_regen_sums_across_items_into_one_status():
	ItemInventory.grant(REGEN_UNIT_ITEM)   # 5/turn
	ItemInventory.grant(REGEN_TEAM_ITEM)   # 2/turn
	ItemInventory.equip("vineweave", REGEN_UNIT_ITEM)
	ItemInventory.set_team_item(0, REGEN_TEAM_ITEM)
	var unit := _mock_unit()

	ItemSystem.apply_loadout(unit, "vineweave")

	var active: Array[StatusCondition] = unit.ctrl.get_active()
	assert_eq(active.size(), 1, "ONE status, not one per item -- so REFRESH stays meaningful")
	# Deliberately untyped: get_active() is declared -> Array[StatusCondition], and
	# heal_per_turn only exists on the RegenStatus subclass.
	var regen = active[0]
	assert_eq(int(regen.heal_per_turn), 7, "carrying the SUMMED 5 + 2 heal")


func test_damage_reduction_takes_the_strongest_never_the_sum():
	# The project rule: reductions refresh, they never stack, sum or compound.
	var unit := _mock_unit()
	var controller: StatusController = unit.ctrl
	controller.add_status(ItemSystem.build_ward_status(15))
	controller.add_status(ItemSystem.build_ward_status(15))
	assert_eq(controller.stack_count(ItemSystem.WARD_STATUS_ID), 1, "a re-application refreshes")
	assert_almost_eq(controller.status_damage_taken_scale(), 0.85, 0.001,
		"two 15% wards are still 15%, never 30% and never 0.85 * 0.85")


func test_ward_status_scale_matches_the_authored_percent():
	var ward: StatusCondition = ItemSystem.build_ward_status(15)
	assert_almost_eq(ward.damage_taken_scale, 0.85, 0.001, "-15% damage taken == 0.85 scale")
	assert_eq(int(ward.stacking), int(StatusCondition.Stacking.REFRESH), "refresh semantics")
	assert_eq(ward.duration_turns, -1, "and it lasts the whole battle")


func test_ward_is_clamped_short_of_invulnerability():
	var ward: StatusCondition = ItemSystem.build_ward_status(500)
	assert_almost_eq(ward.damage_taken_scale, 0.10, 0.001, "a nonsense value clamps to 90% off")
	assert_gt(ward.damage_taken_scale, 0.0, "an item can never make a unit untouchable")


func test_the_ward_item_installs_its_band():
	ItemInventory.grant(WARD_ITEM)
	ItemInventory.equip("vineweave", WARD_ITEM)
	var unit := _mock_unit()
	ItemSystem.apply_loadout(unit, "vineweave")
	assert_true(unit.ctrl.has_status(ItemSystem.WARD_STATUS_ID), "the ward is active")
	assert_almost_eq(unit.ctrl.status_damage_taken_scale(), 0.85, 0.001, "at the authored 15%")


# --- Drop odds --------------------------------------------------------------

func _tally_drops(seed_value: int, rolls: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tally: Dictionary = { "none": 0, "common": 0, "rare": 0, "epic": 0 }
	for _i in range(rolls):
		var item: ItemResource = ItemSystem.roll_drop_with_rng(rng)
		if item == null:
			tally["none"] += 1
		elif int(item.rarity) == int(ItemResource.Rarity.EPIC):
			tally["epic"] += 1
		elif int(item.rarity) == int(ItemResource.Rarity.RARE):
			tally["rare"] += 1
		else:
			tally["common"] += 1
	return tally


func test_drop_distribution_matches_the_quoted_odds():
	var rolls: int = 20000
	var tally: Dictionary = _tally_drops(12345, rolls)

	assert_almost_eq(float(tally["epic"]) / rolls, 0.02, 0.01, "epics land ~2% of the time")
	assert_almost_eq(float(tally["rare"]) / rolls, 0.08, 0.02, "rares ~8%")
	assert_almost_eq(float(tally["common"]) / rolls, 0.25, 0.03, "commons ~25%")
	assert_almost_eq(float(tally["none"]) / rolls, 0.65, 0.03, "and most battles drop nothing")


func test_the_tiers_are_mutually_exclusive():
	var rolls: int = 5000
	var tally: Dictionary = _tally_drops(999, rolls)
	var total: int = int(tally["none"]) + int(tally["common"]) + int(tally["rare"]) + int(tally["epic"])
	assert_eq(total, rolls, "every roll lands in exactly one band -- one roll, not three")


func test_epics_are_rarer_than_rares_which_are_rarer_than_commons():
	var tally: Dictionary = _tally_drops(777, 20000)
	assert_lt(int(tally["epic"]), int(tally["rare"]), "epics are the rarest drop")
	assert_lt(int(tally["rare"]), int(tally["common"]), "rares sit between")


func test_drop_rolls_are_reproducible_for_a_given_seed():
	var first: Dictionary = _tally_drops(4242, 500)
	var second: Dictionary = _tally_drops(4242, 500)
	assert_eq(first, second, "the same seed rolls the same sequence")


func test_a_null_rng_is_survivable():
	assert_null(ItemSystem.roll_drop_with_rng(null), "no generator, no drop -- never a crash")


# --- Arena run payout -------------------------------------------------------

func _tally_arena(rounds_cleared: int, seed_value: int, rolls: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var tally: Dictionary = { "null": 0, "common": 0, "rare": 0, "epic": 0 }
	for _i in range(rolls):
		var item: ItemResource = ItemSystem.roll_arena_reward_with_rng(rounds_cleared, rng)
		if item == null:
			tally["null"] += 1
		elif int(item.rarity) == int(ItemResource.Rarity.EPIC):
			tally["epic"] += 1
		elif int(item.rarity) == int(ItemResource.Rarity.RARE):
			tally["rare"] += 1
		else:
			tally["common"] += 1
	return tally


func test_an_arena_run_always_pays_out():
	for rounds in [0, 1, 3, 5, 6, 12]:
		var tally: Dictionary = _tally_arena(rounds, 31337, 200)
		assert_eq(int(tally["null"]), 0, "a run that cleared %d rounds always pays an item" % rounds)


func test_a_shallow_run_pays_a_common():
	var tally: Dictionary = _tally_arena(2, 555, 300)
	assert_eq(int(tally["common"]), 300, "<=2 rounds cleared is a guaranteed Common")


func test_a_mid_run_leans_rare():
	var tally: Dictionary = _tally_arena(4, 555, 2000)
	assert_gt(int(tally["rare"]), int(tally["common"]), "3-5 rounds leans Rare")
	assert_gt(int(tally["rare"]), int(tally["epic"]), "but Epic is still the outlier")


func test_a_deep_run_has_a_real_shot_at_an_epic():
	var shallow: Dictionary = _tally_arena(4, 8080, 2000)
	var deep: Dictionary = _tally_arena(8, 8080, 2000)
	assert_gt(int(deep["epic"]), int(shallow["epic"]), "6+ rounds pays Epic far more often")
	assert_gt(float(deep["epic"]) / 2000.0, 0.25, "and it is a real chance, not a token one")


func test_arena_payout_is_reproducible_for_a_given_seed():
	assert_eq(_tally_arena(6, 24, 200), _tally_arena(6, 24, 200), "same seed, same payouts")
