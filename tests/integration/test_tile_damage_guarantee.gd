extends GutTest

## ENVIRONMENTAL DAMAGE IS NOT A SWING YOU CAN DODGE.
##
## This is the tile/hazard half of the bug [code]StatusCondition.tick[/code] already fixed
## for statuses. Tile effects resolve through the shared [MoveContext] pipeline, and that
## pipeline rolls [method MoveContext.hit_chance] -- which sums the defender's evasion AND
## the terrain avoid under it. A cell that is both TALL GRASS (+15 avoid) and ON FIRE
## therefore let its occupant dodge the fire it was standing in, roughly one turn in seven,
## on an unseeded per-tick generator that no two peers or replays agreed on.
##
## The fix is the same one line statuses got: [member MoveContext.guaranteed_hit], set in
## [method TileEffectResource.run]. [TravelingHazard] has always resolved off-pipeline
## through [method DamageMath.environment_damage] and so has never rolled; this file pins
## that too, because "it happens to be true today" is how it stops being true.
##
## WHAT IS REAL HERE: the shipped tile .tres content, the production [TileEffectSystem],
## the production [TileEffectResource.run] / [method TileEffectResource.damage_preview_for]
## pipeline, a real [TravelingHazard], and BOTH real turn systems' own
## [signal TurnSystemBase.turn_started] -- the signal GameWorldManager binds its tile tick
## to. The three-line body that signal reaches (iterate the player's units, prime the cell,
## call on_turn_start) is mirrored in [method _tick_tiles_for] rather than mounting the whole
## battle root; GameWorldManager's WIRING of it is covered by the live-board suites.
##
## The occupant is a local double (tests/README rule 5) whose whole point is a large
## evasion stat: adding one to a shared double would silently reroute every suite that uses
## it through the hit-roll branch under test.

const GRASS_PATH := "res://game/tiles/effects/resources/tall_grass.tres"

## fire.tres deals this much TRUE damage per tick. Asserted against the content itself in
## test_the_fire_content_is_what_this_file_assumes, so every exact-HP expectation has a
## stated source.
const FIRE_TICK_DAMAGE: int = 15

## Enough turns that a rolled path could not survive by luck: at the fixture's ~55% dodge
## chance, 200 consecutive landed ticks has probability ~10^-52.
const LONG_RUN_TICKS: int = 200


# --- Local doubles ----------------------------------------------------------

## A unit with a large evasion stat, so a hit roll (if one were still made) would visibly
## fail rather than marginally. Deep HP pool so a long tick run never kills it.
class _EvasiveUnit:
	var hp: int
	var max_health: int
	var modifiers: Array = []

	func _init(p_hp: int = 1000000) -> void:
		hp = p_hp
		max_health = p_hp

	func get_stat(stat_name: String) -> int:
		return 40 if stat_name == "evasion" else 0

	func get_base_stat(stat_name: String) -> int:
		return get_stat(stat_name)

	func take_damage(n: int) -> void:
		hp -= n

	func heal(n: int) -> void:
		hp = mini(max_health, hp + n)

	func add_stat_modifier(stat: String, amount: int, duration: int) -> int:
		modifiers.append({ "stat": stat, "amount": amount, "duration": duration })
		return modifiers.size()


## A board whose every occupied cell is tall grass ON FIRE -- the exact co-location the bug
## needed: the grass supplies real terrain avoid through [TerrainStats], the fire supplies
## the tick that used to be dodged.
class _BurningGrassBoard:
	var placements: Array = []
	var effects: Array = []

	func _init(p_effects: Array) -> void:
		effects = p_effects

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

	func are_enemies(_a, _b) -> bool:
		return true

	func are_allies(_a, _b) -> bool:
		return false

	func tile_effects_at(_cell: Vector2i) -> Array:
		return effects


# --- Fixtures ---------------------------------------------------------------

func _grass() -> TileEffectResource:
	return load(GRASS_PATH) as TileEffectResource


func _fire() -> TileEffectResource:
	return TileEffectLibrary.fire()


## Board + occupant, standing on burning tall grass at (0, 0).
func _burning_grass() -> Dictionary:
	var fire := _fire()
	var board := _BurningGrassBoard.new([_grass(), fire])
	var unit := _EvasiveUnit.new()
	board.place(unit, Vector2i(0, 0))
	return { "board": board, "unit": unit, "fire": fire }


