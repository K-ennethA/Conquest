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
##   crystal   the Researcher's shard pylon: a glowing crystal on a plinth
##   fire      a burning patch (scorch, flames, embers, a warm light)
##   rubble    a few charred stones
##   arena     a round stone arena (the tournament hall): tiered walls, pennants, a gate arch
##
## [member OverworldEntity.cell] is the footprint's top-left cell; [member footprint] its size.
## Props are NOT blocking by default (the terrain under a house block already decides
## walkability); a prop standing on open ground (a well, a stall) sets
## [member OverworldEntity.blocking] and then blocks EVERY cell of its footprint.

const KINDS: Array[String] = ["house", "ruin", "keep", "tower", "gate", "windmill", "stall", "well",
	"fence", "haystack", "barrels", "cart", "crops", "banner", "dummy", "crystal", "fire", "rubble", "arena"]

@export_enum("house", "ruin", "keep", "tower", "gate", "windmill", "stall", "well", "fence",
	"haystack", "barrels", "cart", "crops", "banner", "dummy", "crystal", "fire", "rubble", "arena")
var prop: String = "house"
@export var footprint: Vector2i = Vector2i(2, 2)


func kind() -> StringName:
	return &"prop"


func is_interactable() -> bool:
	return false


func _init() -> void:
	blocking = false


## Every cell of the footprint (a blocking prop blocks them all).
func cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y in range(maxi(1, footprint.y)):
		for x in range(maxi(1, footprint.x)):
			out.append(Vector3i(cell.x + x, cell.y + y, cell.z))
	return out


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	if not KINDS.has(prop):
		issues.append("%s: unknown prop kind '%s'" % [String(id), prop])
	if footprint.x < 1 or footprint.y < 1:
		issues.append("%s: prop footprint %s is empty" % [String(id), str(footprint)])
