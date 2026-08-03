extends GutTest

## Pins the two pieces of battle-HUD arithmetic that were wrong on screen:
##
##   1. the turn banner's unit count -- it used to be a turn-START SNAPSHOT of
##      TraditionalTurnSystem.get_current_turn_progress().units_can_act, so it read
##      "41 units remaining" for the whole of an enemy phase no matter how many units
##      actually moved, died or spawned during it;
##   2. the left column's height budget -- the unit card was clamped to a bottom reserve
##      with NO floor, so on a short column it was handed less height than its own fixed
##      rows and the inner VBoxContainer distributed negative space (portrait stacked on
##      the Statistics rows, stat labels reading "th: 8" from under it).
##
## Everything under test is a STATIC pure function: no scene tree, no autoloads, no disk.

const Doubles := preload("res://tests/helpers/test_doubles.gd")


## One roster entry, exactly the shape count_act_progress duck-types on: liveness through
## is_alive(), "already acted" through the unit's own has_acted_this_turn flag. Deliberately
## local (tests/README rule 5): the shared doubles carry neither hook, and adding one to
## ObjectiveUnit would silently reroute every win-condition suite that uses it.
##
## Inner classes are RefCounted, so nothing here can orphan.
class RosterUnit:
	var alive: bool = true
	var has_acted_this_turn: bool = false
	var label: String = ""

	func _init(p_label: String = "", p_alive: bool = true, p_acted: bool = false) -> void:
		label = p_label
		alive = p_alive
		has_acted_this_turn = p_acted

	func is_alive() -> bool:
		return alive


func _roster(count: int) -> Array:
	var out: Array = []
	for i in range(count):
		out.append(RosterUnit.new("u%d" % i))
	return out


# --- The counter -------------------------------------------------------------

func test_a_fresh_side_has_every_unit_left_to_act() -> void:
	var progress: Dictionary = TurnIndicator.count_act_progress(_roster(5))
	assert_eq(progress.left, 5, "nobody has acted yet, so all five are still to act")
	assert_eq(progress.total, 5, "and all five count toward the side's total")
	assert_eq(progress.acted, 0, "with none recorded as having acted")


func test_a_unit_that_acted_leaves_the_left_count_but_stays_in_the_total() -> void:
	var units: Array = _roster(4)
	units[0].has_acted_this_turn = true
	units[1].has_acted_this_turn = true

	var progress: Dictionary = TurnIndicator.count_act_progress(units)
	assert_eq(progress.left, 2, "two of the four have acted, so two are left to act")
	assert_eq(progress.total, 4, "the side still has four living units")
	assert_eq(progress.acted, 2, "and two are recorded as having acted")


func test_the_turn_systems_acted_side_list_counts_even_when_the_unit_flag_does_not() -> void:
	# TraditionalTurnSystem.can_unit_act honours BOTH sources because they can disagree
	# (a unit whose unit_action_completed never reached mark_unit_acted, and vice versa).
	var units: Array = _roster(3)
	var acted: Array = [units[2]]

	var progress: Dictionary = TurnIndicator.count_act_progress(units, acted)
	assert_eq(progress.left, 2, "the side list alone is enough to mark a unit as done")
	assert_eq(progress.acted, 1, "and it is counted as having acted")


func test_a_unit_is_never_double_counted_when_both_sources_agree() -> void:
	var units: Array = _roster(3)
	units[0].has_acted_this_turn = true

	var progress: Dictionary = TurnIndicator.count_act_progress(units, [units[0]])
	assert_eq(progress.acted, 1, "one unit acted, however many sources say so")
	assert_eq(progress.left, 2, "and two are still to act")


func test_dead_units_leave_both_counts() -> void:
	var units: Array = _roster(4)
	units[0].alive = false
	units[1].alive = false

	var progress: Dictionary = TurnIndicator.count_act_progress(units)
	assert_eq(progress.total, 2, "a dead unit is not part of the side's total")
	assert_eq(progress.left, 2, "nor is it something still to act")


func test_a_dead_unit_that_had_acted_is_dropped_not_counted_as_acted() -> void:
	var units: Array = _roster(3)
	units[0].has_acted_this_turn = true
	units[0].alive = false

	var progress: Dictionary = TurnIndicator.count_act_progress(units, [units[0]])
	assert_eq(progress.total, 2, "death removes the unit from the roster entirely")
	assert_eq(progress.acted, 0, "so it is not still being reported as one that acted")


func test_a_blocked_unit_cannot_act_but_still_belongs_to_the_side() -> void:
	# Stunned / hijacked this turn: barred by the turn system's per-turn latches, which is
	# not the same as having acted.
	var units: Array = _roster(3)

	var progress: Dictionary = TurnIndicator.count_act_progress(units, [], [units[1]])
	assert_eq(progress.left, 2, "a stunned unit is not something the side can still do")
	assert_eq(progress.total, 3, "but it is still one of the side's living units")
	assert_eq(progress.acted, 0, "and it has not acted -- it was barred")