## The three lines GameWorldManager's turn-start handler runs for one unit.
func _tick_tiles_for(system: TileEffectSystem, unit, board) -> void:
	system.on_turn_start(unit, board)


# ===========================================================================
#  THE FIXTURE ITSELF
# ===========================================================================

func test_the_fire_content_is_what_this_file_assumes() -> void:
	var fire := _fire()
	assert_eq(fire.trigger, TileEffectResource.Trigger.ON_TURN_START_WHILE_OCCUPYING,
		"fire burns at turn start while occupied")
	var dmg: DamageEffect = null
	for e in fire.effects:
		if e is DamageEffect:
			dmg = e as DamageEffect
	assert_not_null(dmg, "its payload is a DamageEffect")
	assert_eq(dmg.power, FIRE_TICK_DAMAGE, "worth 15 -- the number every HP assertion uses")
	assert_eq(dmg.category, CombatTypes.DamageCategory.TRUE,
		"as TRUE damage, so defense can never mask a tick that did fire")


func test_the_fixture_really_grants_terrain_avoid() -> void:
	# If this fails, every test below proves nothing: there would be no dodge to defeat.
	var fx: Dictionary = _burning_grass()
	assert_gt(TerrainStats.bonus_for(fx["unit"], "evasion", fx["board"]), 0,
		"tall grass under the occupant contributes real terrain avoid")
	var ctx := MoveContext.new(fx["unit"], fx["board"], _a_move(), Vector2i.ZERO,
		[Vector2i.ZERO] as Array[Vector2i])
	assert_lt(ctx.hit_chance(fx["unit"]), 100.0,
		"and an ORDINARY move against this occupant really would have to roll")


## A plain 100%-accuracy move, used only to show what the ordinary (rolling) path sees.
func _a_move() -> MoveResource:
	var m := MoveResource.new()
	m.move_id = &"test_probe"
	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.SELF
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	pattern.affects_caster_tile = true
	m.targeting = pattern
	return m


# ===========================================================================
#  THE GUARANTEE
# ===========================================================================

func test_a_fire_tile_burns_a_tall_grass_occupant_every_single_turn() -> void:
	# THE REGRESSION THIS FILE EXISTS FOR. Not "usually", not "on average" -- every tick,
	# for as long as it stands there.
	var fx: Dictionary = _burning_grass()
	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	var unit = fx["unit"]

	for i in range(LONG_RUN_TICKS):
		var before: int = unit.hp
		_tick_tiles_for(system, unit, fx["board"])
		assert_eq(before - unit.hp, FIRE_TICK_DAMAGE,
			"tick %d took exactly 15 off -- you cannot dodge the ground you are standing on" % [i + 1])


func test_the_burn_lands_on_every_turn_of_the_traditional_turn_system() -> void:
	# The tick rides the ACTIVE turn system's turn_started (project convention #2). Both
	# systems raise that signal, so both must burn.
	var fx: Dictionary = _burning_grass()
	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	var unit = fx["unit"]
	var ts: TraditionalTurnSystem = add_child_autofree(TraditionalTurnSystem.new())

	# GUT lambdas capture BY VALUE -- an Array is the only counter that survives (tests/README).
	var landed: Array = []
	var on_turn := func(_player):
		var before: int = unit.hp
		_tick_tiles_for(system, unit, fx["board"])
		landed.append(before - unit.hp)
	ts.turn_started.connect(on_turn)

	for turn in range(12):
		ts.current_turn = turn + 1
		ts.turn_started.emit(null)

	ts.turn_started.disconnect(on_turn)

	assert_eq(landed.size(), 12, "twelve turn boundaries, twelve ticks")
	for i in range(landed.size()):
		assert_eq(int(landed[i]), FIRE_TICK_DAMAGE,
			"Traditional turn %d burned for the full 15" % [i + 1])


