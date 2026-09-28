extends GutTest

## The pure rules behind three local-battle seams, pinned without a booted battle:
##   * WHO GETS AN AI DRIVER -- every local battle (solo AND hot-seat), never a network match,
##     never replay playback ([method GameWorldManager.should_mount_bot_driver]);
##   * WHICH UNIT NAMING A REPLAY USES -- a recording made now says "slot"; a header without the
##     field predates the fix and is read as "legacy", so an archived replay keeps resolving
##     ([method ReplayLog.unit_id_scheme_of]), and the battle names its board accordingly;
##   * THE LOCAL COMMAND STREAM -- a local command's generator is a pure function of the match
##     seed and its index, its seed is handed to the recorder exactly once, and without a solo
##     stream nothing is touched ([method NetSessionNode.begin_local_command]).

## GameWorldManager has no class_name (it is the battle scene's root script), so it is
## reached by path.
const GWM := preload("res://game/world/GameWorldManager.gd")


# --- The AI driver ----------------------------------------------------------------

func test_every_local_battle_mounts_the_ai_driver() -> void:
	assert_true(GWM.should_mount_bot_driver(GameSettings.GameMode.SINGLE_PLAYER, false),
		"a solo battle drives its opponent")
	assert_true(GWM.should_mount_bot_driver(GameSettings.GameMode.VERSUS, false),
		"a HOT-SEAT battle mounts it too: a neutral faction or Siege creeps need driving, and "
		+ "it never touches a unit either human commands")


func test_network_play_and_replays_never_mount_it() -> void:
	assert_false(GWM.should_mount_bot_driver(GameSettings.GameMode.MULTIPLAYER, false),
		"no AI runs on either peer of a network match")
	assert_false(GWM.should_mount_bot_driver(GameSettings.GameMode.SINGLE_PLAYER, true),
		"replay playback re-applies the AI's recorded actions -- a live driver would act twice")
	assert_false(GWM.should_mount_bot_driver(GameSettings.GameMode.VERSUS, true),
		"in any mode")


# --- Replay unit naming -----------------------------------------------------------

func test_a_new_recording_declares_owner_slot_naming() -> void:
	var rec := ReplayRecorder.new()
	rec.auto_save = false
	add_child_autofree(rec)
	var header: Dictionary = rec.build_live_header()
	assert_eq(String(header.get("unit_ids", "")), ReplayLog.UNIT_IDS_SLOT,
		"the recorder stamps the naming the battle now uses")
	var log: Dictionary = ReplayLog.validate(ReplayLog.make_log(header))
	assert_eq(ReplayLog.unit_id_scheme_of(log), ReplayLog.UNIT_IDS_SLOT,
		"and the strict importer carries it through")


func test_a_header_without_the_field_is_a_legacy_recording() -> void:
	var old: Dictionary = ReplayLog.make_log({})
	old.erase("unit_ids")
	var log: Dictionary = ReplayLog.validate(old)
	assert_false(log.is_empty(), "an archived replay still validates")
	assert_eq(ReplayLog.unit_id_scheme_of(log), ReplayLog.UNIT_IDS_LEGACY,
		"a replay recorded before the field existed used the old map-load naming")


func test_an_unknown_naming_value_degrades_to_legacy() -> void:
	var odd: Dictionary = ReplayLog.make_log({})
	odd["unit_ids"] = "something-else"
	assert_eq(ReplayLog.unit_id_scheme_of(ReplayLog.validate(odd)), ReplayLog.UNIT_IDS_LEGACY,
		"an untrusted, unrecognised value never selects a scheme it does not name")


func test_the_battle_names_a_legacy_replays_board_the_old_way() -> void:
	var gwm = GWM.new()
	assert_false(gwm._replay_uses_legacy_unit_ids(), "an ordinary battle is not a legacy replay")
	var legacy: Dictionary = ReplayLog.make_log({})
	legacy.erase("unit_ids")
	gwm._replay_log = ReplayLog.validate(legacy)
	assert_true(gwm._replay_uses_legacy_unit_ids(),
		"a legacy recording's playback keeps the old map-load naming its commands address")
	gwm._replay_log = ReplayLog.validate(ReplayLog.make_log({ "unit_ids": ReplayLog.UNIT_IDS_SLOT }))
	assert_false(gwm._replay_uses_legacy_unit_ids(),
		"a current recording's playback names by owner slot, exactly as it was recorded")
	gwm.free()


# --- The local command stream -------------------------------------------------------

func test_local_commands_draw_a_reproducible_seed_per_command() -> void:
	var a := NetSessionNode.new()
	var b := NetSessionNode.new()
	a.match_rng = MatchRng.new()
	a.match_rng.begin_from_seed(424242)
	b.match_rng = MatchRng.new()
	b.match_rng.begin_from_seed(424242)
	var prev_shared = CombatServices.match_rng

	var ra: RandomNumberGenerator = a.begin_local_command()
	assert_not_null(ra, "with a solo stream a local command gets its own generator")
	assert_eq(CombatServices.match_rng, ra,
		"installed where the apply path installs an applied command's, for its secondary rolls")
	var seed_a1: int = a.take_local_command_seed()
	assert_ne(seed_a1, 0, "and its seed is handed to the recorder")
	assert_eq(a.take_local_command_seed(), 0, "exactly once -- it cannot land on a later command")

	a.begin_local_command()
	var seed_a2: int = a.take_local_command_seed()
	assert_ne(seed_a2, seed_a1, "each command draws a fresh seed")

	b.begin_local_command()
	var seed_b1: int = b.take_local_command_seed()
	assert_eq(seed_b1, seed_a1, "the same match seed yields the same command seeds (reproducible)")

	var twin := RandomNumberGenerator.new()
	twin.seed = seed_a2
	var replayed := RandomNumberGenerator.new()
	replayed.seed = seed_a2
	assert_eq(replayed.randf(), twin.randf(), "a stamped seed re-creates the identical roll sequence")

	CombatServices.match_rng = prev_shared
	a.free()
	b.free()


func test_without_a_solo_stream_nothing_is_touched() -> void:
	var ns := NetSessionNode.new()
	var sentinel := RandomNumberGenerator.new()
	var prev_shared = CombatServices.match_rng
	CombatServices.match_rng = sentinel
	assert_null(ns.begin_local_command(), "no stream -> the caller rolls as it always did")
	assert_eq(CombatServices.match_rng, sentinel, "and the shared generator is left alone")
	assert_eq(ns.take_local_command_seed(), 0, "and nothing is stamped on the recorded command")
	CombatServices.match_rng = prev_shared
	ns.free()


func test_the_local_weather_seed_follows_the_match_seed() -> void:
	var ns := NetSessionNode.new()
	ns.match_rng = MatchRng.new()
	ns.match_rng.begin_from_seed(99)
	var first: int = ns.local_weather_seed()
	assert_eq(ns.local_weather_seed(), first,
		"a local battle's dynamic weather is seeded from its match seed, so a replay re-rolls it")
	ns.match_rng.begin_from_seed(100)
	assert_ne(ns.local_weather_seed(), first, "and a different battle gets a different sky")
	ns.free()
