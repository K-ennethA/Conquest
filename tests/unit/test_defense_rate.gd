extends GutTest

# The DERIVED defense figures behind every base card.
#
# The service stores two counters and nothing else: `attempts` (players who attacked this
# base) and `clears` (players who beat it). "Defended", "defense rate" and every percentage
# the UI prints is arithmetic over those two, done in ONE place --
# CommunityBrowse.defense_stats / defense_percent / defense_label -- so the browse list and
# the My Bases slots can never disagree about the same base.
#
# The case that matters most is 0 attempts. 0/0 is a divide by zero, and the tempting
# "defended 0 of 0 = 100%" is a lie that would badge every freshly published base as
# undefeated. The contract pinned here: no attempts means NO rate (-1.0 sentinel), rendered
# in words as "Not attacked yet".
#
# Pure static functions over a plain Dictionary -- no screen is built, so this suite creates
# no nodes and can never orphan one.

func _counters(attempts: int, clears: int) -> Dictionary:
	return {"id": "b1", "name": "Fort", "type": "challenge", "attempts": attempts, "clears": clears}

# --- the zero case -----------------------------------------------------------

func test_a_base_nobody_attacked_has_no_rate_at_all():
	var stats: Dictionary = CommunityBrowse.defense_stats(_counters(0, 0))

	assert_eq(int(stats["attacked"]), 0, "nobody attacked it")
	assert_eq(int(stats["defended"]), 0, "so it turned nobody away")
	assert_eq(float(stats["rate"]), -1.0, "0/0 is not a rate -- it is the no-data sentinel")

func test_a_base_nobody_attacked_says_so_in_words_never_100_percent():
	var label: String = CommunityBrowse.defense_label(_counters(0, 0))

	assert_eq(label, "Not attacked yet", "an untested base reports that it is untested")
	assert_false(label.contains("100"), "and never claims a perfect record it has not earned")
	assert_eq(CommunityBrowse.defense_percent(_counters(0, 0)), -1,
		"the percent accessor hands back the same sentinel, so no caller can print 100%")

# --- the arithmetic ----------------------------------------------------------

func test_defended_is_attempts_minus_clears():
	var stats: Dictionary = CommunityBrowse.defense_stats(_counters(42, 12))

	assert_eq(int(stats["attacked"]), 42, "42 players attacked")
	assert_eq(int(stats["defended"]), 30, "12 of them cleared it, so 30 were turned away")
	assert_almost_eq(float(stats["rate"]), 30.0 / 42.0, 0.0001, "the rate is defended / attacked")

func test_the_percent_is_the_rate_rounded_to_a_whole_number():
	assert_eq(CommunityBrowse.defense_percent(_counters(42, 12)), 71,
		"30/42 = 71.4% rounds to 71")
	assert_eq(CommunityBrowse.defense_percent(_counters(3, 1)), 67,
		"2/3 = 66.6% rounds up to 67")

func test_a_base_that_never_fell_reads_100_percent_only_once_it_was_actually_attacked():
	assert_eq(CommunityBrowse.defense_percent(_counters(5, 0)), 100,
		"five attacks, five repelled -- this one earned its 100%")

func test_a_base_that_always_fell_reads_zero_not_missing():
	var stats: Dictionary = CommunityBrowse.defense_stats(_counters(4, 4))

	assert_eq(int(stats["defended"]), 0, "every attacker cleared it")
	assert_eq(float(stats["rate"]), 0.0, "0% is a real rate, distinct from the -1 no-data case")
	assert_eq(CommunityBrowse.defense_label(_counters(4, 4)), "Attacked 4   ·   defended 0%",
		"and it is stated plainly rather than hidden")

# --- untrusted counters ------------------------------------------------------

func test_more_clears_than_attempts_is_clamped_rather_than_trusted():
	# Server data is not the client's to believe. Without the clamp this renders a negative
	# defended count and a negative percentage.
	var stats: Dictionary = CommunityBrowse.defense_stats(_counters(2, 9))

	assert_eq(int(stats["defended"]), 0, "defended can never go negative")
	assert_eq(float(stats["rate"]), 0.0, "nor can the rate")

func test_negative_counters_degrade_to_the_no_data_case():
	var stats: Dictionary = CommunityBrowse.defense_stats(_counters(-7, -3))

	assert_eq(int(stats["attacked"]), 0, "a negative attack count is floored at zero")
	assert_eq(float(stats["rate"]), -1.0, "which lands in the honest no-data case")

func test_a_summary_missing_the_counters_entirely_is_not_a_crash():
	var stats: Dictionary = CommunityBrowse.defense_stats({"id": "b1", "name": "Fort"})

	assert_eq(int(stats["attacked"]), 0, "an absent counter reads as zero")
	assert_eq(CommunityBrowse.defense_label({}), "Not attacked yet",
		"and even an empty dictionary renders a sentence")

# --- the card line -----------------------------------------------------------

func test_the_card_line_carries_both_the_count_and_the_rate():
	var label: String = CommunityBrowse.defense_label(_counters(42, 12))

	assert_true(label.contains("42"), "the attack count is on the card")
	assert_true(label.contains("71%"), "and so is the derived defense rate")