func test_the_burn_lands_on_every_turn_of_the_speed_first_turn_system_too() -> void:
	var fx: Dictionary = _burning_grass()
	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	var unit = fx["unit"]
	var ts: SpeedFirstTurnSystem = add_child_autofree(SpeedFirstTurnSystem.new())

	var landed: Array = []
	var on_turn := func(_player):
		var before: int = unit.hp
		_tick_tiles_for(system, unit, fx["board"])
		landed.append(before - unit.hp)
	ts.turn_started.connect(on_turn)

	for turn in range(12):
		ts.current_turn = turn + 1
		ts.turn_started.emit(null)

	ts.turn_started.disconnect(on_turn)

	assert_eq(landed.size(), 12, "Speed First raises the same boundary")
	for i in range(landed.size()):
		assert_eq(int(landed[i]), FIRE_TICK_DAMAGE,
			"Speed First turn %d burned for the full 15 -- the rule is not a property of turn order" % [i + 1])


func test_the_guarantee_is_not_an_accident_of_a_low_evasion_stat() -> void:
	# Push evasion far past 100 so a rolled path would land NEVER rather than sometimes.
	# The tick must be completely indifferent to the number.
	var fire := _fire()
	var board := _BurningGrassBoard.new([_grass(), fire])
	var unit := _MassivelyEvasiveUnit.new()
	board.place(unit, Vector2i(0, 0))
	var system: TileEffectSystem = autofree(TileEffectSystem.new())

	var ctx := MoveContext.new(unit, board, _a_move(), Vector2i.ZERO, [Vector2i.ZERO] as Array[Vector2i])
	assert_eq(ctx.hit_chance(unit), 0.0, "an ordinary move against this occupant could never land")

	for _i in range(20):
		var before: int = unit.hp
		system.on_turn_start(unit, board)
		assert_eq(before - unit.hp, FIRE_TICK_DAMAGE,
			"the tile burns it anyway -- evasion is not a term in environmental damage at all")


## Evasion high enough that hit_chance clamps to 0. Local and deliberately separate from
## _EvasiveUnit so the ordinary-dodge fixture above keeps a REALISTIC number.
class _MassivelyEvasiveUnit extends _EvasiveUnit:
	func get_stat(stat_name: String) -> int:
		return 500 if stat_name == "evasion" else 0


# ===========================================================================
#  NO RNG IS CONSUMED
# ===========================================================================

func test_a_guaranteed_context_never_touches_its_generator() -> void:
	# The mechanism, pinned directly: guaranteed_hit short-circuits AHEAD of
	# MoveContext._get_rng, so the lockstep stream is not advanced by a tile tick. If this
	# ever regressed, every replay and every networked peer would desync on terrain damage.
	var fx: Dictionary = _burning_grass()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ctx := MoveContext.new(fx["unit"], fx["board"], _a_move(), Vector2i.ZERO,
		[Vector2i.ZERO] as Array[Vector2i])
	ctx.rng = rng
	ctx.guaranteed_hit = true

	var state_before: int = rng.state
	for _i in range(50):
		ctx._hit_cache.clear()   # force a fresh resolution each time, not a cached answer
		var outcome: Dictionary = ctx.resolve_hit(fx["unit"])
		assert_true(bool(outcome["hit"]), "it lands")
		assert_false(bool(outcome["crit"]), "and never crits -- environmental damage does not multiply")
	assert_eq(rng.state, state_before,
		"fifty guaranteed resolutions drew nothing from the generator")


func test_a_rolling_context_does_advance_the_generator() -> void:
	# The control for the test above: without the flag the same call DOES consume the stream,
	# which is what makes "unchanged state" evidence rather than a tautology.
	var fx: Dictionary = _burning_grass()
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var ctx := MoveContext.new(fx["unit"], fx["board"], _a_move(), Vector2i.ZERO,
		[Vector2i.ZERO] as Array[Vector2i])
	ctx.rng = rng

	var state_before: int = rng.state
	ctx.resolve_hit(fx["unit"])
	assert_ne(rng.state, state_before, "an ordinary roll really does advance the stream")


func test_the_same_tick_sequence_replays_identically() -> void:
	# Determinism, end to end and without reaching into the context: two independent runs of
	# the same tick sequence must produce byte-identical event logs. A tick that consulted a
	# generator at all -- seeded or not -- could not promise this, because a tile context is
	# built fresh per tick and carries no seed.
	var first: Array = _tick_log(30)
	var second: Array = _tick_log(30)
	assert_eq(first, second, "thirty ticks, twice, identical -- the tile path is deterministic")
	assert_eq(first.size(), 30, "and every one of them produced an event")


