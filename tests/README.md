# Testing Setup for Conquest

This project uses **GUT (Godot Unit Test)** framework for comprehensive testing.

## Installation

### 1. Install GUT Plugin

1. Open your project in Godot Editor
2. Click **AssetLib** at the top of the editor
3. Search for **"Gut"**
4. Click on the GUT result and click **"Install"**
5. Click the second **"Install"** button when download finishes
6. Click the third **"Install"** button in the confirmation dialog

### 2. Activate GUT Plugin

1. Go to **Project → Project Settings**
2. Click the **Plugins** tab
3. Find **Gut** in the list and check the **Enable** checkbox
4. You should now see a **GUT** panel at the bottom of the editor

### 3. Configure Test Directories

1. In the GUT panel, scroll to **"Test Directories"** section
2. Add the following directories:
   - `res://tests/unit`
   - `res://tests/integration`
   - `res://tests/performance`

## Running Tests

### In Editor (Recommended for Development)

1. Open the **GUT** panel at the bottom of the editor
2. Click **"Run All"** to run all tests
3. Use **"Run"** to run individual test files
4. Check the output for results and any failures

### Command Line (For CI/CD)

```bash
# Run all tests headlessly
godot --headless --script tests/run_tests.gd

# Run with specific log level
godot --headless --script tests/run_tests.gd -- --log_level=2
```

## Test Structure

```
tests/
├── unit/                    # Unit tests for individual classes
│   ├── test_grid.gd        # Grid coordinate system tests
│   ├── test_priority_queue.gd # Priority queue algorithm tests
│   ├── test_unit.gd        # Unit class tests
│   └── test_turn_system.gd # Turn system logic tests
├── integration/             # Integration tests for system interactions
│   ├── test_board_integration.gd # Board system integration
│   └── test_game_events.gd # Event system integration
├── performance/             # Performance and benchmark tests
│   └── test_pathfinding_performance.gd
├── mocks/                   # Mock objects for testing
│   └── mock_game_events.gd
├── results/                 # Test output files (JUnit XML, etc.)
├── .gutconfig.json         # GUT configuration
├── run_tests.gd           # Command line test runner
└── README.md              # This file
```

## Writing Tests

### Basic Test Structure

```gdscript
extends GutTest

var my_object

func before_each():
    # Setup before each test
    my_object = MyClass.new()

func after_each():
    # Cleanup after each test
    if my_object:
        my_object.queue_free()

func test_something():
    # Your test code
    assert_eq(my_object.some_value, expected_value, "Description of what should happen")
```

### Common Assertions

- `assert_true(condition, message)`
- `assert_false(condition, message)`
- `assert_eq(actual, expected, message)`
- `assert_ne(actual, expected, message)`
- `assert_null(value, message)`
- `assert_not_null(value, message)`
- `assert_gt(actual, expected, message)` (greater than)
- `assert_lt(actual, expected, message)` (less than)

### Testing Signals

```gdscript
func test_signal_emission():
    # Watch for signal
    watch_signals(my_object)
    
    # Trigger action that should emit signal
    my_object.do_something()
    
    # Verify signal was emitted
    assert_signal_emitted(my_object, "signal_name")
    assert_signal_emit_count(my_object, "signal_name", 1)
```

## Best Practices

1. **Test Naming**: Use descriptive test names starting with `test_`
2. **One Assertion Per Concept**: Each test should verify one specific behavior
3. **Setup/Teardown**: Use `before_each()` and `after_each()` for consistent test state
4. **Mock Dependencies**: Use mock objects to isolate units under test
5. **Test Edge Cases**: Include tests for boundary conditions and error cases
6. **Performance Tests**: Include performance tests for critical algorithms
7. **Integration Tests**: Test system interactions separately from unit tests

## Continuous Integration

The project includes a command-line test runner (`tests/run_tests.gd`) that can be integrated with CI/CD systems:

```yaml
# Example GitHub Actions workflow
- name: Run Tests
  run: godot --headless --script tests/run_tests.gd
```

## Test Coverage

Focus testing on:
- ✅ **Grid System**: Coordinate conversion, bounds checking
- ✅ **Priority Queue**: Heap operations, custom comparators  
- ✅ **Unit Management**: Properties, movement validation
- ✅ **Turn System**: Turn order, priority handling
- ✅ **Event System**: Signal emission and handling
- ✅ **Board Logic**: Unit selection, movement, highlighting
- ✅ **Performance**: Algorithm efficiency with large datasets

## Troubleshooting

### GUT Panel Not Showing
- Ensure GUT plugin is activated in Project Settings → Plugins
- Restart Godot Editor

### Tests Not Found
- Check test directory paths in GUT panel settings
- Ensure test files start with `test_` prefix
- Verify test classes extend `GutTest`

### Signal Tests Failing
- Make sure GameEvents singleton is properly configured
- Check that signals are connected before testing
- Use mock objects to isolate signal testing