extends GutTest

## POST-MATCH SUMMARY behaviour for [b]GameOverScreen[/b] -- the elimination/damage tallies
## that feed the BATTLE section, the points-gained diff behind REWARDS, the VERSUS block's
## visibility rule, the [MatchPeerInfo] handoff it reads its opponent card from, and the
## absolute arena suppression rule.
##
## GameEvents payloads are fed straight to the screen's PRIVATE handlers
## ([code]_on_unit_eliminated_tally[/code] / [code]_on_damage_dealt_tally[/code]) rather than
## emitted through the real (Unit-typed) signals, mirroring how
## test_challenge_survive_capture.gd drives ChallengeController's own tally handlers
## directly -- a duck-typed double could not satisfy those signals' static Unit
## parameter types anyway.
##
## The screen under test is constructed with .new() and NEVER added to the tree, so
## _ready() (which builds the whole UI and connects GameEvents itself) never runs --
## this suite builds no Controls and needs no scene. The ONE piece of global state it
## touches is MatchPeerInfo's static bag, which is cleared in both before_each and
## after_each (tests/README.md rule 3).

const SCREEN_SCRIPT := preload("res://game/ui/screens/GameOverScreen.gd")

## A minimal duck-typed stand-in for Unit: the tally handler only ever reads
## `owner_player` (or `get_owner_player()`) off whatever it is handed, so that is
## the only shape this needs. Kept local -- see tests/README.md rule 5, this is a
## one-off double for one handler's contract.
class FakeUnit:
	extends RefCounted
	var owner_player: Player = null
	func _init(owner: Player = null) -> void:
		owner_player = owner


## FakeUnit + the two identity hooks the summary reads to NAME a casualty:
## [code]get_display_name()[/code] (Unit's accessor) and a [CharacterResource] carrying the
## portrait's character_id. A deliberate SUBCLASS rather than extra methods on FakeUnit --
## _identify_unit branches on which hooks exist, so the plain double must keep lacking them
## (tests/README.md rule 5).
class FakeNamedUnit:
	extends FakeUnit
	var display_name: String = ""
	var character_resource: CharacterResource = null

	func _init(owner: Player = null, unit_name: String = "", character_id: StringName = &"") -> void:
		super(owner)
		display_name = unit_name
		if not String(character_id).is_empty():
			character_resource = CharacterResource.new()
			character_resource.character_id = character_id

	func get_display_name() -> String:
		return display_name


## A Node-based variant of the same duck type, used ONLY for the "already freed"
## test below -- RefCounted objects cannot be manually .free()'d (Godot raises
## "Can't free a reference"), but a Node can, which is what lets that test prove
## is_instance_valid() catches a freed unit before anything reads off it.
class FakeUnitNode:
	extends Node
	var owner_player: Player = null


## Untyped on purpose (mirrors test_player_profile.gd's `_profile` / test_challenge_
## survive_capture.gd's `_controller`): `SCREEN_SCRIPT.new()` does not statically
## resolve to GameOverScreen, and this suite pokes several of its private members
## directly, which a narrower static type would reject at parse time.
var _screen


func before_each() -> void:
	_screen = SCREEN_SCRIPT.new()
	autofree(_screen)
	# MatchPeerInfo is PROCESS-WIDE static state; start every test from empty.
	MatchPeerInfo.clear()


func after_each() -> void:
	# ...and leave it empty even when a test failed part-way (tests/README.md rule 3).
	MatchPeerInfo.clear()


func _human() -> Player:
	return Player.new(0)


func _enemy(id: int = 1) -> Player:
	var p := Player.new(id)
	p.is_ai = true
	return p


func _neutral(id: int = 2) -> Player:
	var p := Player.new(id)
	p.is_ai = true
	p.is_neutral = true
	return p


# =====================================================================================
#  SIDE CLASSIFICATION
# =====================================================================================

