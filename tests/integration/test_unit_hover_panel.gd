extends GutTest

## UnitHoverPanel's selected-unit suppression (game/ui/panels/UnitHoverPanel.gd).
##
## The hover card exists for peeking at OTHER units; the SELECTED unit's readout
## lives on the compact battle card (see the unit-info split in UnitInfoPanel).
## Showing the same HP twice was the duplication the split removed, so the panel
## must refuse to show the selected unit -- and drop it the moment it becomes
## selected while on display.
##
## Handlers are driven directly (_on_unit_selected / _on_unit_deselected):
## GameEvents.unit_selected is TYPED (unit: Unit), so a lightweight stub cannot
## ride the real signal -- the wiring itself is a one-line connect covered by the
## panel's _ready guards.

const PANEL_SCRIPT := preload("res://game/ui/panels/UnitHoverPanel.gd")

## Minimal duck-typed unit: the panel reads HP via `"current_health" in unit`
## guards and never demands a real Unit.
class StubUnit extends Node:
	var current_health: int = 40
	var max_health: int = 60
	func get_display_name() -> String:
		return "Stub"

var panel: Control
var unit_a: StubUnit
var unit_b: StubUnit

func before_each() -> void:
	panel = Control.new()
	panel.set_script(PANEL_SCRIPT)
	add_child_autofree(panel)
	unit_a = StubUnit.new()
	add_child_autofree(unit_a)
	unit_b = StubUnit.new()
	add_child_autofree(unit_b)

func after_each() -> void:
	panel = null
	unit_a = null
	unit_b = null


func test_shows_a_plain_hovered_unit() -> void:
	panel.show_for_unit(unit_a)
	assert_true(panel.visible, "an unselected unit is exactly what the hover card is for")

func test_refuses_to_show_the_selected_unit() -> void:
	panel._on_unit_selected(unit_a)
	panel.show_for_unit(unit_a)
	assert_false(panel.visible,
		"the selected unit's readout lives on the battle card -- never duplicated here")

func test_hides_immediately_when_the_shown_unit_becomes_selected() -> void:
	panel.show_for_unit(unit_a)
	panel._on_unit_selected(unit_a)
	assert_false(panel.visible,
		"selection while on display drops the card now, not on the next cursor move")

func test_other_units_still_show_while_one_is_selected() -> void:
	panel._on_unit_selected(unit_a)
	panel.show_for_unit(unit_b)
	assert_true(panel.visible, "suppression is per-unit, not a blanket hide")

func test_deselection_lifts_the_suppression() -> void:
	panel._on_unit_selected(unit_a)
	panel._on_unit_deselected(unit_a)
	panel.show_for_unit(unit_a)
	assert_true(panel.visible, "once deselected, the unit is hoverable like any other")

func test_selecting_a_different_unit_does_not_hide_the_shown_one() -> void:
	panel.show_for_unit(unit_b)
	panel._on_unit_selected(unit_a)
	assert_true(panel.visible,
		"selecting unit A must not drop a card that is showing unit B")
