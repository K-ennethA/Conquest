extends AugmentEffect
class_name MoveModEffect

## The expressive centrepiece of the Arena's augment system: an effect that MODIFIES a
## unit's actual moves. Where [StatEffect] nudges a number, this reshapes what an ability
## DOES -- "this attack hits twice", "+1 range", "wider blast", "-1 cooldown", "one more
## charge". Each mod hooks the REAL combat model, so the change is felt exactly like an
## authored move:
##
##   extra_hits     -> appends duplicates of the move's primary [DamageEffect]; the
##                     [MoveExecutor] runs every effect in order, so each extra copy is a
##                     full, separately-mitigated damage instance (a real second hit).
##   bonus_range    -> raises the [TargetingPattern.max_range] (the pattern's authored
##                     reach; folded in by [method MoveResource.effective_max_range]).
##   aoe_expand     -> widens the [TargetingPattern.area_size]; a SINGLE-target pattern is
##                     promoted to a DIAMOND so the widening is actually visible.
##   cooldown_delta -> shifts [member MoveResource.cooldown] (tracked by [MovesetController]).
##   max_uses_delta -> shifts [member MoveResource.max_uses] for limited-charge moves.
##
## SHARED-RESOURCE SAFETY (critical). A live [Unit] reads its moves straight from its
## [member Unit.character_resource], and [CharacterLibrary] hands EVERY unit of a character
## the SAME cached [CharacterResource] instance -- which is also the .tres on disk. Mutating
## a move (or the moveset array) in place would permanently buff every copy of that unit and
## corrupt the roster file in-editor. So before touching anything this effect gives THIS unit
## a private character copy (a shallow [method Resource.duplicate] with its own moveset
## array), then deep-duplicates only the move(s) it changes and writes those duplicates back
## onto the private copy. The shared roster resource is never touched.

## Which of the unit's moves to modify.
enum Which {
	ALL,             ## every non-empty move
	FIRST_DAMAGING,  ## the first move that carries a DamageEffect
	BY_SLOT,         ## the single move in [member slot]
	BY_ELEMENT,      ## every move whose element matches [member element]
}

## Marks a CharacterResource this effect has already privatised for a unit, so stacking
## several MoveModEffects on one unit reuses the same private copy instead of re-cloning it.
const _PRIVATE_META: StringName = &"arena_private_moveset"

@export var which: Which = Which.FIRST_DAMAGING
## Slot (0..3) used only when [member which] is BY_SLOT.
@export var slot: int = 0
## Element key used only when [member which] is BY_ELEMENT (e.g. &"ember", &"frost").
@export var element: StringName = &""

## Extra full damage instances to add (1 = "hits twice"). Duplicates the move's primary
## DamageEffect this many times.
@export var extra_hits: int = 0
## Added reach (cells) on the move's targeting pattern.
@export var bonus_range: int = 0
## Widen the move's area of effect. A SINGLE-target move is promoted to a DIAMOND of this
## radius so the expansion is felt; a shaped move (SQUARE/DIAMOND/CROSS/LINE) grows by this.
@export var aoe_expand: int = 0
## Change to the move's cooldown (negative = readier). Floored at 0.
@export var cooldown_delta: int = 0
## Change to a limited move's charge count (positive = more uses). Unlimited moves (-1) are
## left unlimited.
@export var max_uses_delta: int = 0


func apply_to_unit(unit, _run) -> void:
	if unit == null or not unit.has_method("get"):
		return
	var character: CharacterResource = unit.get("character_resource")
	if character == null:
		return

	var targets: Array[int] = _resolve_target_indices(character)
	if targets.is_empty():
		return

	# Give THIS unit a private character copy the first time we touch it, so the shared
	# roster resource (and the .tres on disk) is never mutated. A shallow duplicate shares
	# every sub-resource; we then swap in a fresh moveset array (its own container, still
	# holding the shared move refs) so replacing an entry can never reach the original array.
	if not character.has_meta(_PRIVATE_META):
		var private_character: CharacterResource = character.duplicate(false)
		var fresh_moveset: Array[MoveResource] = []
		for existing_move in character.moveset:
			fresh_moveset.append(existing_move)
		private_character.moveset = fresh_moveset
		private_character.set_meta(_PRIVATE_META, true)
		unit.set("character_resource", private_character)
		character = private_character

	# Deep-duplicate each targeted move (so its targeting + effects are ours to edit) and
	# write the modified duplicate back into this unit's private moveset array.
	for idx in targets:
		var source_move: MoveResource = character.moveset[idx]
		if source_move == null:
			continue
		var modified: MoveResource = source_move.duplicate(true)
		_apply_mods(modified)
		character.moveset[idx] = modified


