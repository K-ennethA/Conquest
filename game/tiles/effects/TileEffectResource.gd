extends Resource
class_name TileEffectResource

## A data-driven behaviour that a tile imposes on the unit standing on it.
##
## Built on the shared effect pipeline: a tile effect simply owns a list of
## [MoveEffect]s that fire when its [member trigger] occurs — exactly the same
## resolution path a move or a [StatusCondition] uses. So authoring a burning,
## empowering, fortifying, or hiding tile is data, not code: fire is a
## [TileEffectResource] whose effects = [DamageEffect]; empowering water is one
## whose effects = [StatModifierEffect] gated by a [member required_unit_tag].
##
## Effects are resolved through a minimal SELF-targeted [MoveContext] built over
## the occupant's own cell (see [method run]), mirroring [method
## StatusCondition.tick]. State that isn't a mutation — stealth, fortification —
## is expressed as [member rule_flags] so other systems (e.g. targeting) can
## query it without anything being applied.

## When the effect fires for an occupying unit.
enum Trigger {
	ON_ENTER,                       ## once, when a unit steps onto the tile
	ON_TURN_START_WHILE_OCCUPYING,  ## each turn start the unit is still on it
	ON_EXIT,                        ## once, when a unit leaves the tile
	PASSIVE_WHILE_OCCUPYING,        ## a standing state, not a per-event mutation
}

## Which occupants the effect is allowed to touch. Perspective for the ENEMIES /
## ALLIES variants is a reference unit the board supplies via a duck-typed
## [code]perspective_unit()[/code]; without one, those variants match nobody.
enum AffectedFactions {
	ALL,               ## any occupant
	OCCUPANT_ENEMIES,  ## occupants hostile to the tile/board perspective
	OCCUPANT_ALLIES,   ## occupants friendly to the tile/board perspective
}

@export var id: StringName = &""
@export var display_name: String = ""
@export var trigger: Trigger = Trigger.ON_ENTER
@export var affected_factions: AffectedFactions = AffectedFactions.ALL

## Empty = affects any unit. Otherwise only affects a unit that reports the tag,
## either via a duck-typed [code]has_tag(tag)[/code] method or a [code]tags[/code]
## array property. This is how "water empowers only aquatic units" is authored.
@export var required_unit_tag: StringName = &""

## Effects applied to the occupant when the trigger fires, in order.
@export var effects: Array[MoveEffect] = []

## RUNTIME owner of a PLACED effect (a trap laid by a unit), stamped by
## ApplyTileEffect at cast time; null for map-authored terrain. When set, the
## OCCUPANT_ENEMIES / OCCUPANT_ALLIES faction check is resolved against THIS owner
## (via the occupant's own get_owner_player) instead of the board perspective -- so a
## trap only springs on its placer's enemies and spares the placer's own side. Not
## exported: it is set live, per placement.
var owner_player = null

## Passive states that are queried rather than applied, e.g.
## [code]{ "untargetable": true }[/code] (stealth) or
## [code]{ "fortified": true }[/code]. Merged by [method TileEffectSystem.passive_flags].
@export var rule_flags: Dictionary = {}


## True if this effect is allowed to act on [param unit] right now — combines the
## faction filter and the [member required_unit_tag] filter.
func applies_to(unit, board) -> bool:
	if unit == null:
		return false
	if not _faction_ok(unit, board):
		return false
	if not _tag_ok(unit):
		return false
	return true


## Apply every effect to [param unit] once, resolved through a SELF-targeted
## [MoveContext] over the unit's cell (the same pipeline a move uses). Does NOT
## re-check [method applies_to] — callers filter first. Returns the event log.
func run(unit, board) -> Array:
	var events: Array = []
	if unit == null or board == null:
		return events
	var cell: Vector2i = Vector2i.ZERO
	if board.has_method("cell_of"):
		cell = board.cell_of(unit)
	var ctx := MoveContext.new(unit, board, _self_move(), cell, [cell] as Array[Vector2i])
	for effect in effects:
		if effect:
			effect.apply(ctx)
	for e in ctx.results:
		events.append(e)
	return events


func _faction_ok(unit, board) -> bool:
	match affected_factions:
		AffectedFactions.OCCUPANT_ENEMIES:
			# A PLACED trap knows its owner: only its owner's ENEMIES spring it. A unit
			# with no owner (or the placer's own side) is spared.
			if owner_player != null:
				var occ = _unit_owner(unit)
				return occ != null and occ != owner_player
			var ref = _perspective(board)
			return ref != null and board.has_method("are_enemies") and board.are_enemies(ref, unit)
		AffectedFactions.OCCUPANT_ALLIES:
			if owner_player != null:
				return _unit_owner(unit) == owner_player
			var ref = _perspective(board)
			return ref != null and board.has_method("are_allies") and board.are_allies(ref, unit)
		_:  # ALL
			return true


## The owning Player of [param unit], or null (duck-typed for mocks).
static func _unit_owner(unit):
	if unit != null and unit.has_method("get_owner_player"):
		return unit.get_owner_player()
	return null


func _tag_ok(unit) -> bool:
	if required_unit_tag == &"":
		return true
	return _unit_has_tag(unit, required_unit_tag)


static func _perspective(board):
	if board and board.has_method("perspective_unit"):
		return board.perspective_unit()
	return null


## Duck-typed tag check: prefer a [code]has_tag()[/code] method, else read a
## [code]tags[/code] array property.
static func _unit_has_tag(unit, tag: StringName) -> bool:
	if unit == null:
		return false
	if unit.has_method("has_tag"):
		return unit.has_tag(tag)
	var tags = unit.get("tags")
	if tags is Array:
		for t in tags:
			if StringName(t) == tag:
				return true
	return false


## Synthetic self-targeted move used to route effects through a [MoveContext].
## SELF targeting makes [method MoveContext.gather_targets] return exactly the
## occupying unit.
func _self_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = id if id != &"" else &"tile_effect"
	m.display_name = display_name
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.SELF
	pattern.min_range = 0
	pattern.max_range = 0
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	m.targeting = pattern
	return m
