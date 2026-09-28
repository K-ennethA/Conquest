extends Node

## Autoload owning the single, shared, live [BoardAdapter] for a running match.
##
## Movement, attacks, AI and tile logic must all read board state through the
## same adapter so they agree on where every unit is. Rather than each system
## constructing its own [BoardAdapter] (and risking divergent snapshots), they
## fetch the one instance owned here via [method board].
##
## The adapter is rebuilt once per map load (see [method rebuild]) because a new
## map produces a fresh set of [Unit] nodes under a new "Map" root. Between the
## autoload coming up and the first successful map load, [method board] returns
## null -- callers MUST null-check.
##
## Wiring: [code]GameWorldManager[/code] calls [method rebuild] with the "Map"
## node the [MapLoader] populated, and [method clear] when the map is torn down.

## Grid resource shared by the whole board (col = X, row = Z, grid y = floor).
const GRID: Grid = preload("res://board/Grid.tres")

## Emitted after [method rebuild] installs a fresh, live [BoardAdapter].
signal board_ready
## Emitted when a cell's RUNTIME tile effects change (a move ignited/doused it),
## so the 3D map overlay can restack that cell's effect markers reactively.
signal tile_effects_changed(cell: Vector3i)

## Deterministic RNG for a NETWORK match (see [NetGameRules]). Null in
## single-player / hotseat, where every [MoveContext] keeps its own randomized
## generator exactly as before. While a network match applies an accepted action
## this holds a generator seeded from (match seed, action seq), and any
## MoveContext created without an injected rng (abilities, status ticks, tile
## effects) draws from it, so every peer rolls identically.
var match_rng: RandomNumberGenerator = null

## Relays [signal WeatherState.changed] for the live battle (HUD chip, WeatherFX,
## announcer). [param weather] / [param previous] are [WeatherResource]s.
signal weather_changed(weather, previous)

## The live battle weather (see [WeatherState], docs/WEATHER.md). Always present;
## permanent Clear until [method configure_weather] runs on map load. Advanced by
## the turn systems' per-unit turn-start tick with the current round, so it is a
## pure function of (map settings, seed, applied actions) on every peer.
var weather: WeatherState = null

## The single live adapter. Null until the first successful [method rebuild].
var _board: BoardAdapter = null

## Shared terrain registry: cell ([Vector3i]) -> [TileResource].
##
## Populated by [MapLoader] via [method register_tile] as it instantiates tiles,
## and read back by the live [BoardAdapter] (which is handed this exact
## dictionary in [method rebuild]) to answer terrain queries -- move cost,
## blocking, tile id/tag. Mutating in place (never reassigned) keeps the adapter
## and this autoload pointed at the same data, so [BoardAdapter.set_tile] updates
## are visible through [method tile_at] and vice-versa.
var _tile_registry: Dictionary = {}

## Every UPPER-floor cell (floor > 0) that has a tile, [Vector3i] -> true -- even a
## tile whose [TileResource] failed to resolve. Floor 0 is implicitly full. Handed
## to the adapter by reference in [method rebuild] ([method BoardAdapter.set_present_cells]).
var _present_cells: Dictionary = {}

## Cross-floor links (stairs / ladders) for the loaded map, as raw link dictionaries
## ({from, to, cost, kind, bidirectional}); registered by [MapLoader] and handed to
## the adapter in [method rebuild] ([method BoardAdapter.set_links]).
var _links: Array = []

# --- Tile effect lookup (T14) -----------------------------------------------
#
# Maps a cell to the [TileEffectResource]s acting on it, for the
# [TileEffectSystem] (consumed via [GameWorldManager]). Two layers:
#   * BASE    -- derived from the tile TYPE at the cell: fire on lava, empowering
#                water on deep water, fortify on sacred ground. Immutable content,
#                authored as .tres under game/tiles/effects/resources/.
#   * APPLIED -- a per-cell runtime set that moves mutate to ignite/douse a tile
#                (see [method add_tile_effect] / [method remove_tile_effect]).
# [method tile_effects_at] merges base + applied, so a transform that adds a
# runtime fire effect stacks on top of whatever the terrain already imposes.

