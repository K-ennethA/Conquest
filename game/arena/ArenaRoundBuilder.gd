extends RefCounted
class_name ArenaRoundBuilder

## Builds an arena ROUND's actors on the freshly-loaded (unit-less) arena map: the run's
## squad on the player-0 start cells, an escalating enemy wave on the player-1 start
## cells, with each squad unit's accumulated augments applied. Arena maps ship with EMPTY
## start slots (MapLoader skips slots with no character reference -- it will not conjure a
## default unit), so the board loads empty and we fill it here. Called from
## GameWorldManager._setup_local_game BEFORE players are assigned, so the normal
## assign_units_by_parent pass then picks these units up like any other placement.

const _APPLIER := preload("res://game/arena/ArenaAugmentApplier.gd")

## Enemy fodder pool, cycled to fill a wave. The hero roster now that the player fields the
## forest units -- so both rosters get exercised in a run.
const ENEMY_POOL := ["wren_fleetfoot", "torvald_ironhide", "sable_quickarrow", "ysolde_emberwynn"]
## Centrepiece dropped into the final round's wave.
const BOSS_ID := "eldroot"


## Fill [param map_loader]'s live board with the round described by [param run] +
## [param ruleset]. Null-safe; a missing map / applier degrades to "spawn what we can".
static func build_round(map_loader, run: ArenaRun, ruleset: ArenaRuleset) -> void:
	if map_loader == null or run == null:
		return
	var map = map_loader.current_map
	if map == null:
		return

	_clear_actors(map_loader)

	var p0_cells: Array = _start_cells(map, 0)
	var p1_cells: Array = _start_cells(map, 1)

	# --- Squad (player 0), with each unit's accumulated augments ---
	var placed: int = 0
	for unit_state in run.living_squad():
		if placed >= p0_cells.size():
			break
		var cell: Vector2i = p0_cells[placed]
		placed += 1
		var unit = map_loader.spawn_unit_now({
			"position": cell,
			"player_id": 0,
			"character_id": unit_state.character_id,
			"spawn_kind": "Start",
		})
		if unit != null and _APPLIER != null:
			_APPLIER.apply(unit, unit_state, run)

	# --- Enemy wave (player 1), escalating with the round number ---
	var wave: Array = _wave_ids(run.round_index, ruleset, p1_cells.size())
	for i in range(wave.size()):
		if i >= p1_cells.size():
			break
		map_loader.spawn_unit_now({
			"position": p1_cells[i],
			"player_id": 1,
			"character_id": wave[i],
			"spawn_kind": "Reinforcement",  # waves CHARGE on arrival (see resolve_default_ai_stance)
			"ai_stance": "aggressive",
		})


## The enemy character ids for [param round_index]: 2 + round fodder (cycled), capped at
## the available cells; the final round drops in the boss as its first enemy.
static func _wave_ids(round_index: int, ruleset: ArenaRuleset, cap: int) -> Array:
	var total_rounds: int = ruleset.total_rounds if ruleset != null else 6
	var count: int = mini(2 + round_index, maxi(1, cap))
	var is_final: bool = round_index >= total_rounds
	var out: Array = []
	for i in range(count):
		if is_final and i == 0:
			out.append(BOSS_ID)
		else:
			out.append(ENEMY_POOL[(round_index + i) % ENEMY_POOL.size()])
	return out


## Every initial (Start) spawn cell on [param map] belonging to [param player_id].
static func _start_cells(map, player_id: int) -> Array:
	var cells: Array = []
	for spawn_data in map.unit_spawns:
		var pid: int = int(spawn_data.get("player_id", 0))
		if pid != player_id:
			continue
		if map.has_method("is_initial_spawn") and not map.is_initial_spawn(spawn_data):
			continue
		var pos = spawn_data.get("position", Vector2i(-1, -1))
		if pos is Vector2i and pos != Vector2i(-1, -1):
			cells.append(pos)
	return cells


## Remove anything the map may have placed under its player containers before we fill it.
## Immediate remove_child (not just queue_free) so the board -- which derives its units
## from these containers -- sees a clean slate this same frame.
static func _clear_actors(map_loader) -> void:
	var root = map_loader.map_root
	if root == null:
		return
	for container_name in ["Player1", "Player2", "Player3", "Player4"]:
		var container = root.get_node_or_null(container_name)
		if container == null:
			continue
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()
