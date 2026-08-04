extends GutTest

## TURN-SYSTEM LIFECYCLE: THE MANAGER OWNS WHAT IT IS HANDED.
##
## Turn systems are built with `.new()` and registered with TurnSystemManager without ever
## being parented -- deliberately: SpeedFirstTurnSystem's move clock RELIES on living outside
## the tree (the in-tree TurnTimer HUD drives the countdown; see the design notes at the top
## of systems/speed_first_turn_system.gd). The flip side of that design is that nothing in
## the tree will ever free them, so when the manager drops its reference -- the
## reset_for_new_game() every battle boot runs, or a registration replacing an occupied
## slot -- the manager must FREE the instance itself, or each boot leaks one parentless Node
## (the orphan integration/test_versus_intro_boot.gd used to sweep up per-test).
##
## This suite pins the fixed lifecycle:
##   1. reset_for_new_game() frees every manager-owned (parentless) system;
##   2. registering over an occupied slot frees the replaced instance;
##   3. a system somebody parented is NOT the manager's to free -- only unregistered;
##   4. the ownership fix changes nothing about the per-turn wiring: turn_started /
##      turn_ended stay connected to the manager for both shipped systems, and a fresh
##      system registered after a reset is wired identically;
##   5. a REAL battle boot + teardown cycle ends with zero orphaned turn-system nodes,
##      with no test-side sweeping.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const WORLD_SCENE := preload("res://game/world/GameWorld.tscn")

## A real shipped 2-side map, the same fixture integration/test_versus_intro_boot.gd loads.
const MAP_PATH := "res://game/maps/resources/proving_grounds.tres"

## Untyped on purpose (tests/README.md rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.set_setting().
var _guard

var _world: Node = null
var _prev_scene: Node = null
var _prev_recording: bool = true


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("selected_map_path", MAP_PATH)
	_guard.set_setting("selected_squad", [])
	_guard.set_setting("host_squad", [])
	# Solo: the boot runs straight through to an active turn system, with no versus-intro
	# hold in the way (see test_versus_intro_boot.gd for the held path).
	_guard.set_setting("game_mode", GameSettings.GameMode.SINGLE_PLAYER)
	# The boot mounts a ReplayRecorder, which WRITES user://replays when the battle is torn
	# down. A test must never leave files in the player's library.
	_prev_recording = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = false
	_clear_globals()


func after_each() -> void:
	if get_tree() != null:
		get_tree().paused = false
	_teardown_world()
	ReplayRecorder.recording_enabled = _prev_recording
	_clear_globals()
	_guard.restore()


func _clear_globals() -> void:
	if PlayerManager != null:
		PlayerManager.reset_for_new_game()
	if TurnSystemManager != null:
		TurnSystemManager.reset_for_new_game()
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("clear"):
		CombatServices.clear()
	PortraitCache.reset()


# =====================================================================================
#  Boot machinery, mirrored from integration/test_versus_intro_boot.gd
# =====================================================================================

## Instantiate the real GameWorld and make it the current scene, which is what
## GameWorldManager runs its ordinary boot against. Returns the world root.
func _boot_world() -> Node:
	var world: Node = WORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(world)
	# Set BEFORE GameWorldManager's first awaited frame resumes -- everything it mounts is
	# resolved off current_scene.
	get_tree().current_scene = world
	_world = world
	return world


## Tear the booted world down. Only ever called once the boot has finished (see
## _await_until callers), so no GameWorldManager coroutine is left suspended on a freed node.
func _teardown_world() -> void:
	if _world == null or not is_instance_valid(_world):
		_world = null
		return
	if get_tree() != null:
		get_tree().current_scene = _prev_scene
		if _world.get_parent() != null:
			_world.get_parent().remove_child(_world)
	_world.free()
	_world = null
	_prev_scene = null


## Poll [param predicate] once per frame, bounded in FRAMES (never wall-clock -- tests/README
## rule 7). Returns whether it ever came true.
func _await_until(predicate: Callable, max_frames: int = 900) -> bool:
	for _i in range(max_frames):
		if bool(predicate.call()):
			return true
		await get_tree().process_frame
	return false


# =====================================================================================
#  1-2. The manager frees what it owns
# =====================================================================================

func test_reset_for_new_game_frees_the_manager_owned_systems() -> void:
	var traditional := TraditionalTurnSystem.new()
	var speed := SpeedFirstTurnSystem.new()
	TurnSystemManager.register_turn_system(traditional)
	TurnSystemManager.register_turn_system(speed)

	TurnSystemManager.reset_for_new_game()

	assert_false(is_instance_valid(traditional),
		"reset frees the parentless Traditional system it was handed -- no orphan Node left")
	assert_false(is_instance_valid(speed),
		"and the parentless Speed First system too")
	assert_true(TurnSystemManager.available_turn_systems.is_empty(),
		"and the registry is empty for the next battle's apply_settings_to_game")