## Canonical tile id ([BoardAdapter]'s scheme: lowercased [enum Tile.TileType]
## name) -> authored .tres effect paths for that terrain.
##
## These stay PATH-addressed on purpose, unlike the tile tables in [BoardAdapter]
## and [MapLoader] which now resolve stable [member TileResource.id]s through
## [TileCatalog]. Two reasons: EFFECTS are a separate resource family with no
## equivalent index (there is no catalog scanning game/tiles/effects/resources/,
## which is a flat directory that has never been reorganised), and this table is
## ENGINE-INTERNAL - it is not written into player-authored maps, so a stale entry
## here is a build-time bug someone fixes, not a shared map that silently breaks on
## another install. Path fragility is only worth designing around where the
## reference escapes the codebase. If the effect resources ever get grouped into
## subfolders, give [TileEffectResource] the same treatment: index its existing
## [code]id[/code] and look these up by it.
const _TILE_EFFECT_PATHS := {
	&"lava": ["res://game/tiles/effects/resources/fire.tres"],
	&"water": ["res://game/tiles/effects/resources/empowering_water.tres"],
	&"sacred_ground": ["res://game/tiles/effects/resources/fortify.tres"],
	# NOTE: DIFFICULT_TERRAIN is deliberately NOT mapped here. Both Tall Grass and
	# Trees use that type but must differ (grass grants evasion, trees do nothing),
	# so each declares its own effects on the TileResource instead -- see
	# _base_effects_for_tile.
}

## Cache: canonical tile id -> [code]Array[TileEffectResource][/code] (base effects).
var _base_tile_effects: Dictionary = {}

## Runtime applied effects: cell ([Vector3i]) -> [code]Array[TileEffectResource][/code].
var _applied_tile_effects: Dictionary = {}


func _init() -> void:
	weather = WeatherState.new()
	weather.changed.connect(_on_weather_changed)


## Start this battle's weather from [param map] (a [MapResource]; null = Clear).
## [param weather_seed] seeds dynamic weather: the match's public setup seed in a
## network match (identical on every peer), any value in single-player.
func configure_weather(map, weather_seed: int) -> void:
	var settings: Dictionary = {}
	if map != null and map.has_method("get_weather_settings"):
		settings = map.get_weather_settings()
	weather.configure(settings, weather_seed)


## Advance the weather to [param round_number] (no-op unless later). Called from
## [method TurnSystemBase._tick_unit_turn_start] before any per-unit tick.
func advance_weather(round_number: int) -> void:
	if weather.advance_to_round(round_number):
		return  # _on_weather_changed already doused
	_douse_suppressed_tile_effects()


func _on_weather_changed(now, previous) -> void:
	_douse_suppressed_tile_effects()
	if DisplayServer.get_name() == "headless" and now != null:
		# Server / bot logs: lets the multi-process net check show the weather moving.
		print_verbose("[Weather] round %d -> %s" % [weather.round, now.id])
	weather_changed.emit(now, previous)


## Remove RUNTIME tile effects the active weather suppresses (Rain puts out fires a
## move lit). Base terrain effects are never removed -- they are merely inert while
## suppressed (see [method TileEffectSystem._run_trigger]).
func _douse_suppressed_tile_effects() -> void:
	var w: WeatherResource = weather.current if weather != null else null
	if w == null or w.suppressed_tile_effects.is_empty():
		return
	var cells: Array = _applied_tile_effects.keys()
	cells.sort_custom(func(a, b): return Cells.less(a, b))
	for cell in cells:
		for te in applied_tile_effects_at(cell):
			if te != null and w.suppresses(StringName(te.get("id") if te.get("id") != null else &"")):
				remove_tile_effect(cell, te)


## Rebuild the shared [BoardAdapter] against a freshly loaded map.
##
## [param map_root] is the "Map" node the [MapLoader] populated; it doubles as
## the adapter's units provider (its [Unit] descendants are gathered live). After
## constructing the adapter this runs [method _assert_units_round_trip] and emits
## [signal board_ready].
func rebuild(map_root: Node3D) -> void:
	if map_root == null:
		push_warning("[CombatServices] rebuild called with null map_root; board not rebuilt.")
		return
	_board = BoardAdapter.new(GRID, map_root)
	# Hand the adapter the shared terrain registry (same dictionary MapLoader just
	# populated for this map) so terrain queries and set_tile stay in sync with
	# tile_at(). The registry is intentionally NOT cleared here: MapLoader fills it
	# during load_map(), which runs BEFORE this rebuild -- it is cleared in
	# clear() (invoked before each map reload) instead.
	_board.set_tile_registry(_tile_registry)
	_board.set_present_cells(_present_cells)
	_board.set_links(_links)
	_assert_units_round_trip(_board, map_root)
	board_ready.emit()


## Drop the current adapter (e.g. when the map is cleared/torn down).
##
## After this [method board] returns null again until the next [method rebuild].
func clear() -> void:
	_board = null
	# Wipe the terrain registry so the next map starts clean (a smaller map would
	# otherwise leave stale out-of-bounds tiles behind). Mutated in place so the
	# reference handed to any adapter stays valid.
	_tile_registry.clear()
	_present_cells.clear()
	_links.clear()
	# Drop any runtime tile effects (ignited/doused cells) from the old map.
	_applied_tile_effects.clear()
	# Back to permanent Clear until the next map configures its weather.
	weather.reset()


