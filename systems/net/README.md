# systems/net — Network multiplayer

Network versus is built on ONE stack: Godot's scene-tree `multiplayer` API,
host-authoritative, 1v1, over a pluggable transport (ENet by default). The
host is either a **player** (listen server, seat 0) or a **dedicated headless
server** with no seat. Combat randomness is **commit-reveal**: no peer — the
host included — can know or bias a roll before the action that consumes it is
irrevocably accepted. Every peer re-validates and applies every accepted action
through ONE deterministic apply path and compares a state digest after each one.

This is the merge of two branches' work: the anti-cheat core (commit-reveal RNG,
validate-on-every-peer, digest checkpoints, dedicated server, transports) and the
game-facing features built on top of the earlier core (join build gate, lobby
channel + collaborative lobby, squad / item / skin replication, forfeit, rejection
toasts, apply-side ultimates and cooldown booking, replays, dev auto-join).

## Pieces

| File | Role |
|---|---|
| `NetSession.gd` (class `NetSessionNode`, autoload `NetSession`) | Join handshake (build gate), lobby, peer→slot seating, the lobby message channel, intent queue, action ordering (seq), the commit-reveal rounds, checkpoints, disconnects / forfeit. Player-hosted (`host_game`) and dedicated (`host_dedicated`) modes share every code path. Also holds the per-battle **seam** (`install_command_seam`: the `CommandApplier` replays drive) and the solo RNG stream. Knows nothing about units. |
| `NetCommitReveal.gd` | Hash-chain commitments, share verification, epoch re-commit, per-action seed derivation. Pure (no networking), unit-tested. |
| `transport/NetTransport.gd`, `transport/ENetTransport.gd` | The only place a `MultiplayerPeer` is created. See *Adding a transport*. |
| `NetProtocol.gd` | Wire format: actions (`MOVE`, `USE_MOVE`, `WAIT`, `END_TURN`, `USE_ITEM`, `SWITCH`; the command-log names `MOVE_UNIT` / `CAST_MOVE` / `WAIT_UNIT` are aliases), builders, shape validation, THE cell (de)serialiser (`[col, row, floor]`, see docs/MULTI_FLOOR.md), `KEY_RNG` (locally stamped seed, never trusted from the wire), the join hello + `validate_hello` + `describe_rejection`, the `INTENT_*` rejection vocabulary + `describe_intent_rejection`, `PROTOCOL_VERSION`. |
| `NetGameRules.gd` | `validate_intent` (host; re-run by clients) and THE deterministic `apply_action` every peer runs — incl. replay recording, the ultimate cut-in announcement, cooldown / charge booking, canto hand-off; `state_digest` for desync detection. |
| `CommandApplier.gd` | `NetGameRules` bound to the live battle under the name the battle / replay code uses (`apply_command(cmd, board, ctx)`, `hash_match_state`). A subclass, never a second apply path. |
| `NetUnitIds.gd` | Stable unit ids (`"<slot>:<n>"`, mid-match arrivals `"<slot>:s<k>"`). |
| `MatchLoadouts.gd`, `MatchPeerInfo.gd` | Process-wide parking for the other participants' `match_loadout` (squad / items / skins, whitelisted) and `profile_info` (name / rank / points) cards, keyed by host-stamped slot. |
| `MatchRng.gd` | The SOLO / replay per-command stream (one local seed). Not used by network play. |
| `DedicatedServer.gd` | Headless server driver: args, lobby, match lifecycle, sequential matches, logs. |
| `systems/game_core/GameModeManager.gd` (autoload) | Live-game glue (match config → `GameSettings` incl. custom-map gate + squads, battle load, rules attach, `request_*` intents, opponent-left → victory, desync / cheat → menu message) and command-line boot of `--server` / `--net-bot`. |
| `menus/NetworkMultiplayerSetup.gd` | Host / join by address:port (a friend's game or a dedicated server): validation, remembered details, connect countdown, rejection text, LAN addresses; embeds the lobby. |
| `menus/CollaborativeLobby.gd` | The lobby: roster + ready, map votes / coin flip (player-hosted) or the leader's pick (dedicated), host match settings, profile + loadout exchange, the start. |
| `systems/multiplayer_launcher.gd` (autoload `MultiplayerLauncher`), `systems/AutoClientDetector.gd` | Dev two-instance auto-join (`-- --multiplayer-auto-join`) and the dev-gated "Host + Auto Client" spawner. |
| `dev_scripts/net_bot_client.gd`, `dev_scripts/net_multiprocess_check.sh` | Scripted headless client + the 3-process check (see *Testing*; `MODE=duel` for online duels). |
| `DuelNetConfig.gd`, `DuelNetRules.gd`, `game/duel/net/NetDuelStage.gd`, `menus/DuelLobby.gd` | ONLINE DUELS (see *Online duels*): the duel match config + its strict request builder, the rules object over a `DuelBattle`, the network-driven duel stage, the duel lobby. |
| `NetTurnClock.gd` | The online TURN CLOCK's presets (Rapid / Standard / Relaxed), budgets per kind (side / unit / duel action / duel KO pick), the anti-AFK default, config keys and the player-facing wording. Pure. The live clock is in `NetSession` (see *Turn clock*); the HUD is `game/ui/hud/TurnTimer.gd` (network mode) and `game/ui/hud/NetMatchBar.gd` (the duel's clock + Forfeit corner). |

## Flow

