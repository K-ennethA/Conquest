extends Node

## Drives a CAMPAIGN chapter run and OWNS its progress across the scene reloads a battle
## walks through (chapter list -> squad pick -> battle -> end screen). Registered as an
## autoload so it survives every scene change and can quietly capture the battle result --
## the same reason [b]ChallengeController[/b] and [b]ArenaController[/b] are autoloads. It
## imitates ChallengeController's staging pattern (prepare -> pick squad -> begin) WITHOUT
## editing GameWorldManager or MapLoader:
##
##   CampaignScreen -> prepare(chapter) -> begin()
##       -> point GameSettings at the chapter's SHIPPED map (a plain res:// path -- no
##          materialisation needed, unlike a challenge's untrusted JSON), set SINGLE_PLAYER
##          + the chapter's AI difficulty, arm result capture
##       -> CharacterSelect (limited to the chapter's squad_size)
##       -> GameWorld battle
##       -> result captured off the elimination signals -> campaign.json
##
## RESULT CAPTURE without a GameWorldManager edit: this node scores the SAME win/lose rules
## the battle itself uses -- [WinConditionLibrary].build_rules(map.victory_conditions),
## evaluated over the live board on every unit/player elimination. Scoring the map's real
## objectives (rather than re-deriving "no enemy left" from PlayerManager) is what makes the
## Eldroot finale work: forgotten_forest is a DEFEAT-BOSS map with endless spawns, so the
## enemy side is never empty -- the win is the boss's death, which only the win-condition
## evaluation sees. Capture is gated on an active run AND on GameSettings still pointing at
## THIS chapter's map, so an elimination in a later, unrelated match never records a result.

##
## STORY SCENES (added on top of the above; every hook is additive and optional). A chapter
## may carry an [code]intro_scene[/code] and/or an [code]outro_scene[/code] -- res:// paths
## to a [StoryScene] (see [CampaignData]). This controller owns BOTH playbacks because it is
## the one object that outlives the scene changes they straddle:
##
##   INTRO -- played by [method play_intro_then_launch], called from Character Select's
##            campaign confirm branch INSTEAD of its immediate change_scene. The overlay
##            mounts over the screen the player is already looking at, blocks input to
##            everything behind it, and the battle scene is only loaded once the story
##            finishes (or is skipped). A chapter with no intro returns false and the caller
##            changes scene exactly as it did before.
##   OUTRO -- played from [method _record_result] on a WIN only; a loss never plays one. It
##            mounts over the live battle at [constant StoryDialogue.LAYER_INDEX] (135),
##            which is above the battle's own "UI" CanvasLayer, so it covers [GameOverScreen]
##            and the player reads the outro before the results card -- with NO edit to
##            GameWorldManager or the end screen. The mount is DEFERRED, because
##            _record_result runs deep inside the death -> elimination signal cascade and
##            adding a node there would fight the teardown that cascade is driving.
##
## REPLAYS NEVER PLAY STORY. [method story_suppressed] reads [method ReplayPlayback.is_playing],
## so watching a recorded campaign battle back is watching the battle, not sitting through
## its cutscenes again.

const CHARACTER_SELECT_SCENE := "res://menus/CharacterSelect.tscn"
const CAMPAIGN_SCREEN_SCENE := "res://menus/CampaignScreen.tscn"

## Chapter-dictionary keys the two optional story scenes live under (see [CampaignData]).
const INTRO_SCENE_KEY := "intro_scene"
const OUTRO_SCENE_KEY := "outro_scene"

## Where cleared-chapter progress + best turn counts live. Overridable so tests can
## round-trip against a temp file instead of the player's real save.
const DEFAULT_PROGRESS_PATH := "user://campaign.json"
var _progress_path: String = DEFAULT_PROGRESS_PATH

## The chapter staged for the squad pick (read by CharacterSelect). Empty when none.
var _pending: Dictionary = {}

## The chapter whose battle is currently live, plus the map path we staged and the
## compiled win/lose rules for it. The path is the guard that stops a later match's
## eliminations from recording here.
var _active: Dictionary = {}
var _active_map_path: String = ""
var _active_rules: GameModeRules = null

## Set once per battle so repeated elimination signals record a single result.
var _result_recorded: bool = false

## Player turns taken this battle (fed to the best-turn record).
var _turns: int = 0

## The live story overlay, or null. Exactly one at a time -- mounting a second dismisses
## the first (see [method play_story]).
var _story_overlay: StoryDialogue = null


