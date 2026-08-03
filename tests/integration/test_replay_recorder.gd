extends GutTest

## Integration tests for [ReplayRecorder] -- the per-battle command-log recorder.
##
## Integration rather than unit: the recorder is a Node that subscribes to autoload signals
## (GameEvents.command_committed, GameEvents.game_ended, TurnSystemManager.turn_system_activated)
## and to the ACTIVE turn system's turn signals.
##
## Coverage:
##  - The commit seam: is_active() gating, and note_* -> GameEvents.command_committed ->
##    the recorder's body, normalised into the NetProtocol vocabulary.
##  - Header LATCH: once and only once, lazily on the first command or the first turn.
##  - Entry order and turn stamping from the ACTIVE turn system.
##  - Checksums on the active system's turn_ended -- and the convention that the recorder
##    is NOT wired to PlayerManager's turn signals (which never fire on AI turns).
##  - finalize(): outcome stamping, idempotence, and the quit-mid-match fallback.
##  - Truncation: the entry cap flips the flag and drops silently.
##  - The PARTICIPANT LOADOUT: each slot sampled from whatever the spawn path would read, in
##    the MatchLoadouts card shape playback republishes verbatim.

## The item store is process-wide static state; point it at a temp path that is never written
## (nothing here calls ItemInventory.save) so the player's real collection cannot be reached.
const TEMP_ITEM_SAVE := "user://test_replay_recorder_items.json"

var _guard_recording_enabled: bool = true


## A stand-in for the PlayerProfile autoload: the one method MatchLoadouts.build_local_payload
## duck-types for. Kept local so the suite never touches the real profile file.
class FakeProfile extends RefCounted:
	var skins: Dictionary = {}

	func get_equipped_skin(character_id: String) -> String:
		return String(skins.get(character_id, ""))


func before_each() -> void:
	_guard_recording_enabled = ReplayRecorder.recording_enabled
	ReplayRecorder.recording_enabled = true
	CombatServices.clear()
	# Both process-wide loadout sources the recorder samples. Cleared in BOTH hooks so neither
	# a previous suite's leftovers answer here nor ours leak onward (tests/README rule 3).
	ItemInventory.set_save_path(TEMP_ITEM_SAVE)
	ItemInventory.reset()
	MatchLoadouts.clear()


func after_each() -> void:
	ReplayRecorder.recording_enabled = _guard_recording_enabled
	CombatServices.clear()
	ItemInventory.reset()
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
	MatchLoadouts.clear()


# --- Helpers ----------------------------------------------------------------

## A mounted recorder that never touches disk. Freed with the test (which is also what
## exercises the _exit_tree teardown path).
func _make_recorder() -> ReplayRecorder:
	var rec: ReplayRecorder = ReplayRecorder.new()
	rec.auto_save = false
	add_child_autofree(rec)
	return rec


## A bare turn system to drive turn_started / turn_ended from. Never registered with
## TurnSystemManager -- the recorder binds it through the handler the activation signal calls,
## so the test drives the real seam without emitting on a shared autoload.
func _make_turn_system() -> TurnSystemBase:
	var ts: TurnSystemBase = TurnSystemBase.new()
	add_child_autofree(ts)
	return ts


func _a_header() -> Dictionary:
	return {
		"mode": ReplayLog.MODE_SKIRMISH,
		"map": { "path": "res://maps/test.tres", "name": "Test" },
		"participants": [{ "slot": 0, "name": "P1", "is_ai": false, "squad": ["a"] }],
		"rng": { "match_seed": 42 },
	}


func _entries(rec: ReplayRecorder) -> Array:
	return rec.get_log().get("entries", []) as Array


func _cmd_type(entry: Dictionary) -> int:
	return int((entry["cmd"] as Dictionary)[NetProtocol.KEY_TYPE])


# --- The commit seam --------------------------------------------------------

func test_is_active_is_false_with_no_recorder_mounted() -> void:
	assert_false(ReplayRecorder.is_active(),
		"with nothing mounted the commit sites do no work at all")


