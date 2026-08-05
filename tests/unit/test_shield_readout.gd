extends GutTest

## The damage-soak SHIELD as a READOUT: the shared arithmetic ([ShieldVisuals]), the
## absorption rule it borrows from combat ([method Unit.absorb_split]), the silver segment
## on the world-space [HealthBar], and the soaked floating number in [DamageNumbers].
##
## WHY THIS SUITE EXISTS. [signal Unit.shield_changed] said "Drives any shield HUD" and
## nothing anywhere was connected to it: a 15-point Crystalline Ward was completely
## invisible, so a hit landing for zero HP looked like a bug in the game rather than a
## ward doing its job.
##
## THE ONE PROPERTY EVERY TEST HERE COMES BACK TO: a unit with NO shield must render
## exactly what it rendered before any of this existed -- the same fill fraction, the same
## label text, and no extra nodes at all. A readout that is free when it is off is a
## readout that can be on every HP surface in the game.

const HEALTH_BAR := preload("res://game/visuals/HealthBar.tscn")
const DAMAGE_NUMBERS := preload("res://game/visuals/DamageNumbers.gd")
const ANIMATOR := preload("res://game/visuals/UnitAnimator.gd")
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose -- see tests/README.md, rule 3.
var _guard


func before_each() -> void:
	_guard = Guard.new()
	# Assigned through the guard, never through the setter: set_animations_enabled()
	# writes the player's real user://settings.cfg.
	_guard.set_setting("animations_enabled", true)
	_guard.set_setting("battle_speed", 1.0)
	ANIMATOR._clear_anim_registry()


func after_each() -> void:
	ANIMATOR._clear_anim_registry()
	_guard.restore()


# --- Fixtures ------------------------------------------------------------------

func _character() -> CharacterResource:
	var c := CharacterResource.new()
	c.character_id = &"geode"
	c.display_name = "Geode"
	c.base_health = 40
	c.base_attack = 20
	c.base_defense = 5
	c.base_speed = 10
	c.base_movement = 3
	return c


## A real, live unit: _ready builds the UnitStats component the bar binds to.
func _unit() -> Unit:
	var u := Unit.new()
	u.character_resource = _character()
	add_child_autofree(u)
	return u


func _bar() -> Node3D:
	var bar: Node3D = HEALTH_BAR.instantiate()
	add_child_autofree(bar)  # entering the tree runs _ready -> materials + meshes
	return bar


func _fill_width(bar) -> float:
	return ((bar.get_node("HealthFill") as MeshInstance3D).mesh as QuadMesh).size.x


func _segment(bar) -> MeshInstance3D:
	return bar.get_node_or_null("ShieldSegment") as MeshInstance3D


func _segment_width(bar) -> float:
	var seg := _segment(bar)
	if seg == null:
		return 0.0
	return (seg.mesh as QuadMesh).size.x


# ==============================================================================
# 1. The glyph actually draws
# ==============================================================================

