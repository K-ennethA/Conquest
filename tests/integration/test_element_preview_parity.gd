extends GutTest

## PREVIEW == REALITY, on live units.
##
## The forecast panel and the resolved blow now run the SAME function
## ([DamageMath.preview] / [DamageMath.apply_scales]). This suite is what keeps that true:
## it forecasts a cast, then actually resolves it on real [Unit]s with real
## [AbilityResource]s, and asserts the two numbers are identical. If anyone ever
## re-implements a damage rule in a preview path, one of these goes red.
##
## THE PROVING CASE IS VINEWEAVE'S GRASS CUTTER. It is a passive that boosts damage only
## against nature-element targets -- a CONDITION evaluated against the unit being hit, not
## a flat aura. A forecast that evaluated it against the wrong thing (or not at all) would
## promise the player one number and deliver another, and it would do so only against
## SOME targets, which is exactly the kind of bug that survives a spot check. So the
## parity assert runs twice: once against a target the condition MATCHES and once against
## a target it does not.
##
## Determinism: every move here uses accuracy 5.0 (hit% clamps to 100) and crit_chance 0.0
## against units with no evasion or crit, so MoveContext.resolve_hit cannot miss and cannot
## crit. A seeded RNG is passed regardless -- an unseeded generator in a test reseeds the
## process-wide one for every other suite.

const VINEWEAVE_PATH: String = "res://game/characters/roster/vineweave.tres"
const GRASS_CUTTER_PATH: String = "res://game/abilities/grass_cutter.tres"
## An EARTH-element roster character: the target Grass Cutter's condition must NOT match.
const EARTH_PATH: String = "res://game/characters/roster/gem_knight.tres"

## Flat power, chosen so no step of the chain lands on a .5 boundary: 24 -> 36 (+50%)
## -> 27 (x0.75). Small enough that nothing here can kill a unit mid-test.
const POWER: int = 24

var _rng: RandomNumberGenerator


func before_each() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 20260803


func after_each() -> void:
	ElementChart.reset_chart()


# --- Fixtures ----------------------------------------------------------------


## A roster character, DUPLICATED and stripped of its model so the headless test never
## depends on an imported .glb. Duplicating first is the project rule: the roster .tres is
## loaded once and shared, so mutating it in place would follow into every other suite.
func _character(path: String) -> CharacterResource:
	var authored := load(path) as CharacterResource
	if authored == null:
		return null
	var copy := authored.duplicate() as CharacterResource
	copy.model_scene = null
	return copy


func _unit(character: CharacterResource) -> Unit:
	var unit := Unit.new()
	unit.character_resource = character  # before add_child, so _ready() builds from it
	add_child_autofree(unit)             # AbilitySystem / StatusController attach here
	return unit


## Range-1 strike of [param element] for [constant POWER] TRUE damage. TRUE bypasses
## defense so the number under test is the SCALING chain, not each roster's defense stat.
func _strike(element: StringName) -> MoveResource:
	var move := MoveResource.new()
	move.move_id = &"test_parity_strike"
	move.display_name = "Test Parity Strike"
	move.category = CombatTypes.DamageCategory.TRUE
	move.element = element
	move.accuracy = 5.0
	move.crit_chance = 0.0

	var pattern := TargetingPattern.new()
	pattern.target_kind = CombatTypes.TargetKind.ENEMY
	pattern.min_range = 1
	pattern.max_range = 1
	pattern.area_shape = CombatTypes.AreaShape.SINGLE
	move.targeting = pattern

	var damage := DamageEffect.new()
	damage.power = POWER
	damage.scaling_stat = ""
	damage.category = CombatTypes.DamageCategory.TRUE
	move.effects = [damage]
	return move


## Forecast [param move], then actually resolve it, and assert the two agree.
## Returns the forecast so a caller can assert on its breakdown too.
func _assert_preview_matches_reality(caster: Unit, target: Unit, board, move: MoveResource, why: String) -> Dictionary:
	var forecast: Dictionary = MoveExecutor.preview_vs(move, caster, target, board)
	var before: int = target.get_hp()
	var result: Dictionary = MoveExecutor.execute(
		move, caster, board, board.cell_of(target), _rng)
	assert_true(result.get("success", false),
		"the cast resolves (%s); a rejected cast would make the parity assert vacuous" % why)
	for event in result.get("events", []):
		if event.get("effect", "") == "damage":
			assert_false(bool(event.get("crit", false)),
				"a zero crit chance never crits, so the two numbers are comparable")
	var actual: int = before - target.get_hp()
	assert_eq(int(forecast["damage"]), actual,
		"FORECAST == REALITY: %s" % why)
	assert_eq(int(forecast["total"]), actual,
		"and the pinned 'total' key carries the same number: %s" % why)
	return forecast


