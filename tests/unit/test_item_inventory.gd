extends GutTest

## [ItemInventory] is the player's collection: what they own, who wears what, and what sits in
## the shared team slots. It is process-wide static state that persists across every scene, so
## the things worth pinning are the rules that are easy to get subtly wrong:
##
##   * YOU OWN COPIES, NOT SLOTS -- equipping an item whose every copy is in use MOVES it off
##     its current holder rather than duplicating it, and reports where it came from.
##   * The two TEAM slots draw from the same pool of copies as the characters do.
##   * The JSON round-trip preserves ownership, equipment and team slots exactly.
##
## Every test runs against a TEMP save path, never the player's real user://items.json.

const TEMP_SAVE_PATH := "user://test_item_inventory.json"

# Two real content ids, so a change that removes them from the library fails loudly here
# rather than leaving the suite quietly testing nothing.
const UNIT_ITEM := "heartwood_charm"
const OTHER_UNIT_ITEM := "ironbark_sigil"
const TEAM_ITEM := "elderroot_standard"
const OTHER_TEAM_ITEM := "verdant_banner"


func before_all() -> void:
	ItemInventory.set_save_path(TEMP_SAVE_PATH)


func before_each() -> void:
	ItemInventory.reset()


func after_all() -> void:
	# Leave no test file behind, and put the store back on the real save so nothing that runs
	# after this suite reads/writes the temp path.
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
	ItemInventory.reset()


# --- Ownership --------------------------------------------------------------

func test_a_fresh_inventory_is_empty():
	assert_eq(ItemInventory.total_owned(), 0, "nothing owned yet")
	assert_eq(ItemInventory.owned_ids().size(), 0, "no owned ids")
	assert_eq(ItemInventory.equipped_item("vineweave"), "", "nobody is wearing anything")


func test_grant_accumulates_copies():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.grant(UNIT_ITEM, 2)
	assert_eq(ItemInventory.owned_count(UNIT_ITEM), 3, "three copies owned")
	assert_eq(ItemInventory.total_owned(), 3, "and that is the whole collection")


func test_grant_ignores_non_positive_counts():
	ItemInventory.grant(UNIT_ITEM, 0)
	ItemInventory.grant(UNIT_ITEM, -5)
	assert_eq(ItemInventory.owned_count(UNIT_ITEM), 0, "a zero/negative grant does nothing")


func test_owned_items_with_scope_filters_to_what_you_have():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.grant(TEAM_ITEM)
	var unit_items: Array[ItemResource] = ItemInventory.owned_items_with_scope(ItemResource.Scope.UNIT)
	var team_items: Array[ItemResource] = ItemInventory.owned_items_with_scope(ItemResource.Scope.TEAM)
	assert_eq(unit_items.size(), 1, "exactly the one owned unit item")
	assert_eq(String(unit_items[0].id), UNIT_ITEM, "and it is the right one")
	assert_eq(team_items.size(), 1, "exactly the one owned team item")
	assert_eq(String(team_items[0].id), TEAM_ITEM, "and it is the right one")


# --- Equipping --------------------------------------------------------------

func test_equip_puts_the_item_on_the_character():
	ItemInventory.grant(UNIT_ITEM)
	var taken_from: String = ItemInventory.equip("vineweave", UNIT_ITEM)
	assert_eq(taken_from, "", "nothing had to be moved")
	assert_eq(ItemInventory.equipped_item("vineweave"), UNIT_ITEM, "vineweave is wearing it")
	assert_eq(ItemInventory.free_copies(UNIT_ITEM), 0, "the only copy is now in use")


func test_equipped_resource_resolves_the_live_item():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var item: ItemResource = ItemInventory.equipped_resource("vineweave")
	assert_not_null(item, "the equipped item resolves")
	assert_eq(String(item.id), UNIT_ITEM, "to the right resource")


func test_equipping_an_unowned_item_is_refused():
	# Refused rather than silently allowed: an inventory that can equip what you do not own is
	# an inventory that can hand out free stats.
	ItemInventory.equip("vineweave", UNIT_ITEM)
	assert_eq(ItemInventory.equipped_item("vineweave"), "", "an unowned item is not equipped")


func test_equipping_empty_clears_the_slot():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	ItemInventory.equip("vineweave", "")
	assert_eq(ItemInventory.equipped_item("vineweave"), "", "passing an empty id unequips")
	assert_eq(ItemInventory.free_copies(UNIT_ITEM), 1, "the copy is free again")