func test_a_player_zero_unit_counts_as_a_friendly_loss() -> void:
	_screen._on_unit_eliminated_tally(FakeUnit.new(_human()), null)
	assert_eq(_screen._friendlies_lost, 1, "player_id 0 is the human side")
	assert_eq(_screen._enemies_defeated, 0, "and must not also count as an enemy kill")


func test_a_non_zero_player_unit_counts_as_an_enemy_defeated() -> void:
	_screen._on_unit_eliminated_tally(FakeUnit.new(_enemy(1)), null)
	assert_eq(_screen._enemies_defeated, 1, "any other player_id is an enemy")
	assert_eq(_screen._friendlies_lost, 0)


func test_friendly_and_enemy_losses_tally_independently() -> void:
	_screen._on_unit_eliminated_tally(FakeUnit.new(_human()), null)
	_screen._on_unit_eliminated_tally(FakeUnit.new(_human()), null)
	_screen._on_unit_eliminated_tally(FakeUnit.new(_enemy(1)), null)
	_screen._on_unit_eliminated_tally(FakeUnit.new(_enemy(2)), null)
	_screen._on_unit_eliminated_tally(FakeUnit.new(_enemy(2)), null)
	assert_eq(_screen._friendlies_lost, 2, "two distinct human units fell")
	assert_eq(_screen._enemies_defeated, 3, "three distinct enemy units fell, across two enemy slots")


func test_a_neutral_owner_counts_toward_neither_tally() -> void:
	_screen._on_unit_eliminated_tally(FakeUnit.new(_neutral()), null)
	assert_eq(_screen._friendlies_lost, 0, "a dormant wild camp is not the human side")
	assert_eq(_screen._enemies_defeated, 0, "and a round is not won by routing it either -- it never counts")


# =====================================================================================
#  DOUBLE-EMIT IDEMPOTENCE
# =====================================================================================

func test_the_same_unit_reported_twice_counts_once() -> void:
	var fallen := FakeUnit.new(_enemy(1))
	_screen._on_unit_eliminated_tally(fallen, null)
	_screen._on_unit_eliminated_tally(fallen, null)
	_screen._on_unit_eliminated_tally(fallen, null)
	assert_eq(_screen._enemies_defeated, 1,
		"a duplicate elimination signal for the same unit must never double-count")


func test_double_emit_is_idempotent_on_both_sides_independently() -> void:
	var ally := FakeUnit.new(_human())
	var foe := FakeUnit.new(_enemy(1))
	_screen._on_unit_eliminated_tally(ally, null)
	_screen._on_unit_eliminated_tally(foe, null)
	_screen._on_unit_eliminated_tally(ally, null)
	_screen._on_unit_eliminated_tally(foe, null)
	assert_eq(_screen._friendlies_lost, 1, "the repeated ally elimination is not re-counted")
	assert_eq(_screen._enemies_defeated, 1, "the repeated enemy elimination is not re-counted")


# =====================================================================================
#  SAFETY: null / freed / ownerless never crashes or miscounts
# =====================================================================================

func test_a_null_unit_is_ignored() -> void:
	_screen._on_unit_eliminated_tally(null, null)
	assert_eq(_screen._friendlies_lost, 0)
	assert_eq(_screen._enemies_defeated, 0)


func test_a_unit_with_no_owner_is_ignored() -> void:
	_screen._on_unit_eliminated_tally(FakeUnit.new(null), null)
	assert_eq(_screen._friendlies_lost, 0)
	assert_eq(_screen._enemies_defeated, 0)


func test_a_freed_unit_is_ignored_rather_than_crashing() -> void:
	var gone := FakeUnitNode.new()
	gone.owner_player = _human()
	gone.free()
	# is_instance_valid() must catch this before anything reads off `gone`.
	_screen._on_unit_eliminated_tally(gone, null)
	assert_eq(_screen._friendlies_lost, 0, "a freed unit is not read, not counted")


# =====================================================================================
#  READ-ONLY DATA HELPERS (null-safe against a bare test harness)
# =====================================================================================

