extends Node

## Autoload that stages a DUEL across its scene changes (docs/design/DUEL_BATTLE.md §8.1):
## DuelSetup -> start(request) -> DuelStage -> results -> rematch / setup / menu. The same
## pattern as Arena / Campaign / Challenge: stage state here, then change scene.
##
## - STANDALONE: [method start] validates and stages a [DuelRequest] (rule 1: a bad request
##   is a returned {success:false, reason}, never an engine error) and opens the stage. The
##   duel's own results card owns the way back.
## - STORY (M4): [method launch_from_story] adapts OVERWORLD's BattleRequest; at the end the
##   result goes to StoryController.report_battle_result exactly once, and the duel never
##   changes scene itself. Registered with OVERWORLD's DuelLauncher when that seam exists.
##
## [method finish] runs exactly once per duel: emits [signal duel_finished], records the
## profile stat, and hands a story result back. The duel never writes the story save, gold,
## flags, inventory or the RosterLedger.

signal duel_finished(result: DuelResult)

const STAGE_SCENE := "res://game/duel/DuelStage.tscn"
const SETUP_SCENE := "res://menus/DuelSetup.tscn"
const MENU_SCENE := "res://menus/SoloModeSelect.tscn"

## Record duel wins / losses on the PlayerProfile (tests switch it off: no disk writes).
var record_profile: bool = true

var _request: DuelRequest = null
var _last_result: DuelResult = null
var _active: bool = false
var _finished: bool = false


func _ready() -> void:
	# Battle music for the duel stage (AudioManager plays the battle bed for listed scenes).
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and "battle_scene_paths" in audio and not (STAGE_SCENE in audio.battle_scene_paths):
		audio.battle_scene_paths.append(STAGE_SCENE)
	_register_story_launcher()


## Stage [param request] and (unless [param change_scene] is false) open the duel stage.
## Returns { success, reason }.
func start(request: DuelRequest, change_scene: bool = true) -> Dictionary:
	if request == null:
		return {"success": false, "reason": "no_request"}
	var check := request.validate()
	if not bool(check["success"]):
		return check
	_request = request
	_last_result = null
	_active = true
	_finished = false
	if change_scene and is_inside_tree():
		get_tree().change_scene_to_file(STAGE_SCENE)
	return {"success": true, "reason": ""}


func is_active() -> bool:
	return _active


func active_request() -> DuelRequest:
	return _request


func last_result() -> DuelResult:
	return _last_result


## The duel ended. Idempotent per staged duel: only the first call counts.
func finish(result: DuelResult) -> void:
	if _finished or result == null:
		return
	_finished = true
	_active = false
	_last_result = result
	if record_profile and result.outcome != DuelResult.OUTCOME_ABORTED:
		var profile := get_node_or_null("/root/PlayerProfile")
		if profile != null and profile.has_method("notify_battle_result"):
			profile.notify_battle_result("duel", result.player_won(), {"rounds": result.rounds})
	duel_finished.emit(result)
	if _request != null and _request.origin == DuelRequest.ORIGIN_STORY:
		var story := get_node_or_null("/root/StoryController")
		if story != null and story.has_method("report_battle_result"):
			story.report_battle_result(result.to_battle_result())


## The same matchup again, from FRESH entropy (DECISIONS.md: retrying re-rolls).
func rematch(change_scene: bool = true) -> Dictionary:
	if _request == null:
		return {"success": false, "reason": "no_request"}
	var again := DuelRequest.from_dict(_request.to_dict())
	if not bool(again["success"]):
		return again
	var req: DuelRequest = again["request"]
	req.seed = 0
	return start(req, change_scene)


## Forget the staged duel (tests; leaving the duel for good).
func reset() -> void:
	_request = null
	_last_result = null
	_active = false
	_finished = false


func open_setup() -> void:
	_active = false
	if is_inside_tree():
		get_tree().change_scene_to_file(SETUP_SCENE)


func open_menu() -> void:
	_active = false
	_request = null
	if is_inside_tree():
		get_tree().change_scene_to_file(MENU_SCENE)


## OVERWORLD's launcher entry (a BattleRequest, as its to_dict() shape). M4 wires the
## return; this adapts and stages it.
func launch_from_story(battle_request) -> Dictionary:
	var br = battle_request
	if br is Object and br.has_method("to_dict"):
		br = br.to_dict()
	var res := DuelRequest.from_battle_request(br)
	if not bool(res["success"]):
		return res
	return start(res["request"])


## Hand our launcher to OVERWORLD's DuelLauncher seam when that branch is present
## (DuelLauncher.register(callable) -- docs/design/OVERWORLD.md §7.2). A no-op otherwise.
func _register_story_launcher() -> void:
	for entry in ProjectSettings.get_global_class_list():
		if String(entry.get("class", "")) == "DuelLauncher":
			var script = load(String(entry.get("path", "")))
			if script is Script:
				for m in (script as Script).get_script_method_list():
					if String(m.get("name", "")) == "register":
						script.call("register", Callable(self, "launch_from_story"))
						break
			return
