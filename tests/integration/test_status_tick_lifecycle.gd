extends GutTest

## Integration test for the two combat-correctness reports that both come down to
## "the effect never happened": poison that is never observed to hurt anything, and a
## Mycothrall whose ability appears not to fire on a kill.
##
## Everything here runs on the LIVE stack -- real character-backed [Unit]s under a real
## "Map" root, the real [CombatServices] / [BoardAdapter], the real [MoveExecutor] damage
## pipeline and the REAL turn systems. Mocks would prove nothing about either report,
## because both are claims about wiring: whether the turn boundary reaches the status
## controller (on AI-owned units too), and whether the damage bus reaches the attacker's
## AbilitySystem when the blow is lethal.
##
## Spawn pattern (synthetic characters injected into CharacterLibrary._cache, live board
## rebuilt over a Map node) mirrors integration/test_ai_live_board.gd.

const GRID: Grid = preload("res://board/Grid.tres")
const CHARACTER_UNIT_SCENE: PackedScene = preload("res://game/characters/CharacterUnit.tscn")

## Authored content under test -- the shipped .tres files, not code-built stand-ins.
const POISON_PATH := "res://game/combat/status/poisoned.tres"
const BLIGHT_BURST_PATH := "res://game/combat/moves/blight_burst.tres"
const SIPHON_BITE_PATH := "res://game/combat/moves/siphon_bite.tres"
const PARASITIC_HOLD_PATH := "res://game/abilities/parasitic_hold.tres"
const INFESTED_PATH := "res://game/combat/status/infested.tres"

const POISONER_ID: StringName = &"test_status_poisoner"
const VICTIM_ID: StringName = &"test_status_victim"
const FRAGILE_ID: StringName = &"test_status_fragile"
const PARASITE_ID: StringName = &"test_status_parasite"
const REAPER_ID: StringName = &"test_status_reaper"
const FRAGILE_REAPER_ID: StringName = &"test_status_fragile_reaper"

## Poison's authored numbers, asserted once in test_poisoned_content_is_what_this_file_assumes
## so every exact-HP expectation below has a stated source.
const POISON_TICK_DAMAGE: int = 4
const POISON_TURNS: int = 3
const POISON_MAX_STACKS: int = 3

var _map_root: Node3D = null


func before_each() -> void:
	CombatServices.clear()
	_map_root = null
	_install_test_characters()


func after_each() -> void:
	CombatServices.clear()
	_map_root = null
	CharacterLibrary.clear_cache()


# --- Content fixtures ------------------------------------------------------

func _poisoned() -> StatusCondition:
	return load(POISON_PATH) as StatusCondition


func _blight_burst() -> MoveResource:
	return load(BLIGHT_BURST_PATH) as MoveResource


func _siphon_bite() -> MoveResource:
	return load(SIPHON_BITE_PATH) as MoveResource


func _parasitic_hold() -> AbilityResource:
	return load(PARASITIC_HOLD_PATH) as AbilityResource


func _infested() -> StatusCondition:
	return load(INFESTED_PATH) as StatusCondition


# --- Live-board scaffolding -------------------------------------------------

func _cell_to_world(cell: Vector2i) -> Vector3:
	return BoardAdapter.new(GRID, []).cell_to_world(cell)


func _install_test_characters() -> void:
	# A Blightcap stand-in: the AUTHORED Blight Burst is its only move, so the poison
	# that lands is the shipped one applied by the shipped effect.
	CharacterLibrary._cache[POISONER_ID] = _make_character(
		POISONER_ID, "Test Poisoner", 80, 14, [_blight_burst()], [])
	# Deep HP pool so a long poison lifecycle never ends the unit early, and 0 defense
	# so mitigation can never be confused with a missing tick.
	CharacterLibrary._cache[VICTIM_ID] = _make_character(
		VICTIM_ID, "Test Victim", 200, 10, [], [])
	# Dies to poison alone (one tick under two ticks' worth of HP).
	CharacterLibrary._cache[FRAGILE_ID] = _make_character(
		FRAGILE_ID, "Test Fragile", POISON_TICK_DAMAGE, 10, [], [])
	# A Mycothrall stand-in carrying the AUTHORED Parasitic Hold on the authored bite.
	CharacterLibrary._cache[PARASITE_ID] = _make_character(
		PARASITE_ID, "Test Parasite", 60, 13, [_siphon_bite()], [_parasitic_hold()])
	# The ON_KILL probe: same bite, but an ON_KILL ability instead, so the kill trigger
	# is observed independently of what Mycothrall happens to be authored with.
	CharacterLibrary._cache[REAPER_ID] = _make_character(
		REAPER_ID, "Test Reaper", 60, 13, [_siphon_bite()], [AbilityLibrary.vampiric()])
	# Dies to a single poison tick AND carries the ON_KILL probe, so a unit that poisons
	# ITSELF to death is observably credited with nothing.
	CharacterLibrary._cache[FRAGILE_REAPER_ID] = _make_character(
		FRAGILE_REAPER_ID, "Test Fragile Reaper", POISON_TICK_DAMAGE, 13, [], [AbilityLibrary.vampiric()])