func test_mounting_a_recorder_activates_the_seam() -> void:
	# Freed by hand (not autofree) because the point of the test is what teardown does.
	var rec: ReplayRecorder = ReplayRecorder.new()
	rec.auto_save = false
	add_child(rec)
	assert_true(ReplayRecorder.is_active(), "a mounted recorder activates the seam")
	rec.free()
	assert_false(ReplayRecorder.is_active(), "freeing it deactivates the seam again")


func test_recording_enabled_is_a_master_off_switch() -> void:
	var rec := _make_recorder()
	assert_true(ReplayRecorder.is_active(), "active by default")
	ReplayRecorder.recording_enabled = false
	assert_false(ReplayRecorder.is_active(), "the master switch overrides a mounted recorder")
	ReplayRecorder.note_end_turn(0)
	assert_eq(rec.entry_count(), 0, "and nothing is recorded while it is off")


func test_the_recorder_subscribes_to_the_command_seam() -> void:
	var rec := _make_recorder()
	assert_true(GameEvents.command_committed.is_connected(rec._on_command_committed),
		"the recorder is the subscriber on GameEvents.command_committed")
	assert_true(GameEvents.game_ended.is_connected(rec._on_game_ended),
		"and on GameEvents.game_ended, its normal finalize path")


func test_note_command_flows_through_the_signal_into_the_body() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	ReplayRecorder.note_command(NetProtocol.make_cast_move(5, 1, Vector2i(2, 2), 1), 1)
	var entries := _entries(rec)
	assert_eq(entries.size(), 1, "the command reached the body through the signal")
	assert_eq(_cmd_type(entries[0]), int(NetProtocol.Action.CAST_MOVE), "as a CAST_MOVE")
	assert_eq(int((entries[0] as Dictionary)["actor_slot"]), 1, "with the acting slot")


func test_note_command_falls_back_to_the_commands_own_actor() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	ReplayRecorder.note_command(NetProtocol.make_end_turn(1, 1))  # no explicit slot
	var entries := _entries(rec)
	assert_eq(int((entries[0] as Dictionary)["actor_slot"]), 1,
		"an omitted slot is read off the command's own actor field")


func test_note_end_turn_normalises_to_an_end_turn_command() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	ReplayRecorder.note_end_turn(1)
	var entries := _entries(rec)
	assert_eq(entries.size(), 1, "the solo end-turn is recorded")
	assert_eq(_cmd_type(entries[0]), int(NetProtocol.Action.END_TURN), "as END_TURN")
	var data: Dictionary = (entries[0]["cmd"] as Dictionary)[NetProtocol.KEY_DATA]
	assert_eq(int(data[NetProtocol.KEY_PLAYER_ID]), 1, "carrying the ending player")


func test_unit_commands_need_a_net_id() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	var nameless: Node3D = add_child_autofree(Node3D.new())
	ReplayRecorder.note_move_unit(nameless, Vector2i(1, 1))
	ReplayRecorder.note_wait_unit(nameless)
	ReplayRecorder.note_cast_move(nameless, 0, Vector2i(1, 1))
	assert_eq(rec.entry_count(), 0,
		"a unit the command seam never named cannot be addressed by a command, so nothing is recorded")
	assert_eq(ReplayRecorder.net_id_of(nameless), -1, "and it reports no net id")
	assert_eq(ReplayRecorder.net_id_of(null), -1, "null reports no net id")


func test_unit_commands_normalise_into_the_netprotocol_vocabulary() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	var unit: Node3D = add_child_autofree(Node3D.new())
	unit.set_meta("net_id", 11)

	ReplayRecorder.note_move_unit(unit, Vector2i(4, 5))
	ReplayRecorder.note_cast_move(unit, 2, Vector2i(6, 7))
	ReplayRecorder.note_wait_unit(unit)

	var entries := _entries(rec)
	assert_eq(entries.size(), 3, "all three solo/AI commit shapes are recorded")

	assert_eq(_cmd_type(entries[0]), int(NetProtocol.Action.MOVE_UNIT), "first is MOVE_UNIT")
	var move_data: Dictionary = (entries[0]["cmd"] as Dictionary)[NetProtocol.KEY_DATA]
	assert_eq(int(move_data[NetProtocol.KEY_UNIT_ID]), 11, "with the unit's net id")
	assert_eq(ReplayLog.decode_cell(move_data[NetProtocol.KEY_DEST_CELL]), Vector2i(4, 5),
		"and its destination")

	assert_eq(_cmd_type(entries[1]), int(NetProtocol.Action.CAST_MOVE), "second is CAST_MOVE")
	var cast_data: Dictionary = (entries[1]["cmd"] as Dictionary)[NetProtocol.KEY_DATA]
	assert_eq(int(cast_data[NetProtocol.KEY_MOVE_SLOT]), 2, "with the move slot")
	assert_eq(ReplayLog.decode_cell(cast_data[NetProtocol.KEY_AIM_CELL]), Vector2i(6, 7),
		"and the aim cell")

	assert_eq(_cmd_type(entries[2]), int(NetProtocol.Action.WAIT_UNIT), "third is WAIT_UNIT")


