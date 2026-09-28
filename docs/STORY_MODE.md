# Story mode — overworld M1 (vertical slice) + the evolution / duel wiring

Design: `docs/design/OVERWORLD.md` (owner decisions in `docs/design/DECISIONS.md` win).
This file records what M1 actually built, how to play it, and how it is wired to
`feat/evolution` (Growth, the Evolution screen) and `feat/duel` (the real 1v1 duel) — see
**Wiring** below.

## How to play — the story OPENING

Solo → **Story** (card 7) → an empty slot. The opening (DECISIONS.md #12–#21) is built by
`game/overworld/build/build_story_content.gd`; its names, the starter and the placeholders live
in that file's `NAMES` / `STARTER_ID` / `GUEST_ID` / `RAIDER_UNITS` / `HERO_MODEL` constants
(rename there and rebuild); its flags are the `F_*` constants.

1. **Oakvale (home)** — a new journey starts on your doorstep with **no creature**
   (`story_ruleset.tres` `starting_party` is empty). The first boot plays the intro and your
   mother **Briony**'s send-off → `opening.sent_off` (the east road is held until then).
   Villagers Tobin / Hessa / Pell, the village-hall notice, the **mill chest**, the Wayshrine.
2. **The Mossway** — with no partner the grass never rolls and trainers let you pass
   (`OverworldController`: no healthy member → no encounter, no trainer); a one-time hint says
   so. **Bram** and the **Lone Petalfang** only appear once `opening.complete`.
3. **Crownhaven** (the Mossway's east end) — the walled castle town: keep, market, barracks
   (**Sergeant Rowan**), the Royal Workshop. Talk to **Researcher Linnea**: the **ceremony**
   gives the starter (**Barkling**, `STARTER_ID`) and the **bonding shard**
   (`key.bonding_shard`, `opening.starter_received`).
4. **The raid** (the same script) — Cindral raiders vault the east wall, seize Linnea and flee
   west; Rowan runs up; the chase is a scripted warp to **Ruined Oakvale** (`opening.attack`,
   `opening.researcher_taken`, `opening.raiders_fled`, `opening.chase`; the respawn moves to the
   ruins' Wayshrine). A journey saved mid-raid resumes it on the next Crownhaven load.
5. **Ruined Oakvale** (`oakvale_ruins`, a second area; the Mossway's west exit switches to it on
   `opening.attack`) — night, smouldering ruins. The survivors tell you your mother went back
   for the others; Rowan offers the chance to fight (`opening.ruins_seen`). "Not yet." leaves
   him waiting in the square.
6. **The first fight** — a TACTICAL battle on `ow_oakvale_ashes` (12x8) vs the raiders' rear
   guard; your starter fights and Rowan's **Geode** joins as a **guest ally** (a player-0
   Reinforcement due on turn 1: placed at load, never replaced by the squad pick). A loss →
   Try Again / Return to Wayshrine (Rowan waits to offer it again).
7. **Aftermath** — Rowan's hook (`opening.complete`, `act1.find_rowan`); a cairn for Briony; the
   road opens. In Crownhaven, Rowan at the barracks starts the Act 1 hook (`act1.met_rowan`).

Controls: arrows / WASD / d-pad / sticks step one cell (tap a new direction = turn; hold = walk;
Shift / R3 = run; every step costs its walk / run time even with Animations off); click / tap
to walk; Confirm reads / talks / opens; Esc / Start → Journey menu. After the opening the M1
mechanics are unchanged: grass → the real duel, befriending, Bram's tactical battle → Growth →
evolution offers, whiteouts to the Wayshrine.

**Placeholders to replace:** the hero's model (Vineweave, `HERO_MODEL`); the human hero is not a
battle unit yet (the party fights); the raiders' units (Undead ×2 + Duskmaw, `RAIDER_UNITS`);
people are procedural figures (`NpcEntity.figure`) and buildings procedural props
(`PropEntity.prop`: house, ruin, keep, tower, gate, windmill, stall, well, fence, crystal, …).

**Saves:** `format_version` 2. A version-1 journey (the M1 slice's Elder-quest world) is not
migrated: it loads as **outdated** — its slot card says a new journey is required (Delete it),
and Continue Journey skips it (`StorySnapshot.is_outdated`). Nothing crashes.

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

Save format: `format_version` 2 since the opening (v1 = outdated, see above). A record's `growth: {}` loads as Growth 0; unknown
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
- Content: the Elder / Sprig quest was replaced by the opening; the starter joins at Growth 0,
  so its evolution offer comes after a few won battles (Bram's, the grass).

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
  (no CharacterSelect story branch yet — with the starter and befriended recruits the party can
  exceed Bram's squad of 3; the later members sit that battle out).
- The Story card is appended as card 7 after Duel (existing number keys unchanged).
- The Wayshrine stands on a sacred-ground basin (the plain fountain tile has no geometry).
- Placeholder houses get procedural roofs (`PropEntity`), people are procedural figures.
- Journey menu ships Resume / Party / Save / Title only; `pending` script resume across an app
  restart is M3 (the pre-battle autosave puts you in front of the trainer instead).
