# Story mode — overworld M1 (vertical slice) + the evolution / duel wiring

Design: `docs/design/OVERWORLD.md` (owner decisions in `docs/design/DECISIONS.md` win).
This file records what M1 actually built, how to play it, and how it is wired to
`feat/evolution` (Growth, the Evolution screen) and `feat/duel` (the real 1v1 duel) — see
**Wiring** below.

## How to play — the story OPENING

Solo → **Story** (card 7) → an empty slot. The opening (DECISIONS.md #12–#21 + "The researcher and
the starter") is built by `game/overworld/build/build_story_content.gd` (run it with
`godot --headless --path . -s res://game/overworld/build/run_builder.gd`); its names, the starters
and the placeholders live in that file's `NAMES` / `STARTER_ID` / `STARTER_OPTIONS` / `GENERAL_UNIT` / `WARRIOR_UNIT` /
`RAIDER_UNITS` / `HERO_MODEL` constants (rename there and rebuild); its flags are the `F_*`
constants. What NPCs SAY outside cutscenes is the **dialogue bank** (see "Dialogue bank & editor").
**Story text is placeholder** where the owner has not decided it (`TODO(story)` in the builder /
the bank's `note` fields) -- don't invent lore there.

**No interruptions.** Arriving somewhere never plays a scene or blocks the hero: entering a new named
place shows a small **location popup** (`OverworldHUD.show_area_name`, top-right corner, slides in,
holds ~2 s, slides out; pure presentation, no input, no pause). `PlaceAnnouncer` decides when: only
for a *different* named place -- never inside a building, never again for the place you are already
standing in, never for a place named in the last 20 s (hopping over an area edge and back). The old
once-only arrival narrations (River Crossing, Crownhaven, Woodland Town), the Mossway's grass hint
and the Crownhaven rival ambush are gone (the arrival flags are still set, silently; Lyra -- the old rival Lark, merged into her -- is now an
opt-in bout you start by talking to her). Ambient NPC talk speaks only when you talk to the NPC.

1. **Oakvale (home)** — a new journey starts on your doorstep with **no creature**
   (`story_ruleset.tres` `starting_party` is empty). The first boot plays the intro line and your
   mother **Briony**'s two-line send-off → `opening.sent_off` (the east road is held until then):
   **Professor Elias** — the Royal Researcher (he/him), an old friend of the family — is expecting
   you at his workshop in Crownhaven. Villagers Tobin / Hessa / Pell, the village-hall notice, the
   **mill chest**, the Wayshrine; your **home** can be entered (see "Interiors"), as can the inn,
   the village hall and the bakery.
2. **The Mossway** (east out of Oakvale) — with no partner the grass never rolls and trainers let
   you pass (`OverworldController`: no healthy member → no encounter, no trainer), silently.
   **Bram** and the **Lone Petalfang** only appear once `opening.complete`. Its east end
   is **River Crossing**: north over the Old Bridge, the King's road ends at Crownhaven's south gate.
3. **Crownhaven** (in by the south gate) — the walled river city: keep, market, barracks
   (**General Varden** once the opening is over), the Royal Workshop. Walk into the **Royal Workshop's door** (east of the
   keep): **Professor Elias** waits INSIDE (`crownhaven_workshop`). Talk to him: he explains his new
   invention — the bonding shards, stones that let a person bond with a creature (placeholder
   lines) — gives you one (`key.bonding_shard`), and you **choose your starter** from
   `STARTER_OPTIONS` (placeholders: **Barkling** — the default, the first option — Petalfang,
   Blightcap; `opening.starter_received`, and `opening.starter_pick` = the 1-based option).
