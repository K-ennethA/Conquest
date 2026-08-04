extends GutTest

## POST-BATTLE LOOT RECAP, proven on the REAL mounted screen.
##
## The summary could report points, casualties, kills and rank -- everything except the one
## reward the player actually keeps. There was no public "what dropped from the battle that
## just ended" accessor for a foreign screen to read; [ItemSystem] now keeps a per-battle
## drop latch and answers [method ItemSystem.drops_this_battle], and this file pins both
## halves: the latch's lifecycle, and the rows the mounted [GameOverScreen] renders from it.
##
## MOUNTED, NOT CONSTRUCTED. tests/unit/test_game_over_screen.gd deliberately builds the
## screen with .new() and never adds it to the tree, so _ready() (and therefore the entire
## UI) never runs -- which is right for the tally/decision logic it covers and useless for
## a rendering claim. Everything here instantiates the shipped .tscn and adds it to the
## tree, so the nodes asserted on are the ones the player would see. The rows are found by
## NAME through find_child, not through a script member, so a row that was built but never
## parented would fail.
##
## _populate_summary() is called directly rather than show_result(): the real reveal pauses
## the tree (get_tree().paused = true), which a test must never leave behind. Population is
## the whole of the rendering contract; the reveal animation is not what is under test.
##
## GLOBAL STATE: the drop latch is process-wide static (it has to be -- award() is static
## and the Arena run payout calls it with no ItemSystem in hand), and granting writes the
## collection. Both are cleared/redirected in before_each AND after_each, so a failing
## assertion cannot leak into the next suite or the player's real save (tests/README rules
## 3 and 4).

const TEMP_SAVE_PATH := "user://test_game_over_drops.json"
const SCREEN_SCENE := preload("res://game/ui/screens/GameOverScreen.tscn")

## Shipped items, used as drop payloads. Names are asserted against the resource itself
## rather than hard-coded, so a content rename cannot make this file lie.
const DROP_A := "heartwood_charm"
const DROP_B := "sagebloom_poultice"
const DROP_C := "hollowbark_ward"
const DROP_D := "ironbark_sigil"
const DROP_E := "swiftspore_boots"

var _screen: GameOverScreen = null


func before_all() -> void:
	ItemInventory.set_save_path(TEMP_SAVE_PATH)
	ItemLibrary.rescan()


func before_each() -> void:
	ItemInventory.reset()
	ItemSystem.begin_battle_drop_log()
	_screen = SCREEN_SCENE.instantiate() as GameOverScreen
	add_child_autofree(_screen)


func after_each() -> void:
	# Cleared even when a test failed part-way: this latch is process-wide.
	ItemSystem.begin_battle_drop_log()
	ItemInventory.reset()
	_screen = null


func after_all() -> void:
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
	ItemInventory.reset()


# --- Helpers ----------------------------------------------------------------

## Grant [param ids] through the PRODUCTION entry point, so the latch is filled exactly the
## way a real battle fills it (rolled -> awarded -> granted -> saved -> recorded) rather
## than by poking the array.
func _drop(ids: Array) -> void:
	for id in ids:
		var item: ItemResource = ItemLibrary.get_item(String(id))
		assert_not_null(item, "the fixture item '%s' is in the library" % String(id))
		ItemSystem.award(item, null)


## The live DropRows container, found by NAME in the mounted screen's tree.
func _rows_box() -> VBoxContainer:
	return _screen.find_child("DropRows", true, false) as VBoxContainer


## Every Label text rendered anywhere inside the drop block, in tree order.
func _rendered_texts() -> Array[String]:
	var out: Array[String] = []
	var box: VBoxContainer = _rows_box()
	if box == null:
		return out
	_collect_labels(box, out)
	return out


func _collect_labels(node: Node, out: Array[String]) -> void:
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		_collect_labels(child, out)


## True when any rendered label contains [param needle].
func _rendered_contains(needle: String) -> bool:
	for text in _rendered_texts():
		if text.find(needle) >= 0:
			return true
	return false


func _display_name(id: String) -> String:
	var item: ItemResource = ItemLibrary.get_item(id)
	return item.display_name if item != null else id


# ===========================================================================
#  THE LATCH -- lifecycle and shape
# ===========================================================================