# --- What Vineweave's ability actually is ------------------------------------


func test_grass_cutter_is_authored_as_a_conditional_anti_element_bonus() -> void:
	var ability := load(GRASS_CUTTER_PATH) as AbilityResource
	assert_not_null(ability, "Vineweave's Grass Cutter ability resource loads")
	assert_eq(ability.trigger, AbilityTrigger.Trigger.PASSIVE,
		"Grass Cutter is a standing passive, not a triggered effect")
	assert_true(ability.rule_modifiers.has("damage_vs_element_nature"),
		"it is keyed on the TARGET's element -- 'damage_vs_element_<elem>' -- which is "
		+ "what makes it conditional on who is being hit rather than a flat aura")
	assert_almost_eq(float(ability.rule_modifiers["damage_vs_element_nature"]), 0.5, 0.001,
		"and it is authored at +50%, matching its own description")

	var vineweave := load(VINEWEAVE_PATH) as CharacterResource
	assert_not_null(vineweave, "the Vineweave roster entry loads")
	assert_eq(vineweave.element, &"nature", "Vineweave is itself a nature unit")
	var ids: Array = []
	for a in vineweave.abilities:
		if a != null:
			ids.append(a.id)
	assert_true(&"grass_cutter" in ids, "and it is the character that carries Grass Cutter")


func test_the_condition_is_evaluated_against_the_target_not_the_caster() -> void:
	var vineweave := _character(VINEWEAVE_PATH)
	var earth := _character(EARTH_PATH)
	if vineweave == null or earth == null:
		pending("roster characters unavailable")
		return
	var caster := _unit(vineweave)
	var nature_target := _unit(_character(VINEWEAVE_PATH))
	var earth_target := _unit(earth)

	assert_almost_eq(
		DamageEffect.element_bonus_scale_for(caster, nature_target, null), 1.5, 0.001,
		"Grass Cutter fires against a NATURE target")
	assert_almost_eq(
		DamageEffect.element_bonus_scale_for(caster, earth_target, null), 1.0, 0.001,
		"and is simply absent against an EARTH target -- the condition reads the "
		+ "element of the unit being hit, so it is not an aura")
	assert_almost_eq(
		DamageEffect.element_bonus_scale_for(earth_target, nature_target, null), 1.0, 0.001,
		"a caster without the passive never gets it")


# --- Preview == reality, with the conditional bonus in play ------------------


func test_preview_matches_reality_against_a_matching_target() -> void:
	var caster_res := _character(VINEWEAVE_PATH)
	var target_res := _character(VINEWEAVE_PATH)
	if caster_res == null or target_res == null:
		pending("roster characters unavailable")
		return
	var caster := _unit(caster_res)
	var target := _unit(target_res)
	var board := _Board.new(caster, Vector2i(0, 0), target, Vector2i(0, 1))

	# Unelemented move, so the ONLY thing scaling this hit is Grass Cutter.
	var forecast := _assert_preview_matches_reality(
		caster, target, board, _strike(&""), "Grass Cutter vs a nature target")

	assert_eq(int(forecast["base"]), POWER,
		"'base' is the damage before any conditional scaling")
	assert_eq(int(forecast["total"]), 36,
		"24 x 1.5 = 36 -- the +50% actually landed, so parity is not two zeroes agreeing")
	assert_eq(int(forecast["ability_bonus_percent"]), 50,
		"the forecast reports the conditional bonus it applied, as a whole percent")
	assert_eq(forecast["element_label"], ElementChart.LABEL_NEUTRAL,
		"an unelemented move contributes no matchup of its own")
	var notes: Array = forecast["ability_notes"]
	assert_eq(notes.size(), 1, "one conditional bonus applied, so one note explains it")
	assert_true(String(notes[0]).contains("Grass Cutter"),
		"and the note NAMES the ability, so the panel need not guess: %s" % notes)