func test_recorded_entries_are_replayable_by_construction() -> void:
	# The contract the playback wave leans on: anything in the body decodes back to a live
	# command CommandApplier.apply_command accepts.
	var rec := _make_recorder()
	rec.begin(_a_header())
	var unit: Node3D = add_child_autofree(Node3D.new())
	unit.set_meta("net_id", 3)
	ReplayRecorder.note_move_unit(unit, Vector2i(1, 2))
	ReplayRecorder.note_end_turn(0)
	for entry in _entries(rec):
		var live := ReplayLog.decode_command((entry as Dictionary)["cmd"])
		assert_false(live.is_empty(), "every recorded entry decodes to a live command")
		assert_true(NetProtocol.is_command_well_formed(live), "and the protocol validator agrees")


func test_out_of_vocabulary_commands_are_dropped_silently() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	rec.append_command({ NetProtocol.KEY_TYPE: 9999 })
	rec.append_command({ "garbage": true })
	assert_eq(rec.entry_count(), 0, "commands playback could never apply never enter the log")


# --- Lifecycle --------------------------------------------------------------

func test_begin_latches_the_header_once() -> void:
	var rec := _make_recorder()
	assert_false(rec.started, "nothing is latched before begin")
	rec.begin(_a_header())
	assert_true(rec.started, "begin latches")
	assert_eq(int((rec.get_log()["rng"] as Dictionary)["match_seed"]), 42, "with the supplied header")

	rec.begin({ "mode": ReplayLog.MODE_ARENA, "rng": { "match_seed": 999 } })
	assert_eq(int((rec.get_log()["rng"] as Dictionary)["match_seed"]), 42,
		"a second begin is ignored -- the header is latched, not re-read")
	assert_eq(String(rec.get_log()["mode"]), ReplayLog.MODE_SKIRMISH, "the original mode stands")


func test_a_command_lazily_latches_the_header() -> void:
	var rec := _make_recorder()
	assert_false(rec.started, "not started")
	ReplayRecorder.note_end_turn(0)
	assert_true(rec.started, "the first command latches the header, so a mode that boots straight "
		+ "into commands still records")
	assert_eq(rec.entry_count(), 1, "and the command itself is kept")


func test_build_live_header_is_well_formed_headless() -> void:
	# Every read in the live header is guarded, so a headless harness still produces a
	# loadable header rather than raising.
	var rec := _make_recorder()
	var header := rec.build_live_header()
	var log := ReplayLog.make_log(header)
	assert_eq(int(log["format_version"]), ReplayLog.FORMAT_VERSION, "it makes a real log")
	assert_eq(String(log["game_version"]), NetProtocol.local_game_version(),
		"stamped with the same version source the net handshake reads")
	assert_true(ReplayLog.MODES.has(String(log["mode"])), "with a recognised mode")
	assert_false(ReplayLog.validate(ReplayLog.parse_text(ReplayLog.to_json(log))).is_empty(),
		"and it survives the strict importer")


# --- The participant loadout (the MatchLoadouts card shape) ------------------

