extends GutTest

## Progression (pure): the XP curve, levels from XP, the anti-grind XP for a defeated foe
## (stronger > equal > weaker > grey, DECISIONS.md #79), the level cap, stats at level, scaled /
## legend levels, bands, bond levels and catch rates. Every test pins its own ProgressionRules
## (the script defaults = the spec's numbers), so retuning the shipped .tres never breaks them.


func _rules() -> ProgressionRules:
	return ProgressionRules.new()


func _char(health: int = 100, attack: int = 20) -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"test_mon"
	c.base_health = health
	c.base_attack = attack
	c.base_defense = 10
	c.base_magic = 10
	c.base_magic_defense = 10
	c.base_speed = 10
	c.base_movement = 3
	return c


# --- Curve ------------------------------------------------------------------------------

func test_curve_is_cubic_and_level_one_is_free() -> void:
	var r := _rules()
	assert_eq(Progression.xp_for_level(1, r), 0, "level 1 needs no XP")
	assert_eq(Progression.xp_for_level(2, r), 8, "level 2 = 2^3")
	assert_eq(Progression.xp_for_level(5, r), 125, "level 5 = 5^3")
	assert_eq(Progression.xp_for_level(50, r), 125000, "level 50 = 125,000 XP (the spec's cap)")


func test_level_for_xp_inverts_the_curve() -> void:
	var r := _rules()
	assert_eq(Progression.level_for_xp(0, r), 1, "0 XP is level 1")
	assert_eq(Progression.level_for_xp(124, r), 4, "one short of level 5 is still 4")
	assert_eq(Progression.level_for_xp(125, r), 5, "exactly 125 is level 5")
	for l in [2, 7, 13, 29, 49]:
		assert_eq(Progression.level_for_xp(Progression.xp_for_level(l, r), r), l, "level %d round-trips" % l)


func test_level_cap_and_xp_past_it_is_discarded() -> void:
	var r := _rules()
	assert_eq(Progression.level_for_xp(10_000_000, r), 50, "nothing goes past max_level")
	var out: Dictionary = Progression.add_xp(124_990, 500, r)
	assert_eq(int(out["xp"]), 125000, "XP past the cap is discarded")
	assert_eq(int(out["gained"]), 10, "only what landed counts as gained")
	assert_eq(int(out["level_after"]), 50, "the add reached the cap")
	assert_eq(Progression.xp_to_next(125000, r), 0, "nothing to the next level at the cap")
	r.max_level = 20
	assert_eq(Progression.level_for_xp(10_000_000, r), 20, "the cap is a knob")


func test_xp_to_next_and_progress() -> void:
	var r := _rules()
	assert_eq(Progression.xp_to_next(125, r), 91, "level 5 -> 6 needs 216 - 125")
	assert_almost_eq(Progression.level_progress(125, r), 0.0, 0.001, "just reached a level: an empty bar")
	assert_almost_eq(Progression.level_progress(170, r), 45.0 / 91.0, 0.001, "the bar fills through the level")


func test_add_xp_reports_level_ups() -> void:
	var r := _rules()
	var out: Dictionary = Progression.add_xp(125, 300, r)
	assert_eq(int(out["level_before"]), 5, "was level 5")
	assert_eq(int(out["level_after"]), 7, "425 XP is level 7 (343 <= 425 < 512)")


# --- XP for a foe (anti-grind) ------------------------------------------------------------

func test_stronger_foe_gives_more_than_equal_more_than_weaker_more_than_grey() -> void:
	var r := _rules()
	var stronger: int = Progression.xp_for_foe(60, 14, 10, 1.0, 1.0, r)
	var equal: int = Progression.xp_for_foe(60, 10, 10, 1.0, 1.0, r)
	var weaker: int = Progression.xp_for_foe(60, 8, 10, 1.0, 1.0, r)
	var grey: int = Progression.xp_for_foe(60, 5, 10, 1.0, 1.0, r)
	assert_gt(stronger, equal, "a stronger foe gives MORE than an equal one")
	assert_gt(equal, weaker, "an equal foe gives more than a weaker one")
	assert_gt(weaker, grey, "a weaker foe still beats a grey one")
	assert_eq(equal, roundi(60.0 * 10.0 / 7.0), "an equal foe is the plain baseline (level factor 1)")