func test_rounds_taken_defaults_to_zero_with_no_live_battle() -> void:
	# No turn system has activated in this bare harness -- TurnSystemManager.
	# active_turn_system is null, and the helper must read that as 0, not error.
	assert_eq(_screen._rounds_taken(), 0, "no active turn system means 0 rounds, not a crash")


func test_points_balance_reads_the_real_playerprofile_autoload() -> void:
	# PlayerProfile is a real autoload in the test harness; the helper must return
	# whatever it reports without erroring, and never go negative (PlayerProfile's
	# own floor).
	assert_gte(_screen._points_balance(), 0, "the balance helper never returns a negative reading")


# =====================================================================================
#  CASUALTY IDENTITY -- the elimination latch records NAMES, not just counts
# =====================================================================================

func test_a_lost_unit_records_its_display_name_and_character_id() -> void:
	_screen._on_unit_eliminated_tally(FakeNamedUnit.new(_human(), "Vineweave", &"vineweave"), null)
	assert_eq(_screen._lost_units.size(), 1, "one fallen ally means one casualty row")
	assert_eq(String(_screen._lost_units[0]["name"]), "Vineweave",
		"the row is named from the unit's own display name")
	assert_eq(String(_screen._lost_units[0]["character_id"]), "vineweave",
		"and carries the character id the portrait lookup needs")


func test_a_defeated_enemy_records_its_name_on_the_enemy_roll_call() -> void:
	_screen._on_unit_eliminated_tally(FakeNamedUnit.new(_enemy(1), "Blightcap", &"blightcap"), null)
	assert_eq(_screen._defeated_units.size(), 1, "one routed enemy means one roll-call entry")
	assert_eq(String(_screen._defeated_units[0]["name"]), "Blightcap",
		"enemies are named on the summary too")
	assert_eq(_screen._lost_units.size(), 0, "and an enemy death is never a casualty of yours")


func test_names_are_recorded_in_the_order_units_fell() -> void:
	_screen._on_unit_eliminated_tally(FakeNamedUnit.new(_human(), "Geode", &"geode"), null)
	_screen._on_unit_eliminated_tally(FakeNamedUnit.new(_human(), "Petalfang", &"petalfang"), null)
	assert_eq(String(_screen._lost_units[0]["name"]), "Geode", "the first to fall is listed first")
	assert_eq(String(_screen._lost_units[1]["name"]), "Petalfang", "then the second")


func test_a_unit_with_no_name_hook_is_recorded_as_unknown_rather_than_dropped() -> void:
	# The plain FakeUnit double deliberately lacks get_display_name/character_resource.
	# A casualty must still be COUNTED and listed -- an unnameable unit is not a missing one.
	_screen._on_unit_eliminated_tally(FakeUnit.new(_human()), null)
	assert_eq(_screen._friendlies_lost, 1, "the loss still counts")
	assert_eq(String(_screen._lost_units[0]["name"]), "Unknown Unit",
		"and is listed under a safe placeholder name")
	assert_eq(String(_screen._lost_units[0]["character_id"]), "",
		"with no character id, so the row falls back to its monogram")


func test_a_double_reported_death_adds_only_one_casualty_row() -> void:
	var fallen := FakeNamedUnit.new(_human(), "Mycothrall", &"mycothrall")
	_screen._on_unit_eliminated_tally(fallen, null)
	_screen._on_unit_eliminated_tally(fallen, null)
	assert_eq(_screen._lost_units.size(), 1,
		"the instance-id latch covers the NAME list exactly as it covers the count")


func test_a_neutral_death_is_named_on_neither_list() -> void:
	_screen._on_unit_eliminated_tally(FakeNamedUnit.new(_neutral(), "Wildcamp", &"wildcamp"), null)
	assert_eq(_screen._lost_units.size(), 0, "a dormant wild camp is not your casualty")
	assert_eq(_screen._defeated_units.size(), 0, "and routing one is not an enemy kill either")


# =====================================================================================
#  DAMAGE TALLY (GameEvents.damage_dealt -> the DEALT / TAKEN figures)
# =====================================================================================

