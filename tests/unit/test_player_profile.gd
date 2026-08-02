extends GutTest

## Points economy, achievement unlocking and persistence for the [b]PlayerProfile[/b]
## autoload. The class is exercised as a PLAIN INSTANCE (never added to the tree, so its
## _ready signal wiring and the toast layer stay dormant) pointed at TEMP user:// paths --
## both for its own profile.json and for the campaign / challenge / maps files the
## retroactive achievement sweep reads. Nothing here touches the player's real save data.
##
## Covers: the spendable-balance floor, rank thresholds + in-rank progress, achievement
## idempotence, the RETROACTIVE sweep (a campaign cleared before this system shipped still
## unlocks on load), a save/load file round-trip, and the skin ownership/equip API the
## cosmetics economy codes against.

const PROFILE := preload("res://game/profile/PlayerProfile.gd")

const TEMP_PROFILE_PATH := "user://test_player_profile.json"
const TEMP_CAMPAIGN_PATH := "user://test_profile_campaign.json"
const TEMP_CHALLENGE_PATH := "user://test_profile_challenges.json"
const TEMP_MAPS_DIR := "user://test_profile_maps/"

var _profile


func before_each() -> void:
	_clean()
	_profile = _make_profile()


func after_each() -> void:
	_clean()


# --- Fixture helpers --------------------------------------------------------

func _make_profile():
	var p = PROFILE.new()
	autofree(p)
	p.set_profile_path(TEMP_PROFILE_PATH)
	p.set_source_paths(TEMP_CAMPAIGN_PATH, TEMP_CHALLENGE_PATH, TEMP_MAPS_DIR)
	p.load_profile()
	return p


func _clean() -> void:
	for path in [TEMP_PROFILE_PATH, TEMP_CAMPAIGN_PATH, TEMP_CHALLENGE_PATH]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(TEMP_MAPS_DIR):
		DirAccess.remove_absolute(TEMP_MAPS_DIR)


