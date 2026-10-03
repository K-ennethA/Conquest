# STORY — Conquest's story mode: world, cast, opening, acts, and the systems they need

The owner's story, organised so it can be built. **`docs/design/DECISIONS.md` is the source of
truth and wins over this file.** Companion docs: `OVERWORLD.md` (walking, scripts, battle round
trip), `DUEL_BATTLE.md` (1v1 duels), `EVOLUTION.md` (Growth, forms), `docs/STORY_MODE.md` (what is
built today).

**Legend.** **[D12]** = owner decision #12 (fixed). **(proposed)** = my suggestion where the
decisions are silent; accept, change or drop it. **OPEN** = the owner still has to choose. Every name
marked † is a working name and can be renamed freely. **Oakvale**, **Crownhaven** and **the
Mossway** are fixed (another agent is building them).

---

## 0. The story in one paragraph

An asteroid struck the world long ago, and people and creatures alike learned to wield elemental
power [D12]. For generations creatures were bound by force with shard chains, and only a few
befriended them the slow way [D17]. Now a researcher's **bonding shard** lets almost anyone forge
a safe bond [D13]. On the day a villager from **Oakvale** receives a first creature in
**Crownhaven**, raiders in an enemy nation's colours abduct the researcher, burn Oakvale, and
kill the hero's mother [D14]. A soldier gives the hero the chance to fight back [D15] and becomes
the general the hero keeps meeting [D21, D25]. The trail leads past the framed nation to a hidden
dark organization [D19, D20] that chains creatures [D22] and wants the **fallen creature** that
came down with the asteroid [D18]. The hero has to stop the war [D20] and face that creature
[D24].

### Names at a glance

