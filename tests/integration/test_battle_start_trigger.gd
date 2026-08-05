extends GutTest

## ON_BATTLE_START -- the trigger that fires once per unit when a battle actually opens, and
## Geode's opening Crystalline Ward, which is its first content user.
##
## WHY THIS SUITE IS AN INTEGRATION SUITE. The claim is not "an AbilityResource with trigger 9
## runs its effects" -- that is [AbilitySystem.trigger], already covered. The claim is that the
## BOOT raises it: for every unit on the board, in BOTH turn systems, on the AI's units as well
## as the player's, exactly once, and never for a unit that shows up afterwards. Every one of
## those is a property of `TurnSystemBase._dispatch_battle_start_once` and of WHERE the two
## systems call it from, so it is proven against real [TraditionalTurnSystem] /
## [SpeedFirstTurnSystem] instances driving real [Unit]s on a real [CombatServices] board.
##
## THE FIFTH CLAIM, and the reason the suppression exists: a RESUMED battle boots a turn
## system too, and a booting turn system runs this pass. The snapshot's HP and shield are
## written back in restore phase 1, BEFORE the turn system exists -- so restore ORDER cannot
## win this on its own, and a Geode saved with a broken ward would come back wearing a fresh
## one. `BattleSaveManager.suppress_turn_start_tick` (restore phase 2) spends each restored
## unit's battle-start moment for exactly that reason. Both the suppressed case and the
## unsuppressed control are asserted below, so the suppression can never be deleted as
## redundant.

const OPENING_WARD := "res://game/abilities/crystalline_ward_initial.tres"
const EARNED_WARD := "res://game/abilities/crystalline_ward.tres"

const WARD_AMOUNT: int = 15
const BASE_HEALTH: int = 120

var _map_root: Node3D = null


func before_each() -> void:
	CombatServices.clear()
	_map_root = add_child_autofree(Node3D.new())
	# Rebuild against an EMPTY root on purpose. The adapter gathers its units LIVE from this
	# node, so units added afterwards are still seen -- while the rebuild's centring
	# round-trip assertion (which push_warning()s a mis-placed unit, and any engine warning
	# fails a GUT test) has nothing to check yet. Units are then placed through
	# cell_to_world, which is the same arithmetic that assertion uses.
	CombatServices.rebuild(_map_root)


func after_each() -> void:
	CombatServices.clear()
	if TurnSystemManager != null:
		TurnSystemManager.reset_for_new_game()
	_map_root = null


# =====================================================================================
#  Fixtures
# =====================================================================================

## A Geode-shaped character carrying the REAL authored ward pair, so these tests assert the
## shipped content rather than a hand-built copy of it. The model-less [CharacterResource]
## keeps the suite off the roster's .glb imports (tests/README rule 8's usual `pending`).
func _geode_character(speed: int) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"battle_start_geode"
	c.display_name = "Geode"
	c.base_health = BASE_HEALTH
	c.base_attack = 22
	c.base_defense = 20
	c.base_speed = speed
	c.base_movement = 4
	c.attack_range = 2
	var kit: Array[AbilityResource] = []
	kit.append(load(OPENING_WARD))
	kit.append(load(EARNED_WARD))
	c.abilities = kit
	return c


## A live unit standing on [param cell] of the shared board. Parented to the map root that
## _map_root's autofree owns, so it is freed with it. [param speed] is set BEFORE the node
## enters the tree, because _ready is what builds UnitStats from the resource.
func _geode(cell: Vector2i, speed: int = 8) -> Unit:
	var u := Unit.new()
	u.character_resource = _geode_character(speed)
	_map_root.add_child(u)   # in-tree -> _ready builds UnitStats + the AbilitySystem
	u.global_position = CombatServices.board().cell_to_world(cell)
	return u


func _player(id: int, is_ai: bool = false) -> Player:
	var p := Player.new(id, "P%d" % (id + 1))
	p.is_ai = is_ai
	return p


func _traditional() -> TraditionalTurnSystem:
	return add_child_autofree(TraditionalTurnSystem.new()) as TraditionalTurnSystem


func _speed_first() -> SpeedFirstTurnSystem:
	return add_child_autofree(SpeedFirstTurnSystem.new()) as SpeedFirstTurnSystem


# =====================================================================================
#  1. The grant, on a real board, in BOTH turn systems
# =====================================================================================

