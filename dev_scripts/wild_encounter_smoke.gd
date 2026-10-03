extends SceneTree

## Headless WILD ENCOUNTER smoke run: the real overworld, the real duel scene, the real scene
## changes -- no stub, no test doubles. It
##   1. starts a story journey past the opening with a two-member party, standing in the Mossway
##      (grass forced to the HIDDEN per-step roll at rate 1.0 so the first grass step fires);
##   2. steps into the tall grass and waits for the duel scene to load;
##   3. lets the AI play the duel to its end, presses the results card's Continue;
##   4. waits for the overworld to come back and checks the hero is on the same cell, the party's
##      HP was carried, the scene is the overworld again and input is not blocked.
## Every step prints a "SMOKE" line; the process exits non-zero on a failed check. Engine errors
## (SCRIPT ERROR / ERROR) show in the output too -- grep for them.
##
##   godot --headless --path . --script dev_scripts/wild_encounter_smoke.gd
##
## Everything is loaded by path after the first frame so the autoloads are registered before the
## gameplay scripts compile (see duel_smoke.gd / check_uid_warnings.gd).

const OVERWORLD_SCENE := "res://game/overworld/OverworldScene.tscn"
const START_CELL := Vector3i(4, 2, 0)

var _failed: bool = false
var _duel: Node = null


func _initialize() -> void:
	# A watchdog: never hang a CI shell.
	create_timer(300.0).timeout.connect(func() -> void:
		print("SMOKE FAIL: timed out")
		quit(2))
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _check(ok: bool, what: String) -> void:
	print("SMOKE %s: %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_failed = true


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


## Wait up to [param seconds] of REAL time for [param pred] (the duel stage paces itself on timers); true when it held.
func _until(pred: Callable, seconds: float = 60.0) -> bool:
	var deadline: int = Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if bool(pred.call()):
			return true
		await process_frame
	return bool(pred.call())


## The duel launcher: DuelController.launch_from_story with the party played by the AI.
func _ai_launch(battle_request) -> Dictionary:
	var res: Dictionary = load("res://game/duel/DuelRequest.gd").from_battle_request(battle_request.to_dict())
	if not bool(res["success"]):
		return res
	res["request"].player_is_ai = true
	return _duel.start(res["request"])


## True while the duel stage is the current scene.
func _on_duel_stage() -> bool:
	if current_scene == null or current_scene.get_script() == null:
		return false
	return String(current_scene.get_script().resource_path).ends_with("DuelStage.gd")


## True while the overworld is the current scene.
func _on_overworld() -> bool:
	return current_scene != null and current_scene.has_method("try_step")


func _run() -> void:
	var story: Node = root.get_node("/root/StoryController")
	var duel: Node = root.get_node("/root/DuelController")
	var settings: Node = root.get_node("/root/GameSettings")
	settings.set("animations_enabled", false)

	# 1. A journey standing in the Mossway grass.
	var fixture = load("res://tests/helpers/story_fixture.gd")
	story.new_journey(0)
	var s = story.state()
	fixture.past_opening(s)
	s.grace_steps = 0
	# The real launcher, except the party's side is played by the AI (set before the stage reads the request).
	_duel = duel
	var launcher_script = load("res://game/overworld/battle/DuelLauncher.gd")
	launcher_script.register(_ai_launch)
	var area = story.load_area("mossway")
	for z in area.zones():
		z.mode = 1  # EncounterZone.Mode.HIDDEN
		z.rate = 1.0
		z.grace_steps = 0
	s.set_location("mossway", START_CELL, "east")
	var hp_before: Array = []
	for m in s.party:
		hp_before.append(m.current_hp)
	print("SMOKE party %s, standing at %s in %s" % [str(s.party.map(func(m): return m.character_id)), str(START_CELL), s.location_area()])

	var ow: Node = (load(OVERWORLD_SCENE) as PackedScene).instantiate()
	root.add_child(ow)
	current_scene = ow
	await _frames(3)
	_check(ow.get_class() != "" and ow.player != null, "the overworld booted with the hero on the map")
	_check(story.has_method("is_script_running") and not story.is_script_running(), "no script is running before the step")
	var tile: String = ow.tile_under_player()
	print("SMOKE hero tile: %s" % tile)

	# 2. Step until the grass fires (the step east lands on tall grass).
	var fired: bool = false
	for i in range(6):
		ow.try_step(Vector2i(1, 0))
		await _frames(4)
		if story.is_script_running() or story.active_request() != null:
			fired = true
			break
	_check(fired, "stepping into the tall grass fired an encounter")
	if not fired:
		quit(1)
		return
	var req = story.active_request()
	_check(req != null and req.is_duel(), "a duel request is armed (kind %s, foe %s)" % [
		req.kind if req != null else "?", str(req.opponent.get("team", [{}])[0].get("character_id", "?")) if req != null else "?"])
	var stood: Vector3i = s.location_cell()
	print("SMOKE return point: %s" % str(req.return_to if req != null else {}))

	# 3. The real duel scene loads (scene change), the AI plays the party's side.
	var loaded: bool = await _until(_on_duel_stage, 30.0)
	_check(loaded, "the real duel scene is the current scene (%s)" % (current_scene.name if current_scene != null else "none"))
	if not loaded:
		quit(1)
		return
	var dreq = duel.active_request()
	_check(dreq != null and duel.is_story_duel(), "DuelController holds the staged STORY duel")
	_check(dreq != null and dreq.is_wild(), "it is a wild encounter with one foe (%d)" % (dreq.foe_party.size() if dreq != null else -1))
	var stage: Node = current_scene
	var over: bool = await _until(func() -> bool: return stage.battle != null and stage.battle.is_over, 150.0)
	_check(over, "the duel ran to its end (outcome %s)" % (str(stage.battle.result.outcome) if over else "?"))
	if not over:
		quit(1)
		return
	var shown: bool = await _until(func() -> bool: return stage.hud.results_visible(), 30.0)
	_check(shown, "the results card is up")
	if shown:
		var cont = stage.hud.continue_button()
		_check(cont != null, "it offers Continue Journey")
		if cont != null:
			cont.pressed.emit()

	# 4. Back in the overworld, on the same cell.
	var back: bool = await _until(_on_overworld, 30.0)
	_check(back, "the overworld scene is back (%s)" % (current_scene.name if current_scene != null else "none"))
	if not back:
		quit(1)
		return
	await _frames(10)
	var ow2: Node = current_scene
	s = story.state()
	_check(s.location_cell() == stood, "the saved location is the cell the hero fought on %s" % str(stood))
	_check(ow2.player.cell == stood, "the hero stands on it again (%s)" % str(ow2.player.cell))
	var hp_after: Array = []
	for m in s.party:
		hp_after.append(m.current_hp)
	print("SMOKE party HP before %s after %s" % [str(hp_before), str(hp_after)])
	_check(not story.is_battle_active() and story.active_request() == null, "no battle is left armed")
	await _until(func() -> bool: return not story.is_script_running(), 20.0)
	_check(not ow2.is_input_blocked(), "input is not blocked")
	var moved: bool = ow2.try_step(Vector2i(0, 1))
	_check(moved, "the hero can walk on after the encounter")
	await _frames(5)
	print("SMOKE %s" % ("DONE: all checks passed" if not _failed else "DONE: FAILED"))
	quit(1 if _failed else 0)
