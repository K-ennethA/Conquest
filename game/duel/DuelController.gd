extends Node

## Autoload that stages a DUEL across its scene changes (docs/design/DUEL_BATTLE.md §8.1):
## DuelSetup -> start(request) -> DuelStage -> results -> rematch / setup / menu. The same
## pattern as Arena / Campaign / Challenge: stage state here, then change scene.
##
## - STANDALONE: [method start] validates and stages a [DuelRequest] (rule 1: a bad request
##   is a returned {success:false, reason}, never an engine error) and opens the stage. The
##   duel's own results card owns the way back.
## - STORY: this node is THE registered story duel launcher ([method register_story_launcher]
##   -> OVERWORLD's DuelLauncher seam; the overworld's debug DuelStub is only the fallback when
##   no real launcher is present). [method launch_from_story] adapts the story's BattleRequest;
##   at the end the result goes to StoryController.report_battle_result EXACTLY ONCE (as a
##   BattleResult), and the duel never changes scene itself -- StoryController walks back to
##   the overworld.
##
## [method finish] runs exactly once per duel: emits [signal duel_finished], records the
## profile stat, awards STANDALONE growth (only when EvolutionRules.growth_modes lists "duel"),
## and hands a story result back. The duel never writes the story save, gold, flags or
## inventory; story growth is StoryController's (the story party's own records).

signal duel_finished(result: DuelResult)

const STAGE_SCENE := "res://game/duel/DuelStage.tscn"
const SETUP_SCENE := "res://menus/DuelSetup.tscn"
const MENU_SCENE := "res://menus/SoloModeSelect.tscn"
## The EvolutionRules.growth_modes id of a STANDALONE duel.
const GROWTH_MODE := "duel"

## Record duel wins / losses on the PlayerProfile (tests switch it off: no disk writes).
var record_profile: bool = true
## Tests switch scene changes off (a story launch then only stages the request).
var scene_changes_enabled: bool = true

var _request: DuelRequest = null
var _last_result: DuelResult = null
var _active: bool = false
var _finished: bool = false
var _story_launcher: Callable = Callable()


func _ready() -> void:
	# Battle music for the duel stage (AudioManager plays the battle bed for listed scenes).
	var audio := get_node_or_null("/root/AudioManager")
	if audio != null and "battle_scene_paths" in audio and not (STAGE_SCENE in audio.battle_scene_paths):
		audio.battle_scene_paths.append(STAGE_SCENE)
	register_story_launcher()


func _exit_tree() -> void:
	# The launcher is a Callable bound to this node; a static holding it past shutdown crashes
	# the engine on exit (the same rule StoryController follows for the stub).
	if _story_launcher.is_valid() and DuelLauncher.is_registered(_story_launcher):
		DuelLauncher.reset()


## Put the REAL duel in OVERWORLD's seam (it replaces the debug stub; a stub never replaces
## it). Public so tests that swapped launchers can restore the shipped state.
func register_story_launcher() -> void:
	_story_launcher = Callable(self, "launch_from_story")
	DuelLauncher.register(_story_launcher)


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
	if change_scene and scene_changes_enabled and is_inside_tree():
		get_tree().change_scene_to_file(STAGE_SCENE)
	return {"success": true, "reason": ""}


func is_active() -> bool:
	return _active


func active_request() -> DuelRequest:
	return _request


func last_result() -> DuelResult:
	return _last_result


## True when the staged duel belongs to story (its result goes to StoryController).
func is_story_duel() -> bool:
	return _request != null and _request.origin == DuelRequest.ORIGIN_STORY


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
	if not is_story_duel():
		result.growth = award_standalone_growth(_request, result, growth_context(_request))
	duel_finished.emit(result)
	if is_story_duel():
		var story := get_node_or_null("/root/StoryController")
		if story != null and story.has_method("report_battle_result"):
			story.report_battle_result(BattleResult.from_dict(result.to_battle_result()))


