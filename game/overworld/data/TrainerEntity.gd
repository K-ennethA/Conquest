class_name TrainerEntity
extends NpcEntity

## An NPC who challenges you (docs/design/OVERWORLD.md §4.5). Undefeated, he watches the cells
## in a straight line along his facing up to [member sight_range] ([TrainerSight]); step into
## that line and he spots you: "!" -> walks up -> [member pre_scene] -> battle. Talking to him
## (from the side / behind) starts the same battle. Once beaten
## (trainer.<area>.<id>.defeated) he only says [member defeated_scene].

@export_range(1, 12) var sight_range: int = 4
@export var battle: BattleSpec
@export var pre_scene: StoryScene
@export var defeated_scene: StoryScene
@export var rematchable: bool = false


func kind() -> StringName:
	return &"trainer"


func auto_flag(area_id: String) -> String:
	return defeated_flag(area_id, String(id))


static func defeated_flag(area_id: String, trainer_id: String) -> String:
	return "trainer.%s.%s.defeated" % [area_id, trainer_id]


func encounter_id(area_id: String) -> String:
	return "trainer.%s.%s" % [area_id, String(id)]


func is_defeated(area_id: String, state: StoryState) -> bool:
	return state.has_flag(auto_flag(area_id))


func is_interactable() -> bool:
	return true


## Talking to him: once beaten, his dialogue-bank line when the bank has one that matches (what he
## says changes with the story), else the defeated line; unbeaten, the challenge (no walk-up).
func interact_script(area_id: String, state: StoryState) -> Array:
	if is_defeated(area_id, state) and not rematchable:
		var out: Array = []
		var say: SayCommand = DialogueBank.say_command(area_id, String(id), state)
		if say != null:
			out.append(say)
		elif defeated_scene != null:
			out.append(SayCommand.from_scene(defeated_scene))
		out.append_array(on_interact)
		return out
	return encounter_script(area_id, Vector3i.ZERO, false)


## The challenge. [param approach_cell] is where he walks to (the cell next to the player) when
## he SPOTTED you; ignored when you walked up and talked to him.
func encounter_script(area_id: String, approach_cell: Vector3i, spotted: bool) -> Array:
	var out: Array = []
	var emote := EmoteCommand.new()
	emote.actor = String(id)
	emote.glyph = "!"
	out.append(emote)
	if spotted:
		var walk := MoveActorCommand.new()
		walk.actor = String(id)
		walk.to = approach_cell
		walk.persist = false
		out.append(walk)
	var face := FaceActorCommand.new()
	face.actor = "player"
	face.facing = "toward:" + String(id)
	out.append(face)
	if pre_scene != null:
		out.append(SayCommand.from_scene(pre_scene))
	if battle != null:
		var fight := StartBattleCommand.new()
		fight.spec = battle
		fight.source = BattleRequest.SOURCE_TRAINER
		fight.encounter_id = encounter_id(area_id)
		out.append(fight)
		# After a WIN the rewards (gold, the defeated flag) are already applied by the
		# controller; he says his line. A whiteout stops the script before this runs.
		if defeated_scene != null:
			var after := IfCommand.new()
			after.condition = "outcome() == \"victory\""
			after.then_commands = StoryCommand.list([SayCommand.from_scene(defeated_scene)])
			out.append(after)
	return out


func validate(area: Resource, issues: Array[String]) -> void:
	super.validate(area, issues)
	if battle == null:
		issues.append("%s: trainer has no battle" % String(id))
	else:
		battle.validate(issues)
