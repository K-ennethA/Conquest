extends GutTest

## [MatchLoadouts] -- the item/skin replication that makes a networked match look and
## SIMULATE the same on both machines.
##
## Three things are pinned here, because each one fails silently and expensively:
##
##   1. THE CARD IS WHITELISTED AT THE BOUNDARY. Everything stored came off the wire as an
##      untrusted peer Dictionary. An id the local libraries do not know, an id announced in
##      the wrong scope, a skin announced against a character it was not authored for, or a
##      value that is not even a string must be DROPPED -- never applied, never a crash. There
##      is no server-side ownership proof, so this whitelist is the only thing standing
##      between "the opponent equipped a Ward" and "the opponent equipped anything it likes".
##   2. A REMOTE UNIT IS EQUIPPED BY THE LOCAL CODE PATH. The buffs a peer's unit receives are
##      computed by [method ItemSystem.apply_loadout_items] -- the same static that equips our
##      own units -- so the two simulations cannot drift. A second implementation would.
##   3. SOLO IS UNTOUCHED. With no networked lobby seating us, [method MatchLoadouts.is_active]
##      reads false and every read falls back to the pre-existing "local human, slot 0" rule.

const TEMP_SAVE_PATH := "user://test_match_loadouts.json"

const UNIT_ITEM := "heartwood_charm"       # +5 Max HP, unit-scope
const TEAM_ITEM := "elderroot_standard"    # +2 Defense, team-scope
const REGEN_ITEM := "sagebloom_poultice"   # heal 5/turn, unit-scope
const WARD_ITEM := "hollowbark_ward"       # -15% damage taken, unit-scope

const BLIGHTCAP_SKIN := "blightcap_ashcap"
const VINEWEAVE_SKIN := "vineweave_emberroot"

const HOST_SLOT := 0
const CLIENT_SLOT := 1


# --- Doubles ----------------------------------------------------------------

## The unit shape the item application actually touches (see test_item_system.gd), plus the
## two fields the OWNERSHIP routing reads: a character_resource for "whose loadout" and an
## owner_player for "which slot".
class MockUnit extends RefCounted:
	var stats: Dictionary = { "health": 20, "attack": 5, "defense": 3, "movement": 3 }
	var unit_stats = null
	var ctrl: StatusController = null
	var character_resource: CharacterResource = null
	var owner_player: Player = null

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


## Stand-in for the PlayerProfile autoload: the skin source, duck-typed exactly as
## [MatchLoadouts] and [Unit] read it.
class FakeProfile extends RefCounted:
	var equipped: Dictionary = {}
	func get_equipped_skin(character_id: String) -> String:
		return String(equipped.get(character_id, ""))


var _controllers: Array = []


func before_all() -> void:
	ItemInventory.set_save_path(TEMP_SAVE_PATH)
	ItemLibrary.rescan()


func before_each() -> void:
	ItemInventory.reset()
	MatchLoadouts.clear()


func after_each() -> void:
	# Static, process-wide, and read by the battle: a leak here would equip the NEXT suite's
	# units from this suite's fake opponent.
	MatchLoadouts.clear()
	ItemInventory.reset()
	for controller in _controllers:
		if is_instance_valid(controller):
			controller.free()
	_controllers.clear()


func after_all() -> void:
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
	ItemInventory.reset()


## A mock unit wired to a live StatusController (the regen / ward channels need one). The
## controller is a Node created inside a RefCounted, which autofree cannot reach -- so it is
## swept explicitly in after_each (tests/README rule 2).
func _mock_unit(character_id: String = "", slot: int = -1) -> MockUnit:
	var unit := MockUnit.new()
	var controller: StatusController = StatusController.new()
	controller.owner_unit = unit
	unit.ctrl = controller
	_controllers.append(controller)
	if not character_id.is_empty():
		var character := CharacterResource.new()
		character.character_id = StringName(character_id)
		unit.character_resource = character
	if slot >= 0:
		unit.owner_player = Player.new(slot, "Slot %d" % slot)
	return unit


# --- Building the local card ------------------------------------------------

