extends GutTest

# Tests for the base-assault objective (game/modes/DestroyBase.gd), its registration in
# WinConditionLibrary, and the bookkeeping in BaseAssaultRuntime.
#
# Mirrors test_win_condition.gd: lightweight mocks, no scene tree and no live board. The
# mocks carry both shapes DestroyBase duck-types against -- a bare `is_base` flag, and a
# nested `character_resource.character_id` (what the live Unit actually exposes) -- so the
# resolver is proven on each.

# --- Mocks -----------------------------------------------------------------

class MockChar:
	var character_id: StringName
	func _init(p_id: StringName) -> void:
		character_id = p_id

class MockUnit:
	var team: int
	var hp: int
	var is_base: bool
	var is_neutral: bool
	var character_resource
	func _init(p_team: int, p_hp: int = 100, p_is_base: bool = false, p_neutral: bool = false) -> void:
		team = p_team
		hp = p_hp
		is_base = p_is_base
		is_neutral = p_neutral
		character_resource = null

## A unit that names its character the way the LIVE Unit does.
class MockCharacterUnit:
	var team: int
	var hp: int
	var character_resource
	func _init(p_team: int, p_hp: int, p_char_id: StringName) -> void:
		team = p_team
		hp = p_hp
		character_resource = MockChar.new(p_char_id)


## Compiling a base-assault rule set ARMS the shared BaseAssaultRuntime singleton (that
## is the production wiring). Silence it again so it cannot observe another suite's
## events -- it is inert outside a real battle either way, but leaving it armed is noise.
func after_all() -> void:
	BaseAssaultRuntime.sync(null)


func _condition(faction: int = 0) -> DestroyBase:
	var c := DestroyBase.new()
	c.faction = faction
	return c


# --- Winning: the enemy base falls -----------------------------------------

func test_met_when_the_enemy_base_is_destroyed_even_with_grunts_alive() -> void:
	# The whole point of the mode: the endless waves are never cleared, so the win has
	# to come from the structure alone.
	var cond := _condition()
	var my_base := MockUnit.new(0, 200, true)
	var enemy_base := MockUnit.new(1, 0, true)     # rubble
	var enemy_grunt := MockUnit.new(1, 55)         # still very much alive
	var ally := MockUnit.new(0, 40)
	var state := { "units": [my_base, ally, enemy_grunt, enemy_base] }
	assert_eq(cond.evaluate(state), WinCondition.Status.MET, "enemy base down -> MET despite grunts")


func test_ongoing_while_the_enemy_base_stands() -> void:
	var cond := _condition()
	var my_base := MockUnit.new(0, 200, true)
	var enemy_base := MockUnit.new(1, 1, true)     # one HP is still standing
	var state := { "units": [my_base, enemy_base] }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "living enemy base -> ONGOING")


func test_every_enemy_base_must_fall() -> void:
	var cond := _condition()
	var state := {
		"units": [
			MockUnit.new(0, 200, true),
			MockUnit.new(1, 0, true),
			MockUnit.new(1, 120, true),
		]
	}
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "a second enemy base still stands")


# --- Losing: your own base falls --------------------------------------------

func test_failed_when_our_own_base_is_destroyed() -> void:
	var cond := _condition()
	var my_base := MockUnit.new(0, 0, true)
	var enemy_base := MockUnit.new(1, 200, true)
	var ally := MockUnit.new(0, 90)                # we still have an army; it does not matter
	var state := { "units": [my_base, ally, enemy_base] }
	assert_eq(cond.evaluate(state), WinCondition.Status.FAILED, "own base down -> FAILED")


func test_mutual_destruction_reads_as_a_loss() -> void:
	# Defeat is checked first on purpose -- the conservative answer.
	var cond := _condition()
	var state := { "units": [MockUnit.new(0, 0, true), MockUnit.new(1, 0, true)] }
	assert_eq(cond.evaluate(state), WinCondition.Status.FAILED, "both bases down -> FAILED")


# --- Neutrals never move the objective --------------------------------------

func test_a_neutral_death_triggers_nothing() -> void:
	var cond := _condition()
	var my_base := MockUnit.new(0, 200, true)
	var enemy_base := MockUnit.new(1, 200, true)
	var dead_guardian := MockUnit.new(2, 0, false, true)
	var state := { "units": [my_base, enemy_base, dead_guardian] }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "a felled guardian decides nothing")


