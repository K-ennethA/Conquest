extends GutTest

## THE DEPLOY PICKER view (docs/design/HUMANS.md "Deploying"): it opens on the default squad, a
## required hero's card is locked, toggling respects the squad size, and Deploy emits the picks.

var _screen: SquadPickScreen = null
var _got: Array = []


func after_each() -> void:
	if _screen != null and is_instance_valid(_screen):
		_screen.free()
	_screen = null
	_got = []


func _cands() -> Array:
	return [
		{"id": "wren", "character_id": "wren", "name": "Wren", "level": 5, "kind": "human",
			"hero": true, "guest": false, "temporary": false, "required": true, "member": true},
		{"id": "tree_grunt", "character_id": "tree_grunt", "name": "Barkling", "level": 5,
			"kind": "creature", "hero": false, "guest": false, "temporary": false, "required": false, "member": true},
		{"id": "petalfang", "character_id": "petalfang", "name": "Petalfang", "level": 5,
			"kind": "creature", "hero": false, "guest": false, "temporary": false, "required": false, "member": true},
		{"id": "guest:lyra", "character_id": "lyra", "name": "Lyra", "level": 6, "kind": "human",
			"hero": false, "guest": true, "temporary": true, "required": false, "member": false},
	]


func _on_confirmed(picks: Array) -> void:
	_got = picks


func test_picker_defaults_toggles_and_confirms() -> void:
	_screen = SquadPickScreen.open(self, _cands(), 2, "Enemy Soldiers")
	await get_tree().process_frame
	_screen.confirmed.connect(_on_confirmed)
	assert_eq(_screen.picks(), ["wren", "tree_grunt"] as Array[String], "the default squad")
	var hero_card := _screen.find_child("Pick_wren", true, false) as Button
	assert_not_null(hero_card)
	assert_true(hero_card.disabled, "a required hero is locked in")
	assert_true(hero_card.button_pressed)
	_screen.toggle("guest:lyra")
	assert_eq(_screen.picks().size(), 2, "full: nothing added")
	_screen.toggle("tree_grunt")
	_screen.toggle("guest:lyra")
	assert_eq(_screen.picks(), ["wren", "guest:lyra"] as Array[String])
	var go := _screen.find_child("DeployButton", true, false) as Button
	assert_false(go.disabled)
	go.pressed.emit()
	assert_eq(_got, ["wren", "guest:lyra"])
