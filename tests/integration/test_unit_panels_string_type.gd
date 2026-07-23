extends GutTest

# Regression: after the character migration, Unit.get_unit_type() returns a
# String (the character id), but several live panels still treated it as an
# object -- `unit_type.display_name`, `.get_type_name()`, `.type` -- which
# hard-crashed the moment a unit was selected ("Invalid access to property or
# key 'display_name' on a base object of type 'String'"). These tests drive the
# exact update methods with a real character-backed unit; before the fix they
# throw, after the fix they update cleanly.

const ACTIONS_PANEL := preload("res://game/ui/panels/UnitActionsPanel.tscn")
const INFO_PANEL := preload("res://game/ui/panels/UnitInfoPanel.tscn")


func _make_character_unit() -> Unit:
	var c := CharacterResource.new()
	c.character_id = &"vineweave"
	c.display_name = "Torvald Ironhide"
	var u := Unit.new()
	u.character_resource = c
	add_child_autofree(u)  # _ready derives the stats component (sets unit_type)
	return u


func test_get_unit_type_is_a_string():
	var u := _make_character_unit()
	assert_eq(typeof(u.get_unit_type()), TYPE_STRING, "get_unit_type() returns a String")
	assert_eq(u.get_unit_type(), "vineweave", "and it is the character id")


func test_actions_panel_header_and_icon_survive_selection():
	var u := _make_character_unit()
	var panel = ACTIONS_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame  # let @onready labels resolve

	panel.selected_unit = u
	panel._update_unit_header()  # crashed here pre-fix (String.display_name)
	panel._update_unit_icon()    # and here

	pass_test("actions panel header + icon updated without error")


func test_info_panel_update_survives_selection():
	var u := _make_character_unit()
	var panel = INFO_PANEL.instantiate()
	add_child_autofree(panel)
	await get_tree().process_frame

	panel._update_unit_info(u)  # crashed pre-fix (.get_type_name() then .type)

	pass_test("info panel updated without error")
