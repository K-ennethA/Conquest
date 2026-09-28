class_name WarpEntity
extends OverworldEntity

## An exit: stepping onto any cell of [member area_rect] loads [member target_area] at
## [member target_entry] (a door, or a whole map edge). Invisible and non-blocking.
##
## [member preserve_axis] ("row" / "col" / "none") keeps your row (or column) across an edge exit,
## offset from the entry cell, so walking out of the top of a route arrives level with where
## you left. [member requires] gates it; a locked warp plays [member locked_scene] and turns you
## back instead.

@export var area_rect: Rect2i = Rect2i(0, 0, 1, 1)
@export var target_area: StringName = &""
@export var target_entry: StringName = &""
@export_enum("none", "row", "col") var preserve_axis: String = "none"
@export var requires: String = ""
@export var locked_scene: StoryScene


func kind() -> StringName:
	return &"warp"


func cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for y in range(area_rect.position.y, area_rect.end.y):
		for x in range(area_rect.position.x, area_rect.end.x):
			out.append(Vector3i(x, y, 0))
	return out


func has_actor() -> bool:
	return false


func is_interactable() -> bool:
	return false


func is_open(state: StoryState) -> bool:
	return ConditionContext.evaluate(requires, state)


## The arrival cell in the target area given the player stepped in at [param from_cell] and the
## target entry sits at [param entry_cell].
func arrival_cell(from_cell: Vector3i, entry_cell: Vector3i) -> Vector3i:
	match preserve_axis:
		"row":
			return Vector3i(entry_cell.x, entry_cell.y + (from_cell.y - area_rect.position.y), entry_cell.z)
		"col":
			return Vector3i(entry_cell.x + (from_cell.x - area_rect.position.x), entry_cell.y, entry_cell.z)
	return entry_cell


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	StoryCommand.check_condition(requires, issues, "%s requires" % String(id))
	if String(target_area).is_empty() or String(target_entry).is_empty():
		issues.append("%s: warp has no target" % String(id))
