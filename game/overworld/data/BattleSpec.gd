class_name BattleSpec
extends Resource

## An AUTHORED battle (a trainer, a scripted fight, a story recruit) -- turned into a runtime
## [BattleRequest] by [method to_request] (docs/design/OVERWORLD.md §4.2).

enum Kind { TACTICAL, DUEL }
enum DefeatPolicy { WHITEOUT, CONTINUE, RETRY }
## How the foes' story level is decided (docs/design/PROGRESSION.md §3):
## FIXED -- the authored level ([member enemy_level] / each row's "level"): trainers, main-line
## bosses (the linear spine) and LEGENDS ([method make_legend], DECISIONS.md #81).
## SCALED -- clamp(party top level + [member scale_offset], [member scale_min], [member scale_max]):
## CHIEFS ([method make_chief], DECISIONS.md #80), so they can be taken in any order.
enum LevelMode { FIXED, SCALED }

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
## Duel: [{character_id, strength, level?}] -- `level` = that foe's STORY LEVEL
## (docs/design/PROGRESSION.md; missing = [member enemy_level]); strength stays a stat multiplier on
## top of it (rematch scaling, DuelScaling).
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

@export_group("Level")
## The FOES' story level (docs/design/PROGRESSION.md §3): every tactical enemy unit (a map spawn may
## carry its own "level") and every [member opponent_team] row without a "level". 0 = no level
## (roster base stats).
@export_range(0, 200) var enemy_level: int = 0
## A CHIEF or LEGEND battle: XP uses [member ProgressionRules.battle_mult_boss], and the content
## validator does not hold it to the easy-species rule ([method catch_warnings]).
@export var boss_battle: bool = false
## FIXED (the authored levels) or SCALED to the party ([enum LevelMode]).
@export var level_mode: LevelMode = LevelMode.FIXED
## SCALED: levels above (+) or below (-) the party's top level.
@export_range(-50, 50) var scale_offset: int = 0
## SCALED: never below this level (a chief: its region band's min).
@export_range(1, 200) var scale_min: int = 1
## SCALED: never above this level (a chief: its region band's max); 0 = only the level cap.
@export_range(0, 200) var scale_max: int = 0

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
	if boss_battle:
		r.rules["boss"] = true
	r.enemy_level = maxi(0, enemy_level)
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


## The foes' level this spec resolves to for [param state]: FIXED = [member enemy_level]; SCALED =
## [method Progression.scaled_level] of the party's top level (no state = scale_min).
func resolved_enemy_level(state: StoryState) -> int:
	if level_mode != LevelMode.SCALED:
		return maxi(0, enemy_level)
	var top: int = state.party_top_level() if state != null else maxi(1, scale_min)
	return Progression.scaled_level(top, scale_offset, scale_min, scale_max)


## Make [param spec] a CHIEF battle (DECISIONS.md #80): SCALED inside [param band] (its region's)
## at [param offset] from the party's top level; a boss battle for XP. Returns the spec.
static func make_chief(spec: BattleSpec, band: Vector2i, offset: int = 0) -> BattleSpec:
	var b: Vector2i = Progression.normalize_band(band)
	spec.level_mode = LevelMode.SCALED
	spec.scale_offset = offset
	spec.scale_min = maxi(1, b.x)
	spec.scale_max = maxi(0, b.y)
	spec.boss_battle = true
	return spec


## Make [param spec] a LEGEND battle (DECISIONS.md #81): FIXED at its area band's max +
## [member ProgressionRules.legend_over_band] -- NEVER scaled; a boss battle for XP. Returns the spec.
static func make_legend(spec: BattleSpec, band: Vector2i, rules: ProgressionRules = null) -> BattleSpec:
	spec.level_mode = LevelMode.FIXED
	spec.enemy_level = Progression.legend_level(Progression.normalize_band(band), rules)
	for t in spec.opponent_team:
		(t as Dictionary).erase("level")
	spec.boss_battle = true
	return spec


## Scale [param request] for [param state]: a SCALED spec sets every foe to
## [method resolved_enemy_level] (rows' own levels are overridden); then the rematch STRENGTH
## ([method scale_factor]). A FIXED spec without a rematch flag is left alone.
func apply_scaling(request: BattleRequest, state: StoryState) -> void:
	if request != null and level_mode == LevelMode.SCALED:
		var lv: int = resolved_enemy_level(state)
		request.enemy_level = lv
		var rows = request.opponent.get("team", [])
		if rows is Array:
			for t in rows:
				if t is Dictionary:
					(t as Dictionary)["level"] = lv
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
	var cap: int = ProgressionRules.current().max_level
	if enemy_level > cap:
		issues.append("enemy_level %d is above the level cap %d" % [enemy_level, cap])
	for t in opponent_team:
		if int((t as Dictionary).get("level", 0)) > cap:
			issues.append("opponent '%s' level %d is above the level cap" % [String(t.get("character_id", "")), int(t.get("level", 0))])
	if level_mode == LevelMode.SCALED and scale_max > 0 and scale_min > scale_max:
		issues.append("SCALED level: scale_min %d is above scale_max %d" % [scale_min, scale_max])
	if not scale_flag.strip_edges().is_empty() and (scale_step <= 0.0 or scale_max_steps <= 0):
		issues.append("scale_flag '%s' set but scale_step / scale_max_steps are zero" % scale_flag)
	for i in reward_items:
		if not ItemLibrary.has_item(i):
			issues.append("reward item '%s' does not exist" % i)


## CONTENT GUIDANCE (DECISIONS.md #78, PROGRESSION.md §5): ordinary trainers, new shard users and
## chain-using grunts field mostly EASY (high catch rate) species. One warning per opponent row of a
## NON-BOSS battle whose species' catch rate is below [member ProgressionRules.low_catch_rate].
## Advisory only -- returned for a content test to report, never logged at runtime.
func catch_warnings(rules: ProgressionRules = null) -> Array[String]:
	var out: Array[String] = []
	if boss_battle:
		return out
	var r: ProgressionRules = rules if rules != null else ProgressionRules.current()
	for t in opponent_team:
		var cid: String = String((t as Dictionary).get("character_id", ""))
		var chr: CharacterResource = CharacterLibrary.get_character(StringName(cid))
		if chr == null:
			continue
		var rate: float = Progression.catch_rate_of(chr, r)
		if rate < r.low_catch_rate:
			out.append("%s fields '%s' (catch rate %.2f < %.2f) but is not a boss battle"
				% [opponent_name if not opponent_name.is_empty() else encounter_id, cid, rate, r.low_catch_rate])
	return out


func _to_string() -> String:
	return "Battle(%s vs %s)" % [kind_name(), opponent_name]