func test_registering_over_an_occupied_slot_frees_the_replaced_instance() -> void:
	# This is the boot path itself: apply_settings_to_game registers a FRESH instance every
	# battle, so a replaced slot's old instance has no owner left but the manager.
	var first := TraditionalTurnSystem.new()
	var second := TraditionalTurnSystem.new()
	TurnSystemManager.register_turn_system(first)
	TurnSystemManager.register_turn_system(second)

	assert_false(is_instance_valid(first),
		"the replaced system is freed, not leaked -- the manager held its only reference")
	assert_true(is_instance_valid(second), "the newcomer lives")
	assert_eq(TurnSystemManager.available_turn_systems.get("TRADITIONAL"), second,
		"and holds the slot")


# =====================================================================================
#  3. Ownership stops at a parent
# =====================================================================================

func test_a_parented_system_is_not_the_managers_to_free() -> void:
	var adopted := add_child_autofree(TraditionalTurnSystem.new()) as TraditionalTurnSystem
	TurnSystemManager.register_turn_system(adopted)

	TurnSystemManager.reset_for_new_game()

	assert_true(is_instance_valid(adopted),
		"a system with a parent belongs to that parent -- the manager only frees what it owns")
	assert_false(adopted.turn_started.is_connected(TurnSystemManager._on_turn_started),
		"though it is still fully unregistered: its per-turn signals are disconnected")


# =====================================================================================
#  4. The wiring is untouched by the ownership fix
# =====================================================================================

func test_per_turn_signal_wiring_survives_a_reset_cycle() -> void:
	# Per CONQUEST.md, per-turn logic rides the ACTIVE turn system's turn_started/ended,
	# which reach the rest of the game through these manager connections. The ownership fix
	# must not change when they are made.
	var first := TraditionalTurnSystem.new()
	TurnSystemManager.register_turn_system(first)
	assert_true(first.turn_started.is_connected(TurnSystemManager._on_turn_started),
		"registration wires turn_started to the manager, exactly as before the fix")
	assert_true(first.turn_ended.is_connected(TurnSystemManager._on_turn_ended),
		"and turn_ended")

	TurnSystemManager.reset_for_new_game()

	var second := SpeedFirstTurnSystem.new()
	TurnSystemManager.register_turn_system(second)
	assert_true(second.turn_started.is_connected(TurnSystemManager._on_turn_started),
		"a fresh system registered after a reset is wired identically")
	assert_true(second.turn_ended.is_connected(TurnSystemManager._on_turn_ended),
		"for the Speed First system as much as the Traditional one")


# =====================================================================================
#  5. A real boot + teardown cycle leaves nothing behind
# =====================================================================================

func test_a_battle_boot_and_teardown_cycle_leaves_no_orphaned_turn_systems() -> void:
	_boot_world()

	var started: bool = await _await_until(
		func() -> bool: return TurnSystemManager.has_active_turn_system())
	assert_true(started, "a solo battle boots straight through to an active turn system")
	if not started:
		return

	# Evidence the per-turn wiring actually FIRED for the opening turn: only the manager's
	# _on_turn_started handler marks the current player ACTIVE.
	var current: Player = TurnSystemManager.get_current_active_player()
	assert_not_null(current, "the opening turn is under way")
	if current != null:
		assert_eq(current.current_state, Player.PlayerState.ACTIVE,
			"and the manager's turn_started handler marked its player ACTIVE -- the signal fired")

	# Capture every instance the boot registered BEFORE the reset drops the references.
	var systems: Array = TurnSystemManager.available_turn_systems.values().duplicate()
	if TurnSystemManager.active_turn_system != null \
			and not (TurnSystemManager.active_turn_system in systems):
		systems.append(TurnSystemManager.active_turn_system)
	assert_gt(systems.size(), 0, "the boot registered at least one turn system")

	# The runtime teardown-for-the-next-battle path, exactly as _setup_local_game runs it.
	_teardown_world()
	PlayerManager.reset_for_new_game()
	TurnSystemManager.reset_for_new_game()

	for system in systems:
		assert_false(is_instance_valid(system),
			"teardown frees every turn system the boot registered -- no test-side sweeping needed")

	# And the whole cycle, counted: give any queue_free stragglers from the world teardown
	# their end-of-frame, then demand the suite invariant outright.
	await get_tree().process_frame
	await get_tree().process_frame
	if typeof(CombatServices) == TYPE_OBJECT and CombatServices != null \
			and CombatServices.has_method("clear"):
		CombatServices.clear()
	assert_no_new_orphans("a full battle boot + teardown cycle leaks no Nodes at all")
