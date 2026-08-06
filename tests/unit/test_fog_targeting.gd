extends GutTest

## FOG HONESTY: what a hidden unit does to targeting, to the forecast and to the AI.
##
## THE RULE. A unit the acting side cannot see is not gathered by any move, so a swing aimed
## into the dark resolves against exactly what a swing aimed at empty ground resolves against:
## nothing. It is NOT refused at the aim, deliberately -- refusing the aim would make a hidden
## unit's cell behave differently from the empty ground it is supposed to look like, and a
## player (or a script) could sweep the board with a legal/illegal probe and read off where
## every hidden unit is. Fog that can be probed is not fog. The first block below pins that the
## aim stays legal AND that nothing lands.
##
## THE OTHER HALF is that GROUND stays targetable: fog hides units, not terrain, so a
## cell-targeted cast reaches anywhere in its range whatever is standing there.
##
## AND THE PIN THAT MATTERS MOST: with fog off, every one of these paths resolves exactly as it
## did before the vision system existed. Each behaviour below is asserted twice -- once fogged,
## once not -- against the same board.
##
## THE FIXTURE. The lurker stands THREE cells from the hero: inside its sight radius (so being
## hidden is entirely the veil's doing, not distance) but outside the one-cell adjacency that
## sees into concealing ground. Every move here reaches three cells for the same reason.

const Doubles := preload("res://tests/helpers/test_doubles.gd")

const VEIL_PATH := "res://game/tiles/effects/resources/smoke_veil.tres"

const HERO_CELL := Vector2i(5, 5)
const VEIL_CELL := Vector2i(5, 8)


# --- Local doubles ---------------------------------------------------------------
# Vision resolves per PLAYER SLOT through `get_owner_player().player_id`, which the shipped
# doubles (keyed on a plain `team` int) do not expose. These carry both, so MinimalBoard's
# allegiance queries keep working untouched while VisionSystem gets the owner it needs.

class Side:
	var player_id: int

	func _init(p_player_id: int) -> void:
		player_id = p_player_id


class Combatant:
	var team: int
	var owner_player
	var hp: int = 100
	var stats: Dictionary

	func _init(p_side, p_stats: Dictionary = {}) -> void:
		owner_player = p_side
		team = p_side.player_id
		stats = { "health": 100, "attack": 10, "defense": 0, "magic": 0, "evasion": 0 }
		stats.merge(p_stats, true)
		hp = int(stats["health"])

	func get_owner_player():
		return owner_player

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name.to_lower(), 0))

	func take_damage(n: int) -> void:
		hp = maxi(0, hp - n)

	func heal(n: int) -> void:
		hp += n

	func get_hp() -> int:
		return hp

	func add_stat_modifier(_stat: String, _amount: int, _duration: int) -> int:
		return 0


## Roster + per-cell tile effects on one board, which is what vision needs and no shipped
## double combines.
class FogBoard extends Doubles.CombatBoard:
	var effects: Dictionary = {}

	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out

	func tile_effects_at(cell: Vector2i) -> Array:
		var arr = effects.get(cell, null)
		return arr if arr is Array else []

	func put_effect(cell: Vector2i, effect) -> void:
		effects[cell] = [effect]


## Records what the vision system said about a watched unit AT THE MOMENT the move's effects
## began resolving. Ordered ahead of the damage effect in the move it is attached to, and
## [DamageEffect] announces from inside its own apply(), so whatever this saw is what a
## damage-bus listener would have seen. One-off on purpose: it exists to observe an ORDERING,
## which no shared double is shaped to do.
class VisibilityProbe extends MoveEffect:
	var vision
	var watched
	var seen: Array = [false]

	func apply(_ctx: MoveContext) -> void:
		seen[0] = vision.is_unit_visible(0, watched)