func test_a_unit_spawned_mid_turn_joins_both_counts_on_the_next_read() -> void:
	var units: Array = _roster(2)
	units[0].has_acted_this_turn = true
	var before: Dictionary = TurnIndicator.count_act_progress(units)

	units.append(RosterUnit.new("reinforcement"))
	var after: Dictionary = TurnIndicator.count_act_progress(units)

	assert_eq(before.total, 2, "two units on the side before the wave")
	assert_eq(after.total, 3, "the spawned unit joins the side's total")
	assert_eq(after.left, 2, "and it has not acted, so it is one more thing left to do")


func test_null_and_freed_entries_are_skipped_entirely() -> void:
	var ghost := Node.new()
	ghost.free()  # freed, not queue_freed -- is_instance_valid() is false immediately

	var units: Array = [RosterUnit.new("live"), null, ghost]
	var progress: Dictionary = TurnIndicator.count_act_progress(units)
	assert_eq(progress.total, 1, "only the one real unit is counted")
	assert_eq(progress.left, 1, "and it is the only one still to act")


func test_a_unit_without_a_liveness_hook_is_assumed_alive() -> void:
	# The shared CombatUnit double exposes neither is_alive() nor current_health; a unit
	# that cannot be proven dead must not silently vanish from the banner.
	var progress: Dictionary = TurnIndicator.count_act_progress(
			[Doubles.CombatUnit.new(0, {"attack": 10})])
	assert_eq(progress.total, 1, "an un-provable unit still counts toward the side")


# --- The wording -------------------------------------------------------------

func test_the_banner_reads_n_of_m_units_left_to_act() -> void:
	var text: String = TurnIndicator.progress_text(2, {"left": 3, "total": 8, "acted": 5})
	assert_eq(text, "Round 2 - 3 of 8 units left to act",
			"the banner names both the work left and the size of the side")


func test_the_banner_drops_the_count_when_there_is_no_side_to_count() -> void:
	assert_eq(TurnIndicator.progress_text(4, {}), "Round 4",
			"no active player means no roster, so the round stands alone")
	assert_eq(TurnIndicator.progress_text(4, {"left": 0, "total": 0, "acted": 0}), "Round 4",
			"and an empty side reports no count rather than '0 of 0'")


# --- The left-column budget --------------------------------------------------
#
# Since the unit-info redesign the card's height is PINNED (UnitInfoPanel.CARD_HEIGHT):
# every row on the compact battle card has a fixed height, so the column budgets against
# a constant instead of re-measuring a card whose content changes whenever a status lands.
# That constant is what the arithmetic below spends.

func test_the_left_column_claims_add_up_to_the_column_exactly() -> void:
	# 720 window - 15 HUD margin - 56 top bar - 10 separation = the column's top edge.
	var column_top: float = 15.0 + 56.0 + 10.0
	assert_eq(column_top, 81.0, "the left column starts 81px down at 720p")

	# What is left after the terrain card's bottom-left reserve.
	var usable: float = 720.0 - UnitInfoPanel.BOTTOM_RESERVE - column_top
	assert_eq(usable, 463.0, "463px of column to share")

	# The card's claim is its pinned height plus the column separation above it.
	var card_claim: float = UnitInfoPanel.CARD_HEIGHT + 10.0
	assert_eq(card_claim, 238.0, "the card claims its 228px card plus the 10px separation")

	# What is left is the battle log's budget, and the three add up with nothing over.
	var log_budget: float = usable - card_claim
	assert_eq(log_budget, 225.0, "225px of column is left for the battle log")
	assert_eq(card_claim + log_budget, usable,
			"card + separation + log budget == the usable column, with nothing left over")


func test_the_compact_card_frees_enough_column_for_a_fully_expanded_log() -> void:
	# THE DIVIDEND of shrinking the card. The old sheet-style card claimed a 358px
	# fixed-content floor, so the log was handed 463 - 358 - 10 = 95px -- under
	# MIN_EXPANDED_HEIGHT, which forced it back to its 30px chip for as long as anything
	# was selected. The pinned 228px card leaves 225px, which is more than the log's whole
	# panel, so it now expands in full WITH a unit selected.
	var log_budget: float = 463.0 - (UnitInfoPanel.CARD_HEIGHT + 10.0)
	assert_true(log_budget >= BattleLog.PANEL_HEIGHT,
			"the freed slack covers the log's whole expanded panel")
	assert_eq(BattleLog.resolved_height(true, log_budget), BattleLog.PANEL_HEIGHT,
			"so an expanded log renders at its full height beside the card")


