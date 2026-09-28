class_name PropEntity
extends OverworldEntity

## Pure SCENERY on an area: no interaction, never blocking (the terrain under it already
## decides walkability). M1 uses it to put a timber-and-thatch ROOF over the placeholder stone
## house blocks so a town reads as houses, not paving (real building props are M2's
## HouseBuilder). [member cell] is the footprint's top-left cell; [member footprint] its size.

@export_enum("house") var prop: String = "house"
@export var footprint: Vector2i = Vector2i(2, 2)


func kind() -> StringName:
	return &"prop"


func is_interactable() -> bool:
	return false


func _init() -> void:
	blocking = false
