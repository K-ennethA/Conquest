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
- Evolutions have REQUIREMENTS, all of which must be met (DECISIONS.md #26; EVOLUTION.md §3.2a):
  Growth, battle feats, held / used item, location, weather, known move, story flag, party
  member. The story context (`StoryGrowth.evolution_context`, `mode = "story"`) carries the flags,
  the area / region / weather the party stands in, the party and the bag; the member adds its held
  item. After every story battle the members that fought also record their BATTLE FEAT counters
  (wins, KOs, KOs by element, clutch wins) in their record (`growth.feats`), same gates as Growth.
- Once the overworld is back (`overworld_ready`), before the paused script resumes,
  `StoryController.offer_pending_evolutions()` chains an `EvolutionScreen` per party member with
  an evolution available (Evolve / Not now; never after a whiteout; members on **Hold** skipped).
- **Other auto-offer events** (DECISIONS.md #27): entering a new area (`warp_to`), a flag set or a
  member joining (flushed when the script ends — `OverworldController` calls
  `StoryController.flush_evolution_events`), and using an item from the bag. A non-battle event
  offers only the edges it could have changed, so a declined offer is not re-asked on every step.
- **Evolve later / Hold** — Journey → **Party**: each member card shows its requirements
  checklist per next form (✓ met / ○ unmet with progress; branches listed separately), an
  **EVOLVE** (or **PROMOTE**) button while an evolution is due (now, or by using an item the bag
  holds), and a **Hold** toggle (no automatic prompts; the button still works). Journey →
  **Bag**: an item some evolution uses lists "Use on" buttons per member
  (`StoryController.use_item_on_member`: a confirmed evolution spends it, Not now keeps it).
  Hold is saved per member as `"hold"` (format_version stays 2; an older save loads it off). The screen's story `commit`
  runs `StoryGrowth.evolve`: the member **becomes** the form (member id, nickname and item kept,
  HP mapped by the edge's `hp_policy`, KEEP_RATIO by default) and the form is unlocked for open
  modes. Not now writes nothing; the offer returns at the next relevant event (the next battle for
  a Growth / feat edge) and the member's EVOLVE button in Journey → Party stays.
- `StoryState.story_flags()` is passed as `story_flags` in every story evolution context, and the
  new `StoryFlagTrigger` (evolution data layer) reads it — a story-only edge never unlocks in
  open modes.
- `EvolveMemberCommand` (script): a story beat evolves a member past its triggers
  (EVOLUTION.md §6 `evolve_member(uid_or_line, edge_id)`), through the same screen.
- Content: the Elder / Sprig quest was replaced by the opening; the starter joins at Growth 0,
  so its evolution offer comes after a few won battles (Bram's, the grass). Barkling → Oakheart
  now needs **Growth 3 + Win 2 battles with it**; Growth only comes from surviving won battles,
  so the third win that brings Growth 3 has always brought the two wins too — the opening's first
  offer arrives exactly when it did (no starter-growth change was needed).

### Standalone duels and Growth
Choice: standalone duels (Solo → Duel) award Growth only if `evolution_rules.tres` lists
`"duel"` — **shipped OFF** (a free pick-any-unit 1v1 against the AI is the cheapest grind in the
game; EVOLUTION's `growth_modes` is the authority on where Growth is earned). The code path is
wired (`DuelController.award_standalone_growth`, same gates; the results card shows the rows and
opens the Evolution screen for a member that became ready), so turning it on is a one-line data
change. Story duels always follow `"story"`.

## Shops, consumables and gold (DECISIONS.md #28 + its revision)

Scope now: healing items, status cures, revives and the existing equipment. Bonding shards and
evolution / promotion items are **not** sold yet — a shop is generic data, so they are later
stock lines (gated by story flags), not code.

- **Consumables** — an `ItemResource` whose `consumable` holds a `ConsumableEffect` (heal N HP
  and / or N% of max HP, cure named statuses or every AFFLICTION — the rule-6a classification,
  revive a knocked-out member at N% HP; `usable_in_field` / `usable_in_battle`). Never worn,
  never dropped (`ItemLibrary.consumables()`; `items_of_rarity` / `items_with_scope` leave them
  out). Every item has a base `price` in gold (0 = not sold / not bought back: catalysts, key
  items). Content: `game/items/content/consumables/` — names are the `.tres` `display_name`
  (rename freely; the ids are the save keys).

  | id | name | effect | price |
  |---|---|---|---|
  | `mossleaf_tonic` | Mossleaf Tonic | +25 HP | 40 |
  | `heartwood_tonic` | Heartwood Tonic | +60% max HP | 120 |
  | `bitterroot_salve` | Bitterroot Salve | cures Poisoned (battle only) | 30 |
  | `clearwater_draught` | Clearwater Draught | cures every ailment (battle only) | 70 |
  | `dawnpetal_draught` | Dawnpetal Draught | revives a knocked-out member at 50% HP | 250 |

  Equipment prices: commons 150–180, rares 420–500, epics 1400–1500.
- **Using them** — out of battle: Journey → Bag → "Use on" (the ONE use-an-item flow,
  `StoryController.use_item_on_member` → `StoryState.use_consumable`). Each member's button
  shows its HP and is disabled with the reason when the item would be wasted (full HP, a healthy
  member for a revive, a battle-only cure); a use saves the journey. A heal never raises a
  knocked-out member; a revive only clears the knocked-out / wounded state. In a duel: the
  **Items** action (`DuelRuleset.allow_items`, on in `default_duel.tres`) opens a picker of the
  side's battle items (`BattleRequest.items` ← the bag's battle consumables); a pick is the
  recorded **USE_ITEM** command (`NetProtocol` action 5, **PROTOCOL_VERSION 3**), applied by
  `NetGameRules` like any command — deterministic (no roll), replayed by
  `DuelBattle.replay_commands`, in `ReplayLog`'s appliable vocabulary — and it costs the turn.
  In a strict 1v1 the target is the lead (a revive cannot be used mid-duel: a KO ends it).
  `DuelResult.items_used` → `BattleResult.items_used` → `StoryResultApplier` takes them from the
  bag whatever the outcome. The AI never uses items. **Tactical battles have no item action yet.**
- **Gold** — story gold (`StoryState.gold`). Knobs on `story_ruleset.tres`: `wild_gold_per_foe`
  (15: a won wild duel), `battle_gold_per_foe` (0: trainers pay their authored
  `BattleSpec.reward_gold` purse), `sell_ratio` (0.5), `bag_stack_cap` (99). Chests give gold
  (`ChestEntity.loot_gold`).
- **Merchants** — `ShopEntity` (an NPC with a `ShopResource`): talking plays its greeting then
  `OpenShopCommand` → the host's `open_shop` → `ShopScreen`; the script (and the overworld)
  waits until you leave. `ShopResource` (`game/overworld/content/shops/<id>.tres`, built by the
  content builder): stock lines `{item_id, price (0 = the item's), stock_limit (-1 = unlimited),
  condition (a story-flag gate)}`, `restock` (NEVER / ON_REST — a Wayshrine / healer / whiteout
  rest, `StoryState.rests` / EVERY_N_STEPS), `sell_ratio` (-1 = the ruleset's), `buys_items`.
  The rules are `ShopLedger` (pure). Shipped: **Merchant Oda** at the green-awning stall in
  Crownhaven's market (`crownhaven_general`: tonics, salves, draughts, revives, a few charms; boots
  and the poultice after the opening) and **Pedlar Jory** by the Mossway road after the opening
  (`mossway_pedlar`: road prices, restocks every 150 steps, buys at 40%). Names in the builder's
  `NAMES`.
- **Shop screen** — grove card: Buy / Sell tabs (Q / E, LB / RB), gold pill, item list (owned,
  stock, price), detail (effect, a **party preview** of what it does to each member), quantity
  picker (← / →, − / +), confirm; messages for not enough gold, sold out, bag full, not bought
  here. Modal overlay (`InputActions.OVERLAY_GROUP`); leaving saves the journey when anything
  changed. Screenshots: `docs/screenshots/shops/`.
- **Saves** — `"shops": {shop_id: {sold: {item_id: n}, epoch}}` and `"rests"`; format_version
  stays 2 (an older save loads with every merchant fully stocked).
- **Compendium** — `CompendiumData` has no items section yet, so consumables have no entry.

### Remaining gaps (M2)
- Party duels (bench switching / KO-replacement) — the duel is strict 1v1; the bench never fights
  (and an item cannot target a bench member).
- Tactical battle items (no Items action on the tactical HUD); the duel AI never uses items.
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
- Journey menu ships Resume / Party (with evolution checklists, EVOLVE, Hold) / Bag (evolution items
  and consumables: Use on) / Save / Title; `pending` script resume across an app
  restart is M3 (the pre-battle autosave puts you in front of the trainer instead).
