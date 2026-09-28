# Story / Evolution / Duel — decisions (2026-09-27)

Owner decisions on the three design docs (EVOLUTION.md, OVERWORLD.md, DUEL_BATTLE.md). Where a
doc's default differs from this file, THIS FILE WINS. Anything not listed: use the doc's default.

## Owner decisions
1. **Collecting:** BOTH story joins AND befriending wild units are in scope (not deferred to M3).
   Befriending = after WINNING a wild duel, the defeated wild unit may offer to join. No capture
   items, no mid-battle capture.
2. **Evolution in open modes:** evolving UNLOCKS the evolved form in open modes (Skirmish, Versus,
   Arena — both forms pickable); in STORY the party member actually becomes the evolved form.
3. **Duel party size:** flexible — build the doc default (lead + up to 2 bench, KO-replacement,
   switch costs the turn; wild encounters 1 foe) but keep party size a ruleset knob
   (CONQUEST.md rule 11: tuning on the mode's ruleset resource). First slice is strict 1v1.
4. **Overworld avatar:** a dedicated HUMAN HERO (the "Warden" idea) — separate from the party, not
   the lead unit. Until a Blender model exists, the hero uses an existing roster character model as
   a placeholder (configurable in ONE place, e.g. a HeroResource with model/scene + yaw), so
   swapping in the real model later is a data change.

## RNG / befriend fairness (lead's default, owner may revise)
- Every battle (tactical or duel) starts from FRESH entropy (NetSession.begin_solo_match_rng); the
  per-command seed is stamped into replays so playback reproduces. Retrying re-rolls. Resuming a
  battle save also re-rolls (no anti-save-scum lock).
- A crit KO never forfeits a befriend: the join offer is rolled on VICTORY whether the wild unit
  was KO'd or not.
- "Subdue" mechanic: a False-Swipe-style move effect that cannot reduce the target below 1 HP;
  a wild unit that is subdued (ended at 1 HP / KO'd by a subdue move) gets a higher join chance.
  Join chance + subdue bonus are data on the duel/story ruleset.
- Story-critical recruits are never missable: on loss/flee the encounter persists (re-triggers on
  return / after a wayshrine rest).
- The join-offer roll uses the battle's seeded stream (deterministic in replays), never randf().

## Shared contracts (all three features)
- Persistent party/roster member records: EVOLUTION's RosterLedger member (stable member_id) is
  THE record the story party stores (OVERWORLD §10) — one record type, not two.
- Battle launch/return: OVERWORLD's BattleRequest / BattleResult; StoryController.report_battle_result
  exactly once per battle. BattleResult gains `befriend_offer: {character_id, accepted}`.
- Duel combatants are real Units on a DuelBoard; damage only through DamageMath (rule 9).
- Evolution: Unit.apply_form / EvolveEffect / GrowthTracker as in EVOLUTION.md.

## Process
- Branches off `reconcile/cloud-merge` (the reconciled merge; PR into main pending):
  `feat/evolution`, `feat/duel`, `feat/overworld`, each in its own worktree.
- Milestone 1 of each feature first (the vertical slices). Keep GUT at 0 failures on your branch.
- Follow CONQUEST.md coding conventions and docs/UI_STYLE.md (grove look) strictly.

## Humans vs creatures (owner decisions, 2026-09-28)
5. **Unit kind:** every CharacterResource gets `kind` = HUMAN or CREATURE (Compendium +
   squad-select badge). Acquisition and progression key off it.
6. **Humans are recruited, not caught:** unique named individuals (one of each), joined via
   story / quests / talk-to-recruit. Never in the wild.
7. **Humans fight in duels too, alongside creatures** — e.g. sparring to stay in shape, or
   being attacked by criminals and defending yourself and your creatures. So duel sides can
   field humans and creatures together (this supersedes "combatants are creatures" framing;
   party size stays a ruleset knob — see decision 3).
8. **Human progression = class promotion** (e.g. Squire -> Knight) on the same Growth +
   EvolutionResource machinery as creature evolution.
9. **Creatures are species; most are found in the wild** (per-area encounter tables), some
   are story-only (starter, legendaries, bosses) or story gifts; you can own several of one
   species. Trained via Growth -> evolution.
10. **Catching = ACTIVE catch attempt during a wild duel** (an action/item); chance rises when
    the target is weakened, subdued (Subdue move) or statused; a failed attempt costs the
    turn. Rolled from the battle's seeded stream (deterministic, replayable). This replaces
    decision 1's "offer to join after a win" as the primary way to get wild creatures.
11. **Individual variation (rolled deterministically when caught, stored on the roster
    record):** temperament (nature-like stat lean, shown on the card), hidden potential rolls
    (small per-stat variance), rare variants (alternate colour or elemental form, e.g. changed
    element + one different move). Cosmetic SKINS stay a separate, later system (the existing
    SkinLibrary) and must not be confused with variants.

## Story premise and opening (owner, 2026-09-28)
12. **World:** an asteroid struck the world long ago; humans and creatures alike can wield
    elemental powers.
13. **Bonding shards:** the kingdom's lead researcher (at the castle city) developed a unique
    shard that makes bonding with creatures easier and safer. Shards were being handed out, but
    not widely — a select few testers have them, and the army may have some. In game terms the
    shard IS the catch / bond mechanic (decision 10): it is why few people have creatures and
    why the tech is worth stealing.
14. **Opening:** the villager hero goes to the castle city to receive their first creature (and
    shard). While they are in town, an ENEMY NATION abducts the lead researcher for this new
    technology. The raiders escape toward the hero's village and destroy it on the way — a
    casualty of war, nothing personal to them. The hero's MOTHER is killed.
15. **First fight:** an army soldier, feeling for the hero, offers them the chance to fight to
    avenge their mother — the first battle is against the fleeing raiders (see decision 7:
    humans fight alongside creatures).
16. **Human class promotion needs an ITEM or a specific LOCATION** (e.g. a trainer/order at a
    place, a crest/insignia item) in addition to Growth — it is a class change, not a
    biological one. Creature evolution stays Growth-driven (items/story triggers optional).

## World history, the true enemy, the general (owner, 2026-09-28)
17. **Before shards:** nations and people bound creatures by FORCE — e.g. chains made of shard
    material — or, among good people, genuinely befriended them through trial and error (those
    bonds need no shard). The researcher's shard lets almost ANYONE forge a connection.
18. **The fallen creature:** a creature so powerful it is thought to have crashed WITH the
    asteroid. It wields shard magic directly, giving it dominion over lesser creatures and
    potentially humans.
19. **The true enemy is a hidden DARK ORGANIZATION** that wants to capture the fallen creature.
    Whether Mortis / the Dark units belong to it is still OPEN.
20. **Main thread:** the enemy nation takes the blame — framed by, or controlled by, the dark
    organization. The hero must prevent an all-out war by uncovering its secrets and the true
    enemy.
21. **The recurring GENERAL:** the soldier from the opening becomes a recurring general the hero
    keeps bumping into across the game, eventually teaming up with them to save the day.

## Story mechanics and arcs (owner approved, 2026-09-28)
22. **Shard chains (villain mechanic):** the dark organization's creatures are CHAINED —
    forced bonds, not friendship — shown as a status + visual. Breaking the chain in battle
    frees the creature; a freed creature can then be catchable.
23. **Old-way bonds:** the few people who befriended creatures WITHOUT shards (trial and error)
    are mentors / recruitable humans; their creatures get something special for being
    shard-free bonds.
24. **The fallen creature's finale:** its dominion over lesser creatures can turn the hero's own
    creatures against them until its hold is broken; the ending choice is capture / free /
    befriend it the old way.
25. **The general's arc:** met repeatedly at army battles — wary and by-the-book at first —
    later learns their nation is being manipulated and sides with the hero for the finale.

## Evolution / promotion requirements and holding (owner, 2026-09-28)
26. **Evolution is not just XP.** Each evolution/promotion lists REQUIREMENTS that must all be
    met — Growth is only one kind. Others (data-authored per edge): hold/use an item, be at a
    location (or a region/biome), a story flag, time-of-day or weather, knowing a move, a
    battle feat (e.g. win N battles with this unit, land N KOs of an element, survive at low
    HP), bond/friendship, party composition (e.g. a certain species in the party). Human class
    promotions typically require an item or location (decision 16).
27. **Auto-trigger + hold:** when a unit's requirements become met, the evolve/promote offer
    appears automatically (after a battle, on reaching a location, on using an item). The
    player can decline ("Not now") and evolve LATER from a menu (story: Journey -> Party;
    open modes: squad select) — pending evolutions stay listed there. A per-unit "Hold"
    toggle stops the automatic prompts entirely (Everstone-style) until turned off.
    Unmet requirements are shown as a checklist so players know what's missing.

## Shops and merchants (owner, 2026-09-28)
28. **Stores / merchants** sell healing items and special items. Defaults (lead's proposal,
    owner may revise):
    - **Currency:** story gold (StoryState / GiveGold already exist), earned from battles,
      chests and selling; separate from profile points.
    - **Merchants:** an NPC entity type with a stock list (ShopResource: items, prices, stock
      limits, restock rule), placed in towns (Crownhaven's market stalls first) plus the odd
      travelling merchant on routes. Stock can be gated by story flags / progress.
    - **Buy and sell:** sell at a fraction of price; a grove-look shop screen (buy/sell tabs,
      quantity, party preview of what an item does to each member).
    - **Item categories:** HEALING consumables (restore HP out of battle; usable in duels via the
      Items action, costing the turn), STATUS cures, REVIVES (knocked-out members, instead of a
      Wayshrine trip), BONDING SHARDS in tiers (the catch items, scarce and gated), EVOLUTION /
      PROMOTION items (stones, crests — decision 16/26), and the existing EQUIPMENT (held items).
    - Uses the one "use an item on a party member" flow from the bag (built with evolution
      requirements), not a second one.
