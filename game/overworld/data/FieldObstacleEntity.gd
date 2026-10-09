class_name FieldObstacleEntity
extends OverworldEntity

## An overworld OBSTACLE a [FieldMoveResource] clears (docs/design/DECISIONS.md #40 / #41 / #71): a
## BREAKABLE TREE first (the tree-felling move Nyra teaches); the same entity takes a later look
## (a boulder, a reef) for another move, so the sea move reuses it as data.
##
## It blocks its cell like any solid entity. Confirm-facing it:
##   * the move is NOT UNLOCKED -> one line ([member FieldMoveResource.locked_hint]); nothing forced;
##   * unlocked, nobody can use it -> one line ([member FieldMoveResource.no_user_hint]);
##   * READY -> "Use <move>?" Yes / No; Yes sets [method cleared_flag] (and toasts who used it).
## The obstacle is GONE once cleared, for good: [member OverworldEntity.visible_if] must read
## [code]not has("<area>.<id>.cleared")[/code] (the builder's helper writes it; [method validate]
## insists), so the actor hides and the grid stops blocking the cell -- across a reload, because the
## flag is in the save (the [ChestEntity] pattern).

## The [FieldMoveResource] id that clears it ([method FieldMoveResource.load_by_id]).
@export var field_move: StringName = &""
## The placeholder look ([method OverworldProps.field_obstacle]): "tree" for now.
@export_enum("tree") var look: String = "tree"


func kind() -> StringName:
	return &"obstacle"


## The flag a cleared obstacle sets: "<area>.<id>.cleared".
static func flag_for(area_id: String, obstacle_id: String) -> String:
	return "%s.%s.cleared" % [area_id, obstacle_id]


func cleared_flag(area_id: String) -> String:
	return flag_for(area_id, String(id))


func is_cleared(area_id: String, state: StoryState) -> bool:
	return state != null and state.has_flag(cleared_flag(area_id))


## The visible_if an obstacle needs ([method validate]): present until cleared.
static func presence_condition(area_id: String, obstacle_id: String) -> String:
	return "not has(\"%s\")" % flag_for(area_id, obstacle_id)


func is_interactable() -> bool:
	return true


func prompt_verb() -> String:
	return "Check"


func move() -> FieldMoveResource:
	return FieldMoveResource.load_by_id(String(field_move))


func interact_script(area_id: String, state: StoryState) -> Array:
	return script_for(move(), area_id, state)


## The interaction for [param fm] (split out so a test can hand it any move): a hint while locked /
## unusable, else the Yes / No that clears it.
func script_for(fm: FieldMoveResource, area_id: String, state: StoryState) -> Array:
	var out: Array = []
	if fm == null or is_cleared(area_id, state):
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
				SetFlagCommand.make(cleared_flag(area_id), 1),
				ToastCommand.make(fm.fill(fm.used_text, fm.user_name(state)), "info"),
			]
			yes.append_array(on_interact)
			ask.options = StoryCommand.list([ChoiceOption.make("Yes", yes), ChoiceOption.make("No", [], true)])
			out.append(ask)
	return out


func _narrate(text: String) -> SayCommand:
	var say := SayCommand.new()
	say.beats = StoryCommand.list([SayCommand.beat(StoryBeat.NARRATOR, "", text)])
	return say


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	var aid: String = String(area.get("area_id")) if area != null else ""
	var where: String = "%s/%s" % [aid, String(id)]
	if move() == null:
		issues.append("%s: field move '%s' does not exist" % [where, field_move])
	if not visible_if.contains(cleared_flag(aid)):
		issues.append("%s: visible_if must hide it once cleared (%s)" % [where, presence_condition(aid, String(id))])
