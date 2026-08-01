extends Node

## Drives a CHALLENGE run and OWNS its state across the scene reloads a run walks through
## (browse -> squad pick -> battle -> end screen). Registered as an autoload so it survives
## every scene change and can quietly capture the battle result -- the same reason
## [b]ArenaController[/b] is an autoload. It imitates that controller's staging pattern
## (prepare -> pick squad -> begin) WITHOUT editing GameWorldManager or MapLoader:
##
##   ChallengeBrowse -> prepare(challenge) -> begin()
##       -> materialise the map as a user:// .tres, point GameSettings at it,
##          set turn system + AI difficulty from the challenge rules
##       -> CharacterSelect (limited to challenger_squad_size)
##       -> GameWorld battle (defenders are the map's player-1+ AI spawns)
##       -> result captured off GameEvents.player_eliminated -> results.json
##
## WHY a .tres (not the raw JSON): the shipped battle flow only loads maps through
## GameWorldManager -> MapLoader.load_map_from_file, which resolves a resource PATH via
## ResourceLoader. Those two files are read-only for this work, and custom JSON maps have
## no in-battle load route today. So begin() takes the challenge's UNTRUSTED map JSON,
## runs it through the hardened, catalog-strict [method ChallengeCodec.map_resource_from_challenge]
## (== MapResource.import_from_json) to get a VALIDATED in-memory resource, then serialises
## THAT trusted resource to a local user:// .tres keyed by the challenge checksum and points
## GameSettings.selected_map at it. No untrusted bytes are ever fed to ResourceLoader.
##
## RESULT CAPTURE without a GameWorldManager edit: this node listens to
## GameEvents.player_eliminated and re-derives win/loss from PlayerManager exactly the way
## GameWorldManager's own arena branch does (no enemy defender left -> win; no challenger
## unit left -> loss). It is gated on an active run AND on GameSettings still pointing at
## THIS run's map, so an elimination in a later normal match can never record a stray result.

## Where the run's materialised map + the results file live.
const ACTIVE_MAP_DIR := "user://challenges/active/"
const RESULTS_PATH := "user://challenges/results.json"

const CHARACTER_SELECT_SCENE := "res://menus/CharacterSelect.tscn"
const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"

## The challenge staged for the squad pick (read by CharacterSelect). Empty when none.
var _pending: Dictionary = {}

## The challenge whose battle is currently live, plus the map path we staged for it. The
## path is the guard that stops a later match's eliminations from recording here.
var _active: Dictionary = {}
var _active_map_path: String = ""

## Set once per battle so repeated elimination signals record a single result.
var _result_recorded: bool = false

## Challenger turns taken this battle (fed to the personal-best record).
var _turns: int = 0


func _ready() -> void:
	name = "ChallengeController"
	# Survive the pause the GameOverScreen applies, and outlive every scene change.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Result capture rides the SAME elimination signal GameWorldManager trusts. PlayerManager
	# emits the reliable one; GameEvents.player_eliminated is a fallback that does not always
	# fire (see GameWorldManager._connect_end_signals). Connecting BOTH is safe because
	# _on_player_eliminated is idempotent per battle (_result_recorded).
	if PlayerManager != null:
		if PlayerManager.has_signal("player_eliminated"):
			PlayerManager.player_eliminated.connect(_on_player_eliminated)
		# Turn tally: connect ONE source only (PlayerManager, the reliable one) so turns are
		# not double-counted.
		if PlayerManager.has_signal("player_turn_started"):
			PlayerManager.player_turn_started.connect(_on_player_turn_started)
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null and GameEvents.has_signal("player_eliminated"):
		GameEvents.player_eliminated.connect(_on_player_eliminated)


# --- Staging (browse -> squad pick) -----------------------------------------

## Stage [param challenge] for play without starting yet (mirrors ArenaController.prepare_run).
func prepare(challenge: Dictionary) -> void:
	_pending = challenge.duplicate(true)


