class_name PropEntity
extends OverworldEntity

## Pure SCENERY on an area: no interaction. M1 used it to put a timber-and-thatch ROOF over the
## placeholder stone house blocks so a town reads as houses, not paving; the story opening adds
## the rest of a village / castle-town kit (all procedural, [OverworldProps]):
##
##   house     a plastered, timber-framed house with a gabled roof in [member OverworldEntity.tint]
##   ruin      the same house BURNED: charred stumps of wall, fallen beams, flames and embers
##   keep      a castle keep with corner towers, battlements and banners (sits on a wall block)
##   tower     a squat wall tower with a cone roof (wall corners)
##   gate      a gatehouse: two towers and an arch over the middle cell (walk under it)
##   windmill  a mill tower with four sails
##   stall     a market stall with a striped awning
##   well      a stone well with a little roof
##   fence     a split-rail fence along the footprint's long axis
##   haystack  a golden haystack
##   barrels   a cluster of barrels
##   cart      a hand cart
##   crops     rows of leafy crops over the footprint
##   banner    a pole with a hanging banner
##   dummy     a straw training dummy
##   crystal   the Royal Workshop's pylon: a glowing crystal on a plinth
##   fire      a burning patch (scorch, flames, embers, a warm light)
##   rubble    a few charred stones
##   arena     a round stone arena (the tournament hall): tiered walls, pennants, a gate arch
##   cabin     a timber log cabin: dark log walls, steep mossy roof, porch (the forest town)
##   logs      a pyramid stack of cut logs over the footprint (the lumber yard)
##   lamp      a street lamp
##   chapel    a stone chapel with a bell tower and spire
##   smithy    a forge house: glowing forge mouth, chimney, anvil
##   scarecrow a field scarecrow
##   mat       an interior's exit mat: a rug on the floor (walk-over)
##
## [member OverworldEntity.cell] is the footprint's top-left cell; [member footprint] its size.
## COLLISION is per KIND: [constant SOLID_KINDS] (a cart, barrels, a well, a stall, fences,
## houses, ...) block EVERY cell of their footprint; the rest (crops, a gatehouse's arch) are
## walk-over and the terrain under them decides. [member collision] overrides one prop either way
## ("solid" / "walkable"). [member OverworldEntity.blocking] is NOT used by props: its exported
## default (true) differed from what the old _init() forced (false), so ResourceSaver dropped an
## authored `true` and every reloaded prop came back walk-through (the pass-through-carts bug).

const KINDS: Array[String] = ["house", "ruin", "keep", "tower", "gate", "windmill", "stall", "well",
	"fence", "haystack", "barrels", "cart", "crops", "banner", "dummy", "crystal", "fire", "rubble", "arena",
	"cabin", "logs", "lamp", "chapel", "smithy", "scarecrow", "mat", "thicket"]

@export_enum("house", "ruin", "keep", "tower", "gate", "windmill", "stall", "well", "fence",
	"haystack", "barrels", "cart", "crops", "banner", "dummy", "crystal", "fire", "rubble", "arena", "cabin", "logs", "lamp", "chapel", "smithy", "scarecrow", "mat", "thicket")
var prop: String = "house"
@export var footprint: Vector2i = Vector2i(2, 2)
## "auto" = the kind's default ([constant SOLID_KINDS]); "solid" / "walkable" override it.
@export_enum("auto", "solid", "walkable") var collision: String = "auto"
## OPT-IN: can the hero go inside? A building is NOT enterable by default (a plain solid block
## with no door). When true, the area carries a [DoorEntity] on [method door_cell] that leads to
## the building's interior area (docs/STORY_MODE.md "Interiors").
@export var enterable: bool = false
## The door's cell inside the footprint (offset from [member OverworldEntity.cell]); (-1, -1) =
## the bottom row's centre column (the south facade, toward the camera).
@export var door_offset: Vector2i = Vector2i(-1, -1)
## A LIT prop (a lantern burning, a glowing marker): 0 = unlit (the default); above 0 its light
## part glows in [member OverworldEntity.tint] -- an emissive head plus a light of this energy
## ([method OverworldProps.add_glow]). A look, never collision. E.g. the Deep Woods' maze lanterns.
@export_range(0.0, 8.0, 0.1) var glow: float = 0.0

## Kinds that block their whole footprint unless [member collision] says "walkable". Walk-over
## decor (crops) and arches the player walks under (gate) are deliberately absent.
const SOLID_KINDS: Array[String] = ["house", "ruin", "keep", "tower", "windmill", "stall", "well",
	"fence", "haystack", "barrels", "cart", "banner", "dummy", "crystal", "fire", "rubble", "arena",
	"cabin", "logs", "lamp", "chapel", "smithy", "scarecrow"]


func kind() -> StringName:
	return &"prop"


func is_interactable() -> bool:
	return false


## Does this prop block its footprint? The kind's default, unless [member collision] overrides it.
func is_blocking() -> bool:
	match collision:
		"solid":
			return true
		"walkable":
			return false
	return SOLID_KINDS.has(prop)


## Every cell of the footprint (a blocking prop blocks them all).
func cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y in range(maxi(1, footprint.y)):
		for x in range(maxi(1, footprint.x)):
			out.append(Vector3i(cell.x + x, cell.y + y, cell.z))
	return out


## The facade cell the door is on, or [constant Cells.INVALID] when the building is not
## [member enterable]. Still a SOLID cell of the footprint: the hero never stands on it -- a step
## into it from the front cell enters ([DoorEntity]).
func door_cell() -> Vector3i:
	if not enterable:
		return Cells.INVALID
	var fp := Vector2i(maxi(1, footprint.x), maxi(1, footprint.y))
	var off: Vector2i = door_offset
	if off.x < 0 or off.y < 0:
		off = Vector2i((fp.x - 1) / 2, fp.y - 1)
	return Vector3i(cell.x + off.x, cell.y + off.y, cell.z)


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	if enterable:
		var d: Vector3i = door_cell()
		if not cells().has(d):
			issues.append("%s: door %s is outside the footprint" % [String(id), str(d)])
	if not KINDS.has(prop):
		issues.append("%s: unknown prop kind '%s'" % [String(id), prop])
	if not ["auto", "solid", "walkable"].has(collision):
		issues.append("%s: unknown collision '%s'" % [String(id), collision])
	if footprint.x < 1 or footprint.y < 1:
		issues.append("%s: prop footprint %s is empty" % [String(id), str(footprint)])