func test_the_local_card_carries_worn_items_team_items_and_skins() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)
	var profile := FakeProfile.new()
	profile.equipped["vineweave"] = VINEWEAVE_SKIN

	var card: Dictionary = MatchLoadouts.build_local_payload(profile)

	assert_eq(String((card["equipped"] as Dictionary).get("vineweave", "")), UNIT_ITEM,
		"the card names the item each character wears")
	assert_eq((card["team"] as Array).size(), 1, "and the filled team slots, empties dropped")
	assert_eq(String((card["team"] as Array)[0]), TEAM_ITEM, "with the team item's id")
	assert_eq(String((card["skins"] as Dictionary).get("vineweave", "")), VINEWEAVE_SKIN,
		"and the cosmetic skin each character wears")


func test_an_empty_collection_still_announces_a_card() -> void:
	# "I equipped nothing" is an ANSWER: it is what stops the other machine falling back to
	# its own inventory for our units.
	var card: Dictionary = MatchLoadouts.build_local_payload(null)
	assert_eq((card["equipped"] as Dictionary).size(), 0, "nothing worn")
	assert_eq((card["team"] as Array).size(), 0, "no team items")
	assert_eq((card["skins"] as Dictionary).size(), 0, "no skins without a profile")


func test_a_missing_profile_costs_only_the_skins() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var card: Dictionary = MatchLoadouts.build_local_payload(null)
	assert_eq(String((card["equipped"] as Dictionary).get("vineweave", "")), UNIT_ITEM,
		"a headless harness with no PlayerProfile still replicates items")


func test_a_skin_the_local_library_does_not_know_never_reaches_the_wire() -> void:
	var profile := FakeProfile.new()
	profile.equipped["vineweave"] = "vineweave_from_the_future"
	var card: Dictionary = MatchLoadouts.build_local_payload(profile)
	assert_eq((card["skins"] as Dictionary).size(), 0,
		"an id this build cannot resolve is not announced at all")


# --- The trust boundary -----------------------------------------------------

func test_unknown_item_ids_are_dropped() -> void:
	var card: Dictionary = MatchLoadouts.normalise({
		"equipped": { "vineweave": "definitely_not_an_item" },
		"team": ["also_not_an_item"],
	})
	assert_eq((card["equipped"] as Dictionary).size(), 0, "an unknown worn item is dropped")
	assert_eq((card["team"] as Array).size(), 0, "and so is an unknown team item")


func test_an_item_announced_in_the_wrong_scope_is_dropped() -> void:
	# The rule the local inventory enforces: a UNIT item cannot sit in a team slot, and a TEAM
	# item is not worn by one character. Without this a peer could announce its unit item in
	# both team slots and triple a bonus the local rules would never let it hold.
	var card: Dictionary = MatchLoadouts.normalise({
		"equipped": { "vineweave": TEAM_ITEM },
		"team": [UNIT_ITEM],
	})
	assert_eq((card["equipped"] as Dictionary).size(), 0, "a TEAM item cannot be worn")
	assert_eq((card["team"] as Array).size(), 0, "a UNIT item cannot fill a team slot")


func test_a_skin_authored_for_another_character_is_dropped() -> void:
	var card: Dictionary = MatchLoadouts.normalise({
		"skins": { "vineweave": BLIGHTCAP_SKIN },
	})
	assert_eq((card["skins"] as Dictionary).size(), 0,
		"a peer cannot dress its Vineweave in a Blightcap skin")


func test_a_valid_skin_survives_the_boundary() -> void:
	var card: Dictionary = MatchLoadouts.normalise({
		"skins": { "blightcap": BLIGHTCAP_SKIN, "vineweave": VINEWEAVE_SKIN },
	})
	assert_eq((card["skins"] as Dictionary).size(), 2, "both correctly-authored skins are kept")
	assert_eq(String((card["skins"] as Dictionary)["blightcap"]), BLIGHTCAP_SKIN,
		"and resolve to the announced id")


func test_the_team_list_can_never_exceed_the_local_slot_count() -> void:
	var flood: Array = []
	for _i in range(64):
		flood.append(TEAM_ITEM)
	var card: Dictionary = MatchLoadouts.normalise({ "team": flood })
	assert_eq((card["team"] as Array).size(), ItemInventory.TEAM_SLOTS,
		"a peer gets exactly the team slots this build has, never more")


func test_garbage_of_every_shape_normalises_to_an_empty_card() -> void:
	for junk in [
		{ "equipped": "not a dictionary", "team": 7, "skins": [1, 2, 3] },
		{ "equipped": { "vineweave": { "nested": true } }, "team": [[UNIT_ITEM]], "skins": { 5: 6 } },
		{},
	]:
		var card: Dictionary = MatchLoadouts.normalise(junk)
		assert_eq((card["equipped"] as Dictionary).size(), 0, "nothing worn survives %s" % [junk])
		assert_eq((card["team"] as Array).size(), 0, "no team item survives %s" % [junk])
		assert_eq((card["skins"] as Dictionary).size(), 0, "no skin survives %s" % [junk])


