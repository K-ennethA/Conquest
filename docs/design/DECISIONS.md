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

## The researcher and the starter (owner, 2026-10-03)
- **The researcher is PROFESSOR ELIAS**, the Royal Researcher (magic / history / science): 60+,
  he/him, wise, calm, intelligent, wears glasses; a **longtime friend of the hero's mother** and a
  family friend. Reference sheet: `docs/design/characters/professor_elias.webp`.
- **The hero chooses a starter.** The starter roster is **TBD** (placeholder options for now).

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

### Revision to 28 (owner, 2026-09-28)
- **Shop scope for now: healing items, status cures, revives, and the existing equipment only.**
  Bonding shards and evolution/promotion items are NOT sold yet — those systems aren't fleshed
  out. Keep the ShopResource generic so they can be added later as data.

## Permanent death mode (owner, 2026-09-28)
29. **Permadeath mode** (Fire Emblem "Classic" style), as an option:
    - If an ally falls in a real battle (tactical or duel), they cannot be used for the rest of
      the game. **Sparring and friendly battles never cause permadeath** — battles carry a
      `spar` / friendly tag, and training spars, rival friendlies etc. only knock units out.
    - A fallen unit is marked FALLEN, not deleted (its record, growth, form and items are kept),
      so a later mechanic can bring them back ("we might introduce a mechanic to get them later").
    - Defaults (lead's proposal, owner may revise): chosen per journey when starting a new story
      (Classic = permadeath / Casual = knocked-out units recover at a Wayshrine); it can be turned
      OFF mid-journey but not back ON; applies to STORY mode only (open modes have no persistent
      roster to lose); fallen units show as fallen in the Party menu (with where/when they fell),
      are excluded from squads and duels, and their equipped item returns to the bag.
      The hero is not a battle unit yet — hero death rules come with that milestone.

### Permadeath refinements (owner, 2026-09-28) — supersede 29's defaults where they differ
- **Chosen at the start of a journey**, as a difficulty TIER. A player may move DOWN a tier
  mid-journey if it's too hard (Classic -> Casual), never back up.
- **Casual tier:** knocked-out units are recovered AT A COST OF GOLD (e.g. at a Wayshrine /
  healer), not for free. (Revive items from shops also work in both tiers.)
- **Story mode only for now.** Later idea (not now): a Campaign "challenge" mode where fallen
  units are lost for the rest of that run.
- **Fallen units:** as in 29 (kept as records, shown as fallen, excluded, item returned).
- **Game over:** the MAIN CHARACTER falling is always a game over. Other characters can also
  cause a game over when the story or mission objective says so (e.g. "Protect Elias") — use
  the engine's ProtectUnit lose condition (exists as a class; needs wiring into maps/story
  battles). A game over returns to the last save / pre-battle autosave.

## Menu structure: Online, and duels live in story (owner, 2026-09-28)
30. **Main menu:** Solo, **Online** (new), Compendium, Map Creator (+ Resume / Continue Journey
    rows as today). The old top-level Versus entry folds into Online.
31. **Solo:** Story, Campaign, Skirmish, Arena Run (solo roguelite stays). **No Duel card** —
    duels are reached through STORY MODE, not the menu. Challenges moves out of Solo.
