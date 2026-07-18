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