| Role | Name | Status |
|---|---|---|
| Hero's village | **Oakvale** | fixed |
| Castle city / capital | **Crownhaven** | fixed |
| Route between them | **the Mossway** | fixed |
| The kingdom | **Aldermere** | † |
| The enemy nation | **Cindral** | † |
| The dark organization | **the Gloam** | † |
| The hero | player-named, default **Wren** | † |
| The hero's mother | **Briony** | † |
| The lead researcher (the Royal Researcher) | **Professor Elias** | † |
| The soldier who becomes the general | **Rowan** (Sergeant at the start, then Captain, then General) | † |
| The fallen creature (a boss, so a multi-word title is allowed) | **Astrael, the Fallen Star** | † |
| The asteroid / its crater | **the Starfall** / **the Shardscar** | † |
| Raw shard material | **starstone** (the Gloam's refined kind is *blackstone*) | † |
| The old-way bonders | **the Grovewardens** | † |

Non-boss units keep one-word names (CONQUEST.md). Human units are unique people, so their unit
name is the person's name ("Rowan"), and the class is a subtitle (see §6.6).

---

## 1. Premise and world

### 1.1 History (proposed chronology inside D12 and D17)

| Era | What happened |
|---|---|
| **The Starfall** | The asteroid struck, and people and creatures alike gained elemental power [D12]. (Proposed) Its crater, **the Shardscar**, lies in the dark borderland both Aldermere and Cindral claim, with **starstone** scattered around it. **Astrael** came down with it [D18] and sleeps there. |
| **The Chain Age** | Nations bound creatures by force with **shard chains** of forged starstone [D17]. Armies were built that way, and it is why common folk still fear creatures. |
| **The old way** | A few good people befriended creatures with no shard, by trial and error [D17]: the **Grovewardens**, fewer every year [D23]. |
| **Now** | Elias's **bonding shard** makes a safe bond possible for almost anyone [D13, D17]. Only testers and some army units have one [D13]. That scarcity is why few people have creatures, and why the shards are worth stealing. |

**(Proposed late reveal)** The shards are cut from the purest starstone, which resonates with
Astrael. That is why they bond, and why the Gloam needs Elias: his method could make a shard
strong enough to bind the fallen creature.

### 1.2 The fallen creature (Astrael)
- Crashed with the asteroid; wields shard magic directly, with dominion over lesser creatures and
  possibly humans [D18].
- (Proposed) Not evil, just vast. Its dominion runs through starstone, so **shard-bonded creatures
  can be seized by it and old-way bonds cannot**, which ties D23 to the finale [D24]. Its restless
  sleep is why the Duskmire (§5) is dark.

---

## 2. Factions and key characters

### 2.1 The hero (Wren †)
- A human villager from Oakvale [D14]: the overworld avatar [D4] and a **human battle unit**
  who fights alongside creatures [D7].
- Promotes by class [D8], which needs an item or a location as well as Growth [D16].
  (Proposed: **Wayfarer**, then either **Warden** at the Grovewarden lodge with the *Warden's
  Crest*, or **Knight** at the Crownhaven barracks with *Rowan's Insignia*: the old way or the
  army's way.)
- (Proposed) Elias picks ordinary villagers as testers on purpose, to prove almost anyone can
  bond [D17].

### 2.2 Briony †, the mother
- Killed when the raiders burn Oakvale: collateral damage, not a personal act [D14].
- (Proposed) That morning she gives the hero her keepsake, the existing **Heartwood Charm**. She
  is a little afraid of creatures, like most people after the Chain Age. Her last words point
  toward kindness rather than revenge, which plants the old way in the hero before any
  Grovewarden appears.

### 2.3 Professor Elias †, the Royal Researcher
- (Owner, 2026-10-03; DECISIONS.md "The researcher and the starter") The Royal Researcher (magic /
  history / science), 60+, he/him, wise, calm, intelligent, wears glasses; a longtime friend of the
  hero's mother and a family friend. Reference sheet: `docs/design/characters/professor_elias.webp`.
- Inventor of the bonding shard [D13], abducted during the hero's visit [D14].
- (Proposed) Rescued at the end of Act 2. He joins as a human support unit and upgrades your
  shards (§6.4).

### 2.4 Rowan †, the soldier who becomes the general [D15, D21, D25]

| When | Rank | What Rowan does |
|---|---|---|
| Prologue | Sergeant | Checks papers on the Mossway. Shields the hero in the raid. Offers the chance to fight [D15]. |
| Act 1 | Captain | Pursues the raiders and fights beside you as a **guest**. Wary of a civilian with a shard. |
| Act 2 | General | Holds Fort Brannock and carries out the Crown's reprisals. Clashes with the hero over Kesh, a Cindral prisoner. By the book [D25]. |
| Act 3 | General | Sees proof that **his own nation is being manipulated** (the orders came from a Gloam agent at court). Sides with the hero [D25] and joins for good. |

Rowan is never a villain: decent, rigid, loyal to the wrong chain of command.

### 2.5 Cindral †, the enemy nation
- Takes the blame for the raid [D20]. (Proposed) Its bordermen still keep chained creatures, so
  chained raiders **look** Cindrali, and the frame is easy to sell.
- (Proposed) **Framed at the top, controlled at the edges:** Cindral's crown knew nothing; one
  border warlord, **Varg** †, is Gloam-held; the raiders were Gloam agents in Cindral colours.
  This covers both readings of D20.
- Recruit: **Kesh** †, a Cindral scout who knows the raiders' company does not exist (Act 2).

### 2.6 The Gloam †, the hidden dark organization [D19, D20, D22]
- **Goal:** capture Astrael [D19] and, through its dominion, command every shard-bonded creature.
- **Methods (proposed):** masks (fighting in Cindral colours); agents in both courts
  (**Chancellor Vesk** †, Crownhaven's war-hawk adviser, and the warlord Varg); long patience (the
  chain on Eldroot, §4, is years old); and chains of *blackstone*, a refined starstone no nation
  makes, which is the physical clue.
- **Shard chains [D22]:** every Gloam creature is chained, a forced bond, shown as a *Chained*
  status and visible dark-crystal links. **Breaking the chain in battle frees the creature, and a
  freed creature can be caught.** You don't kill the villain's creatures; you set them free
  (rules in §6.8).
- **Mortis and the Dark units: OPEN [D19]. Two options:**

| | **A. Mortis is a Gloam lieutenant** | **B. Mortis is independent** |
|---|---|---|
| Who | The Gloam's gravecaller and the face of the organization for most of the game. He appears in Act 2 and is fought as a boss. | A Duskmire hermit who binds the dead. The Gloam hunts him because he knows the Shardscar. He can be recruited in Act 3. |
| Undead | What a shard chain leaves behind: creatures chained until they died, still bound. They are chained enemies that cannot be freed, only laid to rest. | The dead Mortis keeps from wandering. They are neutral wild creatures in the Duskmire. |
| Duskmaw | An ordinary wild dark creature, catchable. Dark is not the same as evil. | The same. |
| Pro | Gives the Gloam a person the player can hate, with existing content. | More moral colour. Dark stays fully morally neutral. |

**Recommendation: A**, with Duskmaw neutral and wild, so the dark *element* is never simply "the
bad guys".

### 2.7 The Grovewardens, the old-way bonders [D23]
- Mentors and recruitable humans whose creatures are special because the bond is shard-free
  [D23]. Proposed: a **Heartbond** trait, immune to chains and to Astrael's dominion, plus a small
  bonus (for example +1 Growth per win).
- **Sorrel** † (Act 1): a forest hermit with a Heartbonded **Vineweave**. Tests the hero in a
  duel, then teaches and joins.
- **Garrow** † (Act 2): a Quarryhold miner with a Heartbonded **Geode** of forty years.
- (Proposed) The hero can earn old-way bonds too (§6.9), which gates the old-way ending.

---

## 3. The opening, beat by beat

The battle types are **Duel** (turn-based, no movement; humans fight alongside creatures [D7]) and
**Tactical** (the grid board). Flags follow the existing `quest.*` / `trainer.*` style.

| # | Beat | Location | Characters | What the player does | Battle | Flags set |
|---|---|---|---|---|---|---|
| 1 | **Village morning** | Oakvale | Hero, Briony, villagers (the existing slice cast can be recast) | Chores; Briony gives the Heartwood Charm. **Optional spar with Bram** (human vs human) teaches duels [D7]. | Optional **duel** | `story.prologue.started`, `spar.bram.won` |
| 2 | **The Mossway** | the Mossway | Hero, Sergeant Rowan | Walks to the capital. Wild creatures are visible, but encounters stay **off** until the hero has a shard. Rowan checks the hero's summons. | none | `met.rowan` |
| 3 | **Crownhaven** | Crownhaven, the Royal Shardworks | Elias, other testers | Explores the city. Elias: almost anyone can bond [D17]. | none | `met.elias` |
| 4 | **First creature + shard** | Shardworks | Elias | Bonds with the **starter** (see below) in a short guided scene. | none | `party.starter`, `story.has_shard` |
| 5 | **The abduction** | Shardworks, streets | Raiders in Cindral colours, **chained** creatures [D22], Rowan | Rowan shoves the hero clear. Elias is taken with a crate of shards. | none (cutscene) | `story.elias_taken` |
| 6 | **Raiders flee toward Oakvale** | the Mossway, smoking | Hero, Rowan's squad | Runs home. Grass encounters switch **on**. | optional wild **duel** | `story.prologue.pursuit` |
| 7 | **Oakvale destroyed; mother killed** | Oakvale (burned variant) | Hero, Briony, survivors | Finds Briony; her last words. The village burned to slow pursuit: war, not personal [D14]. | none | `oakvale.burned`, `story.briony_lost` |
| 8 | **Rowan's offer** | Oakvale outskirts | Rowan | *"Their rearguard's still on the far road. I can't order you. I won't stop you."* A choice; "Not yet" keeps the offer open. | none | `story.accepted_fight` |
| 9 | **FIRST FIGHT** | Oakvale's far road | Hero + starter vs raider + chained creature | The hero fights **alongside** the starter [D7, D15]; Rowan holds off the rest. At low HP the creature's **chain breaks** and it flees, free. | **Duel** (story-critical, retry on loss) | `trainer.raider_rearguard.defeated`, `seen.chain_break` |
| 10 | **Aftermath / hook** | Oakvale ruins, then Crownhaven | Rowan, the Crown's steward | The raider's chain is **blackstone**; only the player notices. The Crown blames Cindral and musters. The hero is named a **Shardbearer** and sent after the raiders. Survivors move to Crownhaven (the hub). | none | `quest.find_elias`, `clue.blackstone` |

**First-fight format.** Ideal: a *tandem* duel, with hero and starter on the field together
(§6.7). Until then, a **party duel** (the hero leads, the starter switches in), or as a stopgap a
tiny **tactical** board (hero, starter and Rowan as a guest vs 2 raiders and 1 chained creature,
Eliminate All), which the engine supports today.

**Starter creature (owner, 2026-10-03): the hero CHOOSES a starter; the starter roster is TBD.**
The build offers placeholder options (existing roster units, `STARTER_OPTIONS` in
`build_story_content.gd`); `opening.starter_pick` records which one you took. Nothing else about
the starters is decided. The options table is kept for the record.

| Option | Pro | Con |
|---|---|---|
| One fixed starter (Barkling) | Barkling to Oakheart is the only finished 2-stage line; the existing Sprig content fits; the story is simpler | Less player ownership |
| **A choice** (owner's pick) | A classic hook, plus replay value | Needs more 2-stage base lines (nature is the only one that exists; fire and water barely have content) |

---

## 4. Act structure

### Overview

| Act | Title | Region | Goal | Ends when |
|---|---|---|---|---|
| Prologue | Ashes on the Mossway | the Greenwold (Oakvale, the Mossway, Crownhaven) | Get a creature; lose home | The hero is sent after the raiders |
| 1 | The Blighted Road | the Greenwold (the Forgotten Forest) | Follow the trail and meet the old way | Eldroot is freed from its chain; the trail turns to the mountains |
| 2 | The Stone Border | the Greyspine | Rescue Elias; the frame starts to crack | Elias is rescued; the Gloam is named; war is declared anyway |
| 3 | The Shardscar | the Duskmire | Stop the war; face Astrael | The ending choice |

**Act 1 (proposed: the Forgotten Forest campaign folded in).** The raiders cut through the dying
forest, and the four existing chapters become the act's spine (OVERWORLD §3.4). **Twist: Eldroot,
the Hollow Crown, is a chained guardian.** The Gloam chained it years ago, and the blight is
Eldroot draining the wood against its will, so the existing chapter text still reads true.
Beating Eldroot breaks the chain and ends the blight. The chain's age is the second clue.

**Act 2.** In the Greyspine's starstone mines, General Rowan carries out the Crown's reprisals.
Kesh swears the raiders' company does not exist, and Garrow shows what old-way bonds can do. Once
rescued, Elias reveals his captors wanted a shard that could bind "the one that fell", and names
**the Gloam**. Rowan calls it Cindral trickery, and Aldermere declares war.

**Act 3.** The armies mass on the Sundered Field. Vesk's letters to both courts, found in the
**Hollow Spire** †, turn Rowan [D25]. Together they hold the field until a Cindral envoy sees the
truth, and the war stops [D20]. Out of time, the Gloam starts its ritual and wakes Astrael.

**How the frame is uncovered:** the blackstone chain (prologue), a years-old chain on Eldroot
(Act 1), forged orders and Kesh's testimony (Act 2), Elias's account (Act 2), Vesk's letters
(Act 3).

### Key battles

Objective types are the ones the engine supports: **Eliminate All**, **Defeat Boss**, **Survive
N**, **Seize** (throne), **Destroy Base**, and Capture Base (Siege). `ProtectUnit` exists as a
class but has no string or story hook yet (§6). "Guest" means a temporary party member under the
player's control; there is no AI-allied faction today.

| # | Battle | Where | Type | Objective | Allies | Notes |
|---|---|---|---|---|---|---|
| P-1 | Yard spar (optional) | Oakvale | Duel | KO (spar) | none | Human vs human tutorial [D7] |
| P-2 | **Raiders' Rearguard** | Oakvale road | Duel | KO the raider side | Rowan (off-screen) | The first fight [D15]; first chain break |
| 1-1 | First catches | the Mossway, forest edge | Duel (wild) | Catch or KO | none | Shard catching tutorial [D10] |
| 1-2 | Rearguard at the Treeline | Forest edge | Tactical | Eliminate All | **Rowan (Captain, guest)** | First tactical battle; first fight beside Rowan |
| 1-3 | The Blighted Clearing (ch1) | Forest | Tactical | Eliminate All (existing map) | none | Existing intro and outro still fit |
| 1-4 | Sorrel's Trial | Sorrel's hollow | Duel | KO (spar) | none | Sorrel joins [D23]; the Heartbond is introduced |
| 1-5 | The Tainted Crossroads (ch2) | Forest | Tactical | **Survive 6** while Rowan's column crosses (proposed re-author; or keep Eliminate All) | Rowan (guest) | A chained test creature appears (free it, then catch it) |
| 1-6 | The Proving Grounds (ch3) | Deep forest | Tactical | **Seize** (the map has a THRONE marker) | Sorrel (guest if not recruited) | |
| 1-7 | Heart of the Forgotten Forest (ch4) | Heartwood | Tactical | **Defeat Boss**: Eldroot, chained | none | Break the chain; blight ends; `clue.old_chain` |
| 2-1 | Toll Thugs | Quarryhold road | Duel | KO | none | "Attacked by criminals" [D7] |
| 2-2 | Brannock Drill | Fort Brannock | Tactical | Eliminate All (sparring) | none | Rowan is now General; a by-the-book exercise |
| 2-3 | The Cindral Pass | Border pass | Tactical | **Destroy Base** (the "raider" camp) | Rowan (guest) | The camp's orders are forged; `clue.forged_orders` |
| 2-4 | Kesh | Pass cells | Duel | Subdue, then talk | none | Kesh joins; Rowan objects |
| 2-5 | Deepvein Rescue | the Mines | Tactical | **Seize** (the wardroom where Elias is held) | Kesh, Garrow | `story.elias_rescued` |
| 2-6 | The Gravecaller | Mine mouth | Tactical | **Defeat Boss** (Mortis, if option A) | none | The Gloam is named |
| 3-1 | Lanternmoor Night | Lanternmoor | Tactical | **Survive 5** (a Gloam raid on the town) | Elias | |
| 3-2 | The Hollow Spire | Gloam hideout | Tactical | **Seize** (the archive) | none | Vesk's letters; `clue.vesk` |
| 3-3 | **The Sundered Field** | Border | Tactical | **Protect** the Cindral envoy (needs the ProtectUnit hook; fallback: Survive 6) | **Rowan joins for good** | War averted [D20, D25] |
| 3-4 | The Binding | Shardscar rim | Tactical | **Destroy Base** (three ritual anchors) | Rowan | |
| 3-5 | **The Fallen Star** | Shardscar heart | Tactical | **Defeat Boss** (Astrael, a large boss) with a Dominion phase | Full party + Rowan | Then the ending choice (below) |

### The finale [D24] (proposed shape)
1. **Dominion.** At set thresholds Astrael turns your shard-bonded creatures against you (the
   existing Enthralled control status). **Heartbonded creatures and humans are immune.** You break
   its hold by shattering the dominion crystals, or by beating the controlled unit down to the
   subdue threshold.
2. **Ending choice.** At Astrael's last HP a short final **duel** begins, and the choice is your
   action:

| Choice | Proposed outcome |
|---|---|
| **Capture** (use a shard) | Astrael joins, sullen; shards keep working; the epilogue hints at the Gloam's temptation. |
| **Free** (break every tie) | Astrael returns to its sleep; shards dim, and from then on bonds are earned the old way. Bittersweet. |
| **Befriend it the old way** (lower your shard) | Needs old-way progress (§6.9). Astrael joins willingly and its dominion ends. **The true ending.** |

---

## 5. World map

### 5.1 Launch regions (these match the existing content: nature, earth, dark)

| Region | Element | Towns and places | Routes | Wild habitats (existing species) | Human recruits |
|---|---|---|---|---|---|
| **The Greenwold** † | Nature | **Oakvale** (a ruin after the prologue), **Crownhaven** (hub and capital), Thornwick † (forest town), Sorrel's hollow, the Grovewarden lodge, the Blighted Clearing, the Tainted Crossroads, the Proving Grounds, the Heartwood | **the Mossway**, the Treeline Path †, the Blight Road † | Barkling (common), Petalfang (meadow), Blightcap (blighted zones only; they thin out after 1-7), Mycothrall (deep forest, rare) | Bram (Warden-apprentice, optional), **Sorrel** |
| **The Greyspine** † | Earth | Quarryhold † (mining town), Fort Brannock † (army), the Cindral Pass, the Deepvein Mines | the Switchback †, the Quarry Road † | Geode (mines, rare); Bastion (proposed as story-only: the living gatehouse of Fort Brannock); **new earth species needed** (at least 2 common) | **Garrow**, **Kesh** |
| **The Duskmire** † | Dark | Lanternmoor † (a lamplit stilt village), the Hollow Spire, the Sundered Field, **the Shardscar** | the Fenwalk †, the Crater Rim † | Duskmaw (night fen), Mycothrall (rot), Undead (option A: chained remnants, not catchable; option B: wild) | **Elias**, **Rowan** (permanent), Mortis (option B only) |

### 5.2 Later regions (not for launch)

| Region | Element | Hook |
|---|---|---|
| The Cinderlands † (Cindral's homeland) | Fire | A post-war peace mission; face Varg |
| The Saltreach † (coast) | Water | Shard trade routes; sea creatures |
| The Highwinds † | Wind | The Grovewardens' oldest lodge |
| The Starfall Sanctum † | Holy | Post-game: what Astrael *is* |

**Content note (proposed):** the Gloam should field **chained fire creatures** to sell the Cindral
frame. Until fire species exist, the raiders use chained nature and dark creatures, and the
frame rests on the colours and the chains.

### 5.3 Slice changes to note
OVERWORLD §4.9 planned "Oakvale, then the Mossway, then the Blighted Clearing". With Crownhaven at
the far end of the Mossway, the **Forest Edge / Blighted Clearing lies beyond Oakvale on the other
side** (proposed). The existing `StoryRuleset.starting_party` (`vineweave`, `blightcap`) becomes
**the hero alone**; the starter joins in beat 4.

---

## 6. Systems the story needs, as buildable milestones

Sizes: **S** is about a day, **M** a few days, **L** a week or more.

| # | System | What exists | What's new | Depends on | Size |
|---|---|---|---|---|---|
| 6.1 | **Unit `kind`** (HUMAN / CREATURE) [D5] | `CharacterResource`, Compendium, squad-select cards | A `kind` enum field; a badge on the Compendium and squad cards; a `kind` set on all 12 roster units (proposed: Mortis is HUMAN, everyone else CREATURE, Eldroot a CREATURE boss); a validator | none | **S** |
| 6.2 | **The human hero as a battle unit** [D4, D7] | `HeroResource` (overworld model, currently a Vineweave placeholder), `StoryPartyMember` | A hero `CharacterResource` (`hero_wayfarer`, HUMAN) referenced from `HeroResource` (the model swap stays in one place); an `is_hero` party record that can never be released; fielding rules (may sit out a tactical battle; a hero KO is a game over only when a battle says so) | 6.1 | **M** |
| 6.3 | **Recruiting humans** [D6] | `JoinPartyCommand`, flags, `story_critical` | A one-of-each guard (a unique human can't be duplicated); a validator that keeps humans out of every encounter table; **guest members** (temporary, `guest_until` flag, used for Rowan before Act 3) | 6.1 | **S–M** |
| 6.4 | **Active shard catching in duels** [D10, D13] | Befriend roll on `DuelRuleset` (`befriend_base_chance`, `befriend_subdue_bonus`), seeded `befriend_rng`, the Subdue effect, `BefriendPromptCommand`, flee costing the turn | A **CATCH** duel command (a miss costs the turn); **shard items** (proposed: consumable, tiers Rough / Cut / Flawless). Chance = `clamp(tier_base × (1 + hp_weight × (1 − hp/max_hp)) + subdue_bonus + status_bonus[status] − species_resist, 0, cap)`, every term a ruleset knob, rolled from the seeded stream. Wild, unchained creatures only; never humans or bosses unless flagged. The post-win offer stays for story-critical recruits only. | Duel items / `USE_ITEM` (an M2 gap), 6.1 | **M–L** |
| 6.5 | **Individual variation** [D11] | Nothing (a `growth` payload on the member record round-trips unknown keys) | Rolled at the catch (seeded) and stored on the member: **temperament** (about 8, a ±10% stat lean, shown on the card), hidden **potential** (small per-stat variance), a rare **variant** (`VariantResource`: palette, or an element override plus one move swap). Applied at spawn on a *duplicated* resource (rule 7). Separate from `SkinLibrary` skins. | 6.4 | **M** |
| 6.6 | **Class promotion** [D8, D16] | `EvolutionResource`, `GrowthTrigger`, `StoryFlagTrigger`; `CatalystTrigger` / `AllTrigger` are planned (EVOLUTION M3) | Build `CatalystTrigger` + `AllTrigger`; a new `LocationTrigger` (reads the ctx `area_id` / `place_id`); a validator rule that a HUMAN edge needs Growth **plus** an item or a location; a "Promote" script command for trainer NPCs; a `class_title` on human forms (the name stays "Rowan", the subtitle changes from "Sergeant" to "General") | 6.1 | **S–M** |
| 6.7 | **Mixed human + creature duel parties** [D3, D7] | `DuelRuleset.party_size` knob; strict 1v1 today | M2: party duels (bench, switch, KO-replacement), so the hero leads and a creature switches in. M3 (proposed): a **tandem** format (`active_per_side = 2`), with human and creature on the field *together* | 6.2 | **M** (party), **L** (tandem) |
| 6.8 | **Shard-chained enemy creatures** [D22] | Status system (authored `clock`), Subdue, `EnthralledStatus` (control) | A `chained` status (pinned clock, not cleansable) with chain VFX to its handler: a small power boost, not catchable. **Break** at the subdue threshold (≤ 25% HP, a knob) or with a **Sever** move (the hero and Heartbonded creatures have it). In a duel the freed creature becomes catchable while its handler fights on; in a tactical battle it leaves the board and is flagged to reappear as a catchable encounter. | 6.4 | **M–L** |
| 6.9 | **Old-way bonds (Heartbond)** [D23, D24] | Member record | A `heartbond` trait for members who joined without a shard: immune to chains and Dominion, plus a small bonus. (Proposed) The hero earns one for a creature through a Grovewarden trial or N battles together without a KO. The count gates the old-way ending. | 6.1 | **S** |
| 6.10 | **Per-region encounter tables** [D9] | `EncounterZone` / `EncounterEntry`, deterministic `EncounterRoller`, grace steps | A `RegionEncounterTable` resource (species, weight, strength band, time and weather conditions, variant rate), which zones reference; habitat tags; encounters switch on with `story.has_shard` | 6.1, 6.5 | **S–M** |
| 6.11 | **Protect objective in story** | The `ProtectUnit` class, `ObjectiveText` | A `BattleSpec` field naming the protected spawn (it can't be string-parsed), for battle 3-3 | none | **S** |
| 6.12 | **Dominion (finale)** [D24] | `EnthralledStatus`, boss phases | A boss ability that enthralls shard-bonded player creatures (never Heartbond or humans); "dominion crystal" props as targets that break it | 6.8, 6.9 | **M** |
| 6.13 | **Area state variants** | Area flags, `persist_move` | A burned **Oakvale** variant chosen by `oakvale.burned` (terrain and props swap) | none | **S–M** |

**Suggested build order:** 6.1, then 6.2 and 6.3 (the prologue can be played), then 6.7 party
duels and 6.10, then 6.4 and 6.8 (Act 1's core loop), then 6.5, 6.6 and 6.9, then 6.11 and 6.12
(Act 3), with 6.13 whenever the prologue content lands.

---

## 7. Open questions for the owner

1. **Starter roster.** ANSWERED in part (owner, 2026-10-03): the hero chooses a starter. Still
   open: which creatures (and how many) are offered -- the build uses placeholders.
2. **Mortis and the Dark units [D19]:** A (a Gloam lieutenant; Undead are dead chained creatures)
   or B (an independent gravecaller who can be recruited)? Recommendation: **A**, with Duskmaw
   wild and neutral.
3. **How is Cindral blamed [D20], and how is Rowan's nation manipulated [D25]?** Recommendation:
   *framed at the top, controlled at the edges*. Cindral's crown is innocent, one warlord (Varg)
   is Gloam-held, and a Gloam agent at Crownhaven's court (Chancellor Vesk) gives the orders Rowan
   follows.
4. **Ending structure [D24]:** three real endings, or one canonical ending with flavour?
   Recommendation: three endings, with **befriend the old way** as the true ending, gated by
   old-way bonds.
5. **Bonding shards as items:** consumable with tiers, or one reusable shard? Recommendation:
   **consumable, in tiers**, scarce early and crafted later by Elias. That keeps the "rare
   technology" of D13 true in the gameplay.
6. **What does "alongside" mean in duels [D7]?** On the field together (a tandem duel), or in the
   same party with switching? Recommendation: party switching first (M2), then tandem for story
   set pieces, starting with the first fight.
7. **Army allies in tactical battles:** guest units the player controls, or an AI-allied faction?
   Recommendation: **guests**. AI allies need a third-faction system the engine does not have.
8. **The hero's identity:** a fixed name and look, or player-named with a choice of look?
   Recommendation: player-named (default **Wren**) with one model at launch; a second body model
   later is a data swap in `HeroResource`.
