extends Node
class_name ReplayRecorder

## The per-battle COMMAND-LOG RECORDER. Mounted once per battle (see
## [method GameWorldManager._setup_replay_recorder]), it latches the initial setup, appends
## every command every actor commits -- human AND AI, every mode -- stamps a cheap state
## checksum at each turn end, and writes a [ReplayLog] to [code]user://replays/[/code] when
## the battle ends.
##
## WHY THIS WORKS AT ALL: the game is lockstep-deterministic. Every mutation runs through
## the same resolution layer, and every roll comes from a [MatchRng] stream derived from the
## match seed, so re-issuing the same commands from the same setup reproduces the battle
## exactly. Recording is therefore just LISTENING -- it changes no state and consumes nothing.
##
## THE ONE SEAM: [signal GameEvents.command_committed]. Every commit site in the game emits
## it (via the [code]note_*[/code] statics below) and this node is the only subscriber, so a
## new command site costs ONE line and nothing else in the game knows recording exists.
## Sites, and what they cover:
##   * [method CommandApplier.apply_command] -- ALL networked play (every peer applies there,
##     so the acting peer's own UI submit path deliberately does not also record).
##   * [UnitActionsPanel] -- the solo/hotseat FE command loop: the committed move, the cast,
##     Wait, and End Player Turn.
##   * [BotTurnDriver] -- the AI: its relocations, its casts, and its waits.
## Solo and AI actions are normalised into the SAME [NetProtocol] vocabulary the networked
## commands use, so playback has exactly one apply path to drive.
##
## ZERO-COST WHEN OFF. Every [code]note_*[/code] static returns immediately on
## [method is_active] (a static counter of mounted recorders), so a battle with no recorder --
## and every unit test that constructs a [CommandApplier] -- pays one integer compare and
## builds no dictionaries.
##
## TURN SIGNALS RIDE THE ACTIVE TURN SYSTEM. [signal TurnSystemBase.turn_started] /
## [signal TurnSystemBase.turn_ended], never [code]PlayerManager.player_turn_started[/code] --
## the latter does not fire on AI turns, so a recorder wired to it would silently stop
## checksumming the moment the enemy acted (project convention #2).

## Group every battle-scoped consumer can find this node by.
const GROUP := &"replay_recorder"

## How many recorders are mounted. The [method is_active] gate every commit site checks.
static var _active_count: int = 0

## Master off switch. Recording is ON for real battles by default (it is cheap, and the
## challenge "base defense" flow needs it); a test or a tool can switch it off process-wide.
static var recording_enabled: bool = true


# --- The commit seam (statics every commit site calls) -----------------------

## True when at least one recorder is mounted AND recording is enabled. Commit sites gate on
## this so nothing is built when nobody is listening.
static func is_active() -> bool:
	return recording_enabled and _active_count > 0


## Record an already-normalised [NetProtocol] command. THE entry point for the networked
## path, where [method CommandApplier.apply_command] already holds a resolved command.
static func note_command(cmd: Dictionary, actor_slot: int = -1) -> void:
	if not is_active():
		return
	var slot: int = actor_slot
	if slot < 0:
		slot = int(cmd.get(NetProtocol.KEY_ACTOR, -1))
	_emit(cmd, slot)


## Record a committed board move for [param unit] onto [param dest_cell] (MOVE_UNIT).
static func note_move_unit(unit, dest_cell: Vector2i) -> void:
	if not is_active():
		return
	var nid: int = net_id_of(unit)
	if nid < 0:
		return
	_emit(NetProtocol.make_move_unit(nid, dest_cell, slot_of_unit(unit)), slot_of_unit(unit))


## Record a resolved cast: [param unit]'s [param move_slot] aimed at [param aim_cell]
## (CAST_MOVE). Called AFTER the cast succeeded, so a refused/aborted aim is never recorded.
static func note_cast_move(unit, move_slot: int, aim_cell: Vector2i) -> void:
	if not is_active():
		return
	var nid: int = net_id_of(unit)
	if nid < 0:
		return
	_emit(NetProtocol.make_cast_move(nid, move_slot, aim_cell, slot_of_unit(unit)), slot_of_unit(unit))


