class_name BattleSpec
extends Resource

## An AUTHORED battle (a trainer, a scripted fight, a story recruit) -- turned into a runtime
## [BattleRequest] by [method to_request] (docs/design/OVERWORLD.md §4.2).

enum Kind { TACTICAL, DUEL }
enum DefeatPolicy { WHITEOUT, CONTINUE, RETRY }

@export var kind: Kind = Kind.TACTICAL
## Stable id; empty = derived by the caller (trainer.<area>.<id>, ...).
@export var encounter_id: String = ""
## Tactical: the battle map (a MapResource under game/overworld/content/battles/, status
## Inactive so it never shows in a map picker).
@export_file("*.tres") var map_path: String = ""
## Tactical alternative: a CampaignData chapter id (M2 folds the campaign into the story).
@export var campaign_chapter: String = ""
@export_range(1, 6) var squad_size: int = 3
@export_enum("Easy", "Normal", "Hard", "Brutal") var ai_difficulty: int = 1
@export var opponent_name: String = ""
@export var opponent_speaker_id: StringName = &""
## Duel: [{character_id, strength}] -- strength is opaque upstream (EVOLUTION decides levels).
@export var opponent_team: Array[Dictionary] = []
@export var intro_scene: StoryScene
@export var outro_scene: StoryScene
@export var reward_gold: int = 0
@export var reward_items: Array[StringName] = []
@export var reward_flags: Array[String] = []
@export var defeat_policy: DefeatPolicy = DefeatPolicy.WHITEOUT
@export var can_flee: bool = false
@export var can_befriend: bool = false
## Non-missable recruit (DECISIONS.md): loss / flee leaves the encounter in the world.
@export var story_critical: bool = false
## Play the VS clash before a trainer battle.
@export var clash_intro: bool = false
## A FRIENDLY battle (a training spar, a rival friendly): it only knocks units out -- it never
## causes permadeath (DECISIONS.md #29). Shown as "Friendly spar" on the battle.
@export var spar: bool = false
## Units that MUST SURVIVE ("Protect Elias"): a name, character id or party member id each. On a
## tactical board a matching player-side unit (a guest ally, a party member) falling is a defeat;
## in a duel, a matching party member fainting. Either way the journey is over: GAME OVER, back
## to the last save (both tiers).
@export var protect: Array[String] = []

@export_group("Scaling")
## REMATCH SCALING (a rival, a champion, a repeat cup -- DECISIONS.md #33): every opponent's
## strength is multiplied by 1 + [member scale_step] x min(flag([member scale_flag]),
## [member scale_max_steps]) when a script starts the battle ([method apply_scaling]; the duel reads
## strength only through DuelScaling). Blank flag = no scaling.
@export var scale_flag: String = ""
@export_range(0.0, 1.0, 0.01) var scale_step: float = 0.0
@export_range(0, 20) var scale_max_steps: int = 0


func kind_name() -> String:
	return BattleRequest.KIND_DUEL if kind == Kind.DUEL else BattleRequest.KIND_TACTICAL


func policy_name() -> String:
	match defeat_policy:
		DefeatPolicy.CONTINUE:
			return BattleRequest.DEFEAT_CONTINUE
		DefeatPolicy.RETRY:
			return BattleRequest.DEFEAT_RETRY
	return BattleRequest.DEFEAT_WHITEOUT


## Build the runtime request. [param fallback_id] names the encounter when the spec does not.
func to_request(source: String, fallback_id: String = "") -> BattleRequest:
	var r := BattleRequest.new()
	r.kind = kind_name()
	r.encounter_id = encounter_id if not encounter_id.is_empty() else fallback_id
	r.source = source
	var team: Array = []
	for t in opponent_team:
		team.append((t as Dictionary).duplicate(true))
	r.opponent = {
		"name": opponent_name,
		"speaker_id": String(opponent_speaker_id),
		"portrait": String(opponent_speaker_id),
		"team": team,
	}
	r.rules = {
		"can_flee": can_flee,
		"can_befriend": can_befriend,
		"defeat_policy": policy_name(),
		"story_critical": story_critical,
		"spar": spar,
		"protect": protect.duplicate(),
	}
	var items: Array = []
	for i in reward_items:
		items.append(String(i))
	var flags: Array = []
	for f in reward_flags:
		flags.append(f)
	r.rewards = {"gold": reward_gold, "items": items, "points": 0, "flags": flags}
	r.intro_scene = intro_scene.resource_path if intro_scene != null else ""
	r.outro_scene = outro_scene.resource_path if outro_scene != null else ""
	r.map_path = map_path
	r.campaign_chapter = campaign_chapter
	r.squad_size = squad_size
	r.ai_difficulty = ai_difficulty
	r.clash_intro = clash_intro
	return r


## The strength multiplier [param state] earns this spec (1.0 without a [member scale_flag]).
func scale_factor(state: StoryState) -> float:
	if scale_flag.strip_edges().is_empty() or state == null or scale_step <= 0.0:
		return 1.0
	var n: int = clampi(state.get_flag_int(scale_flag), 0, maxi(0, scale_max_steps))
	return 1.0 + scale_step * float(n)


## Scale [param request]'s opponent strengths for [param state] ([method scale_factor]); a no-op
## for an unscaled spec.
func apply_scaling(request: BattleRequest, state: StoryState) -> void:
	var f: float = scale_factor(state)
	if request == null or is_equal_approx(f, 1.0):
		return
	var team = request.opponent.get("team", [])
	if not (team is Array):
		return
	for t in team:
		if t is Dictionary:
			(t as Dictionary)["strength"] = snappedf(float((t as Dictionary).get("strength", 1.0)) * f, 0.001)


## The first opponent's strength for [param state] (scaling included): what a ladder shows.
func lead_strength(state: StoryState = null) -> float:
	if opponent_team.is_empty():
		return 1.0
	return float(opponent_team[0].get("strength", 1.0)) * scale_factor(state)


func validate(issues: Array[String]) -> void:
	if kind == Kind.TACTICAL:
		if map_path.is_empty() and campaign_chapter.is_empty():
			issues.append("tactical battle has neither a map_path nor a campaign_chapter")
		elif not map_path.is_empty():
			if not ResourceLoader.exists(map_path):
				issues.append("battle map '%s' does not exist" % map_path)
			else:
				var m := load(map_path) as MapResource
				if m == null:
					issues.append("battle map '%s' is not a MapResource" % map_path)
				else:
					var v: Dictionary = m.validate_map(true)
					if not bool(v.get("valid", false)):
						issues.append("battle map '%s' fails validation: %s" % [map_path, str(v.get("issues", []))])
	else:
		if opponent_team.is_empty():
			issues.append("duel has no opponent_team")
	for t in opponent_team:
		var cid: String = String((t as Dictionary).get("character_id", ""))
		var chr: CharacterResource = CharacterLibrary.get_character(StringName(cid))
		if chr == null:
			issues.append("opponent character '%s' does not exist" % cid)
		elif kind == Kind.DUEL and not DuelMoveCompiler.is_duel_eligible(chr):
			# The duel refuses a kit with no offensive move (DuelSetup lists only eligible units).
			issues.append("duel opponent '%s' is not duel-eligible" % cid)
	if not scale_flag.strip_edges().is_empty() and (scale_step <= 0.0 or scale_max_steps <= 0):
		issues.append("scale_flag '%s' set but scale_step / scale_max_steps are zero" % scale_flag)
	for i in reward_items:
		if not ItemLibrary.has_item(i):
			issues.append("reward item '%s' does not exist" % i)


func _to_string() -> String:
	return "Battle(%s vs %s)" % [kind_name(), opponent_name]