4. **The kidnapping** — right after the choice, in the SAME room: placeholder enemy soldiers
   (`raider_captain` / `raider_a` / `raider_b`, Cindral-red figures that exist only between
   `opening.attack` and `opening.raiders_fled`) come in from the east side and take Elias; two lines
   and one narration ("enemy soldiers are attacking the city -- a distraction, so the raiders can
   slip away"). The raiders then run to escape (and burn Oakvale, which the ruins show). The hero is
   then **free** -- no warp: the way to Oakvale is the open road (south gate → River Crossing → the
   Mossway, whose west end now leads to Ruined Oakvale). Flags `opening.attack`,
   `opening.researcher_taken`, `opening.raiders_fled`, `opening.chase`; the respawn moves to the
   ruins' Wayshrine; the end autosaves. A journey saved between the ceremony and the end resumes the
   kidnapping on the next workshop load (its `on_enter`).
5. **Ruined Oakvale** (`oakvale_ruins`, a second area; the Mossway's west exit switches to it on
   `opening.attack`) — night, smouldering ruins. You walk up to the **General** and the **Warrior**
   (placeholder allies, `NAMES.GENERAL` / `NAMES.WARRIOR`): three short lines say what happened and
   they ask you to fight (`opening.allies_met`, `opening.ruins_seen`). "Not yet." leaves them waiting
   and you free to explore (the village's east road is open; they stay until the fight is won). Your
   mother's fate is told by Hessa when you talk to her (the dialogue bank).
6. **The first fight** — a TACTICAL battle on `ow_oakvale_ashes` (12x8) vs four placeholder enemies
   (two soldiers, a creature, a Duskmaw); your starter fights and the **General** and the **Warrior**
   join as **guest allies** (player-0 Reinforcements due on turn 1: placed at load, never replaced
   by the squad pick; player-controlled). A loss → Try Again / Return to Wayshrine (they wait to
   offer it again).
7. **Aftermath** — the General and the Warrior task you with getting stronger (to avenge your mother)
   while they prepare for war (`opening.complete`; `act1.find_rowan` is still set but nothing uses it
   to send you anywhere); a cairn for Briony. The whole starting region is then open: the placeholder
   main quest is **Grow Stronger** (no destination). General Varden's barracks line (he only stands there after `opening.complete`) and spar remain as
   optional talk (`act1.met_rowan` is a LEGACY save key from when he was a separate Sergeant Rowan, now merged into the General; kept so saves stay valid).

Controls: arrows / WASD / d-pad / sticks step one cell (tap a new direction = turn; hold = walk;
Shift / R3 = run; every step costs its walk / run time even with Animations off); click / tap
to walk; Confirm reads / talks / opens; Esc / Start → Journey menu. After the opening the M1
mechanics are unchanged: wild creatures (visible ones you walk into, or a hidden grass roll —
see "Visible wild creatures") → the real duel, befriending, Bram's tactical battle → Growth →
evolution offers, whiteouts to the Wayshrine.

**Placeholders to replace:** the starter options (`STARTER_OPTIONS`, roster TBD); the opening's
story lines (`TODO(story)`); the human hero is not a battle unit yet (the party fights); the
enemy units (`RAIDER_UNITS`: Undead ×2, Blightcap, Duskmaw) and the General's / Warrior's guest units (`GENERAL_UNIT` = Geode, `WARRIOR_UNIT` = Vineweave -- roster stand-ins; their names, `NAMES.GENERAL` / `NAMES.WARRIOR` = Talyn, female (she/her), are placeholders); people wear placeholder human models -- clones of Wren's and Lyra's (see
[NPC looks](#npc-looks-placeholder-human-models)) -- and buildings, door markers and
interiors procedural props (`PropEntity.prop`: house, ruin, keep, tower, gate, windmill, stall,
well, fence, crystal, mat, …). The hero's model is the Wren forge model (`HERO_MODEL`).

**Saves:** `format_version` 2. A version-1 journey (the M1 slice's Elder-quest world) is not
migrated: it loads as **outdated** — its slot card says a new journey is required (Delete it),
and Continue Journey skips it (`StorySnapshot.is_outdated`). Nothing crashes.

## Where things live

| Piece | Files |
|---|---|
| Autoload (session, runner, battle round trip) | `game/overworld/StoryController.gd` |
| Data | `game/overworld/data/` — `OverworldAreaResource`, entity kinds (`Npc`, `Trainer`, `Sign`, `Chest`, `Warp`, `Door`, `Wayshrine`, `TriggerZone`, `Prop`), `EncounterZone/Entry`, `BattleSpec`, `HeroResource`, `StoryRuleset`, `TournamentResource`, `WorldAtlas` / `WorldLocation`, `QuestLog` / `QuestTracker` / `QuestValidator` |
| Scripts | `game/overworld/script/` — `StoryCommand` + `commands/*`, `StoryScriptRunner`, `ScriptContext`, `StoryScriptHost` (the host contract), `ConditionContext` |
| Runtime | `game/overworld/runtime/` — `OverworldController` (scene root + live host), `OverworldGrid`, `TrainerSight`, `EncounterRoller`, `WildSpawner` (visible wild creatures), `TapPathfinder`, `OverworldActor`, `OverworldCamera`, `OverworldProps` |
| Battles | `game/overworld/battle/` — `BattleRequest`, `BattleResult`, `StoryBattleBridge`, `StoryResultApplier`, `StoryGrowth` (story Growth + evolution rules), `StoryPermadeath` (difficulty tiers, fallen, revives, game over), `StorySparring` (sparring-partner cooldown), `TournamentLedger` (the arena ladder), `DuelLauncher`, `DuelStub` (debug fallback) |
| Saves | `game/overworld/save/` — `StoryState`, `StoryPartyMember`, `StorySnapshot`, `StorySaveManager` (`user://story/slot_<n>.json`) |
| UI | `game/overworld/ui/` — `OverworldHUD` (+ the quest tracker), `JourneyMenu`, `world_map/WorldMapView`, `StoryStartScreen` (slots + the New Journey tier picker), `StoryGameOverScreen`, `TournamentLadderPanel` |
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

## Progression: levels, XP, bands, bond, catch rate (DECISIONS.md #65, #68, #76, #78-#82)
Spec: `docs/design/PROGRESSION.md`. **Levels exist only in story battles** — Skirmish, Versus,
Arena, online and their replays never read any of this.

**Where the knobs live:** `game/overworld/content/progression_rules.tres` (`ProgressionRules`,
`game/characters/progression/`): `max_level` 50, the XP curve (`xp_curve_k` 1 × L^`xp_curve_pow` 3),
`starter_level` 5, `legacy_level` 5, the XP formula (`xp_level_divisor` 7, `xp_level_exp` 2.5,
`xp_grey_gap` 5 / `xp_grey_mult` 0.1, `xp_min` 1, `xp_yield_per_budget` 0.5 / `xp_yield_min` 10),
battle multipliers (wild 1.0 / trainer 1.5 / boss 2.0), shares (fought 1.0 / fell 0.5 / bench 0.0),
`xp_on_loss_mult` 0, `xp_spar_mult` 0, stats (`default_growth` 0.04, `speed_growth_mult` 0.5),
`legend_over_band` 5, bond (`bond_max` 10, `bond_xp_per_level` 5, `bond_per_battle` 1,
`bond_per_win` 2) and catch rates (`catch_budget_easy` 130 → 1.0, `catch_budget_hard` 240 → 0.2,
`low_catch_rate` 0.5 for the content advisory). Per species (CharacterResource "Progression (story)"
group): `health_growth` … `speed_growth` (negative = the default), `xp_yield` (0 = from the power
budget), `catch_rate` (negative = from the power budget).

**What is built:**
- **Maths** — `Progression` (pure, static): curve, level from XP, the anti-grind XP for a foe,
  stat at level, scaled / legend levels, bands, bond, catch rate. Pinned by
  `tests/unit/test_progression_math.gd`.
- **Members** — `StoryPartyMember.level / xp / bond_xp` (saved as `level`, `xp`, `bond_xp`;
  format_version stays 2: an older save loads every member at `legacy_level`, its HP kept by ratio).
  `max_hp()` is the level's. Joins: `JoinPartyCommand.level` (0 = `starter_level`; the starter joins
  this way), the ruleset's starting party at `starter_level`, a befriended creature at the level it
  was met (`befriend_offer.level`).
- **Stats at level, both battle types, ONE function** (`Progression.apply_level`, on a private
  copy, rule 7): the DUEL applies it to the compiled `DuelCharacter` (then `strength` on top) from
  `DuelCombatant.level` (serialised only when > 0, so open-mode replay headers are byte-identical);
  the TACTICAL board levels at spawn — `MapLoader._create_unit_from_spawn` asks
  `StoryController.level_for_spawn` (0 unless a story tactical battle is live) and swaps in
  `Progression.leveled_copy`. Party members fight at their own level (by squad slot), a guest ally
  at the party's top level (`BattleRequest.ally_level`), foes at a spawn's own `"level"` key or the
  request's `enemy_level`. Leveled units carry meta `story_level` ("Lv N" on the duel unit cards and
  the tactical unit info panel).
- **Enemy levels** — `BattleSpec.enemy_level` (+ an opponent row's own `"level"`), `boss_battle`
  (XP ×2, exempt from the catch advisory), `level_mode` FIXED / SCALED (`scale_offset`, `scale_min`,
  `scale_max`; resolved in `apply_scaling`, so every script / trainer / tournament launch gets it),
  `BattleSpec.make_chief(spec, band, offset)` and `make_legend(spec, band)` (band max +
  `legend_over_band`, never scaled). Wild: `OverworldAreaResource.level_band`, narrowed per zone by
  `EncounterZone.level_band`; a hidden roll hashes the level from (seed, area, step), a visible
  creature rolls it at spawn and saves it (`"lv"` in its slot) — `EncounterRoller.roll_level`.
- **XP after every story battle** — `StoryProgression` (pure) via `StoryResultApplier` under the
  Growth gates (never replay / network / arena; only mode "story"), after the battle's HP is in
  (a level-up keeps the HP ratio). Per defeated foe, per member, with the member's own level:
  stronger foes pay more, weaker less, grey (5+ below) a tenth. Foe levels come from
  `BattleResult.defeated_levels` (the tactical board reports them), else the request's rows /
  `enemy_level`. End screens: the tactical GameOverScreen's "EXPERIENCE" rows
  (`StoryController.battle_progress_rows`) and the duel results card (`DuelResult.progress`, filled
  from `StoryController.preview_duel_progress`) — `ProgressRows`. Party page: Lv, XP bar, XP to next,
  bond, and the stat table at the member's level; the party list shows "Lv N".
- **Bond** — every member fielded earns bond XP (`StoryProgression.bond_for`: win 2, else 1, never
  a flee); shown on the party page; nothing reads it yet (the stone boost, #65, comes later).
- **Catch rate** — multiplies the befriend chance in story duels (`DuelRuleset.roll_join(...,
  catch_mult)`; open modes pass 1.0) and in the debug stub. `BattleSpec.catch_warnings()` is the
  content advisory (non-boss battles fielding a species under `low_catch_rate`); the report is
  printed by `tests/unit/test_story_bond_catch.gd`, never logged at runtime.
- **LevelTrigger** — one more evolution requirement kind ("Reach Lv N"), reading `level` from the
  story member context (`StoryGrowth.member_context`); unmet in open modes. No edge uses it yet and
  no Growth edge was migrated (#82).
- **Content** (builder `REGION_BANDS` / `LV_*` constants): Heartlands areas 2-8 (the Mossway grass
  2-5), Sparse Forest / Woodland Town 8-15, the other listed regions' bands ready for their areas;
  first fight 4, the lone Petalfang 4, Bram 5, Fenna 6, the footpad 7, the bandit boss 8, Lyra 7,
  sparring Wynn 5 / Aldous 7 / the General 10, the Crown Cup 6 → 7 → 8 → 10, the champion's rematch 12.

**Known gaps:** a replay of a story TACTICAL battle spawns at roster base (replays are not a story
battle — the same gap carried HP already has); runtime reinforcements of a story map are levelled
but not counted in `defeated_levels` (they fall back to `enemy_level`, which is what they spawn at).

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
  **General Varden** at the Crownhaven barracks (after the opening) offers a repeatable duel
  spar with his Geode (`crownhaven.spar.rowan` -- legacy id, kept for saves; built by `_general_spar_offer`).
- **Protect objectives** — `ProtectUnit` is now a GUARD (`WinCondition.is_guard`): listed as a
  LOSE condition, its FAILED is a defeat (`GameModeRules`). A map authors it as a victory string,
  `"Protect Elias"` / `"Protect: Elias"` (`WinConditionLibrary` puts it on the lose side, matched
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
| **Lyra** — the friendly RIVAL, a fellow tester and Professor Elias' student (Blightcap; the old rival Lark was merged into her -- the `rival.*` flags, quest `rival_lark` and encounter `crownhaven.rival.lark` keep their legacy spelling for saves). First duel: opt-in -- talk to her inside Crownhaven's south gate (the road home) after the opening; then rematches by the arena | Crownhaven (17,21) → (23,18) | spar (a rival FRIENDLY), CONTINUE, 60 gold on a win, `clash_intro` | `rival.met`, `rival.stage` (duels fought), `rival.wins`, `rival.duel1`; encounter `crownhaven.rival.lark` |
| **Sparring roster** — Corporal Wynn (Blightcap 0.8) < Lieutenant Aldous (Petalfang 0.95) < General Varden (Geode 0.8, the existing spar); a "Sparring Roster" sign | the barracks yard; after the opening (the General after his first line) | spar, CONTINUE, no purse | `crownhaven.spar.wynn` / `.aldous` / `.rowan` |
| **The ambush** — Cutpurse Nell and her footpad hold the Mossbrook's plank bridge (the only crossing: the brook runs tree line to tree line) once you have spoken to the General at the barracks | the Mossway, trigger at (21,6); after `act1.met_rowan` | TWO real duels back to back (HP carries), WHITEOUT; Classic permadeath applies | `mossway.ambush.sprung`, `.footpad_beaten` (a beaten footpad stays beaten after a loss), `.cleared`; 40 + 180 gold + a Dawnpetal Draught |
| **The Crown Arena** — a new `arena` prop (elliptical stone drum, pennants, gate arch) where the SE house stood; **Arena Master Bex** runs **the Crown Cup**; **Champion Isolde** offers rematches once her title is yours | Crownhaven (22..26, 19..21); master at (22,22), champion (25,18) | 4 spars | `arena.crown_cup.run` / `.round` / `.wins` / `.champion` (the title); rematch `arena.crown_cup.champion_beaten` |

**Rematch scaling** — `BattleSpec.scale_flag` / `scale_step` / `scale_max_steps`: every opponent's
strength is multiplied by `1 + step × min(flag, max)` when a script starts the battle
(`StartBattleCommand` → `BattleSpec.apply_scaling`; the authored spec is never mutated). Lyra +8% per
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
with the new condition `spar_ready("<encounter id>")` (the roster, the General, Lyra's and Isolde's
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
- `DuelScaling` treats `strength` as a stat scale; story LEVELS are applied first (see "Progression") and `strength` multiplies on top.
- Mid-battle `EvolveEffect` PERMANENT commits in story, and the duel's `unit_evolved` move
  re-compile, are not wired (no shipped edge uses them yet).
- No CharacterSelect story branch. A tactical squad comes from the deploy picker (see Humans,
  below), or, with no UI, from the default: the hero first, then the first healthy members. There
  is no Party-screen reorder yet.
- Profile points still accrue on the story tactical end screen (existing behaviour).

## Humans: the hero, recruits and guests (DECISIONS.md #5-#8, #54, #61, #63-#66)

The full as-built spec is docs/design/HUMANS.md. In short:

- **The hero is a battle unit.** A new journey adds the hero's party record (`is_hero`; roster
  entry `wren`, from `HeroResource.battle_character_id`) at the starter level. An older save gets
  him on load.
  - He never counts toward the party cap and can never leave or fall. If he falls in a real
    battle, it is a **game over** and the journey loads the pre-battle save.
  - The **lead** is the first partner creature.
  - Duels are the creatures' (`StoryRuleset.hero_joins_duels` = false), so a lost wild duel is
    still a whiteout. A duel spec with `hero_deploy = REQUIRED` (self-defence) adds the hero
    right behind the lead (`hero_duel_slot`).
  - Wild contact and trainer challenges still need a healthy partner creature
    (`hero_alone_can_battle` = false), so the opening walks past them.
- **Humans fight with a weapon.** The weapon attack fills slot 0, followed by any special moves
  the character lists. Weapon types (sword / lance / axe / bow / staff / tome) and the weapon
  triangle are data on `game/characters/weapons/weapon_rules.tres`. A member can swap weapons
  within its proficiencies (`StoryState.equip_weapon`).
- **Recruits are unique.** A human already in the party is not added twice, and humans are never
  in wild tables (the validator rejects them).
- **Temporary joins.** `JoinPartyCommand.temporary` / `guest_until` add a guest who leaves when
  that flag is set, or through `LeavePartyCommand`. A returning guest comes back as its old
  record. The party cards show Hero, Human and Guest badges and the weapon.
- **Deploying.** Before a story tactical battle with a real choice, the **deploy picker**
  (`SquadPickScreen` over the pure `SquadPick`) lets the player choose up to `squad_size` units:
  party members, temporary guests, and any `BattleSpec.offered_guests`.
  - `BattleSpec.hero_deploy` = REQUIRED locks the hero in. The opening's first fight uses it:
    the hero and his starter fight, and General Varden fights as himself.
  - Headless runs, tests and a direct `begin_battle` use the default squad.
- **Bonds.** A human's `bond_partner` is the creature it is bonded to. `StoryBond` /
  `StoryController.activate_bond` is the activation hook, with a placeholder stat bonus scaled
  by the creature's bond level. It is behind `StoryRuleset.bond_activation_enabled` (OFF).

## NPC looks (placeholder human models)

Owner, 2026-10-08: every PERSON on the overworld -- an `NpcEntity` (villager, trainer, merchant)
with no `visual_character` -- wears a clone of **Wren's** model by default and a clone of
**Lyra's** for a woman, instead of the procedural "chonky" figure (`OverworldProps.figure`).
`game/overworld/runtime/NpcLooks.gd` resolves and dresses it; `OverworldController._make_entity_actor`
calls it. Unchanged: NPCs with a `visual_character` (Varden, Elias, creatures), the hero, props.

- **The knobs** -- `StoryRuleset` "NPC looks" group (`game/overworld/content/story_ruleset.tres`):
  `npc_models_enabled` (off = the procedural figures again), `npc_default_model` = `wren` and
  `npc_female_model` = `lyra` (roster ids: a real model later is a data change), `npc_child_scale`
  (a `child` figure's clone, 0.72), `npc_tinted_figures` / `npc_tint_strength` (the `raider` figures
  keep their cloak colour as a multiply overlay, so the raiders and thieves read apart).
- **Who is a woman** -- `NpcEntity.body = "female"`, set by the builder from `FEMALE_NPCS` (in
  `build_story_content.gd`, next to `NAMES`) only where the story establishes it: an owner fact, a
  gendered title, or she / her about that person. Everyone else wears the default.
- **Fallbacks** -- a roster id with no model: the female look falls back to the default, the default
  to the figure. Each clone instances the roster's one shared `PackedScene`.
- **Animation** -- a Wren clone idles / walks with the hero's clips at his stride-matched rates
  (`OverworldController.HERO_STRIDES_META`), each NPC's idle offset so a crowd is not in lockstep;
  Lyra's model has no clips yet (bind pose).
- Screenshots: `docs/screenshots/npc_models/` (`dev_scripts/npc_models_shots.tscn`).

## Collision

`OverworldGrid.is_walkable(cell)` = the terrain's `is_passable` (minus water / lava, see
`OVERWORLD_BLOCKING_TILES`) AND no blocker on it. Blockers are the present entities whose
`is_blocking()` is true (NPCs, trainers, signs, chests, the Wayshrine, **solid props**) plus the
visible wild creatures. Warps and trigger zones never block.

- **Props are solid by KIND.** `PropEntity.SOLID_KINDS` (house, ruin, keep, tower, windmill, stall,
  well, fence, haystack, barrels, cart, banner, dummy, crystal, fire, rubble, arena, cabin, logs,
  lamp, chapel, smithy, scarecrow) block **every cell of their footprint**. Walk-over decor
  (`crops`) and a `gate` (its arch is walked under; the towers are wall terrain) are not.
  `PropEntity.collision` (`"auto"` / `"solid"` / `"walkable"`) overrides one prop either way; the
  builder's `_prop(..., blocking)` sets `"solid"` for a walk-over kind passed `true`.
- **Why the carts were walk-through.** `PropEntity._init()` forced `blocking = false`, but the
  exported default of `blocking` is `true`. `ResourceSaver` omits a value equal to the exported
  default, so every `blocking = true` the builder set was dropped from `area.tres`, and the
  reload came back with `false`. Never give an `@export` a different runtime default than its
  declared one; props no longer read `blocking` at all (`OverworldEntity.is_blocking()`, which
  `PropEntity` overrides, is what the grid asks).
- **Footprints.** A prop's footprint is its model's cell rect (`OverworldProps` builds each model
  inside it; one cell is 2 m). A cart / barrels / haystack / lamp is one cell; stalls and fences
  are 2+ cells along their long axis and block all of them. Houses and other buildings stand on
  `stone_wall` terrain, so they were already impassable; the prop being solid too keeps a model
  from ever being walkable if its terrain is repainted.
- **Routes.** `tests/integration/test_overworld_collision.gd` flood-fills every area from each
  entry point under every story stage and asserts every warp, NPC (a neighbouring cell), chest,
  sign, shrine, trigger and scripted-move target is still reachable, that no solid prop sits on an
  entry, an exit, an actor or a cutscene destination, that every solid prop cell is unwalkable on
  the real grid, and that prop models stay inside their footprints. When adding a prop, run it: a
  failure means a prop sealed something off (or walled a pocket of open ground away) -- nudge the
  prop's position in `build_story_content.gd`, then rebuild. The nudges made when props went solid:
  Crownhaven's four bridge lamps now stand on the deck corners (they cut each one-cell river bank in
  two and walled the south sign into a nook), the north-gate street lamp moved to the barracks-side
  column, one yard lamp and a training dummy moved a cell; Oakvale's plaza lamp (14, 6) and the barn
  haystacks (19, 13) / (19, 14); the River Crossing bank fence (3, 10); Woodland Town's archery
  targets (3, 7) / (5, 7) and the lumber-yard logs (18, 17).
- **Saves.** A save made before a prop turned solid may stand inside it: `StoryController.settle_location`
  (run by `continue_journey`) moves the hero to the nearest reachable open cell, wild creatures
  too (`WildSpawner._restore_slot` re-lays-out one on a blocked cell).
- **Encounter arrival.** A step that lands while the journey menu (or another overlay) is open
  waits for it to close before warps, triggers, trainers, creatures and the grass roll run
  (`OverworldController._await_arrival`; the menu can be opened mid-step, so without this a wild
  battle could start behind it). A TACTICAL encounter row stays a tactical battle
  (`StartDuelCommand.build_request` no longer forces `kind = duel` on it). Tests:
  `tests/integration/test_wild_encounter_flow.gd` (seeded grass roll -> the predicted foe on the
  predicted step; a contact fought on the real stage returns to the same cell with the duel's HP;
  every shipped table plays; no shipped roster spawns on a blocked cell). To watch a real
  encounter headless: `godot --headless --path . --script dev_scripts/wild_encounter_smoke.gd`
  (overworld -> grass step -> the real duel scene played by the AI -> Continue -> back on the same
  cell, with a pass / fail line per step).

## Interiors

Buildings can be entered, Pokemon-style -- **opt-in per building** (a building is NOT enterable by
default: a plain solid block, no door, no marker, no room).

- **Data** -- `PropEntity.enterable` (default false) + `door_offset` (default: the bottom row's middle
  cell, the south facade); `PropEntity.door_cell()`. A `DoorEntity` (a `WarpEntity`, kind `door`)
  sits on that facade cell -- still a SOLID cell of the footprint -- with `building` (the prop id) and
  `enter_dir` ("north"). Its actor is a placeholder door marker (`OverworldProps.door_marker`: plank
  door, frame, step); the real buildings come from Blender.
- **Going in** -- stepping toward the door from its front cell while facing the building
  (`OverworldController.try_step` → `door_at` / `enter_door`), Confirm on it (prompt "Enter"), or a
  tap on it: the door's `WarpCommand` → `StoryController.warp_to` (the same save + fade as every
  warp). You arrive inside at entry `door` (just above the exit mat), facing in.
- **Coming out** -- the interior's **exit mat** (bottom-centre, a `mat` prop under a plain warp):
  step onto it and you are back on the door's FRONT cell (town entry `door_<building id>`), facing
  away from the building.
- **The interior template** -- `_build_interior` in the builder: ONE function builds every room: an
  OverworldAreaResource of kind `INTERIOR` (`parent_area` = the town) with a floor of `size` cells
  (8x6 .. 12x8), stone walls on three sides (the south is the open cut-away the camera looks in
  through), the mat + exit, two placeholder barrel stacks, no encounter zones (no wild creatures).
  Indoors the overworld mounts no world skirt / scenery ring (a dark backdrop instead) and the camera
  (`OverworldController.camera_bounds_for`) holds on the room's middle, a little closer
  (`OverworldCamera.INTERIOR_DISTANCE`).
- **Map + tracker** -- interiors are listed under their town's place in `world.tres` (not places of
  their own), so `WorldAtlas.location_for_area(<interior>)` is the town (it also falls back to
  `parent_area`) and "You are here" stays the town. The quest tracker counts a town and its
  interiors as the same "Here".
- **Saves** -- an interior is an ordinary area: a save made inside loads inside; the respawn point
  and whiteouts are unchanged (interiors have no Wayshrine).

**Enabled now** (`INTERIORS` in the builder): Oakvale -- the hero's **home**, the Hearth & Hen, the
village hall, the bakery; River Crossing -- the toll house; Crownhaven -- the **Royal Workshop**
(Professor Elias waits inside; the ceremony happens there), the barracks, the Gilded Stag, the
Merchants' Guildhall, the Chapel of the Starfall, the Aldermere Forge; Woodland Town -- the Wardens'
Lodge, the Stumped Hart, the trading post, the smithy, the herb hut. Every room is empty except the
workshop (no new NPCs).

**Adding one** -- in `build_story_content.gd`, add a row to `INTERIORS[<town area id>]`:
`"<building prop id>": {"id": "<interior area id>", "name": "...", "size": Vector2i(w, h)}` (optional
`"door": Vector2i(x, y)` in the footprint, `"floor": "<tile id>"`); for people inside, add a case to
`_interior_people` (and `_interior_on_enter` for an arrival script). Rebuild. The door, the town
entry and the room are generated; the builder fails if the door would open onto a wall, a prop or
an NPC (it picks the nearest open bottom-row cell when no `door` is given).

Tests: `tests/integration/test_interiors.gd` (the opt-in list and a default house with no door, doors
↔ interiors ↔ exits, reachable encounter-free rooms, a door step in and the mat out with the facing,
Confirm on a door, save / load inside, the map's "You are here", the tracker, the workshop ceremony
→ the kidnapping in the same room); the collision audit treats a door as used from its front cell.

## Journey menu pages (Esc / Start)

Rows: Resume · Party · Quests · Bag · Map · Difficulty · Settings · Load · Save · Title Screen. The
card footer is the journey summary (place, gold, play time, the TRACKED quest's objective).

- **Quests** — `QuestLog` (`game/overworld/data/`) derives the log from story flags against
  `game/overworld/content/quests.json` (`start_flag`, `complete_flag`, ordered `steps` of
  `{flag, text}` + the optional pointers below); only the pin is saved. All / Main / Side /
  Completed filters, **Track** / Untrack and **Show on map** per open quest (see "Quest tracking").
  Edit quests with the Quest Editor plugin (or the JSON).
- **Party → Details** — `PartyDetailPage`: portrait, form / element / role chips, HP, Lv + XP bar + bond, Growth
  (the evolution currency), the shared `UnitPageContent` stat table (at the member's level), equipment and move / ability
  cards. Equip / Unequip move a unit-scope item between the member and the bag
  (`StoryState.equip_item` / `unequip_item`, `StoryController.equip_from_menu`).
- **Map** — the WORLD MAP (see "World map" below); its **Places** toggle keeps the old list (the
  current place, the Wayshrine rest point and every visited area).
- **Settings** — the shared `SettingsPanel`. **Load** — reloads the slot's last save behind a second press.

Tests: `tests/unit/test_story_journey_pages.gd`, `tests/integration/test_quest_tracking_live.gd`.

### World map

`WorldMapView` (`game/overworld/ui/world_map/`) draws the owner's painting
(`game/overworld/ui/world_map/world_map.webp`, a copy of `docs/design/world_map/world_map.webp`;
imported lossy with mipmaps) with one marker per known `WorldLocation` at its `map_pos`:

- **Glyph by kind** — city = keep, town / village = house, dungeon / special = red seal, island =
  isle, route = waystone, nation = banner. **Gold** = visited, **cream** = built but not visited,
  **dim + lock** = CLOSED; a secret place is drawn only once `is_known` (its open flag is set).
- **You are here** pulses (gold rings); the **respawn Wayshrine** wears a green flame; each active
  quest's objective hangs a **"!" pennant** over its place (gold = main, green = side). **Roads**
  (toolbar toggle) overlay the atlas roads by kind: gold = main, dashed cream = track, dashed blue = sea.
- **The card** (corner away from the selection): name, region · kind, status chips, description,
  the quests that point there. A short view (phone landscape) drops the description.
- **Controls** — arrows / d-pad / left stick step to the nearest marker that way (nothing that
  way: focus moves on, as everywhere in the menu), Tab / shoulders cycle markers, Confirm zooms onto
  the selection (again: back out), right stick / WASD pan, + / - / PgUp / PgDn / triggers / wheel
  zoom, Home resets; mouse or one finger drags, a click / tap selects, two fingers / a trackpad
  pinch zoom; toolbar - / + for touch. The opening view COVERS the frame and centres on the player.
- **Phone width** (< 1000 logical px): the command card steps aside while the map has focus (a
  **Back** button and Esc bring it back); short views (< 560 px) tighten the page gutters.
- **Positions** — every `map_pos` sits on the place's ART (just above its painted label, so the
  marker never hides the label text); verified with `dev_scripts/world_map_shots.tscn -- align`
  (`docs/screenshots/world_map/map_alignment.png`). Screenshots: `docs/screenshots/world_map/`.

### Quest tracking

- **Schema (additive; old entries load unchanged)** — on a quest and / or a step (a step's own
  wins): `location` (a `WorldLocation` id, or an area id that resolves to its place), `area` (the
  area id the objective is in), `npc` (step: the entity to talk to), `giver` (quest: who anchors it).
  `QuestLog.entries` adds `step_index`, `location`, `area`, `npc`, `giver` to each row.
- **Tracked quest** — `QuestLog.tracked_entry`: the PIN (`StoryState.tracked_quest`, set by Journey
  → Quests **Track** via `StoryController.set_tracked_quest`, which saves) while it is active, else the
  first active main quest, else the first active side quest. The pin is saved as `"tracked_quest"`
  inside format 2 (no version bump: an older save has none and tracks the main quest; a finished /
  unknown pin just falls back).
- **HUD tracker** (`OverworldHUD`, top left): MAIN / SIDE kicker, title, objective and where it is
  ("→ Crownhaven", or "Here" in the objective's area -- then the step's `npc` wears a gold ◆).
- **Toasts** — `QuestTracker` diffs two `QuestLog` views (STARTED / ADVANCED / COMPLETED); it never
  listens to single flags, so scripts, battle rewards and tournaments are all covered. The baseline
  is taken whenever a session begins (a load / new journey is not news) and a swapped-in state (Try
  Again) re-baselines silently; `StoryState.flags_revision` makes the no-change poll free.
  `OverworldController._tick_quests` polls `StoryController.poll_quest_events()` only at a quiet
  moment (no script running, the Journey menu shut) and shows each event as a quest toast card.
  Scripted `_toast("Quest: ...")` beats in the builder still fire as before.
- **Quest Editor** (`addons/quest_editor`, enabled in project.godot; the **Quests** tab in the
  editor's bottom panel): quests grouped Main / Side (add / duplicate / remove / reorder), the
  fields above plus steps, flag / place pickers fed by `QuestValidator.scan_project` (the builder's
  F_* constants and flag literals, the generated .tres: SetFlag keys, joins, reward flags, trainer
  `.defeated`, tournament flags), **Validate** (unknown flags, unreachable quests whose start flag no
  content sets, duplicate ids, empty text, unknown places) and **Story flow** (quests in the order
  their start flags are reached). Saves via `QuestLog.to_json`: tab-indented, fixed key order, empty
  optional keys omitted -- `quests.json` is kept in exactly that form (a test checks).

Tests: `tests/unit/test_quest_tracking.gd` (schema, tracked entry, filters, JSON, the transition
detector, the pin's save round trip, the validator + story flow) and
`tests/integration/test_quest_tracking_live.gd`.

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

## The world map, and the towns on it

The owner's world map (`docs/design/world_map/world_map.webp`) is the source of truth for
geography. The story's **Oakvale** is the map's Starting Village, **Crownhaven** its Central
Kingdom; River Crossing, the Sparse Forest and Woodland Town keep their map names. Everything is
generated by `build_story_content.gd` (rerun it after editing; see the header for the command) and
drawn from the procedural prop kit in `OverworldProps` (placeholders until the Blender models land).

**Built route:** Oakvale → (east) the Mossway → River Crossing → (north over the Old Bridge)
Crownhaven's south gate → (west gate, after the opening) the Sparse Forest → Woodland Town →
(west road, once Warden Hale opens it) Deepwood Village → (north trail, once Nyra is beaten) the
Depths of the Wood (a maze) → the Heart of the Wood. See "The Deep Woods" below.

| Area | Character | Layout |
|---|---|---|
| Oakvale 24x21 | open farming village above the coast; one terracotta roof colour | no paving: a beaten-earth green with a crossroads, the well and the Wayshrine basin; the Hearth & Hen inn, cottages, mill, barn, bakery; barley field + scarecrow, orchard, haystacks; the south lane runs down to the Strand and a jetty on the sea; the mill lane runs west to the Farm Hamlet track (closed) |
| Ruined Oakvale | the same village after the raid, night | embers and ash; the Farm Hamlet track still runs west (closed); **after the opening** the fires are out, Marra / Ned / Wick are back to rebuild (new timber on the inn's plot) |
| The Mossway 34x12 (route) | mossy forest road | biting grass; Bram, Fenna, the Lone Petalfang, Pedlar Jory; the **Mossbrook** (bank to bank -- its plank bridge, and the ambush on it, cannot be walked round) |
| River Crossing 24x20 (village) | slate-roofed toll village | the river runs edge to edge (3 rows), the **Old Bridge** (2-wide stone) is the only way over; toll-keeper Hobb (tells the bridge story twice), Fisher Nan on the jetty, Carter Joss, the Wayshrine; the coast road east to Beach Village is washed out (closed) |
| Crownhaven 30x29 | grand walled river city, slate roofs, blue banners | the river along its south side with a 3-wide stone bridge; **five gates**: south (River Crossing, always open), west (the Sparse Forest, after the opening), north (the Mountain Road to Mountain Base, closed), east (the Redrock road to the Badlands, closed), the harbour gate south-east (the coast road to Beach Village, closed); keep + courtyard, barracks yard, Royal Workshop, market + Wayshrine, the Gilded Stag, Merchants' Guildhall, Chapel of the Starfall, Aldermere Forge on Harbour Lane, the Crown Arena |
| The Sparse Forest 28x12 (route) | open woodland | a winding cart track, four thickets of wild grass (its own table: Petalfang, Blightcap, Mycothrall, Barkling), Woodsman Alder's clearing |
| Woodland Town 28x24 | rustic timber town in a forest clearing, dawn light | stream with a plank bridge; east bank: Wardens' Lodge, boardwalk square + Wayshrine, Stumped Hart inn, Timber Row (trading post `woodland_trader`, forge), lumber yard + sawmill, camp; west bank: herbalist, archery range, the Starfall Stone glade; roads: east (the Sparse Forest), west (Deepwood Village -- held by the Wardens' rope until Warden Hale is asked), the north trail (Frostpeak Village, closed), the unmarked south trail (closed -- the Thieves Guild is never named in town) |
| Deepwood Village 26x20 | clan village in a clearing of the old forest | Nyra's lodge + three tree-houses (PLACEHOLDER cabins), the Deepwood Wayshrine, Nyra, Lyra (while she is in Deepwood), three generic villagers; east: the road to Woodland Town; north: the trail into the Depths (shut until Nyra is beaten) |
| Depths of the Wood: 4 rooms, 19x17 each (route) | old forest at dusk, every room alike | a MAZE (Lost Woods meets a Pokemon forest), each room enclosed by thick forest walls: a small clearing, 1-wide corridors to four exits and side passages; LIT lanterns mark the right exit (dark ones at the wrong exits, which lead back to the entrance); BREAKABLE TREES block the right way in rooms 2 and 4 (and a nook in room 3); tall grass (Petalfang, Blightcap, Barkling, Vineweave, Oakheart in the 8-15 band), two optional trainers, two chests |
| Heart of the Wood 19x14 (route) | the sacred glade at the maze's end | Eldroot waits in the clearing |

### The world registry (`content/world.tres`)

A `WorldAtlas` of `WorldLocation`s (`game/overworld/data/`), generated from the builder's
`WORLD_LOCATIONS` / `WORLD_REGIONS` / `WORLD_ROADS` -- the ONE place for geography. Each place has
an id, a name, a kind (city / town / village / route / dungeon / special / island / nation), a
region, a normalised `map_pos` on the map image, a status (**BUILT** with its `area_ids`, or
**CLOSED** with the `world.*_open` flag that will open its road) and an optional `secret` (the
Hidden Thieves Guild stays off the map until its flag is set: `is_known(state)`). Roads are
undirected `{a, b, kind}` with the map legend's kinds (`main` / `secondary` / `sea`); helpers:
`location`, `location_for_area`, `neighbours`, `has_road`, `reachable_built`, `validate`. Each built
area's `world_map_pos` / `region_id` come from its place (`_place()` in the builder).

| Place | Region | Status / opening flag | Reached from |
|---|---|---|---|
| Oakvale (0.426, 0.63) | heartlands | built (`oakvale`, `oakvale_ruins`) | Mossway, Farm Hamlet |
| Farm Hamlet | heartlands | closed `world.farm_hamlet_open` | Oakvale's mill lane |
| The Mossway | heartlands | built | Oakvale, River Crossing |
| River Crossing (0.544, 0.655) | heartlands | built | Mossway, Crownhaven, Beach Village |
| Crownhaven (0.498, 0.41) | heartlands | built | River Crossing, Sparse Forest, Mountain Base, Redrock, Beach Village |
| The Sparse Forest | woodlands | built | Crownhaven, Woodland Town |
| Woodland Town (0.301, 0.384) | woodlands | built | Sparse Forest, Deepwood, Thieves Guild, Frostpeak |
| Hidden Thieves Guild | woodlands | closed `world.thieves_guild_open`, **secret** | Woodland Town's south trail |
| Deepwood Village (0.098, 0.474) / Depths of the Wood (0.114, 0.337) | woodlands | built (`deepwood_village` / `depths_of_the_wood`, `_2`, `_3`, `_4`, `_heart`); their roads open with `world.deepwood_open` (Warden Hale) / `world.depths_of_the_wood_open` (Nyra's win) | Woodland Town's west road / Deepwood's north trail |
| Frostpeak Village | snowy_peaks | closed `world.frostpeak_open` | Woodland Town's north trail |
| Mountain Base / Mountain Pass / Hidden Depths | northern_mountains | closed `world.mountain_road_open` / `world.mountain_pass_open` / `world.hidden_depths_open` | Crownhaven's north gate / Mountain Base |
| Cindral (the Other Nation) | cindral | closed `world.cindral_open` | the Mountain Pass |
| Redrock Village | rocky_badlands | closed `world.badlands_open` | Crownhaven's east gate |
| Beach Village | sunlit_coast | closed `world.beach_road_open` | Crownhaven's harbour gate, River Crossing's coast road |
| Sunrise Isle / Island of Tides / Stormreef Isle | open_ocean | closed `world.sea_routes_open` | sea routes from Beach Village |

Closed roads are `WarpEntity`s built by `_closed_road()`: `requires` is the place's open flag and a
`locked_scene` answers until then (the warp targets an entry beside it meanwhile), so the next
chapter only has to add the target area, retarget the warp, flip the place to BUILT and set the
flag. Tests: `test_overworld_content.gd` (layouts, the atlas and positions, the river and the
bridges, the three towns' looks, every NPC reachable at every story stage) and
`test_story_towns_travel.gd` (real warps between the towns, every closed road turning you back).

### The Deep Woods (DECISIONS.md #38-#41, #50, #56, #67, #71, #74, #75, #80, #81, #85, #88, #92-#94)

Built by the builder's "THE DEEP WOODS" section (knobs are its constants). How to play it:

1. After the opening, walk west through the Sparse Forest to **Woodland Town** and talk to **Warden
   Hale** at the Lodge: the west road opens (`world.deepwood_open`).
2. Take the west road to **Deepwood Village**. Touch the Wayshrine. **Lyra** is here (she stays from
   the moment the road opens until the Eldroot battle is won; Crownhaven's Lyras hide meanwhile --
   `LYRA_IN_DEEPWOOD`, one Lyra at a time).
3. Talk to **Lyra**: she **challenges** you (#94) -- a friendly rival **duel** (`deepwood.rival.lyra`,
   a spar: never permadeath, a loss costs nothing), SCALED with the party inside the 8-15 band
   (`LYRA_DEEPWOOD_SCALE_OFFSET`, `LYRA_DEEPWOOD_TEAM`). "Not now" is fine: she blocks nothing. Once
   the bout is FOUGHT, win or lose (`deepwood.lyra_challenged`), she **joins** as a TEMPORARY member
   at the party's top level (`JoinPartyCommand.match_party_level`, `guest_until` =
   `deepwood.eldroot_beaten`). While she follows you she is **not an overworld character** (her village
   NPC hides, there is no follower actor); she is a human unit you deploy in the Eldroot battle's squad
   pick. A full party: she says so and joins when you talk to her again. Skip her entirely and the
   Eldroot battle still works -- she is simply not offered.
4. Talk to **Nyra** (the Deepwood chief, by her lodge): a chief **duel**, `BattleSpec.make_chief` --
   SCALED to the party's top level + `NYRA_SCALE_OFFSET` inside the 8-15 band. Her final creature
   carries `NYRA_STONE_BOOST` (TODO(bond): the stone boost placeholder). A loss whites out (a story
   duel has no Try Again screen); she waits. Winning sets `deepwood.nyra_beaten` and
   `fieldmove.treefell` (the move is now TEACHABLE) and opens the trail north
   (`world.depths_of_the_wood_open`; only Nyra gates it). She then **teaches the field move** (#92):
   pick which eligible party member learns it (one eligible member and nobody knowing it yet = no
   question; nobody eligible = "come back with one who can", and she teaches it whenever you return).
   Talk to her again to teach it to another eligible member. `deepwood.treefell_learned` marks the
   quest step.
5. **The Depths of the Wood -- the maze** (#93): four look-alike rooms (`depths_of_the_wood`, `_2`,
   `_3`, `_4`; one name, one size, one painter), each ENCLOSED by walls of old forest several cells
   thick (tree terrain, made dense by `thicket` props -- the tree tile's own art, extra trees per cell;
   the row just south of open ground keeps a single tree so the path stays visible). The walkable
   space is a small central clearing, four 1-wide corridors out to the exits, and each room's side
   passages cut into the walls (tall-grass pockets, dead ends). You always come in from the south;
   the three other exits are reachable only along their corridors: the RIGHT one leads on, the two
   WRONG ones send you back to the maze's entrance (`WarpEntity.arrival_toast`: a short "You feel
   turned around..." toast, nothing blocks); south goes back a room. **The clue:** every choice exit
   has a pair of lantern posts at its mouth (`DM_LIGHT_PROP`, PLACEHOLDER look); at the right one they
   are LIT (`PropEntity.glow` = `DM_LIGHT_GLOW`: an emissive lantern head and a light, in
   `DM_LIGHT_TINT`), at the wrong ones they stay dark (`DM_DARK_TINT`, no glow), and fireflies drift
   over the right corridor (`DM_CLUE_TILE`: sacred-meadow ground, the tile's own glow) -- the old
   signpost at the entrance, the Deepwood hunter and Nyra all say "follow the lights". The way
   through: room 1 **north**, room 2 **east**, room 3 **west**, room 4 **north**. In rooms 2 and 4 a
   **gnarled tree** stands between the lit lanterns: face it, Confirm, "Use Treefell?" -- Yes fells it
   for good (a saved flag) -- so without a member who LEARNED the move you cannot get through. Also:
   tall-grass pockets in every room (the Deep Woods' creatures, 8-15), two OPTIONAL trainers (a
   Forager in room 2, a Trapper in room 3: generic placeholders in side pockets, looking into them,
   away from the paths), a chest in a nook behind a breakable tree (room 3) and one at the end of a
   dead-end passage (room 4).
6. **The Heart of the Wood** (`depths_of_the_wood_heart`): the clearing at the end, where **Eldroot**
   waits. Talk to it: a **tactical legend battle** (`ow_deepwood_glade.tres`, squad of 4 picked in the
   squad pick -- Lyra among them if she came along; `BattleSpec.make_legend`: FIXED at band max +
   `legend_over_band` = 20, never scaled; Try Again on a loss). Win -> the OPTIONAL bond: "Bond"
   records Eldroot in `StoryState.legends` (saved as `legends`, format 2 unchanged), never the party;
   "Not now" leaves it in the glade to ask again. Journey -> Party lists bonded legends read-only.

**Maze knobs** (`DM_*`): `DM_ROOMS` (the rooms in order: each one's `right` exit, `gate` -- a breakable
tree in its mouth -- and `carve`: the side passages cut into the walls, `[Rect2i, tile]`), the
clearing's size (`DM_RX` / `DM_RY`), the lanterns (prop, lit / dark tints, glow), the clue tile, the
wrong-way toast (`DM_LOST_TOAST`), the signpost / trainers' cells and levels (`LV_DM_*`), the nook /
pocket chests. `PropEntity.glow` and the `thicket` prop kind are generic (any area can use them).
Deterministic: no RNG. Add a room = add a row (and its area folder in `_initialize`'s list and the
Depths' `area_ids` in `WORLD_LOCATIONS`).

**Field moves are LEARNED** (#71 / #92; `FieldMoveResource`, `content/field_moves/<id>.tres`):
`unlock_flag` (the move becomes TEACHABLE), who CAN LEARN it -- `species` (a creature's current form
or evolution line) and `humans` (human character ids: the hero's `wren`; add `lyra` to the builder's
`FIELD_MOVE_TREES_HUMANS` to let the Deepwood rival learn it -- left out, since a guest leaves) -- and
the hint / prompt / toast texts. A member LEARNS it through **`TeachFieldMoveCommand`** (the chief's
script; a choice of the eligible members, paged when long, "Not now" declines) and keeps it on its
record (`StoryPartyMember.field_moves`, saved as `field_moves`, format 2 unchanged; an older save loads
none). The move is USABLE when a FIT (fieldable) party member has learned it; the party page shows a
"Field moves: ..." line. Conditions: `knows_field_move("<id>")`, `can_learn_field_move("<id>")`.
**`FieldObstacleEntity`** (kind `obstacle`, look `tree`) blocks its cell; Confirm on it gives one hint
line while locked or while no fit member knows the move, else "Use <move>?" -- Yes sets
`<area>.<id>.cleared` (its `visible_if` hides it, so the actor and the blocker go, across a reload).
The sea move (Beach Village, #43) reuses all of it as data: a new move .tres, a chief's
`TeachFieldMoveCommand`, a new obstacle look.

**Guests stay out of duels:** a TEMPORARY member (Lyra here) is never in a duel lineup
(`StoryState.duel_lineup`) and never counts as the partner that lets a fight start (`can_battle`):
wild, trainer and chief duels stay the creatures'. She deploys in tactical battles through the squad
pick (default picks put party order first, so she is last).

Placeholders: Nyra's team (`NYRA_TEAM`), Lyra's team, the move's name ("Treefell"), the tree-houses
(cabin props), the lights (lamp props), the maze trainers ("Forager", "Trapper"), every Deepwood line
(TODO(story)). Tests: `tests/integration/test_deep_woods.gd` (+ `_live`: the Eldroot board, the
wrong-way toast), `tests/unit/test_field_moves.gd`, `test_story_humans.gd` (guests and duels),
`test_region_open.gd` (the Deep Woods open step by step). Screenshots: `docs/screenshots/deep_woods/`
(`dev_scripts/deep_woods_shots.tscn`).

## Dialogue bank & editor

**What NPCs say is data**: `game/overworld/content/dialogue.json`, read at runtime by
`DialogueBank` (`game/overworld/data/`). Editing it needs **no rebuild and no save migration** —
like `quests.json`, nothing of it is saved; every pick is computed from the journey's flags and
clocks on each talk.

- **Schema** — `{"areas": {"<area id>": {"<npc id>": {"note"?, "variants": [{"if", "label"?,
  "lines": [{"speaker", "text", "side"?, "name"?}]}]}}}, "version": 1}`. Variants are ORDERED: the
  first whose `if` passes plays (blank = always — put it last as the fallback). Speakers: `self`
  (the NPC, right side), `hero` (left), `narrator` (no portraits) or another NPC id of the same
  area. `{hero}` / `{lead}` / `{gold}` are filled at runtime.
- **Conditions** — the `ConditionContext` expressions (`has`, `flag`, `visited`, `party_has`, …) plus
  the readable `after('flag')` / `before('flag')` and **story time**: `rests_since('flag')`,
  `steps_since('flag')`, `minutes_since('flag')` (-1 while unset) and `rests()` / `steps()` /
  `play_minutes()`. Time comes from `StoryState.flag_times`: when a flag is first set (unset →
  truthy) it is stamped with the journey's clocks `{step, rest, sec}`; clearing it forgets the stamp.
  Saved additively as `"flag_times"` (**format_version stays 2**; an older save loads with none and
  its flags count from the journey's start). Single quotes work in conditions, so the JSON stays
  readable.
- **Runtime** — `NpcEntity.interact_script` (also merchants' greetings, and a trainer once BEATEN):
  an NPC **with** an entry says its matching variant (nothing when none matches) **instead of** its
  `.tres` `dialogue`; its `on_interact` script (a ceremony, an offer, a shop) still runs after the
  line. An NPC **without** an entry keeps its authored `.tres` line. An entry also makes an NPC with
  no lines talkable (`is_interactable_in(area_id)`, used by `OverworldController.entity_at`).
- **Content** — every ambient line of every built area moved out of the builder into the bank, with
  phase variants: before the raid / after it (`opening.attack`) / after the first fight
  (`opening.complete`) / Act 1 (`act1.met_rowan`) and a few time-based ones ("3 rests after the
  opening": Crownhaven moves on, Oakvale rebuilds). Nobody mentions the raid before `opening.attack`.
  Cutscenes (send-off, ceremony, raid, ruins arrival and the General's offer, the General's barracks line, the opt-in rival bout, ambush, arena,
  spars) stay in the builder.
- **Story phases** — `StoryPhases` derives the timeline from the MAIN quests in `quests.json` (start
  flag, step flags, completion flag, in order): phase k = the first k milestones set. A new main quest
  extends it with no code change.
- **The editor** — `addons/dialogue_editor` (enabled in `project.godot`): the **Dialogue** tab at the
  top of the Godot editor (beside 2D / 3D / Script). Left: Town → NPC tree + search. Top: the story
  phase and "+ rests / + steps" of story time; every view simulates that state. Tabs: **Lines** (the
  NPC's variants in order, each condition shown readably — "after: opening.attack · before:
  opening.complete · 3+ rests since opening.complete" — the phases it plays in, the variant that
  plays now highlighted; edit text inline, add / remove / reorder / duplicate variants and lines,
  condition helpers, create an entry for any NPC of the area `.tres`), **Town now** (tick flags, see
  what every NPC of a town says), **Cutscenes** (the area's scripted dialogue, read-only, each line
  under the condition that gates it), **Search**, **Missing** (NPCs with no entry, NPCs silent in a
  phase, TODO lines, variants that never play), **Issues** (the validator). **Save** runs the
  validator and writes sorted-key, tab-indented JSON (`DialogueBank.to_json`), so diffs stay small.
  The editor reads area resources through `StoryContentIndex` (properties only: in the editor the
  overworld scripts are not `@tool`, so their methods cannot be called).
- **Validator** — `DialogueBank.validate`: unknown areas / NPC ids / speakers, malformed conditions,
  flags no script / quest / entity sets or reads, entries without variants, variants without lines,
  empty text, variants shadowed by an earlier always-variant.
- Tests: `tests/unit/test_dialogue_bank.gd` (parsing, picking, the fallback, merchants and trainers,
  story time + its save round trip, readable conditions, the validator, phases) and
  `tests/integration/test_dialogue_content.gd` (the shipped bank validates and is canonical, every
  talking NPC has an entry, no raid talk before the raid, the towns talk about it after, time moves
  people on, the Researcher is Professor Elias (he/him, a family friend; none of the removed invented
  backstory / lore comes back), the live overworld plays the bank, the
  editor loads / edits / simulates / searches / saves).

## Deviations from OVERWORLD.md (M1)

- Hero = a dedicated `HeroResource` (DECISIONS.md #4) with Vineweave's model as the placeholder.
- The squad for a story tactical battle is the first `squad_size` healthy members in party order
  (no CharacterSelect story branch yet — with the starter and befriended recruits the party can
  exceed Bram's squad of 3; the later members sit that battle out).
- The Story card is appended as card 7 after Duel (existing number keys unchanged).
- The Wayshrine stands on a sacred-ground basin (the plain fountain tile has no geometry).
- Placeholder houses get procedural roofs (`PropEntity`); people wear placeholder human models
  (clones of Wren's / Lyra's -- [NPC looks](#npc-looks-placeholder-human-models)), the procedural
  figures their fallback.
- Journey menu ships Resume / Party (with evolution checklists, EVOLVE, Hold, and the Fallen) / Bag
  (evolution items and consumables: Use on) / Difficulty / Save / Title; `pending` script resume across an app
  restart is M3 (the pre-battle autosave puts you in front of the trainer instead).