func test_a_battle_that_dropped_nothing_reports_an_empty_latch() -> void:
	assert_eq(ItemSystem.drops_this_battle(), [] as Array[String],
		"no grant, no drops -- and an EMPTY answer, never a null one")


func test_an_awarded_item_is_recorded_on_the_latch() -> void:
	_drop([DROP_A])
	assert_eq(ItemSystem.drops_this_battle(), [DROP_A] as Array[String],
		"the single grant entry point records what it granted")


func test_the_latch_keeps_drops_in_the_order_they_landed() -> void:
	_drop([DROP_B, DROP_A, DROP_C])
	assert_eq(ItemSystem.drops_this_battle(), [DROP_B, DROP_A, DROP_C] as Array[String],
		"the recap reads like a log, not a set")


func test_the_latch_records_a_repeat_of_the_same_item_twice() -> void:
	_drop([DROP_A, DROP_A])
	assert_eq(ItemSystem.drops_this_battle().size(), 2,
		"two copies really were earned -- de-duplicating would under-report the reward")


func test_beginning_a_battle_forgets_the_previous_battle() -> void:
	_drop([DROP_A, DROP_B])
	ItemSystem.begin_battle_drop_log()
	assert_eq(ItemSystem.drops_this_battle(), [] as Array[String],
		"the latch is per-BATTLE; last battle's loot is not this battle's news")


func test_a_mounted_item_system_clears_the_latch_at_battle_start() -> void:
	# setup() is the battle-start moment: GameWorldManager frees and rebuilds this node per
	# battle, so the clear has to live there and not in _ready or a caller's discipline.
	_drop([DROP_A])
	var system: ItemSystem = add_child_autofree(ItemSystem.new())
	system.setup()
	assert_eq(ItemSystem.drops_this_battle(), [] as Array[String],
		"standing up the per-battle item runtime starts a fresh drop log")


func test_the_accessor_hands_back_a_copy() -> void:
	_drop([DROP_A])
	var first: Array[String] = ItemSystem.drops_this_battle()
	first.append("tampered")
	assert_eq(ItemSystem.drops_this_battle().size(), 1,
		"a reader mutating what it was handed must not edit the record")


func test_awarding_nothing_records_nothing() -> void:
	ItemSystem.award(null, null)
	assert_eq(ItemSystem.drops_this_battle(), [] as Array[String],
		"a roll that produced no item is not a drop")


func test_a_drop_is_really_granted_as_well_as_recorded() -> void:
	# The latch must never be able to claim loot the player did not actually receive.
	_drop([DROP_A])
	assert_eq(ItemInventory.owned_count(DROP_A), 1,
		"what the summary lists is what the collection gained")


# ===========================================================================
#  THE RENDERED ROWS (real mounted scene)
# ===========================================================================

func test_the_drop_block_exists_in_the_built_screen() -> void:
	assert_not_null(_rows_box(),
		"the mounted screen really builds a DropRows container inside its REWARDS section")


func test_a_battle_with_no_drops_renders_no_row_at_all() -> void:
	_screen._populate_summary()
	var box: VBoxContainer = _rows_box()
	assert_false(box.visible, "nothing dropped means the block is not shown")
	assert_eq(box.get_child_count(), 0,
		"and NOT an 'Items found: none' row -- silence, per the section's budget discipline")


func test_a_single_drop_renders_its_name() -> void:
	_drop([DROP_A])
	_screen._populate_summary()
	var box: VBoxContainer = _rows_box()
	assert_true(box.visible, "a battle that paid out shows the block")
	assert_true(_rendered_contains(_display_name(DROP_A)),
		"the item is named on the summary: '%s'" % _display_name(DROP_A))


func test_a_drop_row_carries_the_items_inventory_glyph() -> void:
	# Items render as "<icon_hint> <display_name>" everywhere they are listed (the loadout
	# screen's team chips are the reference); the recap must read the same way.
	_drop([DROP_A])
	_screen._populate_summary()
	var item: ItemResource = ItemLibrary.get_item(DROP_A)
	assert_false(item.icon_hint.strip_edges().is_empty(),
		"the fixture item has a glyph, or this test proves nothing")
	assert_true(_rendered_contains(item.icon_hint),
		"the row shows the same glyph the inventory shows")


