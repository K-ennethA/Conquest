extends RefCounted
class_name CombatTypes

## Shared enums for the combat / move system.
##
## Neutral, game-agnostic vocabulary (no external-franchise terms). Board cells
## are [Vector2i] in the combat module's own space; the live board adapter maps
## those to the game's Vector3 grid.

## Who a move is allowed to affect at a given cell.
enum TargetKind {
	SELF,        ## only the caster
	ALLY,        ## friendly units (excludes caster unless affects_caster_tile)
	ENEMY,       ## hostile units
	ANY_UNIT,    ## any unit regardless of allegiance
	TILE,        ## the terrain, occupied or not
	EMPTY_TILE,  ## only unoccupied terrain
}

## The footprint a move covers around its aim point.
enum AreaShape {
	SINGLE,   ## just the aimed cell
	CROSS,    ## aim + the four cardinal arms, length = area_size
	SQUARE,   ## Chebyshev radius area_size (a filled (2n+1)² block)
	DIAMOND,  ## Manhattan radius area_size (a filled rhombus)
	LINE,     ## a straight run from the aim, length area_size, aimed away from caster
	## A 3-cell frontal arc: the aimed cell plus the two cells flanking it
	## PERPENDICULAR to the caster->aim direction — the face of the caster the
	## swing sweeps across. area_size is ignored. Appended LAST: these enum values
	## serialise as integers into authored .tres files, so inserting mid-list would
	## silently re-point every existing pattern to a different shape.
	ARC,
}

## How damage interacts with a defender's stats.
enum DamageCategory {
	PHYSICAL,  ## reduced by defense
	MAGICAL,   ## reduced by magic defense / resistance
	TRUE,      ## ignores mitigation
}

## How a unit traverses the board (affects pathing, not moves directly).
enum MovementKind {
	GROUND,   ## blocked by obstacles and units
	FLYING,   ## ignores ground obstacles
	PHASING,  ## ignores everything
}

## Damage multiplier applied on a critical hit.
const CRIT_MULTIPLIER: float = 1.5


## Does [param unit] match [param kind] evaluated RELATIVE TO [param source]?
##
## The single shared implementation of "who does this affect" so every system that
## asks the question agrees. [MoveContext._matches_target_kind] (for an instant
## move's gathered targets) and [TravelingHazard.advance] (for a persistent hazard's
## per-band victims) both resolve through here, so a hazard and a plain AoE reading
## the SAME [enum TargetKind] can never disagree about allegiance.
##
## Duck-typed and null-safe: allegiance is only asserted when the board can answer
## it ([code]are_enemies[/code] / [code]are_allies[/code]), so a mock board missing
## those simply never matches ALLY/ENEMY (never inventing hostility). ANY_UNIT is
## true for every unit INCLUDING the source -- callers that must exclude the source
## (a hazard never damages its own caster) filter that out themselves.
static func unit_matches_target_kind(kind: int, source, unit, board) -> bool:
	match kind:
		TargetKind.SELF:
			return unit == source
		TargetKind.ALLY:
			return unit != source and board != null and board.has_method("are_allies") \
				and board.are_allies(source, unit)
		TargetKind.ENEMY:
			return board != null and board.has_method("are_enemies") \
				and board.are_enemies(source, unit)
		TargetKind.ANY_UNIT:
			return true
		_:
			return false
