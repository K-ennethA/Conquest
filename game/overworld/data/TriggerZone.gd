class_name TriggerZone
extends OverworldEntity

## An invisible zone that runs [member OverworldEntity.on_step] when the player steps into it
## (cutscenes, a guard calling out). [member once] zones set <area>.<id>.fired and never fire
## again.

@export var area_rect: Rect2i = Rect2i(0, 0, 1, 1)
@export var once: bool = true


func kind() -> StringName:
	return &"trigger"


func auto_flag(area_id: String) -> String:
	return "%s.%s.fired" % [area_id, String(id)] if once else ""


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


func can_fire(area_id: String, state: StoryState) -> bool:
	return not once or not state.has_flag(auto_flag(area_id))


func step_script(area_id: String) -> Array:
	var out: Array = []
	if once:
		var fired := SetFlagCommand.new()
		fired.key = auto_flag(area_id)
		fired.value = 1
		out.append(fired)
	out.append_array(on_step)
	return out
