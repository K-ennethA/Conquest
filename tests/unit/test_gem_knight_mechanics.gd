extends GutTest

## Covers the engine hooks added for the Gem Knight (Geode) + Vineweave's Grass Cutter:
##   - DamageEffect's attacker-side element bonus ("damage_vs_element_<elem>")
##   - the Gem Knight roster entry + its moves/abilities resolve and wire correctly
## Mock style mirrors test_eldroot.gd / test_tree_grunt.gd (no scene tree needed).

# --- Mocks for the element-bonus hook ---------------------------------------

class MockAbilitySystem:
	var mods: Dictionary
	func _init(m: Dictionary) -> void:
		mods = m
	func passive_modifiers(_unit = null, _board = null) -> Dictionary:
		return mods

class MockCaster:
	var system
	func _init(m: Dictionary) -> void:
		system = MockAbilitySystem.new(m)
	func get_ability_system():
		return system

class MockTarget:
	var elem: StringName
	func _init(e: StringName) -> void:
		elem = e
	func get_element() -> StringName:
		return elem


func _grass_cutter_caster() -> MockCaster:
	return MockCaster.new({"damage_vs_element_nature": 0.5})


# --- Attacker element bonus --------------------------------------------------

func test_element_bonus_boosts_matching_element_target():
	var scale := DamageEffect.element_bonus_scale_for(_grass_cutter_caster(), MockTarget.new(&"nature"), null)
	assert_almost_eq(scale, 1.5, 0.001, "Grass Cutter deals +50% to a nature-element target")

func test_element_bonus_ignores_other_elements():
	var caster := _grass_cutter_caster()
	assert_almost_eq(DamageEffect.element_bonus_scale_for(caster, MockTarget.new(&"fire"), null), 1.0, 0.001,
		"no bonus against a non-matching element")
	assert_almost_eq(DamageEffect.element_bonus_scale_for(caster, MockTarget.new(&""), null), 1.0, 0.001,
		"no bonus against an unelemented target")

func test_element_bonus_absent_without_the_passive():
	var plain := MockCaster.new({})
	assert_almost_eq(DamageEffect.element_bonus_scale_for(plain, MockTarget.new(&"nature"), null), 1.0, 0.001,
		"a caster without the passive gets no element bonus")

func test_element_bonus_null_safe():
	assert_almost_eq(DamageEffect.element_bonus_scale_for(null, MockTarget.new(&"nature"), null), 1.0, 0.001,
		"null caster is a plain 1.0")


# --- Gem Knight content resolves --------------------------------------------

func test_geode_resolves_with_full_kit():
	var geode: CharacterResource = CharacterLibrary.get_character(&"gem_knight")
	assert_not_null(geode, "gem_knight.tres resolves via CharacterLibrary")
	if geode == null:
		return
	assert_eq(geode.element, &"earth", "Geode is an earth-element unit")
	assert_eq(geode.moveset.size(), 4, "Geode has four moves")
	var ab: Array = geode.get("abilities")
	assert_eq(ab.size(), 2, "Geode has two abilities (Crystalline Ward + Reprisal)")

func test_crystalline_ward_grants_a_shield_after_untouched_turns():
	var ward: AbilityResource = load("res://game/abilities/crystalline_ward.tres")
	assert_not_null(ward, "crystalline_ward.tres loads")
	if ward == null:
		return
	assert_eq(ward.trigger, AbilityTrigger.Trigger.ON_TURN_START, "fires at turn start")
	assert_true(ward.condition is UndamagedForTurnsCondition, "gated on the undamaged-turns condition")
	assert_eq(int(ward.condition.turns), 3, "after 3 untouched turns")
	assert_eq(ward.effects.size(), 1, "one effect")
	assert_true(ward.effects[0] is ShieldEffect, "the effect is a shield")
	assert_eq(int(ward.effects[0].amount), 15, "a 15 HP shield")

func test_vineweave_wears_grass_cutter():
	var vine: CharacterResource = CharacterLibrary.get_character(&"vineweave")
	assert_not_null(vine, "vineweave.tres resolves")
	if vine == null:
		return
	var found := false
	for a in vine.get("abilities"):
		if a != null and a.id == &"grass_cutter":
			found = true
	assert_true(found, "Vineweave carries the Grass Cutter passive")