## Record [param unit] ending its own turn without casting (WAIT_UNIT).
static func note_wait_unit(unit) -> void:
	if not is_active():
		return
	var nid: int = net_id_of(unit)
	if nid < 0:
		return
	_emit(NetProtocol.make_wait_unit(nid, slot_of_unit(unit)), slot_of_unit(unit))


## Record [param player_id] ending their whole turn (END_TURN).
static func note_end_turn(player_id: int) -> void:
	if not is_active():
		return
	_emit(NetProtocol.make_end_turn(player_id, player_id), player_id)


## The deterministic id naming [param unit] across peers -- the [code]net_id[/code] metadata
## [method CommandApplier.UnitRegistry.register] stamps on every unit when the battle's
## command seam is built. Read from METADATA rather than through NetSession on purpose: it
## keeps this file free of any dependency on the net layer (which itself depends on the
## applier that calls us). -1 means "unnameable" -- the caller must not record.
static func net_id_of(unit) -> int:
	if unit == null or not (unit is Object):
		return -1
	if not is_instance_valid(unit):
		return -1
	if not (unit as Object).has_meta("net_id"):
		return -1
	return int((unit as Object).get_meta("net_id"))


## The player slot that owns [param unit], or -1 when unknown. Slot == player_id, the same
## alignment [method NetSession._slot_for_player] uses by default (host = player 0 = slot 0).
static func slot_of_unit(unit) -> int:
	if unit == null or typeof(PlayerManager) != TYPE_OBJECT or PlayerManager == null:
		return -1
	# get_player_owning_unit is TYPED (unit: Unit); handing it anything else is an engine
	# error, not a returned failure. Guard here so a double / a non-unit caller reads as
	# "unowned" instead (convention #1 -- and the recorder must never be able to spam the log).
	if not (unit is Unit):
		return -1
	if not PlayerManager.has_method("get_player_owning_unit"):
		return -1
	var owner = PlayerManager.get_player_owning_unit(unit)
	if owner == null:
		return -1
	return int(owner.player_id)


static func _emit(cmd: Dictionary, actor_slot: int) -> void:
	if typeof(GameEvents) != TYPE_OBJECT or GameEvents == null:
		return
	if not GameEvents.has_signal(&"command_committed"):
		return
	GameEvents.command_committed.emit(cmd, int(actor_slot))


# --- Instance state ----------------------------------------------------------

## The log being built. Empty until [method begin] latches the header.
var log: Dictionary = {}
## True once the header is latched (the battle "started" from the recorder's point of view).
var started: bool = false
## True once the outcome has been stamped; a second finalize is a no-op.
var finished: bool = false
## True once the entry cap stopped recording. Stamped into the file so playback knows the
## tail is missing rather than treating a truncated battle as a complete one.
var truncated: bool = false
## Entry ceiling for THIS recorder. Injectable so a test can drive truncation cheaply.
var max_entries: int = ReplayLog.MAX_ENTRIES
## Write the file on finalize. Off in tests that only inspect the in-memory log.
var auto_save: bool = true
## Where the finalized replay was written ("" when it was not).
var saved_path: String = ""

## The turn number checksums and entries are stamped with, driven by the ACTIVE turn system.
var _turn: int = 0
## The turn system we are currently subscribed to (dropped and re-hooked on a switch).
var _turn_system: TurnSystemBase = null


func _ready() -> void:
	add_to_group(GROUP)
	_active_count += 1
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.has_signal(&"command_committed") \
			and not GameEvents.command_committed.is_connected(_on_command_committed):
		GameEvents.command_committed.connect(_on_command_committed)
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and not GameEvents.game_ended.is_connected(_on_game_ended):
		GameEvents.game_ended.connect(_on_game_ended)
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null:
		if not TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
			TurnSystemManager.turn_system_activated.connect(_on_turn_system_activated)
		if TurnSystemManager.has_active_turn_system():
			_bind_turn_system(TurnSystemManager.get_active_turn_system())