## The board, the two sides and the two combatants are UNTYPED on purpose. GUT re-loads a suite
## script while collecting it, which mints a SECOND copy of every inner class -- so a member
## statically typed as an inner class is rejected at parse time with the famously unhelpful
## "value of type X cannot be assigned to a variable of type X". Everything that consumes them
## is duck-typed anyway (that is the whole point of the combat module's board/unit interfaces),
## so nothing is lost by leaving the declarations open.
var _vs: VisionSystem
var _board
var _p0
var _p1
var _hero
var _lurker


func before_each() -> void:
	# CombatServices owns the APPLIED tile-effect layer the ground-cast tests write into.
	CombatServices.clear()
	_p0 = Side.new(0)
	_p1 = Side.new(1)
	_board = FogBoard.new()
	_hero = Combatant.new(_p0, { "attack": 10 })
	_lurker = Combatant.new(_p1, { "attack": 10, "defense": 0 })
	_board.place(_hero, HERO_CELL)
	_board.place(_lurker, VEIL_CELL)
	_board.put_effect(VEIL_CELL, load(VEIL_PATH))
	_vs = add_child_autofree(VisionSystem.new())
	_vs.set_board(_board)
	_vs.set_map(_map(true))


func after_each() -> void:
	CombatServices.clear()


func _map(fog: bool) -> MapResource:
	var m := MapResource.new()
	m.map_name = "Fog Targeting Fixture"
	m.width = 12
	m.height = 12
	m.fog_of_war = fog
	return m


## A plain physical strike that reaches the veil without standing beside it. 24 power + 10
## attack = 34 raw, against 0 defense.
func _strike() -> MoveResource:
	var m := MoveLibrary.basic_strike()
	m.targeting.max_range = 3
	return m


## A move that places a smoke veil on an EMPTY TILE -- the ordinary, non-hostile ground cast.
func _lay_veil_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_lay_veil"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.EMPTY_TILE
	pattern.min_range = 1
	pattern.max_range = 3
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = pattern
	var lay := ApplyTileEffect.new()
	lay.effect = load(VEIL_PATH)
	m.effects = [lay] as Array[MoveEffect]
	return m


# --- The fixture itself ------------------------------------------------------------

func test_the_lurker_is_hidden_by_the_veil_and_not_by_distance() -> void:
	assert_true(_vs.is_cell_visible(0, VEIL_CELL),
		"the veil cell is comfortably inside the hero's sight radius")
	assert_false(_vs.is_unit_visible(0, _lurker),
		"so everything below is about the veil, not about how far away it is")


# --- Targeting ---------------------------------------------------------------------

func test_a_strike_into_the_dark_lands_on_nothing() -> void:
	var result := MoveExecutor.execute(_strike(), _hero, _board, VEIL_CELL)
	assert_true(result.success,
		"the cast still RESOLVES -- aiming at a hidden unit is aiming at empty ground")
	assert_eq(_lurker.hp, 100, "and it takes nothing off the unit standing in the veil")


func test_the_same_strike_lands_with_fog_off() -> void:
	_vs.set_map(_map(false))
	MoveExecutor.execute(_strike(), _hero, _board, VEIL_CELL)
	assert_eq(_lurker.hp, 66, "34 raw minus 0 defense -- exactly what it always did")


func test_the_aim_stays_legal_so_fog_cannot_be_probed() -> void:
	# If a hidden unit's cell were refused, sweeping legal/illegal aims across the board would
	# hand the player a map of every hidden unit. It must look exactly like open ground.
	var move := _strike()
	assert_true(move.can_target(HERO_CELL, VEIL_CELL, _hero, _board),
		"the cell a hidden unit stands on is still a legal aim")
	assert_true(move.can_target(HERO_CELL, Vector2i(5, 7), _hero, _board),
		"and so is the genuinely empty cell beside it -- the two are indistinguishable")


func test_a_revealed_enemy_is_hit_again() -> void:
	_vs.mark_revealed(_lurker)
	MoveExecutor.execute(_strike(), _hero, _board, VEIL_CELL)
	assert_eq(_lurker.hp, 66,
		"once it has given itself away it takes the full hit, veil or no veil")