func test_an_over_long_id_is_refused() -> void:
	var absurd: String = "x".repeat(MatchLoadouts.MAX_ID_LENGTH + 1)
	var card: Dictionary = MatchLoadouts.normalise({ "equipped": { absurd: UNIT_ITEM } })
	assert_eq((card["equipped"] as Dictionary).size(), 0, "an id past the cap is not even looked up")


func test_a_stored_card_is_returned_as_a_copy() -> void:
	MatchLoadouts.set_peer_loadout(CLIENT_SLOT, { "equipped": { "vineweave": UNIT_ITEM } })
	var first: Dictionary = MatchLoadouts.get_peer_loadout(CLIENT_SLOT)
	(first["equipped"] as Dictionary).clear()
	assert_eq((MatchLoadouts.get_peer_loadout(CLIENT_SLOT)["equipped"] as Dictionary).size(), 1,
		"a caller mutating the answer cannot edit the stored record")


func test_a_slot_that_never_announced_reads_as_an_empty_card() -> void:
	assert_false(MatchLoadouts.has_peer_loadout(CLIENT_SLOT), "nobody announced")
	var card: Dictionary = MatchLoadouts.get_peer_loadout(CLIENT_SLOT)
	assert_eq((card["equipped"] as Dictionary).size(), 0, "and the answer is empty, never null")


# --- Which items a slot has in force ----------------------------------------

func test_a_peers_items_are_its_worn_item_then_its_team_items() -> void:
	MatchLoadouts.set_local_slot(HOST_SLOT)
	MatchLoadouts.set_peer_loadout(CLIENT_SLOT, {
		"equipped": { "vineweave": UNIT_ITEM },
		"team": [TEAM_ITEM],
	})

	var ids: Array[String] = MatchLoadouts.item_ids_for(CLIENT_SLOT, "vineweave")
	assert_eq(ids.size(), 2, "the worn item and the team item both apply")
	assert_eq(ids[0], UNIT_ITEM, "the personal item leads -- same order the local path builds")
	assert_eq(ids[1], TEAM_ITEM, "then the team items")

	var other: Array[String] = MatchLoadouts.item_ids_for(CLIENT_SLOT, "blightcap")
	assert_eq(other.size(), 1, "a character wearing nothing still gets the team items")


func test_a_peers_items_resolve_to_the_local_resources() -> void:
	MatchLoadouts.set_peer_loadout(CLIENT_SLOT, { "equipped": { "vineweave": UNIT_ITEM } })
	var items: Array[ItemResource] = MatchLoadouts.items_for(CLIENT_SLOT, "vineweave")
	assert_eq(items.size(), 1, "the announced item resolved")
	assert_eq(String(items[0].id), UNIT_ITEM, "against THIS build's library, not the sender's word")


# --- Whose skin does a unit wear --------------------------------------------

func test_offline_only_slot_zero_wears_a_skin() -> void:
	var profile := FakeProfile.new()
	profile.equipped["vineweave"] = VINEWEAVE_SKIN

	assert_false(MatchLoadouts.is_active(), "no lobby seated us, so replication is off")
	assert_eq(MatchLoadouts.skin_for(0, "vineweave", profile), VINEWEAVE_SKIN,
		"the local human wears their skin, exactly as before")
	assert_eq(MatchLoadouts.skin_for(1, "vineweave", profile), "",
		"an AI fielding the same character keeps its canonical look")


func test_networked_our_own_slot_still_reads_the_local_profile() -> void:
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	var profile := FakeProfile.new()
	profile.equipped["vineweave"] = VINEWEAVE_SKIN

	assert_eq(MatchLoadouts.skin_for(CLIENT_SLOT, "vineweave", profile), VINEWEAVE_SKIN,
		"our units wear what WE equipped, never a replicated card")


