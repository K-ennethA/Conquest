extends GutTest

## HUMANS IN DUELS (docs/design/HUMANS.md; DECISIONS.md #7, #54): a human leads or sits on the
## bench beside creatures, and its WEAPON ATTACK is an ordinary duel move (slot 0). A story
## member's weapon override rides the combatant as an optional "weapon_id" key that open-mode
## requests never carry (no wire / replay change).


func before_each() -> void:
	CombatServices.clear()


func after_each() -> void:
	CombatServices.clear()
	CombatServices.match_rng = null


func _battle(a: Array, b: Array, seed_value: int = 41) -> DuelBattle:
	var req := DuelRequest.teams(a, b, DuelFormat.preset(DuelFormat.TRIO))
	req.kind = DuelRequest.KIND_VERSUS
	req.seed = seed_value
	req.player_is_ai = false
	req.foe_is_ai = false
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	var ok := battle.setup(req)
	assert_true(bool(ok["success"]), str(ok.get("reason", "")))
	battle.start()
	return battle


func test_a_human_leads_a_duel_with_its_weapon() -> void:
	var b := _battle(["varden", "tree_grunt"], ["petalfang"])
	var varden = b.unit_of(0)
	assert_eq(String(varden.character_resource.character_id), "varden")
	assert_eq(varden.get_move(0).move_id, &"weapon_iron_sword", "slot 0 is the weapon attack")
	assert_true(WeaponResource.is_weapon_move(varden.get_move(0)))
	# Play until the human has struck at least once.
	var foe = b.unit_of(1)
	var start_hp: int = int(foe.get_hp())
	for i in range(6):
		var actor = b.current_actor()
		if actor == null:
			break
		var slots: Array[int] = b.legal_slots(actor)
		if slots.is_empty():
			break
		assert_true(bool(b.submit_slot(slots[0])["ok"]))
		if actor == varden:
			break
	assert_lt(int(foe.get_hp()), start_hp, "the sword strike landed or the duel moved on")


func test_mixed_sides_field_humans_and_creatures() -> void:
	var b := _battle(["tree_grunt", "wren"], ["lyra", "petalfang"])
	assert_eq(String(b.unit_of(0).character_resource.character_id), "tree_grunt")
	assert_eq(String(b.unit_of(1).character_resource.character_id), "lyra")
	assert_eq(b.unit_of(1).get_move(0).move_id, &"weapon_study_tome")


func test_combatant_weapon_id_is_optional_and_strict() -> void:
	var c := DuelCombatant.make(&"varden")
	assert_false(c.to_dict().has("weapon_id"), "open-mode combatants never carry the key")
	c.weapon_id = "iron_lance"
	var d := c.to_dict()
	assert_eq(String(d["weapon_id"]), "iron_lance")
	var back: Dictionary = DuelCombatant.from_dict(d)
	assert_true(bool(back["success"]), str(back["reason"]))
	assert_eq((back["combatant"] as DuelCombatant).weapon_id, "iron_lance")
	d["weapon_id"] = "study_tome"
	assert_eq(String(DuelCombatant.from_dict(d)["reason"]), "bad_weapon:study_tome", "not a type Varden wields")
	d["weapon_id"] = "no_such_weapon"
	assert_false(bool(DuelCombatant.from_dict(d)["success"]))


func test_story_weapon_override_reaches_the_duel_unit() -> void:
	var br := BattleRequest.new()
	br.kind = BattleRequest.KIND_DUEL
	br.source = BattleRequest.SOURCE_SCRIPT
	br.party = [{"member_id": "varden", "character_id": "varden", "current_hp": -1, "level": 0,
		"weapon_id": "iron_lance"}]
	br.opponent = {"name": "Foe", "team": [{"character_id": "petalfang", "strength": 1.0}]}
	br.seed = 5
	var res: Dictionary = DuelRequest.from_battle_request(br.to_dict())
	assert_true(bool(res["success"]), str(res.get("reason", "")))
	var req: DuelRequest = res["request"]
	assert_eq(req.player_party[0].weapon_id, "iron_lance")
	req.player_is_ai = false
	req.foe_is_ai = false
	var battle := DuelBattle.new()
	add_child_autofree(battle)
	assert_true(bool(battle.setup(req)["success"]))
	assert_eq(battle.unit_of(0).get_move(0).move_id, &"weapon_iron_lance")
	assert_eq(CharacterLibrary.get_character(&"varden").weapon.weapon_id, &"iron_sword", "roster untouched")