func test_level_factor_is_one_for_an_equal_foe() -> void:
	var r := _rules()
	assert_almost_eq(Progression.level_factor(12, 12, r), 1.0, 0.0001, "equal levels: factor 1")
	assert_gt(Progression.level_factor(20, 12, r), 1.0, "stronger foe: factor above 1")
	assert_lt(Progression.level_factor(8, 12, r), 1.0, "weaker foe: factor below 1")


func test_grey_floor_applies_at_the_gap() -> void:
	var r := _rules()
	assert_false(Progression.is_grey(6, 10, r), "4 levels below is not grey")
	assert_true(Progression.is_grey(5, 10, r), "xp_grey_gap (5) levels below is grey")
	var just_above: float = 60.0 * 6.0 / 7.0 * Progression.level_factor(6, 10, r)
	assert_eq(Progression.xp_for_foe(60, 6, 10, 1.0, 1.0, r), roundi(just_above), "no grey cut above the gap")
	var at_gap: float = 60.0 * 5.0 / 7.0 * Progression.level_factor(5, 10, r) * 0.1
	assert_eq(Progression.xp_for_foe(60, 5, 10, 1.0, 1.0, r), maxi(1, roundi(at_gap)), "grey foes give xp_grey_mult of it")


func test_xp_min_floor_and_zero_share() -> void:
	var r := _rules()
	assert_eq(Progression.xp_for_foe(10, 1, 50, 1.0, 1.0, r), 1, "a trivially weak foe still gives xp_min")
	assert_eq(Progression.xp_for_foe(60, 10, 10, 1.0, 0.0, r), 0, "a zero share (the bench) earns nothing, not xp_min")
	assert_eq(Progression.xp_for_foe(60, 10, 10, 0.0, 1.0, r), 0, "a zero multiplier (a loss) earns nothing")


func test_battle_mult_and_share_scale_linearly() -> void:
	var r := _rules()
	var base: int = Progression.xp_for_foe(70, 10, 10, 1.0, 1.0, r)
	assert_eq(Progression.xp_for_foe(70, 10, 10, 1.5, 1.0, r), roundi(70.0 * 10.0 / 7.0 * 1.5), "trainer x1.5")
	assert_eq(Progression.xp_for_foe(70, 10, 10, 1.0, 0.5, r), roundi(float(base) * 0.5), "a fallen member's half share")


func test_xp_yield_derives_from_budget_unless_authored() -> void:
	var r := _rules()
	var weak := _char(50, 10)
	var strong := _char(200, 40)
	assert_gt(Progression.xp_yield_of(strong, r), Progression.xp_yield_of(weak, r), "stronger species yield more")
	assert_eq(Progression.xp_yield_of(weak, r), roundi(weak.power_budget() * 0.5), "yield = budget x xp_yield_per_budget")
	weak.xp_yield = 77
	assert_eq(Progression.xp_yield_of(weak, r), 77, "an authored xp_yield wins")


# --- Stats at level -------------------------------------------------------------------

func test_stat_at_level_formula() -> void:
	var r := _rules()
	assert_eq(Progression.stat_at_level(100, 0.04, 1, r), 100, "level 1 = the roster base")
	assert_eq(Progression.stat_at_level(100, 0.04, 11, r), 140, "100 x (1 + 0.04 x 10)")
	assert_eq(Progression.stat_at_level(100, 0.04, 50, r), 296, "level 50 is about 3x base")
	assert_eq(Progression.stat_at_level(0, 0.04, 30, r), 0, "a zero base stays zero")


func test_apply_level_scales_stats_but_not_movement_and_speed_at_half() -> void:
	var r := _rules()
	var c := _char(100, 20)
	Progression.apply_level(c, 11, r)
	assert_eq(c.base_health, 140, "HP scales with default_growth")
	assert_eq(c.base_attack, 28, "attack scales")
	assert_eq(c.base_magic_defense, 14, "magic defense scales")
	assert_eq(c.base_speed, 12, "speed scales at speed_growth_mult (half): 10 x 1.2")
	assert_eq(c.base_movement, 3, "movement never scales")


func test_per_species_growth_wins_over_default() -> void:
	var r := _rules()
	var c := _char(100, 20)
	c.health_growth = 0.1
	assert_eq(Progression.max_hp_at(c, 11, r), 200, "a species' own health_growth (0.1 x 10)")
	assert_eq(Progression.character_stat(c, "base_attack", 11, r), 28, "other stats keep the default")


