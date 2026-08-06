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
		# Stamp the placed effect with its OWNER (the caster's player) so a trap only
		# springs on the placer's enemies -- see TileEffectResource.owner_player /
		# _faction_ok. Duplicate first so different placers don't share one owner and the
		# authored resource is never mutated. Shallow (sub-effects are shared, immutable).
		var owner = null
		if ctx.caster != null and ctx.caster.has_method("get_owner_player"):
			owner = ctx.caster.get_owner_player()
		# THE PLACEMENT RECORD. The active MODE decides how long a planted trap lives
		# (0 = forever, which is every battle outside a mode that declares otherwise), and the
		# expiry round is FROZEN onto this copy right now -- read once, here, from the round
		# the trap goes down. Nothing recomputes it, so retuning the ruleset mid-match cannot
		# move a trap already on the board and two lockstep peers agree on the round it goes
		# without exchanging anything. See TileEffectResource.stamp_placement.
		var expiry: int = ModeTuning.trap_expiry_rounds()
		var placed = effect
		if owner != null or expiry > 0:
			# Duplicated for the same reason it always was (CONQUEST.md rule 7): this resource
			# is loaded once and handed to every caster, so the owner AND the placement record
			# have to land on a per-cast copy. Shallow -- sub-effects are shared and immutable.
			placed = effect.duplicate()
			placed.owner_player = owner
			placed.stamp_placement(ModeTuning.current_round(), expiry)
		for cell in ctx.affected_cells:
			CombatServices.add_tile_effect(cell, placed)
			ctx.log_event({ "effect": "apply_tile_effect", "cell": cell, "tile_effect": placed })


func describe() -> String:
	if description_override != "":
		return description_override
	var label := "an effect"
	if effect != null and "display_name" in effect and String(effect.display_name) != "":
		label = String(effect.display_name)
	return "Set the ground alight with %s" % label
