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
mechanics are unchanged: wild creatures (visible ones you walk into, or a hidden grass roll —
see "Visible wild creatures") → the real duel, befriending, Bram's tactical battle → Growth →
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
| Data | `game/overworld/data/` — `OverworldAreaResource`, entity kinds (`Npc`, `Trainer`, `Sign`, `Chest`, `Warp`, `Wayshrine`, `TriggerZone`, `Prop`), `EncounterZone/Entry`, `BattleSpec`, `HeroResource`, `StoryRuleset`, `TournamentResource` |
| Scripts | `game/overworld/script/` — `StoryCommand` + `commands/*`, `StoryScriptRunner`, `ScriptContext`, `StoryScriptHost` (the host contract), `ConditionContext` |
| Runtime | `game/overworld/runtime/` — `OverworldController` (scene root + live host), `OverworldGrid`, `TrainerSight`, `EncounterRoller`, `WildSpawner` (visible wild creatures), `TapPathfinder`, `OverworldActor`, `OverworldCamera`, `OverworldProps` |
| Battles | `game/overworld/battle/` — `BattleRequest`, `BattleResult`, `StoryBattleBridge`, `StoryResultApplier`, `StoryGrowth` (story Growth + evolution rules), `StoryPermadeath` (difficulty tiers, fallen, revives, game over), `StorySparring` (sparring-partner cooldown), `TournamentLedger` (the arena ladder), `DuelLauncher`, `DuelStub` (debug fallback) |
| Saves | `game/overworld/save/` — `StoryState`, `StoryPartyMember`, `StorySnapshot`, `StorySaveManager` (`user://story/slot_<n>.json`) |
| UI | `game/overworld/ui/` — `OverworldHUD`, `JourneyMenu`, `StoryStartScreen` (slots + the New Journey tier picker), `StoryGameOverScreen`, `TournamentLadderPanel` |
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

## Difficulty tiers, permadeath and game over (DECISIONS.md #29 + "Permadeath refinements")

Story mode only. The rules are ONE pure class, `game/overworld/battle/StoryPermadeath.gd`; they run
when a battle's result is APPLIED (`StoryResultApplier`), never inside the battle, so the tactical
board, the duel and their replays know nothing about tiers.

- **The tier** — `StoryState.tier`: `"classic"` or `"casual"`, chosen on the New Journey screen
  (an empty slot → two grove choice cards, 1 / 2 or arrows + Confirm, Esc back to the slots).
  `StoryState.lower_tier` / `StoryController.lower_tier` only ever move DOWN (Classic → Casual;
  "cannot_raise" otherwise): Journey → **Difficulty** shows the tier, what it means and, in
  Classic, "Lower to Casual" behind a confirm ("You can't go back up"). The slot card shows the tier.
- **Classic (permadeath)** — every member knocked out in a REAL battle (tactical: dead on the board
  when it ends; duel: the lead that fainted — the bench never fought) FALLS:
  `StoryState.mark_fallen` moves it from `party` to `fallen` with `fallen_info`
  `{area_id, encounter_id, foe, kind, play_seconds, at_utc, item_id}`; its form, growth and nickname
  are kept (a later mechanic can bring it back), its equipped item goes back into the bag. Because
  it is no longer in `party`, nothing that reads the party sees it: squads, duels, healing,
  revives, evolution offers, merchants' previews, the party cap (a fallen uid is never reused).
  Journey → Party lists them under **Fallen** ("Fell at The Mossway against Bram · 1h 02m into the
  journey · Heartwood Charm returned to the bag"); the next overworld boot says who fell. A lost
  battle still whites out as before (those knocked out in it are fallen first).
- **Casual** — knocked-out members stay down until revived. A Wayshrine / healer rest heals the
  living for free (`HealPartyCommand`), then the Wayshrine's `ReviveOfferCommand` asks "Revive N
  knocked-out companions for X gold?" (`revive_fee_per_member` each; Not now keeps the gold; short
  of gold it says the price; when nobody can fight and the fee cannot be paid it revives them free,
  so a journey is never stuck). Revive items (Dawnpetal Draught) work in both tiers.