func test_networked_a_peers_slot_wears_the_skin_it_announced() -> void:
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, { "skins": { "blightcap": BLIGHTCAP_SKIN } })
	var profile := FakeProfile.new()   # we own nothing; the look must come off the wire

	assert_eq(MatchLoadouts.skin_for(HOST_SLOT, "blightcap", profile), BLIGHTCAP_SKIN,
		"the opponent's unit renders with the opponent's skin on OUR machine")
	assert_eq(MatchLoadouts.skin_for(HOST_SLOT, "vineweave", profile), "",
		"a character they announced no skin for keeps the default look")


func test_a_peer_that_announced_a_bad_skin_gets_the_default_look() -> void:
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, { "skins": { "blightcap": "not_a_skin" } })
	assert_eq(MatchLoadouts.skin_for(HOST_SLOT, "blightcap", null), "",
		"an unresolvable id reads as default, never a crash")


func test_clearing_switches_replication_back_off() -> void:
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, { "skins": { "blightcap": BLIGHTCAP_SKIN } })
	MatchLoadouts.clear()

	assert_false(MatchLoadouts.is_active(), "a new lobby (or a solo battle) starts clean")
	assert_eq(MatchLoadouts.peer_count(), 0, "and last match's opponent is forgotten")
	assert_eq(MatchLoadouts.skin_for(HOST_SLOT, "blightcap", null), "",
		"so the previous opponent's skin cannot appear in the next match")


# --- Application on spawn ---------------------------------------------------

func test_a_remote_units_buffs_come_off_the_replicated_card() -> void:
	# The whole point: the opponent equipped these, WE own nothing, and their unit must still
	# carry every channel -- stats, regen and the damage-reduction ward.
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, {
		"equipped": { "vineweave": WARD_ITEM },
		"team": [TEAM_ITEM],
	})
	var system: ItemSystem = autofree(ItemSystem.new())
	var unit := _mock_unit("vineweave", HOST_SLOT)

	assert_true(system.apply_to_unit(unit), "the peer's loadout was applied")
	assert_eq(unit.get_stat("defense"), 5, "their team item's +2 Defense landed on base 3")
	assert_true(unit.ctrl.has_status(ItemSystem.WARD_STATUS_ID), "and their ward is active")
	assert_almost_eq(unit.ctrl.status_damage_taken_scale(), 0.85, 0.001,
		"at exactly the authored 15%, which is what the other machine will also compute")


func test_a_remote_unit_is_equipped_by_the_same_maths_as_a_local_one() -> void:
	# Two units, identical equips -- one resolved from the LOCAL inventory, one from a
	# REPLICATED card. If the numbers ever differ, the two peers have desynced.
	ItemInventory.grant(REGEN_ITEM)
	ItemInventory.grant(TEAM_ITEM)
	ItemInventory.equip("vineweave", REGEN_ITEM)
	ItemInventory.set_team_item(0, TEAM_ITEM)

	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, {
		"equipped": { "vineweave": REGEN_ITEM },
		"team": [TEAM_ITEM],
	})

	var system: ItemSystem = autofree(ItemSystem.new())
	var ours := _mock_unit("vineweave", CLIENT_SLOT)
	var theirs := _mock_unit("vineweave", HOST_SLOT)
	system.apply_to_unit(ours)
	system.apply_to_unit(theirs)

	assert_eq(theirs.get_stat("defense"), ours.get_stat("defense"),
		"the same items produce the same stats on either side of the wire")
	assert_eq(theirs.ctrl.get_active().size(), ours.ctrl.get_active().size(),
		"and the same status channels")
	# Deliberately untyped: get_active() is declared -> Array[StatusCondition], and
	# heal_per_turn only exists on the RegenStatus subclass.
	var their_regen = theirs.ctrl.get_active()[0]
	var our_regen = ours.ctrl.get_active()[0]
	assert_eq(int(their_regen.heal_per_turn), int(our_regen.heal_per_turn),
		"carrying the identical summed regen")


func test_our_own_units_never_read_a_replicated_card() -> void:
	# A hostile peer that announced a card for OUR slot must not be able to change our units.
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(CLIENT_SLOT, { "equipped": { "vineweave": WARD_ITEM } })

	var system: ItemSystem = autofree(ItemSystem.new())
	var unit := _mock_unit("vineweave", CLIENT_SLOT)
	system.apply_to_unit(unit)

	assert_eq(unit.get_stat("health"), 25, "our slot took OUR +5 Max HP from the local inventory")
	assert_false(unit.ctrl.has_status(ItemSystem.WARD_STATUS_ID),
		"and not the ward a peer tried to announce on our behalf")