## Register the [TileResource] backing [param cell] (called by [MapLoader]).
## [param res] may be null for an upper-floor tile with no resolvable resource: the
## cell still EXISTS (is walkable) but reads as flat default terrain.
func register_tile(cell: Vector3i, res) -> void:
	if res != null:
		_tile_registry[cell] = res
	if cell.z > 0:
		_present_cells[cell] = true
	if _board != null:
		_board.refresh_floors()


## Register a cross-floor link (called by [MapLoader] from [method MapResource.get_links]).
## Takes effect on the next [method rebuild] (or immediately if a board is live).
func register_link(link: Dictionary) -> void:
	_links.append(link)
	if _board != null:
		_board.set_links(_links)


## The registered links (raw dictionaries, see [method register_link]).
func get_links() -> Array:
	return _links.duplicate()


## The [TileResource] bound to [param cell], or null if none is registered.
func tile_at(cell: Vector3i) -> TileResource:
	var r = _tile_registry.get(cell, null)
	return r if r is TileResource else null


## All [TileEffectResource]s acting on [param cell]: the BASE effects from the
## tile type first, then the runtime APPLIED set. This is the cell->effects
## lookup the [TileEffectSystem] consumes (fed in via [GameWorldManager] because
## the live [BoardAdapter] does not expose one). Never returns null.
func tile_effects_at(cell: Vector3i) -> Array:
	var out: Array = []
	var res := tile_at(cell)
	if res != null:
		for te in _base_effects_for_tile(res):
			if te != null:
				out.append(te)
	var applied = _applied_tile_effects.get(cell, null)
	if applied is Array:
		for te in applied:
			if te != null and te not in out:
				out.append(te)
	return out


## Just the RUNTIME (applied-this-battle) tile effects on [param cell], excluding
## the terrain's inherent base effects. Lets the UI mark those as temporary. Never
## returns null; the returned array is a copy, safe to iterate while mutating.
func applied_tile_effects_at(cell: Vector3i) -> Array:
	var applied = _applied_tile_effects.get(cell, null)
	if applied is Array:
		return applied.duplicate()
	return []


## Every cell currently carrying at least one RUNTIME (applied) tile effect.
##
## The APPLIED layer's key set and nothing else -- map-authored terrain is derived from the
## tile type and never appears here, which is precisely what makes this the enumeration a
## placed-trap sweep may walk ([method TileEffectSystem.expire_placed_effects]) without any
## risk of reaching authored ground. A copy of the keys, safe to iterate while removing.
func applied_effect_cells() -> Array:
	return _applied_tile_effects.keys()


## Add a runtime tile effect to [param cell] (e.g. a move ignites the ground into
## fire). Idempotent; the effect layers on top of the tile's base effects.
func add_tile_effect(cell: Vector3i, effect) -> void:
	if effect == null:
		return
	var applied = _applied_tile_effects.get(cell, null)
	if not (applied is Array):
		applied = []
		_applied_tile_effects[cell] = applied
	if effect not in applied:
		applied.append(effect)
		tile_effects_changed.emit(cell)


## Remove a runtime tile effect from [param cell] (e.g. a move douses the fire).
## Only affects the runtime set; base terrain effects are never removed here.
func remove_tile_effect(cell: Vector3i, effect) -> void:
	var applied = _applied_tile_effects.get(cell, null)
	if applied is Array and effect in applied:
		applied.erase(effect)
		if applied.is_empty():
			_applied_tile_effects.erase(cell)
		tile_effects_changed.emit(cell)


## Canonical terrain id for a [TileResource] -- the lowercased [enum
## Tile.TileType] name (LAVA -> &"lava"), matching [BoardAdapter]'s id scheme.
func _tile_effect_id_of(res: TileResource) -> StringName:
	if res == null:
		return &""
	var keys := Tile.TileType.keys()
	var idx := int(res.tile_type)
	if idx >= 0 and idx < keys.size():
		return StringName(String(keys[idx]).to_lower())
	return &""


## Base [TileEffectResource]s for a specific tile.
##
## A tile's OWN declaration wins: when [member TileResource.has_default_effects] is
## set, [member TileResource.default_effects] is authoritative (an empty list then
## means "explicitly no effects"). Only tiles that declare nothing fall back to the
## per-TileType table below.
##
## This is what lets two tiles of the SAME [enum Tile.TileType] behave differently
## -- e.g. Tall Grass and Trees are both DIFFICULT_TERRAIN, but only the grass
## grants evasion. Keying effects purely by type could never express that.
func _base_effects_for_tile(res: TileResource) -> Array:
	if res == null:
		return []
	if res.has_default_effects:
		var declared: Array = []
		for te in res.default_effects:
			if te is TileEffectResource:
				declared.append(te)
		return declared
	return _base_effects_for_id(_tile_effect_id_of(res))