```
Join     client hello {name, PROTOCOL_VERSION, game version}  ->  host build gate
         (validate_hello): protocol mismatch -> join_rejected("version_mismatch", info);
         lobby full / match running -> "lobby_full" / "match_in_progress"; else seated.

Lobby    host_game(name, port)  |  host_dedicated(port, cfg, rng_mode)  |  join_game(addr, name, port)
         host seats peers (max 2); set_ready; lobby channel (votes, profile + loadout
         cards); config by the player-host, or on a dedicated server by --map /
         --turn-system (locked) or the slot-0 client (lobby leader).
         start_match(final_config): full + all ready, single-shot (a dedicated server
         auto-starts). The player-host's lobby passes its last word here: the voted
         map (+ its content if custom), host_squad, versus_rounds.

Commit   host: fresh secret chain, broadcast (contributors, chain length, host anchor)
         each contributing client: fresh chain -> its anchor -> host
         host: all anchors in -> match_started {config..., slots, anchors,
               seed = setup seed derived from the anchors}
         clients check their own + the host's anchor are the ones committed.
         GameModeManager (every peer): config -> GameSettings, load GameWorld.

Match    UI --request_*--> submit_intent --rpc--> host intent queue
         host (one intent at a time, only when no RNG round is in flight):
             validate_intent(action, sender's seat) -> rejected: intent_rejected(reason)
             accepted -> stamp {actor, seq}; broadcast ACCEPTED(action, host share)
         clients: verify the host share against the host chain; check an action
             in their own seat is the intent they sent; THEN reveal their share
         host: verify each share, relay ROUND(seq, shares) to everyone
         every peer: verify, seed = H(shares || seq), apply_action (<= 1 per frame;
             clients first re-validate it on their own state)
         host, next frame: checkpoint {seq, turn slot, digest} -> clients compare.

Clock    clients: battle attached -> GAME_ATTACHED -> host. Host, on a settled state once every
         seat is attached: a new timed turn (rules.clock_turn_key) -> CLOCK {key, slot, kind,
         budget_ms, remaining_ms, strikes, ...} to everyone; its deadline passed (+ grace) and
         the seat has no intent queued -> the rules' timeout_action, stamped timeout:true, goes
         through ACCEPT like any intent (or, on the Nth expiry in a row, CLOCK_FORFEIT(slot) +
         match_ended("clock_forfeit")). See *Turn clock*.
```

* **Actor is the sender's seat**, never a field of the payload.
* **Apply uses the local-play primitives** (`board.move_unit` + `GameEvents.unit_moved` +
  `mark_moved`; `Unit.perform_move` + `MovesetController.on_used` + `mark_action_completed`;
  `mark_unit_acted`; `end_turn_manually`). Hotseat / single-player keep their direct paths.
