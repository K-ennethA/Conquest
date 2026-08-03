extends GutTest

# THE PLAYBACK HAND-OFF: the byte container playback and the transport share, and what
# ReplayPlayback.launch() does -- and refuses to do -- with a log handed to it.
#
# Two things are pinned here because other code is written against them:
#   * ReplayLog.encode_container / decode_container -- the ONE CQRP codec. The file helpers
#     and the attach-to-attempt transport both go through it, so a second implementation (or
#     a decode that returns something other than {} for junk) would split the format in two.
#   * launch()'s result shapes -- { ok: true } and { ok: false, error: <ERROR_*> }. A replay
#     picker codes against exactly those, and a VERSION MISMATCH must refuse without touching
#     the scene, because the player is still standing in a menu when it happens.
#
# Nothing here ever launches SUCCESSFULLY: a successful launch changes scene, which would tear
# the test run's own scene out from under it. The staging half is driven directly instead
# (ReplayPlayback.stage), which is exactly what launch does after its two gates pass.

const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose (tests/README rule 3): a `: RefCounted` annotation makes the static
## analyser reject _guard.watch_setting().
var _guard

func before_each() -> void:
	_guard = Guard.new()
	for property in ["selected_map_path", "selected_turn_system", "ai_difficulty",
			"player_count", "selected_squad", "host_squad", "game_mode"]:
		_guard.watch_setting(property)
	# Process-wide statics this suite drives. Cleared in BOTH hooks so neither a previous
	# suite's leftovers answer here nor ours leak onward (tests/README rule 3).
	ReplayPlayback.end_playback()
	MatchLoadouts.clear()

func after_each() -> void:
	ReplayPlayback.end_playback()
	MatchLoadouts.clear()
	ReplayRecorder.recording_enabled = true
	_guard.restore()


# --- fixtures ----------------------------------------------------------------

## A minimal but COMPLETE log: a header this build accepts plus one appliable command.
func _log(overrides: Dictionary = {}) -> Dictionary:
	var fields: Dictionary = {
		"game_version": NetProtocol.local_game_version(),
		"protocol_version": NetProtocol.PROTOCOL_VERSION,
		"mode": ReplayLog.MODE_SKIRMISH,
		"map": { "path": "res://game/maps/resources/proving_grounds.tres", "name": "Proving Grounds" },
		"participants": [
			{ "slot": 0, "name": "Rowan", "is_ai": false,
				"squad": ["gem_knight"], "equipped": { "gem_knight": "ironbark_sigil" },
				"team": ["verdant_banner"], "skins": { "gem_knight": "gem_knight_sapphire" } },
			{ "slot": 1, "name": "The Wilds", "is_ai": true,
				"squad": ["mycothrall"], "equipped": {}, "team": [], "skins": {} },
		],
		"rng": { "match_seed": 4242 },
		"turn_system": 1,
		"difficulty": 2,
	}
	for key in overrides.keys():
		fields[key] = overrides[key]
	var log: Dictionary = ReplayLog.make_log(fields)
	log["entries"] = [ReplayLog.make_entry(1, 0, NetProtocol.make_move_unit(1, Vector2i(2, 3), 0))]
	log["checksums"] = [ReplayLog.make_checksum(1, "0011223344556677")]
	log["outcome"] = ReplayLog.make_outcome(ReplayLog.RESULT_VICTORY, 0, 7)
	return log


# --- 1. The container is one codec, and it round-trips -----------------------

func test_container_round_trips_a_log() -> void:
	var log: Dictionary = _log()
	var bytes: PackedByteArray = ReplayLog.encode_container(log)
	assert_gt(bytes.size(), ReplayLog.CONTAINER_HEADER_SIZE,
		"the container is a header plus a compressed body")
	var back: Dictionary = ReplayLog.decode_container(bytes)
	assert_eq(int(back.get("format_version", -1)), ReplayLog.FORMAT_VERSION,
		"the decoded log is a replay of this format")
	assert_eq((back.get("entries", []) as Array).size(), 1, "its body survived the round trip")
	assert_eq(int((back.get("rng", {}) as Dictionary).get("match_seed", 0)), 4242,
		"and so did the match seed playback re-seeds from")

