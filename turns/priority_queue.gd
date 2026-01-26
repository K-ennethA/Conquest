extends Resource

class_name PriorityQueue

# Generic priority queue implementation using a binary heap
# Supports custom comparator functions for flexible ordering

var heap: Array = []
var comparator: Callable

func _init(comp: Callable = _default_comparator):
	comparator = comp

func _default_comparator(a, b) -> int:
	# Default: max-heap for numbers
	if typeof(a) == TYPE_INT or typeof(a) == TYPE_FLOAT:
		return int(a - b)
	return 0

func push(value) -> void:
	heap.append(value)
	_heapify_up(heap.size() - 1)

func pop():
	if heap.is_empty():
		return null
	
	var top = heap[0]
	heap[0] = heap[heap.size() - 1]
	heap.pop_back()
	
	if not heap.is_empty():
		_heapify_down(0)
	
	return top

func peek():
	return heap[0] if not heap.is_empty() else null

func size() -> int:
	return heap.size()

func is_empty() -> bool:
	return heap.is_empty()

func build_heap(data: Array) -> void:
	heap = data.duplicate()
	var last_parent = (heap.size() / 2) - 1
	for i in range(last_parent, -1, -1):
		_heapify_down(i)

func clear() -> void:
	heap.clear()

# Internal heap operations
func _heapify_up(index: int) -> void:
	var current = index
	while current > 0:
		var parent = (current - 1) / 2
		if comparator.call(heap[current], heap[parent]) > 0:
			_swap(current, parent)
			current = parent
		else:
			break

func _heapify_down(index: int) -> void:
	var current = index
	var heap_size = heap.size()
	
	while true:
		var left = 2 * current + 1
		var right = 2 * current + 2
		var best = current

		if left < heap_size and comparator.call(heap[left], heap[best]) > 0:
			best = left
		if right < heap_size and comparator.call(heap[right], heap[best]) > 0:
			best = right

		if best != current:
			_swap(current, best)
			current = best
		else:
			break

func _swap(i: int, j: int) -> void:
	var temp = heap[i]
	heap[i] = heap[j]
	heap[j] = temp

func _swap(i: int, j: int) -> void:
	var temp = heap[i]
	heap[i] = heap[j]
	heap[j] = temp