func test_a_neutral_structure_never_counts_as_an_enemy_base() -> void:
	# Guard against a future neutral structure handing the player a free win.
	var cond := _condition()
	var my_base := MockUnit.new(0, 200, true)
	var neutral_base := MockUnit.new(2, 0, true, true)
	var state := { "units": [my_base, neutral_base] }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "neutral rubble is not a victory")


func test_an_unowned_base_is_ignored() -> void:
	# team -1 = a unit the board holds before ownership is assigned.
	var cond := _condition()
	var state := { "units": [MockUnit.new(0, 200, true), MockUnit.new(-1, 0, true)] }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "unowned rubble is not a victory")


# --- Degenerate states -------------------------------------------------------

func test_ongoing_when_no_enemy_base_was_ever_present() -> void:
	var cond := _condition()
	var state := { "units": [MockUnit.new(0, 200, true), MockUnit.new(1, 50)] }
	assert_eq(cond.evaluate(state), WinCondition.Status.ONGOING, "nothing to destroy -> never an instant win")


func test_ongoing_on_an_empty_state() -> void:
	assert_eq(_condition().evaluate({}), WinCondition.Status.ONGOING, "no units -> ONGOING")


# --- Base detection ----------------------------------------------------------

func test_is_base_resolves_through_the_live_character_resource() -> void:
	var cond := _condition()
	assert_true(cond.is_base(MockCharacterUnit.new(1, 200, &"bastion")), "character_resource.character_id names the base")
	assert_false(cond.is_base(MockCharacterUnit.new(1, 200, &"tree_grunt")), "an ordinary character is not a base")
	assert_false(cond.is_base(null), "null is not a base")


func test_is_base_honours_an_authored_id_list() -> void:
	var cond := _condition()
	var ids: Array[StringName] = [&"eldroot"]
	cond.base_character_ids = ids
	assert_true(cond.is_base(MockCharacterUnit.new(1, 10, &"eldroot")), "authored id counts")
	assert_false(cond.is_base(MockCharacterUnit.new(1, 10, &"bastion")), "the default no longer counts")


func test_the_live_unit_shape_wins_the_whole_map() -> void:
	# End to end on the shape the real board hands the condition.
	var cond := _condition()
	var state := {
		"units": [
			MockCharacterUnit.new(0, 200, &"bastion"),
			MockCharacterUnit.new(1, 0, &"bastion"),
			MockCharacterUnit.new(1, 55, &"tree_grunt"),
		]
	}
	assert_eq(cond.evaluate(state), WinCondition.Status.MET, "live-shaped enemy base down -> MET")


# --- WinConditionLibrary registration ----------------------------------------

func test_library_maps_the_objective_string() -> void:
	assert_true(WinConditionLibrary.build_one("Destroy Enemy Base", 0) is DestroyBase, "'Destroy Enemy Base' -> DestroyBase")
	assert_true(WinConditionLibrary.build_one("destroy the base", 0) is DestroyBase, "phrasing tolerated")
	assert_true(WinConditionLibrary.build_one("DESTROY BASE", 1) is DestroyBase, "case-insensitive")


func test_library_carries_the_faction_through() -> void:
	var cond := WinConditionLibrary.build_one("Destroy Enemy Base", 1) as DestroyBase
	assert_not_null(cond)
	assert_eq(cond.faction, 1, "scored for the faction it was built for")


func test_library_rules_win_and_lose_on_the_bases() -> void:
	var rules := WinConditionLibrary.build_rules(["Destroy Enemy Base"], 0)
	var win_state := {
		"units": [MockUnit.new(0, 200, true), MockUnit.new(1, 0, true), MockUnit.new(1, 60)]
	}
	assert_eq(rules.evaluate(win_state), GameModeRules.Outcome.VICTORY, "enemy base down -> VICTORY")

	var lose_state := {
		"units": [MockUnit.new(0, 0, true), MockUnit.new(0, 60), MockUnit.new(1, 200, true)]
	}
	assert_eq(rules.evaluate(lose_state), GameModeRules.Outcome.DEFEAT, "own base down -> DEFEAT")

	var ongoing_state := {
		"units": [MockUnit.new(0, 200, true), MockUnit.new(1, 200, true)]
	}
	assert_eq(rules.evaluate(ongoing_state), GameModeRules.Outcome.ONGOING, "both bases up -> ONGOING")