func test_the_shield_glyph_is_a_glyph_the_font_can_draw() -> void:
	# This project has shipped TOFU before (a ⚔ that rendered as an empty box), so the
	# glyph is not a matter of taste -- it is a capability of the font, asserted here
	# before anything is allowed to print it.
	#
	# The probe below is why ShieldVisuals.GLYPH is ◊ and not the ◈ the design asked for:
	# run this test and read the table. It also covers the STATUS vocabulary's ORIGINAL
	# glyphs (◆▲●▼■), which on the measured font are ALL undrawable -- this table is the
	# standing evidence that sent StatusVisuals to † + O - ~. The wider candidate sweep
	# (dingbats, Latin-1 marks, ASCII) lives in unit/test_status_feedback.gd.
	var font: Font = ThemeDB.fallback_font
	assert_not_null(font, "there is a fallback font to measure against")
	if font == null:
		return
	for candidate in ["◈", "◇", "◊", "●", "○", "◆", "▲", "▼", "■"]:
		gut.p("  probe: '%s' U+%04X  has_char=%s"
				% [candidate, candidate.unicode_at(0), font.has_char(candidate.unicode_at(0))])

	var code: int = ShieldVisuals.GLYPH.unicode_at(0)
	assert_true(font.has_char(code),
			"the theme font can draw the shield glyph '%s' (U+%04X) -- an undrawable glyph "
			% [ShieldVisuals.GLYPH, code]
			+ "renders as tofu on every HP surface at once")
	var drawn: float = font.get_string_size(
			ShieldVisuals.GLYPH, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	assert_true(drawn > 0.0, "and it occupies real width when drawn (%.1fpx)" % drawn)


func test_the_shield_silver_is_from_the_theme_family() -> void:
	assert_eq(ShieldVisuals.SILVER, ConquestTheme.EL_STEEL,
			"the shield's silver IS the theme's steel -- not an off-palette grey")


# ==============================================================================
# 2. The bar arithmetic (pure)
# ==============================================================================

func test_no_shield_is_exactly_the_bar_that_shipped_before() -> void:
	# The whole "free when it is off" claim, as a float comparison.
	for hp in [0, 1, 25, 40]:
		var fractions: Dictionary = ShieldVisuals.bar_fractions(hp, 40, 0)
		assert_eq(float(fractions["hp"]), float(hp) / 40.0,
				"with no shield the fill fraction is still current/max (%d/40)" % hp)
		assert_eq(float(fractions["shield"]), 0.0,
				"and there is no tail at all (%d/40)" % hp)


func test_a_shield_that_fits_the_missing_health_never_moves_the_hp_fill() -> void:
	# The design's central case: the ward stands in for health you have lost, so the green
	# does not budge and the silver claims part of the depleted track.
	var without: Dictionary = ShieldVisuals.bar_fractions(25, 40, 0)
	var with_ward: Dictionary = ShieldVisuals.bar_fractions(25, 40, 15)
	assert_eq(float(with_ward["hp"]), float(without["hp"]),
			"25/40 draws the same green with a 15 ward as without it")
	assert_almost_eq(float(with_ward["shield"]), 15.0 / 40.0, 0.0001,
			"and the ward claims its own 15 points at the SAME points-per-pixel as HP")


func test_a_shield_bigger_than_the_bar_rescales_instead_of_overflowing() -> void:
	# 40/40 + a 60 ward is 100 points in a bar that holds 40. A fixed-width slot cannot
	# grow, so both segments rescale together -- and the sum still fits.
	var fractions: Dictionary = ShieldVisuals.bar_fractions(40, 40, 60)
	var hp: float = float(fractions["hp"])
	var shield: float = float(fractions["shield"])
	gut.p("overflow    : hp=%.4f shield=%.4f sum=%.4f" % [hp, shield, hp + shield])
	assert_almost_eq(hp, 40.0 / 100.0, 0.0001, "HP takes its share of the shared scale")
	assert_almost_eq(shield, 60.0 / 100.0, 0.0001, "and the ward takes the rest")
	assert_true(hp + shield <= 1.0 + 0.0001,
			"the two segments never exceed the bar (%.4f)" % (hp + shield))


func test_the_two_segments_never_exceed_the_bar_for_any_input() -> void:
	for spec in [[0, 0, 0], [10, 0, 5], [0, 40, 99], [40, 40, 1], [3, 7, 200]]:
		var fractions: Dictionary = ShieldVisuals.bar_fractions(spec[0], spec[1], spec[2])
		var total: float = float(fractions["hp"]) + float(fractions["shield"])
		assert_true(total <= 1.0 + 0.0001,
				"cur=%d max=%d shield=%d fits the bar (%.4f)" % [spec[0], spec[1], spec[2], total])


# ==============================================================================
# 3. The number formats
# ==============================================================================

func test_zero_shield_formats_to_nothing_at_all() -> void:
	assert_eq(ShieldVisuals.number_text(0), "",
			"no shield produces no label -- never a '◊0'")
	assert_eq(ShieldVisuals.spaced_number_text(0), "", "same for the spaced form")
	assert_eq(ShieldVisuals.hp_text(58, 108, 0), "58/108",
			"and the HP numbers line is untouched")
	assert_eq(ShieldVisuals.absorb_text(0, 30), "",
			"an unshielded target gives the forecast nothing to say")
	assert_eq(ShieldVisuals.absorbed_popup_text(0), "",
			"and nothing absorbed floats no silver number")


func test_a_live_shield_reads_as_the_glyph_and_the_number() -> void:
	assert_eq(ShieldVisuals.number_text(15), "%s15" % ShieldVisuals.GLYPH,
			"the compact form the HUD cards use")
	assert_eq(ShieldVisuals.hp_text(58, 108, 15), "58/108 %s15" % ShieldVisuals.GLYPH,
			"the HP numbers line carries it after the numbers")
	assert_eq(ShieldVisuals.spaced_number_text(15), "%s 15" % ShieldVisuals.GLYPH,
			"the roomier surfaces space it")


func test_the_shield_is_read_off_any_unit_and_off_none() -> void:
	var unit := _unit()
	assert_eq(ShieldVisuals.shield_of(unit), 0, "a fresh unit carries no ward")
	unit.grant_shield(15)
	assert_eq(ShieldVisuals.shield_of(unit), 15, "and reports the one it is granted")
	assert_eq(ShieldVisuals.shield_of(null), 0, "null is 0, not an error")
	assert_eq(ShieldVisuals.shield_of(autofree(Node.new())), 0,
			"and so is anything with no shield concept -- every surface asks unconditionally")


# ==============================================================================
# 4. The absorption rule: ONE function, shared with the live hit
# ==============================================================================

func test_the_absorption_split_is_the_rule_take_damage_applies() -> void:
	var partial: Dictionary = Unit.absorb_split(15, 10)
	assert_eq(int(partial["absorbed"]), 10, "a 15 ward eats a 10 hit whole")
	assert_eq(int(partial["shield_left"]), 5, "and 5 of it survives")
	assert_eq(int(partial["to_health"]), 0, "so nothing reaches health")

	var overrun: Dictionary = Unit.absorb_split(15, 24)
	assert_eq(int(overrun["absorbed"]), 15, "a 24 hit burns the whole 15")
	assert_eq(int(overrun["shield_left"]), 0, "leaving none")
	assert_eq(int(overrun["to_health"]), 9, "and 9 falls through to health")

	var none: Dictionary = Unit.absorb_split(0, 24)
	assert_eq(int(none["absorbed"]), 0, "no ward absorbs nothing")
	assert_eq(int(none["to_health"]), 24, "and the hit lands in full")


func test_the_live_hit_burns_the_shield_by_that_same_split() -> void:
	# The parity claim, proven against the board rather than against the helper: whatever
	# absorb_split says the forecast will show is what take_damage actually does.
	var unit := _unit()
	unit.grant_shield(15)
	var before: int = unit.current_health

	unit.take_damage(10)
	assert_eq(unit.get_shield(), 5, "a 10 hit leaves 5 of the ward")
	assert_eq(unit.current_health, before, "and costs no health at all")

	unit.take_damage(9)
	assert_eq(unit.get_shield(), 0, "the next hit burns the rest")
	assert_eq(unit.current_health, before - 4, "and only the overrun reaches health")


func test_the_forecast_line_states_the_absorption_and_what_is_left() -> void:
	assert_eq(ShieldVisuals.absorb_text(15, 10), "absorbs 10 (5 left)",
			"a soaked hit says how much is eaten and how much ward survives")
	assert_eq(ShieldVisuals.absorb_text(15, 24), "absorbs 15 (0 left)",
			"and an overrun says the ward is spent")


# ==============================================================================
# 5. The world-space bar
# ==============================================================================

func test_an_unshielded_unit_grows_no_shield_node_at_all() -> void:
	var bar := _bar()
	var unit := _unit()
	unit.take_damage(15)
	bar.bind_unit(unit)

	assert_null(_segment(bar),
			"a unit that is never shielded pays for no segment node -- the bar is the two "
			+ "quads it always was")
	assert_almost_eq(_fill_width(bar), bar.FILL_MAX_WIDTH * 25.0 / 40.0, 0.001,
			"and its fill is plain current/max")


func test_granting_a_shield_appends_a_silver_segment_after_the_green_fill() -> void:
	var bar := _bar()
	var unit := _unit()
	unit.take_damage(15)          # 25/40
	bar.bind_unit(unit)
	var fill_before: float = _fill_width(bar)

	unit.grant_shield(15)         # rides shield_changed -- no HP change involved
	await get_tree().process_frame

	var seg := _segment(bar)
	assert_not_null(seg, "the ward brings the silver segment into being")
	if seg == null:
		return
	assert_true(seg.visible, "and it is drawn")
	assert_almost_eq(_fill_width(bar), fill_before, 0.001,
			"the green fill did not move: a ward that fits the missing health claims the "
			+ "DEPLETED track, it does not shrink health")
	assert_almost_eq(_segment_width(bar), bar.FILL_MAX_WIDTH * 15.0 / 40.0, 0.001,
			"and the segment is 15 points wide at the bar's own points-per-pixel")

	# Continuity: the silver starts exactly where the green stops.
	var fill_right: float = -bar.FILL_MAX_WIDTH * 0.5 + _fill_width(bar)
	var seg_left: float = seg.position.x - _segment_width(bar) * 0.5
	gut.p("bar         : fill=%.4f seg=%.4f  fill_right=%.4f seg_left=%.4f"
			% [_fill_width(bar), _segment_width(bar), fill_right, seg_left])
	assert_almost_eq(seg_left, fill_right, 0.001,
			"the segment begins where the fill ends, so the two read as ONE bar")
	assert_true(_fill_width(bar) + _segment_width(bar) <= bar.FILL_MAX_WIDTH + 0.001,
			"and together they never overflow the fixed track")
	assert_eq(seg.material_override.albedo_color, bar.SHIELD_COLOR,
			"drawn in the theme's steel, not in a health colour")


func test_a_shield_that_would_overflow_rescales_the_whole_bar() -> void:
	var bar := _bar()
	var unit := _unit()          # 40/40
	bar.bind_unit(unit)
	unit.grant_shield(60)
	await get_tree().process_frame

	assert_almost_eq(_fill_width(bar), bar.FILL_MAX_WIDTH * 40.0 / 100.0, 0.001,
			"a 60 ward on a full 40 HP unit rescales the green rather than pushing it out")
	assert_almost_eq(_segment_width(bar), bar.FILL_MAX_WIDTH * 60.0 / 100.0, 0.001,
			"the silver takes its share of the same scale")
	assert_true(_fill_width(bar) + _segment_width(bar) <= bar.FILL_MAX_WIDTH + 0.001,
			"and the bar still fits its 1.4-wide slot")


func test_depleting_the_shield_restores_exactly_the_pre_shield_bar() -> void:
	var bar := _bar()
	var unit := _unit()
	unit.take_damage(15)          # 25/40
	bar.bind_unit(unit)
	var fill_before: float = _fill_width(bar)

	unit.grant_shield(15)
	await get_tree().process_frame
	assert_true(_segment(bar) != null and _segment(bar).visible, "the ward is up")

	unit.take_damage(15)          # soaked whole: HP untouched, ward spent
	await get_tree().process_frame

	assert_eq(unit.current_health, 25, "the hit cost no health -- the ward ate it")
	assert_false(_segment(bar).visible,
			"and with the ward spent the silver segment is gone from the bar")
	assert_almost_eq(_fill_width(bar), fill_before, 0.001,
			"leaving EXACTLY the bar the unit had before it was ever shielded")


# ==============================================================================
# 6. The floating number
# ==============================================================================

func _numbers() -> Node3D:
	return add_child_autofree(DAMAGE_NUMBERS.new())


## Every popup's text, in spawn order.
func _popup_texts(numbers: Node3D) -> PackedStringArray:
	var out: PackedStringArray = []
	for child in numbers.get_children():
		if child is Label3D:
			out.append((child as Label3D).text)
	return out


## Every popup's HUE, in spawn order. Alpha is deliberately dropped: each popup's fade
## tween starts the frame it spawns, so by the time a test can look, `modulate.a` is
## already ~0.9998 and an exact Color compare fails on a difference nobody can see.
func _popup_hues(numbers: Node3D) -> Array:
	var out: Array = []
	for child in numbers.get_children():
		if child is Label3D:
			var m: Color = (child as Label3D).modulate
			out.append(Color(m.r, m.g, m.b))
	return out


func test_an_unshielded_hit_still_floats_one_plain_white_number() -> void:
	# The regression guard: the overwhelmingly common case must be untouched.
	var numbers := _numbers()
	var victim := _unit()
	numbers._on_damage_dealt(null, victim, 12)
	await get_tree().process_frame

	assert_eq(Array(_popup_texts(numbers)), ["12"],
			"one hit, one number, exactly as before")
	assert_true(_popup_hues(numbers)[0].is_equal_approx(
			Color(numbers.damage_color.r, numbers.damage_color.g, numbers.damage_color.b)),
			"in plain damage white (%s)" % _popup_hues(numbers)[0])
	numbers.clear_popups()


func test_a_fully_soaked_hit_floats_silver_instead_of_white() -> void:
	# The reported confusion, as pixels: a hit that a ward swallows whole used to draw a
	# white "12" while the unit lost no HP, which reads as the game dropping the hit.
	var numbers := _numbers()
	var victim := _unit()
	victim.grant_shield(15)
	# Announced BEFORE the damage is applied -- the order DamageEffect guarantees, and the
	# reason the split can be sampled exactly.
	numbers._on_damage_dealt(null, victim, 12)
	victim.take_damage(12)
	await get_tree().process_frame

	assert_eq(Array(_popup_texts(numbers)),
			["%s 12" % ShieldVisuals.GLYPH],
			"the whole hit floats as an ABSORBED number, and no damage number at all")
	assert_true(_popup_hues(numbers)[0].is_equal_approx(
			Color(numbers.shield_color.r, numbers.shield_color.g, numbers.shield_color.b)),
			"in the shield's silver, matching the segment it came off (%s)"
			% _popup_hues(numbers)[0])
	numbers.clear_popups()


func test_a_partly_soaked_hit_floats_the_soak_and_the_health_it_still_cost() -> void:
	var numbers := _numbers()
	var victim := _unit()
	victim.grant_shield(5)
	numbers._on_damage_dealt(null, victim, 12)
	victim.take_damage(12)
	await get_tree().process_frame

	var texts: Array = Array(_popup_texts(numbers))
	gut.p("popups      : %s" % [texts])
	assert_eq(texts.size(), 2, "two numbers: what the ward ate and what HP paid")
	assert_true(texts.has("%s 5" % ShieldVisuals.GLYPH),
			"the ward's 5 floats silver: %s" % [texts])
	assert_true(texts.has("7"),
			"and the 7 that actually reached health floats as damage: %s" % [texts])
	assert_eq(victim.current_health, 40 - 7, "which is exactly the HP the board took")
	numbers.clear_popups()


# ==============================================================================
# 7. The bar reads the shield that is ALREADY there when it binds
# ==============================================================================
#
# Every test above grants the ward while the bar is already watching, so the silver
# arrives on `shield_changed`. The other order -- the unit is shielded FIRST and the bar
# binds afterwards -- fires no signal at all, and it is the order the game actually uses
# whenever a unit arrives pre-warded: a mid-battle save restored through
# `BattleSnapshot._restore_shield` (grant_shield before any visual exists), a summon whose
# visuals are built after its state, an ownership change that re-runs setup_unit_visuals.
# If bind_unit only subscribed to the future, all of those would render an unshielded bar
# until the ward next happened to move.

func test_a_unit_that_is_already_shielded_renders_its_segment_the_moment_the_bar_binds() -> void:
	var unit := _unit()
	unit.take_damage(15)          # 25/40
	unit.grant_shield(15)         # granted BEFORE any bar exists -- nothing is listening
	var bar := _bar()             # _ready has already built materials + meshes
	bar.bind_unit(unit)

	# No shield_changed will ever fire for this ward. If the bind did not READ the
	# unit's CURRENT shield, nothing would ever draw it.
	var seg := _segment(bar)
	assert_not_null(seg, "binding a pre-warded unit brings the silver segment into being")
	if seg == null:
		return
	assert_true(seg.visible, "and draws it immediately -- no second event required")
	assert_almost_eq(_segment_width(bar), bar.FILL_MAX_WIDTH * 15.0 / 40.0, 0.001,
			"at the bar's own points-per-pixel, exactly as a live grant would")
	assert_almost_eq(_fill_width(bar), bar.FILL_MAX_WIDTH * 25.0 / 40.0, 0.001,
			"and the green fill is still plain current/max -- the ward claimed depleted track")


func test_binding_a_shielded_unit_before_the_bar_enters_the_tree_still_paints_it() -> void:
	# The tighter order: bind runs BEFORE _ready, so the materials and meshes the
	# segment needs do not exist yet and the paint has to happen when they do.
	var unit := _unit()            # 40/40
	unit.grant_shield(20)
	var bar: Node3D = HEALTH_BAR.instantiate()
	bar.bind_unit(unit)            # no materials yet -- this refresh can only defer
	add_child_autofree(bar)        # entering the tree runs _ready

	var seg := _segment(bar)
	assert_not_null(seg, "_ready repaints from the unit it was bound to before it existed")
	if seg == null:
		return
	assert_true(seg.visible, "so the ward is on screen the first frame the bar is")
	assert_almost_eq(_segment_width(bar), bar.FILL_MAX_WIDTH * 20.0 / 60.0, 0.001,
			"20 ward over 40 HP rescales to the shared 60-point denominator")
	assert_almost_eq(_fill_width(bar), bar.FILL_MAX_WIDTH * 40.0 / 60.0, 0.001,
			"and the green takes its share of that same scale")


func test_binding_an_unshielded_unit_still_grows_no_segment_node() -> void:
	# The regression guard for the two above: reading the shield at bind time must not
	# make the overwhelmingly common case pay for a node.
	var unit := _unit()
	var bar := _bar()
	bar.bind_unit(unit)
	assert_null(_segment(bar),
			"a bind that finds no ward builds nothing -- the bar is the two quads it always was")


# ==============================================================================
# 8. WHEN the ward arrives -- Geode OPENS warded, and RE-EARNS it once broken
# ==============================================================================
#
# A playtest report ("there is no gray shield on Geode even though match just started")
# read the missing silver as a bug in the readout. It was not a readout bug -- it was the
# DESIGN, and the design has since been changed: the ward is now issued at battle start and
# re-crystallized on a three-untouched-turn streak after it breaks. Geode's kit therefore
# carries TWO authored entries, because an AbilityResource has exactly one trigger and one
# condition:
#   crystalline_ward_initial.tres -- ON_BATTLE_START, ungated
#   crystalline_ward.tres         -- ON_TURN_START, gated on UndamagedForTurnsCondition(3)
# Both grant the SAME 15 through ShieldEffect, and Unit.grant_shield refreshes to the
# strongest value, so the two firing over each other can only ever leave 15.
#
# These tests raise the triggers directly, which is the readout's own concern; that the
# BOOT actually raises ON_BATTLE_START (in both turn systems, and never on a resume) is
# pinned on real turn systems in integration/test_battle_start_trigger.gd.

const Doubles := preload("res://tests/helpers/test_doubles.gd")


## A live Geode carrying the REAL authored ward pair (so this asserts the shipped content,
## not a hand-built copy of it), already standing on a board.
func _warded_unit() -> Unit:
	var kit: Array[AbilityResource] = []
	kit.append(load("res://game/abilities/crystalline_ward_initial.tres"))
	kit.append(load("res://game/abilities/crystalline_ward.tres"))
	var c := _character()
	c.abilities = kit
	var u := Unit.new()
	u.character_resource = c
	add_child_autofree(u)   # _ready builds the AbilitySystem child from the kit
	return u


func test_geode_opens_the_battle_already_warded_and_the_silver_is_there_to_show_it() -> void:
	var unit := _warded_unit()
	var board = Doubles.MinimalBoard.new()
	board.place(unit, Vector2i.ZERO)
	var system = unit.get_ability_system()
	assert_not_null(system, "the authored kit gave the unit a live AbilitySystem")
	if system == null:
		return

	var bar := _bar()
	bar.bind_unit(unit)
	assert_eq(unit.shield_hp, 0, "before the battle opens there is nothing to draw")
	assert_null(_segment(bar), "so no segment node has been paid for yet")

	system.dispatch_battle_start(board)
	await get_tree().process_frame

	assert_eq(unit.shield_hp, 15,
			"THE OPENING GRANT: Geode enters the fight already encased in the authored 15 HP ward")
	var seg := _segment(bar)
	assert_not_null(seg, "and the bar it was bound to grows the silver segment right there")
	if seg == null:
		return
	assert_true(seg.visible, "visibly, on the very first turn")
	assert_almost_eq(_segment_width(bar), bar.FILL_MAX_WIDTH * 15.0 / 55.0, 0.001,
			"15 ward over a full 40 HP rescales to the shared 55-point denominator")


func test_the_opening_grant_is_spent_once_and_never_re_fires() -> void:
	var unit := _warded_unit()
	var board = Doubles.MinimalBoard.new()
	board.place(unit, Vector2i.ZERO)
	var system = unit.get_ability_system()
	if system == null:
		return

	assert_eq((system.dispatch_battle_start(board) as Array).size(), 1,
			"the first dispatch runs the opening ward")
	unit.take_damage(15)
	assert_eq(unit.shield_hp, 0, "and the ward is spent by a hit that fills it")

	assert_eq((system.dispatch_battle_start(board) as Array).size(), 0,
			"a second dispatch does nothing at all -- ON_BATTLE_START is once per battle")
	assert_eq(unit.shield_hp, 0,
			"so a broken ward is NOT quietly re-issued: it has to be re-earned")


func test_a_broken_ward_recrystallizes_on_the_third_untouched_turn() -> void:
	var unit := _warded_unit()
	var board = Doubles.MinimalBoard.new()
	board.place(unit, Vector2i.ZERO)
	var system = unit.get_ability_system()
	if system == null:
		return

	system.dispatch_battle_start(board)
	assert_eq(unit.shield_hp, 15, "the battle opened warded")

	GameEvents.damage_dealt.emit(null, unit, 15)   # the hit the ability listens for
	unit.take_damage(15)
	assert_eq(unit.shield_hp, 0, "a 15 hit burns the whole ward")
	assert_eq(int(system.turns_since_damaged()), 0, "and wipes the untouched streak with it")

	var bar := _bar()
	bar.bind_unit(unit)
	assert_true(_segment(bar) == null or not _segment(bar).visible,
			"with the ward spent there is no silver on the bar")

	system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.shield_hp, 0, "one untouched turn is not yet three")
	system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.shield_hp, 0, "nor is two")
	system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	await get_tree().process_frame

	assert_eq(unit.shield_hp, 15,
			"the THIRD untouched turn start crystallizes the ward anew")
	var seg := _segment(bar)
	assert_not_null(seg, "and the silver comes back onto the bar")
	if seg == null:
		return
	assert_true(seg.visible, "visibly")
	assert_almost_eq(_segment_width(bar), bar.FILL_MAX_WIDTH * 15.0 / 55.0, 0.001,
			"at the same 55-point scale -- the ward ate the whole hit, so HP never moved")


