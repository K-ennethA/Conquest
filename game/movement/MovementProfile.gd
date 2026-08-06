extends Resource
class_name MovementProfile

## Data-driven description of how a unit traverses the board.
##
## A profile pairs a [b]kind[/b] (how the unit relates to obstacles — reuses
## [enum CombatTypes.MovementKind]) with a [b]shape[/b] (the geometry of the
## steps/jumps it may take), a [b]range[/b] budget, and optional per-tile cost
## overrides. It is pure data: [MovementResolver] consumes it to compute which
## cells are reachable. Cells are [Vector2i](col, row) in the combat module's
## own space (the live board adapter maps those onto the game's Vector3 grid).
##
## Author these as .tres resources for shipping content; [MovementLibrary]
## seeds a few examples in code for tests and prototyping.

## The geometry of a single step (for stepping shapes) or the whole move
## (for [constant Shape.KNIGHT] / [constant Shape.TELEPORT]).
enum Shape {
	ORTHOGONAL,  ## 4-directional cardinal steps; cost accumulates per step.
	DIAGONAL,    ## 4-directional diagonal steps only; cost accumulates.
	ALL8,        ## 8-directional (cardinal + diagonal) steps; cost accumulates.
	KNIGHT,      ## Fixed L-jumps that ignore intervening cells; range = jump count.
	TELEPORT,    ## Any cell within range regardless of obstacles; range = distance.
}

## Stable identifier (used as a lookup key / for serialization).
@export var id: StringName = &""

## Human-readable label for UI.
@export var display_name: String = ""

## How the unit relates to obstacles while pathing. See [MovementResolver] for
## the exact per-kind rules (GROUND is stopped by walls/units, FLYING ignores
## walls, PHASING ignores both — none may END on an occupied cell).
@export var kind: CombatTypes.MovementKind = CombatTypes.MovementKind.GROUND

## FALLBACK movement budget, used only WHEN NO UNIT IS SUPPLIED.
##
## A live unit's stride is its movement STAT ([code]get_stat("movement")[/code]) — the
## number its card prints, already carrying every modifier and mode grant — and
## [MovementResolver] reads that directly. This field is what the resolver falls back to
## for a call with no mover: an editor tool, a range preview for a profile not yet attached
## to anybody, a mock board in a test.
##
## That is deliberate, and it is why the whole roster can share one `ground_standard.tres`
## while every character still moves its own printed distance: a profile describes HOW a
## unit moves (kind, shape, terrain costs), never HOW FAR.
##
## Units: accumulated move cost for stepping shapes, number of jumps for
## [constant Shape.KNIGHT], direct (Manhattan) distance for [constant Shape.TELEPORT].
@export var range: int = 1

## Geometry of the movement pattern.
@export var shape: Shape = Shape.ORTHOGONAL

## Optional overrides for the cost of entering a tile, keyed by the tile's id or
## tag (as reported by the board's `tile_id_at` / `tile_tag_at`). A matching
## entry replaces the board's default `move_cost` for that cell. Higher values
## shrink reach; lower values extend it.
@export var terrain_cost_overrides: Dictionary = {}


## Convenience factory so libraries / tests can build a profile in one call.
static func create(
	p_id: StringName,
	p_name: String,
	p_kind: CombatTypes.MovementKind,
	p_range: int,
	p_shape: Shape,
	p_overrides: Dictionary = {}
) -> MovementProfile:
	var mp := MovementProfile.new()
	mp.id = p_id
	mp.display_name = p_name
	mp.kind = p_kind
	mp.range = p_range
	mp.shape = p_shape
	mp.terrain_cost_overrides = p_overrides.duplicate()
	return mp