func test_a_traditional_boot_hands_every_unit_its_battle_start_moment() -> void:
	var mine := _geode(Vector2i(1, 1))
	var theirs := _geode(Vector2i(5, 5))
	var me := _player(0)
	var them := _player(1, true)
	me.add_unit(mine)
	them.add_unit(theirs)

	var ts := _traditional()
	ts.register_player(me)
	ts.register_player(them)

	assert_eq(mine.get_shield(), 0, "precondition: nothing is warded before the battle opens")
	assert_eq(theirs.get_shield(), 0, "on either side")

	ts.start_turn_system()

	assert_eq(mine.get_shield(), WARD_AMOUNT,
		"THE OPENING GRANT: a Traditional boot puts Geode's 15 HP ward up on turn one")
	assert_eq(theirs.get_shield(), WARD_AMOUNT,
		"and it reaches the AI-OWNED Geode too -- the pass walks every registered unit, not "
		+ "just the side whose turn opened")


func test_a_speed_first_boot_hands_every_unit_its_battle_start_moment() -> void:
	# The other system, and the harder one: Speed First opens ONE unit's turn, so a pass wired
	# to "the units of the side that just became active" would ward the fastest unit only.
	var fast := _geode(Vector2i(1, 1), 20)
	var slow := _geode(Vector2i(5, 5), 1)
	var me := _player(0)
	var them := _player(1, true)
	me.add_unit(fast)
	them.add_unit(slow)

	var ts := _speed_first()
	ts.register_player(me)
	ts.register_player(them)
	ts.start_turn_system()

	assert_eq(fast.get_shield(), WARD_AMOUNT,
		"the unit whose turn opened the battle is warded")
	assert_eq(slow.get_shield(), WARD_AMOUNT,
		"and so is the one that has not acted yet -- the grant is a BATTLE event, not a turn one")


func test_the_opening_ward_lands_before_the_first_turn_tick() -> void:
	# Ordering, stated as a rule rather than as a coincidence: ON_BATTLE_START resolves ahead
	# of the opening ON_TURN_START, so a battle-start effect is already in force when the first
	# turn's abilities read the unit.
	var unit := _geode(Vector2i(2, 2))
	var me := _player(0)
	me.add_unit(unit)
	var ts := _traditional()
	ts.register_player(me)
	ts.start_turn_system()

	var system = unit.get_ability_system()
	assert_not_null(system, "the unit has a live AbilitySystem")
	if system == null:
		return
	assert_true(bool(system.battle_start_fired()),
		"the battle-start moment is spent by the time the boot returns")
	assert_eq(int(system.turns_since_damaged()), 1,
		"and the opening turn ALSO ticked -- so the ward was granted first, then the turn began")
	assert_eq(unit.get_shield(), WARD_AMOUNT, "leaving the ward up")


# =====================================================================================
#  2. Once per battle, and never as a spawn event
# =====================================================================================

func test_a_unit_that_arrives_after_the_battle_began_is_never_warded() -> void:
	# THE SCOPE LINE. ON_BATTLE_START is "the battle began", not "a unit exists": a summon or a
	# reinforcement wave must not collect a free opening buff. If this ever needs to change it
	# is a NEW trigger (ON_SPAWN), not a widening of this one.
	var opener := _geode(Vector2i(1, 1))
	var me := _player(0)
	me.add_unit(opener)
	var ts := _traditional()
	ts.register_player(me)
	ts.start_turn_system()
	assert_eq(opener.get_shield(), WARD_AMOUNT, "precondition: the opener is warded")

	var late := _geode(Vector2i(3, 3))
	me.add_unit(late)            # adopted exactly as SpawnManager adopts a runtime spawn
	ts.register_unit(late)

	assert_eq(late.get_shield(), 0,
		"a unit that joined a battle already in progress gets nothing")
	ts._dispatch_battle_start_once()
	assert_eq(late.get_shield(), 0,
		"and the pass is spent -- re-running it cannot retroactively ward the newcomer")
	assert_eq(opener.get_shield(), WARD_AMOUNT,
		"while the unit that WAS there keeps the one ward it was given")


func test_the_pass_runs_once_however_many_turns_open() -> void:
	var unit := _geode(Vector2i(1, 1))
	var me := _player(0)
	me.add_unit(unit)
	var ts := _traditional()
	ts.register_player(me)
	ts.start_turn_system()

	unit.take_damage(WARD_AMOUNT)
	assert_eq(unit.get_shield(), 0, "a hit that fills the ward spends it")

	# Every later turn re-enters _start_player_turn, which is where the pass is called from.
	for _i in range(3):
		ts._start_player_turn(me)
	assert_eq(unit.get_shield(), 0,
		"opening later turns never re-issues the ward -- a broken ward is re-EARNED (three "
		+ "untouched turns), never re-handed out")


