extends Node
class_name AbilitySystem

## Per-unit component that owns the unit's [AbilityResource]s and evaluates them.
##
## Attach one to a unit (or hold one on a mock in tests) and populate
## [member abilities]. The turn / action system drives it two ways:
##   - [method trigger] — on a gameplay event (turn start, kill, …), run the
##     pipeline effects of every ability whose trigger matches and whose condition
##     holds. Deterministic (insertion order), so networked peers resolve alike.
##   - [method passive_modifiers] — ask, on demand, for the merged action-economy
##     tweaks of all currently-in-force PASSIVE abilities, e.g. "how many extra
##     actions / movement does this unit have on its current tile right now?".
##
## While in the scene tree it ALSO listens on the game-wide [code]GameEvents[/code]
## bus and raises the combat triggers for its own unit (see [method _wire_events]),
## which is what makes ON_ATTACK / ON_DAMAGED / ON_KILL / ON_MOVE fire without any
## caller having to remember to. Instantiated bare (as tests do) it stays inert.
##
## Ability effects and rule-modifier vocabulary live on [AbilityResource].

## The unit these abilities belong to; passed as the acting unit when an explicit
## one isn't supplied. Defaults to the parent node if left unset.
var owner_unit

var abilities: Array[AbilityResource] = []

## Per-UNIT activation state, keyed by the [AbilityResource] INSTANCE:
##   ability -> { "cooldown": int (turns remaining), "uses": int (spent) }
##
## This lives here, on the per-unit component, and deliberately NOT on the
## resource: a single authored .tres is shared by every unit that has the
## ability (and by the character resource itself), so state stored there would
## leak across units — one soldier's once-per-battle power would exhaust the
## whole squad's. Keyed by instance rather than by [member AbilityResource.id]
## so abilities with blank or duplicated ids still track independently.
var _ability_state: Dictionary = {}

## The last unit this one damaged, used to attribute a kill when the elimination
## signal carries no eliminator (see [method _on_unit_eliminated]).
var _last_damaged = null

## Consecutive OWN turn-starts this unit has begun without taking damage. Bumped
## once at each ON_TURN_START (see [method trigger]) and reset to 0 the moment the
## unit is damaged (see [method _on_damage_dealt]). Read by UndamagedForTurnsCondition
## to gate "reward for staying untouched" abilities like Crystalline Ward.
var _turns_since_damaged: int = 0


func _ready() -> void:
	if owner_unit == null:
		owner_unit = get_parent()
	_wire_events()


## Convenience: register an ability. Returns it for chaining in setup code.
func add_ability(ability: AbilityResource) -> AbilityResource:
	if ability != null:
		abilities.append(ability)
	return ability


## Fire every ability whose [member AbilityResource.trigger] equals [param event]
## and whose condition currently holds, applying each one's pipeline effects to
## [param unit] (defaults to [member owner_unit]). Returns the combined event log.
##
## [param other] is the unit that caused the event — the attacker for ON_DAMAGED,
## the victim for ON_ATTACK / ON_KILL — and is what an ability with
## [member AbilityResource.targets_triggering_unit] set reaches out to. Both
## [param board] and [param other] are optional and trailing, so every existing
## call site is unaffected.
##
## Abilities that are on cooldown or out of activations are skipped (see
## [method can_activate]); one that actually runs records the activation.
func trigger(event: AbilityTrigger.Trigger, unit = null, board = null, other = null) -> Array:
	var acting = unit if unit != null else _unit()
	# Count another untouched turn BEFORE evaluating this turn-start's abilities, so a
	# condition that reads the counter (Crystalline Ward's "undamaged for N turns") sees
	# the freshly-incremented value on the very turn it should fire.
	if event == AbilityTrigger.Trigger.ON_TURN_START:
		_turns_since_damaged += 1
	var events: Array = []
	for ability in abilities:
		if ability == null or ability.trigger != event:
			continue
		if not can_activate(ability):
			continue
		if not ability.is_condition_met(acting, board):
			continue
		_note_activation(ability)
		for e in ability.run_effects(acting, board, other):
			events.append(e)
	return events