func _ready() -> void:
	name = "CampaignController"
	# Survive the pause the GameOverScreen applies, and outlive every scene change.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Result capture rides the elimination signals GameWorldManager itself trusts:
	# unit_eliminated is essential (a boss death does NOT eliminate a whole player while
	# its grunts stand), player_eliminated is the wipe case. Both handlers are idempotent
	# per battle (_result_recorded), so connecting several sources is safe.
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null:
		if GameEvents.has_signal("unit_eliminated"):
			GameEvents.unit_eliminated.connect(_on_unit_eliminated)
		if GameEvents.has_signal("player_eliminated"):
			GameEvents.player_eliminated.connect(_on_player_eliminated)
	if PlayerManager != null:
		if PlayerManager.has_signal("player_eliminated"):
			PlayerManager.player_eliminated.connect(_on_player_eliminated)
		# Turn tally: connect ONE source only (PlayerManager, the reliable one) so turns
		# are not double-counted.
		if PlayerManager.has_signal("player_turn_started"):
			PlayerManager.player_turn_started.connect(_on_player_turn_started)


# --- Staging (chapter list -> squad pick) -----------------------------------

## Stage [param chapter] for play without starting yet (mirrors ChallengeController.prepare).
func prepare(chapter: Dictionary) -> void:
	_pending = chapter.duplicate(true)


## True while a chapter is staged and waiting for its squad pick. CharacterSelect reads
## this to know it should cap the pick to the chapter's squad_size and, on confirm, run
## the normal map -> GameWorld path (the map is already staged in GameSettings).
func has_pending_chapter() -> bool:
	return not _pending.is_empty()


## Squad-pick cap for the staged chapter (its squad_size), or 0 when none staged.
func pending_squad_size() -> int:
	if _pending.is_empty():
		return 0
	return maxi(1, int(_pending.get("squad_size", 4)))


## Display title of the staged chapter (for the Character Select header).
func pending_name() -> String:
	if _pending.is_empty():
		return "Campaign"
	return String(_pending.get("title", "Campaign"))


## Stage the pending chapter for play and route to the squad pick. Returns false (staying
## put) when the chapter's map cannot be loaded, so the caller can surface an error. On
## success this configures GameSettings for the run and changes scene to Character Select.
func begin() -> bool:
	if _pending.is_empty():
		return false
	var chapter: Dictionary = _pending
	var map_path: String = String(chapter.get("map_path", ""))
	if map_path.is_empty():
		push_error("CampaignController.begin: chapter has no map_path.")
		return false

	var map_resource: MapResource = load(map_path) as MapResource
	if map_resource == null:
		push_error("CampaignController.begin: could not load chapter map '%s'." % map_path)
		return false

	# Defensive: drop any Arena / Challenge run staged earlier so CharacterSelect's confirm
	# can never mistake this campaign launch for one of them.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run() \
			and arena.has_method("abort_run"):
		arena.abort_run()
	var challenge := get_node_or_null("/root/ChallengeController")
	if challenge != null and challenge.has_method("has_pending_challenge") \
			and challenge.has_pending_challenge() and challenge.has_method("cancel"):
		challenge.cancel()

	if GameSettings != null:
		GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
		if GameSettings.has_method("set_ai_difficulty"):
			GameSettings.set_ai_difficulty(int(chapter.get("ai_difficulty", 1)))
		if GameSettings.has_method("clear_selected_squad"):
			GameSettings.clear_selected_squad()
		if GameSettings.has_method("set_player_count"):
			GameSettings.set_player_count(_team_count(map_resource))
		GameSettings.set_selected_map(map_path)

	# Arm result capture for this run: score the map's OWN objectives (the boss finale
	# needs the DefeatBoss rule, not a naive "no enemy left").
	_active = chapter
	_active_map_path = map_path
	_active_rules = WinConditionLibrary.build_rules(map_resource.victory_conditions)
	_result_recorded = false
	_turns = 0

	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
	return true


## Called by CharacterSelect when the player confirms their squad and heads into battle.
## Clears the staging slot (the pick is done) while KEEPING the run armed for result
## capture, so a later Arena / Skirmish launch is never misread as this chapter.
func notify_squad_confirmed() -> void:
	_pending = {}


## Abandon the staged/active run (Character Select "Back", or bailing out). Clears the
## capture arming so nothing records after the player walks away.
func cancel() -> void:
	_pending = {}
	_active = {}
	_active_map_path = ""
	_active_rules = null
	_result_recorded = false
	_turns = 0
	# A story mounted for a run the player just walked away from must come down with it.
	_dismiss_story()