func test_unequip_frees_the_copy():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	ItemInventory.unequip("vineweave")
	assert_eq(ItemInventory.equipped_item("vineweave"), "", "the slot is empty")
	assert_eq(ItemInventory.free_copies(UNIT_ITEM), 1, "the copy is back in the pool")


# --- The MOVE rule (you own copies, not slots) -------------------------------

func test_equipping_the_last_copy_elsewhere_moves_it():
	ItemInventory.grant(UNIT_ITEM)          # exactly ONE copy
	ItemInventory.equip("vineweave", UNIT_ITEM)

	var taken_from: String = ItemInventory.equip("blightcap", UNIT_ITEM)

	assert_eq(taken_from, "vineweave", "the equip reports who it was taken from")
	assert_eq(ItemInventory.equipped_item("blightcap"), UNIT_ITEM, "blightcap now wears it")
	assert_eq(ItemInventory.equipped_item("vineweave"), "", "vineweave no longer does")
	assert_eq(ItemInventory.owned_count(UNIT_ITEM), 1, "and it was MOVED, never duplicated")


func test_a_second_copy_means_no_move_is_needed():
	ItemInventory.grant(UNIT_ITEM, 2)
	ItemInventory.equip("vineweave", UNIT_ITEM)

	var taken_from: String = ItemInventory.equip("blightcap", UNIT_ITEM)

	assert_eq(taken_from, "", "with a spare copy nothing is disturbed")
	assert_eq(ItemInventory.equipped_item("vineweave"), UNIT_ITEM, "vineweave keeps its copy")
	assert_eq(ItemInventory.equipped_item("blightcap"), UNIT_ITEM, "blightcap gets the spare")
	assert_eq(ItemInventory.free_copies(UNIT_ITEM), 0, "both copies are now in use")


func test_re_equipping_the_same_item_is_a_no_op():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var taken_from: String = ItemInventory.equip("vineweave", UNIT_ITEM)
	assert_eq(taken_from, "", "you cannot steal an item from yourself")
	assert_eq(ItemInventory.equipped_item("vineweave"), UNIT_ITEM, "still wearing it")


func test_swapping_a_characters_item_frees_the_old_one():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.grant(OTHER_UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	ItemInventory.equip("vineweave", OTHER_UNIT_ITEM)
	assert_eq(ItemInventory.equipped_item("vineweave"), OTHER_UNIT_ITEM, "the new item is worn")
	assert_eq(ItemInventory.free_copies(UNIT_ITEM), 1, "the displaced item returns to the pool")


func test_holder_of_finds_the_wearer():
	ItemInventory.grant(UNIT_ITEM)
	assert_eq(ItemInventory.holder_of(UNIT_ITEM), "", "nobody holds it yet")
	ItemInventory.equip("petalfang", UNIT_ITEM)
	assert_eq(ItemInventory.holder_of(UNIT_ITEM), "petalfang", "petalfang holds it")


# --- Team slots -------------------------------------------------------------

func test_team_items_always_reports_every_slot():
	var slots: Array[String] = ItemInventory.team_items()
	assert_eq(slots.size(), ItemInventory.TEAM_SLOTS, "always exactly TEAM_SLOTS entries")
	for slot_value in slots:
		assert_eq(slot_value, "", "and they start empty")


func test_setting_and_clearing_a_team_slot():
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)
	assert_eq(ItemInventory.team_items()[0], TEAM_ITEM, "slot 0 holds it")
	assert_eq(ItemInventory.team_resources().size(), 1, "and it resolves for the battle side")

	ItemInventory.clear_team_item(0)
	assert_eq(ItemInventory.team_items()[0], "", "the slot is empty again")
	assert_eq(ItemInventory.team_resources().size(), 0, "and nothing resolves")


func test_both_team_slots_hold_different_items():
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.grant(OTHER_TEAM_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)
	ItemInventory.set_team_item(1, OTHER_TEAM_ITEM)
	var resolved: Array[ItemResource] = ItemInventory.team_resources()
	assert_eq(resolved.size(), 2, "both slots contribute")


