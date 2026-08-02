extends GutTest

## THE DOUBLE-APPLY PIN, plus the per-unit snapshot round trip that carries it.
##
## Mid-battle save/resume has exactly one way to go quietly, catastrophically wrong. A unit's
## live stats are:
##
##     base (CharacterResource)  +  permanent item deltas  +  live status modifiers
##
## A restored unit is a FRESH spawn: its stats are rebuilt from its CharacterResource, and
## then its items and statuses are applied AGAIN. So if the snapshot stored the RESULT of that
## sum and wrote it back, every term would land twice -- +5 Max HP would become +10, and a
## -2 movement slow would become -4. Worse, the failure is invisible: nothing errors, the unit
## is simply wrong, and it compounds every time the player saves and resumes.
##
## [BattleSnapshot] therefore stores the INPUTS (which statuses are live, and for how much
## longer) and exactly ONE derived value that genuinely cannot be recomputed: current HP.
## Restore replays the same order the battle did -- spawn, items, statuses, HP last.
##
## These tests drive that replay on REAL character-backed [Unit]s (real UnitStats, real
## StatusController, real MovesetController, the real [ItemSystem] applier), because every one
## of the terms above lives in a different component and a mock would prove nothing about how
## they compose.

const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")
const RUBBLE_SLOWED := "res://game/combat/status/rubble_slowed.tres"

## A deterministic synthetic character, injected straight into the CharacterLibrary cache so
## these tests never depend on the shipped roster's tuning. Base movement 3 is the number the
## slow test is written against.
const TEST_ID: StringName = &"test_save_restore_unit"
const BASE_HEALTH: int = 40
const BASE_MOVEMENT: int = 3

## +5 Max HP, unit-scope. The item whose delta must land exactly once.
const UNIT_ITEM := "heartwood_charm"
const TEMP_INVENTORY_PATH := "user://test_battle_save_restore_items.json"

var _map_root: Node3D = null


func before_all() -> void:
	ItemInventory.set_save_path(TEMP_INVENTORY_PATH)
	ItemLibrary.rescan()


func after_all() -> void:
	if FileAccess.file_exists(TEMP_INVENTORY_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_INVENTORY_PATH))
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
	ItemInventory.reset()


func before_each() -> void:
	CombatServices.clear()
	ItemInventory.reset()
	CharacterLibrary._cache[TEST_ID] = _test_character()
	_map_root = add_child_autofree(Node3D.new())


func after_each() -> void:
	CombatServices.clear()
	CharacterLibrary.clear_cache()
	ItemInventory.reset()
	_map_root = null


# --- The double-apply pin ---------------------------------------------------

func test_a_slowed_unit_resumes_at_the_slowed_speed() -> void:
	# THE case from the brief: a unit carrying rubble-slow, saved at movement 1, must come
	# back at movement 1 -- not 3 (the slow lost) and not -1 (the slow applied twice).
	var saved: Unit = _spawn()
	_slow(saved)
	assert_eq(saved.get_stat("movement"), BASE_MOVEMENT - 2,
		"precondition: rubble-slow takes 2 movement off the base 3")

	var entry: Dictionary = _capture(saved)
	var resumed: Unit = _restore(entry)

	assert_eq(resumed.get_stat("movement"), BASE_MOVEMENT - 2,
		"the resumed unit is slowed exactly as much as it was when the battle was saved")
	assert_eq(resumed.get_base_stat("movement"), BASE_MOVEMENT,
		"and its BASE movement is untouched, so the slow can still be lifted")


func test_the_slow_is_lifted_normally_after_a_resume() -> void:
	# The mirror-image failure: a restored modifier that is never revoked would be permanent.
	var saved: Unit = _spawn()
	_slow(saved)
	var resumed: Unit = _restore(_capture(saved))

	# Untyped on purpose: Unit.get_status_controller() is declared -> Node, so a typed local
	# would make the analyser reject remove_status(). Same reason the runtime code does it.
	var controller = resumed.get_status_controller()
	controller.remove_status(&"rubble_slowed")
	assert_eq(resumed.get_stat("movement"), BASE_MOVEMENT,
		"clearing the restored status returns the unit to its base movement")