func _make_character(
	id: StringName,
	display_name: String,
	hp: int,
	atk: int,
	moves: Array,
	abilities: Array
) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = id
	c.display_name = display_name
	c.model_scene = load("res://game/characters/models/forest/tree_grunt.glb")
	c.movement_profile = load("res://game/movement/profiles/ground_standard.tres")
	c.base_health = hp
	c.base_attack = atk
	c.base_defense = 0
	c.base_magic = 4
	c.base_magic_defense = 0
	c.base_speed = 10
	c.base_movement = 3
	c.attack_range = 1
	var typed_moves: Array[MoveResource] = []
	for m in moves:
		typed_moves.append(m)
	c.moveset = typed_moves
	var typed_abilities: Array[AbilityResource] = []
	for a in abilities:
		typed_abilities.append(a)
	c.abilities = typed_abilities
	return c


func _begin_map() -> void:
	_map_root = Node3D.new()
	_map_root.name = "Map"
	add_child_autofree(_map_root)


func _spawn(character_id: StringName, cell: Vector2i, owner: Player) -> Unit:
	var character := CharacterLibrary.get_character(character_id)
	if character == null:
		return null
	var unit: Unit = CHARACTER_UNIT_SCENE.instantiate()
	# Must be set BEFORE add_child: Unit._ready() builds stats + the StatusController /
	# AbilitySystem children from character_resource only if it is already assigned.
	unit.character_resource = character
	unit.position = _cell_to_world(cell)
	_map_root.add_child(unit)
	owner.add_unit(unit)
	return unit


func _finish_map() -> void:
	CombatServices.rebuild(_map_root)


func _slot_of(unit: Unit, move: MoveResource) -> int:
	var moveset := unit.get_moveset()
	for i in range(moveset.size()):
		if moveset[i] == move:
			return i
	return -1


