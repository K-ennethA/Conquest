extends GutTest

## NPC LOOKS ([NpcLooks]; owner 2026-10-08): a person on the overworld with no visual_character
## wears a placeholder human model -- a clone of Wren's by default, of Lyra's for a woman
## (NpcEntity.body "female") -- chosen by the story ruleset's "NPC looks" knobs; the procedural
## figure stays the fallback. Pure resolution + dressing a bare actor (no scene).


func _npc(id: String, body: String = "", visual: StringName = &"") -> NpcEntity:
	var n := NpcEntity.new()
	n.id = StringName(id)
	n.body = body
	n.visual_character = visual
	return n


func _actor() -> OverworldActor:
	var a := OverworldActor.new()
	autofree(a)
	return a


func test_shipped_defaults_are_the_wren_and_lyra_clones() -> void:
	var rs := StoryRuleset.new()
	assert_true(rs.npc_models_enabled, "people wear models by default")
	assert_eq(rs.npc_default_model, &"wren", "the default look is a clone of Wren")
	assert_eq(rs.npc_female_model, &"lyra", "the female default is a clone of Lyra")
	var shipped := StoryRuleset.load_default()
	assert_eq(shipped.npc_default_model, &"wren", "the shipped ruleset keeps the Wren default")
	assert_eq(shipped.npc_female_model, &"lyra", "and the Lyra female default")


func test_a_person_resolves_to_the_default_or_female_model() -> void:
	var rs := StoryRuleset.new()
	assert_eq(NpcLooks.model_id(_npc("tobin"), rs), &"wren", "no visual_character -> the default model")
	assert_eq(NpcLooks.model_id(_npc("briony", "female"), rs), &"lyra", "a woman -> the female model")
	var t := TrainerEntity.new()
	t.id = &"bram"
	assert_eq(NpcLooks.model_id(t, rs), &"wren", "a trainer is a person too")
	var shop := ShopEntity.new()
	shop.body = "female"
	assert_eq(NpcLooks.model_id(shop, rs), &"lyra", "and a merchant")


func test_roster_models_props_and_the_knob_keep_their_own_look() -> void:
	var rs := StoryRuleset.new()
	assert_eq(NpcLooks.model_id(_npc("general", "", &"varden"), rs), &"",
		"an NPC with a visual_character keeps its roster model")
	assert_eq(NpcLooks.model_id(_npc("pup", "", &"petalfang"), rs), &"", "and so does a creature")
	assert_eq(NpcLooks.model_id(SignEntity.new(), rs), &"", "props are not people")
	assert_eq(NpcLooks.model_id(_npc("tobin"), null), &"", "no ruleset -> the figure")
	rs.npc_models_enabled = false
	assert_eq(NpcLooks.model_id(_npc("tobin"), rs), &"", "the knob off -> the procedural figure")
	assert_eq(NpcLooks.model_id(_npc("briony", "female"), rs), &"", "for women too")


func test_a_blank_female_model_falls_back_to_the_default() -> void:
	var rs := StoryRuleset.new()
	rs.npc_female_model = &""
	assert_eq(NpcLooks.model_id(_npc("briony", "female"), rs), &"wren", "no female model -> the default")


func test_child_scale_and_raider_tint() -> void:
	var rs := StoryRuleset.new()
	assert_almost_eq(NpcLooks.scale_for("child", rs), rs.npc_child_scale, 0.0001, "a child is scaled down")
	assert_lt(rs.npc_child_scale, 1.0, "smaller than an adult")
	assert_eq(NpcLooks.scale_for("elder", rs), 1.0, "an elder is full size")
	assert_ne(NpcLooks.tint_for("raider", Color(0.6, 0.1, 0.1), rs), Color.WHITE, "a raider keeps a tint")
	assert_eq(NpcLooks.tint_for("villager", Color(0.6, 0.1, 0.1), rs), Color.WHITE, "a villager is untinted")
	rs.npc_tint_strength = 0.0
	assert_eq(NpcLooks.tint_for("raider", Color(0.6, 0.1, 0.1), rs), Color.WHITE, "strength 0 -> no tint")


func test_dress_instances_the_roster_scene() -> void:
	var rs := StoryRuleset.new()
	var a := _actor()
	var worn: CharacterResource = NpcLooks.dress(a, _npc("tobin"), "villager", rs)
	assert_not_null(worn, "dressed")
	assert_eq(worn.character_id, &"wren", "in the default model")
	assert_not_null(a.model(), "the actor has a body")
	assert_eq(a.model().scene_file_path, worn.model_scene.resource_path, "an instance of the roster's scene")
	assert_eq(worn.model_scene, CharacterLibrary.get_character(&"wren").model_scene,
		"the one shared PackedScene (nothing reloaded per NPC)")

	var kid := _actor()
	NpcLooks.dress(kid, _npc("pell"), "child", rs)
	assert_almost_eq(kid.model().scale.x, worn.model_scale * rs.npc_child_scale, 0.0001, "a child is scaled down")

	var her := _actor()
	var lyra: CharacterResource = NpcLooks.dress(her, _npc("briony", "female"), "villager", rs)
	assert_eq(lyra.character_id, &"lyra", "a woman wears the female model")

	var raider := _actor()
	var r := _npc("raider_a")
	r.tint = Color(0.6, 0.12, 0.1)
	NpcLooks.dress(raider, r, "raider", rs)
	var meshes: Array[Node] = raider.model().find_children("*", "GeometryInstance3D", true, false)
	assert_gt(meshes.size(), 0, "the model has meshes")
	assert_not_null((meshes[0] as GeometryInstance3D).material_overlay, "a raider is dyed by an overlay")


func test_an_unknown_model_id_falls_back_to_the_figure() -> void:
	var rs := StoryRuleset.new()
	rs.npc_default_model = &"no_such_roster_id_npc_looks"
	rs.npc_female_model = &"no_such_roster_id_npc_looks"
	assert_null(NpcLooks.dress(_actor(), _npc("tobin"), "villager", rs), "no model -> null (the caller builds the figure)")
	rs.npc_female_model = &""
	rs.npc_default_model = &"wren"
	var a := _actor()
	assert_eq(NpcLooks.dress(a, _npc("briony", "female"), "villager", rs).character_id, &"wren",
		"a missing female model falls back to the default")
