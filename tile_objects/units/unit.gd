extends TileObject

class_name Unit

var unit_name : String
var speed : int
var has_turn : bool
var movement: int

func _ready() -> void:
	print("wtf is happening")
	_test("kenneth", 10, false)

func _test(_name: String, _speed: int, _has_turn: bool) -> void:
	print("hello ue")
	unit_name = _name
	speed = _speed
	has_turn = _has_turn