func _exit_tree() -> void:
	_active_count = maxi(0, _active_count - 1)
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.has_signal(&"command_committed") \
			and GameEvents.command_committed.is_connected(_on_command_committed):
		GameEvents.command_committed.disconnect(_on_command_committed)
	if typeof(GameEvents) == TYPE_OBJECT and GameEvents != null \
			and GameEvents.game_ended.is_connected(_on_game_ended):
		GameEvents.game_ended.disconnect(_on_game_ended)
	if typeof(TurnSystemManager) == TYPE_OBJECT and TurnSystemManager != null \
			and TurnSystemManager.turn_system_activated.is_connected(_on_turn_system_activated):
		TurnSystemManager.turn_system_activated.disconnect(_on_turn_system_activated)
	_unbind_turn_system()
	# Battle teardown is the LAST chance to keep what was recorded. A battle that was quit
	# mid-match finalizes with RESULT_UNKNOWN rather than losing the log entirely -- which is
	# exactly what a "watch what the attacker did" flow wants even for an abandoned attempt.
	if started and not finished:
		finalize(ReplayLog.RESULT_UNKNOWN, -1)


# --- Lifecycle ---------------------------------------------------------------

## LATCH the header from live state and open the body. Idempotent: a second call is ignored,
## so the "start the battle" hook and the lazy latch on the first command cannot double-latch.
## [param header_override] lets a caller (or a test) supply the header outright.
func begin(header_override: Dictionary = {}) -> void:
	if started:
		return
	log = ReplayLog.make_log(header_override if not header_override.is_empty() else build_live_header())
	started = true
	finished = false
	truncated = false
	saved_path = ""


## Stamp the outcome and (when [member auto_save]) write the file. Idempotent.
## Returns the path written, or "" when nothing was written.
func finalize(result: String = ReplayLog.RESULT_UNKNOWN, winner_slot: int = -1) -> String:
	if not started or finished:
		return saved_path
	finished = true
	log["truncated"] = truncated
	log["outcome"] = ReplayLog.make_outcome(result, winner_slot, _turn)
	if auto_save:
		saved_path = ReplayLog.save_to_file(log)
	return saved_path


## The finished (or in-progress) log. A COPY -- a caller mutating the result must not edit
## what is still being recorded. This is what the playback wave and the "attach a replay to
## a challenge attempt report" transport will read.
func get_log() -> Dictionary:
	return log.duplicate(true)


func entry_count() -> int:
	return (log.get("entries", []) as Array).size() if started else 0


func checksum_count() -> int:
	return (log.get("checksums", []) as Array).size() if started else 0


# --- Recording ---------------------------------------------------------------

func _on_command_committed(cmd: Dictionary, actor_slot: int) -> void:
	append_command(cmd, actor_slot)


## Append one committed command. Lazily latches the header if the battle-start hook never
## ran (a mode that boots straight into commands still records). Past [member max_entries]
## it flips [member truncated] and drops the command -- silently, because a capped recording
## is a handled outcome, not a fault (convention #1).
func append_command(cmd: Dictionary, actor_slot: int = -1) -> void:
	if not started:
		begin()
	if finished:
		return
	var entries: Array = log.get("entries", [])
	if entries.size() >= max_entries:
		truncated = true
		return
	var encoded: Dictionary = ReplayLog.encode_command(cmd)
	if encoded.is_empty():
		return  # outside the replayable vocabulary -- dropped rather than written
	entries.append(ReplayLog.make_entry(_turn, actor_slot, encoded))


## Stamp the current board state as this turn's checksum. Called at every turn end; also
## callable directly by a test.
func append_checksum() -> void:
	if not started or finished:
		return
	var checks: Array = log.get("checksums", [])
	if checks.size() >= ReplayLog.MAX_CHECKSUMS:
		return
	checks.append(ReplayLog.make_checksum(_turn, ReplayLog.state_checksum(collect_state_rows())))


## The rows [method ReplayLog.state_checksum] hashes: one
## [code]{ id, cell, hp }[/code] per live unit that the command seam named. A unit with no
## net_id is SKIPPED -- it cannot be addressed by a command either, so including it would
## make the checksum depend on something playback can never reproduce.
func collect_state_rows() -> Array:
	var rows: Array = []
	if typeof(CombatServices) != TYPE_OBJECT or CombatServices == null:
		return rows
	var board = CombatServices.board()
	if board == null or not board.has_method("all_units"):
		return rows
	for unit in board.all_units():
		if unit == null or not is_instance_valid(unit):
			continue
		var nid: int = net_id_of(unit)
		if nid < 0:
			continue
		rows.append({
			"id": nid,
			"cell": board.cell_of(unit) if board.has_method("cell_of") else Vector2i.ZERO,
			"hp": int(unit.get_hp()) if unit.has_method("get_hp") else 0,
		})
	return rows


