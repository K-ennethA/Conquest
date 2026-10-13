extends GutTest

## [code]CharacterSelect.pickable_ids[/code] (EVOLUTION.md task 1.5): the pure roster filter.
## In open modes an evolved form is an UNLOCK -- hidden until the ledger unlocks it, then
## pickable beside its base form -- while bosses and the summon-only undead stay excluded.

const CS_SCRIPT := preload("res://menus/CharacterSelect.gd")
## The test-only Barkling -> Mycothrall edge: Mycothrall is a pickable unit, so it shows the unlock
## (Barkling's shipped Cinderbark is still a placeholder excluded from the roster).
const EvoFixture := preload("res://tests/helpers/evolution_fixture.gd")


func before_each() -> void:
	EvoFixture.install()


func after_each() -> void:
	EvoFixture.uninstall()


func test_pickable_ids_filters_bosses_excluded_and_locked_forms() -> void:
	var all_ids := CharacterLibrary.all_ids()
	var locked: Array = CS_SCRIPT.pickable_ids(all_ids, [], true)
	assert_false("mycothrall" in locked, "a locked evolved form is hidden")
	assert_true("tree_grunt" in locked, "its base form is not")
	assert_false("eldroot" in locked, "a boss is still excluded")
	assert_false("undead" in locked, "undead is still excluded")
	var unlocked: Array = CS_SCRIPT.pickable_ids(all_ids, ["mycothrall"], true)
	assert_true("mycothrall" in unlocked and "tree_grunt" in unlocked, "once unlocked both forms are pickable")
	var shown_all: Array = CS_SCRIPT.pickable_ids(all_ids, [], false)
	assert_true("mycothrall" in shown_all, "with hide_locked_forms off every form is listed")
	assert_false("eldroot" in shown_all or "undead" in shown_all, "but bosses and undead never are")