func _rng(seed_value: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_value
	return r


# ===========================================================================
# REPORT 1 -- poison: application, ticking, stacking, expiry, death
# ===========================================================================

func test_poisoned_content_is_what_this_file_assumes() -> void:
	var poison := _poisoned()
	assert_not_null(poison, "the authored poison loads")
	assert_eq(poison.duration_turns, POISON_TURNS, "poison lasts 3 turns")
	assert_eq(poison.max_stacks, POISON_MAX_STACKS, "and caps at 3 stacks")
	assert_eq(poison.stacking, StatusCondition.Stacking.STACK, "it stacks rather than refreshes")
	var tick: DamageEffect = null
	for e in poison.tick_effects:
		if e is DamageEffect:
			tick = e as DamageEffect
	assert_not_null(tick, "its tick is a DamageEffect")
	assert_eq(tick.power, POISON_TICK_DAMAGE, "worth 4 a turn -- the number every HP assertion below uses")
	assert_eq(tick.category, CombatTypes.DamageCategory.TRUE,
		"as TRUE damage, so defense can never mask a tick that did fire")


func test_the_authored_blight_burst_really_poisons_a_live_unit() -> void:
	# APPLICATION, end to end: the shipped move, through the shipped executor, onto a
	# live Unit's real StatusController. Blight Burst poisons on a 50% roll, so this
	# sweeps seeds rather than trusting one -- the claim is "it CAN land", not "it always
	# does". The victim is healed between casts so the sweep cannot kill it.
	_begin_map()
	var side_a := Player.new(0, "A")
	var side_b := Player.new(1, "B")
	var poisoner := _spawn(POISONER_ID, Vector2i(2, 2), side_a)
	var victim := _spawn(VICTIM_ID, Vector2i(2, 3), side_b)
	if poisoner == null or victim == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var board = CombatServices.board()
	assert_not_null(board, "the live board exists")

	var move := _blight_burst()
	var slot := _slot_of(poisoner, move)
	assert_true(slot >= 0, "Blight Burst is in the poisoner's moveset")

	var controller = victim.get_status_controller()
	assert_not_null(controller, "a character-backed unit owns a StatusController")

	var landed := false
	for seed_value in range(40):
		victim.heal(999)
		var result: Dictionary = poisoner.perform_move(slot, Vector2i(2, 3), board, _rng(seed_value))
		assert_true(bool(result.get("success", false)),
			"the cast resolves: %s" % str(result.get("reason", "")))
		if controller.has_status(&"poisoned"):
			landed = true
			break
	assert_true(landed, "Blight Burst inflicts the authored poison on a live unit")


func test_poison_ticks_every_turn_on_the_traditional_turn_system() -> void:
	# TICKING, on the real turn system: three turns, three ticks of exactly 4, then
	# expiry. This is the whole of Report 1's "does it hurt anything" claim.
	_begin_map()
	var side := Player.new(0, "Human")
	var victim := _spawn(VICTIM_ID, Vector2i(1, 1), side)
	if victim == null:
		pending("Could not build the character-backed unit; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	ts.register_player(side)
	ts.is_active = true

	var controller = victim.get_status_controller()
	controller.add_status(_poisoned())
	var start_hp: int = victim.get_hp()

	for turn in range(POISON_TURNS):
		ts.current_turn = turn + 1
		ts._start_player_turn(side)
		await get_tree().process_frame
		assert_eq(victim.get_hp(), start_hp - POISON_TICK_DAMAGE * (turn + 1),
			"turn %d: the poison tick removed exactly 4 more HP" % [turn + 1])

	assert_false(controller.has_status(&"poisoned"),
		"a 3-turn poison is gone after its third tick")

	# A fourth turn must cost nothing -- an expired status that kept ticking would be
	# the mirror-image bug of one that never ticked at all.
	var settled_hp: int = victim.get_hp()
	ts.current_turn = POISON_TURNS + 1
	ts._start_player_turn(side)
	await get_tree().process_frame
	assert_eq(victim.get_hp(), settled_hp, "and takes nothing once it has expired")


func test_poison_ticks_on_an_AI_OWNED_unit_too() -> void:
	# The convention this project has already been bitten by: per-turn logic wired to
	# PlayerManager.player_turn_started silently stops on AI turns. An AI-owned unit
	# must bleed on exactly the same schedule as a human-owned one.
	_begin_map()
	var ai_side := Player.new(1, "AI")
	ai_side.is_ai = true
	var victim := _spawn(VICTIM_ID, Vector2i(4, 4), ai_side)
	if victim == null:
		pending("Could not build the character-backed unit; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	ts.register_player(ai_side)
	ts.is_active = true

	victim.get_status_controller().add_status(_poisoned())
	var start_hp: int = victim.get_hp()

	ts.current_turn = 1
	ts._start_player_turn(ai_side)
	await get_tree().process_frame

	assert_eq(victim.get_hp(), start_hp - POISON_TICK_DAMAGE,
		"an AI-owned unit's poison ticks on the AI's own turn -- the tick rides the TURN SYSTEM's boundary, not PlayerManager's")


func test_poison_ticks_on_the_speed_first_turn_system_too() -> void:
	# The OTHER turn system. Speed First opens ONE unit's turn at a time, so the tick
	# has to hang off the per-unit hook rather than the per-side one.
	_begin_map()
	var side := Player.new(0, "Human")
	var victim := _spawn(VICTIM_ID, Vector2i(6, 6), side)
	if victim == null:
		pending("Could not build the character-backed unit; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	ts.register_player(side)
	ts.is_active = true

	victim.get_status_controller().add_status(_poisoned())
	var start_hp: int = victim.get_hp()

	for turn in range(2):
		ts.current_turn = turn + 1
		ts._start_unit_turn(victim)
		await get_tree().process_frame
		assert_eq(victim.get_hp(), start_hp - POISON_TICK_DAMAGE * (turn + 1),
			"Speed First turn %d: the same 4 HP came off" % [turn + 1])


func test_poison_severity_is_the_stack_count_and_stops_at_the_cap() -> void:
	# STACKING, on live units: Blightcap's poison is one of the deliberate exceptions to
	# "statuses refresh" -- severity IS the number of live instances, bounded at 3.
	_begin_map()
	var side := Player.new(0, "Human")
	var single := _spawn(VICTIM_ID, Vector2i(1, 1), side)
	var stacked := _spawn(VICTIM_ID, Vector2i(3, 1), side)
	var overstacked := _spawn(VICTIM_ID, Vector2i(5, 1), side)
	if single == null or stacked == null or overstacked == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	ts.register_player(side)
	ts.is_active = true

	single.get_status_controller().add_status(_poisoned())
	for _i in range(3):
		stacked.get_status_controller().add_status(_poisoned())
	for _i in range(6):
		overstacked.get_status_controller().add_status(_poisoned())

	assert_eq(overstacked.get_status_controller().stack_count(&"poisoned"), POISON_MAX_STACKS,
		"six applications cap at three stacks")

	var single_before: int = single.get_hp()
	var stacked_before: int = stacked.get_hp()
	var over_before: int = overstacked.get_hp()

	ts.current_turn = 1
	ts._start_player_turn(side)
	await get_tree().process_frame

	assert_eq(single_before - single.get_hp(), POISON_TICK_DAMAGE,
		"one stack ticks for 4")
	assert_eq(stacked_before - stacked.get_hp(), POISON_TICK_DAMAGE * 3,
		"three stacks tick for 12 -- severity is the stack count")
	assert_eq(over_before - overstacked.get_hp(), POISON_TICK_DAMAGE * POISON_MAX_STACKS,
		"and a capped poison ticks for the cap, never more")


func test_a_poison_tick_can_kill_and_the_death_resolves() -> void:
	# DEATH BY POISON: a unit whose HP a tick takes to 0 has to die through the ordinary
	# death path -- eliminated, no longer alive, off the board -- not linger at 0 HP.
	_begin_map()
	var side := Player.new(0, "Human")
	var doomed := _spawn(FRAGILE_ID, Vector2i(7, 7), side)
	if doomed == null:
		pending("Could not build the character-backed unit; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	# Deliberately NOT registered with the turn system and left inactive: a death inside
	# a live turn defers _check_turn_completion, which on a one-sided board ends the turn
	# system and calls PlayerManager.end_game() -- global state this suite must not touch.
	# The per-unit hook is the production path either way, and the tests above already
	# prove _start_player_turn reaches it.
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())

	# GUT lambdas capture BY VALUE: an int counter would never be seen to change.
	var eliminated: Array = []
	var on_eliminated := func(unit, _killer): eliminated.append(unit)
	GameEvents.unit_eliminated.connect(on_eliminated)

	doomed.get_status_controller().add_status(_poisoned())
	ts.current_turn = 1
	ts._tick_unit_turn_start(doomed)  # resolves synchronously -- assert before the free

	GameEvents.unit_eliminated.disconnect(on_eliminated)

	assert_eq(eliminated.size(), 1, "the poison tick raised exactly one elimination")
	assert_true(is_instance_valid(doomed) and not doomed.is_alive(),
		"and the poisoned unit is dead, not sitting at 0 HP")
	await get_tree().process_frame


func test_a_status_tick_is_never_dodged() -> void:
	# THE REGRESSION THIS FILE EXISTS FOR. A tick resolves through the shared damage
	# pipeline, which rolls the defender's evasion -- and terrain avoid feeds that, so a
	# poisoned unit standing in TALL GRASS (+15 avoid) used to skip roughly one tick in
	# seven, at random, on an unseeded generator. Poison is already inside you: it lands.
	var board := _GrassBoard.new()
	var unit := _EvasiveUnit.new(100000)
	board.place(unit, Vector2i(0, 0))

	assert_gt(TerrainStats.bonus_for(unit, "evasion", board), 0,
		"the fixture really does grant terrain avoid, or this test proves nothing")

	var controller: StatusController = autofree(StatusController.new())
	controller.owner_unit = unit

	var ticks: int = 300
	for _i in range(ticks):
		# Re-applied each iteration so the 3-turn duration never runs out mid-sweep.
		controller.add_status(_poisoned())
		var before: int = unit.hp
		controller.tick_all(board)
		assert_gt(before - unit.hp, 0, "every single tick landed -- a tick is not a swing to dodge")


# ===========================================================================
# REPORT 2 -- the Mycothrall's ability on a killing blow
# ===========================================================================

func test_parasitic_hold_is_an_ON_ATTACK_ability_not_an_ON_KILL_one() -> void:
	# The crux of the report. Mycothrall's only ability fires when it HITS, and what it
	# does is plant an infestation; there is no on-kill and no on-death payload in its
	# kit at all. "It killed something and its ability did not happen" describes a kit
	# that has no kill trigger to fire.
	var ability := _parasitic_hold()
	assert_not_null(ability, "parasitic_hold.tres loads")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.ON_ATTACK,
		"Parasitic Hold fires on the ATTACK, not on the kill")
	assert_true(ability.targets_triggering_unit, "and lands on whatever it just hit")


func test_a_killing_blow_still_fires_the_attackers_ON_ATTACK_ability() -> void:
	# And it DOES fire on the blow that kills: damage_dealt is announced before
	# take_damage precisely so the victim is still there when the attacker's ability
	# resolves. The infestation lands -- on a unit that then dies with it.
	_begin_map()
	var parasite_side := Player.new(0, "Parasite")
	var prey_side := Player.new(1, "Prey")
	var parasite := _spawn(PARASITE_ID, Vector2i(2, 2), parasite_side)
	var prey := _spawn(VICTIM_ID, Vector2i(2, 3), prey_side)
	if parasite == null or prey == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var board = CombatServices.board()
	var bite := _siphon_bite()
	var slot := _slot_of(parasite, bite)
	assert_true(slot >= 0, "the bite is in its moveset")

	# One HP left: the next bite is certainly lethal.
	prey.take_damage(prey.get_hp() - 1)
	assert_eq(prey.get_hp(), 1, "the prey is one hit from death")

	var result: Dictionary = parasite.perform_move(slot, Vector2i(2, 3), board, _rng(7))
	assert_true(bool(result.get("success", false)),
		"the lethal bite resolves: %s" % str(result.get("reason", "")))
	assert_false(prey.is_alive(), "and it killed the prey")

	# The victim node is freed DEFERRED, so its components are still readable this frame.
	var prey_status = prey.get_status_controller()
	assert_not_null(prey_status, "the prey's status controller is still readable this frame")
	assert_eq(prey_status.stack_count(&"infested"), 1,
		"the ON_ATTACK ability fired on the killing blow -- the infestation was planted before the prey died")


func test_the_ON_KILL_trigger_fires_when_an_AI_OWNED_unit_lands_the_kill() -> void:
	# The other half of Report 2's suspicion: that the kill trigger only works when the
	# HUMAN swings. It is routed off the global damage/elimination bus, so the owner of
	# the killer is irrelevant -- proven here with an AI-owned killer.
	_begin_map()
	var ai_side := Player.new(0, "AI")
	ai_side.is_ai = true
	var prey_side := Player.new(1, "Prey")
	var reaper := _spawn(REAPER_ID, Vector2i(5, 5), ai_side)
	var prey := _spawn(VICTIM_ID, Vector2i(5, 6), prey_side)
	if reaper == null or prey == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var board = CombatServices.board()
	var slot := _slot_of(reaper, _siphon_bite())

	# Wound the killer so its ON_KILL heal is visible and not capped away.
	reaper.take_damage(40)
	var wounded_hp: int = reaper.get_hp()
	prey.take_damage(prey.get_hp() - 1)

	var result: Dictionary = reaper.perform_move(slot, Vector2i(5, 6), board, _rng(3))
	assert_true(bool(result.get("success", false)), "the AI's lethal bite resolves")
	assert_false(prey.is_alive(), "the AI landed the kill")
	await get_tree().process_frame

	# Siphon Bite lifesteals half of 1 damage (rounds to 1 at most); the ON_KILL heal is
	# 15, so anything at or above +14 can only have come from the kill trigger.
	assert_gt(reaper.get_hp(), wounded_hp + 13,
		"the killer's ON_KILL ability fired even though an AI owns it")


func test_two_bites_seize_control_of_a_living_host_on_the_live_board() -> void:
	# The ability's real payoff, so the report's "did not happen" has a working
	# counterexample to sit beside: against a host that SURVIVES both bites, the second
	# hit spends the infestation and hands the unit over.
	_begin_map()
	var parasite_side := Player.new(0, "Parasite")
	var prey_side := Player.new(1, "Prey")
	var parasite := _spawn(PARASITE_ID, Vector2i(2, 2), parasite_side)
	var host := _spawn(VICTIM_ID, Vector2i(2, 3), prey_side)
	if parasite == null or host == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var board = CombatServices.board()
	var slot := _slot_of(parasite, _siphon_bite())
	var status = host.get_status_controller()

	# GUT lambdas capture BY VALUE -- an Array is the only counter that survives.
	var takeovers: Array = []
	var on_controlled := func(u, _src): takeovers.append(u)
	GameEvents.unit_controlled.connect(on_controlled)

	parasite.perform_move(slot, Vector2i(2, 3), board, _rng(11))
	assert_eq(status.stack_count(&"infested"), 1, "the first bite plants one infestation")
	assert_eq(takeovers.size(), 0, "one is not yet a takeover")

	host.reset_turn_actions()
	parasite.reset_turn_actions()
	parasite.perform_move(slot, Vector2i(2, 3), board, _rng(12))

	GameEvents.unit_controlled.disconnect(on_controlled)

	assert_true(host.is_alive(), "the host survived both bites (this is the LIVING-host case)")
	assert_true(status.has_status(&"enthralled"), "the second bite seized control")
	assert_eq(status.stack_count(&"infested"), 0, "spending the infestation counter")
	assert_eq(takeovers.size(), 1, "and announced the betrayal exactly once")


# ===========================================================================
# REPORT 3 -- an INDIRECT kill belongs to whoever caused it
# ===========================================================================
#
# A poison tick used to announce the VICTIM as its own attacker, so the victim's
# AbilitySystem recorded itself as the last unit to damage it -- and
# AbilitySystem._on_unit_eliminated early-returns when the eliminated unit IS the
# listener. The net effect: nobody's ON_KILL fired on a damage-over-time kill. Ever.
#
# These run on the live stack because the elimination signal is typed (Unit, Unit) and
# the ON_KILL routing is autoload wiring -- a mock can prove none of it. The attribution
# RULE itself (dead applier, off-board applier, self-inflicted) is unit-tested in
# unit/test_indirect_kill_credit.gd.
#
# TURN-SYSTEM COVERAGE follows the same pattern as
# test_a_poison_tick_can_kill_and_the_death_resolves above: the death is driven through
# the per-unit hook on an INACTIVE turn system, because a death inside a live turn defers
# _check_turn_completion into PlayerManager.end_game -- global state this suite must not
# touch. Both systems are instantiated, and the tests further up already prove
# _start_player_turn / _start_unit_turn reach that hook on each of them.


## Inflict the AUTHORED poison on [param victim] FROM [param applier], through the
## production [ApplyStatusEffect] path (which is what stamps the applier onto the live
## instance). Returns nothing -- a failure to land would show as a missing tick.
func _poison(applier: Unit, victim: Unit, board) -> void:
	var effect := ApplyStatusEffect.new()
	effect.condition = _poisoned()
	effect.apply(_cast_at(applier, victim, board))


## Inflict the authored poison on [param unit] BY ITSELF, through the self-application
## branch (to_caster) -- the shape a self-damaging buff would take.
func _self_poison(unit: Unit, board) -> void:
	var effect := ApplyStatusEffect.new()
	effect.condition = _poisoned()
	effect.to_caster = true
	effect.apply(_cast_at(unit, unit, board))


## A single-cell ENEMY-targeted context from [param caster] onto [param target]'s cell.
func _cast_at(caster: Unit, target: Unit, board) -> MoveContext:
	var cell: Vector2i = board.cell_of(target)
	var move := MoveResource.new()
	move.move_id = &"test_poison_cast"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 0
	pattern.max_range = 12
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern
	return MoveContext.new(caster, board, move, cell, [cell] as Array[Vector2i])


## Record every damage_dealt attacker for the duration of [param body]. GUT lambdas
## capture BY VALUE, so the Array is the counter (tests/README).
func _attackers_during(body: Callable) -> Array:
	var attackers: Array = []
	var probe := func(attacker, _defender, _amount): attackers.append(attacker)
	GameEvents.damage_dealt.connect(probe)
	body.call()
	GameEvents.damage_dealt.disconnect(probe)
	return attackers


func test_a_poison_kill_fires_the_APPLIERS_on_kill_ability() -> void:
	_begin_map()
	var hunter_side := Player.new(0, "Hunter")
	var prey_side := Player.new(1, "Prey")
	var poisoner := _spawn(REAPER_ID, Vector2i(2, 2), hunter_side)
	var doomed := _spawn(FRAGILE_ID, Vector2i(6, 6), prey_side)
	if poisoner == null or doomed == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	_poison(poisoner, doomed, CombatServices.board())
	assert_true(doomed.get_status_controller().has_status(&"poisoned"), "the poison landed")

	# Wound the poisoner so its ON_KILL heal (15) is visible and not capped away, and note
	# that it is nowhere near the victim -- the credit travels with the status, not by range.
	poisoner.take_damage(40)
	var wounded_hp: int = poisoner.get_hp()

	ts.current_turn = 1
	var attackers: Array = _attackers_during(func(): ts._tick_unit_turn_start(doomed))

	assert_eq(attackers, [poisoner],
		"the tick announced the POISONER as its attacker, not the victim itself")
	assert_true(is_instance_valid(doomed) and not doomed.is_alive(), "the tick killed the victim")
	assert_eq(poisoner.get_hp(), wounded_hp + 15,
		"and the applier's ON_KILL fired -- an indirect kill is still its kill")
	await get_tree().process_frame


func test_a_poison_kill_credits_the_applier_on_the_speed_first_system_too() -> void:
	_begin_map()
	var hunter_side := Player.new(0, "Hunter")
	var prey_side := Player.new(1, "Prey")
	var poisoner := _spawn(REAPER_ID, Vector2i(2, 2), hunter_side)
	var doomed := _spawn(FRAGILE_ID, Vector2i(6, 6), prey_side)
	if poisoner == null or doomed == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())
	_poison(poisoner, doomed, CombatServices.board())
	poisoner.take_damage(40)
	var wounded_hp: int = poisoner.get_hp()

	ts.current_turn = 1
	ts._tick_unit_turn_start(doomed)

	assert_false(doomed.is_alive(), "Speed First: the tick killed the victim")
	assert_eq(poisoner.get_hp(), wounded_hp + 15,
		"and the same applier is credited -- attribution is a property of the status, not of the turn order")
	await get_tree().process_frame


func test_a_poison_kill_credits_an_AI_OWNED_applier() -> void:
	# The mirror of test_poison_ticks_on_an_AI_OWNED_unit_too: kill credit is routed off
	# the global damage bus, so who OWNS the applier is irrelevant.
	_begin_map()
	var ai_side := Player.new(0, "AI")
	ai_side.is_ai = true
	var prey_side := Player.new(1, "Prey")
	var poisoner := _spawn(REAPER_ID, Vector2i(2, 2), ai_side)
	var doomed := _spawn(FRAGILE_ID, Vector2i(6, 6), prey_side)
	if poisoner == null or doomed == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	_poison(poisoner, doomed, CombatServices.board())
	poisoner.take_damage(40)
	var wounded_hp: int = poisoner.get_hp()

	ts.current_turn = 1
	ts._tick_unit_turn_start(doomed)

	assert_false(doomed.is_alive(), "the AI's poison killed the prey")
	assert_eq(poisoner.get_hp(), wounded_hp + 15,
		"and the AI-owned applier's ON_KILL fired just the same")
	await get_tree().process_frame


func test_a_poison_whose_applier_has_died_credits_nobody() -> void:
	_begin_map()
	var hunter_side := Player.new(0, "Hunter")
	var prey_side := Player.new(1, "Prey")
	var poisoner := _spawn(REAPER_ID, Vector2i(2, 2), hunter_side)
	var doomed := _spawn(FRAGILE_ID, Vector2i(6, 6), prey_side)
	if poisoner == null or doomed == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	_poison(poisoner, doomed, CombatServices.board())

	poisoner.take_damage(9999)  # the poisoner falls before its poison finishes the job
	assert_false(poisoner.is_alive(), "the applier is dead")

	ts.current_turn = 1
	var attackers: Array = _attackers_during(func(): ts._tick_unit_turn_start(doomed))

	assert_eq(attackers.size(), 1, "the tick still announced its damage")
	assert_null(attackers[0],
		"but with NO attacker -- a kill cannot be earned by a unit that is already gone")
	assert_false(doomed.is_alive(), "and the poison still finished the victim")
	await get_tree().process_frame


func test_a_unit_that_poisons_itself_to_death_is_credited_with_nothing() -> void:
	# The precise shape of the original bug: the victim announced as its own attacker.
	# It carries the ON_KILL probe, so if the credit ever came back to it the heal would
	# show -- and a dead unit healing itself for its own death is exactly the nonsense
	# this refuses.
	_begin_map()
	var side := Player.new(0, "Solo")
	var doomed := _spawn(FRAGILE_REAPER_ID, Vector2i(6, 6), side)
	if doomed == null:
		pending("Could not build the character-backed unit; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())
	_self_poison(doomed, CombatServices.board())
	assert_true(doomed.get_status_controller().has_status(&"poisoned"), "it poisoned itself")

	ts.current_turn = 1
	var attackers: Array = _attackers_during(func(): ts._tick_unit_turn_start(doomed))

	assert_eq(attackers.size(), 1, "the self-inflicted tick is still announced")
	assert_null(attackers[0], "with no attacker -- a unit is never credited with its own death")
	assert_false(doomed.is_alive(), "and it really did kill itself")
	await get_tree().process_frame


func test_a_direct_kill_still_credits_the_unit_that_swung() -> void:
	# Regression guard on the ordinary case: nothing about redirecting INDIRECT credit
	# may disturb a plain swing, which is announced with its caster exactly as before.
	_begin_map()
	var hunter_side := Player.new(0, "Hunter")
	var prey_side := Player.new(1, "Prey")
	var reaper := _spawn(REAPER_ID, Vector2i(5, 5), hunter_side)
	var prey := _spawn(VICTIM_ID, Vector2i(5, 6), prey_side)
	if reaper == null or prey == null:
		pending("Could not build the character-backed units; skipping.")
		return
	await get_tree().process_frame
	_finish_map()

	var board = CombatServices.board()
	var slot := _slot_of(reaper, _siphon_bite())
	reaper.take_damage(40)
	var wounded_hp: int = reaper.get_hp()
	prey.take_damage(prey.get_hp() - 1)

	var attackers: Array = _attackers_during(func():
		reaper.perform_move(slot, Vector2i(5, 6), board, _rng(5)))

	assert_true(reaper in attackers, "the swing is announced with the unit that swung")
	assert_false(prey.is_alive(), "the bite killed")
	await get_tree().process_frame
	assert_gt(reaper.get_hp(), wounded_hp + 13, "and its ON_KILL fired, exactly as it always did")


# --- Local doubles ----------------------------------------------------------
#
# Deliberately local (tests/README rule 5): these exist to give ONE production path --
# the terrain-avoid lookup inside MoveContext.hit_chance -- something to read. Adding
# tile_effects_at or an evasion stat to a shared double would silently reroute every
# suite that uses it.

## A board whose every cell is tall grass, so TerrainStats reports real terrain avoid.
class _GrassBoard:
	var placements: Array = []
	var _grass = load("res://game/tiles/effects/resources/tall_grass.tres")
	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })
	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)
	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out
	func are_enemies(_a, _b) -> bool:
		return false
	func are_allies(_a, _b) -> bool:
		return true
	func tile_effects_at(_cell: Vector2i) -> Array:
		return [_grass] if _grass != null else []

## A unit with its own evasion on top of the terrain's, so the dodge chance under test
## is unmistakable rather than marginal.
class _EvasiveUnit:
	var hp: int
	var max_health: int
	func _init(p_hp: int) -> void:
		hp = p_hp
		max_health = p_hp
	func get_stat(n: String) -> int:
		return 40 if n == "evasion" else 0
	func get_base_stat(n: String) -> int:
		return get_stat(n)
	func take_damage(n: int) -> void:
		hp -= n
	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)
