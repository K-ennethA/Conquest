extends GutTest

## The OBJECTIVE line's wording, and the live phrasing the win conditions supply it.
##
## Two halves, both pure:
##
##   1. [ObjectiveBanner]'s static text assembly -- which objective is shown, how the
##      others are counted, what a battle with no resolvable objective falls back to;
##   2. the additive [method WinCondition.describe_progress] surface -- the boss the
##      objective is actually waiting on, and the turns still to hold.
##
## Nothing here builds a Node. The banner as it is DRAWN (mounted in the real
## GameUILayout, measured against the turn chip and the action banner, counting down on
## real turn ends) is pinned in `integration/test_battle_objective_banner.gd`.


## A duck-typed enemy boss, exactly the shape DefeatBoss reads: a `team`, an `hp`, a bare
## `is_boss` flag and a `display_name`. Deliberately local (tests/README rule 5) -- the
## shared ObjectiveUnit double carries neither boss-ness nor a display name, and adding
## them would reroute every win-condition suite that uses it.
##
## Inner classes are RefCounted, so nothing here can orphan.
class BossUnit:
	var team: int = 1
	var hp: int = 40
	var is_boss: bool = true
	var display_name: String = "Eldroot the Hollow Crown"

	func _init(p_team: int = 1, p_hp: int = 40, p_name: String = "Eldroot the Hollow Crown") -> void:
		team = p_team
		hp = p_hp
		display_name = p_name


## A rank-and-file unit on the same duck-typed shape: no boss flag, no name.
class GruntUnit:
	var team: int = 1
	var hp: int = 12
	var is_boss: bool = false

	func _init(p_team: int = 1, p_hp: int = 12) -> void:
		team = p_team
		hp = p_hp


# --- Which objective the line shows -------------------------------------------

func test_a_single_objective_is_the_whole_line() -> void:
	assert_eq(ObjectiveBanner.banner_text(["Defeat the boss"]),
			ObjectiveBanner.PREFIX + "Defeat the boss",
			"one objective is stated in full behind the objective glyph")


func test_extra_objectives_are_counted_not_crammed_in() -> void:
	var text: String = ObjectiveBanner.banner_text(
			["Defeat the boss", "Destroy the enemy base", "Keep Torvald alive"])
	assert_eq(text, ObjectiveBanner.PREFIX + "Defeat the boss" + (ObjectiveBanner.MORE_SUFFIX % 2),
			"the primary objective is shown and the other two are counted")
	assert_false(text.contains("Destroy"),
			"a second objective never widens the line -- the tooltip carries it")


func test_the_rest_of_the_objectives_are_listed_in_the_tooltip() -> void:
	var tip: String = ObjectiveBanner.tooltip_text_for(
			["Defeat the boss", "Destroy the enemy base"])
	assert_true(tip.contains("Defeat the boss"), "the tooltip lists the primary objective")
	assert_true(tip.contains("Destroy the enemy base"), "and the one that did not fit")
	assert_eq(tip.split("\n").size(), 2, "one row per objective")


func test_a_single_objective_has_no_tooltip_at_all() -> void:
	assert_eq(ObjectiveBanner.tooltip_text_for(["Defeat the boss"]), "",
			"a tooltip repeating the line above it is noise, not information")


func test_a_battle_with_no_resolvable_objective_still_says_what_winning_is() -> void:
	assert_eq(ObjectiveBanner.banner_text([]),
			ObjectiveBanner.PREFIX + ObjectiveBanner.FALLBACK_TEXT,
			"every map can at minimum be won by clearing the field, so say so")
	assert_eq(ObjectiveBanner.banner_text(["", "   "]),
			ObjectiveBanner.PREFIX + ObjectiveBanner.FALLBACK_TEXT,
			"and a condition that describes itself as nothing counts as nothing")


func test_a_blank_objective_never_occupies_the_primary_slot() -> void:
	assert_eq(ObjectiveBanner.banner_text(["", "Destroy the enemy base"]),
			ObjectiveBanner.PREFIX + "Destroy the enemy base",
			"the first objective that has something to say is the one shown")


