# How to write a Conquest test

Framework: **GUT 9.5** (`addons/gut/`), Godot 4.6, GDScript with **tabs** and **explicit types**.

This document is the contract. If you are an agent adding tests, read it before you write
one — most of it exists because something already went wrong.

---

## Layout

```
tests/
├── unit/           # No scene tree, no autoload mutation, no disk. ~75 files, flat.
├── integration/    # Real tree, real autoloads, real map/turn systems.
├── performance/    # OPT-IN. Wall-clock thresholds; never in the default run.
├── helpers/        # Shared doubles + fixtures. Not a test dir -- see note below.
│   ├── test_doubles.gd        # MockUnit/MockBoard replacements
│   └── global_state_guard.gd  # snapshot/restore for autoloads and user:// files
├── results/        # JUnit XML output
├── .gutconfig.json # what the editor GUT panel runs
└── run_tests.gd    # what CI / the orchestrator runs
```

One file per unit of behaviour, named `test_<subject>.gd`, `extends GutTest`. Test functions
start with `test_`.

`tests/helpers/` is **not** a test directory — GUT only collects from the dirs listed in
`.gutconfig.json` (`unit`, `integration`), and subdirectory recursion is off. Do not add
`res://tests` itself to that list: `helpers/test_doubles.gd` carries the `test_` prefix and
GUT would try to run it as a suite.

**The flat `unit/` directory is a known wart.** With ~75 files it is at the edge of
manageable. Do not reorganise it piecemeal — either leave it flat or move all of it at once,
because half-nested directories are worse than either.

### Unit or integration?

| Put it in `unit/` when… | Put it in `integration/` when… |
|---|---|
| the subject is a resource, a pure function, or a system you can hand a double to | you need `add_child`, `await get_tree().process_frame`, or a real turn system |
| it never touches an autoload's state | it exercises autoload wiring (GameSettings, CombatServices, PlayerManager) |
| it never reads or writes `user://` | it loads a real `.tres` map and spawns real units |

The split is currently **imperfect** — several suites in `unit/` (`test_collaborative_lobby.gd`,
`test_map_selector_panel.gd`, `test_eldroot.gd`, `test_mycothrall.gd`) build real Controls or
live turn systems and are integration tests wearing a unit-test hat. Don't add more; when you
touch one of them, prefer moving it over deepening it.

---

## Running

```bash
# Everything (unit + integration). Exits non-zero if any test failed.
godot --headless --script tests/run_tests.gd

# One file, or one test, via GUT's own CLI.
godot --headless -s addons/gut/gut_cmdln.gd -gselect=test_mycothrall -gexit
godot --headless -s addons/gut/gut_cmdln.gd -gunit_test_name=refresh -gexit

# Performance suite (opt-in; see below).
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/performance -gexit
```

In the editor: **GUT panel → Run All**. Its directory list comes from `.gutconfig.json`;
keep that list and the one in `run_tests.gd` in step.

**How the orchestrator gates:** `tests/run_tests.gd` exits `0` only when the failure count is
zero, and prints a `WARNING: N orphan node(s)` line when nodes leaked. A change is not done
until that command exits 0. Batch your verification into **one** Godot launch — the engine is
slow to start and there is a project rule about not launching it repeatedly.

---

## The rules

### 1. Expected failures return values. They never touch the engine log.

**GUT 9.5 fails a test on any engine error** (`addons/gut/error_tracker.gd`:
`treat_engine_errors_as = FAILURE`). So a production path that reports a foreseeable, handled
failure with `push_error()` / `push_warning()` makes every test that covers that path red —
and the "fix" people reach for is to stop testing the failure.

A foreseeable failure is **data**, returned to the caller.

```gdscript
# GOOD -- the failure is a value the test can assert on.
var result := unit.perform_move(0, Vector2i.ZERO, null)
assert_false(result.success, "an empty slot fails")
assert_eq(result.reason, "no_move_in_slot", "and says why")
```

`push_error` is for **impossible** states — a bug, not a rejected input. If a test needs to
prove an error path, it proves the returned value, never the log.

### 2. Every Node a test creates must be freed. Target: zero orphans.

GUT counts, per script, every Node still alive when the script ends and prints them as
*orphans*. This suite was reporting ~50 every run. Orphans are not cosmetic — they keep
signal connections and static-registry entries alive into the next suite.

```gdscript
var sc: StatusController = autofree(StatusController.new())   # not in the tree
var u: Unit = add_child_autofree(Unit.new())                  # needs _ready() to run
```

- `autofree(x)` → `free()` after the test. `add_child_autofree(x)` adds to the test's tree
  first, so `_ready()` runs.