func test_team_slot_draws_from_the_same_copy_pool_as_characters():
	# One copy cannot be both worn and standing in a team slot -- that is the whole point of
	# free_copies. (Using a unit-scope item keeps the test about COPIES, not about scope.)
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var note: String = ItemInventory.set_team_item(0, UNIT_ITEM)
	assert_eq(note, "vineweave", "the slot reports taking it off vineweave")
	assert_eq(ItemInventory.equipped_item("vineweave"), "", "vineweave gave it up")
	assert_eq(ItemInventory.team_items()[0], UNIT_ITEM, "the slot has it now")
	assert_eq(ItemInventory.owned_count(UNIT_ITEM), 1, "still one copy in the world")


func test_equipping_can_pull_an_item_out_of_a_team_slot():
	# The mirror of the test above: the pool is shared in both directions, and the caller is
	# told where the item came from in the same display-ready wording either way.
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.set_team_item(0, UNIT_ITEM)
	var taken_from: String = ItemInventory.equip("vineweave", UNIT_ITEM)
	assert_eq(taken_from, "team slot 1", "the equip reports the slot it emptied")
	assert_eq(ItemInventory.team_items()[0], "", "the slot gave it up")
	assert_eq(ItemInventory.equipped_item("vineweave"), UNIT_ITEM, "vineweave has it now")


func test_moving_an_item_between_team_slots():
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)
	var note: String = ItemInventory.set_team_item(1, TEAM_ITEM)
	assert_eq(note, "team slot 1", "the move is reported in human 1-based slot numbers")
	assert_eq(ItemInventory.team_items()[0], "", "slot 0 gave it up")
	assert_eq(ItemInventory.team_items()[1], TEAM_ITEM, "slot 1 has it")


func test_out_of_range_team_slots_are_ignored():
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.set_team_item(-1, TEAM_ITEM)
	ItemInventory.set_team_item(ItemInventory.TEAM_SLOTS, TEAM_ITEM)
	assert_eq(ItemInventory.free_copies(TEAM_ITEM), 1, "nothing was equipped anywhere")


func test_unowned_team_item_is_refused():
	ItemInventory.set_team_item(0, TEAM_ITEM)
	assert_eq(ItemInventory.team_items()[0], "", "you cannot slot what you do not own")


# --- Persistence ------------------------------------------------------------

func test_save_load_round_trip_preserves_everything():
	ItemInventory.grant(UNIT_ITEM, 2)
	ItemInventory.grant(OTHER_UNIT_ITEM)
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	ItemInventory.equip("blightcap", OTHER_UNIT_ITEM)
	ItemInventory.set_team_item(1, TEAM_ITEM)
	assert_true(ItemInventory.save(), "the store writes")

	# Drop the cache and force a real read back off disk.
	ItemInventory.set_save_path(TEMP_SAVE_PATH)
	ItemInventory.ensure_loaded()

	assert_eq(ItemInventory.owned_count(UNIT_ITEM), 2, "counts survive")
	assert_eq(ItemInventory.owned_count(OTHER_UNIT_ITEM), 1, "so does the second item")
	assert_eq(ItemInventory.equipped_item("vineweave"), UNIT_ITEM, "equipment survives")
	assert_eq(ItemInventory.equipped_item("blightcap"), OTHER_UNIT_ITEM, "for every character")
	assert_eq(ItemInventory.team_items()[1], TEAM_ITEM, "and the team slot index is preserved")
	assert_eq(ItemInventory.team_items()[0], "", "including which slot was left empty")


func test_loading_a_partial_save_is_repaired_not_rejected():
	# A save written by an older build (or hand-edited) must not lose the player's collection.
	var file: FileAccess = FileAccess.open(TEMP_SAVE_PATH, FileAccess.WRITE)
	assert_not_null(file, "the temp save opens for writing")
	file.store_string(JSON.stringify({ "owned": { UNIT_ITEM: 1 } }))
	file.close()

	ItemInventory.set_save_path(TEMP_SAVE_PATH)
	ItemInventory.ensure_loaded()

	assert_eq(ItemInventory.owned_count(UNIT_ITEM), 1, "the section that was present is kept")
	assert_eq(ItemInventory.equipped_item("vineweave"), "", "the missing sections default empty")
	assert_eq(ItemInventory.team_items().size(), ItemInventory.TEAM_SLOTS, "team slots are rebuilt")


func test_reset_clears_memory_without_touching_disk():
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.save()
	ItemInventory.reset()
	assert_eq(ItemInventory.total_owned(), 0, "the in-memory store is empty")

	ItemInventory.set_save_path(TEMP_SAVE_PATH)  # forces a re-read
	assert_eq(ItemInventory.owned_count(UNIT_ITEM), 1, "but the saved file was untouched")
