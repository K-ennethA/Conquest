extends GutTest

## Tests for the AI's use of NON-DAMAGE SUPPORT MOVES in [method BotController.plan]:
## self-buffs (Heartwood Guard), heals, and pure debuffs. Before this feature the AI
## ranked every candidate purely by estimated DAMAGE, so a 0-direct-damage move could
## never be chosen -- Eldroot never guarded and a healer never healed.
##
## The branch is DAMAGE-FIRST: a lethal or clearly-strong attack is always taken over
## a support cast; support only fills turns where attacking is weak or survival/tempo
## matters. Coverage:
##  - A THREATENED unit (enemy adjacent) with an off-cooldown self-buff and no strong
##    attack CHOOSES the buff and aims at itself (SELF cast, cast in place).
##  - REGRESSION: the SAME unit, when a LETHAL attack is available, takes the ATTACK.
##  - A LOW-HP unit with a heal chooses the heal (aimed at itself); a FULL-HP one does
##    not (it falls through to the ordinary plan).
##  - A self-buff ON COOLDOWN is not chosen -- the readiness gate reuses
##    MovesetController.can_use, so the plan falls through to the normal attack.
##  - REGRESSION: a unit with ONLY a damage move behaves exactly as before (no support
##    candidate exists, so the support branch is a no-op).
##
## Uses the lightweight duck-typed StubUnit / MockBoard harness from
## tests/unit/test_ai_behavior.gd, extended with a stub MovesetController so cooldown
## readiness can be pinned. `reachable` is passed directly, so no live board is needed.

# --- Mocks (mirror test_ai_behavior.gd, plus a moveset controller) ----------

## A per-unit cooldown gate: any move_id in `blocked` reports NOT usable, mirroring
## MovesetController.can_use for a move on cooldown / out of charges.
class StubMoveset:
	var blocked: Array = []

	func can_use(move) -> bool:
		return move != null and not (move.move_id in blocked)


class StubUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var stance: String = "aggressive"
	var home: Vector2i = Vector2i(-1, -1)
	var aggro: int = 0
	var leash: int = -1
	var moveset_controller = null  # a StubMoveset, or null for "everything ready"

	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))

	func get_stat(name: String) -> int:
		return int(stats.get(name, 0))

	func take_damage(n: int) -> void:
		hp -= n

	func get_hp() -> int:
		return hp

	func is_aggressive() -> bool:
		return stance == "aggressive"

	func is_defensive() -> bool:
		return stance == "defensive"

	func get_home_cell() -> Vector2i:
		return home

	func has_home_cell() -> bool:
		return home.x >= 0 and home.y >= 0

	func get_aggro_range() -> int:
		return aggro

	func get_leash_radius() -> int:
		return leash

	func has_leash() -> bool:
		return leash >= 0

	func get_moveset_controller():
		return moveset_controller


class MockBoard:
	var placements: Array = []  # { unit, cell }

	func place(unit, cell: Vector2i) -> void:
		placements.append({ "unit": unit, "cell": cell })

	func cell_of(unit) -> Vector2i:
		for p in placements:
			if p.unit == unit:
				return p.cell
		return Vector2i(-999, -999)

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for p in placements:
			if p.cell == cell:
				out.append(p.unit)
		return out

	func are_enemies(a, b) -> bool:
		return a.team != b.team

	func are_allies(a, b) -> bool:
		return a.team == b.team

	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out


# --- Move fixtures (built in code so no .tres load is needed) ----------------

## A Heartwood-Guard-style SELF buff: target_kind SELF, range 0, NO DamageEffect, a
## lasting defence StatModifier (+ a status). Classified as SELF-BUFF purely by data.
func _self_buff_move(cd: int = 2) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_guard"
	m.display_name = "Test Guard"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	m.cooldown = cd
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.SELF
	p.min_range = 0
	p.max_range = 0
	p.area_shape = CombatTypes.AreaShape.SINGLE
	p.affects_caster_tile = true
	m.targeting = p
	var buff := StatModifierEffect.new()
	buff.stat_name = "defense"
	buff.amount = 10
	buff.duration = 3
	var status := ApplyStatusEffect.new()
	status.condition = StatusCondition.new()  # a bare timed buff; never executed here
	status.chance = 1.0
	m.effects = [status, buff]
	return m