func test_container_starts_with_the_cqrp_magic() -> void:
	var bytes: PackedByteArray = ReplayLog.encode_container(_log())
	for i in 4:
		assert_eq(bytes.decode_u8(i), ReplayLog.CONTAINER_MAGIC.unicode_at(i),
			"byte %d is the CQRP magic, so a non-replay file is refused before anything else" % i)

func test_to_bytes_is_the_same_container() -> void:
	# The aliases must not be able to drift into a second format.
	var log: Dictionary = _log()
	assert_eq(ReplayLog.to_bytes(log), ReplayLog.encode_container(log),
		"to_bytes IS encode_container -- one implementation, two names")
	assert_eq(ReplayLog.from_bytes(ReplayLog.encode_container(log)),
		ReplayLog.decode_container(ReplayLog.encode_container(log)),
		"and from_bytes IS decode_container")


# --- 2. Hostile bytes decode to {} -- quietly --------------------------------

func test_decode_container_refuses_junk_quietly() -> void:
	# Every one of these is an EXPECTED input (a truncated download, a hand-edited file, a
	# hostile upload), so each answers with {} and nothing reaches the engine log.
	assert_eq(ReplayLog.decode_container(PackedByteArray()), {}, "empty bytes are not a replay")
	assert_eq(ReplayLog.decode_container("not a replay at all".to_utf8_buffer()), {},
		"neither is arbitrary text")
	var short: PackedByteArray = ReplayLog.encode_container(_log()).slice(0, ReplayLog.CONTAINER_HEADER_SIZE)
	assert_eq(ReplayLog.decode_container(short), {}, "a header with no payload is refused")

func test_decode_container_refuses_a_broken_magic() -> void:
	var bytes: PackedByteArray = ReplayLog.encode_container(_log())
	bytes.encode_u8(0, "X".unicode_at(0))
	assert_eq(ReplayLog.decode_container(bytes), {}, "one wrong magic byte is enough to refuse")

func test_decode_container_refuses_a_wrong_container_version() -> void:
	var bytes: PackedByteArray = ReplayLog.encode_container(_log())
	bytes.encode_u32(4, ReplayLog.CONTAINER_VERSION + 1)
	assert_eq(ReplayLog.decode_container(bytes), {},
		"a container version this build cannot read is refused, never guessed at")

func test_decode_container_refuses_a_tampered_payload() -> void:
	var bytes: PackedByteArray = ReplayLog.encode_container(_log())
	# Flip a byte INSIDE the compressed payload: the digest no longer matches, so the bytes
	# never reach the decompressor (whose failure path is an uncatchable engine error).
	var at: int = ReplayLog.CONTAINER_HEADER_SIZE + 2
	bytes.encode_u8(at, (bytes.decode_u8(at) + 1) % 256)
	assert_eq(ReplayLog.decode_container(bytes), {},
		"the sha256 catches tampering BEFORE inflation")

func test_decode_container_refuses_an_absurd_declared_size() -> void:
	var bytes: PackedByteArray = ReplayLog.encode_container(_log())
	bytes.encode_u32(8, ReplayLog.MAX_DECOMPRESSED_BYTES + 1)
	assert_eq(ReplayLog.decode_container(bytes), {}, "a decompression bomb is capped by size")


# --- 3. launch() refuses without touching the scene --------------------------

func test_launch_refuses_a_version_mismatch_without_changing_scene() -> void:
	var before: Node = get_tree().current_scene
	var stale: Dictionary = _log({ "game_version": "some-other-build" })
	var result: Dictionary = ReplayPlayback.launch(stale)

	assert_false(bool(result.get("ok", true)), "a replay from another build is refused")
	assert_eq(String(result.get("error", "")), ReplayPlayback.ERROR_VERSION_MISMATCH,
		"and says exactly why, in the vocabulary the picker codes against")
	assert_eq(get_tree().current_scene, before,
		"the refusal never changes scene -- the player is still standing in the menu")
	assert_false(ReplayPlayback.has_pending(), "and nothing was staged for a battle")
	assert_false(ReplayPlayback.is_playing(), "so spectator mode was never armed")

