class_name OverworldEntity
extends Resource

## BASE of everything that lives on an overworld area (docs/design/OVERWORLD.md §4.2): NPCs,
## signs, chests, warps, the Wayshrine, trigger zones. Terrain is the area's MapResource; this
## is the story layer on top of it.
##
## A kind subclass pre-fills behaviour ([method interact_script], [method auto_flag]); an author
## can always append more with [member on_interact] / [member on_step]. Entities are pure data
## -- the overworld builds an actor node per visible entity at area load.

@export var id: StringName = &""
@export var cell: Vector3i = Vector3i.ZERO
@export_enum("south", "north", "east", "west") var facing: String = "south"
@export var display_name: String = ""
## Roster CharacterResource id used as the model; empty = the kind's procedural figure / prop.
@export var visual_character: StringName = &""
## Cloak / accent colour of a procedural figure or prop.
@export var tint: Color = Color(0.44, 0.52, 0.34)
@export var blocking: bool = true
## Condition (see [ConditionContext]); blank = always present.
@export var visible_if: String = ""
@export var on_interact: Array[Resource] = []
@export var on_step: Array[Resource] = []


## Stable kind key (for the actor factory and describe()).
func kind() -> StringName:
	return &"entity"


## The flag this kind sets automatically ("" when none).
func auto_flag(_area_id: String) -> String:
	return ""


func is_present(state: StoryState) -> bool:
	return ConditionContext.evaluate(visible_if, state)


## Cells this entity occupies (blocking / interaction). Most entities are one cell.
func cells() -> Array[Vector3i]:
	return [cell]


func occupies(c: Vector3i) -> bool:
	return cells().has(c)


## Does it get an actor node (a model / prop)? Warps and trigger zones are invisible.
func has_actor() -> bool:
	return true


## Can the player talk to / use it by facing it and pressing Confirm?
func is_interactable() -> bool:
	return not on_interact.is_empty()


## The prompt verb on the HUD chip ("Talk", "Read", "Open", "Touch").
func prompt_verb() -> String:
	return "Talk"


## The commands pressing Confirm on it runs. Kinds compose their built-in behaviour here.
func interact_script(_area_id: String, _state: StoryState) -> Array:
	return on_interact.duplicate()


## Content validation: ids, conditions, nested scripts. Appends human-readable issues.
func validate(area: Resource, issues: Array[String]) -> void:
	var where: String = "%s/%s" % [String(area.get("area_id")) if area != null else "?", String(id)]
	if String(id).is_empty():
		issues.append("%s: entity has no id" % where)
	if not String(visual_character).is_empty() \
			and CharacterLibrary.get_character(visual_character) == null:
		issues.append("%s: visual_character '%s' does not exist" % [where, visual_character])
	StoryCommand.check_condition(visible_if, issues, "%s visible_if" % where)
	StoryCommand.validate_list(on_interact, issues, where)
	StoryCommand.validate_list(on_step, issues, where)


static func facing_vector(name: String) -> Vector2i:
	match name:
		"north":
			return Vector2i(0, -1)
		"east":
			return Vector2i(1, 0)
		"west":
			return Vector2i(-1, 0)
	return Vector2i(0, 1)


static func facing_name(dir: Vector2i) -> String:
	if dir == Vector2i(0, -1):
		return "north"
	if dir == Vector2i(1, 0):
		return "east"
	if dir == Vector2i(-1, 0):
		return "west"
	return "south"


func _to_string() -> String:
	return "%s '%s' @ %s" % [String(kind()).capitalize(), String(id), str(cell)]