func test_restoring_the_same_status_twice_still_lands_once() -> void:
	# Restore is not re-entrant by design, but the REFRESH rule is what makes a double call
	# harmless -- the same guarantee that stops a re-inflicted slow from deepening.
	var saved: Unit = _spawn()
	_slow(saved)
	var entry: Dictionary = _capture(saved)

	var resumed: Unit = _restore(entry)
	BattleSnapshot.apply_unit_statuses(resumed, entry)

	assert_eq(resumed.status_stack_count(&"rubble_slowed"), 1,
		"a second restore refreshes the one instance, it never adds another")
	assert_eq(resumed.get_stat("movement"), BASE_MOVEMENT - 2,
		"so the movement penalty does not deepen")


func test_remaining_status_duration_is_what_is_restored() -> void:
	var saved: Unit = _spawn()
	var controller = saved.get_status_controller()
	controller.add_status(load(RUBBLE_SLOWED).duplicate(true))
	controller.tick_all(null)  # one turn burned: 2 -> 1 remaining

	var entry: Dictionary = _capture(saved)
	assert_eq(int((entry["statuses"][0] as Dictionary).get("turns_left", -1)), 1,
		"the snapshot stores the REMAINING turns, not the authored duration")

	var resumed: Unit = _restore(entry)
	var live = resumed.get_status_controller()
	var restored: StatusCondition = live.get_active()[0]
	assert_eq(restored.turns_left, 1,
		"so the slow has one turn left after a resume, not a fresh two")


# --- Items: the ItemSystem latch --------------------------------------------

func test_an_equipped_item_lands_exactly_once_across_a_resume() -> void:
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip(String(TEST_ID), UNIT_ITEM)

	var saved: Unit = _spawn()
	ItemSystem.apply_loadout(saved, String(TEST_ID))
	assert_eq(saved.max_health, BASE_HEALTH + 5, "precondition: +5 Max HP landed once")
	saved.take_damage(10)
	var saved_hp: int = saved.current_health

	var resumed: Unit = _restore(_capture(saved))

	assert_eq(resumed.max_health, BASE_HEALTH + 5,
		"the item's Max HP delta is re-applied ONCE, never twice")
	assert_eq(resumed.current_health, saved_hp,
		"and current HP is exactly what was saved -- the item did not top it back up")


func test_the_turn_start_sweep_no_ops_on_a_restored_unit() -> void:
	# ItemSystem re-sweeps the whole board at EVERY turn boundary. Its idempotence latch lives
	# in unit meta, which a freshly spawned restored unit does not have -- so the restore has
	# to go through the real applier, which is what sets the latch. If it ever stopped doing
	# that, this unit would gain +5 Max HP per turn, forever.
	ItemInventory.grant(UNIT_ITEM)
	ItemInventory.equip(String(TEST_ID), UNIT_ITEM)

	var saved: Unit = _spawn()
	ItemSystem.apply_loadout(saved, String(TEST_ID))
	var resumed: Unit = _restore(_capture(saved))

	assert_true(resumed.has_meta(ItemSystem.APPLIED_META),
		"the restore left ItemSystem's own applied latch set")
	assert_false(ItemSystem.apply_loadout(resumed, String(TEST_ID)),
		"so the next turn-start sweep reports 'already equipped' and does nothing")
	assert_eq(resumed.max_health, BASE_HEALTH + 5,
		"and Max HP is still the single item delta after that sweep")


# --- The rest of the per-unit round trip ------------------------------------

