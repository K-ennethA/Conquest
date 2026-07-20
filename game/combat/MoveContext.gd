extends RefCounted
class_name MoveContext

## Runtime state handed to each [MoveEffect] while a move resolves.
##
## Decouples effects from the concrete game: effects talk to [member board] and
## to units through small duck-typed interfaces, so the same effect works in the
## live game and against a mock board in tests.
##
## Expected [member board] interface (any object with these methods):
##   cell_of(unit) -> Vector2i
##   units_at(cell: Vector2i) -> Array
##   are_enemies(a, b) -> bool
##   are_allies(a, b) -> bool
##   set_tile(cell: Vector2i, tile_id) -> void
##   move_unit(unit, to_cell: Vector2i) -> void
##
## Expected unit interface: get_stat(name) -> int, take_damage(n), heal(n),
## add_stat_modifier(stat, amount, duration).

var caster                       ## the acting unit
var board                        ## board query/mutation adapter (see above)
var move: MoveResource
var aim_cell: Vector2i
var affected_cells: Array[Vector2i]
var results: Array[Dictionary] = []

## Optional event-bus override for effects that announce themselves (see
## [DamageEffect]). Left null in the live game, where those effects fall back to
## the [code]GameEvents[/code] autoload; tests inject a mock bus here.
var event_bus = null

## RNG for hit/crit rolls. Injected by [MoveExecutor] (seedable for deterministic
## replay / networked peers); a randomized one is created lazily if left null.
var rng: RandomNumberGenerator = null
## Per-target hit/crit resolution, cached so multiple effects on the same move
## share one roll per target (a miss misses everything, a crit crits everything).
var _hit_cache: Dictionary = {}


func _init(p_caster, p_board, p_move: MoveResource, p_aim: Vector2i, p_cells: Array[Vector2i]) -> void:
	caster = p_caster
	board = p_board
	move = p_move
	aim_cell = p_aim
	affected_cells = p_cells


func get_caster_stat(stat_name: String) -> int:
	if caster and caster.has_method("get_stat"):
		return caster.get_stat(stat_name)
	return 0


## Percent chance (0..100) this move lands on [param target]: move accuracy minus
## the target's evasion.
func hit_chance(target) -> float:
	if move == null:
		return 100.0
	# Terrain avoid (FE model): the tile under the defender adds to its evasion,
	# summed at combat time from the cell's passive tile effects.
	var evasion := float(_stat(target, "evasion")) + float(TerrainStats.bonus_for(target, "evasion", board))
	return clampf(move.accuracy * 100.0 - evasion, 0.0, 100.0)


## Percent chance (0..100) of a critical hit on [param target]: the move's base
## crit plus the caster's crit stat.
func crit_chance(_target) -> float:
	if move == null:
		return 0.0
	return clampf(move.crit_chance * 100.0 + float(get_caster_stat("crit")), 0.0, 100.0)


## Resolve (once, then cache) whether this move hits [param target] and whether it
## crits. Returns { hit, crit, hit_pct, crit_pct }.
func resolve_hit(target) -> Dictionary:
	if _hit_cache.has(target):
		return _hit_cache[target]
	var hp := hit_chance(target)
	var cp := crit_chance(target)
	var r := _get_rng()
	var did_hit := r.randf() * 100.0 < hp
	var did_crit := did_hit and r.randf() * 100.0 < cp
	var out := { "hit": did_hit, "crit": did_crit, "hit_pct": hp, "crit_pct": cp }
	_hit_cache[target] = out
	return out


func _get_rng() -> RandomNumberGenerator:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.randomize()
	return rng


func _stat(unit, stat_name: String) -> int:
	if unit and unit.has_method("get_stat"):
		return unit.get_stat(stat_name)
	return 0


## Units in the affected area that match the move's target kind.
func gather_targets() -> Array:
	var found: Array = []
	for cell in affected_cells:
		for unit in board.units_at(cell):
			if _matches_target_kind(unit) and unit not in found:
				found.append(unit)
	return found


func log_event(event: Dictionary) -> void:
	results.append(event)


func _matches_target_kind(unit) -> bool:
	match move.targeting.target_kind:
		CombatTypes.TargetKind.SELF:
			return unit == caster
		CombatTypes.TargetKind.ALLY:
			return unit != caster and board.are_allies(caster, unit)
		CombatTypes.TargetKind.ENEMY:
			return board.are_enemies(caster, unit)
		CombatTypes.TargetKind.ANY_UNIT:
			return true
		_:
			return false  # TILE / EMPTY_TILE effects don't gather units