# --- Turn plumbing (the ACTIVE turn system, never PlayerManager) -------------

func _on_turn_system_activated(system: TurnSystemBase) -> void:
	_bind_turn_system(system)


func _bind_turn_system(system: TurnSystemBase) -> void:
	if system == _turn_system:
		return
	_unbind_turn_system()
	_turn_system = system
	if _turn_system == null:
		return
	if not _turn_system.turn_started.is_connected(_on_turn_started):
		_turn_system.turn_started.connect(_on_turn_started)
	if not _turn_system.turn_ended.is_connected(_on_turn_ended):
		_turn_system.turn_ended.connect(_on_turn_ended)
	_turn = int(_turn_system.current_turn)


func _unbind_turn_system() -> void:
	if _turn_system == null or not is_instance_valid(_turn_system):
		_turn_system = null
		return
	if _turn_system.turn_started.is_connected(_on_turn_started):
		_turn_system.turn_started.disconnect(_on_turn_started)
	if _turn_system.turn_ended.is_connected(_on_turn_ended):
		_turn_system.turn_ended.disconnect(_on_turn_ended)
	_turn_system = null


func _on_turn_started(_player) -> void:
	if _turn_system != null and is_instance_valid(_turn_system):
		_turn = int(_turn_system.current_turn)
	# A battle that begins with the first turn latches its header HERE, so the participant
	# roster and squads are read once everyone is registered.
	if not started:
		begin()


func _on_turn_ended(_player) -> void:
	append_checksum()


## The battle DECIDED. Stamp a final checksum (so the winning turn's board state is in the
## log even though its turn_ended may never fire) and finalize -- this is the normal write
## path; [method _exit_tree]'s finalize is only the quit-mid-match fallback.
func _on_game_ended(winner) -> void:
	if not started or finished:
		return
	append_checksum()
	finalize(result_for_winner(winner), _slot_of_player(winner))


## Outcome label from the winning [Player], read from the LOCAL player's point of view:
## no winner is a draw, an AI winner is a defeat, anyone else is a victory. The authoritative
## payload either way is [code]outcome.winner_slot[/code] -- in versus / hotseat, where both
## sides are human, "victory" simply means a human won and the slot says which.
static func result_for_winner(winner) -> String:
	if winner == null or not is_instance_valid(winner):
		return ReplayLog.RESULT_DRAW
	if "is_ai" in winner and bool(winner.is_ai):
		return ReplayLog.RESULT_DEFEAT
	return ReplayLog.RESULT_VICTORY


static func _slot_of_player(player) -> int:
	if player == null or not is_instance_valid(player) or not ("player_id" in player):
		return -1
	return int(player.player_id)


# --- Header from live state --------------------------------------------------

## Build the replay header from whatever the live battle can tell us. Every read is guarded,
## so a headless harness with no autoloads still produces a well-formed (if sparse) header.
##
## The shape deliberately MIRRORS [method BattleSaveManager._capture_context]: same mode
## discriminator (which controller is capturing this battle), same map identity, same
## turn-system / difficulty / squad sources. One serialization vocabulary, two consumers.
func build_live_header() -> Dictionary:
	return {
		"game_version": NetProtocol.local_game_version(),
		"protocol_version": NetProtocol.PROTOCOL_VERSION,
		"recorded_at_utc": Time.get_datetime_string_from_system(true),
		"mode": resolve_mode(),
		"map": _live_map(),
		"participants": _live_participants(),
		"rng": { "match_seed": _live_match_seed() },
		"turn_system": int(GameSettings.selected_turn_system) if _autoload_ok(GameSettings) else 0,
		"difficulty": int(GameSettings.ai_difficulty) if _autoload_ok(GameSettings) else 0,
		"challenge_id": _live_challenge_id(),
		"campaign_chapter_id": _live_chapter_id(),
	}