## A SELF heal: HealEffect targeting the caster's own cell.
func _heal_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_heal"
	m.display_name = "Test Heal"
	m.category = CombatTypes.DamageCategory.MAGICAL
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.SELF
	p.min_range = 0
	p.max_range = 0
	p.area_shape = CombatTypes.AreaShape.SINGLE
	p.affects_caster_tile = true
	m.targeting = p
	var heal := HealEffect.new()
	heal.amount = 30
	m.effects = [heal]
	return m


## A plain melee strike whose power the caller controls (so an attack can be made
## deliberately weak or lethal against a given target).
func _strike_move(power: int) -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_strike"
	m.display_name = "Test Strike"
	m.category = CombatTypes.DamageCategory.PHYSICAL
	var p := TargetingPattern.new()
	p.target_kind = CombatTypes.TargetKind.ENEMY
	p.min_range = 1
	p.max_range = 1
	p.area_shape = CombatTypes.AreaShape.SINGLE
	m.targeting = p
	var d := DamageEffect.new()
	d.power = power
	d.scaling_stat = ""
	d.scale = 0.0
	d.category = CombatTypes.DamageCategory.PHYSICAL
	m.effects = [d]
	return m


# --- Self-buff: chosen only when NO attack is reachable ----------------------

func test_self_buff_fires_only_when_no_attack_is_reachable() -> void:
	# THREATENED (a hostile at distance 2 <= THREAT_RANGE) but UNABLE to retaliate this
	# turn: the only attack is a range-1 strike, the enemy is at distance 2, and the
	# unit cannot move (empty reachable). With nothing to hit, it shields itself.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(2, 0))  # within threat range, outside range-1 reach

	var bot := BotController.new()
	var decision := bot.plan(actor, [_self_buff_move(), _strike_move(8)], board, [])

	assert_eq(decision["action"], BotController.ActionType.MOVE, "it acts (uses the buff)")
	assert_eq(decision["move"].move_id, &"test_guard", "with no attack reachable, the self-buff is chosen")
	assert_eq(decision["target"], actor, "the buff targets the caster itself")
	assert_eq(decision["aim_cell"], Vector2i(0, 0), "a SELF cast aims at the actor's own cell")
	assert_eq(decision["dest_cell"], Vector2i(0, 0), "and is cast in place -- no walk before it")


# --- Damage-first: ANY reachable attack beats the self-buff ------------------

func test_any_reachable_attack_is_taken_over_the_self_buff() -> void:
	# SAME actor, SAME off-cooldown buff, SAME threat -- but now the enemy is adjacent,
	# so the range-1 strike CAN hit it. Even a weak chip on a healthy 100-HP foe (not
	# lethal, nowhere near half its HP) is taken over the buff: damage-first is strict.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))  # adjacent -> the strike reaches it

	var bot := BotController.new()
	var decision := bot.plan(actor, [_self_buff_move(), _strike_move(8)], board, [])

	assert_eq(decision["action"], BotController.ActionType.MOVE, "it acts")
	assert_eq(decision["move"].move_id, &"test_strike", "a reachable attack wins over the buff")
	assert_eq(decision["target"], enemy, "and it is aimed at the enemy, not itself")


# --- Heal: the healer exception (fires over a NON-lethal attack) --------------

func test_low_hp_unit_heals_over_a_reachable_nonlethal_attack() -> void:
	# Below 60% HP with a heal AND a reachable (adjacent) attack. The strike is not
	# lethal (8 into a healthy 100-HP foe), so the healer saves itself rather than
	# trading a chip -- heal is the one support that may beat a non-lethal attack.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })
	actor.hp = 20  # 20% -- well under the heal threshold
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))  # adjacent -> the strike is reachable

	var bot := BotController.new()
	var decision := bot.plan(actor, [_heal_move(), _strike_move(8)], board, [])

	assert_eq(decision["action"], BotController.ActionType.MOVE, "it acts (heals)")
	assert_eq(decision["move"].move_id, &"test_heal", "a badly hurt healer heals over a non-lethal attack")
	assert_eq(decision["target"], actor, "it heals the most-hurt valid target -- itself")
	assert_eq(decision["aim_cell"], Vector2i(0, 0), "aimed at its own cell")


