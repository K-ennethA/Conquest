extends GutTest

## HUMANS AS BATTLE UNITS, the data half (docs/design/HUMANS.md; DECISIONS.md #5, #54, #63):
## every roster entry's kind, the weapon data + library, a human's kit (weapon attack in slot 0
## plus whatever special moves it lists), the weapon triangle, and that creatures are untouched.

## Every roster entry and its kind. A new roster entry must be added here on purpose.
const HUMANS: Array[String] = ["cael", "elias", "lyra", "varden", "wren"]


func after_each() -> void:
	WeaponRules.set_current(null)


func test_every_roster_entry_has_the_expected_kind() -> void:
	for id in CharacterLibrary.all_ids():
		var c := CharacterLibrary.get_character(id)
		assert_not_null(c, "roster entry %s loads" % id)
		if c == null:
			continue
		var want_human: bool = HUMANS.has(String(id))
		assert_eq(c.is_human(), want_human, "%s kind" % id)
	# Mortis (necromancer) is a "gravecaller" but not clearly a person: kept CREATURE (noted in
	# docs/design/HUMANS.md) until the owner says otherwise.
	assert_false(CharacterLibrary.get_character(&"necromancer").is_human())


func test_every_human_validates_and_wields_its_weapon() -> void:
	for id in HUMANS:
		var c := CharacterLibrary.get_character(StringName(id))
		var v: Dictionary = c.validate()
		assert_true(bool(v["valid"]), "%s validates: %s" % [id, str(v["issues"])])
		assert_not_null(c.weapon, "%s has a weapon" % id)
		assert_true(c.can_wield(c.weapon), "%s can wield its own weapon" % id)


func test_weapon_rules_and_library_validate() -> void:
	assert_eq(WeaponRules.current().validate(), [] as Array[String])
	var ids := WeaponLibrary.all_ids()
	assert_true(ids.has(&"pitchfork") and ids.has(&"iron_sword") and ids.has(&"unarmed"))
	for wid in ids:
		var w := WeaponLibrary.get_weapon(wid)
		assert_not_null(w, "weapon %s loads" % wid)
		assert_eq(w.validate(), [] as Array[String], "weapon %s validates" % wid)
		assert_eq(w.weapon_id, wid, "weapon id matches its file")


func test_human_kit_is_weapon_attack_then_listed_moves() -> void:
	var wren := CharacterLibrary.get_character(&"wren")
	assert_eq(wren.move_count(), 1, "the hero fields only his weapon attack (no specials listed)")
	var strike := wren.get_move(0)
	assert_eq(strike.move_id, &"weapon_pitchfork")
	assert_true(WeaponResource.is_weapon_move(strike))
	assert_eq(WeaponResource.strike_type_of(strike), &"lance")
	# A human that LISTS special moves (an "enhanced" one -- flavour, not a flag) fields them after.
	var chief := wren.duplicate(false) as CharacterResource
	var specials: Array[MoveResource] = [load("res://game/combat/moves/cleave.tres"),
		load("res://game/combat/moves/thorn_spit.tres")]
	chief.moveset = specials
	assert_eq(chief.move_count(), 3)
	assert_eq(chief.get_move(0).move_id, &"weapon_pitchfork")
	assert_eq(chief.get_move(1).move_id, specials[0].move_id)


func test_weapon_attack_reads_the_weapon() -> void:
	var w := WeaponLibrary.get_weapon(&"short_bow")
	var m := w.attack_move()
	assert_eq(m.targeting.target_kind, CombatTypes.TargetKind.ENEMY)
	assert_eq(m.targeting.min_range, 2)
	assert_eq(m.targeting.max_range, 3)
	assert_almost_eq(m.accuracy, w.hit, 0.0001)
	assert_eq(m.max_uses, -1, "durability off by default")
	var e := m.effects[0] as WeaponStrikeEffect
	assert_eq(e.power, w.might)
	assert_eq(e.scaling_stat, "attack")
	var tome := WeaponLibrary.get_weapon(&"study_tome").attack_move()
	assert_eq(tome.category, CombatTypes.DamageCategory.MAGICAL)
	assert_eq((tome.effects[0] as DamageEffect).scaling_stat, "magic")
	assert_same(w.attack_move(), m, "the compiled strike is cached (shared, read-only)")