## Base [TileEffectResource]s for a canonical terrain id, lazily loaded from the
## authored .tres and cached. Falls back to [TileEffectLibrary] if a .tres is
## missing or fails to load, so the system still works without the files.
func _base_effects_for_id(tile_id: StringName) -> Array:
	if tile_id == &"":
		return []
	if _base_tile_effects.has(tile_id):
		return _base_tile_effects[tile_id]
	var out: Array = []
	if _TILE_EFFECT_PATHS.has(tile_id):
		for path in _TILE_EFFECT_PATHS[tile_id]:
			var res = _load_tile_effect(path, tile_id)
			if res != null:
				out.append(res)
	_base_tile_effects[tile_id] = out
	return out


## Load one authored [TileEffectResource], falling back to the code factory.
func _load_tile_effect(path: String, tile_id: StringName):
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is TileEffectResource:
			return res
	return _fallback_tile_effect(tile_id)


## Code-factory fallback mirroring the authored .tres content.
func _fallback_tile_effect(tile_id: StringName):
	match tile_id:
		&"lava":
			return TileEffectLibrary.fire()
		&"water":
			return TileEffectLibrary.empowering_water()
		&"sacred_ground":
			return TileEffectLibrary.fortify()
	return null


## The single shared live adapter, or null before the first [method rebuild].
##
## Callers MUST null-check the result; there is intentionally no board between
## the autoload starting and the first map load completing.
func board() -> BoardAdapter:
	return _board


## Startup assertion: verify every spawned [Unit] round-trips through the board.
##
## For each unit we take its cell via [code]board.cell_of(unit)[/code], map that
## cell back to a world center via [code]board.cell_to_world(cell)[/code], and
## check it lands within one cell of the unit's [code]global_position[/code].
##
## This guards the known risk that [MapLoader] centers units at
## [code]grid_pos * 2 + 1[/code] while [method Grid.calculate_map_position] may
## center cells differently -- if the two ever disagree, movement and attacks
## would target the wrong tiles. On mismatch we log loudly but never crash, so a
## bad map surfaces in the log instead of taking down the game.
func _assert_units_round_trip(board_adapter: BoardAdapter, map_root: Node3D) -> void:
	if board_adapter == null or map_root == null:
		return

	var units: Array = _gather_units(map_root)
	if units.is_empty():
		return

	# Derive "one cell" in world units from the adapter itself so this stays
	# correct if the grid's cell_size changes. The step between adjacent cell
	# centers equals the grid's cell_size on each axis.
	var origin: Vector3 = board_adapter.cell_to_world(Vector3i.ZERO)
	var step_x: float = absf(board_adapter.cell_to_world(Vector3i(1, 0, 0)).x - origin.x)
	var step_z: float = absf(board_adapter.cell_to_world(Vector3i(0, 1, 0)).z - origin.z)
	var tolerance: float = maxf(maxf(step_x, step_z), 0.001)

	var mismatches: int = 0
	# Detail of the FIRST offender only. This sweep runs on every board rebuild, and it
	# used to push one warning PER offending unit plus a summary -- so a systematic
	# centering mismatch (which affects every unit at once, the exact case this guards)
	# emitted N+1 debugger warnings on each rebuild. One line carries the same diagnosis.
	var first_detail: String = ""
	for unit in units:
		if unit == null or not is_instance_valid(unit):
			continue
		var actual: Vector3 = unit.global_position
		var cell: Vector3i = board_adapter.cell_of(unit)
		var expected: Vector3 = board_adapter.cell_to_world(cell)
		# Compare on the XZ plane only: MapLoader lifts units to Y = 1.5 while the
		# grid centers cells at Y = 0, which is an intended height offset, not a
		# cell mismatch.
		var dx: float = actual.x - expected.x
		var dz: float = actual.z - expected.z
		var planar_dist: float = sqrt(dx * dx + dz * dz)
		if planar_dist > tolerance:
			mismatches += 1
			if first_detail.is_empty():
				first_detail = "'%s' global=%s -> cell=%s -> world=%s (XZ off by %.3f, tolerance %.3f)" \
					% [unit.name, str(actual), str(cell), str(expected), planar_dist, tolerance]

	if mismatches > 0:
		push_warning(
			"[CombatServices] Board rebuilt with %d of %d unit(s) failing the cell round-trip; first: %s. Likely a MapLoader vs Grid.calculate_map_position centering mismatch."
			% [mismatches, units.size(), first_detail]
		)


## Recursively collect [Unit] descendants under [param node] (mirrors the way
## [BoardAdapter] gathers units from a Node provider) so the assertion checks the
## same set of units the adapter will serve.
func _gather_units(node: Node) -> Array:
	var out: Array = []
	for child in node.get_children():
		if child is Unit:
			out.append(child)
		out.append_array(_gather_units(child))
	return out
