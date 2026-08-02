extends RefCounted

## Shared, duck-typed test doubles for Conquest's combat/board pipeline.
##
## WHY THIS FILE EXISTS: ~24 suites had hand-rolled `class MockUnit` / `class MockBoard`
## copies. They drifted, and drift is dangerous here because the production code is
## DUCK-TYPED -- `DamageEffect`, `MoveExecutor`, `StatModifierStatus`, `TileEffectResource`
## and friends all branch on `has_method(...)`. Two mocks that "look the same" but differ
## by one method exercise DIFFERENT production code paths.
##
## THE RULE THAT SHAPES THIS FILE: each double is an EXACT SHAPE, never a kitchen sink.
## Do NOT add a convenience method to a base class "because it might be handy" -- adding
## `get_base_stat` to [CombatUnit] silently reroutes every damage calculation in every
## suite that uses it (see DamageEffect.gd: `has_method("get_stat") and
## has_method("get_base_stat")`). If your test needs one more method, add a NEW small
## subclass here and name what it is for.
##
## Methods the production code branches on, and who owns them:
##   get_base_stat        -> DamageEffect (defense mitigation), HealEffect, MovementResolver
##   get_hp               -> MoveExecutor / BotController (HP bookkeeping)
##   add_stat_modifier    -> StatModifierEffect, StatModifierStatus, BaseAssaultRuntime
##   add_status           -> ApplyStatusEffect (direct sink)
##   get_status_controller-> ApplyStatusEffect, DamageEffect, ItemSystem, InfestEffect
##   all_units            -> BotController, ItemSystem, CampaignController, win conditions
##   tile_tag_at          -> OnTerrainCondition, OnTerrainTagCondition, MovementResolver
##   tile_effects_at      -> TileEffectSystem, ElementChart, TerrainStats, MovementResolver
##   perspective_unit     -> TileEffectResource (faction filters)
##   move_unit / set_tile -> KnockbackEffect, LeapEffect, TileTransformEffect
##
## USAGE (this script has no class_name on purpose -- tests/ must not pollute the global
## class registry):
## [codeblock]
## const Doubles := preload("res://tests/helpers/test_doubles.gd")
##
## func test_something() -> void:
##     var caster := Doubles.CombatUnit.new(0, {"attack": 30, "health": 100})
##     var board := Doubles.CombatBoard.new()
##     board.place(caster, Vector2i(0, 0))
## [/codeblock]
##
## Every double here is a [RefCounted]: they are collected automatically and can never
## show up in GUT's orphan count. If you need a double that is a [Node], you own freeing
## it -- see tests/README.md ("Orphans").


# =============================================================================
# UNITS
# =============================================================================

## The canonical combat target: stats, HP, and a stat-modifier sink.
## Shape verified identical to the hand-rolled mocks in test_move_system.gd and
## test_abilities.gd. Deliberately has NO `get_base_stat`, NO `get_hp` and NO
## `get_status_controller` -- adding any of them changes which branch the effect
## pipeline takes.
class CombatUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var modifiers: Array = []

	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))

	func take_damage(n: int) -> void:
		hp -= n

	func heal(n: int) -> void:
		hp += n

	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({"stat": stat, "amount": amount, "duration": duration})
		return modifiers.size()


## A [CombatUnit] that also carries unit TAGS, which [TileEffectResource] reads to decide
## whether a tile effect applies to it.
class TaggedCombatUnit extends CombatUnit:
	var tags: Array = []

	func _init(p_team: int, p_stats: Dictionary, p_tags: Array = []) -> void:
		super(p_team, p_stats)
		tags = p_tags


## A stats/HP target with a DIRECT status sink (`add_status`) and no modifier support.
## This is the shape [ApplyStatusEffect] takes its first branch on, so a status lands on
## `added_statuses` without a live StatusController Node in play.
class StatusSinkUnit:
	var team: int
	var stats: Dictionary
	var hp: int
	var added_statuses: Array = []

	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))

	func take_damage(n: int) -> void:
		hp -= n

	func heal(n: int) -> void:
		hp += n

	func add_status(condition) -> void:
		added_statuses.append(condition)