func test_an_enemy_seen_in_the_open_is_hit_normally() -> void:
	_board.effects.clear()  # the smoke blows away; nothing else changes
	_vs.invalidate()
	MoveExecutor.execute(_strike(), _hero, _board, VEIL_CELL)
	assert_eq(_lurker.hp, 66, "fog only ever hides what is actually hidden")


func test_an_enemy_hidden_by_distance_alone_is_also_unhittable() -> void:
	# The other way to be hidden: no veil, simply nobody looking. Same outcome, same seam.
	_board.effects.clear()
	_board.move_unit(_lurker, Vector2i(11, 11))
	_vs.invalidate()
	var far := _strike()
	far.targeting.max_range = 20
	MoveExecutor.execute(far, _hero, _board, Vector2i(11, 11))
	assert_eq(_lurker.hp, 100, "a unit nobody can see takes nothing, however long your reach")


func test_a_side_can_always_reach_its_own_units() -> void:
	# The reason the gather path is a safe place for this rule when an untargetable FLAG was
	# not: a side always sees its own units, so a heal can never be blocked by fog.
	var friend := Combatant.new(_p0)
	friend.hp = 40
	_board.place(friend, Vector2i(5, 4))
	_board.put_effect(Vector2i(5, 4), load(VEIL_PATH))
	_vs.invalidate()
	MoveExecutor.execute(MoveLibrary.mend(), _hero, _board, Vector2i(5, 4))
	assert_gt(friend.hp, 40, "an ally standing in smoke is still mine to heal")


func test_ground_targeted_casts_reach_anywhere_in_range() -> void:
	# Fog hides units, not terrain. A cell-targeted cast must be unaffected by who is standing
	# on the cell -- that is what keeps ground-shaped moves castable in the dark.
	var result := MoveExecutor.execute(_lay_veil_move(), _hero, _board, VEIL_CELL)
	assert_true(result.success, "a ground cast onto a hidden unit's cell is legal")
	assert_false(CombatServices.applied_tile_effects_at(VEIL_CELL).is_empty(),
		"and it actually lands on the ground there")


# --- Forecast -----------------------------------------------------------------------

func test_there_is_no_forecast_for_something_you_cannot_see() -> void:
	var preview: Dictionary = MoveExecutor.preview_vs(_strike(), _hero, _lurker, _board)
	assert_true(bool(preview.get("hidden", false)),
		"the forecast says outright that the target is hidden")
	assert_eq(int(preview.get("damage", -1)), 0,
		"and quotes no damage -- the swing would deal none, so promising a number would lie")
	assert_false(bool(preview.get("lethal", true)), "nothing hidden is ever forecast as lethal")


func test_the_forecast_is_untouched_with_fog_off() -> void:
	_vs.set_map(_map(false))
	var preview: Dictionary = MoveExecutor.preview_vs(_strike(), _hero, _lurker, _board)
	assert_false(preview.has("hidden"), "no map asked for fog, so nothing is hidden")
	assert_eq(int(preview.get("damage", 0)), 34, "and the forecast is exactly what it was")


# --- The AI -------------------------------------------------------------------------

func test_the_bot_does_not_swing_at_what_it_cannot_see() -> void:
	var bot := BotController.new()
	bot.difficulty = BotController.Difficulty.NORMAL
	var decision: Dictionary = bot.decide(_lurker_as_actor(), [_strike()], _board)
	assert_ne(int(decision["action"]), BotController.ActionType.MOVE,
		"a bot never spends its turn attacking a unit the gather path will not hand it")


func test_the_bot_attacks_the_moment_the_target_is_revealed() -> void:
	var bot := BotController.new()
	bot.difficulty = BotController.Difficulty.NORMAL
	var actor = _lurker_as_actor()  # untyped: the helper returns an inner-class instance
	_vs.mark_revealed(_hero)
	var decision: Dictionary = bot.decide(actor, [_strike()], _board)
	assert_eq(int(decision["action"]), BotController.ActionType.MOVE,
		"a revealed enemy is a target again")
	assert_eq(decision["target"], _hero, "and it is the one that gave itself away")


