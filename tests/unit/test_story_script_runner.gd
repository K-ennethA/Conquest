extends GutTest

## StoryScriptRunner + the commands, driven against a FAKE host (StoryScriptHost that records and
## completes instantly) and a FAKE session (battles resolve immediately) -- the whole interaction
## layer, no scene tree (docs/design/OVERWORLD.md §4.4).


class FakeHost extends StoryScriptHost:
	var said: Array = []
	var choices: Array = []
	var pick: int = 0
	var moves: Array = []
	var emotes: Array = []
	var toasts: Array = []
	var refreshes: int = 0

	func show_dialogue(scene: StoryScene) -> void:
		for b in scene.playable_beats():
			said.append(b)

	func show_choice(prompt: StoryBeat, options: PackedStringArray, cancel_index: int = -1) -> int:
		choices.append({"prompt": prompt.text, "options": options, "cancel": cancel_index})
		return pick

	func move_actor(actor_id: String, to: Vector3i, persist: bool = false) -> void:
		moves.append([actor_id, to, persist])

	func emote(actor_id: String, glyph: String) -> void:
		emotes.append([actor_id, glyph])

	func toast(text: String, kind: String = "") -> void:
		toasts.append([text, kind])

	func refresh_world() -> void:
		refreshes += 1


class FakeSession extends RefCounted:
	var next_outcome: String = BattleResult.OUTCOME_VICTORY
	var offer: String = ""
	var requests: Array = []
	var saves: int = 0
	var warps: Array = []

	func run_battle(request: BattleRequest) -> BattleResult:
		requests.append(request)
		var r := BattleResult.make(request.encounter_id, next_outcome)
		if not offer.is_empty():
			r.befriend_offer = {"character_id": offer, "accepted": false}
		return r

	func save_game() -> Dictionary:
		saves += 1
		return {"success": true, "reason": ""}

	func warp_to(area_id: String, entry_id: String) -> Dictionary:
		warps.append([area_id, entry_id])
		return {"success": true}

	func hero_name() -> String:
		return "Warden"

	func party_cap() -> int:
		return 6


var _host: FakeHost
var _session: FakeSession
var _state: StoryState


func before_each() -> void:
	_host = FakeHost.new()
	_session = FakeSession.new()
	_state = StoryState.new()
	_state.add_member("vineweave")


func _ctx() -> ScriptContext:
	var c := ScriptContext.new(_state, _host, _session, "oakvale")
	c.owner_id = "elder"
	c.vars["owner_speaker_id"] = "npc_elder"
	c.vars["owner_speaker_name"] = "Elder Wynn"
	return c


func _say(text: String, speaker: StringName = &"self") -> SayCommand:
	var s := SayCommand.new()
	s.beats = StoryCommand.list([SayCommand.beat(speaker, "", text)])
	return s


func test_say_resolves_self_hero_and_substitutions() -> void:
	var runner := StoryScriptRunner.new()
	await runner.run([_say("Hello {hero}, you carry {gold} gold."), _say("I am you.", &"hero")], _ctx())
	assert_eq(_host.said.size(), 2, "both lines shown")
	assert_eq((_host.said[0] as StoryBeat).speaker_name, "Elder Wynn", "'self' becomes the NPC")
	assert_eq((_host.said[0] as StoryBeat).text, "Hello Warden, you carry 0 gold.", "{hero} and {gold} filled in")
	assert_eq((_host.said[1] as StoryBeat).speaker_name, "Warden", "'hero' becomes the hero")
	assert_false(runner.is_running(), "the lock is released at the end")


func test_shared_beats_are_never_mutated() -> void:
	var s := _say("Gold: {gold}")
	var original: StoryBeat = s.source_beats()[0]
	await StoryScriptRunner.new().run([s], _ctx())
	assert_eq(original.text, "Gold: {gold}", "the authored beat keeps its placeholder (rule 7)")