func test_participant_loadout_samples_the_local_slot_from_the_local_stores() -> void:
	# Outside a networked match slot 0 IS the local human, and ItemSystem.loadout_for_slot /
	# MatchLoadouts.skin_for read its items and skins straight off the local stores. The
	# recorder must sample the SAME stores, or the replay would field a loadout the battle
	# never had.
	ItemInventory.grant("ironbark_sigil")
	ItemInventory.grant("verdant_banner")
	ItemInventory.equip("gem_knight", "ironbark_sigil")
	ItemInventory.set_team_item(0, "verdant_banner")
	var profile := FakeProfile.new()
	profile.skins = { "gem_knight": "gem_knight_sapphire" }

	var rec := _make_recorder()
	var card: Dictionary = rec.participant_loadout(0, profile)

	assert_eq(card["equipped"], { "gem_knight": "ironbark_sigil" },
		"the worn UNIT item is recorded KEYED to the character wearing it")
	assert_eq(Array(card["team"]), ["verdant_banner"], "the filled TEAM slot is recorded as a team item")
	assert_eq(card["skins"], { "gem_knight": "gem_knight_sapphire" },
		"and the equipped skin, keyed the same way")


func test_participant_loadout_samples_an_announced_slot_verbatim() -> void:
	# In a networked match every OTHER slot's loadout is its announced card -- the one the
	# spawn path reads through MatchLoadouts.items_for. Recording it verbatim is what makes
	# the two agree.
	MatchLoadouts.set_local_slot(0)
	MatchLoadouts.set_peer_loadout(1, {
		"equipped": { "mycothrall": "quillvine_barb" },
		"team": ["sunleaf_totem"],
		"skins": { "mycothrall": "mycothrall_emberspore" },
		"squad": ["mycothrall"],
	})

	var rec := _make_recorder()
	var card: Dictionary = rec.participant_loadout(1, null)

	assert_eq(card["equipped"], { "mycothrall": "quillvine_barb" }, "the peer's worn item, keyed")
	assert_eq(Array(card["team"]), ["sunleaf_totem"], "its team slot")
	assert_eq(card["skins"], { "mycothrall": "mycothrall_emberspore" }, "and its skin")


func test_participant_loadout_reads_our_own_seat_locally_in_a_networked_match() -> void:
	# Our own units never read a replicated card, even in a networked match -- the local
	# inventory is authoritative for us (MatchLoadouts.build_local_payload is what we ANNOUNCE).
	# So a recording made on seat 1 must sample seat 1 from the local stores, not from slot 0's.
	ItemInventory.grant("heartwood_charm")
	ItemInventory.equip("vineweave", "heartwood_charm")
	MatchLoadouts.set_local_slot(1)

	var rec := _make_recorder()
	assert_eq(rec.participant_loadout(1, null)["equipped"], { "vineweave": "heartwood_charm" },
		"our own seat is sampled from the local inventory")
	assert_eq(rec.participant_loadout(0, null)["equipped"], {},
		"and a slot that announced nothing records an empty card, not ours")


func test_participant_loadout_is_empty_for_a_side_that_fields_nothing() -> void:
	# A solo AI side and a neutral camp are equipped by nobody, so an empty card is the
	# truthful record. Every field is still present, so no reader needs a has() check.
	var rec := _make_recorder()
	var card: Dictionary = rec.participant_loadout(3, null)
	assert_eq(card["equipped"], {}, "no worn items")
	assert_eq(Array(card["team"]), [], "no team items")
	assert_eq(card["skins"], {}, "no skins")


func test_a_recorded_loadout_survives_the_container_still_keyed() -> void:
	# End to end: what the recorder sampled is what a loaded file hands playback -- per
	# character, not as a flat union that would arm the whole team.
	ItemInventory.grant("ironbark_sigil")
	ItemInventory.grant("verdant_banner")
	ItemInventory.equip("gem_knight", "ironbark_sigil")
	ItemInventory.set_team_item(0, "verdant_banner")
	var rec := _make_recorder()
	var card: Dictionary = rec.participant_loadout(0, null)

	rec.begin({
		"mode": ReplayLog.MODE_CHALLENGE,
		"participants": [{
			"slot": 0, "name": "P1", "is_ai": false, "squad": ["gem_knight"],
			"equipped": card["equipped"], "team": card["team"], "skins": card["skins"],
		}],
	})
	rec.finalize(ReplayLog.RESULT_VICTORY, 0)

	var loaded: Dictionary = ReplayLog.from_bytes(ReplayLog.to_bytes(rec.get_log()))
	var p: Dictionary = (loaded["participants"] as Array)[0]
	assert_eq(p["equipped"], { "gem_knight": "ironbark_sigil" },
		"the worn item is still keyed to its character after the round trip")
	assert_eq(p["team"], ["verdant_banner"], "and the team item is still a team item")


