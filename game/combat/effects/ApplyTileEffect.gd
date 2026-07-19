extends MoveEffect
class_name ApplyTileEffect

## Layers a runtime [TileEffectResource] onto every affected cell WITHOUT changing
## the terrain. This is how a move "sets the floor on fire" additively: a tall-grass
## tile keeps its BASE effect (e.g. +evasion) AND the cell now also burns -- both
## are returned together by [method CombatServices.tile_effects_at] (base + runtime).
##
## Contrast with [TileTransformEffect], which REPLACES the terrain (and its base
## effects). Use this when effects should STACK; use TileTransformEffect when the
## terrain itself should change.

## The tile effect to layer onto each affected cell.
@export var effect: TileEffectResource


func apply(ctx: MoveContext) -> void:
	if effect == null:
		return
	# Runtime tile effects live on CombatServices (the shared board owner), not on
	# the BoardAdapter, so add them there. add_tile_effect is idempotent and stacks
	# on top of the cell's base effects.
	if CombatServices:
		for cell in ctx.affected_cells:
			CombatServices.add_tile_effect(cell, effect)
			ctx.log_event({ "effect": "apply_tile_effect", "cell": cell, "tile_effect": effect })


func describe() -> String:
	if description_override != "":
		return description_override
	var label := "an effect"
	if effect != null and "display_name" in effect and String(effect.display_name) != "":
		label = String(effect.display_name)
	return "Set the ground alight with %s" % label