* **Turns** are derived: every peer runs the same turn system over the same
  applied actions; the host's checkpoint carries the authoritative active slot.
  (The earlier turn-ownership *bridge* is gone — the validator reads the rules' turn system.)
* **Leaving a live match is a loss.** A seat dropping mid-match raises `opponent_left`
  (then `match_aborted("opponent_disconnected" | "host_disconnected")`); a deliberate
  `forfeit_match()` is announced first on the lobby channel (`MSG_MATCH_FORFEIT` →
  `opponent_forfeited(slot)`, slot stamped by the host). The battle HUD
  (`UILayoutManager`) eliminates the absent side, so the one who stayed gets the normal
  victory screen; GameModeManager keeps the battle up and just drops the link. Before the
  battle is up (or on a dedicated server) an abort returns to the menu with a message. A
  dedicated server returns to an empty lobby for the next pair.

## Join handshake (the build gate)

The hello also names the LOBBY MODE the joiner came for (`NetProtocol.MODE_CONQUEST` /
`MODE_DUEL`, set on `NetSession.lobby_mode` by the Versus screen or `--mode`): a host running the
other mode refuses it with `mode_mismatch` ("That host is running a Duel lobby. Choose Online >
Versus > Duel to join it."), after the protocol check. The host stamps its mode into the match
config (`config.mode`), which is what GameModeManager dispatches on.

A joining client's **first** message is a hello — display name plus
`NetProtocol.PROTOCOL_VERSION` and `application/config/version`. The host runs the pure
`NetProtocol.validate_hello()` **before** the peer gets a roster slot:

- different `PROTOCOL_VERSION` → `join_rejected("version_mismatch", info)` on the client
  (`peer_join_refused` on the host), then the peer is dropped after a short flush;
  `NetProtocol.describe_rejection(reason, info)` is the line a menu shows;
  `last_join_rejection()` survives the disconnect.
- same protocol, different game version → admitted, `build_differs` logged
  (an editor run joining an exported build is a legitimate test setup).

Bump `PROTOCOL_VERSION` whenever the envelope or an action's data shape changes (2 = the
merged core, 3 = USE_ITEM, 4 = lobby modes + the online-duel config keys, 5 = used by two
parallel builds with different wire changes -- (a) the online turn clock: the `timeout` action
stamp, the clock / attach / clock-forfeit RPCs, the `turn_clock` / `afk_limit` config keys;
(b) party duels: the `SWITCH` action, `duel_format` / `duel_teams`, the team-carrying
`duel_pick` -- and 6 = both together plus party-aware duel timeouts (a timed-out KO replacement
pick is a `timeout`-stamped `SWITCH`). Replays stamp it too and refuse other versions.
Two-machine procedure:
`docs/NETWORK_TESTING.md`.

## Lobby channel

Pre-match traffic (map votes, ready flags, profile / loadout cards, the informational
game-start line, forfeits) is **not** part of the action vocabulary — it is never
validated, sequenced or RNG-stamped, and must never mutate battle state:

```gdscript
NetSession.lobby_message.connect(_on_lobby_message)   # (type, data, from_slot)
NetSession.send_lobby_message("map_vote", { "map_path": path })
```

The host relays; **the sender never receives its own message back**, so a lobby UI can
broadcast unconditionally. Only seated peers may send. Treat `data` as untrusted peer
input. (A player-host is a participant and receives relayed messages; a dedicated server
also sees them but has no lobby UI.)

## Match settings: whose squad is whose

A `player_id` on a map is a **roster slot**, and the same slot must field the same characters
on every machine. `MapLoader.resolve_player_squad(player_id, local_squad, replicated_squad,
local_slot, networked)` is the one rule that says which pick is authoritative:

| | `player_id == local_slot` | any other `player_id` |
|---|---|---|
| **not networked** | the local pick (player 0 only) | the map's authored roster |
| **networked** | the local pick | that slot's **replicated** pick |

Slot 0's pick rides the match config (`host_squad`, set from the player-host's lobby); every
other slot's pick rides its `match_loadout` card. Squads are untrusted input and normalised at
the boundary (`MapLoader.normalise_squad_ids`, `MatchLoadouts.normalise_squad` with a
`CharacterLibrary` whitelist). An empty squad means "field the map's authored roster" on every
peer. Squad-picked spawns are exempt from the per-peer `min_difficulty` gate.

**Without a loadout exchange every peer fields map rosters.** GameModeManager keeps the local
pick only when `MatchLoadouts.is_active()` and the host is not a dedicated server; otherwise it
clears the pick and `host_squad` on every peer (a seatless server runs no lobby UI and could
not know the clients' picks). Pinned by `tests/integration/test_net_host_squad.gd`,
`test_net_client_squad.gd` and `tests/unit/test_game_mode_manager.gd`.

**Custom / community maps** travel as content: the player-host puts `map_payload` in the
final config; every other peer strict-validates it and boots from its own installed copy
(`GameModeManager.resolve_boot_map` → `MapCatalog.install_session_payload`), or refuses the
match. Never a same-named local file.

**Offline-only maps.** Network versus seats two humans and runs **no AI** on any peer, so a map
that needs AI turns is never played online: one that fields units on player slot 2+ (an
AI-controlled neutral faction — Riftwood's jungle camps, King's Crossing's guardians; the mode
layer registers it as a third, AI player with its own turn) or that authors Siege creep
`lanes` (creep waves are AI-driven — only `BotTurnDriver` moves them). The one rule is
`MapCatalog.network_refusal(path)` (codes `NET_REFUSAL_*`, wording
`describe_network_refusal`; `network_eligible` is `network_refusal == ""`), applied at every
door: the lobby's map rows (disabled, tagged "Offline only", the reason as the tooltip), a
dedicated server's `--map` (refused at boot) and leader-config sanitiser (the pick is dropped,
the previous map kept), and `GameModeManager.apply_match_config` on every peer (the match is
refused with `offline_only_map`). Backstop: if the rules ever hand the turn to a slot no seat
occupies, the host ends the match with `NetSessionNode.ABORT_UNDRIVEN_TURN` instead of waiting
forever. Offline pickers still offer these maps exactly as before. Pinned by `tests/unit/test_net_offline_only_maps.gd`,
`tests/integration/test_net_undriven_turn.gd` and `test_net_dedicated.gd`.

## Squad, loadouts and skins: `match_loadout`

Equipped items are real buffs and skins change what a unit looks like, and both live in
process-local storage, so **both** machines need **both** sides' data before a unit spawns:

```gdscript
NetSession.send_lobby_message("match_loadout", {
    "squad":    ["<character_id>"],                   # this peer's pick, in order, MAX_SQUAD max
    "equipped": { "<character_id>": "<item_id>" },   # UNIT-scope items, per character
    "team":     ["<item_id>"],                        # TEAM slots, ItemInventory.TEAM_SLOTS max
    "skins":    { "<character_id>": "<skin_id>" },    # cosmetic skin per character
})
```

`CollaborativeLobby` sends one card per peer (host: on admitting the opponent; client:
alongside its `lobby_hello`); cards are parked in `MatchLoadouts` by host-stamped slot and
survive the scene change. `MatchLoadouts.set_local_slot()` switches replication on — solo /
hotseat / arena leave it unset. `ItemSystem` equips every human slot through one
`apply_loadout_items()`; `Unit.apply_equipped_skin` asks `MatchLoadouts.skin_for`.
State is cleared when a new lobby forms and when a non-networked battle builds its board
(`MapLoader._clear_stale_replication`). `MatchLoadouts.normalise()` whitelists every id
(library + scope + character), caps sizes; a hostile peer can only field fewer buffs than it
claimed. Pinned by `tests/unit/test_match_loadouts.gd`, `test_lobby_loadout_exchange.gd`.

## Online duels

DECISIONS.md #32: a DUEL is played over this same core. Menu: Online > Versus > Duel > Network
(host / join / a `--mode duel` dedicated server) -> `menus/DuelLobby.gd` (roster + ready, each
seat's TEAM, the host's / leader's format + stage + weather).

* **Formats** (`game/duel/DuelFormat.gd`, data): team size (1-6), active per side (1 = singles;
  doubles is refused until built), switching (costs the turn), KO replacement (the fainted
  unit's owner picks, free), item rules, species clause, strength cap. Presets **Singles 1v1**,
  **Trio 3v3** (a new player-host's default) and **Full 6v6**; anything else is custom. The
  format writes the party knobs onto a private copy of the `DuelRuleset` (rule 7 / rule 11).
* **Config** (`DuelNetConfig`): `mode: "duel"`, `duel_format` (`DuelFormat.to_dict`; absent =
  Singles), `duel_teams {slot: [character_id, ...]}` (lead first, exactly the team size),
  `duel_units {slot: lead}` (the Singles-era key, kept), `duel_stage`, `duel_weather`, plus the
  session's `seed`. The host / lobby leader (or `--duel-format singles|trio|full` on a dedicated
  server, which locks it) sets the format; each seat announces a team PREFERENCE list on the
  lobby channel (`duel_pick {character_id, team}`); the player-host's lobby, or the dedicated
  server (`auto_start_config`), folds both into the start trimmed / filled to the team size
  (`final_config` / `teams_for`: repeats dropped under the clause, gaps filled with the seat's
  defaults). The teams are per-match keys (`DuelNetConfig.PER_MATCH_KEYS`: never kept in a
  standing lobby config, taken even when a server's config is locked). Untrusted: `sanitize`
  whitelists, and `build_request` -- run on EVERY peer -- refuses an unreadable format, a team of
  the wrong size (`bad_team_size`), a repeat under the clause (`species_clause`), a unit that is
  not duel-eligible (`DuelMoveCompiler.is_duel_eligible`; humans and creatures alike) or an
  unknown stage / weather (the match ends with `duel_refused`). Missing picks fall back to each
  slot's default team. The offline-only-maps rule does not apply (no map).
* **The duel** is a VERSUS `DuelRequest` (both sides human, seed = the setup seed, so the speed
  tie-break / weather / opening ticks agree) on every peer. GameModeManager opens
  `NetDuelStage` (a `DuelStage` that never applies anything itself) and attaches `DuelNetRules`.
* **Validation** (`DuelNetRules.validate_intent`, host + every client): the duel is live and it is
  the sender's combatant's turn (the speed-order `DuelTurnSystem`; slot = side); `USE_MOVE` names
  the acting combatant, a slot `legal_slots` offers, aimed exactly where `DuelBrain.aim_for` aims;
  `WAIT` only while it must pass (stunned / controlled -- the seat's stage submits it by itself);
  `MOVE` / `END_TURN` / `USE_ITEM` are refused. **No items and no flee online**: an online duel
  carries no bag and cannot be run from (both are local / story actions).
* **Party intents** (`SWITCH {unit_id}` = the incoming member's `"<side>:<index>"` id). A
  voluntary switch needs the format's switching, the sender's own turn, a combatant free to act
  and one of the SENDER's benched, healthy members (`INTENT_NO_SWITCHING`, `INTENT_NOT_YOUR_UNIT`,
  `INTENT_ILLEGAL_SWITCH`). After a faint the fainted side's seat must send its KO replacement
  pick first -- any other action from it is `INTENT_MUST_PICK`, the other seat is
  `INTENT_NOT_YOUR_TURN` -- and `current_turn_slot()` names the picking side (side 0 first when
  both must). Same rule object as the local duel (`DuelBattle.switch_problem`).
* **Defaults**: `DuelNetRules.default_intent(slot)` is the seat's sensible legal default right
  now (the brain's replacement pick when one is pending, else its forced pass / first legal
  move) -- what a bot or stand-in plays. It is NOT the clock's timeout (see *Turn clock* below).
* **Apply**: `DuelBattle.apply_command` with the NetSession-stamped seq + commit-reveal seed (a
  kept canto move's follow-up WAIT applies inside the same call on every peer). `NetGameRules`
  hands a `SWITCH` to the board that owns the parties (`DuelBoard.apply_switch`: a benched member
  is by design not on the board); a tactical board has none. **Digest**: the board digest +
  round, decided flag, winner, command count, whose turn, and both PARTIES
  (`DuelBattle.party_digest`: every member's HP / statuses / cooldowns / fainted flag, the pending
  picks) -- a desync on a benched unit is caught too.
* **Leaving**: pause-menu Forfeit (a loss); the opponent's forfeit / drop is this seat's win
  (`DuelBattle.concede`), with the same toasts and messages as Conquest online. The stage shows
  a visible **Forfeit** button (`NetMatchBar`, opening the pause menu's forfeit confirm).
* **Turn clock**: every ACTION is timed by the host's clock (*Turn clock*; Standard 30s), and a
  party duel's pending KO replacement PICK has its own short clock (Standard 15s). The duel's
  hook (`DuelNetRules`) is all the duel adds:
  * `clock_kind` = `action`, or `pick` while a replacement is pending; `clock_turn_key` =
    `"<command count>:<actor id>"` per applied command, or `"pick:<side>:<members fainted>"`
    for a pick (keyed by the picking side's KO count, so the OTHER seat's simultaneous pick after
    a double KO does not restart it; with both pending, side 0's clock runs first, then side 1
    gets a fresh pick clock if it has not picked meanwhile).
  * A voluntary **SWITCH is the action**: it answers the action's clock like a move (it spends
    the turn), and there is no separate switch deadline.
  * The KO replacement pick is **not** charged to anyone's action clock: the faint settles, the
    pick clock opens (nobody can act until the pick lands), and once it is picked the next
    action gets a fresh action clock.
  * `timeout_action`: an action expiry = the acting combatant **passes** (a WAIT -- the idle seat
    deals no damage and rolls nothing; never "the first legal move"); a pick expiry = the host
    **auto-picks** the seat's first healthy benched member in TEAM ORDER (`auto_pick_index`; the
    same "next in order" the engine uses when `ko_replacement` is off) as a `SWITCH` stamped
    `timeout: true`. It is a pure read of the identical party state, so every peer derives the
    same member and `validate_timeout` re-checks it before applying.
  * Strikes: a timed-out action or pick is a strike; any real action of the seat (a move, a
    voluntary switch, its own pick) resets them -- the generic NetSession count.
  `NetDuelStage` mounts the countdown, narrates "Time's up! X passes." / "Time's up! Go, Y!" and
  drops a stale command grid / replacement picker when the clock played for its seat. (The
  local ruleset's `turn_timer_seconds` stays 0: a local expiry would be an un-networked call.)
* **Same device**: Online > Versus > Duel > Same device is the hot-seat `DuelSetup` (two human
  sides on one `DuelStage`) -- no network involved.

## Turn clock (online timers)

Owner rule: **every online match is timed** -- Conquest map battles (Traditional and Speed
First) and online duels. There is no "Off" online. (The local Speed First clock,
`GameSettings.speed_turn_timer_seconds`, is for solo / hot-seat only: `SpeedFirstTurnSystem`
never arms it in a MULTIPLAYER match, because a local expiry would end the turn on one peer.)

**Presets** (`NetTurnClock`; default **Standard**):

| Preset | Traditional (per side) | Speed First (per unit) | Duel (per action) | Duel KO pick |
|---|---|---|---|---|
| Rapid | 45s + 3s per living unit | 10s | 15s | 10s |
| Standard | 90s + 5s per living unit | 20s | 30s | 15s |
| Relaxed | 150s + 8s per living unit | 35s | 50s | 25s |

A Traditional side's allowance is counted when its turn opens (a bigger army gets a little
longer). Chosen in the lobby by the player-host / the dedicated server's leader (the Turn clock
picker in `CollaborativeLobby` / `DuelLobby`; the player-host publishes it with
`set_match_config` so the joiner sees it) or fixed by the server's `--turn-clock <preset>`. The
host stamps the match's `turn_clock` preset and `afk_limit` into the match config.

**Who decides.** The host / dedicated server owns every deadline. Once every seat has reported
its battle attached (`attach_game` -> `_rpc_game_attached`; a seat still loading never loses
time), on each SETTLED state (every accepted action applied and digested) the host asks the
rules for `clock_turn_key()` -- Traditional `"<turn>:<slot>"`, Speed First
`"<turn>:<acting unit id>"`, duel `"<command count>:<actor id>"` (a pending KO pick:
`"pick:<side>:<members fainted>"`) -- and when it changes opens a
new clock: `budget_ms` from the preset and `clock_kind()` (+ `clock_units(slot)` for a side), and
broadcasts `{key, slot, kind, budget_ms, remaining_ms, seq, strikes, afk_limit, preset}`.
Every peer stores `deadline = now + remaining_ms` (`turn_clock()`, `turn_clock_remaining_ms()`,
signal `turn_clock_changed`) and only RENDERS it.

**Expiry.** When `now > deadline + turn_clock_grace_ms` (500 ms of lag allowance) and the seat
has no intent already queued (a last-instant intent goes first), the host builds the rules'
`timeout_action(slot)` -- Traditional **END_TURN** for the seat; Speed First **WAIT** for the
active unit (END_TURN if it cannot wait, e.g. stunned); duel: the acting combatant **passes**
(a WAIT: fair -- the idle seat deals nothing and rolls nothing, the opponent simply gets the
tempo), or, while its KO replacement pick is pending, the **auto-pick** `SWITCH` (first healthy
benched member in team order; see *Online duels*) -- stamps it `timeout: true` and runs it through the SAME accept path as an intent
(validation, commit-reveal round, apply, digest). So it is identical on every peer, recorded by
the replay recorder like any action, and replayable. `turn_timed_out(slot, action, strikes)`
fires on every peer at apply time (HUD: "TIME'S UP" on the chip, a NetToast line).

**Anti-AFK.** Every peer counts a seat's consecutive applied timeouts (`turn_clock_strikes`; any
own action resets it -- a duel's voluntary SWITCH or own KO pick included; a timed-out
auto-pick is a strike like any timeout). On the host, the expiry that would be the seat's `afk_limit`-th in a row
(default **3**, `--afk-limit N`, 0 = never) is not played out: the seat **forfeits** --
`clock_forfeit(slot)` on every peer (the others also get `opponent_forfeited(slot)`, so the
battle resolves exactly like a pause-menu forfeit: UILayoutManager eliminates that side, the
duel stage concedes it), then the host ends the match with `match_aborted("clock_forfeit")`
(GameModeManager keeps the decided battle on screen). A dedicated server reopens its lobby.

**Trust model.**
* Only the host issues timeouts. A client intent's `timeout` key is stripped (`submit_intent`,
  and again on the host's `_rpc_intent`), so a claimed timeout is validated as the ordinary
  intent it is -- e.g. a duel seat cannot "time itself out" to skip a turn.
* Clients check every timeout: it must hit the seat whose clock they are counting and arrive no
  earlier than their derived deadline minus `TIMEOUT_EARLY_TOLERANCE_MS` (1.5 s of jitter) --
  else `premature_timeout` / `timeout_wrong_seat` / `unclocked_timeout` ->
  `host_verification_failed`; and at apply time `validate_timeout` must find it IS the rules'
  canonical timeout on their identical state (`timeout_mismatch` otherwise). So a host cannot
  cut your time short (beyond the tolerance) nor dress a free choice up as a timeout.
* Residual: the host decides the grace and can be *late* (give a seat more time) or stall; it
  sets the budget within its preset; a timeout in your seat is exempt from the "only intents I
  submitted" check (it is canonical and deadline-checked instead). A dedicated server is the
  trusted clock for both seats.

**HUD.** `TurnTimer` (the grove chip) follows the network clock whenever one is open: both seats
see the countdown with a caption (YOUR TURN / OPPONENT), M:SS over a minute, the warning pulse
under 10s and the urgent red band + per-second tick (own clock only) under 5s; it never expires
anything itself. The Conquest battle mounts it in the top-centre column; the online duel stage
mounts it in `NetMatchBar` with a visible **Forfeit** button. The battle **Map Menu** carries a
**Forfeit** entry online (confirm page -> the pause menu's forfeit path, `forfeit_match()`), and
online the menu opens on either seat's turn.

**Bots** (`net_bot_client.gd`) play the safe move (END_TURN / WAIT / the canonical auto-pick)
when their own clock has under 1.2 s left; `--idle-turns N` sits out their first N timed turns
so the host times them out, `--idle-picks N` (duel) their first N KO replacement picks (the
host auto-picks; the FINAL line counts `timeouts=` and `autopicks=`).

## What the player sees at the seam

- **Refused commands are surfaced.** The origin peer gets `intent_rejected(action, reason)`
  with a `NetProtocol.INTENT_*` reason (the rules' specific one: `not_your_turn`,
  `illegal_destination`, `move_unavailable`, …); the battle HUD's `NetToast` renders
  `NetProtocol.describe_intent_rejection(reason, action)` — "Move rejected — that unit cannot
  move there". GameModeManager draws a plain fallback line only when no NetToast is mounted.
  Pinned by `tests/unit/test_net_intent_rejection.gd`, `tests/integration/test_net_rejection_toast.gd`.
- **Ultimates flash on every peer.** `NetGameRules` emits `GameEvents.ultimate_casting` when
  an applied `USE_MOVE` is an ultimate, so a remote opponent's ultimate plays the cut-in here
  too; the battle UI's networked submit branch does not play it, so the caster flashes once
  and never for a refused cast. Pinned by `tests/unit/test_command_applier_ultimate.gd`.
- **Cooldowns and charges are booked apply-side** (`MovesetController.on_used` after
  `perform_move`, preserving a wait the resolution set for itself — Voidstep's teleport).
  The digest includes cooldowns and statuses, so an unbooked cooldown is a detected desync.
  Pinned by `tests/integration/test_net_cast_cooldown.gd`.

## Replays and solo play ride the same apply path

Every battle (solo too) installs a `CommandApplier` on NetSession
(`install_command_seam`) and names its units with `NetUnitIds`. Solo / hotseat seed a
per-command stream with `begin_solo_match_rng()` (`MatchRng`). `ReplayRecorder` records
networked actions from inside `apply_action` (exactly once per peer) and solo commands from
the UI / AI commit sites, in this same vocabulary; `ReplayDriver` plays them back through
`NetSession.command_applier.apply_command`. A recorded network action keeps its verified
seed (`KEY_RNG`), so playback rolls exactly what the match rolled; an unstamped (solo) command
draws from the replay header's `match_seed` stream.

## Unpredictable, unriggable combat RNG (commit-reveal)

**Contributors.** The host / server and (default) every seated client. On a
dedicated server `--rng server` makes the server the only contributor (it is
trusted anyway; fewer round trips); a player-host can never be the only one.

**Chains.** Each contributor draws a secret 32-byte `S` (`Crypto.generate_random_bytes`)
and builds `h_0 = S, h_{i+1} = sha256(h_i)` up to `h_N` (`N = 4096`,
`NetSession.rng_chain_length`). It publishes only the **anchor** `h_N` before the
match. Its share for the k-th action of the epoch is `h_{N-k}`; anyone verifies
it with `sha256(h_{N-k}) == h_{N-k+1}` (the previous verified value). SHA-256 is
one-way, so revealed values say nothing about the next ones, and the whole
future sequence is fixed at commit time.

**Seed.** `seed(seq) = first 8 bytes of sha256(share_c1 || share_c2 || ... || seq)`
(contributors in peer-id order). The action's `RandomNumberGenerator` is seeded
with it, passed to the executor and installed as `CombatServices.match_rng`,
where it **stays until the next action** — so abilities, status ticks, tile
effects and the turn-start ticks deferred after an END_TURN / last WAIT all draw
from the same verified stream. Every action consumes one share per contributor
(also MOVE / WAIT / END_TURN: a WAIT can end the turn and trigger rolling ticks,
and a uniform rule keeps the chains in lockstep; cost ≈ 32 bytes per contributor
per action). Rolls made while the battle is set up, before action 1, use the
public setup seed derived from the anchors.

**Ordering (why nobody can predict).** The host reveals its share only inside the
ACCEPTED broadcast, and clients reveal theirs only after receiving it — so every
share for an action appears after that action is irrevocable:

| Actor | What it knows when choosing | Missing until after acceptance |
|---|---|---|
| player-host | its own chain | the client's share |
| client (player-hosted) | its own chain | the host's share |
| client (dedicated, `rng all`) | its own chain | server's AND the other client's share |
| dedicated server | its own chain | both clients' shares (it does not act anyway) |

The host cannot reject an action after seeing its roll: acceptance is broadcast
before any other share exists. Nobody can bias a roll: chains are committed
before the match and each share must extend its chain. **Epochs:** the last
share of a chain carries the anchor of the contributor's next chain (committed
before any of its values is revealed), so matches can run past `N` actions.

**Verification failure = cheating.** A share that does not extend its chain,
arrives out of order, changes a commitment, or is withheld longer than
`reveal_timeout_ms` (30 s) ends the match: the host / server emits
`cheat_detected` + `match_aborted("rng_verification_failed" | "reveal_timeout")`
and tells the clients; a client that catches the host leaves with
`match_aborted("host_verification_failed")`. The UI shows a clear message.

**Residuals.** The last contributor to reveal learns the roll a moment before
the others and could disconnect instead of revealing (a rage-quit, handled as a
forfeit — a loss, never a re-roll). The setup seed (only rolls before the first
action) is derived from the anchors, so the last committer could grind it --
this only affects rolls made while the battle is set up (e.g. a turn-1 start
tick of a map-authored tile effect), never a player-chosen action.

(The earlier single-match-seed commit/entropy/reveal handshake in `MatchRng` is superseded
by this; `MatchRng` remains only as the solo / replay stream.)

## Trust model

| | Player-hosted (listen server) | Dedicated server |
|---|---|---|
| Who validates | host (a player) — clients re-validate every accepted action on their own state and refuse illegal ones | server — clients re-validate too |
| Actions in your seat | only ones you submitted (host cannot puppet your units: forged → match ends) | same; the server derives the actor from the sending seat |
| Roll prediction | impossible for either player (both contribute) | impossible for clients; the server could only learn rolls post-accept |
| Roll biasing | impossible (committed chains) | impossible for clients; `rng server` mode trusts the server |
| Host-private info | host sees everything a client sends | server sees everything |
| State divergence | per-action digest checkpoint → `desync_detected` → match ends | same |
| Turn clock | the host owns deadlines and issues timeouts; clients refuse an early / wrong-seat / non-canonical timeout (see *Turn clock*) | the server is the clock for both seats |
| Lobby payloads (squads, items, skins, custom maps) | untrusted: whitelisted / strict-validated on receipt; no ownership proof yet | not used (map rosters) |
| Remaining trust | the host process can still refuse / delay your intents, drop you, or run modified rules on ITS copy (you'd see a desync, not a silent change); ENet is unencrypted | operator runs the server; same transport caveat |

**Fog of war** (per-team vision) is presentation-only in network play: every peer holds the
full state because it must re-validate and apply every action, so a modified client — and a
player-host by construction — can see through fog. The fog overlay reads
`NetSession.local_slot()` for its perspective. Only a dedicated server that withheld state
could keep secrets (not implemented). Validation may also reveal information (e.g. a move
refused because an unseen unit blocks the path).

## Dedicated server

Run locally (project root, after `godot --headless --import .`):

```
godot --headless --path . -- --server --port 8910 \
      [--map res://game/maps/resources/default_skirmish.tres] \
      [--turn-system traditional|speed_first] [--rng all|server] \
      [--max-matches N] [--end-after-actions N] [--reveal-timeout 30] [--transport enet]
      [--mode duel [--duel-format singles|trio|full] [--stage meadow|tall_grass|grove] [--weather clear|...]]
      [--turn-clock rapid|standard|relaxed] [--afk-limit 3] [--turn-clock-ms MS]
```

`--turn-clock` fixes the preset (else the leader picks; default Standard), `--afk-limit` the
consecutive expiries that forfeit, `--turn-clock-ms` (testing) gives every timed turn MS ms.
The clock flags apply to both modes and combine freely with the duel flags.

`--mode duel` serves online DUELS instead (no map; `--duel-format` / `--stage` lock the format /
stage, else the slot-0 client picks; each seat's team comes from its `duel_pick` lobby message,
fitted to the format; the match ends when a side has nobody left -- `DuelNetRules.is_match_over`).

`--server` is detected by `GameModeManager` (also any export with the
`dedicated_server` feature tag, i.e. Godot's *Dedicated Server* export mode).
The main menu is unloaded; each match loads the normal `GameWorld` under the
headless dummy renderer (no window, nothing drawn), so the server applies
actions with exactly the systems players run (tile effects, turn ticks, win
conditions). Clients join with the normal **Join** (address:port): the
lobby shows the two players, no host seat. **Lobby leader:** with `--map` the
config is locked; without it the slot-0 client picks map / turn system (the
server sanitises it; builtin, network-eligible maps only -- see *Offline-only maps*). The match starts when both are ready. When it is decided
(or a seat drops / cheats) the server tells the clients, drops them, unloads
the battle and reopens the lobby; `--max-matches N` exits after N. Logs:
`[server] ...` lines incl. `FINAL match=… seq=… digest=…` and a heartbeat.

**Many matches per process** is not supported by the live path: PlayerManager,
TurnSystemManager, CombatServices (board, `match_rng`), GameSettings and the
NetSession autoload are singletons, and tile-effect wiring lives in
GameWorldManager. The network core already runs N instances per process (the
tests run three NetSessions + three rule sets over three BoardAdapters in one
SceneTree, each with its own `MultiplayerAPI` branch via `set_multiplayer`). To
host many matches per process: move per-match state into a match context
(board, turn system, players, rng, tile-effect system) instead of autoloads,
give each match a subtree with its own `SceneMultiplayer` and port (or one
listener that routes peers to matches). Until then: **one process per match**,
scaled by an orchestrator (below).

## Adding a transport

`NetSession.transport` is a `NetTransport`; it only has to return a ready
`MultiplayerPeer` from `create_host(port, max_clients)` / `create_client(address,
port)` (null + `last_error` on failure). Everything else (RPCs, seating,
commit-reveal, the lobby channel) is transport-agnostic.

1. `systems/net/transport/SteamTransport.gd` (GodotSteam, when the dependency is
   added; sketch -- method names per GodotSteam 4.x, check the installed version):
   ```gdscript
   extends NetTransport
   func id() -> String: return "steam"
   func create_host(_port: int, max_clients: int) -> MultiplayerPeer:
       var p = SteamMultiplayerPeer.new()
       last_error = p.create_host(0)              # virtual port; lobby via Steam.createLobby
       return p if last_error == OK else null
   func create_client(address: String, _port: int) -> MultiplayerPeer:
       var p = SteamMultiplayerPeer.new()
       last_error = p.create_client(int(address), 0)   # address = host SteamID64
       return p if last_error == OK else null
   ```
   Steam relay (SDR) gives NAT traversal and hides IPs for free.
2. Register it: `NetTransport.register("steam", "res://systems/net/transport/SteamTransport.gd")`
   (or add it to `_registry`), then `NetSession.transport = NetTransport.create("steam")`
   before hosting/joining (servers: `--transport steam`).
3. Web builds: `WebSocketMultiplayerPeer` (`create_server(port)` / `create_client("wss://host:port")`)
   or `WebRTCMultiplayerPeer` (needs a signalling service) as another subclass.
   ENet is unavailable on web.

## Path to production hosting

* **Build:** export a Linux *Dedicated Server* preset (strips textures/audio,
  keeps scripts + resources), run with `-- --server --port $PORT`. Containerise
  (small base image + the export; expose UDP `$PORT`; log to stdout; the
  heartbeat line doubles as a liveness probe; `--max-matches 1` makes each
  container one match — simplest scaling and isolation).
* **Matchmaking / lobby service:** a small HTTP service (or platform lobbies:
  Steam, EOS, …) pairs players, asks an orchestrator (Agones, Nomad, ECS/Fargate,
  Edgegap, Hathora …) for a server, and hands both clients `address:port` plus a
  **join ticket**. Next step for the server: verify the ticket in the hello
  (`_host_admit_peer`, HMAC signed by the matchmaker) so only the matched players can take the seats.
* **NAT / relay:** a dedicated server with a public IP needs no NAT traversal.
  Player-hosted over the internet needs port forwarding, UPnP (`UPNP` class), or
  a relay (Steam SDR via SteamTransport, WebRTC TURN).
* **Security:** ENet is plaintext — use DTLS (`ENetConnection.dtls_server_setup`
  / `dtls_client_setup`) or the platform relay's encryption. Rate-limit intents per
  peer; cap name length (done) and payload shape (done: `NetProtocol.is_well_formed`).
* **Reconnect / spectators** are not implemented: the per-seq action log plus the
  commit-reveal transcript is a full, verifiable replay (the replay system already
  records it), which is the natural base for both.

## Testing

**In process** (real ENet on 127.0.0.1, every peer a subtree with its own
`SceneMultiplayer`), plus pure / mock-board suites:

| Test | Covers |
|---|---|
| `tests/unit/test_net_protocol.gd`, `test_command_protocol.gd` | wire shapes, builders, the command-log aliases, cells, resolution stamp |
| `tests/unit/test_net_handshake.gd` | the build gate (`validate_hello`), pure |
| `tests/unit/test_net_intent_rejection.gd` | the player-facing rejection wording, pure |
| `tests/unit/test_net_commit_reveal.gd` | chains, tamper/replay/out-of-order detection, re-commit, 3 contributors, seed unknowable until all reveal |
| `tests/unit/test_command_determinism.gd`, `test_command_applier_ultimate.gd` | the apply path on mock boards: lockstep, flags, digest, spawn ids, ultimate announcement |
| `tests/unit/test_match_rng.gd` | the solo / replay stream |
| `tests/unit/test_game_mode_manager.gd` | local defaults, session teardown, match config → GameSettings (squads, custom-map gate) |
| `tests/unit/test_match_loadouts.gd`, `test_lobby_*.gd`, `test_collaborative_lobby.gd` | loadout normalisation, the lobby's transport adapter, votes, loadout / profile exchange, custom-map transmission |
| `tests/integration/test_net_lobby.gd` | seating, ready, single-shot start, rejects (full / in progress / **version mismatch**), leave, the **lobby channel**, `start_match(final_config)`, **forfeit over a socket** |
| `tests/integration/test_net_match.gd` | validation, identical apply, turns (Traditional/Speed First), desync, disconnects, multi-floor |
| `tests/integration/test_net_rng.gd` | host-as-actor cannot derive before the client reveals; tampered client / host shares end the match; withheld reveal times out; re-commit over 12 actions; host cannot puppet or cheat illegal actions past a client |
| `tests/integration/test_net_dedicated.gd` | seatless server + 2 clients: seating, 3rd client rejected, locked vs leader config, auto-start, 3 contributors, identical play, actor cannot derive until the other client reveals, server-only RNG, disconnect → lobby → second match, closing a finished match |
| `tests/integration/test_net_lobby_ui.gd` | the real setup screen + lobby joined to a dedicated server |
| `tests/integration/test_mp_loopback.gd` | two-peer lockstep on mock boards, turn validation, the battle seam, host-side seating + relay |
| `tests/integration/test_net_forfeit.gd` | forfeit / opponent-left semantics (host-stamped slot, no echo, loss on disconnect) |
| `tests/integration/test_net_cast_cooldown.gd` | apply-side cooldown / charge booking, the maxi rule, lockstep, replay round trip |
| `tests/integration/test_net_host_squad.gd`, `test_net_client_squad.gd` | squad replication per slot through MapLoader |
| `tests/integration/test_net_rejection_toast.gd` | refused command → NetToast |
| `tests/integration/test_net_duel.gd` | ONLINE DUEL: mode stamped + mode-mismatch refused, both peers build one duel, a whole duel applies identically (commands, commit-reveal seeds, timeline, winner, digest), host validation (turn, slot, aim, no items / moves / end-turn / free skip), client re-validation, the actor cannot derive its roll before the other reveals, desync, forfeit / drop, ineligible picks refused, a `--mode duel` DedicatedServer folding both picks |
| `tests/integration/test_net_turn_clock.gd` | the TURN CLOCK over ENet: deadline broadcast to both seats (and only once every battle is attached), a new turn = a new clock, expiry -> END_TURN (Traditional) / the active unit's WAIT (Speed First) / the duel's pass applied identically (stamped, digests), strikes cleared by an own action, a client cannot issue a timeout, an early host timeout is caught, N expiries forfeit (limit 0 never), lobby / locked presets, the HUD chip on both seats (caption, urgent band, TIME'S UP) |
| `tests/unit/test_net_turn_clock_ui.gd` | presets / budgets (incl. the KO pick kind) / wording, PROTOCOL 6 + the timeout stamp, config sanitiser + server flags, the local Speed First clock off online, the chip in network mode (never expires), the timeout toast, the Map Menu's Forfeit (confirm -> the pause menu's forfeit), `NetMatchBar`, the lobbies' Turn clock pickers |
| `tests/integration/test_net_duel_stage.gd` | the `NetDuelStage` on both seats: HUD pick -> intent -> applied on both, each seat prompted only for its own unit, per-seat Victory / Defeat, forfeit = the other seat's win |
| `tests/integration/test_net_party_turn_clock.gd` | PARTY DUEL x TURN CLOCK over ENet: a pending KO pick gets its own `pick` clock (own budget / key), a timeout during it AUTO-PICKS the first healthy benched member in team order identically on both peers (`timeout: true` SWITCH, digests, party state), an expired action still passes (no attack), a voluntary SWITCH / own pick resets strikes while an auto-pick adds one, a non-canonical pick dressed as a timeout is refused |
| `tests/integration/test_net_party_duel.gd` | ONLINE PARTY DUELS: format + teams ride the config, a whole 3v3 with switches and KO picks applies identically, illegal switches / picks refused (turn, bench, fainted, must-pick-first, Singles), a desync on a BENCHED unit caught, strict team / format configs, a `--duel-format trio` dedicated server folding both teams, the net stage's replacement picker |

```
godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests/unit,res://tests/integration -gprefix=test_net -gexit
```

**Multi-process** (1 dedicated server + 2 scripted headless clients, each a
separate Godot process running the full GameWorld):

```
GODOT=/path/to/godot dev_scripts/net_multiprocess_check.sh \
    [res://game/maps/resources/default_skirmish.tres] [traditional|speed_first] [actions] [all|server]
```

It passes when the server and both bots print the same `FINAL seq=… digest=…`
with no desync / verification failure. `MODE=duel` runs an online duel instead (map / turn
system ignored; `UNIT_A` / `UNIT_B` pick the combatants), e.g.
`MODE=duel GODOT=… dev_scripts/net_multiprocess_check.sh "" "" 60` (and `HOSTED=1`). `FORMAT=trio` (or `full`)
plays a PARTY duel: the server / hosting bot sets the format, the bots announce teams, switch
every few turns and pick KO replacements (`MODE=duel FORMAT=trio … "" "" 400`). `IDLE=N` (any
mode) has the second bot sit out its first N timed turns (the run must show timeouts; `CLOCK_MS`
per timed turn, default 1500); `IDLE=9` exceeds the forfeit limit (`clock_forfeit`). With a party
`FORMAT`, `IDLE` also sits out one KO pick (`IDLE_PICKS`, default 1) so the host auto-picks;
`EXPECT_AUTOPICK=1` fails a run without one. FORMAT and IDLE combine
(`MODE=duel FORMAT=trio IDLE=2 … "" "" 400`). `HOSTED=1` runs the player-hosted
variant (a host bot = listen server + seat 0, and a guest bot). A bot alone:
`godot --headless --path . -- --net-bot --connect 127.0.0.1 --port 8910 --name BotA`
(add `--host [--map … --turn-system … --end-after-actions N]` to make it the player-host).
Large maps are slow with the naive bot (it pre-validates every candidate intent).

**Idle-bot turn-clock check:** `IDLE=N` makes the second bot (BotB / the guest) sit out its first
N timed turns with every turn clocked at `CLOCK_MS` (default 1500 ms, `--turn-clock-ms`), so the
host / server times it out; it passes when the FINAL states agree AND the idle bot saw a timeout
(`timeouts=K` on the FINAL lines), e.g. `IDLE=2 GODOT=... dev_scripts/net_multiprocess_check.sh
res://game/maps/resources/castle_siege.tres traditional 40` (also `HOSTED=1`, `MODE=duel`). With
N >= the forfeit limit (3) the match ends `reason=clock_forfeit`, still with identical digests.

**Two interactive instances:** Debug → *Customize Run Instances…* → 2, Run;
Host in one, Join `127.0.0.1` in the other (or both Join a local dedicated server).
Or start the second instance with `godot --path . -- --multiplayer-auto-join
[--multiplayer-port 8910]` (MultiplayerLauncher) — it opens the setup screen and presses
Join for you, on the same code path a human uses. The dev-gated "Host + Auto Client"
button (`NetworkMultiplayerSetup.ENABLE_HOST_AUTO_CLIENT`) spawns exactly that.
**Two machines:** `docs/NETWORK_TESTING.md`.

## Known limitations

* 1v1 humans only; no AI seats in network play. No reconnect.
* Online duels: singles-style (one combatant per side on the field; doubles is a follow-up),
  no items, no flee, no spectators.
* The turn clock is host-authoritative: a player-host could be LATE with a timeout (never early,
  see *Turn clock*); there is no pause / reconnect time bank.
* Desync is detected (digest mismatch → match ends), not repaired.
* ENet is unencrypted (see *Path to production hosting*).
* One match per server process (see *Dedicated server*).
* Squads / items / skins replicate only in player-hosted lobbies; dedicated matches field map rosters.
* Fog of war cannot hide information from a modified client (see *Trust model*).