## The damage amounts logged by [param count] consecutive ticks on a fresh fixture.
func _tick_log(count: int) -> Array:
	var fx: Dictionary = _burning_grass()
	var system: TileEffectSystem = autofree(TileEffectSystem.new())
	var amounts: Array = []
	for _i in range(count):
		for event in system.on_turn_start(fx["unit"], fx["board"]):
			if String(event.get("effect", "")) == "damage":
				amounts.append(int(event.get("amount", -1)))
	return amounts


# ===========================================================================
#  PREVIEW == REALITY
# ===========================================================================

func test_the_damage_preview_equals_what_the_tick_actually_takes_off() -> void:
	# CONQUEST.md rule 9: the forecast and the board share one arithmetic. Now that the tick
	# cannot miss, the preview is not "damage on landing" -- it is the whole answer, so the
	# two must be equal with no chance term anywhere.
	var fx: Dictionary = _burning_grass()
	var fire: TileEffectResource = fx["fire"]
	var unit = fx["unit"]
	var system: TileEffectSystem = autofree(TileEffectSystem.new())

	var previewed: int = fire.damage_preview_for(unit, fx["board"])
	assert_eq(previewed, FIRE_TICK_DAMAGE, "the terrain card promises 15")

	var before: int = unit.hp
	system.on_turn_start(unit, fx["board"])
	assert_eq(before - unit.hp, previewed,
		"and the tile takes exactly what the card promised")


func test_the_preview_holds_across_repeated_ticks() -> void:
	# A preview that drifted from reality only after the first tick would be the same class
	# of bug, one turn later.
	var fx: Dictionary = _burning_grass()
	var fire: TileEffectResource = fx["fire"]
	var unit = fx["unit"]
	var system: TileEffectSystem = autofree(TileEffectSystem.new())

	for i in range(25):
		var previewed: int = fire.damage_preview_for(unit, fx["board"])
		var before: int = unit.hp
		system.on_turn_start(unit, fx["board"])
		assert_eq(before - unit.hp, previewed,
			"tick %d: preview and reality still agree" % [i + 1])


func test_a_tile_that_deals_no_damage_previews_zero() -> void:
	var fx: Dictionary = _burning_grass()
	assert_eq(_grass().damage_preview_for(fx["unit"], fx["board"]), 0,
		"tall grass hurts nobody, and says so")


# ===========================================================================
#  TRAVELING HAZARDS
# ===========================================================================

func test_a_traveling_hazard_band_is_never_dodged() -> void:
	# The crawling-vine sibling of the tile rule. resolve_hazard_damage is defender-side
	# arithmetic only -- no accuracy, no evasion, no crit -- so a vine entering the cell of a
	# highly evasive unit standing in tall grass hits it, every time.
	var landed: int = 0
	for run in range(60):
		var fx: Dictionary = _burning_grass()
		var unit = fx["unit"]
		var hazard := TravelingHazard.new(
			Vector2i(0, -1), Vector2i(0, 1), 0, 1, 3, 20,
			CombatTypes.DamageCategory.TRUE, CombatTypes.TargetKind.ANY_UNIT, null)
		var before: int = unit.hp
		var result: Dictionary = hazard.advance(fx["board"])
		assert_eq((result["damaged"] as Array).size(), 1,
			"run %d: the band found the occupant" % [run + 1])
		assert_eq(before - unit.hp, 20, "run %d: and took the full 20 off" % [run + 1])
		landed += 1
	assert_eq(landed, 60, "sixty independent vines, sixty landed hits -- a hazard does not roll")


func test_a_hazard_advance_is_deterministic() -> void:
	# Same setup twice, same answer: nothing on the hazard path consults a generator, so
	# advancing a vine cannot shift the lockstep RNG stream either.
	assert_eq(_hazard_damage_log(), _hazard_damage_log(),
		"two identical advances report identical damage")


func _hazard_damage_log() -> Array:
	var fx: Dictionary = _burning_grass()
	var hazard := TravelingHazard.new(
		Vector2i(0, -1), Vector2i(0, 1), 0, 1, 3, 20,
		CombatTypes.DamageCategory.TRUE, CombatTypes.TargetKind.ANY_UNIT, null)
	var out: Array = []
	for entry in (hazard.advance(fx["board"])["damaged"] as Array):
		out.append(int(entry["amount"]))
	return out