func test_every_saved_unit_field_comes_back() -> void:
	var saved: Unit = _spawn()
	saved.take_damage(13)
	saved.grant_shield(6)
	saved.configure_ai_behavior(Vector2i(4, 5), "aggressive", 3, 7)
	saved.mark_moved()
	var saved_moves = saved.get_moveset_controller()
	saved_moves.on_used(saved.get_move(0))

	var entry: Dictionary = _capture(saved)
	# Through JSON, because that is how a real save reaches the restore.
	entry = JSON.parse_string(JSON.stringify(entry))
	var resumed: Unit = _restore(entry)

	assert_eq(resumed.current_health, saved.current_health, "current HP round-trips")
	assert_eq(resumed.get_shield(), 6, "a temporary shield round-trips")
	assert_eq(resumed.get_home_cell(), Vector2i(4, 5), "the AI home cell round-trips")
	assert_eq(resumed.get_ai_stance(), "aggressive", "the resolved AI stance round-trips")
	assert_eq(resumed.get_aggro_range(), 3, "the defensive wake distance round-trips")
	assert_eq(resumed.get_leash_radius(), 7, "the leash round-trips")
	assert_true(resumed.has_moved_this_turn, "a unit that had already moved cannot move again")
	var resumed_moves = resumed.get_moveset_controller()
	assert_eq(resumed_moves.remaining(resumed.get_move(0)), 3,
		"and the move it spent is still on its full remaining cooldown")


func test_a_unit_with_nothing_on_it_round_trips_cleanly() -> void:
	var saved: Unit = _spawn()
	var resumed: Unit = _restore(_capture(saved))
	var controller = resumed.get_status_controller()
	assert_eq(resumed.current_health, BASE_HEALTH, "an untouched unit resumes at full health")
	assert_eq(resumed.get_stat("movement"), BASE_MOVEMENT, "with its base movement")
	assert_eq(controller.get_active().size(), 0, "and no statuses")


# --- Fixtures ---------------------------------------------------------------

## Spawn a live, character-backed [Unit] under the test's map root. Parenting it to a node
## ALREADY in the tree is what makes _ready run, which is what builds UnitStats /
## StatusController / MovesetController from the CharacterResource.
func _spawn() -> Unit:
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	unit.character_resource = CharacterLibrary.get_character(TEST_ID)
	_map_root.add_child(unit)
	return unit


## Inflict the rubble-slow (-2 movement, 2 turns) through the real status path.
## Untyped local on purpose -- Unit.get_status_controller() is declared -> Node.
func _slow(unit: Unit) -> void:
	var controller = unit.get_status_controller()
	controller.add_status(load(RUBBLE_SLOWED).duplicate(true))


func _capture(unit: Unit) -> Dictionary:
	return BattleSnapshot.capture_unit(unit, 0, Vector2i(2, 2), 0)


## Replay [param entry] onto a FRESH unit in the exact order [BattleSaveManager] uses:
## core -> items -> statuses -> moves -> vitals last. The order is the point of the test.
func _restore(entry: Dictionary) -> Unit:
	var unit: Unit = _spawn()
	BattleSnapshot.apply_unit_core(unit, entry)
	ItemSystem.apply_loadout(unit, String(entry.get("character_id", "")))
	BattleSnapshot.apply_unit_statuses(unit, entry)
	BattleSnapshot.apply_unit_moves(unit, entry)
	BattleSnapshot.apply_unit_vitals(unit, entry)
	return unit


func _test_character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = TEST_ID
	c.display_name = "Save Restore Dummy"
	c.base_health = BASE_HEALTH
	c.base_attack = 10
	c.base_defense = 5
	c.base_magic = 4
	c.base_magic_defense = 4
	c.base_speed = 8
	c.base_movement = BASE_MOVEMENT
	c.attack_range = 1
	c.moveset = [_test_move()] as Array[MoveResource]
	return c


## One move with a 3-turn cooldown, so the cooldown half of the snapshot has something real
## to carry.
func _test_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_save_strike"
	m.display_name = "Test Strike"
	m.cooldown = 3
	m.category = CombatTypes.DamageCategory.PHYSICAL
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	return m
