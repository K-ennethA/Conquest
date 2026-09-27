# Handoff — review, multiplayer, Fire-Emblem UX, multi-floor, world, weather

Branch: `claude/ecstatic-hamilton-6g2nrc` (base: `3f67852`, PR #1 merge on main).
Engine: Godot 4.6. Test suite: GUT (`addons/gut`).

This document is the entry point for whoever picks the project up next: what was
built, where it lives, how to run/verify it, and what is still open.

---

## 1. How to run and verify

```bash
# one-time (or after pulling): import the project
godot --headless --import .

# full test suite (expect 0 failures; 6 pre-existing "SCRIPT ERROR" parse lines in
# old tests -- test_board_integration / test_game_events / test_pathfinding_performance
# + one GUT loader line -- are known and harmless)
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -ginclude_subdirs -gexit

# real multi-process network check (dedicated server + 2 bot clients over ENet)
GODOT=godot bash dev_scripts/net_multiprocess_check.sh res://game/maps/resources/castle_siege.tres traditional 40
HOSTED=1 GODOT=godot bash dev_scripts/net_multiprocess_check.sh res://game/maps/resources/river_crossing.tres speed_first 40

# dedicated server
godot --headless --path . -- --server --port 8910 [--map res://... --turn-system traditional|speed_first --rng all|server]
```

**Testing multiplayer on one machine:** run the game twice (editor: *Debug → Customize
Run Instances → 2*, or `godot --path .` twice). A: *Versus → Network → Host*; B: join
`127.0.0.1:8910`; both Ready; host starts. Or run the dedicated server and join both.

Visual checks were done with the Compatibility (OpenGL3) renderer under xvfb in CI-like
containers; **Forward+ on a real GPU was never checked** — do a visual pass there.

---

## 2. What was built (by area) and where

### Bug fixes from the initial review
- Plain **M** quit to main menu; debug hotkeys (S/V/T/U/O/I/L, F1–F8) live in play →
  gated behind debug build + Ctrl+Shift (`InputActions.is_debug_hotkey`).
- Survive-N-turns / Seize could never be won (turn hardcoded 0) → `WinConditionLibrary`,
  `GameWorldManager._build_win_state`.
- P could end the AI's turn; arrow keys also panned the camera; no key repeat; AoE
  preview only after commit; hotseat outlines from P1's view; `MapResource.import_from_json`
  broken; cursor only saw `Player1/2`; terrain panel move cost ignored movement profile;
  `unit._on_unit_selected` arg-count error; Speed-First crash when a queued unit died;
  timed evasion/magic/crit modifiers silently ignored (`UnitStats._set_current_stat`);
  local hotseat silently became single-player at the turn-system screen.

### Input, controller, rebinding
`game/ui/input/InputActions.gd` + `project.godot [input]`: named actions with keyboard +
gamepad bindings; Settings → Controls tab rebinding (saved in `user://settings.cfg`).
Key hints in the UI come from `InputActions.hint()`.

### Multiplayer (`systems/net/`, read `systems/net/README.md`)
- Legacy stack (systems/networking, systems/multiplayer, GameManager network handlers,
  CollaborativeLobby, auto-client launchers) **deleted**; one stack: `NetSession`
  (autoload; class `NetSessionNode` so tests can instantiate several).
- Host/server-authoritative: intents (MOVE / USE_MOVE / WAIT / END_TURN) validated by
  `NetGameRules` (turn, ownership, reachability, target legality) and applied by one
  deterministic function on every peer. Actor = sender's seat, never the payload.
- **Commit-reveal RNG** (`NetCommitReveal.gd`): per-action hash-chain reveals from every
  contributor → no one can predict or bias a roll; clients re-validate host actions.
- **Dedicated headless server** (`--server`), **pluggable transport** (`NetTransport` /
  `ENetTransport`; README sketches Steam/WebSocket/WebRTC).
- Desync detection via state digests (includes floor + weather); disconnects end the
  match cleanly; session reset on leaving.
- Known limits: 1v1 humans only, no reconnect, no encryption/auth, one match per server
  process, dynamic weather predictable from the public seed.

### Fire-Emblem-style board UX
Danger zone (Z) + single-enemy threat (`game/combat/ThreatResolver.gd`,
`DangerZoneOverlay`), red attack fringe, path arrow + cell-by-cell walking
(`PathArrow`, `UnitAnimator.walk_path`), map menu (`game/ui/panels/MapMenu.gd`: Units,
Objective, Settings, End Turn, Return to Title), objective chip, hold-Shift fast-forward,
walk through allies, forecast chips (effectiveness, height, weather), unit cycling
(Tab/Q/R, LB/RB), camera follow, cursor memory, **smart unit facing**
(`game/visuals/UnitFacing.gd`, `FacingController.gd`; per-model `model_yaw_deg`
corrected for 6 units; visual only; `Unit.get_facing()` for future flanking rules).

### Multi-floor maps (read `docs/MULTI_FLOOR.md`)
Cells are `Vector3i(col, row, floor)` everywhere (`game/board/Cells.gd`). Links/stairs,
floor-aware pathfinding + `path_to`, melee reach / LOS / cover (`LineOfSight.gd`), height
advantage (`Elevation.gd`), AI takes stairs. View floor + cutaway (`FloorCutaway.gd`),
floor HUD, stairs/parapet/broken-bridge decor (`FloorDecor.gd`), multi-floor Map Maker
(reachable from Compendium). Showcase maps: **River Crossing**, **Castle Siege**.

### Menus + battle HUD (read `docs/UI_STYLE.md`)
"Illuminated grove heraldry" theme: `OrnateStyleBox` (notched cards, ribbons, shields,
tags), Cinzel display font (OFL, `fonts/`), element crests, `MenuTheme` tokens shared by
`ConquestTheme`, `MenuKit`/`MenuNav` (breadcrumbs, back, controller focus). Compact
one-strip top HUD (`HudSafeArea.gd`). Before/after shots in `docs/screenshots/`.

### World art (read `docs/WORLD_ART.md`)
Seamless painterly ground (`stylized_grass.gdshader`, `world_lib`/`ground_lib`
includes), new trees (`TreeBuilder.gd`), water/lava/wall/sacred scenes, tile-effect
visuals, **world skirt** so maps no longer float, `WorldLook` (single owner of lighting,
tweenable; bridged to weather via `apply_weather_look`), optional grid lines setting.
Camera opens at a readable zoom (`CameraController.MIN_CELL_PX`) and scrolls on big maps.

### Weather (read `docs/WEATHER.md`)
Data-driven `WeatherResource`s (`game/weather/resources`): Clear, Bright Sun, Rain,
Desert Storm, Overbloom — element damage scales, turn-start effects, stat rules,
tile-effect suppression; weather-conditioned abilities (Rain Bath, Sunlit, Sand Veil)
and a weather-summoning move (Verdant Call). Map weather: fixed / schedule / dynamic
(deterministic). Visuals: `game/visuals/weather/` (particles, overlay, env adapter).
Settings: Weather Effects Full/Reduced/Off (visual only).

---

## 3. Open items / suggested next steps

1. **Visual pass on Forward+ / real GPU**, and profile the world skirt (thousands of
   MultiMesh trees + shadows) on low-end hardware.
2. **Fire Emblem item 8 (deferred by request):** support/adjacency bonuses (Pair Up /
   Attack Stance equivalent), suspend/save, dragon veins / destructible walls.
3. Multiplayer: reconnect, auth/encryption, concurrent matches per server (needs the
   global singletons refactor described in `systems/net/README.md`), choose a platform
   transport (Steam relay etc.).
4. Weather: a desert map; AI avoidance of weather hazards; a move that lights fires so
   Rain dousing is visible in play.
5. Art gaps: faint outline around water/lava cells (height step), basalt/magma/ice
   meshes not restyled, camera can't rotate (cutaway local fade assumes south-facing
   camera), steep one-cell stairs, no rendered unit portraits (crests use initials).
6. Old tests with pre-existing parse errors (`test_board_integration`,
   `test_game_events`, `test_pathfinding_performance`) should be fixed or deleted.
7. Unit roles on squad cards ("Striker", "Caster") are derived from stats — add a real
   `role` field to `CharacterResource` if roles matter.

See the section below for the final work item's status (combat text + Compendium).