# --- Story scenes -----------------------------------------------------------

## The [StoryScene] at [param chapter]'s [param key] ("intro_scene" / "outro_scene"), or null
## when the chapter carries no such key, the path is empty, the file is missing, or it is not
## a StoryScene. A missing story is an ORDINARY, expected answer -- an unscripted chapter is
## the norm -- so this returns null rather than logging (CONQUEST.md #1).
static func story_scene_for(chapter: Dictionary, key: String) -> StoryScene:
	if chapter.is_empty():
		return null
	var path: String = String(chapter.get(key, ""))
	if path.is_empty():
		return null
	if not ResourceLoader.exists(path):
		return null
	return load(path) as StoryScene


## True while story playback must be suppressed outright. Today that is exactly one case:
## a REPLAY. A replay re-simulates a recorded battle for a viewer who has already lived
## through its cutscene, and the overlay would block the spectator's own camera/inspection
## input on top of that.
static func story_suppressed() -> bool:
	return ReplayPlayback.is_playing()


## PURE decision: is [param scene] something we should actually put on screen? Static and
## side-effect free so the gate is testable without a tree, an overlay or a battle.
static func can_play_story(scene: StoryScene) -> bool:
	if scene == null or scene.is_empty():
		return false
	return not story_suppressed()


## Mount a [StoryDialogue] over whatever is currently on screen and play [param scene],
## calling [param on_done] once it finishes OR is skipped.
##
## Returns TRUE when the overlay went up (so [param on_done] will fire later) and FALSE when
## there was nothing to play -- which is the shape every call site wants: "false, so do the
## thing you were going to do anyway, right now".
##
## The overlay is parented to the SceneTree ROOT rather than the current scene, because the
## intro's whole job is to outlive the screen it started over and hand off to the battle.
func play_story(scene: StoryScene, on_done: Callable) -> bool:
	if not can_play_story(scene):
		return false
	var tree: SceneTree = get_tree()
	if tree == null or tree.root == null:
		return false

	_dismiss_story()

	var overlay := StoryDialogue.new()
	_story_overlay = overlay
	tree.root.add_child(overlay)

	# ONE_SHOT: the overlay is torn down in this handler, so a second emission is impossible
	# by construction -- but connecting one-shot means a future re-play of the same node
	# could never double-fire the continuation either.
	overlay.finished.connect(func(_skipped: bool) -> void:
		_dismiss_story()
		if on_done.is_valid():
			on_done.call()
	, CONNECT_ONE_SHOT)

	if not overlay.play(scene):
		# Defensive: can_play_story already rejected an empty scene, so this is the
		# impossible-in-practice branch. Take the overlay back down rather than leaving a
		# blank input blocker on screen.
		_dismiss_story()
		return false
	return true


## Play the ACTIVE chapter's intro, then load [param battle_scene_path]. Returns false when
## there is no intro (or story is suppressed), leaving the caller to change scene itself --
## see the campaign branch of [code]CharacterSelect._on_confirm_pressed[/code].
func play_intro_then_launch(battle_scene_path: String) -> bool:
	return play_story(story_scene_for(_active, INTRO_SCENE_KEY), func() -> void:
		var tree: SceneTree = get_tree()
		if tree != null:
			tree.change_scene_to_file(battle_scene_path)
	)


## True while a story overlay is up. Public so a future caller (a pause menu, a mid-battle
## trigger) can avoid stacking a second one.
func is_story_playing() -> bool:
	return _story_overlay != null and is_instance_valid(_story_overlay)


## The live overlay, or null. Test/tooling hook -- gameplay code should use
## [method is_story_playing] rather than reaching into the node.
func story_overlay() -> StoryDialogue:
	return _story_overlay


## Play the just-cleared chapter's outro, if it has one. Called from [method _record_result]
## on a WIN only.
##
## DEFERRED mount: _record_result runs inside the death -> elimination signal cascade, and
## adding a CanvasLayer there means the rest of that cascade (including GameWorldManager's
## own game-over reveal) runs with a half-built overlay in the tree. Deferring lets the
## frame's cascade finish on the intact scene; the overlay then lands on top of the settled
## result screen, which is exactly the read we want.
func _play_outro() -> void:
	var scene: StoryScene = story_scene_for(_active, OUTRO_SCENE_KEY)
	if not can_play_story(scene):
		return
	call_deferred("_mount_outro", scene)