func test_damage_from_a_human_unit_counts_as_damage_dealt() -> void:
	_screen._on_damage_dealt_tally(FakeUnit.new(_human()), FakeUnit.new(_enemy(1)), 12)
	assert_eq(_screen._damage_dealt, 12, "the human swung it, so it is damage dealt")
	assert_eq(_screen._damage_taken, 0, "and none of it was worn by the human side")


func test_damage_onto_a_human_unit_counts_as_damage_taken() -> void:
	_screen._on_damage_dealt_tally(FakeUnit.new(_enemy(1)), FakeUnit.new(_human()), 9)
	assert_eq(_screen._damage_taken, 9, "the human wore it, so it is damage taken")
	assert_eq(_screen._damage_dealt, 0, "and the human dealt none of it")


func test_damage_accumulates_across_events() -> void:
	_screen._on_damage_dealt_tally(FakeUnit.new(_human()), FakeUnit.new(_enemy(1)), 5)
	_screen._on_damage_dealt_tally(FakeUnit.new(_human()), FakeUnit.new(_enemy(1)), 7)
	assert_eq(_screen._damage_dealt, 12, "every hit adds to the running total")


func test_friendly_fire_counts_on_both_lines() -> void:
	# The documented, deliberate caveat: a line attack clipping your own unit genuinely IS
	# both damage you dealt and damage you took, and the summary reports it as both.
	_screen._on_damage_dealt_tally(FakeUnit.new(_human()), FakeUnit.new(_human()), 6)
	assert_eq(_screen._damage_dealt, 6, "you dealt it")
	assert_eq(_screen._damage_taken, 6, "and you took it")


func test_neutral_damage_counts_on_neither_line() -> void:
	_screen._on_damage_dealt_tally(FakeUnit.new(_neutral()), FakeUnit.new(_enemy(1)), 20)
	assert_eq(_screen._damage_dealt, 0, "a neutral camp's swing is not yours")
	assert_eq(_screen._damage_taken, 0, "and the enemy wearing it is not your loss")


func test_non_positive_damage_is_ignored() -> void:
	_screen._on_damage_dealt_tally(FakeUnit.new(_human()), FakeUnit.new(_enemy(1)), 0)
	_screen._on_damage_dealt_tally(FakeUnit.new(_human()), FakeUnit.new(_enemy(1)), -4)
	assert_eq(_screen._damage_dealt, 0, "a zero or negative payload never moves the total")


func test_damage_with_a_null_side_is_ignored_rather_than_crashing() -> void:
	_screen._on_damage_dealt_tally(null, FakeUnit.new(_human()), 8)
	assert_eq(_screen._damage_taken, 8, "the defender side is still read")
	_screen._on_damage_dealt_tally(FakeUnit.new(_human()), null, 3)
	assert_eq(_screen._damage_dealt, 3, "and a null attacker simply contributes nothing")


# =====================================================================================
#  REWARDS -- points gained is a battle-start DIFF, never a live reading
# =====================================================================================

func test_points_gained_is_the_difference_from_the_battle_start_latch() -> void:
	# Hermetic against whatever the real profile holds: the "before" latch is placed a known
	# distance BELOW the live lifetime total, so the diff must be exactly that distance.
	_screen._start_points_total = _screen._points_total() - 40
	assert_eq(_screen.points_gained(), 40, "the reward is the lifetime total's rise this match")


func test_points_gained_is_zero_when_nothing_was_earned() -> void:
	_screen._start_points_total = _screen._points_total()
	assert_eq(_screen.points_gained(), 0, "a battle that paid nothing shows nothing earned")


func test_points_gained_never_reports_a_negative_reward() -> void:
	# A profile reset (or any unexpected drop) must read as "earned nothing", not "-500".
	_screen._start_points_total = _screen._points_total() + 500
	assert_eq(_screen.points_gained(), 0, "the reward figure is floored at zero")


