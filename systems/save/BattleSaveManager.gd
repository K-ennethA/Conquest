extends Node
class_name BattleSaveManager

## Mid-battle SAVE & RESUME for the solo modes: put a battle down, quit to the menu, pick it
## up later exactly where you left it.
##
## ONE SLOT, ONE FILE. [constant DEFAULT_SAVE_PATH] holds a single [BattleSnapshot] (see that
## script for the format). There is no autosave and no save-on-quit: closing the app without
## pressing Save & Quit simply loses the battle, which is the honest reading of "quit" and
## keeps the file from ever being written behind the player's back. The save is SINGLE-USE --
## it is deleted the moment a resume consumes it, so a battle can never be re-farmed from one
## snapshot.
##
## TWO SURFACES, DELIBERATELY.
##   * A NODE, discoverable through group [constant GROUP], mounted per battle by
##     [GameWorldManager]. This is the pause menu's contract: [method can_save_now] and
##     [method save_and_quit], both null-safe to call at any time.
##   * STATIC functions for everything OUTSIDE a battle -- the main-menu banner (peek /
##     describe / stage) and the restore itself. Statics are process-wide, so the staged
##     snapshot survives the scene change from the menu into the battle without an autoload.
##
## WHAT IS EXCLUDED, AND WHY.
##   * NETWORKED matches -- the battle is not this peer's to pause.
##   * VERSUS / hot-seat -- "resume" means resuming YOUR battle; a shared-screen match has no
##     single owner to hand it back to.
##   * ARENA runs -- a run's real state (squad, augments, currency, life) lives in
##     [ArenaController], not on the board. Saving only the board would resume a round into an
##     empty run. Excluded at the gate rather than half-serialised.
##
## THE CHALLENGE END-OF-DAY RULE. A challenge attempt is a daily commitment: a paused attempt
## expires when the UTC date rolls over, and expiring FORFEITS it (recorded as a played,
## un-cleared attempt through [method ChallengeController.forfeit_expired_attempt]). Checked
## twice -- when the menu builds the banner, and again at resume -- so neither a stale banner
## nor a session left open across midnight can slip through. Skirmish and campaign saves never
## expire.
##
## THE RESTORE ORDER is the load-bearing part; it is documented at
## [method restore_units] and, for the reasoning, in [BattleSnapshot]'s class docs.

## Group the pause menu resolves this node through:
## [code]get_tree().get_first_node_in_group(&"battle_save_manager")[/code].
const GROUP: StringName = &"battle_save_manager"

## Default on-disk location of the one save slot. Redirect with [method set_save_path] in
## tests -- see tests/README.md ("Temp paths, or a path-injection API").
const DEFAULT_SAVE_PATH := "user://saves/battle.json"

const MAIN_MENU_SCENE := "res://menus/MainMenu.tscn"
const GAME_WORLD_SCENE := "res://game/world/GameWorld.tscn"

## The shared board grid -- the SAME resource [CombatServices] builds its adapter against, so
## sweeping it for runtime tile effects covers exactly the cells the loaded map has.
const GRID: Grid = preload("res://board/Grid.tres")

## Where the slot is actually read from / written to.
static var _save_path: String = DEFAULT_SAVE_PATH

## The snapshot staged by [method stage_resume], consumed by [GameWorldManager] on the next
## battle load. Static so it survives the menu -> battle scene change; empty when no resume
## is in flight.
static var _pending: Dictionary = {}


# --- Path injection ---------------------------------------------------------

static func set_save_path(path: String) -> void:
	_save_path = path if not path.is_empty() else DEFAULT_SAVE_PATH


static func get_save_path() -> String:
	return _save_path


# --- File layer -------------------------------------------------------------

static func has_save() -> bool:
	return FileAccess.file_exists(_save_path)


