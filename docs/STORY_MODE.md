# Story mode — overworld M1 (vertical slice)

Design: `docs/design/OVERWORLD.md` (owner decisions in `docs/design/DECISIONS.md` win).
This file records what M1 actually built, how to play it, and the merge contract with
`feat/evolution` and `feat/duel`.

## How to play the slice

Solo → **Story** (card 6) → an empty slot → **Oakvale**.

1. Arrows / WASD / d-pad / sticks step one cell (tap a new direction = turn; hold = walk;
   Shift / R3 = run). Click / tap a cell to walk there; tap a person to walk up and talk.
2. Confirm (Space / Enter / A) reads the **sign**, talks to **Maren** / **Tobin**, opens the
   **mill chest** (poultice + 30 gold; stays open after reload).
3. **Elder Wynn** (north of the plaza) asks a **choice** — "I will walk it." sets
   `quest.blight_road`, gives the Heartwood Charm, toasts the quest, and **Gate Warden Hale walks
   aside** (a persisted move). "Not yet." changes nothing.
4. The fountain **Wayshrine** heals, sets the respawn point and saves.
5. The east edge warps to **Route 1 — the Mossway**. Tall grass rolls deterministic wild
   encounters → the **debug duel stub** (Win / Win (befriend) / Lose / Flee). A win may offer
   "X wants to join you!" → Welcome it / Not now.
6. **Bram** watches the road: step into his line → "!" → he walks up → VS clash → tactical battle
   on `ow_mossway_clearing` with your party (carried HP, story-bag items) → **Continue Journey**
   (+120 gold, defeated flag, back where you stood) or **Return to Wayshrine** on a loss.
7. The **Lone Petalfang** in the meadow is a non-missable story recruit (duel; stays until it joins).
8. Esc / Start → Journey menu (Resume · Party · Save · Title). Main menu → **Continue Journey**.

## Where things live

| Piece | Files |
|---|---|
| Autoload (session, runner, battle round trip) | `game/overworld/StoryController.gd` |
| Data | `game/overworld/data/` — `OverworldAreaResource`, entity kinds (`Npc`, `Trainer`, `Sign`, `Chest`, `Warp`, `Wayshrine`, `TriggerZone`, `Prop`), `EncounterZone/Entry`, `BattleSpec`, `HeroResource`, `StoryRuleset` |
| Scripts | `game/overworld/script/` — `StoryCommand` + `commands/*`, `StoryScriptRunner`, `ScriptContext`, `StoryScriptHost` (the host contract), `ConditionContext` |
| Runtime | `game/overworld/runtime/` — `OverworldController` (scene root + live host), `OverworldGrid`, `TrainerSight`, `EncounterRoller`, `TapPathfinder`, `OverworldActor`, `OverworldCamera`, `OverworldProps` |
| Battles | `game/overworld/battle/` — `BattleRequest`, `BattleResult`, `StoryBattleBridge`, `StoryResultApplier`, `DuelLauncher`, `DuelStub` |
| Saves | `game/overworld/save/` — `StoryState`, `StoryPartyMember`, `StorySnapshot`, `StorySaveManager` (`user://story/slot_<n>.json`) |
| UI | `game/overworld/ui/` — `OverworldHUD`, `JourneyMenu`, `StoryStartScreen` |
| Content | `game/overworld/content/` — built by `game/overworld/build/build_story_content.gd` |

Shared-file hooks (all guarded, no-ops outside story): `GameEvents.battle_resolved`,
`GameWorldManager` (`prepare_battle_board` call + the `battle_resolved` emit),
`GameOverScreen` (mode end actions via group `battle_mode_controller`),
`StoryDialogue.play_choice`, `ItemSystem` (story loadout + no drop), `BattleSaveManager.gate`
(`story_active`), `SoloModeSelect` (card 6), `MainMenu` (Continue Journey row).

## Merge notes

**feat/evolution.** EVOLUTION's `RosterLedger` is not on this branch; the party stores
`StoryPartyMember`, a record shaped to merge into it: `member_id` = the RosterLedger uid (same
`"<line>"`, `"<line>#2"` scheme), `line`, `character_id` = the current form, `nickname`, plus the
story-only `current_hp` / `wounded` / `item_id`, and an opaque `growth` dictionary that
round-trips RosterLedger's growth/evolved payload untouched. The overworld never writes
`growth`. Hooks still to wire at merge: `EvolutionService/RosterLedger.available_evolutions`
after `StoryController._conclude`, and `story_flags()` for `StoryFlagTrigger`.

**feat/duel.** Register the real launcher with `DuelLauncher.register(callable)` (a real
launcher always replaces the debug stub; registration order does not matter). The duel must call
`StoryController.report_battle_result(result)` exactly once and never change scene; the stub is
the reference implementation (`DuelStub.build_result`). Contract details the stub fixes:
`befriend_offer` is rolled on VICTORY off `request.seed` (`EncounterRoller.befriend_offered`,
never `randf()`); a `rules.story_critical` recruit ALWAYS offers on a win; the bench keeps its HP.
If feat/duel also stubbed `BattleRequest` / `BattleResult` / `DuelLauncher`, keep these (the
class names would collide).

## Deviations from OVERWORLD.md (M1)

- Hero = a dedicated `HeroResource` (DECISIONS.md #4) with Vineweave's model as the placeholder.
- The squad for a story tactical battle is the first `squad_size` healthy members in party order
  (no CharacterSelect story branch — the M1 party never exceeds the squad).
- The Story card is appended as card 6 (existing number keys unchanged).
- The Wayshrine stands on a sacred-ground basin (the plain fountain tile has no geometry).
- Placeholder houses get procedural roofs (`PropEntity`), people are procedural figures.
- Journey menu ships Resume / Party / Save / Title only; `pending` script resume across an app
  restart is M3 (the pre-battle autosave puts you in front of the trainer instead).