func test_taking_a_hit_mid_streak_sends_it_back_to_zero() -> void:
	# The ward is not merely re-earnable, it is CONDITIONAL -- a Geode that is being fought
	# never reaches three, which is the whole design.
	var unit := _warded_unit()
	var board = Doubles.MinimalBoard.new()
	board.place(unit, Vector2i.ZERO)
	var system = unit.get_ability_system()
	if system == null:
		return

	system.dispatch_battle_start(board)
	GameEvents.damage_dealt.emit(null, unit, 15)
	unit.take_damage(15)                          # opening ward broken, streak at 0

	system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(int(system.turns_since_damaged()), 2, "two untouched turns banked")

	GameEvents.damage_dealt.emit(null, unit, 5)   # the hit the ability listens for
	assert_eq(int(system.turns_since_damaged()), 0, "one hit wipes the streak")

	system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.shield_hp, 0,
			"so the turn that WOULD have been the third grants nothing -- the ward has to "
			+ "be re-earned from scratch")


func test_the_two_ward_entries_refresh_each_other_and_never_stack() -> void:
	# THE PIN that makes a double grant safe BY CONSTRUCTION rather than by scheduling: the
	# opening ward and the earned one both go through Unit.grant_shield, which takes the
	# STRONGEST value. Fire both while a full ward is already up and it is still 15.
	var unit := _warded_unit()
	var board = Doubles.MinimalBoard.new()
	board.place(unit, Vector2i.ZERO)
	var system = unit.get_ability_system()
	if system == null:
		return

	system.dispatch_battle_start(board)
	assert_eq(unit.shield_hp, 15, "the opening ward is up")

	for _i in range(3):
		system.trigger(AbilityTrigger.Trigger.ON_TURN_START, unit, board)
	assert_eq(unit.shield_hp, 15,
			"the streak ability crystallizing onto a LIVE 15 ward refreshes it to 15 -- "
			+ "never 30, and never any other number")

	unit.grant_shield(15)
	assert_eq(unit.shield_hp, 15, "and a third grant of the same size changes nothing either")
