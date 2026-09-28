extends GutTest

## The story entry points on the shared menus: the Solo picker's Story card, the Story start
## screen's three slots, and the Main Menu's "Continue Journey" row (only when a journey exists).
## All against a TEMP story save dir.

const Guard := preload("res://tests/helpers/global_state_guard.gd")
const TEMP_DIR := "user://test_story_entry_menus/"
const DESIGN := Vector2i(1280, 720)

var _prev_size: Vector2i


func before_all() -> void:
	_prev_size = get_tree().root.size
	get_tree().root.size = DESIGN


func after_all() -> void:
	get_tree().root.size = _prev_size


func before_each() -> void:
	StorySaveManager.set_save_dir(TEMP_DIR)
	Guard.rm_rf(TEMP_DIR)
	StoryController.end_session()


func after_each() -> void:
	StoryController.end_session()
	Guard.rm_rf(TEMP_DIR)
	StorySaveManager.set_save_dir(StorySaveManager.DEFAULT_SAVE_DIR)


func _open(script_path: String) -> Control:
	var screen := Control.new()
	screen.set_script(load(script_path))
	add_child_autofree(screen)
	for i in range(4):
		await get_tree().process_frame
	return screen


func test_solo_picker_has_a_story_card() -> void:
	var screen := await _open("res://menus/SoloModeSelect.gd")
	var card := screen.find_child("StoryCard", true, false) as Button
	assert_not_null(card, "a Story card on the Solo picker")
	assert_true(card.is_visible_in_tree(), "drawn")
	var hint := screen.find_child("KeyHint", true, false) as Label
	assert_true(hint.text.contains("7 Story"), "with its number key")
	assert_true(card.get_global_rect().end.x <= DESIGN.x + 0.5, "and it fits the 720p page")


func test_story_start_screen_slots() -> void:
	var s := StoryState.new()
	s.add_member("vineweave")
	s.set_location("mossway", Vector3i(1, 6, 0), "east")
	StorySaveManager.save(2, s)
	var screen := await _open("res://game/overworld/ui/StoryStartScreen.gd")
	var row := screen.find_child("SlotCards", true, false)
	assert_eq(row.get_child_count(), 3, "three journey slots")
	var text1: String = ""
	for l in row.get_child(0).find_children("*", "Label", true, false):
		text1 += (l as Label).text + " "
	assert_true(text1.contains("NEW JOURNEY"), "an empty slot offers a new journey")
	var text2: String = ""
	for l in row.get_child(1).find_children("*", "Label", true, false):
		text2 += (l as Label).text + " "
	assert_true(text2.contains("CONTINUE") and text2.contains("Mossway"), "a saved slot shows where you are (%s)" % text2)
	for c in row.get_children():
		assert_true((c as Control).get_global_rect().end.x <= DESIGN.x + 0.5, "slot cards fit 1280 wide")


func test_main_menu_continue_journey_row() -> void:
	var none := await _open("res://menus/MainMenu.gd")
	assert_null(none.find_child("ContinueJourneyButton", true, false), "no journey -> no row")
	StoryController.new_journey(3)
	StoryController.end_session()
	var menu := await _open("res://menus/MainMenu.gd")
	var row := menu.find_child("ContinueJourneyButton", true, false) as Button
	assert_not_null(row, "a saved journey surfaces as Continue Journey")
	assert_true(row.is_visible_in_tree(), "drawn")