func test_the_bot_plans_exactly_as_before_with_fog_off() -> void:
	_vs.set_map(_map(false))
	var bot := BotController.new()
	bot.difficulty = BotController.Difficulty.NORMAL
	var decision: Dictionary = bot.decide(_lurker_as_actor(), [_strike()], _board)
	assert_eq(int(decision["action"]), BotController.ActionType.MOVE,
		"with no fog the veil means nothing and the bot attacks, as it always has")
	assert_eq(decision["target"], _hero, "hitting the enemy in front of it")


## Turn the fixture around: the LURKER is the bot, and the HERO is what it is deciding about.
## Hiding the hero (from the lurker's side) is one veil on the hero's own cell.
func _lurker_as_actor():
	_board.put_effect(HERO_CELL, load(VEIL_PATH))
	_vs.invalidate()
	return _lurker


# --- Reveal on attack, through the live execute path ----------------------------------

func test_the_attacker_is_already_visible_when_its_damage_resolves() -> void:
	# THE ORDERING PIN. The reveal is stamped inside MoveExecutor.execute before the FIRST
	# effect applies, and DamageEffect announces from inside its own apply() -- so a probe
	# ordered ahead of the damage sees exactly what a damage listener would see.
	var probe := VisibilityProbe.new()
	probe.vision = _vs
	probe.watched = _lurker

	var move := _strike()
	# Built as a TYPED array and appended into: `[probe] + move.effects` yields an untyped
	# Array, and an `as Array[MoveEffect]` cast on a concatenation does not survive assignment
	# to the typed property.
	var ordered: Array[MoveEffect] = [probe]
	ordered.append_array(move.effects)
	move.effects = ordered

	assert_false(_vs.is_unit_visible(0, _lurker), "hidden right up to the cast")
	MoveExecutor.execute(move, _lurker, _board, HERO_CELL)
	assert_true(probe.seen[0],
		"by the time the blow was resolving, the hidden attacker was already visible")


func test_a_hidden_attacker_becomes_targetable_after_it_attacks() -> void:
	assert_false(_vs.is_unit_visible(0, _lurker), "hidden in the veil to start with")
	MoveExecutor.execute(_strike(), _lurker, _board, HERO_CELL)
	assert_lt(_hero.hp, 100, "the blow lands -- the lurker can see perfectly well")
	assert_true(_vs.is_unit_visible(0, _lurker), "and it has given itself away")

	MoveExecutor.execute(_strike(), _hero, _board, VEIL_CELL)
	assert_lt(_lurker.hp, 100, "so the hero can hit back, which is the whole point of the rule")


func test_the_reveal_runs_out_and_the_lurker_is_hidden_again() -> void:
	MoveExecutor.execute(_strike(), _lurker, _board, HERO_CELL)
	assert_true(_vs.is_unit_visible(0, _lurker), "revealed by the attack")
	for _i in range(VisionSystem.REVEAL_TURNS):
		_vs.note_turn_started()
	assert_false(_vs.is_unit_visible(0, _lurker), "and back into the smoke once it has passed")


func test_walking_does_not_reveal() -> void:
	# Movement never touches MoveExecutor, so it cannot mark anything -- pinned so it stays
	# true if a future mover ever grows a move-shaped path.
	_board.move_unit(_lurker, Vector2i(5, 7))
	_vs.invalidate()
	assert_false(_vs.is_revealed(_lurker), "a unit that only walked has given nothing away")


func test_placing_a_veil_does_not_reveal_the_placer() -> void:
	MoveExecutor.execute(_lay_veil_move(), _lurker, _board, Vector2i(5, 7))
	assert_false(_vs.is_revealed(_lurker),
		"laying the cover you are about to hide in must not be the thing that lights you up")
	assert_false(_vs.is_unit_visible(0, _lurker), "so it is still hidden afterwards")