## Which mode this battle is. Decided by WHICH controller is capturing it -- the same gate
## [BattleSaveManager] uses, so the two can never disagree -- falling back to the versus /
## skirmish split on the live game mode.
func resolve_mode() -> String:
	var challenge = get_node_or_null("/root/ChallengeController")
	if challenge != null and challenge.has_method("is_capturing") and challenge.is_capturing():
		return ReplayLog.MODE_CHALLENGE
	var campaign = get_node_or_null("/root/CampaignController")
	if campaign != null and campaign.has_method("is_capturing") and campaign.is_capturing():
		return ReplayLog.MODE_CAMPAIGN
	var arena = get_node_or_null("/root/ArenaController")
	if arena != null and arena.has_method("is_active") and arena.is_active():
		return ReplayLog.MODE_ARENA
	var net = get_node_or_null("/root/NetSession")
	if net != null and net.has_method("is_networked_match") and net.is_networked_match():
		return ReplayLog.MODE_VERSUS
	if _autoload_ok(GameSettings) and GameSettings.game_mode == GameSettings.GameMode.VERSUS:
		return ReplayLog.MODE_VERSUS
	return ReplayLog.MODE_SKIRMISH


func _live_map() -> Dictionary:
	var path: String = String(GameSettings.selected_map_path) if _autoload_ok(GameSettings) else ""
	var custom: bool = path.begins_with("user://")
	return {
		"path": path,
		"name": path.get_file().get_basename(),
		"custom": custom,
		# The embedded payload is the CUSTOM-MAP seam: a challenge / community map has no
		# res:// identity the viewer's machine can resolve, so the map dict travels with the
		# replay. Left empty here -- the transport wave (attach-replay-to-attempt-report) is
		# what has the validated challenge blob in hand and fills it in.
		"payload": {},
	}


func _live_participants() -> Array:
	var out: Array = []
	if not _autoload_ok(PlayerManager):
		return out
	var profile = get_node_or_null("/root/PlayerProfile")
	for player in PlayerManager.players:
		if player == null:
			continue
		var slot: int = int(player.player_id)
		var squad: Array = _squad_for_slot(slot)
		var skins: Dictionary = {}
		var items: Array = []
		for character_id in squad:
			var skin: String = MatchLoadouts.skin_for(slot, String(character_id), profile)
			if not skin.is_empty():
				skins[String(character_id)] = skin
			for item_id in MatchLoadouts.item_ids_for(slot, String(character_id)):
				if not items.has(String(item_id)):
					items.append(String(item_id))
		out.append({
			"slot": slot,
			"name": player.get_display_name() if player.has_method("get_display_name") else String(player.player_name),
			"is_ai": bool(player.is_ai) if "is_ai" in player else false,
			"squad": squad,
			"items": items,
			"skins": skins,
		})
	return out


## The character ids fielded by [param slot]: the replicated card when a networked match
## announced one, else the local Character Select pick for slot 0 (every other solo slot
## fields the map's authored roster, which the map path already identifies).
func _squad_for_slot(slot: int) -> Array:
	var out: Array = []
	if MatchLoadouts.has_peer_loadout(slot):
		for id in MatchLoadouts.squad_for(slot):
			out.append(String(id))
		if not out.is_empty():
			return out
	if slot == 0 and _autoload_ok(GameSettings) and GameSettings.has_method("get_selected_squad"):
		for id in GameSettings.get_selected_squad():
			out.append(String(id))
	return out


## The battle's match seed. Resolved through the tree rather than the NetSession global so
## this file keeps no static dependency on the net layer (see [method net_id_of]).
func _live_match_seed() -> int:
	var net = get_node_or_null("/root/NetSession")
	if net == null:
		return 0
	var rng = net.get("match_rng")
	if rng == null:
		return 0
	return int(rng.match_seed)


func _live_challenge_id() -> String:
	var challenge = get_node_or_null("/root/ChallengeController")
	if challenge == null or not challenge.has_method("is_capturing") or not challenge.is_capturing():
		return ""
	if not challenge.has_method("active_challenge"):
		return ""
	# The challenge id IS its content checksum (see ChallengeCodec.challenge_id). Read the
	# field directly rather than depending on the challenge module from the replay core.
	return String((challenge.active_challenge() as Dictionary).get("checksum", ""))


func _live_chapter_id() -> String:
	var campaign = get_node_or_null("/root/CampaignController")
	if campaign == null or not campaign.has_method("is_capturing") or not campaign.is_capturing():
		return ""
	if not campaign.has_method("active_chapter"):
		return ""
	return String((campaign.active_chapter() as Dictionary).get("id", ""))


func _autoload_ok(node) -> bool:
	return typeof(node) == TYPE_OBJECT and node != null
