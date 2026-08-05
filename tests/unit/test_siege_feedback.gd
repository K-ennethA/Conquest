extends GutTest

## The PURE rules behind Siege's HUD: the respawn row's wording, the capture alarm's
## wording, the mode-aware game-over line, and which mode strings / which maps count as
## Siege.
##
## Everything here is a static or a resource read, so it needs no scene and no autoload.
## What a player can actually SEE is a separate suite -- `integration/test_siege_mode_entry.gd`
## drives the real pickers and `integration/test_siege_battle_feedback.gd` mounts the real
## battle HUD -- because this project has twice shipped a HUD element that passed a
## string-reading suite while the screen was wrong.

const MatchSetupScript := preload("res://menus/MatchSetup.gd")


# =====================================================================================
#  The respawn row's wording
# =====================================================================================

func _entry(display: String, turns: int) -> Dictionary:
	return {"name": display, "turns": turns}


func test_an_empty_queue_draws_nothing_at_all() -> void:
	assert_eq(SiegeFeedback.row_text([]), "",
			"nobody is down, so the row draws NO text -- which is what hides it, and a "
			+ "hidden row costs the left column neither height nor separation")


func test_one_fallen_unit_is_named_and_clocked() -> void:
	assert_eq(SiegeFeedback.row_text([_entry("Petalfang", 2)]),
			SiegeFeedback.PREFIX + "Petalfang respawns in 2 turns",
			"the row names who went down and says when they are back")


func test_the_last_turn_before_a_comeback_is_singular() -> void:
	# Not a nicety: "respawns in 1 turns" is on screen for the one beat a player is most
	# likely to be reading this row.
	assert_eq(SiegeFeedback.respawn_phrase(1), "respawns in 1 turn",
			"one turn left reads as one turn, not '1 turns'")
	assert_eq(SiegeFeedback.respawn_phrase(2), "respawns in 2 turns",
			"and two still reads as two")
	assert_eq(SiegeFeedback.respawn_phrase(0), "respawns now",
			"a clock that has run out says so rather than counting into the negatives")


func test_extra_casualties_are_counted_never_crammed_in() -> void:
	var entries: Array = [_entry("Petalfang", 2), _entry("Geode", 1), _entry("Blightcap", 2)]
	var line: String = SiegeFeedback.row_text(entries)
	gut.p("row line : \"%s\"" % line)
	assert_true(line.begins_with(SiegeFeedback.PREFIX + "Petalfang"),
			"the first to fall is the one shown")
	assert_true(line.contains("+2 more"),
			"the rest are counted -- the row is a fixed height and a second line would "
			+ "spend 24px the left column does not have")


func test_the_tooltip_lists_everyone_only_when_there_is_more_than_one() -> void:
	assert_eq(SiegeFeedback.tooltip_text_for([_entry("Petalfang", 2)]), "",
			"one casualty needs no tooltip repeating the line above it")
	var tip: String = SiegeFeedback.tooltip_text_for(
			[_entry("Petalfang", 2), _entry("Geode", 1)])
	assert_true(tip.contains("Petalfang respawns in 2 turns"), "the row's own line is listed")
	assert_true(tip.contains("Geode respawns in 1 turn"),
			"and so is the one that did not fit on the row")


func test_every_character_the_row_can_emit_is_one_the_font_can_draw() -> void:
	# The bug this guards has shipped in this project twice: a glyph the theme font has no
	# entry for renders as an empty tofu box, permanently, on every battle HUD. The measured
	# drawable set is the probe table in `unit/test_status_feedback.gd`.
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "there is a font to probe")
	if font == null:
		return
	var emitted: String = SiegeFeedback.PREFIX \
			+ (SiegeFeedback.MORE_SUFFIX % 2) \
			+ SiegeFeedback.respawn_phrase(1) \
			+ SiegeFeedback.respawn_phrase(2) \
			+ SiegeFeedback.respawn_phrase(0) \
			+ SiegeFeedback.ANNOUNCE_ENEMY_CAPTURE \
			+ SiegeFeedback.ANNOUNCE_ALLY_CAPTURE \
			+ SiegeFeedback.ANNOUNCE_ENEMY_SUB \
			+ SiegeFeedback.ANNOUNCE_ALLY_SUB \
			+ SiegeFeedback.tooltip_text_for([_entry("A", 2), _entry("B", 1)])
	for i in emitted.length():
		var code: int = emitted.unicode_at(i)
		if code == 10:  # the tooltip's newlines
			continue
		assert_true(font.has_char(code),
				"the font can draw '%s' (U+%04X) -- an undrawable character here is a "
				% [emitted[i], code] + "literal box in the battle HUD")


# =====================================================================================
#  The capture alarm
# =====================================================================================

func test_no_capture_means_no_alarm() -> void:
	assert_eq(SiegeFeedback.alarm_text({"capturing": false, "by_enemy": true}), "",
			"nothing is being captured, so nothing is announced")
	assert_eq(SiegeFeedback.alarm_text({}), "",
			"and an empty status reads as 'not capturing' rather than guessing")


