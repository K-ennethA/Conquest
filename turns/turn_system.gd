extends Node

# Turn-based system managing unit turn order and game flow
# Integrates with the board and unit systems through events

@export var priority_queue: PriorityQueue

var _current_unit: Unit
var _turn_active: bool = false

func _ready() -> void:
	priority_queue = PriorityQueue.new(_unit_priority_compare)
	_connect_events()

func _connect_events() -> void:
	GameEvents.unit_moved.connect(_on_unit_moved)

func initialize_with_units(units: Array[Unit]) -> void:
	priority_queue.build_heap(units)
	_start_next_turn()

func _start_next_turn() -> void:
	if priority_queue.is_empty():
		return
	
	_current_unit = priority_queue.pop()
	_turn_active = true
	_current_unit.has_turn = true
	
	GameEvents.turn_started.emit(_current_unit)

func end_current_turn() -> void:
	if not _current_unit or not _turn_active:
		return
	
	_current_unit.has_turn = false
	GameEvents.turn_ended.emit(_current_unit)
	
	# Re-queue the unit for future turns
	priority_queue.push(_current_unit)
	
	_current_unit = null
	_turn_active = false
	
	# Start next turn
	_start_next_turn()

func _on_unit_moved(unit: Unit, from_position: Vector3, to_position: Vector3) -> void:
	# End turn when current unit moves
	if unit == _current_unit:
		end_current_turn()

func get_current_unit() -> Unit:
	return _current_unit

func is_unit_turn(unit: Unit) -> bool:
	return unit == _current_unit and _turn_active

func _unit_priority_compare(a: Unit, b: Unit) -> int:
	# Higher speed = higher priority
	# Units with has_turn = true get priority over those without
	if a.has_turn != b.has_turn:
		return int(a.has_turn) - int(b.has_turn)
	return a.speed - b.speed