func test_leveled_copy_never_touches_the_roster_resource() -> void:
	var r := _rules()
	var c := _char(100, 20)
	var copy: CharacterResource = Progression.leveled_copy(c, 26, r)
	assert_ne(copy, c, "a level above 1 returns a duplicate (CONQUEST.md rule 7)")
	assert_eq(c.base_health, 100, "the original keeps its base stats")
	assert_eq(copy.base_health, 200, "the copy is at level 26")
	assert_eq(Progression.leveled_copy(c, 1, r), c, "level 1 needs no copy")
	assert_eq(Progression.leveled_copy(c, 0, r), c, "level 0 (unset) reads as level 1")


# --- Enemy levels -------------------------------------------------------------------

func test_scaled_level_clamps_into_its_band() -> void:
	var r := _rules()
	assert_eq(Progression.scaled_level(12, 1, 8, 15, r), 13, "party top + offset")
	assert_eq(Progression.scaled_level(3, 1, 8, 15, r), 8, "never below scale_min")
	assert_eq(Progression.scaled_level(30, 1, 8, 15, r), 15, "never above scale_max")
	assert_eq(Progression.scaled_level(49, 5, 1, 0, r), 50, "no max = the level cap")


func test_legend_level_is_above_its_band() -> void:
	var r := _rules()
	assert_eq(Progression.legend_level(Vector2i(8, 15), r), 20, "band max + legend_over_band (5)")
	r.legend_over_band = 3
	assert_eq(Progression.legend_level(Vector2i(8, 15), r), 18, "legend_over_band is a knob")


func test_level_in_band_is_inclusive_and_deterministic() -> void:
	var band := Vector2i(2, 8)
	assert_eq(Progression.level_in_band(band, 0.0), 2, "u = 0 is the band's min")
	assert_eq(Progression.level_in_band(band, 0.9999), 8, "u near 1 is the band's max")
	assert_eq(Progression.level_in_band(Vector2i.ZERO, 0.5), 0, "an unset band gives no level")
	assert_eq(Progression.level_in_band(Vector2i(8, 2), 0.0), 2, "a reversed band is normalised")
	assert_eq(Progression.normalize_band(Vector2i(0, 6)), Vector2i(6, 6), "a half-set band is one level")


# --- Bond and catch rate ---------------------------------------------------------------

func test_bond_level_climbs_to_its_max() -> void:
	var r := _rules()
	assert_eq(Progression.bond_level(0, r), 0, "no bond XP = bond 0")
	assert_eq(Progression.bond_level(4, r), 0, "under one level's worth")
	assert_eq(Progression.bond_level(5, r), 1, "bond_xp_per_level (5) = bond 1")
	assert_eq(Progression.bond_level(9999, r), 10, "capped at bond_max")


func test_bond_for_battle_by_outcome() -> void:
	var r := _rules()
	assert_eq(Progression.bond_for_battle(true, "victory", r), 2, "a win gives bond_per_win")
	assert_eq(Progression.bond_for_battle(true, "defeat", r), 1, "a loss still gives bond_per_battle")
	assert_eq(Progression.bond_for_battle(true, "fled", r), 0, "a flee gives nothing")
	assert_eq(Progression.bond_for_battle(false, "victory", r), 0, "the bench earns no bond")


func test_catch_rate_by_budget_and_authored() -> void:
	var r := _rules()
	var weak := _char(40, 10)
	var strong := _char(400, 40)
	assert_eq(Progression.catch_rate_of(weak, r), 1.0, "a cheap species is easy (catch_rate_max)")
	assert_almost_eq(Progression.catch_rate_of(strong, r), 0.2, 0.0001, "a strong species is hard (catch_rate_min)")
	strong.catch_rate = 0.65
	assert_almost_eq(Progression.catch_rate_of(strong, r), 0.65, 0.0001, "an authored catch_rate wins")


func test_shipped_rules_resource_loads() -> void:
	var r: ProgressionRules = ProgressionRules.current()
	assert_not_null(r, "the shipped progression_rules.tres loads")
	assert_eq(r.max_level, 50, "the shipped cap is 50 (DECISIONS.md #79)")
	assert_eq(r.starter_level, 5, "the starter joins at level 5")