## True while a challenge is staged and waiting for its squad pick. CharacterSelect reads
## this to know it should limit the pick to the challenger squad size and, on confirm, run
## the normal map -> GameWorld path (the map is already staged in GameSettings).
func has_pending_challenge() -> bool:
	return not _pending.is_empty()


## Squad-pick limit for the staged challenge (the author's challenger_squad_size), or 0.
func pending_squad_size() -> int:
	if _pending.is_empty():
		return 0
	var rules: Dictionary = _pending.get("rules", {})
	return maxi(1, int(rules.get("challenger_squad_size", 4)))


## Display name of the staged challenge (for the Character Select header).
func pending_name() -> String:
	if _pending.is_empty():
		return "Challenge"
	return String(_pending.get("name", "Challenge"))


## Materialise the staged challenge and route to the squad pick. Returns false (staying put)
## if the map cannot be validated/materialised, so the caller can surface an error. On
## success this configures GameSettings for the run and changes scene to Character Select.
func begin() -> bool:
	if _pending.is_empty():
		return false
	var challenge: Dictionary = _pending

	# Defensive: drop any Arena run staged earlier so CharacterSelect's confirm can never
	# mistake this challenge launch for a pending Arena run.
	var arena := get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run() \
			and arena.has_method("abort_run"):
		arena.abort_run()

	# UNTRUSTED map JSON -> hardened import -> VALIDATED in-memory resource. Null => reject.
	var map_resource: MapResource = ChallengeCodec.map_resource_from_challenge(challenge)
	if map_resource == null:
		push_error("ChallengeController.begin: map failed validation; refusing to start.")
		return false

	var map_path: String = _write_active_map(map_resource, ChallengeCodec.challenge_id(challenge))
	if map_path.is_empty():
		push_error("ChallengeController.begin: could not write the run's map.")
		return false

	var rules: Dictionary = challenge.get("rules", {})
	if GameSettings != null:
		GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
		if GameSettings.has_method("set_turn_system"):
			GameSettings.set_turn_system(int(rules.get("turn_system", 0)))
		if GameSettings.has_method("set_ai_difficulty"):
			GameSettings.set_ai_difficulty(int(rules.get("ai_difficulty", 1)))
		if GameSettings.has_method("clear_selected_squad"):
			GameSettings.clear_selected_squad()
		# Register one player per team the map uses (challenger + every defender slot), so
		# single-player setup marks all defender teams as AI. Clamped to the engine's 2..4.
		if GameSettings.has_method("set_player_count"):
			GameSettings.set_player_count(_team_count(map_resource))
		GameSettings.set_selected_map(map_path)

	# Arm result capture for this run. The squad pick and battle happen on the map we just
	# staged; player_eliminated during them records against THIS challenge (guarded by path).
	_active = challenge
	_active_map_path = map_path
	_result_recorded = false
	_turns = 0

	get_tree().change_scene_to_file(CHARACTER_SELECT_SCENE)
	return true


## Called by CharacterSelect when the challenger confirms their squad and heads into
## battle. Clears the staging slot (the pick is done) while KEEPING the run armed for
## result capture, so a later Arena / Skirmish launch is never misread as this challenge.
func notify_squad_confirmed() -> void:
	_pending = {}


## Abandon the staged/active run (Character Select "Back", or bailing out). Clears the
## capture arming so nothing records after the user walks away.
func cancel() -> void:
	_pending = {}
	_active = {}
	_active_map_path = ""
	_result_recorded = false
	_turns = 0


# --- Battle result capture --------------------------------------------------

func _on_player_turn_started(player) -> void:
	if not _is_capturing():
		return
	# Count challenger (human, non-neutral) turns as the run's turn tally.
	if player != null and not _player_is_ai(player) and not _player_is_neutral(player):
		_turns += 1