32. **Online:** 
    - **Versus** — choose the mode (Conquest map battle = today's tactical versus, or **Duel**)
      and where the opponent is: **Network** (host/join/dedicated) or **Same device** (hot-seat).
      **Online duels are built now** on the existing NetSession core (commit-reveal RNG,
      validation, digests) — the duel is already deterministic commands.
    - **Challenges** (moved here from Solo).
    - **Arena** (multiplayer) — shown as COMING SOON; player count undecided, do not implement.
33. **Duels in story mode:** trainers / rivals who challenge you to duels, friendly SPARRING
    partners in towns (never permadeath; Rowan's spar exists), criminals / ambushes (scripted
    self-defence duels), and a TOURNAMENT / arena building in a city with a ladder of duels.

## The opening, refined (owner, 2026-10-04)
34. **Minimal dialogue, open to explore** (earlier Pokemon games): entering a town must not stop
    the player with text telling them where they are; nothing should interrupt movement and
    immersion unless the player asks (talks to someone) or a story beat genuinely needs it.
35. **The abduction:** when the professor is taken, enemy units appear IN THE ROOM (the workshop)
    and take him. At the same time other enemies attack the city as a DISTRACTION. Those enemies
    then run to escape and burn the hero's village as a further distraction.
36. **The burned village:** the hero meets **the General** and **another warrior** there (both
    placeholders for now). They tell the hero what happened, and the hero joins the fight
    alongside their creature, the General and his ally, against (placeholder) enemy soldiers and
    their creatures.
37. **After that win:** they task the hero with getting stronger to avenge their mother, and say
    they will be preparing for war. From there the hero is free to explore the whole region.

## Chiefs, legends and the road to war (owner, 2026-10-04)
38. **Chiefs:** certain towns have a CHIEF -- exceptionally strong, bonded with their creatures
    WITHOUT the need of the stones. With their main partner they ACTIVATE their stone to get
    boosts. The boost works to its full potential depending on the BOND LEVEL with the creature.
    Chiefs so far: **Beach Village**, **the Snowy Peaks**, **Mountain Base**, and the fourth
    thief of the Hidden Thieves (decision 42).
39. **Legendary beasts:** special encounters, some of them TACTICAL battles (the owner will say
    where). A legend may be CAUGHT, but legends do not accompany the hero (not party members):
    they can be called upon in SPECIAL BATTLES or in ONLINE play.
40. **The Deep Woods -- Eldroot:** Eldroot is found by going to the deepest part of the forest.
    To go through the forest the hero must first fight **Nyra** (placeholder name). Nyra teaches
    an OUT-OF-COMBAT move that destroys trees, needed to find the hidden boss. Eldroot can be
    caught (as a legend: decision 39).
41. **Out-of-combat (field) moves:** abilities used on the overworld to open the world -- the
    tree-destroying move (Nyra, decision 40) and the power to traverse the SEA (the Beach Village
    chief, decision 43).
42. **The Hidden Thieves:** the hero is lured into following someone who appears to need help.
    Follow them far enough and the trap springs: the hero must fight **3 thieves in a row** who
    use CHAINS to command their creatures. Then the **4th thief** (on the level of a chief)
    honors the hero, HEALS them, and battles them with their BONDED ally -- no chains and, of
    course, no shard.
43. **Beach Village:** another chief; beating them grants the power to traverse the sea.
44. **The Island of Tides:** reached by learning HINTS from the other island villages on how to
    get there -- e.g. when it is RAINING and at NIGHT, going into a WHIRLPOOL brings the hero to
    the island, to face another legend deep in its cave.
45. **The Snowy Peaks** have another chief. **Mountain Base** has another chief.
46. **The secret enemy base:** near the Redrock badlands and "Bedrock Village" the hero hears
    rumors of weird sightings and a cave. Going to the cave reveals a secret base where the enemy
    hides -- another TACTICAL battle.
47. **Main quest:** ultimately to JOIN THE ARMY AT THE MOUNTAIN PASS. Before all-out war
    escalates, the hero learns of a secret THIRD PARTY: a corrupt ADVISOR with mind-control powers
    similar to the asteroid beast's, who wants to capture the beast to amplify his own powers. The
    hero must CAPTURE the beast and defeat them to prevent an all-out war. (Refines 18-20.)
48. **Side quests and more main quests** are still to be designed (owner: "there is still more we
    want to explore").

**Owner idea, not yet decided:** the legend beats could be about capturing EXCEPTIONAL
stones/shards that the enemy seeks, to create powerful chains to subjugate the original beast.

**Open questions (for the owner):**
- 38: chiefs bond without stones, yet activate a stone for the boost -- is the stone a different
  kind (a boost stone, not a bonding shard)? Can the HERO earn the same boost (scaled by the
  hero's bond level), e.g. as a reward for beating a chief? How is bond level raised?
- 39: in "special battles", is the legend a unit the hero summons onto the field, or one the hero
  fields instead of the party? Online: a pickable unit once caught?
- 46: "Bedrock Village" is not on the world map (Redrock Village is). A new place, or Redrock?
  Is the cave the map's "Hidden Depths", or a new location in the badlands?
- 47 vs 24: decision 24 offered an ending choice (capture / free / befriend the old way). Is
  capture now THE ending, or still one of the choices?
- 47 vs 19-20: is the advisor the head of the hidden dark organization, or is the organization
  dropped? Is the enemy nation still framed?
- 36 vs 21: is the General the soldier from the opening (Rowan), who becomes the recurring
  general?

### More from the owner (2026-10-04, later)
49. **Frostpeak Village -- the sleep:** the whole town can be made to SLEEP by two MYTHICAL
    creatures -- one who causes NIGHTMARES and one who causes DREAMS -- who play and fight each
    other. The hero must save the town. In the sleep the hero fights the DISORIENTED CHIEF, who
    believes the hero may have caused it; after that, a TACTICAL battle against the two creatures.
    (Frostpeak sits under the Snowy Peaks: this is the Snowy Peaks chief of decision 45.)
50. **Chief battles are regular Pokemon-style battles** (duels), not tactical boards.
51. **Shard testers:** the hero meets a few STRONGER people who battle with shards/stones, because
    the professor had been passing them out as tests to see how people bond. They can be the
    hero's RIVALS and ALLIES.
52. **The ceremony has company:** others can also be there when the hero receives their creature
    and stone (fellow testers -- see 51).

**Open questions (later batch):**
- 49: are the two mythical creatures legends under decision 39 (catchable, called upon in special
  battles), and is either (or both) catchable after the tactical battle?
- 51: is the existing rival (Lark, "a tester from the first batch") one of these testers? How many
  testers, and which become allies (guests in battles? recruitable humans, decision 6)?

### Owner answers (2026-10-04, later still)
53. **The General is General Varden** (placeholder name): the General the hero meets in burned
    Oakvale (decision 36).
54. **Humans are playable units**, the hero and other humans alike, working like creatures do but
    with a more traditional Fire Emblem moveset: an ATTACK WITH A WEAPON. Some characters are
    ENHANCED and have more special moves. HUMANS CAN BOND TO CREATURES. (Builds on 5-8.)
55. **The mother's death is a forced story beat**: the hero must learn of it as part of the story
    (it plays on arrival in burned Oakvale, not only if the player talks to someone).
56. **The testers (51) become RIVALS and ALLIES** the hero runs into across the region and can
    battle. E.g. one in **Deepwood Village** accompanies the hero for the tactical battle there and
    becomes a SELECTABLE UNIT TO DEPLOY; another is in **Beach Village**.
57. **The secret enemy base (46):** there the hero can encounter the General, or the General's
    SECOND IN COMMAND, who have been tracking the place down.

### Owner answers to the open questions (2026-10-04) -- these close the lists above
Not everything has to be decided: undecided things are built as flexible data / placeholders, not
asked about. An earlier decision stands unless the owner changes it.

58. **No separate Sergeant Rowan:** he is MERGED INTO General Varden (53). Varden is the recurring
    general of 21 / 25.
59. **The Warrior is Talyn** (placeholder name), female.
60. **The two testers at the ceremony** (present during the kidnapping) are the main RIVALS and
    ALLIES: friendly rivals who challenge the hero to test each other, not to harm. Other testers
    may be spread across the region. The **Deepwood Village** and **Beach Village** testers of 56
    are these two.
61. **Joining:** the main rivals/allies are TEMPORARY joins, and they join for the FINAL BATTLES.
    Other testers or characters can join the party PERMANENTLY.
62. **The villain (unchanged, 19-20 / 47):** the corrupt advisor is ADVISOR TO THE KING of the
    enemy nation, heads the hidden dark organization, and wants the all-out war.
63. **Human weapons and classes, Fire Emblem style:** some characters can SWAP weapons / classes;
    some have a natural TENDENCY toward one weapon or class.
64. **Enhanced humans (54):** chiefs are enhanced by default; the hero becomes enhanced through
    PROMOTION.
65. **Human-creature bond (54):** a human bonded to a creature can ACTIVATE it for a stat bonus or
    special bonuses (the bonuses are defined later).
66. **Hero falls = game over;** the story resets to before that fight (as already decided, like
    other games).
67. **The chiefs' stone is the SAME stone** (38): chiefs were also asked to test it, but don't
    really use it unless forced -- they use it with their FINAL creature in the battle against the
    hero.
68. **Bond level:** the hero bonds with creatures by FIGHTING ALONGSIDE them. Bond is a LEVEL
    system with a MAX.
69. **Frostpeak (49):** both mythical creatures can be caught.
70. **Legend beats** are built around EXCEPTIONAL stones/shards the enemy seeks, to forge chains
    strong enough to subjugate the original beast (the idea under 48, now adopted).
71. **Field moves (41):** certain creatures can learn them, possibly the hero as well -- like HMs.
72. **Time of day** (for the Island of Tides' night + rain, 44) is an IN-GAME clock.
73. **"Bedrock Village" is Redrock Village;** the secret enemy base (46) is in a NEW location
    near it (not the map's Hidden Depths).
74. **Legend battles are the TACTICAL battles** (39): Eldroot's (40) is one, and the Deepwood
    tester joins the hero for it as a deployable unit.
75. **Catching legends is optional** -- as in Pokemon, the hero never has to capture one.
76. **Progression:** some linear progression and some scaling, never forcing one path -- e.g. going
    straight to Mountain Base meets creatures too powerful to get past. Needs a level-up / stat
    system (design proposal in progress).
77. **Starters stay placeholders;** build around them.
- Still undecided by design (build flexibly, don't ask): which towns have chiefs beyond those
  named; how legends are called upon in special battles and in online play (not implemented yet).
78. **Bond / catch difficulty varies by species:** some creatures are EASIER to bond with / catch,
    which is why more random characters have some creatures -- but they are less likely to have
    POWERFUL ones. Those people are usually NEW SHARD USERS, or CHAIN USERS if they are villains.
    (A per-species bond/catch rate on the creature data; it also guides which creatures ordinary
    trainers and grunts field.)

### Progression (owner, 2026-10-04) -- spec: docs/design/PROGRESSION.md
79. **Anti-grind XP:** less XP for beating enemies at a lower level than the member, or near it;
    more for a stronger enemy. Max level: 50 (a tuning knob).
80. **Chiefs SCALE** to the hero's progress (within their region's band), so they can be taken in
    any order.
81. **Legends do NOT scale:** they are stronger than the base levels around their area, to offer a
    challenge.
82. **Evolution may be triggered by different triggers** -- to be discussed later. Level is added as
    one more trigger kind; nothing is migrated.

### The cast, from the owner's reference sheets (2026-10-04) -- docs/design/characters/README.md
83. **The villains:** **Varrick Silas** is the enemy advisor (#62). The **Shadow Assassin** and
    **Kellan** are two of Varrick's main enforcers.
84. **Varden's side:** **Talyn** is General Varden's ally.
85. **The chiefs:** **Nyra** is the Deepwood chief (forest); **Eloi** the sea chief (Beach Village);
    **Saevi** the winter chief (Frostpeak); **Kazren** the mountain chief (Mountain Base).
86. **The rivals / allies:** **Lyra** is a rival and ally; **Cael** is the other, a friend and ally
    -- the two testers of #60 (Professor Elias' students, per their sheets).
- The sheets are the characters' profile art (cropped portraits in game/ui/portraits/) and the
  reference for their models.
87. **Vayne, the King of Thieves,** is the chief of the Hidden Thieves: the 4th thief of #42 (on the
    level of a chief; honors and heals the hero, then battles with his bonded ally, no chains, no
    shard). Sheet: docs/design/characters/vayne.webp.
88. **Lyra is met in Deepwood Village** (she joins the hero for the Eldroot legend battle as a
    deployable unit, #56 / #74); **Cael is met in Beach Village.**
89. **Lark is merged into Lyra:** no separate rival named Lark.
90. **The generic thief** (docs/design/characters/thief.webp): the look of ordinary thieves, e.g. the
    Hidden Thieves gang; variations can indicate region or faction.
91. **"Enhanced" is design flavor, not a mechanic** (clarifies #54 / #64): no flag or rule -- an
    "enhanced" character is one whose authored moveset includes special moves beyond the weapon
    attack (chiefs are authored that way; the hero gets them through promotion, i.e. the promoted
    form's moveset).

### The Deep Woods, refined (owner, 2026-10-09)
92. **Nyra teaches a special move** (not used in battle) that cuts down trees outside battle. It is
    LEARNED by specific creatures or humans (refines #40 / #71: a member learns it, like an HM).
93. **The Deep Woods are a MAZE** that requires the new skill -- think Zelda's Lost Woods and a
    Pokemon forest. At the end, in the clearing, is the battle: Eldroot is there.
94. **The rival in Deepwood Village challenges the hero**, then ACCOMPANIES the hero through the Deep
    Woods: not an overworld character while following, but selectable in the Eldroot battle (#88).