func test_the_card_still_fits_under_a_fully_expanded_log() -> void:
	# The worst case on screen: log expanded, card underneath it, terrain card below both.
	var card_top: float = 81.0 + BattleLog.PANEL_HEIGHT + 10.0
	assert_eq(card_top, 249.0, "the card starts under a fully expanded log")

	var card_bottom: float = card_top + UnitInfoPanel.CARD_HEIGHT
	var reserve_top: float = 720.0 - UnitInfoPanel.BOTTOM_RESERVE
	assert_eq(card_bottom, 477.0, "and ends at 477px")
	assert_true(card_bottom <= reserve_top,
			"which is clear of the band the terrain card owns")
	assert_eq(reserve_top - card_bottom, 67.0, "with 67px of slack, not a hair's breadth")

	# And the budget the card is handed in that worst case still holds its pinned height.
	assert_true(UnitInfoPanel.height_budget(720.0, card_top, UnitInfoPanel.CARD_HEIGHT)
			>= UnitInfoPanel.CARD_HEIGHT,
			"so nothing on the card is ever squeezed or cut off at 720p")


func test_the_bottom_reserve_is_exactly_the_terrain_cards_corner() -> void:
	assert_eq(TerrainInfoPanel.MARGIN + TerrainInfoPanel.MAX_HEIGHT + 8.0,
			UnitInfoPanel.BOTTOM_RESERVE,
			"the reserve is the terrain card's margin, its height cap and an 8px gap")


func test_the_card_is_never_budgeted_below_its_own_fixed_rows() -> void:
	# The bug this guard exists for: a short column (a 180px Speed First top bar, or a
	# shorter window) produced a budget under the card's fixed content, and the inner VBox
	# then distributed NEGATIVE space and overlapped its own children. The budget must
	# yield to the floor, never the other way round.
	var floor_h: float = UnitInfoPanel.CARD_HEIGHT
	assert_eq(UnitInfoPanel.height_budget(720.0, 560.0, floor_h), floor_h,
			"a slot smaller than the card cannot squeeze it -- the card overflows instead")
	assert_eq(UnitInfoPanel.height_budget(380.0, 121.0, floor_h), floor_h,
			"nor can a short window")
	assert_eq(UnitInfoPanel.height_budget(720.0, 121.0, floor_h), 423.0,
			"and a column with room reports the room it has")


func test_the_terrain_card_is_capped_at_its_reserved_height() -> void:
	assert_eq(TerrainInfoPanel.card_height(90.0), 90.0,
			"a short card is exactly its content")
	assert_eq(TerrainInfoPanel.card_height(400.0), TerrainInfoPanel.MAX_HEIGHT,
			"a tile with many effect chips scrolls instead of growing past the cap")


# --- The battle log's share ---------------------------------------------------

func test_a_collapsed_log_is_always_its_chip() -> void:
	assert_eq(BattleLog.resolved_height(false, 463.0), BattleLog.COLLAPSED_HEIGHT,
			"collapsed is collapsed however much room there is")


func test_an_expanded_log_takes_the_full_panel_when_the_column_can_spare_it() -> void:
	# No unit selected: the whole 463px column is the log's.
	assert_eq(BattleLog.resolved_height(true, 463.0), BattleLog.PANEL_HEIGHT,
			"with the card hidden the log expands in full")


func test_an_expanded_log_falls_back_to_its_chip_rather_than_squeezing_the_card() -> void:
	# The rule still holds even though the compact card no longer triggers it at 720p: a
	# budget under MIN_EXPANDED_HEIGHT is not a readable log, so the log gives up its
	# scrollback rather than stealing rows from the card. This is what protects a SHORT
	# window (or the 180px Speed First top bar), where the column really is that tight.
	var leftover: float = 95.0
	assert_true(leftover < BattleLog.MIN_EXPANDED_HEIGHT,
			"95px is less than a readable log")
	assert_eq(BattleLog.resolved_height(true, leftover), BattleLog.COLLAPSED_HEIGHT,
			"so the log shows its chip instead of stealing the card's rows")


func test_an_expanded_log_takes_a_partial_budget_when_it_is_still_readable() -> void:
	assert_eq(BattleLog.resolved_height(true, 140.0), 140.0,
			"a budget over MIN_EXPANDED_HEIGHT is used as-is")
	assert_eq(BattleLog.resolved_height(true, BattleLog.MIN_EXPANDED_HEIGHT),
			BattleLog.MIN_EXPANDED_HEIGHT,
			"the minimum readable height is itself allowed")


# --- The announcement banner --------------------------------------------------

func test_the_action_banner_parks_below_whatever_the_top_bar_is() -> void:
	# Compact Traditional chip: 15 margin + 56 bar = 71, well clear of the 104 floor.
	assert_eq(ActionAnnouncer.banner_top(71.0), ActionAnnouncer.TOP_OFFSET,
			"a short top bar leaves the banner at its authored offset")
	# Speed First turn queue: 15 + 180 = 195. A fixed 104 put the banner straight
	# through it -- the reported "toast renders half under the turn banner".
	assert_eq(ActionAnnouncer.banner_top(195.0), 195.0 + ActionAnnouncer.BANNER_GAP,
			"a tall top bar pushes the banner below it with a gap")
	assert_true(ActionAnnouncer.banner_top(195.0) > 195.0,
			"the banner never starts inside the turn banner's band")
