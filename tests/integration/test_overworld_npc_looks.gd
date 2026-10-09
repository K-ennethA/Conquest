extends GutTest

## NPC LOOKS on the real overworld ([NpcLooks]; owner 2026-10-08): booted Oakvale's people wear
## the placeholder human models -- Wren's clone by default, Lyra's for the hero's mother (the
## content marks her body "female"), a child scaled down -- the hero's own actor and props are
## unchanged, and the ruleset knob switches everyone back to the procedural figures.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const StoryFixture := preload("res://tests/helpers/story_fixture.gd")
const OVERWORLD_SCENE := preload("res://game/overworld/OverworldScene.tscn")
const TEMP_DIR := "user://test_overworld_npc_looks/"

var _guard
var _world: Node = null
var _prev_scene: Node = null
var _prev_enabled: bool = true
## The live ruleset a test flipped the knob on (restored in after_each).
var _rs: StoryRuleset = null


func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("animations_enabled", false)
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()
	StoryController.scene_changes_enabled = false


func after_each() -> void:
	_teardown()
	if _rs != null:
		_rs.npc_models_enabled = _prev_enabled
	_rs = null
	StoryController.end_session()
	StoryController.scene_changes_enabled = true
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)
	PortraitCache.reset()
	_guard.restore()
	await get_tree().process_frame


func _boot(models_on: bool = true) -> OverworldController:
	StoryController.new_journey(1)
	StoryFixture.past_opening(StoryController.state())
	_rs = StoryController.ruleset()
	_prev_enabled = _rs.npc_models_enabled
	_rs.npc_models_enabled = models_on
	var w: Node = OVERWORLD_SCENE.instantiate()
	_prev_scene = get_tree().current_scene
	get_tree().root.add_child(w)
	get_tree().current_scene = w
	_world = w
	await get_tree().process_frame
	await get_tree().process_frame
	return w as OverworldController


func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = _prev_scene
		_world.get_parent().remove_child(_world)
		_world.free()
	_world = null


func _scene_of(ow: OverworldController, id: String) -> String:
	var a: OverworldActor = ow.actor(id)
	return a.model().scene_file_path if a != null and a.model() != null else ""


func _skinned(n: Node) -> bool:
	return not n.find_children("*", "Skeleton3D", true, false).is_empty()


func test_people_wear_the_wren_and_lyra_clones() -> void:
	var ow := await _boot()
	assert_eq(ow.area.area_id, &"oakvale", "Oakvale")
	var wren: CharacterResource = CharacterLibrary.get_character(&"wren")
	var lyra: CharacterResource = CharacterLibrary.get_character(&"lyra")
	assert_eq(_scene_of(ow, "tobin"), wren.model_scene.resource_path, "a villager wears Wren's clone")
	assert_eq(_scene_of(ow, "briony"), lyra.model_scene.resource_path, "the hero's mother wears Lyra's clone")
	var pell: OverworldActor = ow.actor("pell")
	assert_eq(_scene_of(ow, "pell"), wren.model_scene.resource_path, "a child wears the default clone")
	assert_lt(pell.model().scale.y, ow.actor("tobin").model().scale.y, "scaled down")
	assert_true(bool(ow.actor("tobin").get_meta(OverworldController.HERO_STRIDES_META, false)),
		"a clone of the hero's model walks at his stride rates")
	assert_false(bool(pell.get_meta(OverworldController.HERO_STRIDES_META, false)),
		"a scaled-down child does not (its stride is shorter)")
	var anims: Array[Node] = ow.actor("tobin").model().find_children("*", "AnimationPlayer", true, false)
	assert_false(anims.is_empty(), "the Wren clone carries the hero's clips")
	assert_true((anims[0] as AnimationPlayer).is_playing(), "and idles")
	assert_false(_skinned(ow.actor("house_home").model()), "props are unchanged")
	assert_eq(ow.player.model().scene_file_path, StoryController.hero().model_scene.resource_path,
		"the hero's own actor is unchanged")


func test_the_knob_switches_back_to_the_figures() -> void:
	var ow := await _boot(false)
	for id in ["tobin", "briony", "pell"]:
		var a: OverworldActor = ow.actor(id)
		assert_not_null(a, id)
		assert_not_null(a.model(), "%s has a body" % id)
		assert_false(_skinned(a.model()), "%s is the procedural figure again" % id)
		assert_eq(a.model().scene_file_path, "", "%s: not a roster model" % id)