func test_preview_matches_reality_against_a_non_matching_target() -> void:
	var caster_res := _character(VINEWEAVE_PATH)
	var target_res := _character(EARTH_PATH)
	if caster_res == null or target_res == null:
		pending("roster characters unavailable")
		return
	var caster := _unit(caster_res)
	var target := _unit(target_res)
	var board := _Board.new(caster, Vector2i(0, 0), target, Vector2i(0, 1))

	var forecast := _assert_preview_matches_reality(
		caster, target, board, _strike(&""), "Grass Cutter vs a non-nature target")

	assert_eq(int(forecast["total"]), POWER,
		"the bonus does NOT apply to an earth target, in the preview or on the board")
	assert_eq(int(forecast["ability_bonus_percent"]), 0,
		"and the forecast says so rather than quietly showing the boosted number")
	assert_eq(forecast["ability_notes"], [],
		"no bonus, no explanation")


# --- Preview == reality, with the element chart in play ----------------------


func test_preview_matches_reality_with_a_resisted_matchup() -> void:
	var caster_res := _character(VINEWEAVE_PATH)
	var target_res := _character(VINEWEAVE_PATH)
	if caster_res == null or target_res == null:
		pending("roster characters unavailable")
		return
	var caster := _unit(caster_res)
	var target := _unit(target_res)
	var board := _Board.new(caster, Vector2i(0, 0), target, Vector2i(0, 1))

	# nature move into a nature unit: Grass Cutter's +50% AND the chart's self-resist.
	var forecast := _assert_preview_matches_reality(
		caster, target, board, _strike(&"nature"),
		"the ability bonus and the element matchup, stacked")

	assert_almost_eq(float(forecast["element_mult"]), 0.75, 0.001,
		"nature into nature is the self-resist")
	assert_eq(forecast["element_label"], ElementChart.LABEL_RESISTED,
		"and it is labelled resisted")
	assert_eq(int(forecast["total"]), 27,
		"24 x 1.5 (ability) = 36, then x 0.75 (matchup) = 27 -- attacker bonus first, "
		+ "matchup last, rounded at each step exactly as the resolved hit does")


func test_preview_matches_reality_with_a_strong_matchup() -> void:
	var caster_res := _character(VINEWEAVE_PATH)
	var target_res := _character(EARTH_PATH)
	if caster_res == null or target_res == null:
		pending("roster characters unavailable")
		return
	var caster := _unit(caster_res)
	var target := _unit(target_res)
	var board := _Board.new(caster, Vector2i(0, 0), target, Vector2i(0, 1))

	# water is earth's opposite: strong, and Grass Cutter does not apply to earth.
	var forecast := _assert_preview_matches_reality(
		caster, target, board, _strike(&"water"), "a strong matchup with no ability bonus")

	assert_almost_eq(float(forecast["element_mult"]), 1.25, 0.001,
		"water into its opposite earth is strong")
	assert_eq(forecast["element_label"], ElementChart.LABEL_STRONG, "and is labelled strong")
	assert_eq(int(forecast["total"]), 30, "24 x 1.25 = 30")


# --- Local board -------------------------------------------------------------


## A two-unit board, deliberately local. The shared doubles decide hostility from a
## `team` int, which a live [Unit] does not carry -- here the two units are simply always
## enemies, which is all this suite needs and all it should assert on.
class _Board:
	var _cells: Dictionary = {}

	func _init(a, a_cell: Vector2i, b, b_cell: Vector2i) -> void:
		_cells[a] = a_cell
		_cells[b] = b_cell

	func cell_of(unit) -> Vector2i:
		return _cells.get(unit, Vector2i(-999, -999))

	func units_at(cell: Vector2i) -> Array:
		var out: Array = []
		for unit in _cells:
			if _cells[unit] == cell:
				out.append(unit)
		return out

	## Answered (with nothing) on purpose: a board that does NOT expose this sends
	## [ElementChart] to the live CombatServices autoload for its terrain, and this suite
	## would then depend on whatever map the previous suite left loaded.
	func tile_effects_at(_cell: Vector2i) -> Array:
		return []

	func all_units() -> Array:
		return _cells.keys()

	func are_enemies(a, b) -> bool:
		return a != b

	func are_allies(a, b) -> bool:
		return a == b
