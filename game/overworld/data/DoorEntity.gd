class_name DoorEntity
extends WarpEntity

## A BUILDING'S DOOR (docs/STORY_MODE.md "Interiors"): the warp into an enterable building's
## interior area. It sits on the facade cell [method PropEntity.door_cell] of the building prop
## [member building] -- a SOLID cell, so the hero never stands on it. Stepping toward it from
## [method front_cell] while facing [member enter_dir] (or pressing Confirm there) goes inside
## ([method OverworldController.try_step]); the interior's exit mat warps back to the town entry
## "door_<building>" -- the front cell, facing away from the building (Pokemon-style).
##
## Opt-in: a building only has a door when its prop is [member PropEntity.enterable]. Like every
## warp it can be gated ([member WarpEntity.requires] + [member WarpEntity.locked_scene]) and is
## prewarmed with the rest of the area's warps. Its actor is a placeholder door marker on the
## facade ([method OverworldProps.door_marker]; the real buildings come from Blender).

## The entry-point id the interior's exit returns to in the town ("door_<building id>").
const ENTRY_PREFIX := "door_"

## The building prop (a [PropEntity] id in the same area) this door belongs to.
@export var building: StringName = &""
## The direction the hero walks to go in (the facade faces the opposite way).
@export_enum("north", "south", "east", "west") var enter_dir: String = "north"


func kind() -> StringName:
	return &"door"


func cells() -> Array[Vector3i]:
	return [cell]


## The door marker on the facade.
func has_actor() -> bool:
	return true


## Never a blocker of its own: the building's footprint already is one.
func is_blocking() -> bool:
	return false


func is_interactable() -> bool:
	return true


func prompt_verb() -> String:
	return "Enter"


## The cell in front of the door the hero enters from (and comes back out to).
func front_cell() -> Vector3i:
	var v: Vector2i = OverworldEntity.facing_vector(enter_dir)
	return Vector3i(cell.x - v.x, cell.y - v.y, cell.z)


## The facing the hero has after coming back out (away from the building).
func exit_facing() -> String:
	return OverworldEntity.facing_name(-OverworldEntity.facing_vector(enter_dir))


## Does a step in [param dir] from [param from_cell] go through this door?
func accepts(from_cell: Vector3i, dir: Vector2i) -> bool:
	return from_cell == front_cell() and dir == OverworldEntity.facing_vector(enter_dir)


## Confirm on the door: go in (or the locked scene).
func interact_script(_area_id: String, state: StoryState) -> Array:
	if state != null and not is_open(state):
		return [SayCommand.from_scene(locked_scene)] if locked_scene != null else []
	var w := WarpCommand.new()
	w.area_id = target_area
	w.entry = target_entry
	return [w]


static func entry_id_for(building_id: String) -> String:
	return ENTRY_PREFIX + building_id


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	var where: String = "%s/%s" % [String(area.get("area_id")) if area != null else "?", String(id)]
	var a := area as OverworldAreaResource
	if a == null:
		return
	var p := a.entity(String(building)) as PropEntity
	if p == null:
		issues.append("%s: door names no building prop '%s'" % [where, String(building)])
		return
	if not p.enterable:
		issues.append("%s: building '%s' is not enterable" % [where, String(building)])
	elif p.door_cell() != cell:
		issues.append("%s: door %s is not on '%s''s door cell %s" % [where, str(cell), String(building), str(p.door_cell())])
	var back: Dictionary = a.entry(entry_id_for(String(building)))
	if back.is_empty():
		issues.append("%s: no entry '%s' to come back out to" % [where, entry_id_for(String(building))])
	elif back["cell"] != front_cell():
		issues.append("%s: entry '%s' is not the door's front cell" % [where, entry_id_for(String(building))])