func test_latching_battle_start_records_the_current_lifetime_total() -> void:
	_screen._start_points_total = -1
	_screen._latch_battle_start()
	assert_eq(_screen._start_points_total, _screen._points_total(),
		"the 'before' figure is sampled from the live profile at battle start")
	assert_eq(_screen.points_gained(), 0, "so immediately after latching, nothing has been earned yet")


func test_latching_battle_start_samples_the_live_session_rather_than_assuming() -> void:
	# Seeded with deliberately WRONG values first, so a latch that quietly did nothing would
	# fail. Compared against NetSession's own answer rather than a hard-coded false: whether
	# the test process happens to hold a transport peer is not this screen's contract --
	# "the flags come from NetSession, sampled at battle start" is.
	_screen._was_networked_match = not NetSession.is_networked_match()
	_screen._local_slot = 99
	_screen._latch_battle_start()
	assert_eq(_screen._was_networked_match, NetSession.is_networked_match(),
		"the networked flag is sampled off NetSession")
	assert_eq(_screen._local_slot, NetSession.local_slot(),
		"and so is the roster seat we held")


# =====================================================================================
#  VERSUS BLOCK VISIBILITY (pure decision helper)
# =====================================================================================

func test_versus_block_is_shown_for_a_networked_match() -> void:
	assert_true(GameOverScreen.should_show_versus_block({ "networked": true }),
		"a networked versus match reports its opponent")


func test_versus_block_is_hidden_for_a_solo_match() -> void:
	assert_false(GameOverScreen.should_show_versus_block({ "networked": false }),
		"a solo/hotseat battle has no remote opponent to report")


func test_versus_block_is_hidden_when_nothing_is_known() -> void:
	assert_false(GameOverScreen.should_show_versus_block({}),
		"an empty context defaults to hiding the block, never to guessing")


func test_versus_block_is_hidden_for_an_arena_round_even_if_networked() -> void:
	assert_false(GameOverScreen.should_show_versus_block({ "networked": true, "arena": true }),
		"an arena round is never summarised by this screen at all")


func test_versus_context_reports_the_battle_start_latches() -> void:
	_screen._was_networked_match = true
	_screen._arena_run_at_start = false
	var ctx: Dictionary = _screen.versus_context()
	assert_true(bool(ctx["networked"]), "the context carries the latched networked flag")
	assert_false(bool(ctx["arena"]), "and the latched arena flag")
	assert_true(GameOverScreen.should_show_versus_block(ctx),
		"which together decide the block is shown")


func test_the_versus_latch_survives_the_opponent_leaving() -> void:
	# The whole point of latching at battle START: a forfeit win tears the session down, so a
	# live is_networked_match() query at reveal time would read false and silently drop the
	# block in exactly the case it matters most.
	_screen._was_networked_match = true
	_screen._on_opponent_forfeited(1)
	assert_true(GameOverScreen.should_show_versus_block(_screen.versus_context()),
		"the block still shows after the opponent has gone")
	assert_true(_screen._opponent_forfeited, "and the forfeit subtitle is armed")


func test_a_dropped_connection_reads_as_a_forfeit() -> void:
	_screen._on_opponent_left()
	assert_true(_screen._opponent_forfeited,
		"leaving a live match is a loss either way, so it reads the same on the summary")


# =====================================================================================
#  OPPONENT CARD (MatchPeerInfo, exchanged at match START)
# =====================================================================================

func test_peer_info_round_trips_through_the_static_holder() -> void:
	MatchPeerInfo.set_peer_info(1, { "name": "Rival", "rank_name": "Veteran", "lifetime_points": 1800 })
	var stored: Dictionary = MatchPeerInfo.get_peer_info(1)
	assert_eq(String(stored["name"]), "Rival", "the announced name is kept")
	assert_eq(String(stored["rank_name"]), "Veteran", "so is the announced rank")
	assert_eq(int(stored["lifetime_points"]), 1800, "and the lifetime points figure")


func test_peer_info_for_an_unknown_slot_is_empty() -> void:
	assert_true(MatchPeerInfo.get_peer_info(3).is_empty(),
		"a slot that never announced returns nothing to render")