func test_entries_preserve_commit_order() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	for i in 5:
		ReplayRecorder.note_end_turn(i)
	var entries := _entries(rec)
	assert_eq(entries.size(), 5, "all five are recorded")
	for i in 5:
		var data: Dictionary = ((entries[i] as Dictionary)["cmd"] as Dictionary)[NetProtocol.KEY_DATA]
		assert_eq(int(data[NetProtocol.KEY_PLAYER_ID]), i, "entry %d is the %dth commit" % [i, i])


func test_truncation_flips_the_flag_and_drops_silently() -> void:
	var rec := _make_recorder()
	rec.max_entries = 2
	rec.begin(_a_header())
	for i in 6:
		ReplayRecorder.note_end_turn(0)
	assert_eq(rec.entry_count(), 2, "the cap holds")
	assert_true(rec.truncated, "and the recorder knows it truncated")
	rec.finalize(ReplayLog.RESULT_VICTORY, 0)
	assert_true(bool(rec.get_log()["truncated"]),
		"the flag is stamped into the file so playback knows the tail is missing")


func test_finalize_stamps_the_outcome_and_is_idempotent() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	ReplayRecorder.note_end_turn(0)
	rec.finalize(ReplayLog.RESULT_VICTORY, 0)
	assert_true(rec.finished, "the recorder is finished")
	var outcome: Dictionary = rec.get_log()["outcome"]
	assert_eq(String(outcome["result"]), ReplayLog.RESULT_VICTORY, "the result is stamped")
	assert_eq(int(outcome["winner_slot"]), 0, "and the winner slot")

	rec.finalize(ReplayLog.RESULT_DEFEAT, 1)
	assert_eq(String((rec.get_log()["outcome"] as Dictionary)["result"]), ReplayLog.RESULT_VICTORY,
		"a second finalize is a no-op")

	ReplayRecorder.note_end_turn(0)
	assert_eq(rec.entry_count(), 1, "and nothing appends after finalize")


func test_finalize_produces_a_log_that_survives_the_strict_importer() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	var unit: Node3D = add_child_autofree(Node3D.new())
	unit.set_meta("net_id", 8)
	ReplayRecorder.note_move_unit(unit, Vector2i(1, 1))
	ReplayRecorder.note_wait_unit(unit)
	ReplayRecorder.note_end_turn(0)
	rec.finalize(ReplayLog.RESULT_DEFEAT, 1)

	var round_tripped := ReplayLog.from_bytes(ReplayLog.to_bytes(rec.get_log()))
	assert_false(round_tripped.is_empty(), "a finalized log survives the on-disk container")
	assert_eq((round_tripped["entries"] as Array).size(), 3, "with every entry intact")
	assert_eq(String((round_tripped["outcome"] as Dictionary)["result"]), ReplayLog.RESULT_DEFEAT,
		"and its outcome")


func test_get_log_returns_a_copy() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	ReplayRecorder.note_end_turn(0)
	var copy := rec.get_log()
	(copy["entries"] as Array).clear()
	copy["mode"] = "tampered"
	assert_eq(rec.entry_count(), 1, "mutating the copy does not touch the live recording")
	assert_eq(String(rec.get_log()["mode"]), ReplayLog.MODE_SKIRMISH, "nor its header")


func test_result_for_winner_reads_from_the_local_point_of_view() -> void:
	assert_eq(ReplayRecorder.result_for_winner(null), ReplayLog.RESULT_DRAW, "no winner is a draw")
	var human := Player.new()
	human.player_id = 0
	human.is_ai = false
	assert_eq(ReplayRecorder.result_for_winner(human), ReplayLog.RESULT_VICTORY, "a human winner is a victory")
	var bot := Player.new()
	bot.player_id = 1
	bot.is_ai = true
	assert_eq(ReplayRecorder.result_for_winner(bot), ReplayLog.RESULT_DEFEAT, "an AI winner is a defeat")