func test_with_weapon_is_a_private_copy() -> void:
	var varden := CharacterLibrary.get_character(&"varden")
	var lance := WeaponLibrary.get_weapon(&"iron_lance")
	assert_true(varden.can_swap_weapons())
	assert_true(varden.can_wield(lance))
	assert_false(varden.can_wield(WeaponLibrary.get_weapon(&"study_tome")))
	var copy := varden.with_weapon(lance)
	assert_ne(copy, varden)
	assert_eq(copy.get_move(0).move_id, &"weapon_iron_lance")
	assert_eq(varden.get_move(0).move_id, &"weapon_iron_sword", "the roster entry is untouched")


func test_creatures_are_unchanged() -> void:
	var c := CharacterLibrary.get_character(&"tree_grunt")
	assert_true(c.is_creature())
	assert_eq(c.get_moveset(), c.moveset, "a creature's kit is its authored list")
	assert_null(c.equipped_weapon())
	assert_eq(c.effective_attack_range(), c.attack_range)


func test_weapon_triangle_scale() -> void:
	var r := WeaponRules.current()
	assert_true(r.triangle_enabled, "triangle default ON")
	assert_almost_eq(r.triangle_scale(&"sword", &"axe"), 1.15, 0.0001)
	assert_almost_eq(r.triangle_scale(&"axe", &"sword"), 0.85, 0.0001)
	assert_almost_eq(r.triangle_scale(&"lance", &"sword"), 1.15, 0.0001)
	assert_almost_eq(r.triangle_scale(&"bow", &"sword"), 1.0, 0.0001)
	assert_almost_eq(r.triangle_scale(&"sword", &""), 1.0, 0.0001)
	var off := r.duplicate(true) as WeaponRules
	off.triangle_enabled = false
	assert_almost_eq(off.triangle_scale(&"sword", &"axe"), 1.0, 0.0001)


## The DamageMath step: a weapon strike vs a human wielder; 1.0 vs a creature or for a creature move.
func test_damage_math_triangle_step() -> void:
	var sword_move := WeaponLibrary.get_weapon(&"iron_sword").attack_move()
	var lance_holder := _Holder.new(CharacterLibrary.get_character(&"wren"))   # pitchfork = lance
	var axe_holder := _Holder.new(CharacterLibrary.get_character(&"wren").with_weapon(WeaponLibrary.get_weapon(&"iron_axe")))
	var creature := _Holder.new(CharacterLibrary.get_character(&"tree_grunt"))
	assert_almost_eq(DamageMath.weapon_triangle_scale_for(sword_move, lance_holder), 0.85, 0.0001)
	assert_almost_eq(DamageMath.weapon_triangle_scale_for(sword_move, axe_holder), 1.15, 0.0001)
	assert_almost_eq(DamageMath.weapon_triangle_scale_for(sword_move, creature), 1.0, 0.0001)
	var creature_move := load("res://game/combat/moves/tree_bash.tres") as MoveResource
	assert_almost_eq(DamageMath.weapon_triangle_scale_for(creature_move, axe_holder), 1.0, 0.0001)


func test_duel_compiles_a_human_kit_once() -> void:
	var res := DuelMoveCompiler.compile(CharacterLibrary.get_character(&"varden"))
	assert_true(bool(res["success"]))
	var dc: DuelCharacter = res["character"]
	assert_eq(dc.move_count(), 1, "weapon attack only -- not prepended twice")
	assert_eq(dc.get_move(0).move_id, &"weapon_iron_sword")
	assert_true(dc.duel_eligible, "a human with a weapon can duel")
	assert_eq(WeaponResource.strike_type_of(dc.get_move(0)), &"sword", "the compiled copy keeps its type")


class _Holder:
	extends RefCounted
	var character_resource: CharacterResource
	func _init(c: CharacterResource) -> void:
		character_resource = c