func test_every_drop_under_the_cap_is_named() -> void:
	_drop([DROP_A, DROP_B, DROP_C])
	_screen._populate_summary()
	for id in [DROP_A, DROP_B, DROP_C]:
		assert_true(_rendered_contains(_display_name(id)),
			"three drops, three named rows -- '%s' is listed" % _display_name(id))
	assert_false(_rendered_contains("more"),
		"and nothing overflows at exactly the cap")


func test_the_block_is_capped_with_a_plus_n_more_tail() -> void:
	# The casualty rows' pattern, applied verbatim: the card's height budget does not care
	# which section grew.
	_drop([DROP_A, DROP_B, DROP_C, DROP_D, DROP_E])
	_screen._populate_summary()
	assert_true(_rendered_contains("+2 more"),
		"five drops past a cap of three collapse into a '+2 more' tail")
	assert_false(_rendered_contains(_display_name(DROP_D)),
		"the fourth drop is folded into the tail rather than given its own row")
	assert_false(_rendered_contains(_display_name(DROP_E)),
		"and so is the fifth")


func test_the_first_three_drops_are_the_ones_shown() -> void:
	_drop([DROP_A, DROP_B, DROP_C, DROP_D])
	_screen._populate_summary()
	for id in [DROP_A, DROP_B, DROP_C]:
		assert_true(_rendered_contains(_display_name(id)),
			"the rows shown are the FIRST three to drop -- '%s'" % _display_name(id))
	assert_true(_rendered_contains("+1 more"), "with the remainder counted")


func test_repopulating_does_not_stack_rows() -> void:
	# _populate_summary is safe to call more than once (show_result guards re-entry, but the
	# method itself must not accumulate) -- a second pass that doubled the rows would blow
	# the card's height budget silently.
	_drop([DROP_A])
	_screen._populate_summary()
	await get_tree().process_frame   # queue_free'd children leave on the next frame
	_screen._populate_summary()
	await get_tree().process_frame

	var named: int = 0
	for text in _rendered_texts():
		if text == _display_name(DROP_A):
			named += 1
	assert_eq(named, 1, "one drop is still exactly one row after a second population pass")


func test_an_unresolvable_id_is_still_listed_rather_than_silently_dropped() -> void:
	# A shipped item later removed from the content dir: the player earned it and owns it, so
	# under-reporting the reward is worse than printing a raw id.
	ItemSystem.begin_battle_drop_log()
	ItemSystem._drops_this_battle.append("a_retired_item")
	_screen._populate_summary()
	assert_true(_rows_box().visible, "the block still shows")
	assert_true(_rendered_contains("a_retired_item"),
		"and the unresolvable drop is listed under its id, not invented a name for")


func test_the_drop_block_never_disturbs_the_rest_of_the_rewards_section() -> void:
	# Budget discipline: the new block is additive. The points figures the section already
	# reported must still be there and still be filled in.
	_drop([DROP_A, DROP_B])
	_screen._populate_summary()
	assert_false(_screen._gained_value.text.is_empty(), "POINTS EARNED still reports")
	assert_false(_screen._balance_value.text.is_empty(), "and so does BALANCE")


# ===========================================================================
#  ARENA -- drops still accrue, the summary just never appears
# ===========================================================================

func test_arena_suppresses_the_summary_but_not_the_latch() -> void:
	# An arena ROUND never reveals this screen (the run's own results screen is arena's
	# summary), and the run's guaranteed payout goes through the same award() -- so the
	# accessor must keep recording it without the suppressed screen interfering either way.
	_screen._arena_run_at_start = true
	_drop([DROP_A])
	_screen.show_result(GameOverScreen.OUTCOME_VICTORY, "VICTORY", "All enemies defeated!")

	assert_false(_screen.is_shown(), "the screen stays down for an arena round")
	assert_false(_rows_box().visible, "so no drop row is rendered")
	assert_eq(ItemSystem.drops_this_battle(), [DROP_A] as Array[String],
		"but the run's payout is still recorded, for whoever does report it")
	assert_false(get_tree().paused, "and a suppressed reveal never paused the tree")
