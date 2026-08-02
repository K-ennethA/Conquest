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
##
## WHICH SIGNAL ENDS WHAT (all three feed the ONE idempotent [method _record_result]):
##   * player_eliminated  -- ends a BREACH run either way, and ends a SURVIVE run EARLY on a
##                           clear. No non-neutral AI player left standing => WIN; no human
##                           player left => LOSS. Emitted by PlayerManager (reliable) and
##                           mirrored on GameEvents (a fallback that does not always fire),
##                           so both are connected and the recorder de-dupes.
##   * turn_started       -- from the ACTIVE TURN SYSTEM (not PlayerManager). Counts the
##                           challenger's turns, which is the score's "turns" AND the survive
##                           mode's round counter; reaching rules.survive_turns ends a SURVIVE
##                           run as a WIN. See [method _on_turn_started] for why this bus.
##   * unit_eliminated    -- never ends anything; it only tallies units_lost for the score.
## Whichever fires FIRST wins: _record_result latches (_result_recorded), so a survive latch
## can never be flipped to a loss by a later wipe, and vice versa.

## Where the run's materialised map + the results file live.
const ACTIVE_MAP_DIR := "user://challenges/active/"
## Default on-disk location of the local results file. Redirect it with
## [method set_results_path] rather than writing the player's real file -- see
## tests/README.md ("Temp paths, or a path-injection API").
const RESULTS_PATH := "user://challenges/results.json"

## Where results are actually read from / written to. Swappable for tests.
var _results_path: String = RESULTS_PATH

const CHARACTER_SELECT_SCENE := "res://menus/CharacterSelect.tscn"
const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"

## The player slot the CHALLENGER always occupies (the defense is every slot 1+). Shared by
## the turn tally and the units-lost tally so the two can never disagree about whose side is
## whose.
const CHALLENGER_PLAYER_ID := 0

## The challenge staged for the squad pick (read by CharacterSelect). Empty when none.
var _pending: Dictionary = {}

## The challenge whose battle is currently live, plus the map path we staged for it. The
## path is the guard that stops a later match's eliminations from recording here.
var _active: Dictionary = {}
var _active_map_path: String = ""

## Set once per battle so repeated elimination signals record a single result.
var _result_recorded: bool = false

## Challenger turns taken this battle (fed to the personal-best record). In "survive" mode
## this doubles as the ROUND COUNT: each challenger turn start is one round survived.
var _turns: int = 0

## How many of the CHALLENGER's own units (player 0) fell during the armed run. Counted off
## GameEvents.unit_eliminated and fed to the score (each loss costs points; zero == perfect).
var _units_lost: int = 0

## The turn system we are currently listening to for turn_started, re-wired whenever the
## active system changes (see [method _on_turn_system_activated]).
var _watched_turn_system: TurnSystemBase = null


func _ready() -> void:
	name = "ChallengeController"
	# Survive the pause the GameOverScreen applies, and outlive every scene change.
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Result capture rides the SAME elimination signal GameWorldManager trusts. PlayerManager
	# emits the reliable one; GameEvents.player_eliminated is a fallback that does not always
	# fire (see GameWorldManager._connect_end_signals). Connecting BOTH is safe because
	# _on_player_eliminated is idempotent per battle (_result_recorded).
	if PlayerManager != null and PlayerManager.has_signal("player_eliminated"):
		PlayerManager.player_eliminated.connect(_on_player_eliminated)

	# TURN TALLY / SURVIVE ROUNDS ride the ACTIVE TURN SYSTEM's turn_started, which is the
	# only per-turn signal that fires on EVERY turn. PlayerManager.player_turn_started fires
	# just at game start and off the human End-Turn button, so a run driven by the real turn
	# system would under-count turns (inflating the score) and a survive run would never
	# reach its round target at all. Mirrors HazardManager / TurnIndicator wiring: subscribe
	# to activation and re-wire on every switch, since the system instance is per-battle.
	if TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_on_turn_system_activated(TurnSystemManager.get_active_turn_system())

	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null and GameEvents.has_signal("player_eliminated"):
		GameEvents.player_eliminated.connect(_on_player_eliminated)
		# Per-UNIT deaths drive the units-lost tally (scoring). GameEvents is the one bus that
		# carries a per-unit signal; PlayerManager only fires when a whole player is wiped.
		if GameEvents.has_signal("unit_eliminated"):
			GameEvents.unit_eliminated.connect(_on_unit_eliminated)


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
	_units_lost = 0

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
	_units_lost = 0


# --- Mid-battle save / resume + the end-of-day forfeit ----------------------
#
# A challenge attempt is a DAILY commitment: you may put it down and pick it up later the
# same UTC day, but a paused attempt does not survive the date rolling over. That rule is
# enforced from two places -- the main-menu banner (so an expired save never even offers a
# Resume button) and the resume itself (so a session that sat open across midnight cannot
# sneak back in) -- and BOTH funnel into [method forfeit_expired_attempt], which records the
# attempt as a loss through the SAME [method _record_result] path a real defeat uses.
#
# Skirmish and campaign saves have no such rule; only a challenge expires.