## Resolve the indices into [param character]'s moveset that [member which] selects.
func _resolve_target_indices(character: CharacterResource) -> Array[int]:
	var out: Array[int] = []
	var count: int = character.move_count()
	match which:
		Which.BY_SLOT:
			if slot >= 0 and slot < count and character.moveset[slot] != null:
				out.append(slot)
		Which.BY_ELEMENT:
			for i in range(count):
				var move: MoveResource = character.moveset[i]
				if move != null and move.element == element:
					out.append(i)
		Which.FIRST_DAMAGING:
			for i in range(count):
				var move: MoveResource = character.moveset[i]
				if move != null and _has_damage(move):
					out.append(i)
					break
		_:  # ALL
			for i in range(count):
				if character.moveset[i] != null:
					out.append(i)
	return out


## Apply every configured mod to one ALREADY-DUPLICATED move (its targeting and effects are
## private copies, so mutating them is safe).
func _apply_mods(move: MoveResource) -> void:
	if move.targeting != null:
		if bonus_range != 0:
			move.targeting.max_range = maxi(0, move.targeting.max_range + bonus_range)
		if aoe_expand > 0:
			if move.targeting.area_shape == CombatTypes.AreaShape.SINGLE:
				# SINGLE ignores area_size; promote it so the widening actually hits cells.
				move.targeting.area_shape = CombatTypes.AreaShape.DIAMOND
				move.targeting.area_size = maxi(0, move.targeting.area_size) + aoe_expand
			else:
				move.targeting.area_size = maxi(0, move.targeting.area_size + aoe_expand)

	if extra_hits > 0:
		var primary: DamageEffect = _primary_damage(move)
		if primary != null:
			for _i in range(extra_hits):
				var extra_hit: MoveEffect = primary.duplicate(true)
				move.effects.append(extra_hit)

	if cooldown_delta != 0:
		move.cooldown = maxi(0, move.cooldown + cooldown_delta)
	if max_uses_delta != 0 and move.max_uses >= 0:
		move.max_uses = maxi(0, move.max_uses + max_uses_delta)


## The move's first DamageEffect, or null if it deals no direct damage.
func _primary_damage(move: MoveResource) -> DamageEffect:
	for effect in move.effects:
		if effect is DamageEffect:
			return effect
	return null


## True if [param move] carries at least one DamageEffect.
func _has_damage(move: MoveResource) -> bool:
	for effect in move.effects:
		if effect is DamageEffect:
			return true
	return false


func describe() -> String:
	var parts: Array[String] = []
	if extra_hits == 1:
		parts.append("hits twice")
	elif extra_hits > 1:
		parts.append("hits %d extra times" % extra_hits)
	if bonus_range != 0:
		parts.append("%+d range" % bonus_range)
	if aoe_expand > 0:
		parts.append("wider area")
	if cooldown_delta != 0:
		parts.append("%+d cooldown" % cooldown_delta)
	if max_uses_delta != 0:
		parts.append("%+d uses" % max_uses_delta)
	if parts.is_empty():
		return "No move change"
	return "%s: %s" % [_which_label(), ", ".join(parts)]


## Human label for the selected move(s), used by [method describe].
func _which_label() -> String:
	match which:
		Which.FIRST_DAMAGING:
			return "Your first attack"
		Which.BY_SLOT:
			return "Move %d" % (slot + 1)
		Which.BY_ELEMENT:
			var elem_name: String = String(element)
			return "%s moves" % elem_name.capitalize() if elem_name != "" else "Elemental moves"
		_:
			return "Every move"
