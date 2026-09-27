extends RefCounted
class_name Elevation

## HEIGHT ADVANTAGE -- the one place its numbers and rules live.
##
## Compares the attacker's floor with the target's (cells are Vector3i with
## z = floor, see [Cells]). All modifiers are FLAT per sign of the difference (one
## floor up is as good as three), small, and exactly neutral on the same floor -- so
## every single-floor fight resolves byte-for-byte as it did before floors existed.
##
##   attacker HIGHER : +[constant HIGH_GROUND_RANGE_BONUS] max range (RANGED moves only,
##                     i.e. authored max_range > 1), x[constant HIGH_GROUND_DAMAGE_SCALE]
##                     damage, +[constant HIGH_GROUND_HIT_BONUS]% hit chance.
##   attacker LOWER  : x[constant LOW_GROUND_DAMAGE_SCALE] damage,
##                     -[constant LOW_GROUND_HIT_PENALTY]% hit chance (no range change).
##
## Consumers: [TargetingPattern] (range), [DamageEffect] + [MoveExecutor.preview_vs]
## (damage, applied at the same step so the forecast matches), [MoveContext]
## (hit chance, also mirrored in the forecast).

const HIGH_GROUND_RANGE_BONUS: int = 1
const HIGH_GROUND_DAMAGE_SCALE: float = 1.15
const LOW_GROUND_DAMAGE_SCALE: float = 0.85
const HIGH_GROUND_HIT_BONUS: float = 10.0
const LOW_GROUND_HIT_PENALTY: float = 10.0


## Sign of the attacker's height over the target: +1 higher, -1 lower, 0 level.
static func advantage(attacker_cell: Vector3i, target_cell: Vector3i) -> int:
	return signi(attacker_cell.z - target_cell.z)


## Extra max range for a pattern aimed from [param origin] at [param aim].
## Only RANGED patterns (authored max_range > 1) gain reach from height.
static func range_bonus(origin: Vector3i, aim: Vector3i, authored_max_range: int) -> int:
	if authored_max_range > 1 and origin.z > aim.z:
		return HIGH_GROUND_RANGE_BONUS
	return 0


## Damage multiplier for [param caster] hitting [param target] on [param board]
## (1.0 when either has no known cell or they share a floor).
static func damage_scale_for(caster, target, board) -> float:
	match _advantage_of(caster, target, board):
		1: return HIGH_GROUND_DAMAGE_SCALE
		-1: return LOW_GROUND_DAMAGE_SCALE
	return 1.0


## Additive hit-chance modifier (percentage points) for [param caster] vs [param target].
static func hit_modifier_for(caster, target, board) -> float:
	match _advantage_of(caster, target, board):
		1: return HIGH_GROUND_HIT_BONUS
		-1: return -LOW_GROUND_HIT_PENALTY
	return 0.0


static func _advantage_of(caster, target, board) -> int:
	if caster == null or target == null or caster == target or board == null or not board.has_method("cell_of"):
		return 0
	var a = board.cell_of(caster)
	var b = board.cell_of(target)
	if not (a is Vector3i) or not (b is Vector3i):
		return 0
	return advantage(a, b)