func test_a_geode_that_already_holds_a_full_ward_boots_to_the_same_fifteen() -> void:
	# REFRESH, NEVER STACK, at the boot boundary: the opening grant landing on a live 15 leaves
	# 15. This is what makes the two-entry authoring (opening ward + earned ward) safe by
	# construction rather than by scheduling.
	var unit := _geode(Vector2i(1, 1))
	unit.grant_shield(WARD_AMOUNT)
	var me := _player(0)
	me.add_unit(unit)
	var ts := _traditional()
	ts.register_player(me)
	ts.start_turn_system()

	assert_eq(unit.get_shield(), WARD_AMOUNT,
		"15 granted onto a live 15 refreshes to 15 -- never 30, and never any other number")


# =====================================================================================
#  3. Restore safety
# =====================================================================================

## Play a battle up to the point where the ward is broken, and return the JSON round-tripped
## snapshot entry for the unit -- captured through the REAL serializer, so its shape can never
## drift from the one the restore path reads.
func _capture_a_battle_with_a_broken_ward() -> Dictionary:
	var saved := _geode(Vector2i(1, 1))
	var me := _player(0)
	me.add_unit(saved)
	var ts := _traditional()
	ts.register_player(me)
	ts.start_turn_system()
	assert_eq(saved.get_shield(), WARD_AMOUNT, "the battle it was saved from opened warded")

	GameEvents.damage_dealt.emit(null, saved, WARD_AMOUNT + 10)
	saved.take_damage(WARD_AMOUNT + 10)
	assert_eq(saved.get_shield(), 0, "and the ward was broken before the save")
	assert_eq(saved.get_hp(), BASE_HEALTH - 10, "with the overrun costing real health")

	var entry: Dictionary = BattleSnapshot.capture_unit(saved, 0, Vector2i(1, 1), 0)
	ts.end_turn_system()
	# Through JSON, because that is how a real save reaches the restore.
	return JSON.parse_string(JSON.stringify(entry)) as Dictionary


## Replay [param entry] onto a fresh spawn in the order BattleSaveManager.restore_units uses
## (core -> statuses -> moves -> vitals LAST), which is restore phase 1.
## The saved unit is still standing on the board (nothing tears a map down here), so the
## respawn goes on its own cell -- a real restore rebuilds the map from scratch.
func _restore_phase_one(entry: Dictionary) -> Unit:
	var restored := _geode(Vector2i(6, 6))
	BattleSnapshot.apply_unit_core(restored, entry)
	BattleSnapshot.apply_unit_statuses(restored, entry)
	BattleSnapshot.apply_unit_moves(restored, entry)
	BattleSnapshot.apply_unit_vitals(restored, entry)
	return restored


func test_a_resumed_geode_comes_back_with_the_ward_it_was_saved_with() -> void:
	var entry: Dictionary = _capture_a_battle_with_a_broken_ward()

	var restored: Unit = _restore_phase_one(entry)
	assert_eq(restored.get_shield(), 0, "phase 1 wrote the SAVED ward value back: 0")
	assert_eq(restored.get_hp(), BASE_HEALTH - 10, "along with the saved HP")

	var me := _player(0)
	me.add_unit(restored)
	var ts := _traditional()
	TurnSystemManager.register_turn_system(ts)   # the turn system now EXISTS but has not started
	ts.register_player(me)

	# RESTORE PHASE 2, verbatim from GameWorldManager._setup_local_game.
	BattleSaveManager.suppress_turn_start_tick([restored], 1)

	ts.start_turn_system()

	assert_eq(restored.get_shield(), 0,
		"THE PIN: resuming drops you back into the fight you left -- a ward you had already "
		+ "lost is NOT quietly re-issued by the boot")
	assert_eq(restored.get_hp(), BASE_HEALTH - 10,
		"and the saved HP is untouched by the resume")


func test_the_resume_suppression_is_what_wins_not_the_restore_order() -> void:
	# The control for the test above, and the reason the suppression is not redundant: the
	# snapshot's vitals are applied BEFORE the turn system exists, so the battle-start pass
	# happens strictly LATER than the restore. Order alone loses. Asserted here so nobody
	# deletes the suppression on the (reasonable-sounding, wrong) grounds that "HP and shield
	# are restored last anyway".
	var entry: Dictionary = _capture_a_battle_with_a_broken_ward()

	var restored: Unit = _restore_phase_one(entry)
	var me := _player(0)
	me.add_unit(restored)
	var ts := _traditional()
	ts.register_player(me)

	ts.start_turn_system()   # phase 2 deliberately SKIPPED

	assert_eq(restored.get_shield(), WARD_AMOUNT,
		"without the phase-2 suppression the boot re-grants the ward over the restored value "
		+ "-- which is exactly the bug BattleSaveManager.suppress_turn_start_tick prevents")