func test_clearing_peer_info_forgets_every_peer() -> void:
	MatchPeerInfo.set_peer_info(1, { "name": "Rival" })
	MatchPeerInfo.set_peer_info(2, { "name": "Other" })
	MatchPeerInfo.clear()
	assert_eq(MatchPeerInfo.peer_count(), 0, "a new lobby starts with no opponent on record")
	assert_true(MatchPeerInfo.get_peer_info(1).is_empty(),
		"and the previous match's opponent can never be read back")


func test_peer_info_normalises_an_untrusted_payload() -> void:
	MatchPeerInfo.set_peer_info(1, { "name": "   ", "lifetime_points": -50 })
	var stored: Dictionary = MatchPeerInfo.get_peer_info(1)
	assert_eq(String(stored["name"]), MatchPeerInfo.DEFAULT_NAME,
		"a blank announced name falls back rather than rendering an empty row")
	assert_eq(int(stored["lifetime_points"]), 0, "and a negative points claim is floored at zero")
	assert_eq(String(stored["rank_name"]), "", "an unannounced rank stays empty (no chip is drawn)")


func test_peer_info_survives_a_payload_of_the_wrong_types() -> void:
	# Lobby payloads are untrusted peer input; a malformed one must degrade, never error.
	MatchPeerInfo.set_peer_info(1, { "name": 7, "lifetime_points": [1, 2, 3] })
	var stored: Dictionary = MatchPeerInfo.get_peer_info(1)
	assert_eq(int(stored["lifetime_points"]), 0, "a non-scalar points claim reads as zero")
	assert_false(String(stored["name"]).is_empty(), "and the row still has something to print")


func test_get_peer_info_returns_a_copy_not_the_stored_record() -> void:
	MatchPeerInfo.set_peer_info(1, { "name": "Rival", "lifetime_points": 100 })
	var first: Dictionary = MatchPeerInfo.get_peer_info(1)
	first["name"] = "Tampered"
	assert_eq(String(MatchPeerInfo.get_peer_info(1)["name"]), "Rival",
		"mutating a returned card must not edit the stored one")


func test_the_opponent_card_is_the_peer_that_is_not_us() -> void:
	MatchPeerInfo.set_peer_info(0, { "name": "Host" })
	MatchPeerInfo.set_peer_info(1, { "name": "Client" })
	_screen._local_slot = 0
	assert_eq(String(_screen._opponent_info()["name"]), "Client",
		"our own slot is skipped when picking the opponent to show")
	_screen._local_slot = 1
	assert_eq(String(_screen._opponent_info()["name"]), "Host",
		"and the answer follows whichever seat we held")


func test_the_opponent_card_is_empty_when_nobody_announced() -> void:
	_screen._local_slot = 0
	assert_true(_screen._opponent_info().is_empty(),
		"with no announcement and no roster, the row falls back to its default name")


# =====================================================================================
#  ARENA SUPPRESSION (absolute -- the run's own results screen is arena's summary)
# =====================================================================================

func test_an_arena_round_never_reveals_this_screen() -> void:
	_screen._arena_run_at_start = true
	_screen.show_result(SCREEN_SCRIPT.OUTCOME_VICTORY, "VICTORY", "All enemies defeated!")
	assert_false(_screen.is_shown(),
		"an arena round resolves into the Arena loop; this screen must stay down between rounds")


func test_the_arena_suppression_flag_follows_the_battle_start_latch() -> void:
	_screen._arena_run_at_start = true
	assert_true(_screen._arena_suppressed(), "a battle that started inside an arena run is suppressed")
	_screen._arena_run_at_start = false
	assert_false(_screen._arena_suppressed(), "an ordinary battle is not")


func test_a_bare_harness_latches_no_arena_run() -> void:
	_screen._arena_run_at_start = true
	_screen._latch_battle_start()
	assert_false(_screen._arena_run_at_start,
		"with no reachable ArenaController the latch reads 'not an arena battle', not a crash")
