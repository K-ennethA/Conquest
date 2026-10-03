# OVERWORLD — Story mode: walk the world, meet people, trigger battles

Design doc for the story-mode overworld and its encounter triggers (feature asks 2 + 3's
launch side). Written against `reconcile/cloud-merge` (`Conquest-reconcile`). Paths are
repo-relative. Companion docs: **EVOLUTION.md** (unit evolutions) and **DUEL.md** (1v1
turn-based battle) — the interfaces this doc expects from them are in §7.

**TL;DR.** Story mode is a **grid-locked 3D overworld built from the same tiles, shaders and
lighting as the battle board**, one small area per scene (towns, routes, interiors) joined by
warps. Area terrain is an ordinary **`MapResource`** painted in the existing Map Maker; everything
that lives on it (NPCs, signs, chests, doors, trainers, grass encounter zones) is a new
**`OverworldAreaResource`** that points at that map. Interactions run tiny **command scripts**
(`Say`, `Choice`, `SetFlag`, `StartBattle`, …) composed in the Inspector like `MoveEffect`s,
with dialogue rendered by the existing **`StoryDialogue`** overlay. A new **`StoryController`**
autoload (same shape as `CampaignController` / `ArenaController`) owns the story save, the
persistent party, and the **battle round trip**: it hands a `BattleRequest` to either the
existing tactical battle or the new duel, receives a `BattleResult`, applies it, and walks you
back onto the map where you stood.

---

## 1. What exists today (build on it, don't break it)

| System | Files | What the overworld takes from it |
|---|---|---|
| Map data | `game/maps/resources/MapResource.gd` | Area terrain = a `MapResource`: `tile_layout` (floors, stairs), `links`, `lighting_preset`, `environment_preset`, `weather*`. `MAX_MAP_SIZE = 40`. |
| Map loading | `game/maps/MapLoader.gd` (`load_map`, `_load_tiles`, `_build_world_dressing`, `get_available_maps`) | Builds tile nodes (`Tiles/Floor_f/Tile_x_y_f`), the painterly `WorldSkirt`, `TerrainMask`. `get_available_maps` only scans `res://game/maps/resources/` → overworld terrain stored elsewhere never leaks into map pickers. |
| Tiles | `game/tiles/resources/**` (`TileResource`: `is_passable`, `base_movement_cost`, `blocks_line_of_sight`, `step_sound`) | Walkability, trainer sight blocking, footstep audio. **`forest/tall_grass`** (encounter grass) and **`common/fountain`** (heal spot) already exist; `structures/flagstones`, `structures/wooden_planks` for towns. |
| World art | `game/visuals/world/WorldLook.gd`, `WorldSkirt.gd`, `TerrainMask.gd`, `tile_objects/tiles/lowpoly/TreeBuilder.gd`, `game/maps/FloorDecor.gd`, `ProcMesh` | Same sky/sun/fog/grade (`WorldLook.apply_preset`), canopy see-through (`focus_world` uniform), skirt landscape, procedural props. All procedural, no textures — the overworld stays that way. |
| Story dialogue | `game/ui/story/StoryBeat.gd`, `StoryScene.gd`, `StorySequencer.gd` (pure), `StoryDialogue.gd` (CanvasLayer 135, modal, injectable clock, portraits via `PortraitCache`, monogram fallback) | All overworld talk. A beat with `speaker_name` + unknown `speaker_id` already renders a villager with a monogram crest. **Missing: choices** (§4.4). |
| Campaign | `game/campaign/CampaignController.gd` (autoload), `CampaignData.gd` (4 chapters), `game/campaign/story/*.tres`, `menus/CampaignScreen.gd` | Staging pattern (`prepare → begin → CharacterSelect → GameWorld → capture`), `play_story`, intro/outro seam in `GameWorldManager._play_campaign_intro`. Progress in `user://campaign.json`. Must keep working unchanged. |
| Mode controllers | `game/arena/ArenaController.gd`, `ArenaRoundBuilder.gd`, `ArenaUnitState.gd` (`carried_hp`), `ArenaRuleset.HealPolicy.CARRY_DAMAGE` | **The template for the story battle bridge**: autoload owns state across scene loads; `GameWorldManager._setup_local_game` builds actors from it; `_evaluate_game_end` hands the outcome back instead of the normal flow. |
| Battle boot/end | `game/world/GameWorldManager.gd` (`_setup_local_game`, `_evaluate_game_end`, `_play_versus_intro`), `game/ui/screens/GameOverScreen.gd` (Rematch / Main Menu / Quit; mode controller lookup `_mode_controller()`), `game/ui/screens/VersusIntro.gd` (Pokémon-style clash, `should_show(ctx)`) | Where a story battle plugs in (§4.6). No "battle ended" signal exists today. |
| Squad → board | `MapLoader._load_units` fills player-0 `Start` slots from `GameSettings.selected_squad`; `spawn_unit_now` | Story fields party members exactly this way. |
| Saves | `systems/save/BattleSaveManager.gd` (one slot, static staging, close-window save, `gate()`), `BattleSnapshot.gd` (versioned JSON, ids not paths, "store inputs, not results"), `game/items/ItemInventory.gd` (static store + `set_save_path`), `game/profile/PlayerProfile.gd` (points, `notify_mode_win`, `_detect_live_mode`) | Patterns for `StorySnapshot` / `StorySaveManager`; story battles must be excluded from (or taught to) the mid-battle save gate. |
| Items | `game/items/ItemResource.gd` (UNIT/TEAM **equipment**, passive stat mods — no consumables), `ItemLibrary`, `ItemSystem.loadout_for_slot` (reads `ItemInventory` by character id) | Shop stock + chest loot use the same `ItemResource`s. Needs a loadout-source seam for a story bag (§4.8). |
| Characters | `game/characters/CharacterResource.gd` (`model_scene`, `model_yaw_deg`, `model_scale`), `CharacterLibrary`, roster `game/characters/roster/*.tres` | Player avatar + NPC models. Blender models with `idle`/`walk` clips animate via `UnitAnimator` clip lookup (`CLIP_IDLE`, `CLIP_WALK`). **No XP/level system exists.** |
| Facing | `game/visuals/UnitFacing.gd` | 4-way facing math for avatar/NPCs (visual only, same convention: +Z = south). |
| Camera | `game/visuals/CameraController.gd` (fixed ~50° tilt, dolly zoom, `pan_by_screen_delta`, `zoom_by`, board fit) | Tilt/FOV match; touch adapter calls `pan_by_screen_delta` / `zoom_by` duck-typed. |
| Input | `game/ui/input/InputActions.gd` (+ `project.godot [input]`), `game/input/TouchInputAdapter.gd`, `GestureClassifier.gd`, `game/mobile/MobileDisplay.gd` | `cursor_*` (arrows / d-pad / stick), `camera_pan_*` (WASD / right stick), `confirm`, `cancel`, `map_menu`, `unit_info`, `fast_forward` (Shift / R3 hold). Tap == click (mouse emulation on). |
| Menus | `menus/MainMenu.gd` (Resume Battle row), `menus/SoloModeSelect.gd` (5 cards: Campaign, Skirmish, Siege, Arena, Challenges), `menus/CharacterSelect.gd` (squad pick; campaign/challenge/arena branches), `game/ui/theme/*` (`MenuTheme`, `MenuKit`, `MenuNav`, `OrnateStyleBox`) | Story entry + every new screen uses the grove kit (docs/UI_STYLE.md). |
| Transitions | `systems/SceneFade.gd` (`SceneFade.change_scene(from, path)`, auto fade-in) | Area warps and battle hand-offs. |
| Replays | `ReplayPlayback.is_playing()`; `CampaignController.story_suppressed()` | Story battles record like any solo battle; story overlays never play in replays (already true). |