## The EVOLUTION growth gate for a standalone duel ([method GrowthTracker.gate_reason] keys).
func growth_context(request: DuelRequest) -> Dictionary:
	var networked: bool = request != null and request.kind == DuelRequest.KIND_VERSUS
	var ns := get_node_or_null("/root/NetSession")
	if ns != null and ns.has_method("is_networked_match") and bool(ns.is_networked_match()):
		networked = true
	return {"replay": ReplayPlayback.is_playing(), "networked": networked, "arena": false,
		"mode": GROWTH_MODE}


## STANDALONE growth (docs/design/DUEL_BATTLE.md §8.4, EVOLUTION.md §6): the player's fielded
## combatant earns Growth on its open-mode RosterLedger member through the shared
## [method GrowthTracker.compute_awards], gated exactly like a tactical battle (never in a
## replay or a networked match, and only when EvolutionRules.growth_modes lists "duel" --
## shipped OFF). An AI-driven player side (smoke runs) never earns. Saves the ledger when it
## wrote. Returns GrowthTracker's latch rows for the results card.
static func award_standalone_growth(request: DuelRequest, result: DuelResult, ctx: Dictionary) -> Array:
	var rows_out: Array = []
	if request == null or result == null or request.player_is_ai or request.player_party.is_empty():
		return rows_out
	if result.outcome != DuelResult.OUTCOME_VICTORY and result.outcome != DuelResult.OUTCOME_DEFEAT:
		return rows_out
	var rules: EvolutionRules = EvolutionRules.current()
	if GrowthTracker.gate_reason(ctx, rules) != "":
		return rows_out
	var lead: DuelCombatant = request.player_party[0]
	var cid: String = String(lead.character_id)
	var uid: String = RosterLedger.member_for_character(cid)
	var fought: Dictionary = result.party_after[0] if not result.party_after.is_empty() else {}
	var rows: Array = [{"uid": uid, "alive": not bool(fought.get("wounded", false)),
		"kos": int(fought.get("kos", 0))}]
	# Battle feats ([BattleFeatTrigger]) under the same gate: the lead is the only fighter, so the
	# foes it KO'd are result.defeated.
	var chr: CharacterResource = CharacterLibrary.get_character(cid)
	var el_kos: Dictionary = {}
	for foe in result.defeated:
		var fc: CharacterResource = CharacterLibrary.get_character(StringName(String(foe)))
		if fc != null and fc.element != &"":
			el_kos[String(fc.element)] = int(el_kos.get(String(fc.element), 0)) + 1
	var feat_row: Dictionary = rows[0].duplicate()
	feat_row["element_kos"] = el_kos if int(fought.get("kos", 0)) > 0 else {}
	var hp: int = int(fought.get("current_hp", -1))
	feat_row["hp_ratio"] = 1.0 if hp < 0 or chr == null else float(hp) / float(maxi(1, chr.base_health))
	var feats: Dictionary = GrowthTracker.compute_feats([feat_row], result.player_won(), rules)
	for fuid in feats.keys():
		RosterLedger.add_feats(fuid, feats[fuid])
	var awards: Dictionary = GrowthTracker.compute_awards(rows, result.player_won(), rules)
	if awards.is_empty():
		if not feats.is_empty():
			RosterLedger.save()
		return rows_out
	var total: int = RosterLedger.add_growth(uid, int(awards[uid]))
	rows_out.append({
		"uid": uid,
		"character_id": cid,
		"name": chr.display_name if chr != null else cid,
		"gained": int(awards[uid]),
		"total": total,
		"goal": RosterLedger.next_growth_goal(RosterLedger.form_of(uid)),
		"ready": not RosterLedger.available_evolutions(uid).is_empty(),
	})
	RosterLedger.save()
	return rows_out


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


## OVERWORLD's launcher entry: a [BattleRequest] (or its to_dict() shape) -> a story
## [DuelRequest] staged here, then the stage. {success, reason}.
func launch_from_story(battle_request) -> Dictionary:
	var br = battle_request
	if br is Object and br.has_method("to_dict"):
		br = br.to_dict()
	var res := DuelRequest.from_battle_request(br)
	if not bool(res["success"]):
		return res
	return start(res["request"])