# --- Turn plumbing (the ACTIVE turn system, never PlayerManager) -------------

func test_the_recorder_rides_the_turn_system_activation_signal() -> void:
	var rec := _make_recorder()
	assert_true(TurnSystemManager.turn_system_activated.is_connected(rec._on_turn_system_activated),
		"the recorder re-binds whenever the active turn system changes")


func test_the_recorder_is_not_wired_to_player_manager_turn_signals() -> void:
	# PROJECT CONVENTION: PlayerManager's turn signals do NOT fire on AI turns, so a recorder
	# wired to them would silently stop checksumming the moment the enemy acted.
	var rec := _make_recorder()
	assert_eq(PlayerManager.player_turn_started.get_connections().filter(
		func(c): return c["callable"].get_object() == rec).size(), 0,
		"nothing of the recorder listens to PlayerManager.player_turn_started")
	assert_eq(PlayerManager.player_turn_ended.get_connections().filter(
		func(c): return c["callable"].get_object() == rec).size(), 0,
		"nor to PlayerManager.player_turn_ended")


func test_entries_are_stamped_with_the_active_systems_turn() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	var ts := _make_turn_system()
	rec._on_turn_system_activated(ts)

	ts.current_turn = 3
	ts.turn_started.emit(null)
	ReplayRecorder.note_end_turn(0)
	ts.current_turn = 7
	ts.turn_started.emit(null)
	ReplayRecorder.note_end_turn(1)

	var entries := _entries(rec)
	assert_eq(int((entries[0] as Dictionary)["turn"]), 3, "the first command is stamped turn 3")
	assert_eq(int((entries[1] as Dictionary)["turn"]), 7, "the second, turn 7")


func test_turn_end_appends_a_checksum() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	var ts := _make_turn_system()
	rec._on_turn_system_activated(ts)

	assert_eq(rec.checksum_count(), 0, "no checksums yet")
	ts.current_turn = 1
	ts.turn_started.emit(null)
	ts.turn_ended.emit(null)
	assert_eq(rec.checksum_count(), 1, "the active system's turn_ended stamps one")
	ts.current_turn = 2
	ts.turn_started.emit(null)
	ts.turn_ended.emit(null)
	assert_eq(rec.checksum_count(), 2, "and one per turn thereafter")

	var checks: Array = rec.get_log()["checksums"]
	assert_eq(int((checks[0] as Dictionary)["turn"]), 1, "stamped with the turn it closed")
	assert_eq(int((checks[1] as Dictionary)["turn"]), 2, "and the next")
	assert_eq(String((checks[0] as Dictionary)["hash"]).length(), 16, "each hash is a 16-char digest")


func test_the_first_turn_latches_the_header() -> void:
	var rec := _make_recorder()
	var ts := _make_turn_system()
	rec._on_turn_system_activated(ts)
	assert_false(rec.started, "nothing is latched before the first turn")
	ts.current_turn = 1
	ts.turn_started.emit(null)
	assert_true(rec.started,
		"the first turn latches -- late enough that the roster and squads exist")


func test_switching_turn_systems_rebinds_cleanly() -> void:
	var rec := _make_recorder()
	rec.begin(_a_header())
	var first := _make_turn_system()
	var second := _make_turn_system()
	rec._on_turn_system_activated(first)
	rec._on_turn_system_activated(second)

	first.turn_ended.emit(null)
	assert_eq(rec.checksum_count(), 0, "the old system no longer drives the recorder")
	second.turn_ended.emit(null)
	assert_eq(rec.checksum_count(), 1, "the new one does")
	assert_false(first.turn_ended.is_connected(rec._on_turn_ended), "and the old connection is dropped")


func test_teardown_finalizes_an_abandoned_battle() -> void:
	# Quitting mid-match must not lose the log: "watch what the attacker did" wants an
	# abandoned attempt too.
	var rec: ReplayRecorder = ReplayRecorder.new()
	rec.auto_save = false
	add_child(rec)
	rec.begin(_a_header())
	ReplayRecorder.note_end_turn(0)
	assert_false(rec.finished, "not finished while the battle runs")
	rec.free()
	assert_false(ReplayRecorder.is_active(), "the seam is closed after teardown")