- **Never `queue_free()` in a test.** It defers to the end of the frame; GUT counts orphans
  before that happens. Use `autofree`, or `free()` directly.
- **Never both.** `add_child_autofree(x)` *and* `x.queue_free()` in `after_each` is a double
  disposal that turns a real failure into a confusing "freeing a freed object" error.
- A child is freed with its parent. `add_child_autofree(unit)` then `unit.add_child(controller)`
  is fine — one `autofree` covers both.
- **The trap that caused most of the leaks:** a `RefCounted` double that constructs a Node in
  `_init` (`class Thrall: ... _sc = StatusController.new()`). Freeing the RefCounted does not
  free the Node, and `autofree` is unavailable inside an inner class. Register them on a
  `static var` and sweep in `after_each` — see `unit/test_mycothrall.gd`.
- Base classes matter. `Unit` → `Node3D`. `StatusController` / `MovesetController` /
  `AbilitySystem` / `TileEffectSystem` / `HazardManager` / `MapLoader` / `BotTurnDriver` /
  `BaseAssaultRuntime` / turn systems → `Node`. `UltimateCutIn` → `CanvasLayer`.
  `BotController` / `MovementResolver` / `MatchRng` / `CommunityClient` → `RefCounted`.
  `Grid` and every `*Resource` → `Resource`. Only the Node ones can orphan.
- `assert_no_new_orphans()` is available if you want a suite to police itself.

### 3. Global state is snapshot-and-restored from `after_each`, never mid-test.

GUT runs `after_each` even when a test **fails**. Restoring at the end of the test body does
not — the first failing assertion leaks the mutation into every later suite in the run *and*
into the player's real save.

```gdscript
const Guard := preload("res://tests/helpers/global_state_guard.gd")

## Untyped on purpose. `var _guard: RefCounted` makes the static analyser reject
## `_guard.set_setting()` with "not found in base RefCounted" — the one place in a test
## where the project's explicit-types rule yields.
var _guard

func before_each() -> void:
	_guard = Guard.new()
	_guard.set_setting("ai_difficulty", BotController.Difficulty.NORMAL)  # snapshot + set
	_guard.watch_file(ChallengeController.RESULTS_PATH)                   # snapshot contents
	_guard.watch_dir(CommunityClient.MAPS_DIR)                            # snapshot listing

func after_each() -> void:
	_guard.restore()
```

**Never call a GameSettings setter that persists.** `GameSettings.set_animations_enabled()`
writes `user://settings.cfg` — calling it from a test edits the player's real settings file.
Assign the field instead, which is what `_guard.set_setting(...)` does.

The one exception is a suite that is testing *persistence itself*: redirect the whole block
with `GameSettings.set_settings_path("user://test_*.cfg")` in `before_all`, restore
`GameSettings.DEFAULT_SETTINGS_PATH` and delete the temp file in `after_all`, and the real
file is never opened. `integration/test_audio_settings_persistence.gd` is the exemplar.

Also global, and also your responsibility:
- **Static registries** — `UnitAnimator`'s busy registry, `CharacterLibrary`'s cache,
  `ItemLibrary`. Clear them in `before_each` *and* `after_each`.
- **Autoload singletons** — `CombatServices.rebuild()` leaves a board behind for the next
  suite; call `CombatServices.clear()` in both hooks.
- **The process-wide RNG.** `randomize()` reseeds it for every other suite. Never call it.
  Inject a seeded `RandomNumberGenerator`, or use `MatchRng` (see `unit/test_match_rng.gd`).

### 4. Temp paths, or a path-injection API. Never a real save path.

A test that writes the player's real files is a bug in the test.

```gdscript
const TEMP_SAVE_PATH := "user://test_item_inventory.json"

func before_all() -> void:
	ItemInventory.set_save_path(TEMP_SAVE_PATH)

func after_all() -> void:
	if FileAccess.file_exists(TEMP_SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_SAVE_PATH))
	ItemInventory.set_save_path(ItemInventory.DEFAULT_SAVE_PATH)
```

Classes with injection today: `ItemInventory.set_save_path`, `PlayerProfile.set_profile_path`
/ `set_source_paths`, `LocalProvider(root)`, `MapMakerModel.save_to_file(path)`,
`GameSettings.set_settings_path` (+ `reload_presentation_settings()` to re-read).

**Classes without it — a runtime-design gap, not a test problem:**
`ChallengeController.RESULTS_PATH`, `ChallengeCodec.CHALLENGE_DIR`, `CommunityClient.MAPS_DIR`
and `MapLoader.CUSTOM_MAPS_DIR` are `const`. The suites covering them
(`unit/test_community_client.gd`, `unit/test_challenge_survive_capture.gd`,
`unit/test_community_local_provider.gd`) therefore have to touch the **real** library and
restore it. That is as hermetic as it can be made from the test side: it survives a failing
assertion, but a **killed process** still leaves state behind. If you are changing those
classes, adding a `set_*_path()` static is the real fix.