func test_choice_runs_the_picked_branch() -> void:
	var c := ChoiceCommand.new()
	c.prompt = SayCommand.beat(&"self", "", "Will you walk the Mossway?")
	c.options = StoryCommand.list([
		ChoiceOption.make("Yes", [SetFlagCommand.make("quest.blight_road", 1)]),
		ChoiceOption.make("No", [SetFlagCommand.make("said_no", 1)], true),
	])
	_host.pick = 0
	await StoryScriptRunner.new().run([c], _ctx())
	assert_true(_state.has_flag("quest.blight_road"), "Yes set the quest flag")
	assert_false(_state.has_flag("said_no"), "the other branch did not run")
	assert_eq(_host.choices[0]["cancel"], 1, "the cancel option is passed to the dialogue")
	assert_eq(_host.choices[0]["options"].size(), 2, "both options offered")
	assert_gt(_host.refreshes, 0, "a flag change refreshes the world")
	_host.pick = 1
	await StoryScriptRunner.new().run([c], _ctx())
	assert_true(_state.has_flag("said_no"), "No ran its branch")


func test_choice_hides_options_whose_condition_fails() -> void:
	var c := ChoiceCommand.new()
	c.options = StoryCommand.list([ChoiceOption.make("A"), ChoiceOption.make("B")])
	(c.options[1] as ChoiceOption).condition = "has(\"never\")"
	await StoryScriptRunner.new().run([c], _ctx())
	assert_eq(_host.choices[0]["options"].size(), 1, "a gated option is not offered")


func test_if_branches() -> void:
	_state.set_flag("x", 1)
	await StoryScriptRunner.new().run([IfCommand.make("has(\"x\")", [SetFlagCommand.make("then", 1)],
		[SetFlagCommand.make("else", 1)])], _ctx())
	assert_true(_state.has_flag("then"), "then branch")
	assert_false(_state.has_flag("else"), "not else")


func test_start_battle_resumes_with_last_result() -> void:
	var spec := BattleSpec.new()
	spec.map_path = "res://x.tres"
	var fight := StartBattleCommand.new()
	fight.spec = spec
	fight.encounter_id = "trainer.mossway.bram"
	var after := IfCommand.make("outcome() == \"victory\"", [SetFlagCommand.make("won", 1)], [SetFlagCommand.make("lost", 1)])
	var ctx := _ctx()
	await StoryScriptRunner.new().run([fight, after], ctx)
	assert_eq(_session.requests.size(), 1, "the battle went through the SESSION, not the host")
	assert_eq((_session.requests[0] as BattleRequest).encounter_id, "trainer.mossway.bram", "with its id")
	assert_true(_state.has_flag("won"), "the script continued after the battle, reading outcome()")
	assert_eq(ctx.last_result.outcome, "victory", "last_result is kept on the context")
	_session.next_outcome = BattleResult.OUTCOME_DEFEAT
	await StoryScriptRunner.new().run([fight, after], _ctx())
	assert_true(_state.has_flag("lost"), "a loss branches the other way")


func test_befriend_prompt_accept_decline_and_story_flag() -> void:
	var duel := StartDuelCommand.new()
	var entry := EncounterEntry.new()
	entry.character_id = &"petalfang"
	duel.entry = entry
	var prompt := BefriendPromptCommand.new()
	prompt.flag_on_join = "mossway.petalfang.recruited"
	_session.offer = "petalfang"
	_host.pick = 1
	var ctx := _ctx()
	await StoryScriptRunner.new().run([duel, prompt], ctx)
	assert_eq(_state.party.size(), 1, "'Not now' adds nobody")
	assert_false(_state.has_flag("mossway.petalfang.recruited"), "and leaves the recruit in the world")
	assert_true(ctx.last_result.has_open_offer(), "the offer stays unaccepted")
	_host.pick = 0
	var ctx2 := _ctx()
	await StoryScriptRunner.new().run([duel, prompt], ctx2)
	assert_eq(_state.party.size(), 2, "'Welcome it' adds the member")
	assert_eq(_state.party[1].member_id, "petalfang", "with a stable RosterLedger-style id")
	assert_true(bool(ctx2.last_result.befriend_offer["accepted"]), "offer.accepted is set")
	assert_eq(ctx2.last_result.befriended, "petalfang", "and result.befriended")
	assert_true(_state.has_flag("mossway.petalfang.recruited"), "the story flag is set")
	assert_eq((_session.requests[0] as BattleRequest).kind, "duel", "a wild encounter is a duel")