**Must not break:** campaign chapters + `user://campaign.json`; `BattleSaveManager` resume;
`ItemInventory` / profile economy; map pickers (overworld terrain must not appear in Skirmish);
the `GameWorldManager` boot order (intro seams, replay phases, resume phases); CONQUEST.md rules
1 (no `push_error` for expected failures), 3 (JSON arrays), 7 (duplicate shared resources),
8 (never `ResourceLoader` untrusted data), 11 (mode knobs on a ruleset).

---

## 2. The player-facing experience

### What it feels like
You press **Solo → Story → New Journey**. The screen fades in on **Oakvale**, a village of
flagstones and timber at the edge of the Forgotten Forest, lit and painted exactly like the
battle boards. You are **Vineweave** (your lead party member), standing at the fountain. Arrows /
WASD / d-pad / stick step you **one cell at a time** (hold to keep walking, Shift / R3 to run);
tap a cell on a phone and you walk there. The camera sits at the battle camera's angle, a little
closer, and glides after you; trees between you and the camera dither away like they do over the
battle cursor.

Walk up to a signpost and press **Confirm**: the grove text box types "OAKVALE — where the
Mossway begins." Talk to the Elder: two portraits slide in, she asks you to walk the Mossway,
and a **choice** appears (Yes / Not yet). Say yes: a flag is set, the guard at the east gate
steps aside, and a gold ribbon announces **Quest: The Blighted Road**. A chest by the mill gives
you a *Sagebloom Poultice*. The fountain is a **Wayshrine**: touch it to heal the party and save.

East of town is **Route 1 — the Mossway**. Tall grass rustles as you wade through; after a few
steps the screen cracks and a wild **Petalfang** leaps out — a **duel** (1v1, turn-based, no
movement) against your lead unit. Further on, **Bram the Warden-apprentice** spots you: a "!"
pops over his head, he marches up, says his line, the **VS clash** plays, and you are dropped
into a **tactical battle** on a small woodland board with the squad you pick from your party.
Win, and you are back on the Mossway exactly where you stood, facing Bram, who now says his
defeated line; you got 120 gold and a flag that means he never challenges you again. Lose, and
you wake at the last Wayshrine with your party healed.

Esc / Start opens the **journey menu**: Party, Bag, Quests, Map, Save, Settings, Title.

### Walkthrough of the vertical slice (M1)
1. Solo → **Story** card → Story screen → *New Journey* (slot 1).
2. Oakvale: read the town sign; talk to 2 villagers; Elder conversation with a choice.
3. Open the chest (item added, chest stays open after reload).
4. Guard blocks the east exit until the Elder's flag is set; then walks aside (scripted move).
5. Touch the Wayshrine fountain (heal + save).
6. Walk into Route 1 (edge warp, fade). Walk the tall grass → duel hook fires (stub result in M1).
7. Bram sees you (line of sight) → dialogue → tactical battle `ow_mossway_clearing.tres` → win →
   back on the route, rewards applied, Bram's defeated flag set. Lose → Wayshrine.
8. Journey menu → Save → Title → Solo → Story → *Continue* → back on the Mossway.

---

## 3. Options and recommendations

### 3.1 Perspective / art direction

| | (a) Grid-locked 3D on the tile system **(recommended)** | (b) Free-movement 3D | (c) Separate 2D tilemap |
|---|---|---|---|
| Look | Identical to battles: painterly ground, `TreeBuilder` trees, `WorldSkirt`, `WorldLook` | Same assets, but needs collision + navmesh around every prop | Totally different look; zero 2D art exists (project is 100% procedural 3D) |
| Authoring | **Map Maker already paints it** (tiles, floors, stairs, bridges) | New collision/level tooling | Godot TileMap editor (good) but all-new tilesets |
| Encounters / sight | Trivial on cells (grass = tile id, sight = cells in a line) | Fuzzy volumes, raycasts | Trivial |
| Touch | Tap-to-walk via grid A* (fits "tap == click") | Needs a virtual stick | Tap-to-walk |
| Battle transition | Same ground type → "battle where you stand" possible later (§4.6) | Same | Jarring 2D → 3D cut |
| Cost | Lowest: new = entities, mover, camera follow | High | High (art) |

**Grid-locked vs free:** grid-locked logic with **smooth visual interpolation** (Pokémon Gen 3–5):
the logical position is always a `Vector3i` cell; the model tweens between cells (~0.22 s walk,
~0.12 s run) and turns via `UnitFacing` (a tap on a new direction turns in place first). Every
rule (collision, sight, triggers, grass) stays a pure cell function — testable headless.

### 3.2 Area data: reuse `MapResource`, or a new resource?

| Option | Verdict |
|---|---|
| Put NPCs/warps inside `MapResource` (new exported fields) | **No.** `MapResource` is also the community/JSON interchange format guarded by the hardened importers (rule 8); story data (scripts referencing `.tres`) has no business there, and it would bloat every battle map. |
| **Terrain = `MapResource`, entities = new `OverworldAreaResource` that references it** | **Yes.** Terrain painted in the Map Maker, unchanged; the area file holds everything story-specific. Terrain `.tres` lives under `game/overworld/content/areas/<id>/`, so `MapLoader.get_available_maps` never lists it. |
| Fully new overworld terrain format | No — would duplicate tiles, floors, skirt, mask. |

### 3.3 Camera

**New small `OverworldCamera.gd` (Camera3D)** — same pitch/FOV as `GameWorld.tscn`'s camera,
closer default distance (~16 vs ~20+), follows the avatar with an eased dead-zone, clamps to the
area rect (plus the skirt margin), no rotation (the canopy-dither and future cutaway assume a
south-facing camera). It implements `zoom_by(factor, screen_pos)` (clamped band) and a no-op-ish
`pan_by_screen_delta` (temporary look-ahead that springs back) so `TouchInputAdapter` pinch/drag
work with zero adapter changes. Reusing `CameraController` directly was considered and rejected:
90 % of it is board fit, HUD avoidance and cursor follow.

### 3.4 Relationship to the existing Campaign

