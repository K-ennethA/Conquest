class_name RideFieldMoveCommand
extends StoryCommand

## RIDE a TRAVEL field move out onto [member to] (DECISIONS.md #43: the Beach Village chief's power
## to cross the sea): the host turns the move's tiles passable, puts the member who knows it under
## the hero as his mount and walks him out onto the faced tile. He rides until he steps onto land.
## Built by the overworld when the hero faces the water and presses Confirm ([method script_for]);
## a script can also use it (a ferry scene, a tutorial).

@export var move_id: StringName = &""
## The tile the hero rides out onto (the one he faces); [constant Cells.INVALID] = mount in place.
@export var to: Vector3i = Cells.INVALID


static func make(p_move_id: StringName, p_to: Vector3i) -> RideFieldMoveCommand:
	var c := RideFieldMoveCommand.new()
	c.move_id = p_move_id
	c.to = p_to
	return c


## What Confirm at the water's edge runs for travel move [param fm]: one hint line while it is not
## teachable / nobody fit knows it; else "Use <move>?" Yes -> ride out onto [param to] (and a toast
## naming who carries the hero), No -> nothing.
static func script_for(fm: FieldMoveResource, state: StoryState, p_to: Vector3i) -> Array:
	var out: Array = []
	if fm == null:
		return out
	match fm.status(state):
		FieldMoveResource.STATUS_LOCKED:
			out.append(_narrate(fm.fill(fm.locked_hint)))
		FieldMoveResource.STATUS_NO_USER:
			out.append(_narrate(fm.fill(fm.no_user_hint)))
		_:
			var ask := ChoiceCommand.new()
			ask.prompt = SayCommand.beat(StoryBeat.NARRATOR, "", fm.fill(fm.prompt_text))
			var yes: Array = [
				make(fm.id, p_to),
				ToastCommand.make(fm.fill(fm.used_text, fm.user_name(state)), "info"),
			]
			ask.options = StoryCommand.list([ChoiceOption.make("Yes", yes), ChoiceOption.make("No", [], true)])
			out.append(ask)
	return out


static func _narrate(text: String) -> SayCommand:
	var say := SayCommand.new()
	say.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR, "", text)])
	return say


func run(ctx: ScriptContext) -> void:
	if ctx.has_host_method(&"start_ride"):
		await ctx.host.start_ride(move_id, to)


func describe() -> String:
	return "Ride %s to %s" % [String(move_id), str(to)]


func validate(issues: Array[String]) -> void:
	var fm := FieldMoveResource.load_by_id(String(move_id))
	if fm == null:
		issues.append("ride: field move '%s' does not exist" % String(move_id))
	elif not fm.is_travel():
		issues.append("ride: field move '%s' is not a travel move" % String(move_id))
