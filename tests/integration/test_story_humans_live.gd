extends GutTest

## HUMANS IN STORY against the live StoryController (docs/design/HUMANS.md): a new journey starts
## with the hero's party record; the opening's first fight fields the hero (required) beside the
## starter with the hero guard installed; Varden fights as himself; an older save gets the hero on
## load; the picker never opens headless.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const FIRST_FIGHT_MAP := "res://game/overworld/content/battles/ow_oakvale_ashes.tres"

var _guard


func before_each() -> void:
	_guard = Guard.new()
	for k in ["selected_map_path", "selected_squad", "game_mode", "ai_difficulty", "player_count"]:
		_guard.watch_setting(k)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false


func after_each() -> void:
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	_guard.restore()


func test_a_new_journey_starts_with_the_hero_record() -> void:
	assert_true(bool(StoryController.new_journey(0)["success"]))
	var s: StoryState = StoryController.state()
	var hero: StoryPartyMember = s.hero_member()
	assert_not_null(hero, "the hero is a party member")
	assert_eq(hero.character_id, "wren")
	assert_eq(hero.level, ProgressionRules.current().starter_level)
	assert_eq(hero.display_name(), StoryController.hero_name())
	assert_true(hero.is_human())
	assert_false(StoryController.can_battle(), "no partner creature yet: the opening walks past fights")


func test_the_first_fight_fields_the_hero_and_the_general_himself() -> void:
	StoryController.new_journey(0)
	var s: StoryState = StoryController.state()
	StoryFixture.past_opening(s)
	s.set_location("oakvale_ruins", Vector3i(5, 5, 0), "north")
	var ruins := StoryController.load_area("oakvale_ruins")
	var spec: BattleSpec = null
	var all_cmds: Array = _flatten(ruins.on_enter)
	for e in ruins.entities:
		all_cmds.append_array(_commands_of(e))
	for c in all_cmds:
		if c is StartBattleCommand and c.spec != null and c.spec.map_path == FIRST_FIGHT_MAP:
			spec = c.spec
	assert_not_null(spec, "the first fight's spec is authored in the ruins")
	if spec == null:
		return
	assert_eq(spec.hero_deploy, BattleSpec.HeroDeploy.REQUIRED)
	var req := spec.to_request(BattleRequest.SOURCE_SCRIPT)
	var began: Dictionary = StoryController.begin_battle(req, false)
	assert_true(bool(began["success"]), str(began))
	var party: Array = StoryController.active_request().party
	assert_eq(String(party[0]["character_id"]), "wren", "the hero deploys first")
	assert_true(bool(party[0]["hero"]))
	assert_eq(party.size(), 3, "hero + the two partners fill the three chairs")
	assert_eq(StoryController.active_request().hero_member_ids(), ["wren"] as Array[String])
	var guards := StoryBattleBridge.guards_for(StoryController.active_request())
	assert_true(guards.any(func(g): return String(g.get_meta(&"story_reason", "")) == StoryPermadeath.REASON_HERO),
		"his fall is a game over")
	var map := load(FIRST_FIGHT_MAP) as MapResource
	var guests: Array = []
	for sp in map.unit_spawns:
		if String(sp.get("spawn_kind", "")) == MapResource.SPAWN_KIND_REINFORCEMENT:
			guests.append(String(sp.get("character_id", "")))
	assert_true(guests.has("varden"), "General Varden fights as himself: %s" % str(guests))
	assert_false(StoryController.should_pick_squad(req), "headless: no picker")


func test_an_older_save_gets_the_hero_on_load() -> void:
	var s := StoryState.new()
	s.add_member("tree_grunt", "", 6, 9)
	var hero := StoryController.ensure_hero(s, StoryRuleset.load_default(), true)
	assert_not_null(hero)
	assert_true(hero.is_hero)
	assert_eq(hero.level, 9, "an old save's hero catches up to the party's top level")
	assert_eq(StoryController.ensure_hero(s, StoryRuleset.load_default(), true), hero, "only once")


func _commands_of(e) -> Array:
	var out: Array = []
	for key in ["on_interact", "on_step"]:
		if key in e:
			var v = e.get(key)
			if v is Array:
				out.append_array(_flatten(v))
	return out


func _flatten(cmds: Array) -> Array:
	var out: Array = []
	for c in cmds:
		if c == null:
			continue
		out.append(c)
		for key in ["then_commands", "else_commands", "commands"]:
			if key in c and c.get(key) is Array:
				out.append_array(_flatten(c.get(key)))
		if "options" in c and c.get("options") is Array:
			for o in c.get("options"):
				if o != null and "commands" in o:
					out.append_array(_flatten(o.get("commands")))
	return out