- **Fallen refusal** — `ConsumableEffect.check_member` refuses a fallen member ("fallen" — "X has
  fallen -- nothing can bring them back."), as do `StoryState.use_consumable` and
  `StoryController.use_item_on_member`.
- **Spars** — `BattleSpec.spar` → `BattleRequest.rules.spar` → `BattleResult.spar`: a friendly
  battle never marks anyone fallen and never ends the journey through the hero rule; with
  `spar_ko_recovers` its knocked-out leave it at 1 HP. The tactical objective banner shows a green
  "Friendly spar" tag; the duel's intro reads "Friendly spar: X squares up!". Shipped example:
  **Sergeant Rowan** at the Crownhaven barracks, after the Act 1 hook, offers a repeatable duel
  spar with his Geode (`crownhaven.spar.rowan`, built by `_rowan_spar_offer`).
- **Protect objectives** — `ProtectUnit` is now a GUARD (`WinCondition.is_guard`): listed as a
  LOSE condition, its FAILED is a defeat (`GameModeRules`). A map authors it as a victory string,
  `"Protect Linnea"` / `"Protect: Linnea"` (`WinConditionLibrary` puts it on the lose side, matched
  to a player-side unit by protect_id / story member id / character id / display name); a story
  battle names it on `BattleSpec.protect` (names, character ids or party member ids — a guest ally
  works). StoryController adds the guards to the board's rules when it tags the party
  (`StoryBattleBridge.guards_for`); the objective banner shows a rose "Protect Geode" tag and lists
  "Keep Geode alive" in its tooltip; the map menu's Objective page says "Defeat: Geode falls". In a
  duel a protected party member fainting counts the same way.
- **Game over** — `StoryPermadeath.game_over_reason`: the HERO falling (a party entry flagged
  `StoryPartyMember.is_hero` — the main character is not a battle unit yet; the flag is the hook and
  is tested with a stub: its unit carries meta `story_hero` and its own guard), a protected unit
  falling (both tiers), or — Classic, `classic_wipe_is_game_over` — a battle that would leave nobody
  alive. A game-over result is never applied. Tactical: the end screen retitles to **GAME OVER**
  with the reason (`end_banner`) and offers **Load Last Save** / **Return to Title**; a duel opens
  the grove `StoryGameOverScreen` with the same two. Load Last Save reloads the slot (the pre-battle
  autosave every battle writes; a slot-less journey rewinds to its in-memory copy); Return to Title
  leaves without saving the lost battle.
- **Knobs** (`story_ruleset.tres`, group "Difficulty tiers"): `default_tier` (casual: what a journey
  gets when nothing chose one), `revive_fee_per_member` (50), `whiteout_revives` (true),
  `spar_ko_recovers` (true), `classic_wipe_is_game_over` (true).
- **Saves** — `"tier"` and `"fallen"` (member records with `"fallen"` info) in the slot, `"hero"` per
  member; format_version stays 2. A save from before tiers loads as **Casual** (it was played without
  permadeath) with nobody fallen.
- Screenshots: `docs/screenshots/permadeath/`.

## Duels in story (DECISIONS.md #31 / #33)

Duels are no longer on the Solo menu (#31): story mode is where they happen. Everything is content
in `build_story_content.gd` (names in `NAMES`, flags / ids in the constants under "Duels in story",
the section `DUELS IN STORY` at the end of the file); the small systems each piece needed are listed
with it. Every opponent is a duel-eligible roster creature (`BattleSpec.validate` now refuses a duel
opponent `DuelMoveCompiler.is_duel_eligible` rejects, e.g. Bastion), its difficulty the duel's
`strength` stat scale (`DuelScaling`). **Decision 7 (humans fight alongside creatures) is not built:**
every duel here is the strict 1v1 creature duel — the people are trainers, their creatures fight.

| What | Where | Kind | Flags / ids |
|---|---|---|---|
| **Tester Fenna** — a trainer whose battle is a DUEL (line of sight 3, like Bram; Petalfang 0.9, 90 gold) | the Mossway (11,7), facing the path; after `opening.complete` | real duel, WHITEOUT | `trainer.mossway.fenna.defeated` |
| **Lark** — the RIVAL, a first-batch tester (Blightcap "Puck"). First duel: a trigger just inside Crownhaven's west gate after the opening; then rematches by the arena | Crownhaven (7,14) → gate trigger (5,13) → (23,18) | spar (a rival FRIENDLY), CONTINUE, 60 gold on a win, `clash_intro` | `rival.met`, `rival.stage` (duels fought), `rival.wins`, `rival.duel1`; encounter `crownhaven.rival.lark` |
| **Sparring roster** — Corporal Wynn (Blightcap 0.8) < Lieutenant Aldous (Petalfang 0.95) < Sergeant Rowan (Geode 0.8, the existing spar); a "Sparring Roster" sign | the barracks yard; after the opening (Rowan after the Act 1 hook) | spar, CONTINUE, no purse | `crownhaven.spar.wynn` / `.aldous` / `.rowan` |
| **The ambush** — Cutpurse Nell and her footpad hold the brook's plank bridge (the only crossing) once Rowan has signed you on | the Mossway, trigger at (21,6); after `act1.met_rowan` | TWO real duels back to back (HP carries), WHITEOUT; Classic permadeath applies | `mossway.ambush.sprung`, `.footpad_beaten` (a beaten footpad stays beaten after a loss), `.cleared`; 40 + 180 gold + a Dawnpetal Draught |
| **The Crown Arena** — a new `arena` prop (elliptical stone drum, pennants, gate arch) where the SE house stood; **Arena Master Bex** runs **the Crown Cup**; **Champion Isolde** offers rematches once her title is yours | Crownhaven (22..26, 19..21); master at (22,22), champion (25,18) | 4 spars | `arena.crown_cup.run` / `.round` / `.wins` / `.champion` (the title); rematch `arena.crown_cup.champion_beaten` |

**Rematch scaling** — `BattleSpec.scale_flag` / `scale_step` / `scale_max_steps`: every opponent's
strength is multiplied by `1 + step × min(flag, max)` when a script starts the battle
(`StartBattleCommand` → `BattleSpec.apply_scaling`; the authored spec is never mutated). Lark +8% per
rival duel fought (max 6), Isolde +8% per win over her (max 6), every Cup round +5% per cup already
won (max 4).

**Spars and Growth — choice.** A spar is a real duel for Growth: `StoryGrowth` awards it by the
ordinary story rules (the lead that fought and won earns `growth_per_win`; a loss earns
`growth_on_loss`, 0), and its feats count. What stops a friendly bout from being an endless Growth
farm is a **cooldown per partner**, not a Growth gate: `StorySparring` stamps every FOUGHT spar
(won or lost; a flee / abort does not count — `StoryResultApplier`) in two int flags
(`sparred.<encounter id>.rest` / `.step`, so nothing new in the save format), and the partner is
ready again once the journey has rested `StoryRuleset.spar_cooldown_rests` times (default **1**:
a Wayshrine / healer / whiteout rest) and walked `spar_cooldown_steps` (default 0). Content opts in
with the new condition `spar_ready("<encounter id>")` (the roster, Rowan, Lark's and Isolde's
rematches); a partner who is not ready says so ("rest up at the Wayshrine"). Spars never cause
permadeath (#29): `BattleSpec.spar` as before.

**The Crown Cup — format (choice).** `TournamentResource` (`content/tournaments/crown_cup.tres`;
rules `TournamentLedger`, flow `RunTournamentCommand`, screen `TournamentLadderPanel` via the new
host call `open_ladder(tournament, state) -> "enter" / "fight" / "withdraw" / "leave"`):
- **4 bouts, weakest first**: Tamsin (Mycothrall 0.9), Old Harl (Blightcap 0.95), Ser Quenby
  (Petalfang 1.05), the final vs Champion Isolde (Oakheart 0.85).
- **Entry 100 gold** opens a RUN. Bouts are fought **back-to-back or one per visit** — after every
  bout the ladder re-opens (Fight Round N / Withdraw / Leave) and **Leave keeps your place**. A lost
  bout ends the run; withdrawing forfeits the fee.
- **Healed before every bout** (the arena's healers: the living to full HP; NOT a rest — it never
  refreshes a sparring partner or an ON_REST merchant, and the knocked-out stay down).
- **Spars**: friendly competition — no permadeath, no whiteout; a KO leaves you at 1 HP and ends the
  run.
- **Prize**: first cup 400 gold + a **Sunleaf Totem** + the title **Crown Cup Champion**
  (`arena.crown_cup.champion`; toast "Title: …", badge on the ladder); later cups 200 gold. Winning
  unlocks Isolde's scaling champion rematch (once per rest, 120 gold per win).
- **Save / reload mid-ladder**: the run is flags, saved after every bout (and by the pre-battle
  autosave). Quit between bouts or in the middle of one and the arena master offers "Fight Round N"
  again — the same round, no second fee.
- The ladder card: title ribbon, gold pill, entry / prize / healing badges, one row per round
  (crest, entrant, species, **Threat** pips vs your lead, WON / NEXT chips), status line, buttons;
  ←/→ + Enter, Esc leaves. Screenshots: `docs/screenshots/story_duels/`.

Tests: `tests/unit/test_story_sparring.gd` (cooldown, `spar_ready`, applier stamps, scaling,
eligibility), `tests/unit/test_tournament_ledger.gd` (fee, ladder, loss / withdraw, prize once,
healing is not a rest, save round-trip, the command end to end), `tests/integration/test_story_duels.gd`
(content + flags, Fenna spots you → a real duel, the rival's first duel + a scaled rematch after a
rest, a Classic spar never falls + the cooldown, the ambush → two duels → reward, losing it in
Classic costs the partner, a full Cup run → prize + title + the champion, save / reload mid-ladder).

### Remaining gaps (M2)
- The hero is not a battle unit yet: the hero rule is wired through `is_hero` / `story_hero` and
  tested with a stub member; nothing in the shipped story sets it.
- A fallen member can not be brought back yet (the record is kept for that mechanic).
- No shipped battle uses a protect objective yet (the engine, the banner and the story wiring do).
- Party duels (bench switching / KO-replacement) — the duel is strict 1v1; the bench never fights
  (and an item cannot target a bench member). Humans fighting ALONGSIDE creatures in a duel
  (DECISIONS.md #7: the hero defending themselves in the ambush, sparring to stay in shape) needs
  mixed duel sides — every story duel is still the lead creature vs one foe creature.
- The duel intro names the foe CREATURE ("Petalfang challenges you!"), not the trainer: the
  DuelRequest carries no opponent name (the VS clash and the pre-battle lines name the trainer).
- Tactical battle items (no Items action on the tactical HUD); the duel AI never uses items.
- Flee is not a net command (the duel is offline-only); a replay of a fled duel ends at the last
  command. Duel replays (`ReplayLog.MODE_DUEL`) and mid-duel suspend are not built yet.
- `DuelScaling` treats `strength` as a stat scale; levels (EVOLUTION Q2) are undecided.
- Mid-battle `EvolveEffect` PERMANENT commits in story, and the duel's `unit_evolved` move
  re-compile, are not wired (no shipped edge uses them yet).
- No CharacterSelect story branch: a tactical squad is still the first `squad_size` healthy
  members; party > squad needs the picker (and a Party-screen reorder) in M2.
- Profile points still accrue on the story tactical end screen (existing behaviour).

## Journey menu pages (Esc / Start)

Rows: Resume · Party · Quests · Bag · Map · Difficulty · Settings · Load · Save · Title Screen. The
card footer is the journey summary (place, gold, play time, current objective).

- **Quests** — `QuestLog` (`game/overworld/data/`) derives the log from story flags against
  `game/overworld/content/quests.json` (`start_flag`, `complete_flag`, ordered `steps` of
  `{flag, text}`); nothing is saved. Edit the JSON to add / reword quests.
- **Party → Details** — `PartyDetailPage`: portrait, form / element / role chips, HP, Growth
  (there are no levels), the shared `UnitPageContent` stat table, equipment and move / ability
  cards. Equip / Unequip move a unit-scope item between the member and the bag
  (`StoryState.equip_item` / `unequip_item`, `StoryController.equip_from_menu`).
- **Map** — the current place, the Wayshrine rest point and every visited area (no world-map scene yet).
- **Settings** — the shared `SettingsPanel`. **Load** — reloads the slot's last save behind a second press.

Tests: `tests/unit/test_story_journey_pages.gd`.

## Visible wild creatures (the default encounter mode)

Decision: wild creatures are **visible and grid-locked** (Let's Go / Mystery Dungeon "symbol"
encounters); the classic hidden tall-grass roll stays as an **opt-in zone mode**. Rationale and
options: the world research memo (§1) and docs/design/OVERWORLD.md §4.5.

**How it works**
- `EncounterZone.mode` — `VISIBLE` (default) or `HIDDEN` (the old per-step roll, `rate`). A VISIBLE
  zone holds `max_active` creatures (1–8, 3–6 reads well), one per **slot**, standing on the zone's
  cells (its rect and / or tile ids, minus any cell an entity occupies). `spawn_clearance` (3) keeps
  a freshly laid-out roster away from where you arrive.
- **Determinism** — `WildSpawner` (`game/overworld/runtime/`, pure logic) picks each slot's species
  (weighted, condition-filtered table) and cell from `EncounterRoller.unit_float(seed, "area|wild|
  zone|epoch|slot|…")`, and every move from `(seed, area, zone, slot, steps)`. Never `randf()`.
- **The step clock** — creatures move **one cell per player step** (after warps, triggers and
  trainers, before the hidden roll), never in real time. Behaviours on `EncounterEntry.behaviour`
  (per species row): `WANDER` (random walk, leashed to the zone, `move_chance`), `TIMID` (steps away
  while you are within `sense_range`), `AGGRESSIVE` (TrainerSight along its facing, `sense_range`:
  "!" and it closes in; it never leaves its zone), `SLEEPING` (never moves, "z z"), `PATROL`
  (walks the `patrol` waypoints in a loop; may leave the zone, never walls).
- **Contact** — `OverworldController.try_step` (and Confirm / a tap on a creature) checks for a
  creature in the target cell *before* walkability: walking into its **back or side** (or a sleeper)
  = `"ambush"`, face to face = `"neutral"`. `_on_arrived` step 4 ticks the creatures; one that walks
  **into you** = `"ambushed"`. The battle is the wild duel (`StartDuelCommand` with `id_kind =
  "wild"`, encounter id `<area>.wild.<species>`), then `WildOutcomeCommand`, then the befriend prompt.
  Grace steps (after a battle / an area entry) stop creatures walking into you (you may still walk
  into them); a traveller with no healthy partner is never engaged (the opening).
- **The opening rule key** — `BattleRequest.rules["opening"]` (`BattleRequest.RULE_OPENING`,
  `OPENING_AMBUSH` / `_AMBUSHED` / `_NEUTRAL`; missing = neutral). **Consumed by the duel:**
  `DuelRequest.from_battle_request` copies it (the strict `from_dict` accepts only the three values),
  `DuelRequest.opening_side()` → `DuelTurnSystem.first_side` (set in `DuelBattle.setup`): the
  ambushing side acts first in **round 1 only**, whatever the speeds; round 2 on is speed order.
  It is recorded with the request, so a replay starts the same way. **Not consumed by tactical
  battles yet** (a TACTICAL wild entry still runs as a duel today, like the grass): the place to
  read it is `StoryBattleBridge.prepare_board` (e.g. a first-phase / initiative bonus).
- **Despawn / respawn** — a **win** (victory, befriended or not) removes the creature
  (`WildOutcomeCommand` → `WildSpawner.forget` + host `despawn_wild`); a flee or a loss leaves it where
  it stood. Its slot refills when `EncounterZone.respawn` fires (mirrors `ShopResource.restock`):
  `ON_REENTER` (default: every new visit rolls a fresh roster), `ON_REST` (`StoryState.rests`: a
  Wayshrine / healer / whiteout rest), `EVERY_N_STEPS` (`respawn_steps`). In-area refills (a rest, N
  steps) only fill empty slots — survivors never jump.
- **Saves** — `StoryState.wild` (`"<area>|<zone key>"` → `{epoch, mark, visit, slots: {"<slot>":
  {cid, cell, facing, wp}}}`) + `StoryState.visit_serial` (bumped by `on_area_changed`), saved as
  `"wild": {visit, zones}`. **Format version stays 2**: an older save has no `"wild"` (every zone
  rolls fresh); `WildSpawner.sanitize_saved` drops malformed records; a saved species no longer in
  the zone's table is skipped. Within one visit (a battle round trip, a save + reload) every
  creature stands exactly where it stood and walks on identically.
- **Visuals** — each creature is an `OverworldActor` with its **roster model** as a placeholder
  (`CharacterResource.model_scene`, idle / walk clips; a procedural figure if a species has none),
  under the scene's `Wild` node; real overworld models come from Blender later (swap the model in
  `OverworldController._mount_wild`). `AreaPrewarmer` preloads the roster `.tres` (and so the
  `.glb`) of every VISIBLE zone's species with the neighbour's NPCs.
- **Grid** — creatures are `OverworldGrid` blockers (id `wild:<zone>#<slot>`): NPC paths and tap
  paths go round them, but sight does NOT stop at them (`OverworldGrid.blocks_sight`: trainers and
aggressive creatures look over a creature in the grass). `refresh_world` re-registers them.

**Adding a visible zone to an area** (content lives in `build_story_content.gd`; this branch did
not touch it): in the area's builder function, create an `EncounterZone` (mode defaults to
VISIBLE), set `tile_ids` (`[&"tall_grass"]`) and / or `area_rect`, `max_active`, `respawn` (+
`respawn_steps`), give it a stable `zone_id` (e.g. `&"mossway_grass"`, so reordering zones never
orphans saved rosters), and fill `table` with `EncounterEntry` rows — `character_id`, `weight`,
`behaviour`, `sense_range`, `move_chance`, `patrol` (≥ 2 waypoints for PATROL), `condition` (flag
gates). Append it to `area.encounter_zones` and rebuild. For the old feel set `mode = HIDDEN` and
`rate`. `EncounterZone.validate` (run by `test_overworld_content`) flags an empty table, an unknown
species, a bad condition and a patrol without a route.

**Shipped content note:** the Mossway's grass zone predates modes and does not store one, so it
now loads as VISIBLE (4 creatures from its Petalfang / Blightcap / Barkling table, wandering,
ON_REENTER). The world-data rework decides per zone (set `mode = HIDDEN` + `rate` to keep a roll).
The two grass-roll integration tests force the Mossway zone HIDDEN for their duration
(`StoryFixture.set_zone_modes`).

Tests: `tests/unit/test_wild_spawner.gd` (deterministic roster + walk, leash, one cell per step,
each behaviour, creatures block walking but not sight, contact openings, every respawn rule, conditions,
save round trip + malformed / old saves, the request / duel-request rule key),
`tests/integration/test_wild_spawns.gd` (the real scene on the test-only fixture area
`tests/helpers/wild_fixture.gd`: actors + blockers, ambush from behind → win → despawn → still gone
after a reload → back on re-entry, neutral + flee, ambushed by an aggressive one, grace / no
partner, a HIDDEN zone still rolls), `tests/integration/test_duel_contact_opening.gd` (round-1
order).

**Gaps:** creature models are roster placeholders (scale / idle clips as in battle); no
encounter "!" wipe or transition; the tactical battle ignores `opening`; a TACTICAL wild entry is
still forced to a duel (as the grass always did); creatures do not react to weather / time of day
beyond `condition`; no repel; a patrol's waypoints are absolute cells (re-author them if the
terrain moves); NPCs walking scripted paths treat creatures as walls (a cutscene through a crowd
falls back to a straight line).

## Area travel & loading

A warp still swaps the whole `OverworldScene` behind the `SceneFade` (save → fade out → new scene
builds the area → fade in), but the heavy parts of that build are now cached and prepared ahead:

- **Tile geometry** (`TileMeshCache`): `LowPolyTileBuilder` / `PavedTileBuilder` meshes are pure
  functions of (style, world cell) and every area starts at the world origin, so each cell is
  built once per process and shared (it was ~0.5 ms of GDScript per tile per load). Capped at
  `TileMeshCache.MAX_CELLS` (~35 KB per cell; the four areas use ~1.35 k cells).
- **Neighbour prewarm** (`AreaPrewarmer`, polled by `StoryController._process`): once an area is
  up, every area its *present* warps lead to gets its `area.tres`, tile scenes and NPC roster
  models loaded with `ResourceLoader.load_threaded_request`, then its tile geometry
  (`MapLoader.prewarm_tile_geometry`) and world skirt (`WorldSkirt.prewarm`) computed on the
  WorkerThreadPool. One short step per frame; a warp taken before it finishes waits for the
  in-flight task instead of redoing it. `GameWorld.tscn` and `DuelStage.tscn` are then loaded in
  the background and held for the session (windowed only; released on Title).
- **World skirt / terrain mask**: cached by `TerrainMask.content_key` (board size + tile layout);
  the skirt is pure data computed off-thread and mounted from shared meshes / MultiMesh buffers.
- **Board lookups**: `MapResource.build_tile_lookup` replaces the per-cell linear
  `get_tile_at_position` scans (MapLoader, TerrainMask, BoardAdapter) — they were O(cells²).
- **Fewer nodes**: overworld tiles drop the unused per-tile `StaticBody3D` (taps use the ground
  plane; `MapLoader.tile_collision_enabled`, battles keep it), and every tile builds its effect
  particles / overlay only when an effect lands (~10 → ~6 nodes per cell).
- `SceneFade` holds black two frames after a scene lands before fading in, so a heavy arrival
  frame no longer swallows the fade.

Measured headless (CPU only, same machine, instantiate + `_ready` of the new scene): Oakvale →
Mossway ~790 ms → ~60 ms when prewarmed (~160-250 ms if you leave the instant you arrive),
Mossway → Crownhaven ~1.4 s → ~100-140 ms; node count per area −40 %. Guarded by
`tests/integration/test_area_load_perf.gd` (node budgets, "a prewarmed area computes no tile
geometry on the main thread", worker == inline geometry, cache keys).

Content rules: keep areas ≤ ~32×32 (a tile is still ~6 nodes; batching tiles into MultiMesh /
chunks is the next step if areas grow), never give a tile scene per-instance random state that
is not a function of its cell (the cache would share it), and route new warp kinds through a
`WarpEntity` (scripted `WarpCommand` warps are not prewarmed).

## Deviations from OVERWORLD.md (M1)

- Hero = a dedicated `HeroResource` (DECISIONS.md #4) with Vineweave's model as the placeholder.
- The squad for a story tactical battle is the first `squad_size` healthy members in party order
  (no CharacterSelect story branch yet — with the starter and befriended recruits the party can
  exceed Bram's squad of 3; the later members sit that battle out).
- The Story card is appended as card 7 after Duel (existing number keys unchanged).
- The Wayshrine stands on a sacred-ground basin (the plain fountain tile has no geometry).
- Placeholder houses get procedural roofs (`PropEntity`), people are procedural figures.
- Journey menu ships Resume / Party (with evolution checklists, EVOLVE, Hold, and the Fallen) / Bag
  (evolution items and consumables: Use on) / Difficulty / Save / Title; `pending` script resume across an app
  restart is M3 (the pre-battle autosave puts you in front of the trainer instead).
