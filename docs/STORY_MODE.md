# Story mode — overworld M1 (vertical slice) + the evolution / duel wiring

Design: `docs/design/OVERWORLD.md` (owner decisions in `docs/design/DECISIONS.md` win).
This file records what M1 actually built, how to play it, and how it is wired to
`feat/evolution` (Growth, the Evolution screen) and `feat/duel` (the real 1v1 duel) — see
**Wiring** below.

## How to play the slice

Solo → **Story** (card 7) → an empty slot → **Oakvale**.

1. Arrows / WASD / d-pad / sticks step one cell (tap a new direction = turn; hold = walk;
   Shift / R3 = run). Click / tap a cell to walk there; tap a person to walk up and talk.
   Every step costs its walk / run time even with Animations off in Settings (the hero then
   snaps a cell per step instead of gliding; pinned by `test_overworld_key_walk`).
2. Confirm (Space / Enter / A) reads the **sign**, talks to **Maren** / **Tobin**, opens the
   **mill chest** (poultice + 30 gold; stays open after reload).
3. **Elder Wynn** (north of the plaza) asks a **choice** — "I will walk it." sets
   `quest.blight_road`, gives the Heartwood Charm, sends **Sprig** (a Barkling, Growth 2 of 3)
   along with you, toasts the quest, and **Gate Warden Hale walks aside** (a persisted move).
   "Not yet." changes nothing.
4. The fountain **Wayshrine** heals, sets the respawn point and saves.
5. The east edge warps to **Route 1 — the Mossway**. Tall grass rolls deterministic wild
   encounters → the **real duel** (`DuelStage`: your party lead with its carried HP vs one wild
   unit; **Flee** may fail and cost the turn). The results card's **Continue Journey** puts you
   back where you stood; a win may offer "X wants to join you!" → Welcome it / Not now. A loss
   whites out to the Wayshrine.
6. **Bram** watches the road: step into his line → "!" → he walks up → VS clash → tactical battle
   on `ow_mossway_clearing` with your party (carried HP, story-bag items) → the end screen shows
   the **Growth** each surviving member earns → **Continue Journey** (+120 gold, defeated flag,
   back where you stood) → **"Sprig is evolving..."** (Evolve / Not now: Sprig becomes an
   Oakheart for the rest of the journey, and Oakheart unlocks in Skirmish) — or **Return to
   Wayshrine** on a loss.
7. The **Lone Petalfang** in the meadow is a non-missable story recruit (duel; stays until it joins).
8. Esc / Start → Journey menu (Resume · Party · Save · Title). Main menu → **Continue Journey**.

## Where things live

| Piece | Files |
|---|---|
| Autoload (session, runner, battle round trip) | `game/overworld/StoryController.gd` |
| Data | `game/overworld/data/` — `OverworldAreaResource`, entity kinds (`Npc`, `Trainer`, `Sign`, `Chest`, `Warp`, `Wayshrine`, `TriggerZone`, `Prop`), `EncounterZone/Entry`, `BattleSpec`, `HeroResource`, `StoryRuleset` |
| Scripts | `game/overworld/script/` — `StoryCommand` + `commands/*`, `StoryScriptRunner`, `ScriptContext`, `StoryScriptHost` (the host contract), `ConditionContext` |
| Runtime | `game/overworld/runtime/` — `OverworldController` (scene root + live host), `OverworldGrid`, `TrainerSight`, `EncounterRoller`, `TapPathfinder`, `OverworldActor`, `OverworldCamera`, `OverworldProps` |
| Battles | `game/overworld/battle/` — `BattleRequest`, `BattleResult`, `StoryBattleBridge`, `StoryResultApplier`, `StoryGrowth` (story Growth + evolution rules), `DuelLauncher`, `DuelStub` (debug fallback) |
| Saves | `game/overworld/save/` — `StoryState`, `StoryPartyMember`, `StorySnapshot`, `StorySaveManager` (`user://story/slot_<n>.json`) |
| UI | `game/overworld/ui/` — `OverworldHUD`, `JourneyMenu`, `StoryStartScreen` |
| Content | `game/overworld/content/` — built by `game/overworld/build/build_story_content.gd` |

