extends GutTest

# Unit tests for PriorityQueue
# Tests heap operations, custom comparators, and edge cases

var queue: PriorityQueue

func before_each():
	queue = PriorityQueue.new()

func test_empty_queue():
	assert_true(queue.is_empty(), "New queue should be empty")
	assert_eq(queue.size(), 0, "New queue should have size 0")
	assert_null(queue.peek(), "Peek on empty queue should return null")
	assert_null(queue.pop(), "Pop on empty queue should return null")

func test_single_element():
	queue.push(42)
	
	assert_false(queue.is_empty(), "Queue with element should not be empty")
	assert_eq(queue.size(), 1, "Queue should have size 1")
	assert_eq(queue.peek(), 42, "Peek should return the element")
	
	var popped = queue.pop()
	assert_eq(popped, 42, "Pop should return the element")
	assert_true(queue.is_empty(), "Queue should be empty after pop")

func test_multiple_elements_max_heap():
	var numbers = [3, 1, 4, 1, 5, 9, 2, 6]
	
	for num in numbers:
		queue.push(num)
	
	# Should pop in descending order (max heap)
	var expected = [9, 6, 5, 4, 3, 2, 1, 1]
	var actual = []
	
	while not queue.is_empty():
		actual.append(queue.pop())
	
	assert_eq(actual, expected, "Should pop elements in max-heap order")

func test_build_heap():
	var numbers = [3, 1, 4, 1, 5, 9, 2, 6]
	queue.build_heap(numbers)
	
	assert_eq(queue.size(), 8, "Built heap should have correct size")
	
	# Should pop in descending order
	var expected = [9, 6, 5, 4, 3, 2, 1, 1]
	var actual = []
	
	while not queue.is_empty():
		actual.append(queue.pop())
	
	assert_eq(actual, expected, "Built heap should maintain max-heap property")

func test_custom_comparator():
	# Test with custom comparator for min-heap
	var min_comparator = func(a, b): return b - a  # Reverse comparison for min-heap
	queue = PriorityQueue.new(min_comparator)
	
	var numbers = [3, 1, 4, 1, 5, 9, 2, 6]
	for num in numbers:
		queue.push(num)
	
	# Should pop in ascending order (min heap)
	var expected = [1, 1, 2, 3, 4, 5, 6, 9]
	var actual = []
	
	while not queue.is_empty():
		actual.append(queue.pop())
	
	assert_eq(actual, expected, "Custom comparator should create min-heap")

func test_clear():
	queue.push(1)
	queue.push(2)
	queue.push(3)
	
	queue.clear()
	
	assert_true(queue.is_empty(), "Queue should be empty after clear")
	assert_eq(queue.size(), 0, "Queue size should be 0 after clear")

func test_peek_doesnt_modify():
	queue.push(5)
	queue.push(3)
	queue.push(8)
	
	var original_size = queue.size()
	var peeked = queue.peek()
	
	assert_eq(queue.size(), original_size, "Peek should not change queue size")
	assert_eq(queue.peek(), peeked, "Multiple peeks should return same value")
	assert_eq(queue.pop(), peeked, "Pop should return same value as peek")