func _mount_outro(scene: StoryScene) -> void:
	# Nothing follows the outro: the results card is already behind it and becomes readable
	# the moment the overlay tears itself down.
	play_story(scene, Callable())


## Take the live overlay down: out of the tree immediately (so it stops drawing and stops
## blocking input on the very same call) and queued for deletion. Safe to call when there
## is nothing mounted, and safe to call from inside the overlay's own finished handler --
## removing a node from the tree during its signal emission is legal; freeing it there is
## not, which is why this queues.
func _dismiss_story() -> void:
	var overlay: StoryDialogue = _story_overlay
	_story_overlay = null
	if overlay == null or not is_instance_valid(overlay):
		return
	var parent: Node = overlay.get_parent()
	if parent != null:
		parent.remove_child(overlay)
	overlay.queue_free()


# --- Mid-battle save / resume -----------------------------------------------

## True while a campaign battle is live and its result would be recorded. Public face of the
## internal capture gate, so the save layer can identify a campaign battle without guessing
## from the map path.
func is_capturing() -> bool:
	return _is_capturing()


## The chapter dict of the live run ({} when none), and its turn tally -- both written into
## the battle snapshot so a resume continues the same chapter attempt.
func active_chapter() -> Dictionary:
	return _active.duplicate(true)


func captured_turns() -> int:
	return _turns


## Re-arm result capture for a RESUMED chapter battle. The same arming block [method begin]
## runs, minus the GameSettings staging and the scene change (the caller owns both) -- so a
## resumed battle records its clear against the right chapter and keeps its turn count.
## Returns false when the chapter's map cannot be loaded, so the caller can discard the save.
func arm_for_resume(chapter: Dictionary, turns: int) -> bool:
	if chapter.is_empty():
		return false
	var map_path: String = String(chapter.get("map_path", ""))
	if map_path.is_empty():
		return false
	var map_resource: MapResource = load(map_path) as MapResource
	if map_resource == null:
		return false
	_pending = {}
	_active = chapter.duplicate(true)
	_active_map_path = map_path
	_active_rules = WinConditionLibrary.build_rules(map_resource.victory_conditions)
	_result_recorded = false
	_turns = maxi(0, turns)
	return true


# --- Battle result capture --------------------------------------------------

func _on_player_turn_started(player) -> void:
	if not _is_capturing():
		return
	if player != null and not _player_is_ai(player) and not _player_is_neutral(player):
		_turns += 1


func _on_unit_eliminated(unit, _eliminator) -> void:
	_evaluate(unit)


func _on_player_eliminated(_player) -> void:
	_evaluate(null)


## Score the map's rules over the live board (plus [param just_removed], so a boss death is
## seen on the very tick it happens) and record a clear on victory. Idempotent per battle.
func _evaluate(just_removed) -> void:
	if not _is_capturing():
		return
	if _result_recorded:
		return
	if _active_rules == null:
		return

	var state: Dictionary = _build_state(just_removed)
	var outcome: int = _active_rules.evaluate(state)
	if outcome == GameModeRules.Outcome.VICTORY:
		_record_result(true)
	elif outcome == GameModeRules.Outcome.DEFEAT:
		_record_result(false)


## Assemble the neutral state a [WinCondition] scores against: every living unit on the
## board plus the just-removed one. Mirrors GameWorldManager._build_win_state so the
## controller reaches the same verdict the battle screen does.
func _build_state(just_removed) -> Dictionary:
	var units: Array = []
	var board = CombatServices.board() if CombatServices != null else null
	if board != null and board.has_method("all_units"):
		for u in board.all_units():
			units.append(u)
	if just_removed != null and just_removed not in units:
		units.append(just_removed)
	return { "units": units, "board": board, "turn": 0 }


## True while a campaign battle is live AND GameSettings still points at its map. The path
## check is the guard that prevents a later, unrelated match from recording a stray result.
func _is_capturing() -> bool:
	if _active.is_empty() or _active_map_path.is_empty():
		return false
	if GameSettings == null:
		return false
	if GameSettings.game_mode != GameSettings.GameMode.SINGLE_PLAYER:
		return false
	return String(GameSettings.selected_map_path) == _active_map_path


func _player_is_ai(player) -> bool:
	return "is_ai" in player and bool(player.is_ai)


func _player_is_neutral(player) -> bool:
	return "is_neutral" in player and bool(player.is_neutral)