## True if [param ability] is ready for THIS unit: off cooldown and with
## activations left. Mirrors [method MovesetController.can_use] for moves.
func can_activate(ability: AbilityResource) -> bool:
	if ability == null:
		return false
	var state: Dictionary = _state_for(ability)
	if int(state["cooldown"]) > 0:
		return false
	if ability.max_activations >= 0 and int(state["uses"]) >= ability.max_activations:
		return false
	return true


## Cooldown turns still remaining on [param ability] for this unit (0 = ready).
func cooldown_remaining(ability: AbilityResource) -> int:
	if ability == null:
		return 0
	return int(_state_for(ability)["cooldown"])


## Activations left before [param ability] hits its
## [member AbilityResource.max_activations]. Returns -1 for unlimited abilities.
func activations_left(ability: AbilityResource) -> int:
	if ability == null or ability.max_activations < 0:
		return -1
	return maxi(0, ability.max_activations - int(_state_for(ability)["uses"]))


## Count every active ability cooldown down by one turn. Called once per unit per
## turn by the turn system's ON_TURN_START tick, exactly like move cooldowns.
func tick_cooldowns() -> void:
	for ability in _ability_state.keys():
		var state: Dictionary = _ability_state[ability]
		var left := int(state["cooldown"])
		if left > 0:
			state["cooldown"] = left - 1


## Forget all cooldown / activation tracking (e.g. at the start of a new battle).
func reset_activations() -> void:
	_ability_state.clear()
	_turns_since_damaged = 0


## Consecutive own turn-starts begun without taking damage (see [member _turns_since_damaged]).
func turns_since_damaged() -> int:
	return _turns_since_damaged


## This unit's tracking record for [param ability], created on first use.
func _state_for(ability: AbilityResource) -> Dictionary:
	var state = _ability_state.get(ability, null)
	if not (state is Dictionary):
		state = { "cooldown": 0, "uses": 0 }
		_ability_state[ability] = state
	return state


## Spend one activation and start the ability's cooldown for THIS unit.
func _note_activation(ability: AbilityResource) -> void:
	var state: Dictionary = _state_for(ability)
	state["uses"] = int(state["uses"]) + 1
	if ability.cooldown > 0:
		state["cooldown"] = ability.cooldown


## Merged [member AbilityResource.rule_modifiers] of every PASSIVE ability whose
## condition currently holds for [param unit]. Integer values sum across abilities;
## bool values OR together; any other value type is last-write-wins. Callers read
## the result to adjust the action economy (extra actions, movement, terrain-cost
## rules, …). Abilities whose condition is unmet contribute nothing.
func passive_modifiers(unit = null, board = null) -> Dictionary:
	var acting = unit if unit != null else _unit()
	var merged: Dictionary = {}
	for ability in abilities:
		if ability == null or ability.trigger != AbilityTrigger.Trigger.PASSIVE:
			continue
		if ability.rule_modifiers.is_empty():
			continue
		if not ability.is_condition_met(acting, board):
			continue
		_merge_modifiers(merged, ability.rule_modifiers)
	return merged


## Extra actions granted this turn by in-force passives ("act/move twice").
func extra_actions(unit = null, board = null) -> int:
	return int(passive_modifiers(unit, board).get("extra_actions", 0))


## Extra movement range granted this turn by in-force passives.
func extra_movement(unit = null, board = null) -> int:
	return int(passive_modifiers(unit, board).get("extra_movement", 0))


## True if any in-force passive sets the named boolean rule flag
## (e.g. "ignore_terrain_cost").
func has_flag(flag_name: String, unit = null, board = null) -> bool:
	return bool(passive_modifiers(unit, board).get(flag_name, false))


## Rule-modifier keys that are MULTIPLICATIVE reduction SCALES (1.0 = no change,
## < 1.0 = takes less / lasts less). These must NOT be summed across passives: two
## "take 25% less" (0.75) passives summed to 1.5 would make the unit take 50% MORE.
## Instead the STRONGEST (smallest) wins -- reductions refresh, they do not compound
## -- matching StatusController.status_damage_taken_scale (min) and the reduction-
## refresh rule. See DamageEffect.damage_taken_scale_for.
const STRONGEST_WINS_KEYS: Array[String] = ["damage_taken_scale"]