## True while a challenge battle is live and its results would be recorded. Public face of
## the internal capture gate, so the save layer can tell "this is a challenge battle" from
## "this is a skirmish that happens to be running a user:// map".
func is_capturing() -> bool:
	return _is_capturing()


## The challenge dict of the live run ({} when none). Written into the battle snapshot so a
## resume can re-validate the map through the codec rather than trusting a stale .tres.
func active_challenge() -> Dictionary:
	return _active.duplicate(true)


## The live run's score counters, so a resume continues the same attempt instead of
## restarting the tally.
func capture_counters() -> Dictionary:
	return { "turns": _turns, "units_lost": _units_lost }


## Re-stage [param challenge] for a RESUMED battle and re-arm result capture at
## [param turns] / [param units_lost]. Returns the staged map path, or "" when the stored
## challenge no longer validates (a corrupt or tampered save -- the caller then discards it).
##
## Deliberately mirrors [method begin] minus the parts a resume must not repeat: it does NOT
## clear the selected squad (the snapshot fields the board itself) and it does NOT change
## scene (the caller goes straight to the battle). The map still goes through the hardened
## [method ChallengeCodec.map_resource_from_challenge], so a resume is exactly as strict about
## untrusted map data as the original launch was.
func resume_from_snapshot(challenge: Dictionary, turns: int, units_lost: int) -> String:
	if challenge.is_empty():
		return ""
	var map_resource: MapResource = ChallengeCodec.map_resource_from_challenge(challenge)
	if map_resource == null:
		return ""
	var map_path: String = _write_active_map(map_resource, ChallengeCodec.challenge_id(challenge))
	if map_path.is_empty():
		return ""

	var rules: Dictionary = challenge.get("rules", {})
	if GameSettings != null:
		GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
		if GameSettings.has_method("set_turn_system"):
			GameSettings.set_turn_system(int(rules.get("turn_system", 0)))
		if GameSettings.has_method("set_ai_difficulty"):
			GameSettings.set_ai_difficulty(int(rules.get("ai_difficulty", 1)))
		if GameSettings.has_method("set_player_count"):
			GameSettings.set_player_count(_team_count(map_resource))
		GameSettings.set_selected_map(map_path)

	_pending = {}
	_active = challenge.duplicate(true)
	_active_map_path = map_path
	_result_recorded = false
	_turns = maxi(0, turns)
	_units_lost = maxi(0, units_lost)
	return map_path


## FORFEIT a paused attempt whose UTC day has rolled over: record it as a played-and-lost
## attempt (attempts + 1, no clear) through the ordinary results path, then disarm.
##
## Reuses [method _record_result] rather than writing the record by hand, so the forfeit is
## scored, keyed and rolled up exactly like any other loss -- there is one definition of "an
## attempt was made" and this is it. Returns false when the challenge carries no id.
func forfeit_expired_attempt(challenge: Dictionary, turns: int, units_lost: int) -> bool:
	if challenge.is_empty() or ChallengeCodec.challenge_id(challenge).is_empty():
		return false
	_active = challenge.duplicate(true)
	_result_recorded = false
	_turns = maxi(0, turns)
	_units_lost = maxi(0, units_lost)
	_record_result(false)
	# Disarm: the attempt is over, and nothing that happens later belongs to it.
	_active = {}
	_active_map_path = ""
	_turns = 0
	_units_lost = 0
	return true


# --- Battle result capture --------------------------------------------------

## (Re)wire to the ACTIVE turn system's turn_started when one activates or the system is
## switched. The previous system is disconnected first so a switch mid-session can never
## leave two live subscriptions double-counting turns.
func _on_turn_system_activated(turn_system: TurnSystemBase) -> void:
	if _watched_turn_system == turn_system:
		return
	if _watched_turn_system != null and is_instance_valid(_watched_turn_system) \
			and _watched_turn_system.turn_started.is_connected(_on_turn_started):
		_watched_turn_system.turn_started.disconnect(_on_turn_started)
	_watched_turn_system = turn_system
	if turn_system != null and not turn_system.turn_started.is_connected(_on_turn_started):
		turn_system.turn_started.connect(_on_turn_started)


## One more turn taken by the CHALLENGER. Defender turns are ignored, so the tally is the
## challenger's own turn count (what par is measured against) and, in survive mode, the
## number of rounds they have outlasted.
func _on_turn_started(player: Player) -> void:
	if not _is_capturing():
		return
	if not _player_is_challenger(player):
		return
	_turns += 1
	_maybe_latch_survive_win()