func _write_json(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(file, "test fixture could write %s" % path)
	if file == null:
		return
	file.store_string(JSON.stringify(data))
	file.close()


## A campaign progress file with the first [param count] chapters marked cleared.
func _write_campaign_progress(count: int) -> void:
	var data: Dictionary = {}
	for i in range(count):
		var cid: String = String(CampaignData.get_chapter(i).get("id", ""))
		if cid.is_empty():
			continue
		data[cid] = { "cleared": true, "best_turns": 5 }
	_write_json(TEMP_CAMPAIGN_PATH, data)


# =====================================================================================
#  POINTS
# =====================================================================================

func test_a_fresh_profile_starts_empty() -> void:
	assert_eq(_profile.get_points(), 0, "no points before anything is earned")
	assert_eq(_profile.get_points_total(), 0, "no lifetime points either")
	assert_eq(_profile.get_rank_name(), "Recruit", "everyone starts as a Recruit")
	assert_eq(_profile.unlocked_achievement_count(), 0, "nothing unlocked on a blank profile")


func test_granting_points_raises_balance_and_lifetime() -> void:
	_profile.grant_points(120, "test")
	assert_eq(_profile.get_points(), 120, "the balance holds what was granted")
	assert_eq(_profile.get_points_total(), 120, "lifetime tracks the same grant")


func test_non_positive_grants_are_ignored() -> void:
	_profile.grant_points(0, "test")
	_profile.grant_points(-50, "test")
	assert_eq(_profile.get_points_total(), 0, "zero and negative grants change nothing")


func test_spending_deducts_from_the_balance_but_not_the_rank() -> void:
	_profile.grant_points(400, "test")
	assert_true(_profile.spend_points(150, "skin_x"), "an affordable spend succeeds")
	assert_eq(_profile.get_points(), 250, "the balance drops by what was spent")
	assert_eq(_profile.get_points_total(), 400, "spending never lowers lifetime points")


func test_spending_more_than_the_balance_fails_and_changes_nothing() -> void:
	_profile.grant_points(100, "test")
	assert_false(_profile.spend_points(101, "too_dear"), "an unaffordable spend is refused")
	assert_eq(_profile.get_points(), 100, "a refused spend leaves the balance intact")
	assert_false(_profile.spend_points(0, "nothing"), "a zero spend is refused")
	assert_false(_profile.spend_points(-10, "negative"), "a negative spend is refused")
	assert_eq(_profile.get_points(), 100, "still intact after the bad spends")


func test_the_balance_floors_at_zero() -> void:
	_profile.grant_points(50, "test")
	assert_true(_profile.spend_points(50, "all_of_it"))
	assert_eq(_profile.get_points(), 0, "spending everything lands exactly on zero")
	assert_false(_profile.spend_points(1, "overdraft"), "there is no overdraft")
	assert_eq(_profile.get_points(), 0, "the balance can never go negative")


func test_points_changed_fires_on_grant_and_spend() -> void:
	watch_signals(_profile)
	_profile.grant_points(200, "test")
	_profile.spend_points(75, "test")
	assert_signal_emit_count(_profile, "points_changed", 2, "one emit per successful change")
	assert_signal_emitted_with_parameters(_profile, "points_changed", [125], 1)


# =====================================================================================
#  RANK LADDER
# =====================================================================================

func test_rank_thresholds_climb_in_order() -> void:
	assert_eq(RankLadder.rank_for(0), "Recruit")
	assert_eq(RankLadder.rank_for(499), "Recruit", "one short of the threshold does not promote")
	assert_eq(RankLadder.rank_for(500), "Soldier", "the threshold itself promotes")
	assert_eq(RankLadder.rank_for(1500), "Veteran")
	assert_eq(RankLadder.rank_for(3500), "Knight")
	assert_eq(RankLadder.rank_for(7000), "Champion")
	assert_eq(RankLadder.rank_for(12000), "Warlord")
	assert_eq(RankLadder.rank_for(20000), "Mythic")
	assert_eq(RankLadder.rank_for(999999), "Mythic", "Mythic is the ceiling")


func test_next_threshold_and_points_to_next() -> void:
	assert_eq(RankLadder.next_threshold(0), 500, "a Recruit climbs toward Soldier")
	assert_eq(RankLadder.points_to_next(300), 200, "200 more points to Soldier")
	assert_eq(RankLadder.next_threshold(20000), -1, "no tier above Mythic")
	assert_eq(RankLadder.points_to_next(20000), 0, "nothing left to climb at the top")


func test_progress_in_rank_spans_the_current_tier() -> void:
	assert_almost_eq(RankLadder.progress_in_rank(0), 0.0, 0.001, "at a tier floor, progress is 0")
	assert_almost_eq(RankLadder.progress_in_rank(250), 0.5, 0.001, "halfway from 0 to 500")
	assert_almost_eq(RankLadder.progress_in_rank(1000), 0.5, 0.001, "halfway from 500 to 1500")
	assert_almost_eq(RankLadder.progress_in_rank(25000), 1.0, 0.001, "the top tier reads full")


func test_profile_rank_follows_lifetime_points_not_the_balance() -> void:
	_profile.grant_points(1600, "test")
	assert_eq(_profile.get_rank_name(), "Veteran", "1600 lifetime points is Veteran")
	assert_true(_profile.spend_points(1600, "spree"), "spend the lot")
	assert_eq(_profile.get_points(), 0, "balance emptied")
	assert_eq(_profile.get_rank_name(), "Veteran", "buying skins must never demote you")


# =====================================================================================
#  ACHIEVEMENTS
# =====================================================================================

func test_a_win_unlocks_first_victory_once() -> void:
	watch_signals(_profile)
	_profile.notify_mode_win("skirmish", {})
	assert_true(_profile.has_achievement("first_victory"), "the first win unlocks First Blood")
	assert_signal_emit_count(_profile, "achievement_unlocked", 1, "exactly one unlock fired")
	assert_false(_profile.achievement_date("first_victory").is_empty(), "an unlock is dated")


func test_achievement_unlocks_are_idempotent() -> void:
	_profile.notify_mode_win("skirmish", {})
	var stamped: String = _profile.achievement_date("first_victory")
	var unlocked_after_first: int = _profile.unlocked_achievement_count()

	watch_signals(_profile)
	# Force several more sweeps: more wins, a grant, and a fresh load of the same file.
	_profile.notify_battle_result("skirmish", true, {})
	_profile.grant_points(10, "test")
	_profile.load_profile()
	assert_signal_emit_count(_profile, "achievement_unlocked", 0, "an unlocked achievement never re-fires")
	assert_eq(_profile.achievement_date("first_victory"), stamped, "the original unlock date is kept")
	assert_eq(_profile.unlocked_achievement_count(), unlocked_after_first, "no phantom extra unlocks")


func test_one_battle_records_one_result() -> void:
	_profile.notify_mode_win("skirmish", {})
	_profile.notify_mode_win("skirmish", {})
	_profile.notify_battle_result("skirmish", true, {})
	assert_eq(_profile.get_stat("battles_won"), 1, "a battle is decided once, however many hooks fire")
	assert_eq(_profile.get_points_total(), 50, "and it pays out once")


func test_locked_achievements_stay_locked() -> void:
	_profile.notify_mode_win("skirmish", {})
	assert_false(_profile.has_achievement("win_10"), "one win is not ten")
	assert_false(_profile.has_achievement("campaign_complete"), "no campaign progress on disk")
	assert_true(_profile.achievement_date("win_10").is_empty(), "a locked achievement has no date")


func test_retroactive_sweep_unlocks_a_campaign_cleared_before_this_system() -> void:
	# Every chapter already cleared on disk, but a blank profile that has never seen a hook.
	_write_campaign_progress(CampaignData.count())
	var fresh = _make_profile()
	assert_true(fresh.has_achievement("first_campaign_chapter"), "past chapter clears count")
	assert_true(fresh.has_achievement("campaign_complete"), "a finished campaign unlocks on load")
	assert_true(fresh.has_achievement("defeat_eldroot"), "clearing the final chapter fells Eldroot")


func test_partial_campaign_does_not_unlock_the_full_clear() -> void:
	_write_campaign_progress(1)
	var fresh = _make_profile()
	assert_true(fresh.has_achievement("first_campaign_chapter"), "one chapter is one chapter")
	assert_false(fresh.has_achievement("campaign_complete"), "one of four is not the campaign")
	assert_false(fresh.has_achievement("defeat_eldroot"), "the final chapter is still standing")


func test_replaying_one_chapter_never_counts_as_a_full_clear() -> void:
	_write_campaign_progress(1)
	var fresh = _make_profile()
	# The controller hook fires again and again for the SAME chapter (a replay). The full-clear
	# achievement must read the distinct on-disk record, not the tally of campaign wins.
	for _i in range(CampaignData.count() + 3):
		fresh.begin_battle()  # each replay is its own battle
		fresh.notify_mode_win("campaign", { "first_clear": true })
	assert_false(fresh.has_achievement("campaign_complete"), "grinding chapter 1 is not a full clear")


func test_retroactive_sweep_unlocks_a_past_challenge_win() -> void:
	_write_json(TEMP_CHALLENGE_PATH, { "abc123": { "won": true, "best_turns": 7 } })
	var fresh = _make_profile()
	assert_true(fresh.has_achievement("first_challenge_win"), "a past challenge win counts")


func test_map_saves_count_distinct_maps_not_save_presses() -> void:
	assert_eq(_profile.get_stat("maps_created"), 0, "no maps yet")
	_profile.notify_map_saved()
	assert_true(_profile.has_achievement("first_map_created"), "saving a map unlocks Cartographer")
	var after_first: int = _profile.get_stat("maps_created")
	for _i in range(5):
		_profile.notify_map_saved()
	assert_eq(_profile.get_stat("maps_created"), after_first,
		"re-saving the same map does not invent new maps")


func test_collector_unlocks_at_five_owned_skins() -> void:
	for n in range(4):
		_profile.add_skin("skin_%d" % n)
	assert_false(_profile.has_achievement("collector_5_skins"), "four skins is not a collection")
	_profile.add_skin("skin_4")
	assert_true(_profile.has_achievement("collector_5_skins"), "the fifth skin unlocks Collector")


# =====================================================================================
#  SKIN API
# =====================================================================================

func test_skin_ownership_round_trip() -> void:
	assert_false(_profile.owns_skin("ember_knight"), "nothing owned to begin with")
	_profile.add_skin("ember_knight")
	assert_true(_profile.owns_skin("ember_knight"), "an added skin is owned")
	assert_eq(_profile.get_owned_skins().size(), 1, "one skin on the shelf")

	_profile.add_skin("ember_knight")
	assert_eq(_profile.get_owned_skins().size(), 1, "adding the same skin twice is idempotent")
	_profile.add_skin("")
	assert_eq(_profile.get_owned_skins().size(), 1, "an empty id is ignored")


func test_get_owned_skins_returns_a_copy() -> void:
	_profile.add_skin("a")
	var list: Array = _profile.get_owned_skins()
	list.append("smuggled_in")
	assert_eq(_profile.get_owned_skins().size(), 1, "mutating the returned list cannot grant skins")


func test_equipping_and_clearing_a_skin() -> void:
	assert_eq(_profile.get_equipped_skin("frostbloom"), "", "no skin equipped means the default look")
	_profile.equip_skin("frostbloom", "frostbloom_gold")
	assert_eq(_profile.get_equipped_skin("frostbloom"), "frostbloom_gold", "the skin is equipped")
	assert_eq(_profile.get_equipped_skin("cinderpup"), "", "other characters are untouched")

	_profile.equip_skin("frostbloom", "")
	assert_eq(_profile.get_equipped_skin("frostbloom"), "", "an empty id clears back to default")

	_profile.equip_skin("", "orphan_skin")
	assert_eq(_profile.get_equipped_skin(""), "", "an empty character id is ignored")


# =====================================================================================
#  PERSISTENCE
# =====================================================================================

func test_save_load_round_trip() -> void:
	_profile.grant_points(900, "test")
	_profile.spend_points(250, "skin")
	_profile.add_skin("ember_knight")
	_profile.equip_skin("frostbloom", "frostbloom_gold")
	_profile.notify_mode_win("skirmish", {})
	_profile.save_now()

	var reloaded = _make_profile()
	assert_eq(reloaded.get_points_total(), 950, "lifetime points persisted (900 + the 50 win)")
	assert_eq(reloaded.get_points(), 700, "the spend persisted too")
	assert_eq(reloaded.get_stat("battles_won"), 1, "stats persisted")
	assert_true(reloaded.owns_skin("ember_knight"), "owned skins persisted")
	assert_eq(reloaded.get_equipped_skin("frostbloom"), "frostbloom_gold", "equipped skins persisted")
	assert_true(reloaded.has_achievement("first_victory"), "unlocked achievements persisted")


func test_a_missing_file_loads_as_a_blank_profile() -> void:
	assert_false(FileAccess.file_exists(TEMP_PROFILE_PATH), "no file was written yet")
	var fresh = _make_profile()
	assert_eq(fresh.get_points(), 0, "a missing profile reads as zero, not an error")
	assert_eq(fresh.get_stat("battles_won"), 0)
	assert_eq(fresh.get_owned_skins().size(), 0)


func test_a_corrupt_file_loads_as_a_blank_profile() -> void:
	var file: FileAccess = FileAccess.open(TEMP_PROFILE_PATH, FileAccess.WRITE)
	assert_not_null(file, "test fixture could write the corrupt file")
	if file == null:
		return
	file.store_string("{ this is not json ")
	file.close()
	var fresh = _make_profile()
	assert_eq(fresh.get_points_total(), 0, "unreadable JSON degrades to a blank profile")
	assert_eq(fresh.get_rank_name(), "Recruit")


func test_a_partial_file_is_filled_with_defaults() -> void:
	# An older profile written before some stat keys existed must still read cleanly.
	_write_json(TEMP_PROFILE_PATH, { "points_total": 600 })
	var fresh = _make_profile()
	assert_eq(fresh.get_points_total(), 600, "the stored field is kept")
	assert_eq(fresh.get_points(), 600, "a missing points_spent reads as zero")
	assert_eq(fresh.get_stat("arena_rounds_won"), 0, "missing stat keys default to zero")
	assert_eq(fresh.get_rank_name(), "Soldier", "the rank still derives correctly")
