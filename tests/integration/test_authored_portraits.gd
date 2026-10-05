extends GutTest
## The owner's character art (docs/design/characters -> game/ui/portraits) is what story
## dialogue and the portrait panels show for those people (PortraitLibrary via PortraitCache).

func after_each() -> void:
	PortraitCache.reset()


func test_ids_resolve_through_the_npc_prefix_and_aliases() -> void:
	assert_eq(PortraitLibrary.resolve_id("npc_elias"), "elias")
	assert_eq(PortraitLibrary.resolve_id("npc_general"), "varden", "the General NPC is Varden")
	assert_eq(PortraitLibrary.resolve_id("hero"), "wren", "the hero's art is Wren's sheet")
	assert_eq(PortraitLibrary.resolve_id("npc_lyra"), "lyra")
	assert_eq(PortraitLibrary.resolve_id(""), "")
	assert_eq(PortraitLibrary.resolve_id(null), "")


func test_every_sheet_has_a_portrait() -> void:
	for id in ["wren", "elias", "varden", "varrick", "shadow_assassin", "kellan", "eloi", "nyra",
			"saevi", "kazren", "lyra", "cael", "vayne"]:
		assert_not_null(PortraitLibrary.authored(id), "%s has authored art" % id)


func test_people_without_art_fall_back() -> void:
	assert_null(PortraitLibrary.authored("npc_tobin"), "no sheet: monogram / capture as before")
	assert_null(PortraitLibrary.authored("npc_warrior"), "Talyn has no sheet yet")


func test_the_cache_hands_out_authored_art_synchronously() -> void:
	var got: Array = []
	PortraitCache.get_portrait("npc_elias", func(tex: Texture2D) -> void: got.append(tex))
	assert_eq(got.size(), 1, "answered at once, no capture rig needed")
	assert_not_null(got[0], "Professor Elias's portrait")
	assert_not_null(PortraitCache.get_cached("npc_general"), "get_cached sees authored art too")
