extends SceneTree

## Command-line test runner (CI / orchestrator gate).
##
##     godot --headless --script tests/run_tests.gd
##
## Exits 0 only when zero tests failed, so a CI step or an orchestrating agent can gate on
## the process exit code. (The previous version called quit() with no argument, which meant
## a red suite still exited 0 and every gate passed.)
##
## For anything narrower, prefer GUT's own CLI -- it takes filters this script does not:
##     godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit -gexit
##     godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_mycothrall -gexit
##     godot --headless -s addons/gut/gut_cmdln.gd -gunit_test_name=refresh -gexit

var _gut


func _init() -> void:
	print("Starting GUT test runner...")

	_gut = preload("res://addons/gut/gut.gd").new()

	# Keep these in step with tests/.gutconfig.json (which the editor panel reads).
	# tests/performance is opt-in and deliberately absent -- see tests/README.md.
	_gut.add_directory("res://tests/unit")
	_gut.add_directory("res://tests/integration")
	_gut.set_log_level(_gut.LOG_LEVEL_ALL_ASSERTS)
	_gut.set_yield_between_tests(true)
	_gut.set_export_path("res://tests/results/")

	_gut.tests_finished.connect(_on_tests_finished)

	get_root().add_child(_gut)
	_gut.test_scripts()


func _on_tests_finished() -> void:
	var failures: int = _gut.get_fail_count()
	var orphans: int = _gut.get_orphan_counter().get_count()
	print("Tests completed: %d run, %d failed, %d pending."
		% [_gut.get_test_count(), failures, _gut.get_pending_count()])
	if orphans > 0:
		# Not a failure (yet) -- but every orphan is a Node a test forgot to free, and the
		# suite's standing target is zero. See tests/README.md ("Orphans").
		print("WARNING: %d orphan node(s) left behind." % orphans)
	quit(0 if failures == 0 else 1)
