extends Resource

class_name PriorityQueue

var heap: Array = []
var comparator: Callable = func(a, b): return a - b  # Default: max-heap for numbers

func _init(comp: Callable):
	if comp.is_valid():
		comparator = comp

func push(value):
	heap.append(value)
	_heapify_up(heap.size() - 1)

func pop():
	if heap.is_empty():
		return null
	var top = heap[0]
	heap[0] = heap[heap.size() - 1]
	heap.pop_back()
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

# Internal methods

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
	var size = heap.size()
	while true:
		var left = 2 * current + 1
		var right = 2 * current + 2
		var best = current

		if left < size and comparator.call(heap[left], heap[best]) > 0:
			best = left
		if right < size and comparator.call(heap[right], heap[best]) > 0:
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