| Option | Trade-off |
|---|---|
| Replace Campaign | Breaks a finished, tested mode; loses "just fight the story battles" quick play. |
| Coexist, unrelated | Two stories about the same forest that never meet. |
| **Coexist now, fold the chapters into the story spine (recommended)** | Story mode's main quest *is* the Forgotten Forest arc: each chapter becomes a scripted `StartBattle` (`campaign_chapter = "ch1_blighted_clearing"`) at a place on the map (the Blighted Clearing at the end of the Mossway, …), reusing its map, difficulty, intro and outro scenes. Clearing it in story also marks the chapter cleared in `campaign.json` (one write path: `CampaignController.mark_cleared`). The Campaign card stays as "chapter replay / battle-only". |

### 3.5 Dialogue & script authoring format

| Option | Trade-off |
|---|---|
| **Typed command resources (`StoryCommand` subclasses) in `.tres` (recommended runtime)** | Same philosophy as `MoveEffect`: compose in the Inspector, add behavior with one small subclass, `_to_string()` rows read "Say: Elder (3 lines)", "Set quest.blight_road = 1". Testable, validates at load. Verbose to hand-write. |
| Text DSL (Yarn-ish) | Fastest for lots of chatter; needs a parser + error reporting. |
| Third-party addon (Dialogic) | Big dependency, its own UI that fights the grove look, own save format. |

**Recommendation:** commands are the runtime model. M1 content is authored with **builder
scripts** (`build_oakvale.gd`, same practice as `game/maps/build_riftwood.gd`) that construct and
save the `.tres`. M3 adds a **text-DSL importer** that compiles to the same commands, for when
NPC chatter volume makes the Inspector painful (§6).

---

## 4. Proposed design — systems

### 4.1 Folder layout
```
game/overworld/
  StoryController.gd          autoload: session, party, battle round trip, saves
  OverworldScene.tscn / .gd   the walkable scene (one per area load)
  data/        OverworldAreaResource, OverworldEntity (+ kinds), EntryPoint, EncounterZone,
               EncounterEntry, BattleSpec, ShopResource, QuestResource, WorldRegionResource
  script/      StoryCommand (+ commands), StoryScriptRunner, ScriptHost (interface), Conditions
  runtime/     OverworldGrid, GridMover, PlayerAvatar, EntityActor, TrainerSight,
               EncounterRoller, InteractionResolver, TapPathfinder
  battle/      BattleRequest, BattleResult, StoryBattleBridge (tactical), DuelLauncher (seam)
  save/        StoryState, StorySnapshot, StorySaveManager
  ui/          OverworldHUD, JourneyMenu, PartyScreen, BagScreen, ShopScreen, QuestLog,
               WorldMapScreen, StoryStartScreen, ChoiceList (StoryDialogue extension)
  content/areas/<area_id>/terrain.tres, area.tres, scripts/*.tres
  content/battles/*.tres  (tactical battle maps for story, MapResource, status Inactive)
  content/quests/*.tres, content/shops/*.tres, content/world.tres
  build/       build_oakvale.gd, build_mossway.gd ... (content builders)
```

### 4.2 Data model

**`OverworldAreaResource`** (`game/overworld/data/OverworldAreaResource.gd`)

| Field | Type | Notes |
|---|---|---|
| `area_id` | StringName | stable key (saves, flags, warps) |
| `display_name` | String | "Oakvale", shown in the area ribbon |
| `terrain` | MapResource | the painted board (Map Maker) |
| `kind` | enum TOWN / ROUTE / INTERIOR / DUNGEON | HUD / music / map icon; interiors skip the skirt |
| `region_id`, `world_map_pos` | StringName, Vector2 | world map screen (§4.9) |
| `entry_points` | Dictionary `{id: {cell:[c,r,f], facing:"south"}}` | named arrivals for warps; read through a coercion helper (rule 3) |
| `entities` | `Array[Resource]` (OverworldEntity) | Resource-typed like `StoryScene.beats` (plain `.tres` literal; filtered at read) |
| `encounter_zones` | `Array[Resource]` (EncounterZone) | |
| `on_enter` | `Array[Resource]` (commands) | first-visit cutscenes etc., each guarded by conditions |
| `music_cue`, `lighting_preset_override`, `weather_override` | | fall back to the terrain's |

**`OverworldEntity`** base (`id`, `cell: Vector3i`, `facing`, `visual` (a `CharacterResource`,
a prop scene, or none), `blocking: bool`, `visible_if: String`, `on_interact: Array[Resource]`,
`on_step: Array[Resource]`) and kinds that pre-fill behavior:

| Kind | Adds | Auto flag |
|---|---|---|
| `NpcEntity` | `speaker_id` / `speaker_name`, `wander` (none / pace / look-around, deterministic), `dialogue` shortcut (a `StoryScene`) | — |
| `TrainerEntity` (extends Npc) | `sight_range` (default 4), `battle: BattleSpec`, `pre_scene`, `defeated_scene`, `rematchable` | `trainer.<area>.<id>.defeated` |
| `SignEntity` | `text` | — |
| `ChestEntity` | `loot` (item ids / gold), closed/open prop | `<area>.<id>.opened` |
| `WarpEntity` | `cells: Rect2i` (a door or a whole map edge), `target_area`, `target_entry`, `preserve_axis` (edge exits keep your row/column), `requires: String` (condition), `locked_scene` | — |
| `WayshrineEntity` | heal party, save, set respawn point, fast-travel node (M3) | `wayshrine.<area>.<id>.lit` |
| `SwitchEntity` | toggles a flag; other entities read it via `visible_if` / `blocking_if` (gates, bridges, raised roots) | `<area>.<id>.on` |
| `ShopEntity` (extends Npc) | `shop: ShopResource` | — |
| `TriggerZone` | `cells: Rect2i`, `once: bool`, invisible, runs `on_step` | `<area>.<id>.fired` |
| `EncounterNest` (M2) | visible blight nest → tactical battle, disappears when cleared | `<area>.<id>.cleared` |

**`EncounterZone`**: `cells: Rect2i` (empty = whole area) **and/or** `tile_ids: Array[StringName]`
(e.g. `[&"tall_grass"]` — the grass *is* the zone, no double authoring), `rate` (per step, e.g.
0.08), `grace_steps` (3), `table: Array[Resource]` of **`EncounterEntry`** {`character_id`,
`weight`, `kind: DUEL|TACTICAL`, `strength` (stat scale / level — see §7.1), `condition`,
`battle` (optional `BattleSpec` for TACTICAL)}.

**`BattleSpec`** (authored; turned into a runtime `BattleRequest`):
`kind: TACTICAL|DUEL`, `encounter_id`, `map` (MapResource, tactical) or `campaign_chapter`
(String; reuses `CampaignData`), `squad_size`, `ai_difficulty`, `opponent_name`, `opponent_team`
(duel: array of {character_id, strength, moves?}), `intro_scene` / `outro_scene`, `rewards`
{gold, items, points, flags}, `defeat_policy: WHITEOUT|CONTINUE|RETRY`, `can_flee`, `clash_intro`
(bool: play `VersusIntro`).