## Read the slot WITHOUT consuming it. Returns {} when there is no file, it is unreadable, or
## it is not a snapshot this build supports -- every caller treats {} as "nothing to resume".
static func peek_save() -> Dictionary:
	if not FileAccess.file_exists(_save_path):
		return {}
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.READ)
	if file == null:
		return {}
	var text: String = file.get_as_text()
	file.close()
	var snapshot: Dictionary = BattleSnapshot.from_json(text)
	if not BattleSnapshot.is_supported(snapshot):
		return {}
	return snapshot


static func delete_save() -> void:
	if FileAccess.file_exists(_save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(_save_path))


## Write [param snapshot] to the slot, creating the directory as needed. Returns success as a
## VALUE -- a failed write is a foreseeable condition (a full or read-only disk), so it is
## reported to the caller rather than to the engine log.
static func write_save(snapshot: Dictionary) -> bool:
	if snapshot.is_empty():
		return false
	var dir: String = _save_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var file: FileAccess = FileAccess.open(_save_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(BattleSnapshot.to_json(snapshot))
	file.close()
	return true


# --- The end-of-day rule ----------------------------------------------------

## Today's UTC date ("YYYY-MM-DD"). UTC, not local: a daily challenge must roll over at the
## same instant for everyone.
static func today_utc() -> String:
	return Time.get_date_string_from_system(true)


## True when [param snapshot] is a CHALLENGE attempt saved on a different UTC day. Skirmish
## and campaign saves are never expired, however old they are.
static func is_expired(snapshot: Dictionary, today: String) -> bool:
	if snapshot.is_empty():
		return false
	var context: Dictionary = snapshot.get("context", {})
	if String(context.get("mode", "")) != BattleSnapshot.MODE_CHALLENGE:
		return false
	return String(snapshot.get("saved_at_utc_date", "")) != today


## If [param snapshot] has expired, FORFEIT it (record the attempt as played-and-lost) and
## delete the slot. Returns true when it expired -- i.e. "there is nothing to resume".
static func expire_if_needed(snapshot: Dictionary, today: String) -> bool:
	if not is_expired(snapshot, today):
		return false
	var context: Dictionary = snapshot.get("context", {})
	var challenge: Variant = context.get("challenge", {})
	var controller = _challenge_controller()
	if controller != null and controller.has_method("forfeit_expired_attempt") and challenge is Dictionary:
		controller.forfeit_expired_attempt(
			challenge as Dictionary,
			int(context.get("challenge_turns", 0)),
			int(context.get("challenge_units_lost", 0)))
	delete_save()
	_pending = {}
	return true


# --- Resume staging (main menu) ---------------------------------------------

## One-line description for the resume banner ("SKIRMISH — Proving Grounds · saved 2026-08-02").
static func describe(snapshot: Dictionary) -> String:
	if snapshot.is_empty():
		return ""
	var context: Dictionary = snapshot.get("context", {})
	var mode: String = String(context.get("mode", BattleSnapshot.MODE_SKIRMISH))
	var label: String = String(context.get("map_name", ""))
	if label.is_empty():
		label = String(context.get("map_path", "")).get_file().get_basename()
	var when: String = String(snapshot.get("saved_at_utc_date", ""))
	return "%s — %s · saved %s" % [mode.to_upper(), label, when]


## True while a resume has been staged and the next battle load should restore it.
static func has_pending_resume() -> bool:
	return not _pending.is_empty()


## Consume the staged resume (single-use): returns it and clears BOTH the staging slot and the
## file, so a crash part-way through a restore can never loop back into the same save.
static func take_pending_resume() -> Dictionary:
	var snapshot: Dictionary = _pending
	_pending = {}
	delete_save()
	return snapshot


## Point every mode-context setter at [param snapshot] and stage it for the next battle load.
## Returns false (having deleted an unusable save) when the stored context can no longer be
## re-established -- an expired challenge, a challenge whose map no longer validates, a
## campaign chapter that no longer exists.
static func stage_resume(snapshot: Dictionary, today: String) -> bool:
	if not BattleSnapshot.is_supported(snapshot):
		delete_save()
		return false
	if expire_if_needed(snapshot, today):
		return false

	var context: Dictionary = snapshot.get("context", {})
	var mode: String = String(context.get("mode", BattleSnapshot.MODE_SKIRMISH))
	var map_path: String = String(context.get("map_path", ""))

	# Any run staged earlier (an Arena ruleset waiting on a squad pick) must not survive into
	# the resumed battle, or a later confirm would launch it instead.
	var arena = _node("/root/ArenaController")
	if arena != null and arena.has_method("has_pending_run") and arena.has_pending_run() \
			and arena.has_method("abort_run"):
		arena.abort_run()

	match mode:
		BattleSnapshot.MODE_CHALLENGE:
			var controller = _challenge_controller()
			var challenge: Variant = context.get("challenge", {})
			if controller == null or not controller.has_method("resume_from_snapshot") \
					or not (challenge is Dictionary):
				delete_save()
				return false
			# Re-validates the stored map through the hardened codec -- a resume is exactly as
			# strict about untrusted map data as the original launch.
			map_path = String(controller.resume_from_snapshot(
				challenge as Dictionary,
				int(context.get("challenge_turns", 0)),
				int(context.get("challenge_units_lost", 0))))
			if map_path.is_empty():
				delete_save()
				return false
		BattleSnapshot.MODE_CAMPAIGN:
			var campaign = _node("/root/CampaignController")
			var chapter: Dictionary = CampaignData.get_by_id(String(context.get("campaign_chapter_id", "")))
			if campaign == null or not campaign.has_method("arm_for_resume") or chapter.is_empty():
				delete_save()
				return false
			if not campaign.arm_for_resume(chapter, int(context.get("campaign_turns", 0))):
				delete_save()
				return false
			_stage_game_settings(context, map_path)
		_:
			_stage_game_settings(context, map_path)

	if map_path.is_empty():
		delete_save()
		return false

	_pending = snapshot
	return true


## The GameSettings staging every non-challenge mode shares. (The challenge path does its own
## inside [method ChallengeController.resume_from_snapshot], because the map path is only
## known once the codec has re-materialised it.)
static func _stage_game_settings(context: Dictionary, map_path: String) -> void:
	if GameSettings == null:
		return
	GameSettings.set_game_mode(GameSettings.GameMode.SINGLE_PLAYER)
	if GameSettings.has_method("set_turn_system"):
		GameSettings.set_turn_system(int(context.get("turn_system", 0)))
	if GameSettings.has_method("set_ai_difficulty"):
		GameSettings.set_ai_difficulty(int(context.get("difficulty", 1)))
	if GameSettings.has_method("set_player_count"):
		GameSettings.set_player_count(maxi(2, int(context.get("player_count", 2))))
	var squad: Variant = context.get("squad", [])
	if squad is Array and GameSettings.has_method("set_selected_squad"):
		# Only a fallback: the restore replaces every unit on the board anyway. Setting it
		# means a restore that somehow spawns nothing still fields the player's own squad
		# rather than the map's authored roster.
		GameSettings.set_selected_squad(squad as Array)
	GameSettings.set_selected_map(map_path)


# --- The pause menu contract ------------------------------------------------

func _ready() -> void:
	add_to_group(GROUP)


## True when the CURRENT battle may be saved: a solo battle actually in progress, not
## networked, not an Arena round, with a live board and at least one unit still standing on
## the player's side. Null-safe end to end -- every autoload is probed defensively so this can
## be called from a menu that is up before (or after) a battle exists.
func can_save_now() -> bool:
	return BattleSaveManager.gate(
		GameSettings != null and GameSettings.game_mode == GameSettings.GameMode.SINGLE_PLAYER,
		_is_networked(),
		_is_arena_active(),
		PlayerManager != null and PlayerManager.current_game_state == PlayerManager.GameState.IN_PROGRESS,
		TurnSystemManager != null and TurnSystemManager.has_active_turn_system(),
		_has_living_player_unit())


## The PURE decision behind [method can_save_now], split out so the gate can be tested
## exhaustively without standing up a networked session or an Arena run. Every condition is
## necessary; the interesting ones are the two exclusions documented in the class header
## ([param networked] and [param arena_active]).
static func gate(solo: bool, networked: bool, arena_active: bool, in_progress: bool,
		has_turn_system: bool, has_player_unit: bool) -> bool:
	if not solo:
		return false
	if networked or arena_active:
		return false
	return in_progress and has_turn_system and has_player_unit


func _is_networked() -> bool:
	return typeof(NetSession) == TYPE_OBJECT and NetSession != null \
		and NetSession.has_method("is_networked_match") and NetSession.is_networked_match()


func _is_arena_active() -> bool:
	var arena = _node("/root/ArenaController")
	return arena != null and arena.has_method("is_active") and arena.is_active()


func _has_living_player_unit() -> bool:
	var board = CombatServices.board() if CombatServices != null else null
	if board == null or not board.has_method("all_units"):
		return false
	for unit in board.all_units():
		if _player_id_of(unit) == 0:
			return true
	return false


## Serialise the live battle, write it to the slot, and return to the main menu.
## Returns false (changing nothing) when the battle cannot be saved or the write fails.
func save_and_quit() -> bool:
	if not can_save_now():
		return false
	var snapshot: Dictionary = capture(BattleSaveManager.today_utc())
	if snapshot.is_empty():
		return false
	if not BattleSaveManager.write_save(snapshot):
		return false
	var tree: SceneTree = get_tree()
	if tree == null:
		return false
	tree.paused = false
	tree.change_scene_to_file(MAIN_MENU_SCENE)
	return true


# --- Capture ----------------------------------------------------------------

## Build the snapshot for the live battle. [param today] is the UTC date, passed in by the
## call site (project convention) so a test can pin it.
func capture(today: String) -> Dictionary:
	var board = CombatServices.board() if CombatServices != null else null
	if board == null:
		return {}

	var units: Array = []
	var entries: Array = []
	for unit in board.all_units():
		if unit == null or not is_instance_valid(unit):
			continue
		if BattleSnapshot.character_id_of(unit).is_empty():
			continue  # a legacy scene-authored unit cannot be re-spawned from an id
		var index: int = entries.size()
		entries.append(BattleSnapshot.capture_unit(unit, index, board.cell_of(unit), _player_id_of(unit)))
		units.append(unit)
	if entries.is_empty():
		return {}

	var index_of := func(u) -> int:
		var i: int = units.find(u)
		return i

	return {
		"format_version": BattleSnapshot.FORMAT_VERSION,
		"saved_at_utc_date": today,
		"saved_at_utc": Time.get_datetime_string_from_system(true),
		"context": _capture_context(),
		"units": entries,
		"turn": _capture_turn_state(units),
		"board": _capture_board(index_of),
	}


## Mode + every setting the resumed battle has to be re-staged with.
func _capture_context() -> Dictionary:
	var context: Dictionary = {
		"mode": BattleSnapshot.MODE_SKIRMISH,
		"map_path": String(GameSettings.selected_map_path) if GameSettings != null else "",
		"map_name": _current_map_name(),
		"campaign_chapter_id": "",
		"campaign_turns": 0,
		"challenge_id": "",
		"challenge": {},
		"challenge_turns": 0,
		"challenge_units_lost": 0,
		"squad": (GameSettings.get_selected_squad() if GameSettings != null else []),
		"turn_system": int(GameSettings.selected_turn_system) if GameSettings != null else 0,
		"player_count": PlayerManager.players.size() if PlayerManager != null else 2,
		"difficulty": int(GameSettings.ai_difficulty) if GameSettings != null else 1,
	}

	# Mode is decided by WHICH controller is currently capturing this battle's result -- the
	# same gate that decides where the outcome is recorded, so the two can never disagree.
	var challenge = _challenge_controller()
	if challenge != null and challenge.has_method("is_capturing") and challenge.is_capturing():
		var dict: Dictionary = challenge.active_challenge()
		var counters: Dictionary = challenge.capture_counters()
		context["mode"] = BattleSnapshot.MODE_CHALLENGE
		context["challenge"] = dict
		context["challenge_id"] = ChallengeCodec.challenge_id(dict)
		context["challenge_turns"] = int(counters.get("turns", 0))
		context["challenge_units_lost"] = int(counters.get("units_lost", 0))
		return context

	var campaign = _node("/root/CampaignController")
	if campaign != null and campaign.has_method("is_capturing") and campaign.is_capturing():
		var chapter: Dictionary = campaign.active_chapter()
		context["mode"] = BattleSnapshot.MODE_CAMPAIGN
		context["campaign_chapter_id"] = String(chapter.get("id", ""))
		context["campaign_turns"] = int(campaign.captured_turns())
	return context


## Turn-order state for whichever system is driving the battle. Units are referred to by their
## index in [param units] (the snapshot's own numbering).
func _capture_turn_state(units: Array) -> Dictionary:
	var ts = TurnSystemManager.get_active_turn_system() if TurnSystemManager != null else null
	if ts == null:
		return {}
	if ts is SpeedFirstTurnSystem:
		var sf: SpeedFirstTurnSystem = ts
		return {
			"type": BattleSnapshot.TURN_SPEED_FIRST,
			"current_turn": sf.current_turn,
			"round_number": sf.round_number,
			"acting_index": units.find(sf.get_current_acting_unit()),
			"queue": _indices(sf.get_turn_queue(), units),
			"acted": _indices(sf.get_units_that_acted_this_round(), units),
		}
	var trad: TraditionalTurnSystem = ts as TraditionalTurnSystem
	if trad == null:
		return {}
	var had_turn: Array = []
	for player in trad.players_had_turn_this_round:
		if player != null:
			had_turn.append(int(player.player_id))
	return {
		"type": BattleSnapshot.TURN_TRADITIONAL,
		"current_turn": trad.current_turn,
		"round_number": trad.current_turn,
		"current_player_id": int(trad.current_player.player_id) if trad.current_player != null else 0,
		"acted": _indices(trad.get_units_that_acted(), units),
		"players_had_turn": had_turn,
	}


## Everything on the board that is neither terrain nor a unit: runtime tile effects plus the
## two per-battle schedulers' clocks.
func _capture_board(index_of: Callable) -> Dictionary:
	var out: Dictionary = { "applied_tile_effects": [], "spawn_manager": {}, "hazard_manager": {} }

	if CombatServices != null:
		var size: Vector3 = GRID.size if GRID != null else Vector3.ZERO
		for x in range(int(size.x)):
			for y in range(int(size.z)):
				var cell := Vector2i(x, y)
				var ids: Array = []
				for effect in CombatServices.applied_tile_effects_at(cell):
					if effect != null and not String(effect.id).is_empty():
						ids.append(String(effect.id))
				if not ids.is_empty():
					(out["applied_tile_effects"] as Array).append({
						"cell": BattleSnapshot.cell_to_array(cell), "ids": ids })

	var world = _game_world_manager()
	if world != null:
		var spawner = world.get_spawn_manager() if world.has_method("get_spawn_manager") else null
		if spawner != null and spawner.has_method("snapshot_state"):
			out["spawn_manager"] = spawner.snapshot_state()
		var hazards = world.get_hazard_manager() if world.has_method("get_hazard_manager") else null
		if hazards != null and hazards.has_method("snapshot_state"):
			out["hazard_manager"] = hazards.snapshot_state(index_of)
	return out


# --- Restore ----------------------------------------------------------------

## PHASE 1 of the resume, run by [GameWorldManager] straight after the map has loaded and
## BEFORE players are set up.
##
## The map has just placed its own authored units; they are freed and replaced with the
## snapshot's, spawned in snapshot-index order into the same Player{n+1} containers, so the
## ordinary [method PlayerManager.assign_units_by_parent] pass that runs moments later adopts
## them exactly as it would a normal load -- no bespoke ownership or turn registration here.
##
## THE PER-UNIT ORDER IS THE WHOLE TRICK (see [BattleSnapshot] for the reasoning):
##   1. spawn            -- stats rebuilt from the CharacterResource, i.e. BASE
##   2. core             -- AI behaviour, facing, action flags
##   3. items            -- [method ItemSystem.apply_loadout], which sets ItemSystem's own
##                          APPLIED_META latch, so its per-turn sweep later no-ops instead of
##                          stamping every permanent stat delta on a SECOND time
##   4. statuses         -- through add_status, so a [StatModifierStatus] re-installs its
##                          modifier exactly once on top of the base+items stats
##   5. move cooldowns
##   6. HP + shield LAST -- nothing above can overwrite them
##
## Returns the spawned units, positionally aligned with the snapshot's "units" array (a null
## entry marks a unit that could not be re-spawned).
static func restore_units(map_loader, snapshot: Dictionary) -> Array:
	var spawned: Array = []
	if map_loader == null or map_loader.map_root == null:
		return spawned

	_free_units_under(map_loader.map_root)

	var entries: Array = snapshot.get("units", [])
	var networked: bool = typeof(NetSession) == TYPE_OBJECT and NetSession != null \
			and NetSession.has_method("is_networked_match") and NetSession.is_networked_match()

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var character_id: String = String(entry.get("character_id", ""))
		if character_id.is_empty():
			spawned.append(null)
			continue
		var unit = map_loader.spawn_unit_now({
			"position": BattleSnapshot.array_to_cell(entry.get("cell", [])),
			"player_id": int(entry.get("player_id", 0)),
			"character_id": character_id,
			"spawn_kind": MapResource.SPAWN_KIND_START,
			"ai_stance": String(entry.get("ai_stance", "")),
			"aggro_range": int(entry.get("aggro_range", -1)),
			"leash_radius": int(entry.get("leash_radius", -1)),
		}, i)
		spawned.append(unit)

	for i in range(entries.size()):
		var restored = spawned[i]
		if restored == null or not is_instance_valid(restored):
			continue
		var data: Dictionary = entries[i]
		BattleSnapshot.apply_unit_core(restored, data)
		# Step 3: the saved HP/stats were captured WITH the loadout already stamped on, so it
		# has to be replayed here -- and going through the real applier is what latches
		# ItemSystem's APPLIED_META, which is what stops the turn-start sweep re-applying it.
		if int(data.get("player_id", 0)) == 0 and not networked:
			ItemSystem.apply_loadout(restored, String(data.get("character_id", "")))
		BattleSnapshot.apply_unit_statuses(restored, data)
		BattleSnapshot.apply_unit_moves(restored, data)
		BattleSnapshot.apply_unit_vitals(restored, data)

	return spawned


## Re-ignite the runtime (applied) tile effects the battle had going. Base terrain effects are
## derived from the map and need no restoring.
static func restore_board(snapshot: Dictionary) -> void:
	if CombatServices == null:
		return
	var board_state: Dictionary = snapshot.get("board", {})
	var applied: Variant = board_state.get("applied_tile_effects", [])
	if not (applied is Array):
		return
	for item in applied as Array:
		if not (item is Dictionary):
			continue
		var cell: Vector2i = BattleSnapshot.array_to_cell((item as Dictionary).get("cell", []))
		for raw_id in (item as Dictionary).get("ids", []):
			var effect = BattleSnapshot.tile_effect_by_id(StringName(String(raw_id)))
			if effect != null:
				CombatServices.add_tile_effect(cell, effect)


## PHASE 2, run after the turn system has been REGISTERED but before the game starts.
##
## Pre-stamps [TurnSystemBase]'s per-turn tick latch for every restored unit at
## [param turn_number], so the turn the system opens with does NOT tick statuses, move
## cooldowns, stat-modifier durations or ON_TURN_START abilities a second time. Without this a
## resume would silently cost the player one extra poison tick, one extra cooldown step and
## one extra ability proc on the very turn they came back to.
static func suppress_turn_start_tick(units: Array, turn_number: int) -> void:
	if TurnSystemManager == null:
		return
	var systems: Array = TurnSystemManager.available_turn_systems.values()
	if TurnSystemManager.has_active_turn_system():
		systems.append(TurnSystemManager.get_active_turn_system())
	for ts in systems:
		if ts == null or not is_instance_valid(ts):
			continue
		for unit in units:
			if unit != null and is_instance_valid(unit):
				ts._last_tick_turn[unit] = turn_number


## PHASE 3, run after the game (and therefore the turn system) has started.
##
## Rewinds the live turn system to the saved turn / actor and re-asserts the per-unit action
## flags, which BOTH systems clear when a turn begins.
##
## KNOWN APPROXIMATION, deliberately taken: a unit that was mid-way through a forced-control
## (Enthralled) turn is barred from acting for the rest of that turn but is not re-driven --
## the drive is a turn-START event that has already passed. It costs the puppeteer one turn of
## value; it never locks the unit out, because the status still expires on its next tick.
static func restore_turn_state(snapshot: Dictionary, units: Array) -> void:
	if TurnSystemManager == null or not TurnSystemManager.has_active_turn_system():
		return
	var ts = TurnSystemManager.get_active_turn_system()
	var turn: Dictionary = snapshot.get("turn", {})
	if turn.is_empty():
		return

	if ts is SpeedFirstTurnSystem and String(turn.get("type", "")) == BattleSnapshot.TURN_SPEED_FIRST:
		_restore_speed_first(ts as SpeedFirstTurnSystem, turn, units)
	elif ts is TraditionalTurnSystem and String(turn.get("type", "")) == BattleSnapshot.TURN_TRADITIONAL:
		_restore_traditional(ts as TraditionalTurnSystem, turn, units)

	# The turn start above reset every unit's action flags -- write the saved ones back, or a
	# unit that had already acted gets a free second action on resume.
	var entries: Array = snapshot.get("units", [])
	for i in range(mini(entries.size(), units.size())):
		BattleSnapshot.apply_unit_turn_flags(units[i], entries[i])

	_relatch_skips(ts, units)


static func _restore_traditional(ts: TraditionalTurnSystem, turn: Dictionary, units: Array) -> void:
	ts.current_turn = int(turn.get("current_turn", ts.current_turn))
	suppress_turn_start_tick(units, ts.current_turn)

	var had_turn: Array[Player] = []
	for raw_id in turn.get("players_had_turn", []):
		var player: Player = PlayerManager.get_player_by_id(int(raw_id)) if PlayerManager != null else null
		if player != null and player not in had_turn:
			had_turn.append(player)
	ts.players_had_turn_this_round = had_turn

	var target: Player = PlayerManager.get_player_by_id(int(turn.get("current_player_id", 0))) if PlayerManager != null else null
	if target != null and ts.current_player != target:
		ts._start_player_turn(target)

	var acted: Array[Unit] = []
	for index in turn.get("acted", []):
		var unit = _unit_at(units, int(index))
		if unit != null:
			acted.append(unit)
	ts.units_acted_this_turn = acted


static func _restore_speed_first(ts: SpeedFirstTurnSystem, turn: Dictionary, units: Array) -> void:
	ts.current_turn = int(turn.get("current_turn", ts.current_turn))
	ts.round_number = int(turn.get("round_number", ts.round_number))
	suppress_turn_start_tick(units, ts.current_turn)

	var queue: Array[Unit] = []
	for index in turn.get("queue", []):
		var queued = _unit_at(units, int(index))
		if queued != null:
			queue.append(queued)
	ts.turn_queue = queue

	var acted: Array[Unit] = []
	for index in turn.get("acted", []):
		var done = _unit_at(units, int(index))
		if done != null:
			acted.append(done)
	ts.units_acted_this_round = acted

	var actor = _unit_at(units, int(turn.get("acting_index", -1)))
	if actor != null and ts.current_acting_unit != actor:
		ts._start_unit_turn(actor)


## Re-latch the stun / forced-control skips for the restored turn. Both latches are normally
## sampled at turn start, BEFORE statuses tick -- but on a resume the statuses are installed
## after that moment, so they have to be re-sampled here or a unit that was skipping its turn
## would get to act.
static func _relatch_skips(ts, units: Array) -> void:
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		if ts._has_stun_flag(unit):
			ts._stun_skipped_turn[unit] = ts.current_turn
		if ts._has_control_flag(unit):
			ts._control_forced_turn[unit] = ts.current_turn


## PHASE 4: put the per-battle schedulers' clocks back. Run last, because both were created
## fresh during the map load and the turn-state rewind above can fire an extra turn_ended /
## turn_started at them; restoring here overwrites whatever that cost.
static func restore_managers(snapshot: Dictionary, spawn_manager, hazard_manager, units: Array) -> void:
	var board_state: Dictionary = snapshot.get("board", {})
	if spawn_manager != null and spawn_manager.has_method("restore_state"):
		var spawn_state: Variant = board_state.get("spawn_manager", {})
		if spawn_state is Dictionary:
			spawn_manager.restore_state(spawn_state as Dictionary)
	if hazard_manager != null and hazard_manager.has_method("restore_state"):
		var hazard_state: Variant = board_state.get("hazard_manager", {})
		if hazard_state is Dictionary:
			hazard_manager.restore_state(hazard_state as Dictionary,
				func(index: int): return _unit_at(units, index))


# --- Internals --------------------------------------------------------------

## Free every [Unit] under [param root] IMMEDIATELY (not queue_free): the replacements are
## spawned in the same frame, and a deferred free would leave two units standing on one cell
## for the rest of it -- which the occupancy checks and the board's units_at() would both see.
static func _free_units_under(root: Node) -> void:
	var doomed: Array = []
	_gather_units(root, doomed)
	for unit in doomed:
		if not is_instance_valid(unit):
			continue
		# Drop the unit's floating health bar first, exactly as a death would, so the visual
		# manager keeps no dangling entry for a node that is about to stop existing.
		if "visual_manager" in unit and unit.visual_manager != null \
				and unit.visual_manager.has_method("cleanup_unit_visuals"):
			unit.visual_manager.cleanup_unit_visuals(unit)
		unit.free()


static func _gather_units(node: Node, out: Array) -> void:
	if node == null:
		return
	for child in node.get_children():
		if child is Unit:
			out.append(child)
		_gather_units(child, out)


static func _unit_at(units: Array, index: int):
	if index < 0 or index >= units.size():
		return null
	var unit = units[index]
	return unit if unit != null and is_instance_valid(unit) else null


func _indices(subject: Array, units: Array) -> Array:
	var out: Array = []
	for unit in subject:
		if unit == null or not is_instance_valid(unit):
			continue
		var index: int = units.find(unit)
		if index >= 0:
			out.append(index)
	return out


func _player_id_of(unit) -> int:
	if unit == null or not is_instance_valid(unit):
		return -1
	var owner = null
	if unit.has_method("get_owner_player"):
		owner = unit.get_owner_player()
	elif "owner_player" in unit:
		owner = unit.owner_player
	if owner == null or not ("player_id" in owner):
		return -1
	return int(owner.player_id)


func _current_map_name() -> String:
	var world = _game_world_manager()
	if world == null:
		return ""
	var loader = world.get("map_loader")
	if loader == null or loader.current_map == null:
		return ""
	return String(loader.current_map.map_name)


## The live [GameWorldManager], via the group it joins in its own _ready. Deliberately
## UNTYPED: it is reached by group rather than by class, and everything asked of it here is
## duck-typed, so a Node-typed local would only add unsafe-access noise.
func _game_world_manager():
	var tree: SceneTree = get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("game_world_manager")


static func _challenge_controller():
	return _node("/root/ChallengeController")


## Resolve an autoload by PATH rather than by its global identifier, so this script compiles
## and runs in a headless/test context where the autoload may be absent.
static func _node(path: String):
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(path)
	return null