func test_the_enemy_taking_your_base_is_the_line_that_names_the_stakes() -> void:
	assert_eq(SiegeFeedback.alarm_text({"capturing": true, "by_enemy": true}),
			SiegeFeedback.ANNOUNCE_ENEMY_CAPTURE,
			"the alarm says whose base is being taken, because that is the whole point of it")
	assert_eq(SiegeFeedback.alarm_text({"capturing": true, "by_enemy": false}),
			SiegeFeedback.ANNOUNCE_ALLY_CAPTURE,
			"and the friendly capture reads as the opportunity it is")


# =====================================================================================
#  Mode identity
# =====================================================================================

func test_both_siege_variants_are_siege() -> void:
	assert_true(MatchConfigPanel.is_siege_mode(MatchConfigPanel.MODE_SIEGE),
			"solo Siege is a siege match")
	assert_true(MatchConfigPanel.is_siege_mode(MatchConfigPanel.MODE_SIEGE_LOCAL),
			"and so is the hot-seat variant -- callers ask this instead of comparing "
			+ "against two strings")
	assert_false(MatchConfigPanel.is_siege_mode(MatchConfigPanel.MODE_SKIRMISH),
			"skirmish is not")
	assert_false(MatchConfigPanel.is_siege_mode(MatchConfigPanel.MODE_LOCAL),
			"and neither is plain local versus")


# =====================================================================================
#  Which map Siege opens on
# =====================================================================================

func _map(map_type: String, conditions: Array[String], tags: Array[String] = []) -> MapResource:
	var m := MapResource.new()
	m.map_name = "Fixture"
	m.map_type = map_type
	m.victory_conditions = conditions
	m.tags = tags
	return m


func test_a_map_declaring_a_base_capture_reads_as_a_siege_map() -> void:
	# This is the fallback path -- what the picker uses when the build has the MAP but not
	# yet the mode controller that would name it. The string matched is the CaptureBase
	# objective's own, i.e. the same text WinConditionLibrary compiles and the objective
	# banner draws.
	var m := _map("Skirmish", ["Capture Enemy Base"] as Array[String])
	assert_true(MatchSetupScript._is_siege_map(m),
			"a map whose authored objective is taking a base is a siege map")


func test_the_catalogs_own_classification_is_enough_on_its_own() -> void:
	assert_true(MatchSetupScript._is_siege_map(_map("Siege", ["Eliminate All Enemies"] as Array[String])),
			"map_type Siege names it outright")
	assert_true(MatchSetupScript._is_siege_map(
			_map("Skirmish", ["Eliminate All Enemies"] as Array[String], ["siege"] as Array[String])),
			"and so does a siege tag")


func test_an_ordinary_map_is_not_mistaken_for_a_siege_map() -> void:
	assert_false(MatchSetupScript._is_siege_map(
			_map("Skirmish", ["Eliminate All Enemies", "Defeat Boss"] as Array[String])),
			"clearing the field is not capturing a base")
	assert_false(MatchSetupScript._is_siege_map(
			_map("Skirmish", ["Destroy Enemy Base"] as Array[String])),
			"and DESTROYING a base is a different objective from CAPTURING one -- the "
			+ "existing base-assault maps must not be hijacked as Siege defaults")
	assert_false(MatchSetupScript._is_siege_map(null),
			"a map this build could not read is not a siege map either")


# =====================================================================================
#  The post-match line
# =====================================================================================

func test_a_siege_is_decided_by_a_base_not_by_a_body_count() -> void:
	assert_eq(GameOverScreen.outcome_subtitle(
				"siege", GameOverScreen.OUTCOME_VICTORY, GameOverScreen.SUBTITLE_VICTORY),
			GameOverScreen.SUBTITLE_SIEGE_VICTORY,
			"winning a Siege is taking their base, not clearing the field")
	assert_eq(GameOverScreen.outcome_subtitle(
				"siege", GameOverScreen.OUTCOME_DEFEAT, GameOverScreen.SUBTITLE_DEFEAT),
			GameOverScreen.SUBTITLE_SIEGE_DEFEAT,
			"and losing one is your base falling -- a player whose squad is still standing "
			+ "must not be told their forces have fallen")


func test_the_mode_id_is_matched_loosely_so_its_spelling_stays_the_modes_business() -> void:
	for id in ["Siege", "siege_push", "SIEGE"]:
		assert_eq(GameOverScreen.outcome_subtitle(
					id, GameOverScreen.OUTCOME_VICTORY, GameOverScreen.SUBTITLE_VICTORY),
				GameOverScreen.SUBTITLE_SIEGE_VICTORY,
				"'%s' resolves to the siege line" % id)


func test_every_other_mode_gets_exactly_the_card_it_always_got() -> void:
	assert_eq(GameOverScreen.outcome_subtitle(
				"", GameOverScreen.OUTCOME_VICTORY, GameOverScreen.SUBTITLE_VICTORY),
			GameOverScreen.SUBTITLE_VICTORY,
			"no live mode controller -- the shipped default, unchanged")
	assert_eq(GameOverScreen.outcome_subtitle(
				"arena", GameOverScreen.OUTCOME_DEFEAT, GameOverScreen.SUBTITLE_DEFEAT),
			GameOverScreen.SUBTITLE_DEFEAT,
			"and a mode with nothing of its own to say falls straight through")
