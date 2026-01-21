extends Node

@export var queue = preload("res://turns/PriorityQueue.tres")

func _ready() -> void:
	queue = PriorityQueue.new(custom_compare)
	_test()

func _test():
	queue.build_heap([
		Unit.new("ken", 10, true),
		Unit.new("lorena", 12, false),
		Unit.new("leia", 8, true),
		Unit.new("roxy", 7, true)
	])
	
	print(queue.heap.size())
	print(queue.heap)

	for i in queue.size():
		print(queue.pop().unit_name)
	
func is_turn(player_id: String) -> bool:
	return false
	
func get_next(units):
	var elem = queue.pop()
	var test = elem.get("turn")
	
	queue.push(elem)
	return

func custom_compare(a: Unit, b: Unit):
	if a.has_turn && b.has_turn:
		return a.speed - b.speed
	else:
		return int(a.has_turn) - int(b.has_turn)