# --- describe_progress: the live phrasing --------------------------------------

func test_an_unelaborated_condition_falls_back_to_its_static_description() -> void:
	# The additive default: a condition with nothing live to add needs no override, so a
	# future condition class still produces a sensible line for free.
	var c := DefeatAllEnemies.new()
	c.faction = 0
	assert_eq(c.describe_progress({}), c.describe(),
			"describe_progress defaults to describe")


func test_a_boss_objective_names_the_boss_still_standing() -> void:
	var c := DefeatBoss.new()
	c.faction = 0
	var state: Dictionary = {"units": [GruntUnit.new(1), BossUnit.new(1)]}
	assert_eq(c.describe_progress(state), "Defeat Eldroot the Hollow Crown",
			"the objective names the unit the player has to go and find")


func test_a_boss_objective_falls_back_once_the_boss_is_down() -> void:
	var c := DefeatBoss.new()
	c.faction = 0
	var state: Dictionary = {"units": [BossUnit.new(1, 0)]}
	assert_eq(c.describe_progress(state), "Defeat the boss",
			"a dead boss is nothing to name, so the generic phrasing stands")


func test_a_boss_objective_never_names_a_boss_on_our_own_side() -> void:
	var c := DefeatBoss.new()
	c.faction = 0
	var state: Dictionary = {"units": [BossUnit.new(0, 40, "Our Own Champion")]}
	assert_eq(c.describe_progress(state), "Defeat the boss",
			"a friendly boss is not the objective")


func test_a_boss_objective_with_no_state_at_all_still_describes_itself() -> void:
	var c := DefeatBoss.new()
	assert_eq(c.describe_progress({}), c.describe(),
			"a briefing with no board to read reports the static objective")


func test_a_survive_objective_counts_down() -> void:
	var c := SurviveTurns.new()
	c.turns = 6
	assert_eq(c.describe_progress({"turn": 0}), "Survive 6 more turns",
			"nothing survived yet means the whole target is still to go")
	assert_eq(c.describe_progress({"turn": 4}), "Survive 2 more turns",
			"four turns in, two are left")


func test_a_survive_objective_says_turn_not_turns_on_the_last_one() -> void:
	var c := SurviveTurns.new()
	c.turns = 6
	assert_eq(c.describe_progress({"turn": 5}), "Survive 1 more turn",
			"the last round is one turn, singular")


func test_a_survive_objective_never_counts_past_zero() -> void:
	var c := SurviveTurns.new()
	c.turns = 6
	assert_eq(c.describe_progress({"turn": 6}), c.describe(),
			"a met objective reports itself, never 'Survive 0 more turns'")
	assert_eq(c.describe_progress({"turn": 99}), c.describe(),
			"nor a negative countdown when the battle runs on past the target")


func test_the_other_shipped_objectives_still_describe_themselves() -> void:
	# These carry no live refinement, and that is the point: the base implementation
	# covers them, so the banner has a line for every condition the library can compile.
	var base := DestroyBase.new()
	base.faction = 0
	assert_eq(base.describe_progress({"units": []}), "Destroy the enemy base",
			"the base-assault objective reads the same live as it does static")

	var protect := ProtectUnit.new()
	protect.protected_id = &"torvald"
	assert_eq(protect.describe_progress({"units": []}), protect.describe(),
			"and so does the escort objective")


# --- Glyphs: what the banner may put on screen ----------------------------------
#
# THE FONT DECIDES, NOT TASTE. This banner shipped its first draft with a pennant (⚑
# U+2691) in front of the objective -- a character Godot's default font cannot draw, i.e.
# an empty tofu box parked in the middle of the top bar for the whole battle. The probe
# table in `unit/test_status_feedback.gd` (2026-08-03) measured the drawable set; this is
# the pin that keeps the banner inside it.