func _record_result(won: bool) -> void:
	_result_recorded = true
	if won:
		mark_cleared(String(_active.get("id", "")), _turns)
		# STORY: the chapter outro plays on a WIN only -- a loss goes straight to the
		# defeat card. See the class doc for why it is mounted deferred.
		_play_outro()
	else:
		_touch_play(String(_active.get("id", "")))


# --- Progress persistence ---------------------------------------------------

## Where progress is read/written. Tests point this at a temp file.
func set_progress_path(path: String) -> void:
	_progress_path = path if not path.is_empty() else DEFAULT_PROGRESS_PATH


## The whole progress map ({ chapter_id: record }), or {} when there is no file yet.
func load_progress() -> Dictionary:
	if not FileAccess.file_exists(_progress_path):
		return {}
	var file: FileAccess = FileAccess.open(_progress_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


## The stored record for one chapter id, or {} if it has never been played.
func progress_for(chapter_id: String) -> Dictionary:
	var rec: Variant = load_progress().get(chapter_id, {})
	return rec if rec is Dictionary else {}


func is_cleared(chapter_id: String) -> bool:
	return bool(progress_for(chapter_id).get("cleared", false))


## Best (fewest) turn count for a cleared chapter, or -1 when never cleared.
func best_turns(chapter_id: String) -> int:
	return int(progress_for(chapter_id).get("best_turns", -1))


## True when the chapter is playable: the first chapter always is; every later chapter
## unlocks once the PREVIOUS chapter is cleared.
func is_unlocked(chapter_id: String) -> bool:
	var idx: int = CampaignData.index_of_id(chapter_id)
	if idx <= 0:
		return idx == 0  # chapter 0 unlocked; unknown id (-1) is not
	var prev: Dictionary = CampaignData.get_chapter(idx - 1)
	return is_cleared(String(prev.get("id", "")))


## The first unlocked-and-uncleared chapter (where "Play" should resume), or the last
## chapter when everything is cleared. Returns {} only when the campaign is empty.
func next_playable_chapter() -> Dictionary:
	var chapters: Array = CampaignData.chapters()
	for c in chapters:
		var id: String = String(c.get("id", ""))
		if is_unlocked(id) and not is_cleared(id):
			return c
	if chapters.is_empty():
		return {}
	return chapters[chapters.size() - 1]


## Mark [param chapter_id] cleared, keeping the fewest-turn clear as the best. Public so
## the capture path and the tests share ONE write path. Unlocking the next chapter is
## implicit: is_unlocked() derives it from this chapter's cleared flag.
func mark_cleared(chapter_id: String, turns: int) -> void:
	if chapter_id.is_empty():
		return
	var progress: Dictionary = load_progress()
	var prev: Dictionary = progress.get(chapter_id, {})
	var best: int = int(prev.get("best_turns", -1))
	if turns > 0 and (best < 0 or turns < best):
		best = turns
	progress[chapter_id] = {
		"cleared": true,
		"best_turns": best,
		"plays": int(prev.get("plays", 0)) + 1,
		"last_turns": turns,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	_save_progress(progress)


## Record a play (a loss) without clearing the chapter.
func _touch_play(chapter_id: String) -> void:
	if chapter_id.is_empty():
		return
	var progress: Dictionary = load_progress()
	var prev: Dictionary = progress.get(chapter_id, {})
	progress[chapter_id] = {
		"cleared": bool(prev.get("cleared", false)),
		"best_turns": int(prev.get("best_turns", -1)),
		"plays": int(prev.get("plays", 0)) + 1,
		"last_turns": _turns,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	_save_progress(progress)


## Wipe all campaign progress (used by tests and any future "reset" affordance).
func reset_progress() -> void:
	_save_progress({})


func _save_progress(progress: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(_progress_path, FileAccess.WRITE)
	if file == null:
		push_error("CampaignController: could not write progress to '%s'." % _progress_path)
		return
	file.store_string(JSON.stringify(progress, "\t"))
	file.close()


# --- Helpers ----------------------------------------------------------------

## Number of teams a map uses = highest player_id + 1 across its spawns, clamped to the
## engine's supported 2..4 band (matches ChallengeController._team_count).
func _team_count(map_resource: MapResource) -> int:
	var max_pid: int = 1
	for spawn in map_resource.unit_spawns:
		if spawn is Dictionary:
			max_pid = maxi(max_pid, int(spawn.get("player_id", 0)))
	return clampi(max_pid + 1, 2, 4)