**`QuestResource`**: `quest_id`, `title`, `stages: Array[{value:int, text:String}]`, driven by
ONE int flag `quest.<id>` — the quest log is a **view over flags**, not a second state engine.

**`ShopResource`**: `stock: Array[{item_id, price, condition}]`, `buyback_ratio`.

**Conditions** are short strings evaluated with Godot's built-in **`Expression`** against a
restricted proxy (`ConditionContext`) exposing only `flag(key)`, `has(key)`, `party_has(char_id)`,
`item(id)`, `gold()`: e.g. `flag("quest.blight_road") >= 1 and not has("oakvale.guard.moved")`.
Zero parser to write; a content test parses every condition in every area so typos fail CI, not
playtests. (Content is shipped/trusted; if story content ever becomes shareable, rule 8 applies
and this must move to a whitelisted mini-grammar.)

### 4.3 Runtime flow — the walkable scene

`OverworldScene.tscn`: `WorldEnvironment`, `Camera3D` (`OverworldCamera`), `Map` (Node3D +
`Tiles`), `Entities`, `Player`, `UI` CanvasLayer (`OverworldHUD`), root script
`OverworldController`.

Boot (`OverworldController._ready`):
1. Ask `StoryController` for the area id + arrival (entry id, or saved cell + facing).
2. `MapLoader.new().load_map(area.terrain, $Map)` — tiles, skirt, mask; terrain has no
   `unit_spawns`, so no units spawn. `WorldLook` created exactly as `_setup_lighting` does, then
   `apply_preset(terrain.lighting_preset)`; weather visuals optional (M4).
3. `OverworldGrid.build(area, state)`: per-cell walkability from `TileResource.is_passable`
   (floors + `links` supported in the data; M1 uses floor 0), then blocking entities that are
   visible under the current flags.