func _on_player_eliminated(_player) -> void:
	if not _is_capturing():
		return
	if _result_recorded:
		return

	var human_alive: bool = false
	var enemy_alive: bool = false
	if PlayerManager != null:
		for ap in PlayerManager.players:
			if ap == null or not ap.has_units_remaining():
				continue
			if _player_is_neutral(ap):
				continue  # neutral camps never decide a challenge
			if _player_is_ai(ap):
				enemy_alive = true
			else:
				human_alive = true

	if not enemy_alive:
		_record_result(true)
	elif not human_alive:
		_record_result(false)


## True while a challenge battle is live AND GameSettings still points at its map. The path
## check is the guard that prevents a later, unrelated match from recording a stray result.
func _is_capturing() -> bool:
	if _active.is_empty() or _active_map_path.is_empty():
		return false
	if GameSettings == null:
		return false
	return String(GameSettings.selected_map_path) == _active_map_path


func _player_is_ai(player) -> bool:
	return "is_ai" in player and bool(player.is_ai)


func _player_is_neutral(player) -> bool:
	return "is_neutral" in player and bool(player.is_neutral)


## Upsert this battle's outcome into results.json, keeping the best (fewest-turn) win as the
## personal best. Idempotent per battle via [member _result_recorded].
func _record_result(won: bool) -> void:
	_result_recorded = true
	var id: String = ChallengeCodec.challenge_id(_active)
	if id.is_empty():
		return

	var results: Dictionary = load_results()
	var prev: Dictionary = results.get(id, {})

	var best_turns: int = int(prev.get("best_turns", -1))
	if won and (best_turns < 0 or _turns < best_turns):
		best_turns = _turns

	results[id] = {
		"challenge_id": id,
		"won": bool(prev.get("won", false)) or won,
		"best_turns": best_turns,
		"last_won": won,
		"last_turns": _turns,
		"plays": int(prev.get("plays", 0)) + 1,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	_save_results(results)


# --- Results file -----------------------------------------------------------

## The whole results map ({ challenge_id: record }), or {} when there is no file yet.
func load_results() -> Dictionary:
	if not FileAccess.file_exists(RESULTS_PATH):
		return {}
	var file: FileAccess = FileAccess.open(RESULTS_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


## The stored record for one challenge id, or {} if it has never been played.
func result_for(challenge_id: String) -> Dictionary:
	var rec: Variant = load_results().get(challenge_id, {})
	return rec if rec is Dictionary else {}


func _save_results(results: Dictionary) -> void:
	ChallengeCodec._ensure_dir()
	var file: FileAccess = FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify(results, "\t"))
	file.close()


# --- Map materialisation ----------------------------------------------------

## Number of teams a map uses = highest player_id + 1 across its spawns, so the challenger
## and every distinct defender slot each get a registered player. Clamped to the engine's
## supported 2..4 player band (GameSettings.set_player_count enforces the same).
func _team_count(map_resource: MapResource) -> int:
	var max_pid: int = 1
	for spawn in map_resource.unit_spawns:
		if spawn is Dictionary:
			max_pid = maxi(max_pid, int(spawn.get("player_id", 0)))
	return clampi(max_pid + 1, 2, 4)


## Serialise the VALIDATED map resource to a local .tres keyed by the challenge checksum,
## so GameWorldManager's existing ResourceLoader-based map load can field it. Returns the
## path, or "" on failure. Keyed by checksum so replays reuse one file and distinct
## challenges never collide in the resource cache.
func _write_active_map(map_resource: MapResource, checksum: String) -> String:
	if not DirAccess.dir_exists_absolute(ACTIVE_MAP_DIR):
		DirAccess.make_dir_recursive_absolute(ACTIVE_MAP_DIR)
	var stem: String = checksum if not checksum.is_empty() else "current"
	var path: String = ACTIVE_MAP_DIR + stem + ".tres"
	var err: int = ResourceSaver.save(map_resource, path)
	if err != OK:
		return ""
	return path