## SURVIVE mode outcome. A "round survived" is measured at the challenger's own turn
## boundaries (each of their turn starts == one more round they have outlasted), which are
## the SAME turn signals the breach-mode tally rides -- no turn-system code is touched. When
## the tally reaches the author's survive_turns and the challenger is still standing (they
## are, since their turn just started), we LATCH a win: _record_result is idempotent
## (_result_recorded), so a later elimination can never flip this to a loss. The battle
## itself keeps running until the map's own win/lose objective ends it -- capture only
## INTERPRETS the outcome. (Clearing the defense early is also a win, handled in
## _on_player_eliminated the same as breach mode, so survive needs no special-case there.)
func _maybe_latch_survive_win() -> void:
	if _result_recorded:
		return
	if ChallengeCodec.rules_mode(_active) != ChallengeCodec.MODE_SURVIVE:
		return
	if _turns >= ChallengeCodec.rules_survive_turns(_active):
		_record_result(true)


## Tally a CHALLENGER unit (player 0) death for the score. Guarded on an active run so a
## death in a later, unrelated match never counts here. Deliberately does NOT decide the
## outcome (that stays with the player/elimination logic) -- it only feeds units_lost.
func _on_unit_eliminated(unit, _eliminator) -> void:
	if not _is_capturing():
		return
	if unit != null and _unit_is_challenger(unit):
		_units_lost += 1


## True when [param unit] is owned by the challenger. Reads through the unit's owner Player
## when available, tolerating either the get_owner_player() accessor or a bare owner_player
## field so a minor Unit API drift can't break capture.
func _unit_is_challenger(unit) -> bool:
	var owner = null
	if unit.has_method("get_owner_player"):
		owner = unit.get_owner_player()
	elif "owner_player" in unit:
		owner = unit.owner_player
	return _player_is_challenger(owner)


## True when [param player] is the challenger's slot. Identity is the SLOT, not the is_ai
## flag: the challenger is by construction player 0 (every defender lives on slot 1+), and a
## slot check also shrugs off a turn signal that hands us something other than a Player.
func _player_is_challenger(player) -> bool:
	return player != null and "player_id" in player and int(player.player_id) == CHALLENGER_PLAYER_ID


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


## Upsert this battle's outcome into results.json. Keeps the best (highest-SCORE) win as the
## personal best and rolls up the local defense-rating tallies. Idempotent per battle via
## [member _result_recorded].
func _record_result(won: bool) -> void:
	_result_recorded = true
	var id: String = ChallengeCodec.challenge_id(_active)
	if id.is_empty():
		return

	var results: Dictionary = load_results()
	var prev: Dictionary = results.get(id, {})

	# Score this run (pure formula). Par comes from the challenge; survive/breach share it.
	var par: int = ChallengeCodec.rules_par_turns(_active)
	var mode: String = ChallengeCodec.rules_mode(_active)
	var scoring: Dictionary = ChallengeScoring.evaluate(won, _turns, par, _units_lost)
	var score: int = int(scoring.get("score", 0))
	var perfect: bool = bool(scoring.get("perfect", false))

	# Best-of by SCORE (a win always outscores a loss's 0). best_turns is kept alongside for
	# the "cleared in N" line; it only updates when THIS run is the new best score.
	var best_score: int = int(prev.get("best_score", 0))
	var best_turns: int = int(prev.get("best_turns", -1))
	var best_perfect: bool = bool(prev.get("best_perfect", false))
	if won and score > best_score:
		best_score = score
		best_turns = _turns
		best_perfect = perfect

	# Local defense rating: attempts = every recorded play, clears = every challenger win.
	# This is a LOCAL-ONLY placeholder -- it only ever sees THIS install's plays. True
	# cross-player "how often does this defense hold" aggregation arrives with the community
	# service; until then the browse screen labels it as your own local attempts.
	var attempts: int = int(prev.get("attempts", 0)) + 1
	var clears: int = int(prev.get("clears", 0)) + (1 if won else 0)

	results[id] = {
		"challenge_id": id,
		"won": bool(prev.get("won", false)) or won,
		"best_score": best_score,
		"best_turns": best_turns,
		"best_perfect": best_perfect,
		"mode": mode,
		"last_won": won,
		"last_turns": _turns,
		"last_score": score,
		"last_units_lost": _units_lost,
		"last_perfect": perfect,
		"attempts": attempts,
		"clears": clears,
		"plays": int(prev.get("plays", 0)) + 1,
		"timestamp": Time.get_datetime_string_from_system(),
	}
	_save_results(results)


# --- Results file -----------------------------------------------------------

## Redirect the results file. FOR TESTS ONLY -- point it at a `user://test_*` path in
## `before_all` and restore [constant RESULTS_PATH] in `after_all`, or the suite edits the
## player's real record. Empty restores the default.
func set_results_path(path: String) -> void:
	_results_path = path if not path.is_empty() else RESULTS_PATH


func get_results_path() -> String:
	return _results_path


## The whole results map ({ challenge_id: record }), or {} when there is no file yet.
func load_results() -> Dictionary:
	if not FileAccess.file_exists(_results_path):
		return {}
	var file: FileAccess = FileAccess.open(_results_path, FileAccess.READ)
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
	var dir: String = _results_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(_results_path, FileAccess.WRITE)
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