4. Spawn `EntityActor`s (models from `CharacterResource.model_scene`, scaled/yawed by its
   fields; `idle`/`walk` clips when present) and the `PlayerAvatar` (lead party member's model).
5. Run `on_enter` commands whose conditions hold; show the area-name ribbon; fire `music_cue`.

Per frame: if a script is running or `InputActions.gameplay_input_blocked()` → no input. Else
read the held direction (`cursor_*` **or** `camera_pan_*`, so arrows, WASD, d-pad and both
sticks all walk) → `GridMover.try_step(dir)`:
- new direction and not moving → turn in place (a tap turns; a hold walks);
- target cell passable and unoccupied → tween step; **on arrival**: warps → trigger zones →
  trainer sight (every visible undefeated trainer) → encounter roll (only if nothing above fired).
- `confirm` → `InteractionResolver` finds the entity in the faced cell (counter tiles extend
  reach one cell, Pokémon shop-counter style) → runs its `on_interact`.
- `map_menu` → Journey menu. `fast_forward` held → run.

**Touch:** a tap on a cell → `TapPathfinder` (Godot `AStarGrid2D` over `OverworldGrid`; M2
generalises to floors via `AStar3D` over `links`) → queued steps (stop if a trigger fires). Tap on
an NPC/object → path to the nearest adjacent cell, face, interact. A small grove "A" button and a
"Menu" button appear bottom-right on touch devices (`MobileDisplay`). The existing
double-fire caveat (docs/MOBILE_PLAN.md §2) applies unchanged.

**Warps / loading:** one area per scene load, no streaming in v1. A warp writes the target to
`StoryController`, autosaves, and `SceneFade.change_scene(self, OVERWORLD_SCENE)`; the next boot
reads it. Areas are kept ≤ ~32×32 cells (towns ~24×20, routes ~14×40) because every cell is a tile
node; that is the same order as Riftwood (35×35) battles. Adjacent-area prefetch with
`ResourceLoader.load_threaded_request` is an M4 optimisation if loads feel slow on mobile.

### 4.4 Interaction system — scripts, dialogue, choices, cutscenes

**`StoryCommand`** (Resource, `func run(ctx: ScriptContext) -> void`, may `await`). Commands (M1 ★):

| Command | Does |
|---|---|
| ★ `Say` | plays a `StoryScene` or inline `StoryBeat`s through `StoryDialogue`; `speaker_from_actor` fills the NPC's name/id |
| ★ `Choice` | prompt + options `{label, condition, commands}`; runs the chosen branch |
| ★ `SetFlag` / `IncFlag` | writes `StoryState` |
| ★ `If` | `condition`, `then`, `else` command lists |
| ★ `GiveItem` / `GiveGold` / `TakeGold` | story bag / gold, with a toast (`ItemToast` look) |
| ★ `HealParty` | Wayshrine / healer |
| ★ `StartBattle` | builds a `BattleRequest` from a `BattleSpec`; continues **after** the battle with `ctx.last_result` available to later `If`s |
| ★ `StartDuel` | same, kind DUEL (via `DuelLauncher`, §7.2) |
| ★ `Warp` | scripted area change |
| ★ `MoveActor` / `FaceActor` / `Wait` | cutscene staging (actor = entity id or `player`) |
| `Emote` | "!", "?", "…" bubble over an actor (trainer spot) |
| `JoinParty` / `LeaveParty` | story recruitment |
| `OpenShop`, `SaveGame`, `SetQuestStage`, `PlaySfx`, `PlayMusic`, `CameraFocus` | M2 |
| `EvolveCheck` / `Evolve` | hands off to EVOLUTION (§7.1) |

**`StoryScriptRunner`** (pure `RefCounted`, like `StorySequencer`): walks a command list, holds
the "script running" lock, and talks to the world only through an injected **`ScriptHost`**
interface (`show_dialogue(scene) -> signal`, `show_choice(...)`, `move_actor(...)`,
`begin_battle(request)`, …). The live host is the `OverworldController`; tests pass a fake host
that completes instantly — the whole interaction layer is unit-testable with no scene tree.

**Dialogue:** `StoryDialogue` is reused as-is for portrait conversations; a sign or villager line
is a beat with `speaker_name` and `clear_portraits` (a Pokémon text box in the grove frame).
**Choices are the one extension:** add `StoryDialogue.play_choice(prompt: StoryBeat,
options: PackedStringArray) -> signal chosen(index)` — the prompt types out, then 2–4 option rows
(`MenuTheme.row_box`, gold leaf marker on focus, `MenuNav` focus, number keys, tap) appear above
the text box; cancel picks the last option if it is flagged `is_cancel`. The existing
"first tap completes, second advances" contract is untouched; `StorySequencer` is not modified.
Text substitution (`{lead}`, `{gold}`) happens in the runner before the beat is handed over.

**Cutscenes** are just scripts using `MoveActor` / `FaceActor` / `Wait` / `Say` / `CameraFocus`,
triggered by `on_enter`, a `TriggerZone`, or a battle result. Input is locked while the runner
holds the lock; `StoryDialogue`'s own skip skips dialogue, never the state changes.

### 4.5 Encounters

| Encounter | Trigger | Default battle | Result feeds |
|---|---|---|---|
| **Trainer / rival** | `TrainerSight`: after each player step (and on area entry) each undefeated, visible trainer checks the cells in a straight line along its facing, up to `sight_range`; blocked by a non-passable tile, a `blocks_line_of_sight` tile, or a blocking entity. Hit → `Emote "!"`, trainer `MoveActor`s to adjacent, `pre_scene`, `StartBattle`. Talking to a trainer from the side/behind also starts it. | Tactical (spec may say duel) | `trainer.*.defeated`, gold/items, `defeated_scene` on later talks |
| **Scripted story battle** | any script (`StartBattle`), incl. campaign chapters | Tactical | flags, quest stage, `outro_scene` |
| **Wild (grass)** | `EncounterRoller` on each completed step inside a zone | Duel | party HP; later: befriend (Q5) |
| **Nest** (M2) | visible `EncounterNest` entity | Tactical (small map) | cleared flag |

**Deterministic rolls:** `EncounterRoller.roll(save_seed, area_id, step_counter, zone)` is a pure
function over a hash (never `randf()`), so it is unit-testable and reloading a save does not
re-roll the next step. `grace_steps` after any battle/area entry. A Settings/Bag toggle to repel
encounters is M3.

**Return position:** the `BattleRequest` carries `return = {area_id, cell, facing}` captured the
moment the battle starts; the trainer's position after walking up is saved via flag-free state
(`StoryState.actor_positions` for moved actors, reset on area reload unless `persist_move`).

**Defeat handling** (`defeat_policy`): `WHITEOUT` (default for trainers/wild) → party healed,
warp to the last lit Wayshrine, "You retreat to the Oakvale Wayshrine…" (gold penalty: Q2);
`CONTINUE` (story battles you are allowed to lose — the script branches on `last_result`);
`RETRY` (boss battles: "Try again / Return to Wayshrine").

### 4.6 The tactical battle round trip

```
OverworldController ──StartBattle──▶ StoryController.begin_battle(request)
   autosave (pre-battle) · stage GameSettings (SINGLE_PLAYER, map, difficulty, player_count,
   selected_squad = fielded member character_ids) · arm _active_request
   ├─ squad pick: CharacterSelect in STORY branch (candidates = healthy party members,
   │  cap = squad_size; skipped when party size <= squad_size)
   ▼
GameWorld.tscn boot
   _setup_local_game: if StoryController.is_battle_active():
       StoryBattleBridge.prepare_board(map_loader, request)
         · tag each player-0 unit with meta story_member_id (spawn order = squad order)
         · set carried HP (after spawn, like BattleSnapshot's "HP last" rule)
         · story loadout for ItemSystem (see §4.8)
   _play_campaign_intro → story intro scene (same seam; StoryController stages it)
   _play_versus_intro  → VersusIntro when request.clash_intro (trainer battles)
   ...battle...
   _evaluate_game_end → GameEvents.battle_resolved(outcome, ctx)   ◀ NEW signal
   ▼
StoryController._on_battle_resolved
   · BattleResult from the board (member HP by meta, KOs, turns, defeated enemy ids)
   · outro scene on victory (existing play_story, deferred mount)
   · GameOverScreen shows with the story's action set: "Continue" (victory) /
     "Return to Wayshrine" + "Retry" (defeat)   ◀ NEW mode-controller hook
   ▼ Continue
StoryController.apply_result(result) → rewards, flags, party HP, evolution check (§7.1),
   autosave → change_scene(OVERWORLD_SCENE) → boot at request.return → the paused
   script resumes after its StartBattle (runner state kept on StoryController)
```

**GameWorldManager changes (small, additive, following the Arena precedent):**
1. `_setup_local_game`: one guarded call `StoryBattleBridge.prepare_board(...)` next to
   `ArenaRoundBuilder.build_round`.
2. `_evaluate_game_end`: emit **`GameEvents.battle_resolved(outcome: StringName, context:
   Dictionary)`** once, just before revealing the end screen (single-player path). Generic and
   useful beyond story (Campaign could later stop re-deriving its own verdict).
3. `GameOverScreen`: generalise `_mode_controller()` to also check a `battle_mode_controller`
   group, and honour an optional `end_actions(outcome) -> Array[{label, id}]` +
   `on_end_action(id)` on it. Story supplies Continue / Retry / Wayshrine; every other mode
   resolves to nothing and keeps Rematch / Main Menu / Quit.

**Guards:** `StoryController` arms capture only for the staged map path, exactly like
`CampaignController._is_capturing()`, so an unrelated later battle never records. Campaign
chapters launched from story are armed through **StoryController, not CampaignController**
(avoids double capture), and StoryController calls `CampaignController.mark_cleared` on a win.

**Mid-battle Save & Quit:** M1 excludes story battles in `BattleSaveManager.gate` (new
`story_active` argument, same shape as the Arena/Siege exclusions) — safe because the overworld
autosaved right before the battle, so quitting mid-battle resumes in front of the trainer. M3 adds
`BattleSnapshot.MODE_STORY` carrying the serialised `BattleRequest` and a
`StoryController.arm_for_resume(request)` (mirrors `CampaignController.arm_for_resume`).

**"Battle where you stand" (M3 option):** because the overworld *is* tiles,
`OverworldBattleCropper.crop(area.terrain, rect, spawn_plan) -> MapResource` can cut a 12×10 window
around the encounter and fight there — the ground, trees and river you were just walking on. It
goes through the existing custom-map path (`GameSettings.set_custom_map_json` + replay embedding),
so replays still work. Authored battle maps remain the default for designed fights.

### 4.7 Party (persistent story roster)

`StoryState.party: Array[PartyMember]` (ordered; index 0 = lead = your avatar). The overworld
needs only these fields; EVOLUTION owns the growth fields (§7.1):

| Field | Owner | Notes |
|---|---|---|
| `member_id` | overworld | stable unique id ("m_0001") — identity survives evolution |
| `character_id` | shared | current form; EVOLUTION rewrites it on evolve |
| `nickname` | overworld | optional; else `CharacterResource.display_name` |
| `current_hp` | overworld | `-1` = full (same sentinel idea as `ArenaUnitState.HP_FULL`) |
| `wounded` | overworld | KO'd last battle; cannot be fielded until healed (Q2) |
| `item_id` | overworld | equipped `ItemResource` (story bag) |
| `level`, `xp`, `form_history`, `bond`… | EVOLUTION | opaque to the overworld; stored under `member.growth` |

Active party cap 6; extras go to a **Grove** (storage) reachable at Wayshrines (M2). Squad for a
tactical battle = pick up to `squad_size` from healthy members (CharacterSelect story branch);
duel = the lead healthy member (switching per DUEL.md). New members join via `JoinParty`
(story) — recruitment from wild duels is Q5.

### 4.8 Economy: bag, gold, shops, healing

- **Story bag + gold live in the story save**, not in `ItemInventory` / profile points (Q4
  default). Item *definitions* are shared (`ItemLibrary`), so a chest can give any existing item.
- `ItemSystem.loadout_for_slot` gains one branch: while a story battle is active, player-0
  loadouts come from `StoryController.loadout_for_member(member_id)` (read via unit meta) instead
  of `ItemInventory`. The post-battle random drop (`ItemSystem.roll_drop` → `ItemInventory`) is
  suppressed in story battles; story loot is authored rewards.
- **Shops:** `ShopScreen` (grove two-column: stock option cards with rarity gem + price, your
  bag on the right; buy/sell, confirm dialog). **Built** (DECISIONS.md #28): consumables are an
  `ItemResource.consumable` (`ConsumableEffect`), shops a `ShopResource` + `ShopEntity` +
  `ShopScreen` -- see docs/STORY_MODE.md "Shops, consumables and gold".
- **Healing:** Wayshrine (fountain tile + shrine prop): full heal, clear `wounded`, save, set
  respawn. Healer NPCs = `HealParty` in a script.
- Story wins also call `PlayerProfile.notify_mode_win("story", {...})` so ranks/achievements
  count story play; `_detect_live_mode` returns `"story"` when `StoryController` is capturing.

### 4.9 World structure & world map

- **Region → areas.** `content/world.tres` (`WorldRegionResource`): region name, parchment
  layout, area nodes (id, `world_map_pos`, kind), and connections (derived from warps by a tool
  script, not hand-duplicated). **Built** as `WorldAtlas` / `WorldLocation`
  (`game/overworld/data/`): every place on the owner's map (`docs/design/world_map/`), BUILT or
  CLOSED (with its `world.*_open` flag), its region, map position and roads -- generated by
  build_story_content.gd; see docs/STORY_MODE.md "The world map, and the towns on it".
- **WorldMapScreen** (Journey → Map): an illuminated-parchment card (grove frame, gold routes,
  towns as crests, current area pulsing, unvisited areas dim). Fast travel between lit
  Wayshrines is M3.
- Slice-sized world plan for the first region (content, not code): Oakvale → Mossway → Blighted
  Clearing (ch1) → Thornwick (town 2) → Crossroads (ch2) → … → Heartwood (ch4, Eldroot).

### 4.10 UI screens (all grove kit, `docs/UI_STYLE.md`)

| Screen | Build from |
|---|---|
| Story start (slots: Continue / New Journey / Delete) | `MenuKit.build_page`, `option_card` per slot (area, play time, party crests) |
| Overworld HUD: area ribbon, interaction prompt ("[Space] Talk" via `InputActions.hint`), quest toast, touch A / Menu buttons | `ConquestTheme.title_ribbon`, `chip`, `HudSafeArea` rules |
| Journey menu (Party, Bag, Quests, Map, Save, Settings, Title) | `MapMenu` look (`row_box`, leaf marker) |
| Party screen (order, swap lead, equip, HP bars, wounded) | `ConquestTheme.unit_card_box`, `portrait` crests, existing unit detail page |
| Bag / Shop | `option_card`, `GroveGem`, `pill_box` prices |
| Quest log | cards per quest, stage text from `QuestResource` |
| Choice list | extension inside `StoryDialogue` |
| Battle result (story) | `GameOverScreen` with story actions + rewards section |

### 4.11 Save data

`StorySaveManager` (static store with `set_save_path`, like `ItemInventory`/`BattleSaveManager`),
3 slots `user://story/slot_<n>.json`; `StorySnapshot` is the pure serializer
(`FORMAT_VERSION`, ids not paths, unknown ids skipped not raised, `_normalize` on load).

```json
{
  "format_version": 1,
  "saved_at_utc": "2026-09-27T20:14:03", "play_seconds": 8123,
  "location": { "area_id": "mossway", "cell": [6, 21, 0], "facing": "north" },
  "respawn": { "area_id": "oakvale", "entry": "wayshrine" },
  "flags": { "quest.blight_road": 1, "oakvale.chest_mill.opened": true,
             "trainer.mossway.bram.defeated": true },
  "party": [ { "member_id": "m_0001", "character_id": "vineweave", "nickname": "",
               "current_hp": 41, "wounded": false, "item_id": "heartwood_charm",
               "growth": { } } ],
  "grove": [], "bag": { "sagebloom_poultice": 1 }, "gold": 220,
  "visited_areas": ["oakvale", "mossway"], "lit_wayshrines": ["oakvale.wayshrine"],
  "rng": { "seed": 918273645, "steps": 412 },
  "pending": { }
}
```
`pending` holds a battle in flight (its request + the script resume point) — used from M3.

**When it saves:** manual (Journey → Save, Wayshrines), **autosave** on every area change, right
before every battle, after every applied result, on `NOTIFICATION_WM_CLOSE_REQUEST` and on mobile
`NOTIFICATION_APPLICATION_PAUSED` (a phone app is killed without a close). Main menu gets a
"▶ Continue Journey — Mossway · 2h15m" row beside Resume Battle (same `_build_resume_entry`
pattern) when a slot exists.

### 4.12 Networking / replay / determinism

- The overworld is **offline single-player**; nothing touches `NetSession`. Story battles are
  `SINGLE_PLAYER`, so `NetGameRules`/commit-reveal are not involved.
- **Replays** of story battles record and play like any solo battle; story overlays are already
  suppressed in playback (`story_suppressed`). A cropped-map battle embeds its map (existing).
- **Determinism** where it matters for tests and fairness: encounter rolls, NPC wander patterns
  and shop stock are pure functions of `(save seed, area, counter)`; no `randf()` in overworld
  logic. The duel receives `request.seed` (DUEL.md decides how it uses it).

### 4.13 Testing strategy

| Layer | Tests (unit = no tree/disk; integration = real tree) |
|---|---|
| Data | `test_story_state_flags` (set/inc/has, conditions via `ConditionContext`), `test_overworld_area_resource` (entry points coercion, entity filtering, auto flag names) |
| Rules | `test_overworld_grid` (walkability from tiles + blocking entities + `visible_if`), `test_trainer_sight` (range, blocked by wall/LOS tile/entity, facing), `test_encounter_roller` (deterministic, grace steps, tile-id zones, weights), `test_tap_pathfinder` |
| Scripts | `test_story_script_runner` with a fake `ScriptHost`: Say/Choice/If/SetFlag/StartBattle resume with `last_result`; lock released on finish and on error |
| Battle bridge | `test_battle_request_codec` (round trip), `test_story_battle_result_apply` (HP, wounded, rewards, flags, whiteout), integration `test_story_tactical_round_trip` (stage → GameWorld boot → force victory → `battle_resolved` → result applied → return position) |
| Save | `test_story_snapshot` (round trip, version reject, unknown ids skipped), `test_story_save_manager` (temp path injection per tests/README) |
| Dialogue | `test_story_dialogue_choice` (auto_tick false; options appear only after reveal; keyboard/tap pick; cancel option) |
| Content | `test_overworld_content` — every area: terrain loads + validates, entity ids unique, warps target existing area+entry, conditions parse, referenced scenes/maps/characters/items exist, every `TrainerEntity` has a battle, each battle map validates (Compendium-completeness style) |
| Regression | existing campaign/save/replay suites stay green; `test_map_catalog`-style check that no overworld terrain appears in `get_available_maps()` |

---

## 5. Phased implementation plan

### M1 — Vertical slice: Oakvale + Mossway (smallest playable)

| # | Task | Files | Acceptance |
|---|---|---|---|
| 1 | **Story data core** | `data/OverworldAreaResource.gd`, `OverworldEntity.gd` + Npc/Trainer/Sign/Chest/Warp/Wayshrine/TriggerZone, `EncounterZone.gd`, `EncounterEntry.gd`, `BattleSpec.gd`; `save/StoryState.gd`; `script/ConditionContext.gd` | `_to_string` on every kind; auto-flag helpers; unit tests `test_story_state_flags`, `test_overworld_area_resource` pass |
| 2 | **Grid + movement + camera** | `runtime/OverworldGrid.gd`, `GridMover.gd`, `PlayerAvatar.gd`, `EntityActor.gd`, `TapPathfinder.gd`; `OverworldCamera.gd`; `OverworldScene.tscn/.gd` | loads an area via `MapLoader`, walks with arrows/WASD/pad, turn-in-place, run on `fast_forward`, collides with walls/NPCs, tap-to-walk; camera follows + pinch zoom; `test_overworld_grid`, `test_tap_pathfinder`, integration `test_overworld_walk` |
| 3 | **Script runner + commands + choices** | `script/StoryCommand.gd` + ★ commands, `StoryScriptRunner.gd`, `ScriptHost.gd`; `StoryDialogue.play_choice` | fake-host unit tests; `test_story_dialogue_choice`; existing `test_story_dialogue` / `test_story_sequencer` unchanged and green |
| 4 | **Interactables + HUD** | `runtime/InteractionResolver.gd`; `ui/OverworldHUD.gd` | sign/NPC/chest/wayshrine/warp/trigger all work; prompt chip shows live binding; chest stays open across reload |
| 5 | **StoryController + tactical bridge + trainers** | `StoryController.gd` (autoload in `project.godot`), `battle/BattleRequest.gd`, `BattleResult.gd`, `StoryBattleBridge.gd`, `runtime/TrainerSight.gd`; edits: `GameWorldManager` (2 hooks), `game_events.gd` (`battle_resolved`), `GameOverScreen` (mode actions), `BattleSaveManager.gate` (story exclusion), `CharacterSelect` (story branch), `ItemSystem.loadout_for_slot` + drop suppression | integration `test_story_tactical_round_trip`; `test_trainer_sight`; all existing suites green (campaign, arena, save/resume, replay) |
| 6 | **Duel hook** | `battle/DuelLauncher.gd` (interface + registry), `DuelStub.gd` (debug-build panel: Win/Lose/Flee), `runtime/EncounterRoller.gd` | grass rolls deterministically; `StartDuel` round-trips through the stub; swapping in the real DUEL launcher needs no overworld change; `test_encounter_roller`, `test_duel_launch_contract` |
| 7 | **Saves + entry points** | `save/StorySnapshot.gd`, `StorySaveManager.gd`; `ui/StoryStartScreen.gd`; `menus/SoloModeSelect.gd` (Story card first, hints renumbered); `menus/MainMenu.gd` (Continue Journey row) | New/Continue/autosave/close-save work; `test_story_snapshot`, `test_story_save_manager` |
| 8 | **Slice content** | `build/build_oakvale.gd`, `build_mossway.gd`, `content/areas/oakvale/*`, `content/areas/mossway/*`, `content/battles/ow_mossway_clearing.tres` (10×8, 3 P0 Start slots, P1 tree_grunt + petalfang ×2), dialogue `.tres` | walkthrough §2 plays end to end; `test_overworld_content` green |

Houses in M1 are placeholder stone-wall blocks with a "locked" door sign; real building props are M2.

### M2 — A journey, not a demo
Party screen + Grove storage, Bag, Shops, quest log + `QuestResource`, Journey menu, world map
screen, carried HP / wounded / whiteout polish, `EncounterNest`, NPC wander, building props
(`HouseBuilder.gd` procedural like `TreeBuilder`) + interiors, bridges/stairs (floors in
`OverworldGrid` + `AStar3D`), campaign ch1 folded in as the Mossway's end, PlayerProfile hooks,
EVOLUTION post-battle hook live, real DUEL launcher wired.

### M3 — Authoring & depth
**Map Maker "Story layer"** (§6), text-DSL dialogue importer, "battle where you stand" cropper,
story mid-battle save (`MODE_STORY`), Wayshrine fast travel, repel toggle, recruitment (Q5),
party followers trailing the avatar.

### M4 — Polish & scale
Day/dusk/night via `WorldLook` presets, per-area weather visuals, area music, cutscene camera
moves, adjacent-area prefetch, tile-mesh batching for big areas, on-device mobile profiling
(docs/MOBILE_PLAN.md checklist), consumable items if wanted.

---

## 6. Content authoring pipeline (solo dev)

| Step | Tool | Today / planned |
|---|---|---|
| Paint terrain | in-game **Map Maker** (`game/mapmaker/MapMakerScene.tscn`) → save as `MapResource` into `content/areas/<id>/terrain.tres` | today (add "Save as story area" target folder + status Inactive, M1 task 8) |
| Place entities, warps, zones | M1–M2: builder scripts / Inspector on `area.tres`. **M3: Map Maker "Story" tool group** — new `Tool` enum entries (NPC, SIGN, CHEST, WARP, TRIGGER, ENCOUNTER_ZONE) that write the sibling `OverworldAreaResource`; a side panel edits the selected entity's fields; entity markers drawn like spawns | planned |
| Validate | `MapMakerModel.validate()`-style list extended with story checks (warp targets, unreachable entities, trainers staring into walls, zone overlap); same checks as `test_overworld_content` | M3 |
| Write dialogue | M1: `StoryScene` `.tres` (the existing hand-authored format). M3: `.story` text files compiled by `StoryScriptImporter` into commands + beats | M1 / M3 |
| Playtest | Map Maker "Play from here": boots `OverworldScene` at the selected cell with a debug party | M3 |
| Battle maps | Map Maker as today, saved to `content/battles/` (never listed in Skirmish) | today |

DSL sketch (M3):
```
@area oakvale  @npc elder
elder: The Mossway is sick, child. The blight walks it at night.
? Will you walk it for us?
  - Yes:     set quest.blight_road = 1 ; elder: Then take this. ; give item sagebloom_poultice
  - Not yet: elder: Come back when your roots are steady.
```

---

## 7. Interfaces with the other two features

### 7.1 EVOLUTION (expected from EVOLUTION.md)
- **Member identity:** the story party stores per-member records keyed by `member_id`. If
  EVOLUTION defines its own roster-member type (e.g. a `RosterMember` with level/xp/form
  history), `PartyMember` *is* that type (or embeds it under `growth`) — one record, not two.
  Overworld guarantees: `member_id` never changes; it reads/writes only `character_id`,
  `current_hp`, `wounded`, `item_id`, `nickname`.
- **Evolution must:** keep `member_id`, nickname and equipped item; rewrite `character_id`; map
  HP by ratio (`current_hp / old max → new max`), so a wounded unit stays proportionally wounded.
- **Hooks the overworld calls:** `EvolutionService.pending_evolutions(party, ctx) -> Array[member_id]`
  after every applied `BattleResult` (ctx = `{trigger: "after_battle", area_id, tile_id,
  flags, defeated: [...]}`), on `Evolve`/`EvolveCheck` commands (ctx trigger `"script"`, e.g. at a
  sacred-meadow shrine) and on using an item (`"item"`, item_id). For each id it plays EVOLUTION's
  evolution scene over the overworld, then continues. Cancelling (Pokémon B-press) is EVOLUTION's call.
- **Strength scaling:** `EncounterEntry.strength` / duel `opponent_team[].strength` need a
  meaning; if EVOLUTION introduces levels, they are levels; otherwise a stat scale (1.0 = roster
  base). Overworld treats it as an opaque number passed to the battle.

### 7.2 DUEL (expected from DUEL.md)
The overworld never renders a duel; it hands over a request and waits for a result.

```
BattleRequest (RefCounted, JSON-serialisable via to_dict/from_dict)
  kind            "duel" | "tactical"
  encounter_id    String   stable ("mossway.grass.petalfang", "trainer.mossway.bram")
  source          "wild" | "trainer" | "script"
  seed            int      deterministic seed for the battle's RNG
  party           Array[{member_id, character_id, current_hp (-1 = full), item_id, growth}]
                  (ordered; duel uses the lead, switching per DUEL.md)
  opponent        {name, speaker_id, portrait, team: [{character_id, strength, moves?}]}
  backdrop        {area_id, tile_id, environment_preset, lighting_preset, weather}
  rules           {can_flee, can_befriend, defeat_policy}
  rewards         {gold, items, points, flags}        (applied by StoryController, not the duel)
  intro_scene / outro_scene   StoryScene paths (optional)
  -- tactical only: map_path | campaign_chapter, squad_size, ai_difficulty, clash_intro
  return          {area_id, cell, facing}             (filled by StoryController)

BattleResult
  encounter_id, outcome  "victory" | "defeat" | "fled" | "befriended" | "aborted"
  party_after     Array[{member_id, current_hp, wounded}]
  defeated        Array[character_id]     (xp / evolution input)
  befriended      character_id or ""
  turns           int
```

**Contract:**
1. `StoryController` calls `DuelLauncher.launch(request)`; the DUEL feature registers the real
   launcher (`DuelLauncher.register(callable)` at its autoload/_ready), which stages the request
   and changes scene to its duel scene. Until it exists, `DuelStub` is registered (debug builds).
2. The duel reads party stats from `CharacterLibrary` + `party[].character_id`, starts each
   member at `current_hp`, applies `ItemSystem` loadouts from the request (not `ItemInventory`),
   and uses `backdrop` to dress its 3D arena with the same `WorldLook` preset + ground shader
   (the grass you were standing in).
3. On end it calls **`StoryController.report_battle_result(result)` exactly once** and does not
   change scene itself; StoryController returns to the overworld. (A duel launched outside story
   — a quick-play mode — gets its own return target; not overworld's concern.)
4. The duel never writes the story save, gold, flags or inventory. Rewards, whiteout and
   evolution checks are StoryController's.
5. Same `BattleResult` shape is produced by `StoryBattleBridge` for tactical battles, so every
   downstream path (flags, HP, evolution, `If last_result`) is battle-kind agnostic.

---

## 8. Risks & notes
- **Tile-node cost:** every cell is still a small node subtree (~6 nodes; overworld tiles no longer
  carry collision); keep areas ≤ ~32×32 until tile batching (M4). Tile geometry, the skirt and the
  terrain mask are cached and neighbours prewarmed in the background — see STORY_MODE.md "Area
  travel & loading". Profile the skirt on mobile (already an open item in HANDOFF §3).
- **Autoload global state:** `MapLoader` registers tiles with `CombatServices`; the battle boot
  rebuilds it, but the overworld must call `CombatServices.clear()` on exit to leave no stale
  board for menus/tests (verify in task 2).
- **`GameWorldManager` is 1,742 lines with ordered boot phases** — the two story hooks must sit
  next to the Arena ones and be no-ops otherwise; the integration round-trip test is the guard.
- **Human world art:** the roster is forest creatures; villagers/houses/shrine props are new art
  (procedural first). Q1 decides how much.

---

## 9. Open questions for you (most important first; defaults in bold)

1. **Who walks the overworld?** **Default: your lead party unit (e.g. Vineweave), using its
   existing model and walk clip — no new character art.** Alternative: a new human "Warden"
   avatar with creature companions (Pokémon trainer framing; needs a Blender model and shifts the
   tone from "the creatures are the heroes" of the current campaign).
2. **Stakes between battles.** **Default: HP carries over; KO'd members are *wounded* until a
   Wayshrine; a loss sends you to the last Wayshrine healed, losing nothing but position.**
   Alternatives: full heal after every battle (simpler, FE-like), or Pokémon-style gold penalty
   on whiteout.
3. **Campaign relationship.** **Default: keep the Campaign card as chapter replay, and make the
   four Forgotten Forest chapters the story mode's main-quest battles (clearing one in story
   also clears it in Campaign).** Alternative: story is a separate tale, or story replaces Campaign.
4. **Economy.** **Default: story has its own gold + bag (balanced for the journey); item
   definitions are shared; story wins still earn profile points/achievements.** Alternative:
   share `ItemInventory` + profile points (your gacha/arena loot would power the story party).
5. **Recruitment.** **Default: v1 party grows only through story joins; "befriend after a wild
   duel" (Pokémon catching) is considered for M3.** Do you want collecting to be a core loop?
6. **Encounter feel.** **Default: random encounters in tall grass at a modest rate (≈1 per 12
   grass steps, 3-step grace) → duels; trainers → tactical; bosses → tactical; visible blight
   nests (M2) → tactical.** Alternative: no random battles at all — only visible/wandering
   encounters on the map.