func test_no_offer_no_prompt() -> void:
	await StoryScriptRunner.new().run([StartDuelCommand.new(), BefriendPromptCommand.new()], _ctx())
	assert_eq(_host.choices.size(), 0, "no offer -> no prompt")


func test_gifts_heal_save_respawn_move_emote() -> void:
	var give := GiveItemCommand.new()
	give.item_id = &"sagebloom_poultice"
	var gold := GiveGoldCommand.new()
	gold.amount = 30
	var respawn := SetRespawnCommand.new()
	respawn.area_id = &"oakvale"
	respawn.entry = &"wayshrine"
	respawn.wayshrine_key = "oakvale.wayshrine"
	var move := MoveActorCommand.new()
	move.actor = "guard"
	move.to = Vector3i(18, 10, 0)
	move.persist = true
	var emote := EmoteCommand.new()
	emote.actor = "self"
	_state.party[0].current_hp = 3
	await StoryScriptRunner.new().run([give, gold, HealPartyCommand.new(), respawn, SaveGameCommand.new(), move, emote], _ctx())
	assert_eq(_state.item_count("sagebloom_poultice"), 1, "item in the bag")
	assert_eq(_state.gold, 30, "gold")
	assert_eq(_state.party[0].current_hp, StoryPartyMember.HP_FULL, "healed")
	assert_eq(_state.respawn["entry"], "wayshrine", "respawn set")
	assert_eq(_state.lit_wayshrines, ["oakvale.wayshrine"] as Array[String], "shrine lit")
	assert_eq(_session.saves, 1, "saved through the session")
	assert_eq(_host.moves[0], ["guard", Vector3i(18, 10, 0), true], "the host walked the guard")
	assert_eq(_state.actor_override("oakvale", "guard")["cell"], Vector3i(18, 10, 0), "and the move persists in the state")
	assert_eq(_host.emotes[0], ["elder", "!"], "'self' resolves to the owner")
	assert_eq(_host.toasts.size(), 2, "item + gold toasts")


func test_warp_is_terminal_and_the_lock_is_released() -> void:
	var w := WarpCommand.new()
	w.area_id = &"mossway"
	w.entry = &"west"
	var runner := StoryScriptRunner.new()
	var ctx := _ctx()
	await runner.run([w, SetFlagCommand.make("after_warp", 1)], ctx)
	assert_eq(_session.warps[0], ["mossway", "west"], "the warp went through the session")
	assert_false(_state.has_flag("after_warp"), "nothing runs after a warp")
	assert_true(ctx.stopped, "the context is stopped")
	assert_false(runner.is_running(), "and the lock released")


func test_a_busy_runner_refuses_a_second_script() -> void:
	var runner := StoryScriptRunner.new()
	# A command that never completes within this test: a WaitCommand on a host that waits a frame.
	var slow := WaitCommand.new()
	slow.seconds = 1.0
	var frame_host := FrameHost.new()
	frame_host.tree = get_tree()
	var ctx := ScriptContext.new(_state, frame_host, _session, "oakvale")
	runner.run([slow], ctx)
	assert_true(runner.is_running(), "the first script holds the lock while awaiting")
	var second: bool = await runner.run([SetFlagCommand.make("second", 1)], _ctx())
	assert_false(second, "a second script is refused while the first runs")
	assert_false(_state.has_flag("second"), "and did not run")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_false(runner.is_running(), "the lock is released when the first ends")


class FrameHost extends StoryScriptHost:
	var tree: SceneTree

	func wait(_seconds: float) -> void:
		await tree.process_frame
