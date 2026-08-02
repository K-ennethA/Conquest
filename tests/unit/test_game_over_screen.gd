extends GutTest

## Results-tally latch for [b]GameOverScreen[/b]: GameEvents.unit_eliminated is fed
## straight to the screen's PRIVATE handler ([code]_on_unit_eliminated_tally[/code])
## rather than emitted through the real (Unit-typed) signal, mirroring how
## test_challenge_survive_capture.gd drives ChallengeController's own tally handlers
## directly -- a duck-typed double could not satisfy the signal's static Unit
## parameter type anyway.
##
## The screen under test is constructed with .new() and NEVER added to the tree, so
## _ready() (which builds the whole UI and connects GameEvents itself) never runs --
## this suite touches no autoload state and needs no scene.

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
