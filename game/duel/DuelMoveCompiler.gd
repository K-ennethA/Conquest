extends RefCounted
class_name DuelMoveCompiler

## Turns a roster character's authored moveset into its DUEL moveset
## (docs/design/DUEL_BATTLE.md §3.4). A duel has no movement and everything is in reach, so
## the only things that do not translate are position-dependent EFFECTS and landing
## CONSTRAINTS; this is where each is handled, once, from data:
##
## - the policy per effect class is [member DuelRuleset.effect_policies] (keep / drop /
##   exclude the move / convert to plain damage / keep a tile effect only if it fires for a
##   unit that never moves);
## - a move that authors [member MoveResource.duel_variant] is replaced by that variant as-is;
## - landing constraints (requires_empty_cell, requires_adjacent_enemy, aim_rule) are cleared
##   on the compiled pattern; ALLY-targeted moves become SELF (there are no allies in 1v1);
## - excluded moves re-pack the slots, and a move that was the ULTIMATE keeps its cut-in
##   ([member MoveResource.is_ultimate]) wherever it lands;
## - abilities are filtered by [member DuelRuleset.ability_policies] (Reanimate is disabled:
##   a KO ends the duel).
##
## RULE 7: everything is built on private copies -- a fresh [DuelCharacter], duplicated
## moves / patterns / effects -- so the shared roster resources are never touched.
## RULE 1: failures are returned ({success, reason}), never logged.

## Target kinds that reach the foe (a compiled moveset with none of them cannot win).
const OFFENSIVE_KINDS: Array[int] = [
	CombatTypes.TargetKind.ENEMY, CombatTypes.TargetKind.ANY_UNIT,
	CombatTypes.TargetKind.TILE, CombatTypes.TargetKind.EMPTY_TILE,
]


## Compile [param character] for a duel under [param ruleset].
## Returns { success, reason, character: DuelCharacter }.
static func compile(character: CharacterResource, ruleset: DuelRuleset = null) -> Dictionary:
	if character == null:
		return {"success": false, "reason": "no_character", "character": null}
	if ruleset == null:
		ruleset = DuelRuleset.load_default()
	var out := DuelCharacter.new()
	_copy_character(character, out)
	out.source_id = character.character_id

	var moves: Array[MoveResource] = []
	var slot := 0
	for original in character.moveset:
		var was_ultimate: bool = MoveResource.is_ultimate_move(original, slot)
		slot += 1
		if original == null:
			continue
		var res := compile_move(original, ruleset)
		var compiled: MoveResource = res["move"]
		if compiled == null:
			out.excluded_moves.append(original.move_id)
			out.duel_notes[original.move_id] = res["notes"]
			continue
		if not (res["notes"] as Array).is_empty():
			out.duel_notes[compiled.move_id] = res["notes"]
		# ULTIMATE SLOT INTEGRITY: re-packing can move the ultimate off slot 3; the flag keeps
		# its cut-in (MoveResource.is_ultimate_move is flag OR slot 3).
		if was_ultimate and moves.size() != 3:
			compiled.is_ultimate = true
		moves.append(compiled)
		if moves.size() >= CharacterResource.MAX_MOVES:
			break
	out.moveset = moves

	var abilities: Array[AbilityResource] = []
	for ability in character.abilities:
		if ability == null:
			continue
		if ruleset.policy_for_ability(ability.id) == DuelRuleset.POLICY_DISABLE:
			continue
		abilities.append(ability)
	out.abilities = abilities

	if ruleset.struggle_move != null:
		out.struggle_move = ruleset.struggle_move.duplicate(true) as MoveResource
	out.duel_eligible = _has_offensive_move(moves)
	return {"success": true, "reason": "", "character": out}


## Compile one [param move]. Returns { move: MoveResource or null, notes: Array[String],
## reason } -- a null move means it is EXCLUDED from the duel (reason says why).
static func compile_move(move: MoveResource, ruleset: DuelRuleset = null) -> Dictionary:
	var notes: Array[String] = []
	if move == null:
		return {"move": null, "notes": notes, "reason": "no_move"}
	if ruleset == null:
		ruleset = DuelRuleset.load_default()
	if move.duel_variant != null:
		var variant := move.duel_variant.duplicate(true) as MoveResource
		notes.append("Duel variant of %s" % move.display_name)
		return {"move": variant, "notes": notes, "reason": ""}

	var main := _compile_effects(move.effects, ruleset, notes)
	if main["excluded"]:
		return {"move": null, "notes": notes, "reason": String(main["reason"])}
	var effects: Array[MoveEffect] = main["effects"]
	if effects.is_empty():
		return {"move": null, "notes": notes, "reason": "no_effect_left"}

	var copy := move.duplicate(false) as MoveResource
	copy.duel_variant = null
	copy.targeting = compile_pattern(move.targeting)
	copy.effects = effects
	if move.alt_requires_status != &"" and move.alt_targeting != null:
		var alt := _compile_effects(move.alt_effects, ruleset, notes)
		var alt_effects: Array[MoveEffect] = alt["effects"]
		if alt["excluded"] or alt_effects.is_empty():
			# The alternate mode cannot happen in a duel: the move keeps only its main mode.
			copy.alt_requires_status = &""
			copy.alt_targeting = null
			var none: Array[MoveEffect] = []
			copy.alt_effects = none
			notes.append("%s has no alternate mode in duels" % move.display_name)
		else:
			copy.alt_targeting = compile_pattern(move.alt_targeting)
			copy.alt_effects = alt_effects
	return {"move": copy, "notes": notes, "reason": ""}