func test_launch_refuses_a_log_the_gate_rejects() -> void:
	var before: Node = get_tree().current_scene
	for junk in [{}, { "format_version": 99 }, { "format_version": 1, "entries": "nope" }]:
		var result: Dictionary = ReplayPlayback.launch(junk)
		assert_false(bool(result.get("ok", true)), "a non-replay is refused: %s" % [junk])
		assert_eq(String(result.get("error", "")), ReplayPlayback.ERROR_INVALID_REPLAY,
			"under the invalid_replay error, never version_mismatch")
	assert_eq(get_tree().current_scene, before, "and none of them changed scene")
	assert_false(ReplayPlayback.has_pending(), "nor staged anything")

func test_launch_refuses_a_replay_carrying_an_unappliable_command() -> void:
	# ATTACK_UNIT has no apply branch, so validate() drops it -- and a log that is ONLY that
	# command validates to an empty body rather than to nothing. The gate is still the point:
	# whatever survives is appliable, so playback can never stall mid-log on a command it
	# cannot re-simulate.
	var log: Dictionary = _log()
	log["entries"] = [{ "turn": 1, "actor_slot": 0,
		"cmd": { NetProtocol.KEY_TYPE: NetProtocol.Action.ATTACK_UNIT, NetProtocol.KEY_DATA: {} } }]
	var clean: Dictionary = ReplayLog.validate(log)
	assert_eq((clean.get("entries", []) as Array).size(), 0,
		"an unappliable command is dropped at the gate, not discovered mid-playback")


# --- 4. Staging: what a launch points the next battle at ---------------------

func test_staging_points_the_battle_setters_at_the_header() -> void:
	ReplayPlayback.stage(ReplayLog.validate(_log()))

	assert_true(ReplayPlayback.has_pending(), "the log is parked for the battle scene")
	assert_eq(GameSettings.selected_map_path, "res://game/maps/resources/proving_grounds.tres",
		"the recorded map is what the ordinary map load will read")
	assert_eq(int(GameSettings.selected_turn_system), 1, "and the recorded turn system")
	assert_eq(int(GameSettings.ai_difficulty), 2, "and the recorded difficulty")
	assert_eq(int(GameSettings.player_count), 2, "with a seat for every recorded participant")
	assert_eq(GameSettings.get_host_squad(), [],
		"a host squad left over from a real match is cleared, so slot 0's card is authoritative")

func test_staging_seats_the_viewer_in_a_slot_no_participant_holds() -> void:
	ReplayPlayback.stage(ReplayLog.validate(_log()))

	assert_eq(MatchLoadouts.local_slot(), ReplayPlayback.SPECTATOR_SLOT,
		"the viewer is a spectator, so no recorded slot is 'mine'")
	assert_true(MatchLoadouts.is_active(),
		"which is what makes every side field its OWN items and skins instead of the viewer's")
	# The cards go through MatchLoadouts' own whitelist, so a roster id that no longer resolves
	# would legitimately be dropped -- assert on what SURVIVED rather than on a fixed list.
	assert_eq(Array(MatchLoadouts.squad_for(0)), ["gem_knight"],
		"slot 0 fields the squad it fielded when this was recorded")
	assert_eq(Array(MatchLoadouts.squad_for(1)), ["mycothrall"],
		"and so does slot 1 -- the half a solo battle would otherwise take from the map")