func _merge_modifiers(into: Dictionary, from: Dictionary) -> void:
	for key in from:
		var val = from[key]
		if val is bool:
			into[key] = bool(into.get(key, false)) or val
		elif (val is int or val is float) and String(key) in STRONGEST_WINS_KEYS:
			# Strongest reduction wins; never stack/sum/multiply.
			if into.has(key):
				into[key] = minf(float(into[key]), float(val))
			else:
				into[key] = float(val)
		elif val is int or val is float:
			var current = into.get(key, 0)
			if current is bool:
				current = 1 if current else 0
			into[key] = current + val  # int + int stays int; float propagates
		else:
			into[key] = val  # non-numeric, non-bool: last write wins


func _unit():
	return owner_unit if owner_unit != null else get_parent()


# --- Combat trigger routing -------------------------------------------------
#
# The trigger enum used to be mostly decorative: only ON_TURN_START was ever
# raised. Rather than sprinkle `trigger(...)` calls through the combat, movement
# and death paths, each unit's own AbilitySystem subscribes ONCE to the existing
# game-wide signals and filters them down to its own unit. One place to read, and
# a unit with no abilities simply loops over an empty list.
#
# ON_TILE_ENTER is deliberately NOT wired: the only tile-entry notification in the
# codebase is unit_moved itself (see GameWorldManager._on_unit_moved_tile_effects),
# so wiring it here would just fire twice for one movement. It stays dormant until
# a real per-step hook exists.


## Subscribe to the shared event bus. No-op without the autoload (headless tests,
## mock harnesses) or if already connected.
func _wire_events() -> void:
	var bus = GameEvents
	if bus == null:
		return
	if bus.has_signal(&"damage_dealt") and not bus.damage_dealt.is_connected(_on_damage_dealt):
		bus.damage_dealt.connect(_on_damage_dealt)
	if bus.has_signal(&"unit_eliminated") and not bus.unit_eliminated.is_connected(_on_unit_eliminated):
		bus.unit_eliminated.connect(_on_unit_eliminated)
	if bus.has_signal(&"unit_moved") and not bus.unit_moved.is_connected(_on_unit_moved):
		bus.unit_moved.connect(_on_unit_moved)


## One resolved hit anywhere on the board. Raises ON_ATTACK for the attacker and
## ON_DAMAGED for the defender, each passing the OTHER party as the triggering
## unit so a retaliation ability can reach it.
func _on_damage_dealt(attacker, defender, _amount) -> void:
	var me = _unit()
	if me == null:
		return
	if attacker == me:
		_last_damaged = defender
		trigger(AbilityTrigger.Trigger.ON_ATTACK, me, _board(), defender)
	elif defender == me:
		# Being hit resets the "untouched turns" streak (Crystalline Ward must re-earn it).
		_turns_since_damaged = 0
		trigger(AbilityTrigger.Trigger.ON_DAMAGED, me, _board(), attacker)


## A unit died. Fires ON_KILL for its KILLER, and only for the killer -- the
## VICTIM's side of the same moment is [constant AbilityTrigger.Trigger.ON_DEATH],
## which is deliberately NOT raised from here. This handler runs on every unit's
## component in signal order, long after the emitter has moved on; an on-death
## burst instead has to resolve at a precise point inside
## [method Unit._on_unit_died], while the dying unit is still on its cell, so the
## victim raises it on itself there.
##
## [code]unit_eliminated[/code] is
## emitted with a null eliminator from Unit._on_unit_died (nothing there knows who
## landed the blow), so we fall back to attributing the kill to whoever last
## damaged the victim — which is exactly what this component just recorded.
func _on_unit_eliminated(unit, eliminator) -> void:
	var me = _unit()
	if me == null or unit == null or unit == me:
		return
	if eliminator != null:
		if eliminator != me:
			return
	elif unit != _last_damaged:
		return  # we never touched this unit — not our kill
	_last_damaged = null
	trigger(AbilityTrigger.Trigger.ON_KILL, me, _board(), unit)


## This unit finished a movement.
func _on_unit_moved(unit, _from_position, _to_position) -> void:
	var me = _unit()
	if me == null or unit != me:
		return
	trigger(AbilityTrigger.Trigger.ON_MOVE, me, _board())


## The live board, or null before a map is loaded (effects need one; the trigger
## helpers pass it straight through and [method AbilityResource.run_effects]
## no-ops on null).
func _board():
	return CombatServices.board() if CombatServices else null