### 5. Use the shared doubles, and keep each one an exact shape.

`tests/helpers/test_doubles.gd` replaces the ~24 hand-rolled `class MockUnit` /
`class MockBoard` copies.

```gdscript
const Doubles := preload("res://tests/helpers/test_doubles.gd")

var caster := Doubles.CombatUnit.new(0, {"attack": 30, "health": 100})
var board := Doubles.CombatBoard.new()
board.place(caster, Vector2i(0, 0))
```

| Double | Use it for |
|---|---|
| `CombatUnit` | the default target: stats, HP, stat modifiers |
| `TaggedCombatUnit` | + unit tags, which `TileEffectResource` filters on |
| `StatusSinkUnit` | + `add_status`, `ApplyStatusEffect`'s direct sink |
| `SimpleUnit` / `HpUnit` | stats+HP only / + `get_hp()` (`MoveExecutor`'s HP branch) |
| `ObjectiveUnit` | identity + liveness, for win/lose conditions |
| `MinimalBoard` | placement + faction queries |
| `CombatBoard` | + `move_unit` / `set_tile` (knockback, leap, terrain transform) |
| `TerrainBoard` | + `tile_tag_at` (`OnTerrainCondition`, `MovementResolver`) |
| `TileEffectBoard` | + `tile_effects_at` / `perspective_unit` |
| `RosterBoard` | + `all_units` (`BotController`, `ItemSystem`, win conditions) |

Migrated exemplars: `test_move_system.gd`, `test_abilities.gd`, `test_tile_effects.gd`,
`test_status_condition.gd`, `test_line_friendly_fire.gd`, `test_combat_hit_crit.gd`,
`test_win_condition.gd`. Follow those when you migrate another suite.

**Do not add a convenience method to an existing double.** The production code is duck-typed:
`DamageEffect` branches on `has_method("get_base_stat")`, `MoveExecutor` on `get_hp`,
`ApplyStatusEffect` on `add_status`, `TileEffectResource` on `perspective_unit`. Adding one
method silently reroutes every suite that uses that double through a different code path.
Add a small **subclass** and name what it is for.

Keep a double local only when it is genuinely one-off — e.g. a board that deliberately *lacks*
a hook, to prove production code fails closed (`_NoTerrainBoard` in `test_abilities.gd`).

### 6. Every assertion carries a message.

```gdscript
assert_eq(unit.hp, 15, "one tick restored exactly 5 HP")
```

Not "should be 15" — say what the game **rule** is. This suite is already near-universal on
this; keep it that way. A bare `assert_true(x)` in a 900-test run tells the next reader nothing.

### 7. No wall-clock waiting.

`await get_tree().process_frame`, as many as you need. Never
`await get_tree().create_timer(1.0).timeout` — it costs a real second every run and fails on a
loaded machine for reasons unrelated to the code. If you must poll, bound it in **frames** and
assert on the outcome (`_await_until` in `integration/test_mp_loopback.gd` is the pattern).

Anything genuinely environment-dependent (live sockets, GPU) goes behind `pending()` with a
reason and an opt-in env var — see `integration/test_mp_loopback.gd`.

### 8. `pending()` is honest; a vacuous assertion is not.

If a fixture cannot be built (a roster character whose `.glb` is not imported, no
`GameSettings` autoload), call `pending("why")` and return. Do **not** let a test pass by
asserting two nulls are equal — `integration/test_game_events.gd` did exactly that for a long
time, because the removed `Unit.new("name", 10, 3)` constructor returned `null` on both sides
of the `assert_eq`.

And never assert on an expression written in the test itself. It cannot fail, so it is not a
test.

---

## Performance tests

`tests/performance/` is **not** in `.gutconfig.json` and **not** in `run_tests.gd`. Every
assertion there is a wall-clock threshold, which is a property of the machine rather than of
the code. Run it deliberately while optimising:

```bash
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/performance -gexit
```

---

## Known gaps (don't "fix" these by accident)

- `systems/test_battle_effects_integration.gd`, `systems/test_player_management.gd`,
  `systems/test_speed_first_turn_system.gd`, `systems/test_traditional_turn_system.gd`,
  `systems/test_turn_numbering.gd` live in the **runtime** tree, `extends Node` (not
  `GutTest`), and nothing runs them. They are manual scratch scenes that look like tests.
  Port them into `tests/` as real GUT suites or delete them — do not leave a third category.
- `unit/` is flat at ~75 files (see *Layout*).
- The non-injectable `user://` paths listed under rule 4.