func test_staging_republishes_the_recorded_loadout_card_unchanged() -> void:
	# THE fix this shape exists for. The recorder writes a participant in the MatchLoadouts card
	# shape, so staging hands the three fields back verbatim and the spawn path reads exactly
	# what was recorded. A per-character worn item must NOT come back as a team item: that would
	# arm the whole squad and the per-turn checksum would (correctly) call the replay diverged --
	# and a challenge attacker routinely carries per-unit items, so defense replays, the headline
	# use, would refuse to play.
	ReplayPlayback.stage(ReplayLog.validate(_log()))

	var card: Dictionary = MatchLoadouts.get_peer_loadout(0)
	assert_eq(card["equipped"], { "gem_knight": "ironbark_sigil" },
		"the worn UNIT item is republished keyed to the character who wore it")
	assert_eq(Array(card["team"]), ["verdant_banner"], "the team item stays a team item")
	assert_eq(card["skins"], { "gem_knight": "gem_knight_sapphire" }, "and the skin rides along")

	# The reads the SPAWN PATH makes -- which is the only thing that actually matters.
	assert_eq(Array(MatchLoadouts.item_ids_for(0, "gem_knight")),
		["ironbark_sigil", "verdant_banner"],
		"the wearer gets its own item plus the team item")
	assert_eq(Array(MatchLoadouts.item_ids_for(0, "mycothrall")), ["verdant_banner"],
		"and a team-mate gets the TEAM item only -- never the other character's worn one")
	assert_eq(MatchLoadouts.skin_for(0, "gem_knight"), "gem_knight_sapphire",
		"the recorded skin is what the unit wears, because the viewer is a spectator")


func test_staging_a_participant_with_no_loadout_publishes_an_empty_card() -> void:
	ReplayPlayback.stage(ReplayLog.validate(_log()))
	var card: Dictionary = MatchLoadouts.get_peer_loadout(1)
	assert_eq(card["equipped"], {}, "a side that fielded nothing gets an empty equipped map")
	assert_eq(Array(card["team"]), [], "and no team items")
	assert_true(MatchLoadouts.has_peer_loadout(1),
		"but it DID announce -- an empty card is an answer, and it is what stops the viewer's "
		+ "own inventory being applied to that slot")


func test_taking_the_pending_replay_is_single_use() -> void:
	ReplayPlayback.stage(ReplayLog.validate(_log()))
	var taken: Dictionary = ReplayPlayback.take_pending()
	assert_eq((taken.get("entries", []) as Array).size(), 1, "the battle gets the staged log")
	assert_false(ReplayPlayback.has_pending(),
		"and the slot is empty afterwards, so a later battle cannot re-enter playback")


# --- 5. Spectator mode: the three switches -----------------------------------

func test_playback_switches_recording_off_and_back_on() -> void:
	ReplayRecorder.recording_enabled = true
	ReplayPlayback.stage(ReplayLog.validate(_log()))
	assert_false(ReplayRecorder.recording_enabled,
		"a replay being WATCHED must not record itself into a second file")

	ReplayPlayback.end_playback()
	assert_true(ReplayRecorder.recording_enabled,
		"and the next real battle records again -- the switch is restored, not left off")

func test_ending_playback_clears_the_staged_loadouts() -> void:
	ReplayPlayback.stage(ReplayLog.validate(_log()))
	ReplayPlayback.end_playback()
	assert_false(ReplayPlayback.is_playing(), "spectator mode is disarmed")
	assert_false(MatchLoadouts.is_active(),
		"and the replay's cards cannot be fielded by the next battle")

func test_begin_playback_is_idempotent() -> void:
	ReplayRecorder.recording_enabled = true
	ReplayPlayback.begin_playback()
	ReplayPlayback.begin_playback()
	ReplayPlayback.end_playback()
	assert_true(ReplayRecorder.recording_enabled,
		"a second arm cannot overwrite the value that has to be restored")

func test_disable_ai_drivers_is_null_safe() -> void:
	# (The live half -- a real BotTurnDriver being freed -- is in integration/test_replay_driver.)
	assert_eq(ReplayPlayback.disable_ai_drivers(null), 0,
		"no scene root (a transition mid-boot) is a no-op, not a crash")
