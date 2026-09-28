extends GutTest

## OverworldAreaResource + the entity kinds: entry-point coercion, entity filtering by
## visible_if, auto flags, the scripts each kind composes, and _to_string on every kind.


func _area() -> OverworldAreaResource:
	var a := OverworldAreaResource.new()
	a.area_id = &"testville"
	a.display_name = "Testville"
	var m := MapResource.new()
	m.width = 8
	m.height = 6
	a.terrain = m
	a.entry_points = {
		"start": {"cell": [2, 3, 0], "facing": "north"},
		"json_floats": {"cell": [4.0, 1.0], "facing": "sideways"},
		"broken": {"facing": "north"},
		"not_a_dict": 42,
	}
	return a


func test_entry_points_coerce_json_shapes() -> void:
	var a := _area()
	assert_eq(a.entry("start"), {"cell": Vector3i(2, 3, 0), "facing": "north"}, "a plain entry reads back")
	var e: Dictionary = a.entry("json_floats")
	assert_eq(e["cell"], Vector3i(4, 1, 0), "JSON floats and a 2-element cell coerce to a Vector3i")
	assert_eq(e["facing"], "south", "an unknown facing falls back to south")
	assert_true(a.entry("broken").is_empty(), "an entry with no cell is empty, not an error")
	assert_true(a.entry("not_a_dict").is_empty(), "a malformed entry is empty")
	assert_true(a.entry("missing").is_empty(), "an unknown entry is empty")


func test_entities_filter_by_visible_if_and_type() -> void:
	var a := _area()
	var npc := NpcEntity.new()
	npc.id = &"always"
	var gated := NpcEntity.new()
	gated.id = &"gated"
	gated.visible_if = "not has(\"gone\")"
	var ents: Array[Resource] = [npc, gated, null, Resource.new()]
	a.entities = ents
	assert_eq(a.entity_list().size(), 2, "null and foreign entries are filtered out")
	var s := StoryState.new()
	assert_eq(a.present_entities(s).size(), 2, "both present before the flag")
	s.set_flag("gone", 1)
	assert_eq(a.present_entities(s).size(), 1, "visible_if hides the gated one")
	assert_eq(a.entity("gated"), gated, "lookup by id")


func test_auto_flags() -> void:
	var t := TrainerEntity.new()
	t.id = &"bram"
	assert_eq(t.auto_flag("mossway"), "trainer.mossway.bram.defeated", "trainer defeated flag")
	assert_eq(t.encounter_id("mossway") + ".defeated", t.auto_flag("mossway"),
		"the encounter id + .defeated IS the defeated flag (the result applier relies on it)")
	var c := ChestEntity.new()
	c.id = &"mill_chest"
	assert_eq(c.auto_flag("oakvale"), "oakvale.mill_chest.opened", "chest opened flag")
	var w := WayshrineEntity.new()
	w.id = &"wayshrine"
	assert_eq(w.auto_flag("oakvale"), "wayshrine.oakvale.wayshrine.lit", "shrine lit flag")
	var z := TriggerZone.new()
	z.id = &"z"
	assert_eq(z.auto_flag("a"), "a.z.fired", "a once-zone has a fired flag")
	z.once = false
	assert_eq(z.auto_flag("a"), "", "a repeating zone has none")


func test_every_kind_describes_itself() -> void:
	for e in [OverworldEntity.new(), NpcEntity.new(), TrainerEntity.new(), SignEntity.new(),
			ChestEntity.new(), WarpEntity.new(), WayshrineEntity.new(), TriggerZone.new(), PropEntity.new()]:
		(e as OverworldEntity).id = &"x"
		assert_false(str(e).is_empty(), "%s has a _to_string" % (e as OverworldEntity).kind())
	for c in [SayCommand.new(), ChoiceCommand.new(), SetFlagCommand.new(), IncFlagCommand.new(),
			IfCommand.new(), GiveItemCommand.new(), GiveGoldCommand.new(), TakeGoldCommand.new(),
			HealPartyCommand.new(), StartBattleCommand.new(), StartDuelCommand.new(), WarpCommand.new(),
			MoveActorCommand.new(), FaceActorCommand.new(), WaitCommand.new(), EmoteCommand.new(),
			JoinPartyCommand.new(), BefriendPromptCommand.new(), SaveGameCommand.new(),
			SetRespawnCommand.new(), ToastCommand.new()]:
		assert_false(str(c).is_empty(), "%s describes itself" % (c as StoryCommand).get_script().resource_path.get_file())


func test_chest_script_gives_once() -> void:
	var c := ChestEntity.new()
	c.id = &"chest"
	var loot: Array[StringName] = [&"sagebloom_poultice"]
	c.loot_items = loot
	var s := StoryState.new()
	var first: Array = c.interact_script("a", s)
	assert_true(first[0] is SetFlagCommand, "opening sets the opened flag first")
	assert_true(first.any(func(x): return x is GiveItemCommand), "and gives the loot")
	s.set_flag(c.auto_flag("a"), 1)
	var again: Array = c.interact_script("a", s)
	assert_eq(again.size(), 1, "an opened chest only says it is empty")
	assert_true(again[0] is SayCommand, "(a Say)")


func test_trainer_scripts() -> void:
	var t := TrainerEntity.new()
	t.id = &"bram"
	t.battle = BattleSpec.new()
	t.defeated_scene = StoryScene.new()
	var s := StoryState.new()
	var challenge: Array = t.encounter_script("mossway", Vector3i(19, 5, 0), true)
	assert_true(challenge[0] is EmoteCommand, "a spotting trainer pops a bubble first")
	assert_true(challenge[1] is MoveActorCommand, "then walks up")
	assert_eq((challenge[1] as MoveActorCommand).to, Vector3i(19, 5, 0), "to the approach cell")
	assert_true(challenge.any(func(x): return x is StartBattleCommand), "and starts the battle")
	var talk: Array = t.interact_script("mossway", s)
	assert_false(talk.any(func(x): return x is MoveActorCommand), "talking to him does not walk him")
	s.set_flag(t.auto_flag("mossway"), 1)
	var beaten: Array = t.interact_script("mossway", s)
	assert_false(beaten.any(func(x): return x is StartBattleCommand), "a beaten trainer never battles again")


func test_warp_preserves_axis() -> void:
	var w := WarpEntity.new()
	w.area_rect = Rect2i(0, 4, 1, 3)
	w.preserve_axis = "row"
	assert_eq(w.arrival_cell(Vector3i(0, 6, 0), Vector3i(20, 10, 0)), Vector3i(20, 12, 0),
		"a row-preserving edge exit arrives offset by the row")
	w.preserve_axis = "none"
	assert_eq(w.arrival_cell(Vector3i(0, 6, 0), Vector3i(20, 10, 0)), Vector3i(20, 10, 0), "none = the entry cell")
	assert_eq(w.cells().size(), 3, "a warp covers its whole rect")
