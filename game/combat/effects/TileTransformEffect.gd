extends MoveEffect
class_name TileTransformEffect

## Changes the terrain of every affected cell — e.g. scorch grass into a fire
## hazard, freeze water, raise a wall. This is how moves "affect tiles" rather
## than (or in addition to) units.

## Identifier of the terrain to place. Kept as a StringName so it stays
## content-agnostic; the board adapter maps it to a concrete TileResource.
@export var tile_id: StringName = &""
## If false, cells that already hold that terrain are skipped.
@export var overwrite_existing: bool = true


func apply(ctx: MoveContext) -> void:
	for cell in ctx.affected_cells:
		if ctx.board.has_method("set_tile"):
			ctx.board.set_tile(cell, tile_id)
		ctx.log_event({ "effect": "tile_transform", "cell": cell, "tile_id": tile_id })


func describe() -> String:
	if description_override != "":
		return description_override
	return "Transform terrain to '%s'" % tile_id
