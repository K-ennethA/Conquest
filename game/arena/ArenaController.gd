extends Node

## Drives the Arena round -> draft loop and OWNS the run state across scene reloads (it is
## an autoload, so it survives each round's GameWorld load and each draft screen). One
## engine, many modes, all read from the ArenaRuleset it is handed:
##
##   start_run(ruleset) -> build squad -> ROUND (GameWorld battle) -> notify_round_ended
##       -> victory? -> DRAFT (choose_augment) -> next ROUND ... -> run finished
##
## Phase 1 is solo vs AI with full heal. Later phases flip on the economy (CURRENCY
## heal policy) and PvP (player_count > 1) by swapping the ruleset -- this loop's shape
## does not change. GameWorldManager consults is_active() to build a round from the run
## instead of the map, and calls notify_round_ended() instead of the normal end screen.
##
## NOTE (skeleton): the round currently plays the arena map's own units and drafts have
## no options yet. Wiring the run's squad + enemy waves onto the board, rolling a real
## augment pool, and applying augment effects are the first follow-up tasks; the loop,
## the state, and the engine seam they build against are all established here.

signal run_started(run)
signal round_starting(round_index)
signal round_ended(victory)
signal run_finished(victory)

enum Phase { IDLE, IN_ROUND, DRAFT, FINISHED }

const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"
const DRAFT_SCENE := "res://game/arena/ui/ArenaDraftScreen.tscn"
const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"

## Default starting squad when a run is begun without an explicit roster (content tasks
## replace this with a proper pre-run draft / roster pick).
const DEFAULT_SQUAD := ["wren_fleetfoot", "torvald_ironhide", "sable_quickarrow", "ysolde_emberwynn"]

var _ruleset: ArenaRuleset = null
var _run: ArenaRun = null
var _phase: int = Phase.IDLE


func is_active() -> bool:
	return _run != null and _phase != Phase.IDLE


func ruleset() -> ArenaRuleset:
	return _ruleset


func run() -> ArenaRun:
	return _run


func current_round() -> int:
	return _run.round_index if _run != null else 0


## Begin a fresh run under [param ruleset], build a starting squad, then load round 1.
func start_run(p_ruleset: ArenaRuleset, starting_character_ids: Array = []) -> void:
	_ruleset = p_ruleset if p_ruleset != null else ArenaRuleset.new()
	_run = ArenaRun.new()
	_run.currency = _ruleset.starting_currency
	_run.life = _ruleset.starting_life
	_run.round_index = 0

	var ids: Array = starting_character_ids
	if ids.is_empty():
		ids = DEFAULT_SQUAD.duplicate()
	for cid in ids:
		_run.add_unit(String(cid))

	run_started.emit(_run)
	_begin_next_round()


## Abandon the current run and return to IDLE (e.g. quit to menu).
func abort_run() -> void:
	_run = null
	_ruleset = null
	_phase = Phase.IDLE


## Called by GameWorldManager when an arena ROUND battle resolves, instead of the normal
## GameOverScreen: [param victory] true = the enemy wave was routed, false = the player
## squad was wiped. Advances the loop (draft on win / finish on last round or loss).
func notify_round_ended(victory: bool) -> void:
	if not is_active():
		return
	_phase = Phase.DRAFT if victory else Phase.FINISHED
	round_ended.emit(victory)
	if not victory:
		_finish_run(false)
		return
	if _ruleset != null and _run.round_index >= _ruleset.total_rounds:
		_finish_run(true)
		return
	_open_draft()


## The draft screen calls this with the chosen augment (or null to skip / no options).
func choose_augment(augment: Augment) -> void:
	if not is_active():
		return
	if augment != null:
		_grant_augment(augment)
	_begin_next_round()


## Roll the augment options the draft screen presents. Real weighted rolling from the
## ruleset's pool (rarity weights, no-dupes) is a content task; the skeleton returns an
## empty list so the draft screen simply offers "Continue".
func roll_draft_options() -> Array:
	return []


# --- internals --------------------------------------------------------------

func _begin_next_round() -> void:
	if _run == null or _ruleset == null:
		return
	_run.round_index += 1
	_phase = Phase.IN_ROUND
	round_starting.emit(_run.round_index)

	# Configure the shared engine for a solo arena round, then load the battle scene.
	# GameWorldManager sees is_active() and builds the round from the run (a follow-up
	# task) rather than the map's own units.
	if GameSettings != null:
		GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
		var map_path := _map_for_round(_run.round_index)
		if map_path != "":
			GameSettings.set_selected_map(map_path)

	get_tree().change_scene_to_file(GAME_WORLD_SCENE)


func _open_draft() -> void:
	_phase = Phase.DRAFT
	get_tree().change_scene_to_file(DRAFT_SCENE)


func _finish_run(victory: bool) -> void:
	_phase = Phase.FINISHED
	run_finished.emit(victory)
	# A proper results screen is a later task; for now end the run and return to the menu.
	_run = null
	_ruleset = null
	_phase = Phase.IDLE
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func _grant_augment(augment: Augment) -> void:
	# Record the pick on the run; the actual per-unit / per-run effect is applied at the
	# NEXT round's setup (the augment applier, a follow-up task), because each round
	# rebuilds fresh Unit nodes that must inherit the whole accumulated build.
	if augment == null:
		return
	if augment.target == Augment.Target.RUN:
		_run.run_augment_ids.append(augment.id)
	else:
		# SQUAD / SINGLE_UNIT: for the skeleton, stack squad-wide; a real SINGLE_UNIT
		# pick (choose which unit) is part of the draft-UI task.
		for unit_state in _run.squad:
			if unit_state != null:
				unit_state.add_augment(augment.id)


## Which compact arena map this round is fought on. Cycles the ruleset's pool; empty pool
## => keep whatever map GameSettings already holds (skeleton fallback).
func _map_for_round(round_index: int) -> String:
	if _ruleset != null and _ruleset.arena_map_pool.size() > 0:
		var idx: int = (round_index - 1) % _ruleset.arena_map_pool.size()
		return _ruleset.arena_map_pool[idx]
	return ""
