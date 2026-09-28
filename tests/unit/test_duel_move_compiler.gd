extends GutTest

## DuelMoveCompiler against the REAL roster .tres (docs/design/DUEL_BATTLE.md §3.4): every
## policy row, the duel_variant override, ultimate-slot integrity, eligibility, and -- rule 7
## -- that compiling never touches the shared roster resources.

const MOVES := "res://game/combat/moves/"

var _rules: DuelRuleset = null


func before_each() -> void:
	_rules = DuelRuleset.load_default()


func _move(id: String) -> MoveResource:
	return load(MOVES + id + ".tres") as MoveResource


func _compiled(id: String) -> MoveResource:
	return DuelMoveCompiler.compile_move(_move(id), _rules)["move"]


func _has_effect(move: MoveResource, script_name: String) -> bool:
	for e in move.effects:
		if script_name in DuelMoveCompiler.effect_class_chain(e):
			return true
	return false


func _character(id: StringName) -> DuelCharacter:
	var res := DuelMoveCompiler.compile(CharacterLibrary.get_character(id), _rules)
	assert_true(bool(res["success"]), "%s compiles" % id)
	return res["character"]


func test_default_ruleset_ships_the_policy_table() -> void:
	assert_eq(_rules.effect_policies, DuelRuleset.default_effect_policy_table(),
		"default_duel.tres authors the §3.4 table")
	assert_not_null(_rules.struggle_move, "the struggle move ships on the ruleset")
	assert_eq(_rules.policy_for_ability(&"reanimate"), DuelRuleset.POLICY_DISABLE)


func test_class_chain_walks_base_scripts() -> void:
	var bulwark := _move("prism_bulwark")
	var chain := DuelMoveCompiler.effect_class_chain(bulwark.alt_effects[0])
	assert_eq(chain[0], "StackConsumeDamageEffect")
	assert_true("DamageEffect" in chain, "subclasses fall back to their base's policy")


func test_vineweave_compiles_unchanged() -> void:
	var vw := _character(&"vineweave")
	var ids: Array = []
	for m in vw.moveset:
		ids.append(String(m.move_id))
	assert_eq(ids, ["bramble_cleave", "thornward", "splinter_volley", "strangling_roots"],
		"all four of Vineweave's moves are duel-clean")
	assert_true(vw.excluded_moves.is_empty())
	assert_true(vw.duel_eligible)
	assert_true(MoveResource.is_ultimate_move(vw.get_move(3), 3), "Strangling Roots stays the ultimate")
	assert_eq(vw.get_move(DuelCharacter.STRUGGLE_SLOT).move_id, &"desperate_strike",
		"the struggle answers on its reserved slot")
	assert_eq(vw.move_count(), 4, "and never counts as a fifth move")


func test_leaps_drop_the_leap_and_clear_landing_constraints() -> void:
	for id in ["sporeleap", "infesting_lunge"]:
		var m := _compiled(id)
		assert_not_null(m, "%s stays in the duel" % id)
		assert_false(_has_effect(m, "LeapEffect"), "%s: no LeapEffect" % id)
		assert_true(_has_effect(m, "DamageEffect"), "%s: becomes a plain strike" % id)
		assert_false(m.targeting.requires_empty_cell, "%s: landing constraint cleared" % id)
		assert_false(m.targeting.requires_adjacent_enemy, "%s: adjacency constraint cleared" % id)
	assert_true(_has_effect(_compiled("infesting_lunge"), "ApplyStatusEffect"),
		"Infesting Lunge still applies its brace")


func test_traps_are_excluded_unless_a_variant_exists() -> void:
	var vine := DuelMoveCompiler.compile_move(_move("vine_trap"), _rules)
	assert_null(vine["move"], "Vine Trap (an ON_ENTER trap) is excluded")
	var scree := _compiled("scree_trap")
	assert_not_null(scree)
	assert_eq(scree.move_id, &"scree_shower", "Scree Trap's duel_variant wins, as-is")
	assert_true(_has_effect(scree, "DamageEffect") and _has_effect(scree, "StatModifierEffect"))


func test_ally_moves_become_self() -> void:
	var light := _compiled("soothing_light")
	assert_eq(light.targeting.target_kind, CombatTypes.TargetKind.SELF, "no allies in 1v1: heal yourself")
	assert_true(light.targeting.affects_caster_tile)