## A private copy of [param pattern] with the landing constraints cleared and ALLY aimed at
## the caster itself. Range numbers are untouched on purpose (the board's
## reach_is_unbounded skips the range test; Weather.is_ranged still reads max_range).
static func compile_pattern(pattern: TargetingPattern) -> TargetingPattern:
	if pattern == null:
		return null
	var p := pattern.duplicate(false) as TargetingPattern
	p.requires_empty_cell = false
	p.requires_adjacent_enemy = false
	p.aim_rule = null
	match p.target_kind:
		CombatTypes.TargetKind.ALLY:
			p.target_kind = CombatTypes.TargetKind.SELF
			p.affects_caster_tile = true
		CombatTypes.TargetKind.EMPTY_TILE:
			p.target_kind = CombatTypes.TargetKind.TILE
	return p


## The script class chain of [param effect], most-derived first
## (e.g. ["StackConsumeDamageEffect", "DamageEffect", "MoveEffect"]).
static func effect_class_chain(effect) -> Array[String]:
	var out: Array[String] = []
	if effect == null or not (effect is Object):
		return out
	var script: Script = effect.get_script()
	while script != null:
		var n := String(script.get_global_name())
		if n != "":
			out.append(n)
		script = script.get_base_script()
	return out


## Would [param character] field a moveset that can damage the foe? (The Solo picker lists
## only eligible units.)
static func is_duel_eligible(character: CharacterResource, ruleset: DuelRuleset = null) -> bool:
	var res := compile(character, ruleset)
	if not bool(res["success"]):
		return false
	return (res["character"] as DuelCharacter).duel_eligible


# --- internals ---------------------------------------------------------------------

static func _compile_effects(list: Array, ruleset: DuelRuleset, notes: Array[String]) -> Dictionary:
	var out: Array[MoveEffect] = []
	for effect in list:
		if effect == null:
			continue
		var chain := effect_class_chain(effect)
		var label: String = chain[0] if not chain.is_empty() else "effect"
		match ruleset.policy_for_effect_classes(chain):
			DuelRuleset.POLICY_DROP:
				notes.append("%s has no effect in duels" % _pretty(label))
			DuelRuleset.POLICY_EXCLUDE:
				notes.append("%s cannot be used in duels" % _pretty(label))
				return {"effects": out, "excluded": true, "reason": "excluded_" + label}
			DuelRuleset.POLICY_CONVERT_DAMAGE:
				out.append(_as_damage(effect))
				notes.append("%s strikes in place in duels" % _pretty(label))
			DuelRuleset.POLICY_KEEP_IF_STATIONARY:
				if _fires_for_stationary(effect):
					out.append(effect.duplicate(false) as MoveEffect)
				else:
					notes.append("%s needs a unit to step on it" % _pretty(label))
					return {"effects": out, "excluded": true, "reason": "excluded_" + label}
			_:
				out.append(effect.duplicate(false) as MoveEffect)
	return {"effects": out, "excluded": false, "reason": ""}


## A plain [DamageEffect] carrying [param source]'s numbers (a dash that no longer travels).
static func _as_damage(source) -> MoveEffect:
	var d := DamageEffect.new()
	for key in ["power", "scaling_stat", "scale", "category"]:
		if key in source:
			d.set(key, source.get(key))
	return d


## True for an ApplyTileEffect whose tile effect fires for an occupant that never moves.
static func _fires_for_stationary(effect) -> bool:
	var te = effect.get("effect")
	if te == null or not (te is TileEffectResource):
		return false
	if bool(te.springs_on_pass):
		return false
	return te.trigger == TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING \
		or te.trigger == TileEffectResource.Trigger.PASSIVE_WHILE_OCCUPYING


static func _has_offensive_move(moves: Array[MoveResource]) -> bool:
	for m in moves:
		for pattern in [m.targeting, m.alt_targeting]:
			if pattern != null and int(pattern.target_kind) in OFFENSIVE_KINDS:
				return true
	return false


## Copy every stored property of [param src] onto [param dst] (a fresh DuelCharacter), so
## the private copy carries the roster entry's identity, stats, model and profile.
static func _copy_character(src: CharacterResource, dst: CharacterResource) -> void:
	for prop in src.get_property_list():
		var usage: int = int(prop["usage"])
		if not (usage & PROPERTY_USAGE_STORAGE) or not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var pname: String = prop["name"]
		if pname in ["moveset", "abilities"]:
			continue
		dst.set(pname, src.get(pname))


## "KnockbackEffect" -> "Knockback".
static func _pretty(class_label: String) -> String:
	return class_label.trim_suffix("Effect")