## The smallest useful target: stats and HP only. Use this when the test is about
## TARGETING (who gets gathered) rather than about what the effects do to them.
class SimpleUnit:
	var team: int
	var stats: Dictionary
	var hp: int

	func _init(p_team: int, p_stats: Dictionary) -> void:
		team = p_team
		stats = p_stats
		hp = int(stats.get("health", 100))

	func get_stat(stat_name: String) -> int:
		return int(stats.get(stat_name, 0))

	func take_damage(n: int) -> void:
		hp -= n

	func heal(n: int) -> void:
		hp += n


## A [SimpleUnit] that also answers `get_hp()`, which routes [MoveExecutor] and
## [BotController] through their HP-aware bookkeeping instead of `get_stat("health")`.
class HpUnit extends SimpleUnit:
	func get_hp() -> int:
		return hp


## An OBJECTIVE-shaped unit for win/lose-condition tests: identity and liveness, no stats.
class ObjectiveUnit:
	var team: int
	var hp: int
	var unit_id: StringName
	var is_boss: bool

	func _init(p_team: int, p_hp: int = 100, p_id: StringName = &"", p_is_boss: bool = false) -> void:
		team = p_team
		hp = p_hp
		unit_id = p_id
		is_boss = p_is_boss


# =============================================================================
# BOARDS
# =============================================================================

## Placement + faction queries only. The floor every other board builds on.
## Answers exactly: place / cell_of / units_at / are_enemies / are_allies.
class MinimalBoard:
	## `{ unit, cell }` records, in placement order.
	var placements: Array = []

	func place(unit, cell: Vector2i) -> void:
		placements.append({"unit": unit, "cell": cell})

	## The cell [param unit] stands on, or a far-off sentinel when it is not placed --
	## never an error, so an "unplaced target" test asserts on a value instead of a crash.
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


## The default board for effect-pipeline tests: adds the two mutators the movement and
## terrain effects need ([KnockbackEffect] / [LeapEffect] use `move_unit`,
## [TileTransformEffect] uses `set_tile`).
class CombatBoard extends MinimalBoard:
	var tiles: Dictionary = {}

	func set_tile(cell: Vector2i, tile_id) -> void:
		tiles[cell] = tile_id

	func move_unit(unit, to_cell: Vector2i) -> void:
		for p in placements:
			if p.unit == unit:
				p.cell = to_cell


## A [CombatBoard] that answers terrain TAG queries, which is what
## [OnTerrainCondition] / [OnTerrainTagCondition] / [MovementResolver] branch on.
class TerrainBoard extends CombatBoard:
	var tags: Dictionary = {}

	func tag_tile(cell: Vector2i, tag: StringName) -> void:
		tags[cell] = tag

	func tile_tag_at(cell: Vector2i) -> StringName:
		return tags.get(cell, &"")


## A [CombatBoard] that serves TILE EFFECTS and a faction perspective, the two hooks
## [TileEffectSystem] and [TileEffectResource] consume.
##
## Note `tiles` is shared with `set_tile` on purpose -- that aliasing matches the
## hand-rolled mocks this replaced, where a tile IS its effect list.
class TileEffectBoard extends CombatBoard:
	## Reference unit for [TileEffectResource]'s faction filters.
	var perspective = null

	func tile_effects_at(cell: Vector2i) -> Array:
		return tiles.get(cell, [])

	func set_tile_effects(cell: Vector2i, effects: Array) -> void:
		tiles[cell] = effects

	func perspective_unit():
		return perspective


## A [MinimalBoard] that can enumerate everything on it. `all_units` is the hook win
## conditions, [BotController], [ItemSystem] and [CampaignController] branch on, so it is
## deliberately NOT on the base board.
class RosterBoard extends MinimalBoard:
	func all_units() -> Array:
		var out: Array = []
		for p in placements:
			out.append(p.unit)
		return out


# =============================================================================
# EVENT BUS
# =============================================================================

## Records every signal-shaped call instead of emitting, so a test can assert on ORDER --
## the thing a real bus makes hard to see (see test_kill_attribution_order.gd).
class RecordingBus:
	## Append-ordered `{ "name": StringName, "args": Array }` records.
	var calls: Array = []

	func record(event_name: StringName, args: Array = []) -> void:
		calls.append({"name": event_name, "args": args})

	func names() -> Array:
		var out: Array = []
		for c in calls:
			out.append(c.name)
		return out

	func clear() -> void:
		calls.clear()