func test_applying_a_replicated_loadout_twice_applies_it_once() -> void:
	# The sweep runs at every turn boundary; the latch has to hold on the remote path too.
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, { "equipped": { "vineweave": UNIT_ITEM } })
	var system: ItemSystem = autofree(ItemSystem.new())
	var unit := _mock_unit("vineweave", HOST_SLOT)

	for _i in range(10):
		system.apply_to_unit(unit)
	assert_eq(unit.get_stat("health"), 25, "still exactly +5 after ten sweeps")


func test_a_peer_that_never_announced_is_not_equipped_from_our_inventory() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	MatchLoadouts.set_local_slot(CLIENT_SLOT)

	var system: ItemSystem = autofree(ItemSystem.new())
	var unit := _mock_unit("vineweave", HOST_SLOT)

	assert_false(system._should_equip(unit), "a silent peer is skipped rather than guessed at")
	assert_eq(unit.get_stat("health"), 20, "its stats are exactly as spawned")


func test_an_ai_or_neutral_owner_is_never_equipped_in_a_networked_match() -> void:
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, { "team": [TEAM_ITEM] })
	var system: ItemSystem = autofree(ItemSystem.new())

	var bot := _mock_unit("vineweave", HOST_SLOT)
	bot.owner_player.is_ai = true
	assert_false(system._should_equip(bot), "a bot-driven slot carries no player loadout")

	var camp := _mock_unit("vineweave", HOST_SLOT)
	camp.owner_player.is_neutral = true
	assert_false(system._should_equip(camp), "and neither does a neutral camp")


# --- Solo stays exactly as it was -------------------------------------------

func test_offline_the_local_human_is_still_the_only_one_equipped() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var system: ItemSystem = autofree(ItemSystem.new())

	var human := _mock_unit("vineweave", 0)
	var enemy := _mock_unit("vineweave", 1)

	assert_true(system._should_equip(human), "slot 0 is the human, exactly as before")
	assert_false(system._should_equip(enemy), "and nobody else is equipped offline")

	system.apply_to_unit(human)
	assert_eq(human.get_stat("health"), 25, "reading the LOCAL inventory, not a card")


func test_offline_the_loadout_source_ignores_the_slot_entirely() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	for slot in [-1, 0, 1, 7]:
		var items: Array[ItemResource] = ItemSystem.loadout_for_slot(slot, "vineweave")
		assert_eq(items.size(), 1, "slot %d still resolves through the local inventory" % slot)


func test_the_public_apply_loadout_entry_point_is_unchanged() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip("vineweave", UNIT_ITEM)
	var unit := _mock_unit()
	assert_true(ItemSystem.apply_loadout(unit, "vineweave"), "the original signature still applies")
	assert_eq(unit.get_stat("health"), 25, "with the same result it always had")
	assert_false(ItemSystem.apply_loadout(unit, "vineweave"), "and the same idempotence")


# --- The spawn-side skin hook on a real Unit --------------------------------

## A live [Unit] owned by [param slot], with no CharacterModel. The character_resource is
## assigned AFTER the node enters the tree so _ready() never reaches the model pipeline --
## these tests are about the skin RESOLUTION hook, not the mesh.
func _skinless_unit(slot: int) -> Unit:
	var unit := Unit.new()
	var stats := UnitStatsResource.new()
	stats.unit_name = "SkinProbe"
	stats.max_health = 10
	unit.stats_resource = stats
	add_child_autofree(unit)
	var character := CharacterResource.new()
	character.character_id = &"blightcap"
	unit.character_resource = character
	unit.owner_player = Player.new(slot, "Slot %d" % slot)
	return unit


func test_a_real_unit_resolves_a_peers_announced_skin() -> void:
	MatchLoadouts.set_local_slot(CLIENT_SLOT)
	MatchLoadouts.set_peer_loadout(HOST_SLOT, { "skins": { "blightcap": BLIGHTCAP_SKIN } })

	var unit: Unit = _skinless_unit(HOST_SLOT)

	assert_eq(unit._equipped_skin_id("blightcap"), BLIGHTCAP_SKIN,
		"the opponent's unit resolves the skin THEY announced, not one of ours")


func test_a_real_unit_offline_still_asks_only_for_slot_zero() -> void:
	var unit: Unit = _skinless_unit(1)

	assert_eq(unit._equipped_skin_id("blightcap"), "",
		"an offline enemy keeps its canonical look, exactly as before")