# --- BaseAssaultRuntime -------------------------------------------------------
#
# The bounty tests deliberately credit UNREGISTERED team ids (5 / 6). The accounting --
# which is what is under test -- is identical, but PlayerManager.get_player_by_id then
# returns null, so the runtime cannot reach into another suite's live units and hand them
# an attack modifier as a side effect.

const UNREGISTERED_TEAM_A: int = 5
const UNREGISTERED_TEAM_B: int = 6


func test_runtime_is_wanted_only_for_base_assault_rules() -> void:
	var base_rules := WinConditionLibrary.build_rules(["Destroy Enemy Base"], 0)
	assert_true(BaseAssaultRuntime._rules_want_runtime(base_rules), "a DestroyBase map wants the runtime")

	var plain_rules := WinConditionLibrary.build_rules(["Eliminate All Enemies"], 0)
	assert_false(BaseAssaultRuntime._rules_want_runtime(plain_rules), "an ordinary map does not")
	assert_false(BaseAssaultRuntime._rules_want_runtime(null), "null rules do not")


func test_guardian_bounty_credits_the_killers_team() -> void:
	var runtime: BaseAssaultRuntime = autofree(BaseAssaultRuntime.new())
	runtime.set_armed(true)

	var guardian := MockUnit.new(2, 0, false, true)
	var killer := MockUnit.new(UNREGISTERED_TEAM_A, 80)
	runtime._on_unit_eliminated(guardian, killer)

	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_A), BaseAssaultRuntime.BOUNTY_AMOUNT,
		"the killer's side is credited")
	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_B), 0, "the other side is not")

	# A second guardian stacks the bounty.
	runtime._on_unit_eliminated(MockUnit.new(2, 0, false, true), killer)
	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_A), 2 * BaseAssaultRuntime.BOUNTY_AMOUNT,
		"bounties accumulate")


func test_only_neutral_deaths_pay_a_bounty() -> void:
	var runtime: BaseAssaultRuntime = autofree(BaseAssaultRuntime.new())
	runtime.set_armed(true)
	runtime._on_unit_eliminated(MockUnit.new(1, 0), MockUnit.new(UNREGISTERED_TEAM_A, 80))
	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_A), 0, "an ordinary enemy kill pays nothing")


func test_a_disarmed_runtime_pays_nothing() -> void:
	var runtime: BaseAssaultRuntime = autofree(BaseAssaultRuntime.new())
	runtime.set_armed(false)
	runtime._on_unit_eliminated(MockUnit.new(2, 0, false, true), MockUnit.new(UNREGISTERED_TEAM_A, 80))
	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_A), 0, "an unarmed runtime ignores every event")


func test_arming_resets_the_previous_battles_bounties() -> void:
	var runtime: BaseAssaultRuntime = autofree(BaseAssaultRuntime.new())
	runtime.set_armed(true)
	runtime._on_unit_eliminated(MockUnit.new(2, 0, false, true), MockUnit.new(UNREGISTERED_TEAM_A, 80))
	assert_gt(runtime.team_bonus(UNREGISTERED_TEAM_A), 0, "bounty earned")
	runtime.set_armed(true)  # next map load
	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_A), 0, "a fresh battle starts from zero")


func test_an_unattributable_guardian_death_is_harmless() -> void:
	var runtime: BaseAssaultRuntime = autofree(BaseAssaultRuntime.new())
	runtime.set_armed(true)
	runtime._on_unit_eliminated(MockUnit.new(2, 0, false, true), null)
	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_A), 0, "no known killer -> no bounty, no error")
	assert_eq(runtime.team_bonus(2), 0, "and certainly not to the neutrals")


func test_the_killer_is_reconstructed_from_the_last_damager() -> void:
	# GameEvents.unit_eliminated is emitted with a NULL eliminator, so the runtime has to
	# remember who last hit the guardian.
	var runtime: BaseAssaultRuntime = autofree(BaseAssaultRuntime.new())
	runtime.set_armed(true)
	var guardian := MockUnit.new(2, 0, false, true)
	var killer := MockUnit.new(UNREGISTERED_TEAM_B, 70)
	runtime._on_damage_dealt(killer, guardian, 12)
	runtime._on_unit_eliminated(guardian, null)
	assert_eq(runtime.team_bonus(UNREGISTERED_TEAM_B), BaseAssaultRuntime.BOUNTY_AMOUNT,
		"last damager takes the credit")