func test_lethal_attack_is_taken_over_the_heal() -> void:
	# The limit of the healer exception: a LETHAL attack is never passed up. Same low-HP
	# actor, but the adjacent enemy has 8 HP and the strike kills it -- take the kill.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })
	actor.hp = 20
	var enemy := StubUnit.new(1, { "health": 8, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))

	var bot := BotController.new()
	var decision := bot.plan(actor, [_heal_move(), _strike_move(8)], board, [])

	assert_eq(decision["action"], BotController.ActionType.MOVE, "it acts")
	assert_eq(decision["move"].move_id, &"test_strike", "the lethal attack wins over the heal")
	assert_eq(decision["target"], enemy, "aimed at the enemy it can finish")


func test_full_hp_unit_does_not_heal() -> void:
	# No target is hurt enough, so the heal is not chosen. With no attack in range the
	# unit falls through to advancing toward the (far) enemy.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })  # hp defaults to 100
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(10, 0))

	var bot := BotController.new()
	var decision := bot.plan(actor, [_heal_move()], board, [Vector2i(1, 0), Vector2i(2, 0)])

	assert_ne(decision["action"], BotController.ActionType.MOVE, "a full-HP unit does not cast the heal")
	assert_eq(decision["action"], BotController.ActionType.STEP, "it advances toward the enemy instead")


# --- Cooldown gate: a self-buff on cooldown is not chosen --------------------

func test_self_buff_on_cooldown_is_not_chosen() -> void:
	# Same geometry as the self-buff scenario (threatened, no reachable attack), so a
	# READY buff WOULD fire -- but the moveset controller reports it on cooldown. The
	# support branch must skip it and fall through to the normal plan (here: no attack,
	# no movement -> wait), never casting the unavailable buff.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })
	var mc := StubMoveset.new()
	mc.blocked = [&"test_guard"]
	actor.moveset_controller = mc
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(2, 0))  # threatened, but out of range-1 reach

	var bot := BotController.new()
	var decision := bot.plan(actor, [_self_buff_move(), _strike_move(8)], board, [])

	assert_ne(decision["action"], BotController.ActionType.MOVE,
		"the buff is on cooldown, so it is not cast -- the plan falls through (no attack -> wait)")
	assert_null(decision["move"], "no move is cast this turn")


func test_ready_self_buff_would_fire_in_the_cooldown_setup() -> void:
	# The control for the cooldown test: the IDENTICAL geometry with the buff READY does
	# choose it, proving the cooldown -- not the geometry -- is what suppressed it above.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })
	actor.moveset_controller = StubMoveset.new()  # nothing blocked -> buff ready
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(2, 0))

	var bot := BotController.new()
	var decision := bot.plan(actor, [_self_buff_move(), _strike_move(8)], board, [])

	assert_eq(decision["move"].move_id, &"test_guard", "with the buff ready the same setup casts it")


# --- Regression: a damage-only kit is untouched by the support branch --------

func test_damage_only_unit_still_attacks_as_before() -> void:
	# A unit whose entire kit is a damaging move produces no support candidate, so the
	# support branch is a no-op and the historical attack behaviour is unchanged.
	var actor := StubUnit.new(0, { "health": 100, "attack": 10 })
	var enemy := StubUnit.new(1, { "health": 100, "defense": 0 })
	var board := MockBoard.new()
	board.place(actor, Vector2i(0, 0))
	board.place(enemy, Vector2i(1, 0))

	var bot := BotController.new()
	var decision := bot.plan(actor, [_strike_move(8)], board, [])

	assert_eq(decision["action"], BotController.ActionType.MOVE, "it attacks")
	assert_eq(decision["move"].move_id, &"test_strike", "the only move -- the strike -- is used")
	assert_eq(decision["target"], enemy, "aimed at the enemy exactly as before")
