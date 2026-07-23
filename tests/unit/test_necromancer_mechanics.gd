extends GutTest

## Covers the Necromancer (Mortis) content + the new SummonEffect wiring. Resolution /
## data-integrity only (a live summon needs a GameWorldManager, exercised in-game); this
## guards the .tres wiring and that SummonEffect compiles and is reachable.

func test_mortis_resolves_with_full_kit():
	var necro: CharacterResource = CharacterLibrary.get_character(&"necromancer")
	assert_not_null(necro, "necromancer.tres resolves via CharacterLibrary")
	if necro == null:
		return
	assert_eq(necro.element, &"dark", "Mortis is a dark-element caster")
	assert_eq(necro.moveset.size(), 4, "Mortis has four moves")
	var ab: Array = necro.get("abilities")
	assert_eq(ab.size(), 1, "Mortis has one ability (Reanimate)")

func test_reanimate_summons_one_on_kill():
	var reanimate: AbilityResource = load("res://game/abilities/reanimate.tres")
	assert_not_null(reanimate, "reanimate.tres loads")
	if reanimate == null:
		return
	assert_eq(reanimate.trigger, AbilityTrigger.Trigger.ON_KILL, "fires on a kill")
	assert_true(reanimate.targets_triggering_unit, "anchors to the slain victim")
	assert_eq(reanimate.effects.size(), 1, "one effect")
	assert_true(reanimate.effects[0] is SummonEffect, "the effect raises the dead")
	assert_eq(int(reanimate.effects[0].count), 1, "raises exactly one undead per kill")
	assert_eq(reanimate.effects[0].character_id, &"undead", "raises an undead body")

func test_undying_legion_summons_two_from_self():
	var ult: MoveResource = load("res://game/combat/moves/undying_legion.tres")
	assert_not_null(ult, "undying_legion.tres loads")
	if ult == null:
		return
	assert_eq(ult.targeting.target_kind, CombatTypes.TargetKind.SELF, "the ult is self-cast")
	var summon: SummonEffect = null
	for e in ult.effects:
		if e is SummonEffect:
			summon = e
	assert_not_null(summon, "the ult carries a SummonEffect")
	if summon != null:
		assert_eq(int(summon.count), 2, "raises two undead")

func test_soul_drain_lifesteals():
	var drain: MoveResource = load("res://game/combat/moves/soul_drain.tres")
	assert_not_null(drain, "soul_drain.tres loads")
	if drain == null:
		return
	var dmg: DamageEffect = null
	for e in drain.effects:
		if e is DamageEffect:
			dmg = e
	assert_not_null(dmg, "soul_drain deals damage")
	if dmg != null:
		assert_almost_eq(dmg.lifesteal, 0.5, 0.001, "and heals for half of it")
		assert_eq(dmg.category, CombatTypes.DamageCategory.MAGICAL, "as magic damage")

func test_grave_grasp_immobilizes():
	var grasp: MoveResource = load("res://game/combat/moves/grave_grasp.tres")
	assert_not_null(grasp, "grave_grasp.tres loads")
	if grasp == null:
		return
	var applies_ensnare := false
	for e in grasp.effects:
		if e is ApplyStatusEffect and e.condition != null and e.condition.id == &"ensnared":
			applies_ensnare = true
	assert_true(applies_ensnare, "Grave Grasp roots the target (ensnared)")

func test_undead_body_is_a_melee_only_thrall():
	var undead: CharacterResource = CharacterLibrary.get_character(&"undead")
	assert_not_null(undead, "undead.tres resolves")
	if undead == null:
		return
	assert_eq(undead.moveset.size(), 1, "the undead knows exactly one move")
	if undead.moveset.size() == 1:
		assert_eq(undead.moveset[0].targeting.max_range, 1, "and it is a melee strike")