Shared-file hooks (all guarded, no-ops outside story): `GameEvents.battle_resolved`,
`GameWorldManager` (`prepare_battle_board` call + the `battle_resolved` emit),
`GameOverScreen` (mode end actions via group `battle_mode_controller`),
`StoryDialogue.play_choice`, `ItemSystem` (story loadout + no drop), `BattleSaveManager.gate`
(`story_active`), `SoloModeSelect` (card 7), `MainMenu` (Continue Journey row).

## Wiring (feat/evolution + feat/duel, merged)

### Story → the real duel
- `DuelController` (autoload) is THE registered story launcher:
  `register_story_launcher()` → `DuelLauncher.register(launch_from_story)`. The debug `DuelStub`
  stays only as a **fallback** (StoryController registers it as a stub, and a stub never replaces
  a real launcher), so it runs only when no real duel is present; its tests still cover it.
- `launch_from_story(BattleRequest)` → `DuelRequest.from_battle_request`: the fielded party
  (lead first, `character_id` = current form, `current_hp` carried, the story-bag item), the
  opponent team (a **wild** encounter is always **one** foe), the encounter `rules`
  (`can_flee`, `can_befriend`, `story_critical` — a missing key falls back to the kind's
  default: wild = may flee + may befriend) and the backdrop (an overworld tile / weather the duel
  does not know falls back to the stage's own instead of refusing the duel).
- The duel runs on `DuelStage` (strict 1v1: the lead fights, the bench keeps its HP). On a
  story duel the results card offers **Continue Journey**, and only that press calls
  `DuelController.finish` → `StoryController.report_battle_result(BattleResult)` — exactly once,
  and the duel never changes scene (StoryController walks back to the exact return cell).
- `DuelResult.to_battle_result()` carries `befriend_offer = {character_id, accepted}` **only when
  the seeded roll offered** (a declined roll is no offer). The roll is the duel's salted stream
  (`DuelBattle.befriend_rng`, never `randf()`); the subdue bonus applies; a `story_critical`
  recruit ALWAYS offers on a win. The offer reaches the story's `BefriendPromptCommand`
  ("X wants to join you!"); accepting adds the member.
- **Flee** is live for wild duels (`DuelRuleset.allow_flee` + the request's `can_flee`):
  `DuelBattle.attempt_flee()` rolls `DuelRuleset.flee_chance` from its own salted stream; success
  ends the duel as `fled` (no whiteout, HP carried, a story-critical recruit stays), failure
  spends the turn as a recorded WAIT.
- `party_after[]` rows now carry `fought` (false for the duel bench) and `kos`, so every result
  shape feeds Growth the same way.

### Party records — one source of truth
**Design choice: a `StoryPartyMember` IS the story-scoped view of a RosterLedger member record,
stored in the journey's own save slot.** The record shape and uid scheme are RosterLedger's
(`member_id` = uid `"<line>"`, `"<line>#2"`…; `line` = the evolution-line root; `character_id` =
RosterLedger `form`; `nickname`; `growth` = RosterLedger's `{growth, evolved}` payload), and every
evolution rule runs through RosterLedger's **record-level API** (`record_evolutions`,
`evolve_record`) via `StoryPartyMember.ledger_record()` / `apply_ledger_record()` — one record
type, one rule set. The global `user://roster.json` only receives the open-mode **unlock**.

Why not store story members inside `roster.json`: the open-mode implicit member of a line is
keyed by the bare line root (`"tree_grunt"`), exactly the uid a journey's first Barkling gets, so
they would collide; three save slots would share one ledger; and "Try Again" / reloading a slot
must rewind a journey's growth together with the rest of it. Keeping the record in the slot makes
the slot self-contained.

Save format: unchanged (`format_version` 1). An M1 save's `growth: {}` loads as Growth 0; unknown
keys inside `growth` round-trip untouched. New members are keyed by their line (an Oakheart
recruit joins as `tree_grunt`/`tree_grunt#2`).

### Evolution in story
- `"story"` is in `evolution_rules.tres` `growth_modes`. After EVERY story battle (tactical and
  duel) `StoryResultApplier.apply(..., growth_ctx)` awards Growth through
  `GrowthTracker.compute_awards` to the members that **fought and survived** (duel: the lead only;
  tactical: the fielded squad, KOs from the battle's GrowthTracker roll call), gated by
  `GrowthTracker.gate_reason` (never in replays / network). `GrowthTracker` itself never writes
  the global ledger for a story battle (`detect_mode` → `"story"` via
  `StoryController.is_capturing()`); StoryController seeds its end-screen rows with the preview
  of what Continue will award.
- Once the overworld is back (`overworld_ready`), before the paused script resumes,
  `StoryController.offer_pending_evolutions()` chains an `EvolutionScreen` per party member with
  an evolution available (Evolve / Not now; never after a whiteout). The screen's story `commit`
  runs `StoryGrowth.evolve`: the member **becomes** the form (member id, nickname and item kept,
  HP mapped by the edge's `hp_policy`, KEEP_RATIO by default) and the form is unlocked for open
  modes. Not now writes nothing; the offer returns after the next battle.
- `StoryState.story_flags()` is passed as `story_flags` in every story evolution context, and the
  new `StoryFlagTrigger` (evolution data layer) reads it — a story-only edge never unlocks in
  open modes.
- `EvolveMemberCommand` (script): a story beat evolves a member past its triggers
  (EVOLUTION.md §6 `evolve_member(uid_or_line, edge_id)`), through the same screen.
- Content: the Elder's "I will walk it." now also sends **Sprig** (Barkling, `JoinPartyCommand.growth
  = 2`), so winning Bram's battle (where Sprig fights) reaches the evolution offer in the slice.

### Standalone duels and Growth
Choice: standalone duels (Solo → Duel) award Growth only if `evolution_rules.tres` lists
`"duel"` — **shipped OFF** (a free pick-any-unit 1v1 against the AI is the cheapest grind in the
game; EVOLUTION's `growth_modes` is the authority on where Growth is earned). The code path is
wired (`DuelController.award_standalone_growth`, same gates; the results card shows the rows and
opens the Evolution screen for a member that became ready), so turning it on is a one-line data
change. Story duels always follow `"story"`.

### Remaining gaps (M2)
- Party duels (bench switching / KO-replacement) — the duel is strict 1v1; the bench never fights.
- Duel `USE_ITEM` / battle consumables; the duel's Party / Items buttons stay disabled.
- Flee is not a net command (the duel is offline-only); a replay of a fled duel ends at the last
  command. Duel replays (`ReplayLog.MODE_DUEL`) and mid-duel suspend are not built yet.
- `DuelScaling` treats `strength` as a stat scale; levels (EVOLUTION Q2) are undecided.
- Mid-battle `EvolveEffect` PERMANENT commits in story, and the duel's `unit_evolved` move
  re-compile, are not wired (no shipped edge uses them yet).
- No CharacterSelect story branch: a tactical squad is still the first `squad_size` healthy
  members; party > squad needs the picker (and a Party-screen reorder) in M2.
- Profile points still accrue on the story tactical end screen (existing behaviour).

## Deviations from OVERWORLD.md (M1)

- Hero = a dedicated `HeroResource` (DECISIONS.md #4) with Vineweave's model as the placeholder.
- The squad for a story tactical battle is the first `squad_size` healthy members in party order
  (no CharacterSelect story branch yet — with Sprig and a befriended recruit the party can now
  exceed Bram's squad of 3; the later members sit that battle out).
- The Story card is appended as card 7 after Duel (existing number keys unchanged).
- The Wayshrine stands on a sacred-ground basin (the plain fountain tile has no geometry).
- Placeholder houses get procedural roofs (`PropEntity`), people are procedural figures.
- Journey menu ships Resume / Party / Save / Title only; `pending` script resume across an app
  restart is M3 (the pre-battle autosave puts you in front of the trainer instead).