## Every character the banner can put on screen, from every path that emits one: the
## objective mark, the fallback line, the "+N more" suffix, and the tooltip's bullet.
func _emittable_text() -> Array[String]:
	return [
		ObjectiveBanner.PREFIX,
		ObjectiveBanner.FALLBACK_TEXT,
		ObjectiveBanner.MORE_SUFFIX % 2,
		ObjectiveBanner.banner_text([]),
		ObjectiveBanner.banner_text(["Defeat the boss", "Destroy the enemy base"]),
		ObjectiveBanner.tooltip_text_for(["Defeat the boss", "Destroy the enemy base"]),
	]


func test_every_character_the_banner_can_emit_is_one_the_font_can_draw() -> void:
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "there is a fallback font to measure against")
	if font == null:
		return
	for text in _emittable_text():
		for i in range(text.length()):
			var code: int = text.unicode_at(i)
			if code == 10 or code == 32:  # newline / space carry no glyph
				continue
			assert_true(font.has_char(code),
				"the theme font can draw '%s' (U+%04X), emitted in \"%s\" -- see the probe "
				% [text[i], code, text] + "table in unit/test_status_feedback.gd")


func test_the_objective_mark_occupies_real_width_at_the_banner_font_size() -> void:
	# has_char() is necessary but not sufficient: a glyph the font maps to nothing draws as
	# a zero-width nothing, which would leave the line looking like it lost its indent.
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "there is a fallback font to measure against")
	if font == null:
		return
	var width: float = font.get_string_size(
			ObjectiveBanner.PREFIX.strip_edges(), HORIZONTAL_ALIGNMENT_LEFT, -1,
			ConquestTheme.FONT_BODY).x
	gut.p("  objective mark '%s' width@%dpx = %.1f"
			% [ObjectiveBanner.PREFIX.strip_edges(), ConquestTheme.FONT_BODY, width])
	assert_gt(width, 0.0, "the objective mark is really drawn, not mapped to nothing")


func test_every_shipped_objectives_wording_is_drawable_too() -> void:
	# The lines are not authored in this file -- they come from the win conditions -- so the
	# pin has to cover THEIR wording as well, or a future objective could reintroduce tofu
	# through the back door.
	var font: Font = ThemeDB.fallback_font
	if font == null:
		return
	var conditions: Array[WinCondition] = WinConditionLibrary.build_win_conditions(
			["Defeat Boss", "Destroy Enemy Base", "Eliminate All Enemies"],
			WinConditionLibrary.HUMAN_FACTION)
	var survive := SurviveTurns.new()
	survive.turns = 6
	var lines: Array[String] = [survive.describe(), survive.describe_progress({"turn": 5})]
	for c in conditions:
		lines.append(c.describe())
		lines.append(c.describe_progress({}))
	for line in lines:
		for i in range(line.length()):
			var code: int = line.unicode_at(i)
			if code == 32:
				continue
			assert_true(font.has_char(code),
				"objective wording \"%s\" is drawable ('%s' U+%04X)" % [line, line[i], code])


# --- The library seam ----------------------------------------------------------

func test_the_banner_lines_come_from_the_same_strings_the_engine_compiles() -> void:
	# The banner never re-implements a map's objectives: it compiles the SAME authored
	# strings through the SAME library the runtime scores, so the line on screen cannot
	# drift from the rules that end the battle.
	var conditions: Array[WinCondition] = WinConditionLibrary.build_win_conditions(
			["Defeat Boss", "Destroy Enemy Base"], WinConditionLibrary.HUMAN_FACTION)
	var lines: Array = []
	for c in conditions:
		lines.append(c.describe_progress({}))

	assert_eq(lines.size(), 2, "both authored objectives compiled")
	assert_eq(ObjectiveBanner.banner_text(lines),
			ObjectiveBanner.PREFIX + "Defeat the boss" + (ObjectiveBanner.MORE_SUFFIX % 1),
			"and the line states the first with the second counted")