func test_mobility_hazards_and_summons_are_excluded() -> void:
	for id in ["voidstep", "forest_barrage", "undying_legion"]:
		assert_null(DuelMoveCompiler.compile_move(_move(id), _rules)["move"], "%s is excluded" % id)


func test_knockback_and_tile_transform_are_dropped_not_the_move() -> void:
	var quake := _compiled("crushing_quake")
	assert_not_null(quake, "Crushing Quake stays")
	assert_false(_has_effect(quake, "KnockbackEffect"))
	assert_false(_has_effect(quake, "TileTransformEffect"))
	assert_true(_has_effect(quake, "DamageEffect"))
	var notes: Array = DuelMoveCompiler.compile_move(_move("crushing_quake"), _rules)["notes"]
	assert_true(notes.size() >= 2, "the dropped effects are noted for the HUD: %s" % str(notes))


func test_dash_through_converts_to_damage_with_the_same_numbers() -> void:
	var dash := _move("shadow_dash")
	var original = null
	for e in dash.effects:
		if e is DashThroughEffect:
			original = e
	var m := _compiled("shadow_dash")
	assert_not_null(m)
	assert_false(_has_effect(m, "DashThroughEffect"))
	var dmg: DamageEffect = null
	for e in m.effects:
		if e is DamageEffect:
			dmg = e
	assert_not_null(dmg)
	assert_eq(dmg.power, original.power)
	assert_eq(dmg.scaling_stat, original.scaling_stat)
	assert_eq(dmg.category, original.category)


func test_ultimate_flag_survives_repacking() -> void:
	var pf := _character(&"petalfang")
	assert_eq(pf.moveset.size(), 3, "Vine Trap left, three moves remain")
	assert_true(&"vine_trap" in pf.excluded_moves)
	var last := pf.get_move(2)
	assert_eq(last.move_id, &"ingrained", "Ingrained moved from slot 3 to slot 2")
	assert_true(MoveResource.is_ultimate_move(last, 2), "and still gets the cut-in")
	assert_false(MoveResource.is_ultimate_move(pf.get_move(0), 0))


func test_geode_fields_its_variant_and_abilities() -> void:
	var geode := _character(&"gem_knight")
	var ids: Array = []
	for m in geode.moveset:
		ids.append(String(m.move_id))
	assert_eq(ids, ["prism_bulwark", "stone_sling", "scree_shower", "refraction_lance"])
	assert_eq(geode.abilities.size(), CharacterLibrary.get_character(&"gem_knight").abilities.size(),
		"Firstward / Crystalline Ward / Reprisal / Sand Veil all work unchanged")
	assert_ne(geode.get_move(0).alt_requires_status, &"", "Prism Bulwark keeps its alt mode")


func test_reanimate_is_disabled_and_summons_leave() -> void:
	var necro := _character(&"necromancer")
	for a in necro.abilities:
		assert_ne(a.id, &"reanimate", "a KO ends the duel: no Reanimate")
	assert_true(&"undying_legion" in necro.excluded_moves)


func test_eligibility() -> void:
	assert_false(_character(&"bastion").duel_eligible, "a pure self-guard kit cannot win a duel")
	assert_false(DuelMoveCompiler.is_duel_eligible(CharacterLibrary.get_character(&"bastion"), _rules))
	assert_true(_character(&"undead").duel_eligible)
	assert_true(_character(&"monster").duel_eligible)


func test_shared_roster_resources_are_untouched() -> void:
	var leap := _move("sporeleap")
	var ingrained := _move("ingrained")
	var roster_vw := CharacterLibrary.get_character(&"vineweave")
	var before_moves := roster_vw.moveset.duplicate()
	var before_effects := leap.effects.size()
	for id in [&"vineweave", &"gem_knight", &"petalfang", &"blightcap", &"necromancer", &"monster"]:
		_character(id)
	assert_true(leap.targeting.requires_empty_cell, "Spore Leap's shared pattern still requires a landing cell")
	assert_eq(leap.effects.size(), before_effects, "and still carries its LeapEffect")
	assert_false(ingrained.is_ultimate, "the shared Ingrained was never flagged")
	assert_eq(roster_vw.moveset, before_moves, "the roster entry keeps its own moves")
	assert_false(roster_vw is DuelCharacter)
	var vw := _character(&"vineweave")
	assert_ne(vw.get_move(0), roster_vw.moveset[0], "the duel copy holds its own move instances")
