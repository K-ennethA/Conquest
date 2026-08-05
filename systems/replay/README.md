# Battle replays

A Conquest replay is **not video**. It is a *command log* riding the game's lockstep
determinism: every gameplay mutation funnels through one apply path and every roll comes from
a `MatchRng` stream derived from the match seed, so the complete record of a battle is

> initial setup (header) + every command every actor committed, in order + a version stamp
> + a per-turn state checksum

Re-issuing those commands from that setup reproduces the battle exactly. A 200-command battle
is a few kilobytes gzipped.

This directory is the **format, the recorder and the player**. The replay-picker screen and
the attach-a-replay-to-a-challenge-attempt transport are separate waves; see *Seams* at the
bottom for what they build on.

| File | What it is |
|---|---|
| `ReplayLog.gd` | The format and its codec. Pure statics, no scene, no autoload mutation — the whole contract is unit-testable headless. **Nothing else may define the shape.** |
| `ReplayRecorder.gd` | The per-battle `Node` that listens and writes. Mounted by `GameWorldManager._setup_replay_recorder`. |
| `ReplayPlayback.gd` | The hand-off: `launch(log)` validates, stages and changes to the battle scene. Pure statics (the [BattleSaveManager] resume-staging shape), because static state is what survives the scene change. |
| `ReplayDriver.gd` | The per-replay `Node` that steps the log back through `CommandApplier`, paces it, and stops on divergence. Mounted by `GameWorldManager._mount_replay_driver`. |

---

## The format (`format_version` 1)

```jsonc
{
  "format_version": 1,
  "game_version": "dev",        // ProjectSettings application/config/version, read through
                                // NetProtocol.local_game_version() — the SAME source the net
                                // join handshake gates on
  "protocol_version": 1,        // NetProtocol.PROTOCOL_VERSION (the command vocabulary)
  "recorded_at_utc": "2026-08-02T14:03:11",   // display only; nothing gameplay reads it
  "mode": "skirmish",           // skirmish | versus | arena | challenge | campaign |
                                // king_of_the_hill
  "map": {
    "path": "res://… | user://…",   // map identity, mirroring BattleSnapshot's context
    "name": "Forgotten Forest",
    "custom": false,
    "payload": { }              // embedded map dict for a custom/challenge map; empty for a
                                // res:// map, where the path IS the identity
  },
  "participants": [             // one per player slot, ascending
    { "slot": 0, "name": "Player 1", "is_ai": false,
      "squad": ["vineweave"],                  // character ids, pick order
      "equipped": { "vineweave": "ironband" }, // UNIT-scope item, per character
      "team": ["verdant_banner"],              // TEAM-scope items (the shared slots)
      "skins":  { "vineweave": "ashen" } }
  ],
  "rng":  { "match_seed": 123456789 },  // MatchRng.match_seed for the battle
  "turn_system": 0,             // TurnSystemBase.TurnSystemType
  "difficulty": 1,              // BotController.Difficulty
  "challenge_id": "",           // set in challenge mode (the challenge's content checksum)
  "campaign_chapter_id": "",

  "entries": [                  // THE BODY — ordered, one per committed command
    { "turn": 3, "actor_slot": 0, "cmd": { /* encoded NetProtocol command */ } }
  ],
  "checksums": [ { "turn": 3, "hash": "0a1b2c3d4e5f6071" } ],
  "outcome": { "result": "victory", "winner_slot": 0, "turns": 12 },
  "truncated": false            // true when the entry cap stopped recording
}
```

`result` is one of `""` (never finished — the player quit mid-match), `victory`, `defeat`,
`draw`, read from the local player's point of view. `winner_slot` is the authoritative
payload; in versus/hotseat "victory" just means *a human* won and the slot says which.

### The participant loadout *is* a `MatchLoadouts` card

`equipped` / `team` / `skins` are deliberately the **exact** three fields
`systems/net/MatchLoadouts.gd` puts on the wire and applies at spawn — not a replay-specific
spelling of them. Playback republishes them verbatim (`ReplayPlayback._stage_loadouts`) and the
spawn path reads them back through the same `MatchLoadouts.items_for` /
`MatchLoadouts.skin_for` calls that answered while the battle was being recorded, so a worn
UNIT item stays on the one character who wore it.

`ReplayRecorder.participant_loadout(slot, profile)` samples each slot from **whatever the spawn
path would read**, which is what makes recording and application unable to disagree:

| Slot | Sampled from |
|---|---|
| the local one — our seat in a networked match, else slot 0 | `MatchLoadouts.build_local_payload(profile)` — the local `ItemInventory` + `PlayerProfile`, the identical sampler the lobby announces with |
| any slot that announced a card | `MatchLoadouts.get_peer_loadout(slot)`, verbatim |
| anything else (a solo AI side, a neutral camp) | an empty card — which is what `ItemSystem` gives it |

`ReplayLog.validate` cleans these **structurally** (strings only — a number where an id belongs
is dropped, never stringified into a fabricated id; lengths clipped; `team` capped at
`ItemInventory.TEAM_SLOTS`; each map capped at `MAX_LIST`). The **library** whitelist is
`MatchLoadouts.set_peer_loadout`'s, applied at staging: a replay's cards are no more trusted
than a peer's, so an id that no longer resolves is dropped when it is fielded.

### Commands

Stored in the **NetProtocol vocabulary**, JSON-flattened: a `Vector2i` becomes `[x, y]`
(exactly as `BattleSnapshot.cell_to_array` does), and `decode_command` puts it back.

Only the four types `CommandApplier.apply_command` has an apply branch for are accepted
(`ReplayLog.APPLIABLE_TYPES`): `MOVE_UNIT`, `WAIT_UNIT`, `END_TURN`, `CAST_MOVE`.
`ATTACK_UNIT` exists in `NetProtocol.Action` but has **no** apply branch, so a replay carrying
one could never be re-simulated — it is rejected at the gate rather than mid-playback.

`decode_command` finishes by asking `NetProtocol.is_command_well_formed`, so the live protocol
validator — not a copy of its rules — is the last word.

### The per-turn checksum

`ReplayLog.state_checksum(rows)` → a 16-char lowercase hex string.

Recipe, and every part of it is load-bearing:

1. Each row is `{ "id": int, "cell": Vector2i|[x,y], "hp": int }`, one per live unit that the
   command seam named (`net_id` metadata). A unit with no `net_id` is **skipped** — it cannot
   be addressed by a command either, so including it would make the checksum depend on
   something playback can never reproduce.
2. Rows are **sorted by id** before anything is mixed. Scene order is not stable across peers;
   this is exactly the bug the sort guards. The result is *permutation-invariant*.
3. Mixed as `[SALT, count, SEP, id, x, y, hp, SEP, …]` through `MatchRng._mix` — a domain
   salt so a state checksum can never collide with a `MatchRng` seed hash, and a separator
   between variable-length records, mirroring `CommandApplier`'s mixing discipline.
4. Formatted by `to_hex64`, which splits into two 32-bit halves because `"%x"` on a negative
   int prints a sign rather than the bit pattern.

It is deliberately **cheap** — ids, cells and HP only. It is a divergence *tripwire*, not a
state capture. `CommandApplier.hash_match_state` (statuses + cooldowns) is the richer desync
detector the live net layer uses.

### The container

`ReplayLog.encode_container(log)` / `decode_container(bytes)` — one CQRP codec with three
consumers: the file helpers, playback, and the attach-to-attempt transport (whose bytes travel
in a payload and never touch a file). `to_bytes` / `from_bytes` are aliases of the same two
functions, kept because they read better at the file seam. `decode_container` answers `{}` for
**anything** that is not a replay, silently.

### On disk

`user://replays/<mode>_<map>_<stamp>.cqrep`, written by `ReplayLog.save_to_file`.
The container is

```
"CQRP" (4) | container_version u32 | uncompressed_size u32 | sha256(payload) (32) | gzip(JSON)
```

The digest is verified **before** inflation, so bytes we did not write never reach the
decompressor at all (its failure path is an engine error we cannot catch), and a decompression
bomb is capped twice — by the declared size and by `MAX_DECOMPRESSED_BYTES`.

---

## Security posture

A replay file is **untrusted input**. The headline use case is a challenge base-defense replay
recorded on the *attacker's* machine and watched by the defender.

- Never `load()` / `ResourceLoader` on any of it. It is inert JSON end to end.
- Parsing uses an **instance** `JSON`, never `JSON.parse_string` — the static helper logs an
  engine error on malformed input, and a corrupt/hand-edited/hostile file is an *expected*
  case here (project convention #1; GUT fails a test on any engine error). Every rejection
  returns `{}` / `false` and nothing reaches the engine log.
- `ReplayLog.validate` is the strict importer: unknown keys are **dropped** (never carried
  through), every command is re-validated against the live vocabulary, every string is
  length-capped, every list is count-capped.

Caps: `MAX_ENTRIES` 5000 · `MAX_CHECKSUMS` 4000 · `MAX_PARTICIPANTS` 8 · `MAX_LIST` 64 ·
`MAX_STRING` 256 · `MAX_PATH` 512 · `MAX_PAYLOAD_KEYS` 64 · `MAX_DECOMPRESSED_BYTES` 8 MiB ·
`MAX_FILE_BYTES` 4 MiB · `MAX_LISTED_FILES` 512.

Hard refusals (return `{}`): non-dictionary, wrong/absent `format_version`, a
`protocol_version` this build cannot apply, a body that is not a list, bad container magic or
version, digest mismatch, oversized. `game_version` is the **soft** gate —
`matches_this_build()` reports it and playback decides.

---

## Recording: the one seam

`GameEvents.command_committed(cmd, actor_slot)`.

Every commit site in the game emits it through a `ReplayRecorder.note_*` static, and the
recorder is the **only** subscriber — so adding a new command site costs one line and nothing
else in the game has to know replays exist.

| Site | File | Records |
|---|---|---|
| Networked apply | `systems/net/CommandApplier.gd` → `apply_command` | `note_command` — *all* networked play. Every peer applies there, so the acting peer's UI submit path deliberately does not also record. |
| Solo move commit | `game/ui/panels/UnitActionsPanel.gd` → `_commit_tentative_move` | `note_move_unit` — the one place a solo/hotseat move becomes committed board state. |
| Solo cast | `UnitActionsPanel._execute_move_on_target` | `note_cast_move`, on `success` only, so a refused aim never enters the log. |
| Solo wait | `UnitActionsPanel._on_end_unit_turn_pressed`, `_on_action_menu_wait_chosen` | `note_wait_unit` |
| Solo end turn | `UnitActionsPanel._do_end_player_turn` | `note_end_turn`, *before* the turn system advances so the entry is stamped with the turn it ended. |
| AI move | `game/ai/BotTurnDriver.gd` → `_relocate` | `note_move_unit` — plan-attack, plan-advance and the legacy fallback all route through there. |
| AI cast | `BotTurnDriver._execute_move_decision` | `note_cast_move`, on `success` only. |
| AI wait | `BotTurnDriver._finish` | `note_wait_unit`, for the `"wait"` action only. |

Every networked commit site in `UnitActionsPanel` returns **before** its local counterpart
(`_net_submit_pending_move` reverts rather than commits), so no command is ever recorded twice.

**Near-zero cost when off.** Every `note_*` static returns immediately on `is_active()` — a
static counter of mounted recorders AND-ed with the `recording_enabled` master switch — so a
battle with no recorder, and every unit test that constructs a `CommandApplier`, pays one
integer compare and builds no dictionaries.

**Turn signals ride the ACTIVE turn system** (`TurnSystemBase.turn_started` / `turn_ended`,
re-bound on `TurnSystemManager.turn_system_activated`), never `PlayerManager`'s turn signals —
the latter do not fire on AI turns, so a recorder wired to them would silently stop
checksumming the moment the enemy acted (project convention #2).

### Lifecycle

1. `GameWorldManager._setup_replay_recorder` mounts one recorder per battle, before the map
   and players load, so it is subscribed in time for the first turn.
2. The header is **latched once** on the first `turn_started` — late enough that the roster,
   squads and skins exist. `begin()` is idempotent; `append_command` lazily latches too, so a
   mode that boots straight into commands still records.
3. Commands append with the current turn number. Past `max_entries` the recorder flips
   `truncated` and drops the command, silently — a capped recording is a handled outcome, not
   a fault.
4. `turn_ended` stamps a checksum.
5. `GameEvents.game_ended` stamps a final checksum and finalizes with the outcome — the normal
   write path. `_exit_tree` finalizes with `result: ""` as the quit-mid-match fallback, so an
   abandoned attempt still produces a watchable file.

---

## Not covered

- **`BotTurnDriver._fallback_attack`** (the legacy no-character path) mutates HP directly
  instead of going through a `NetProtocol` command, so it has nothing replayable to log. It
  only runs for units with no `Character` backing.
- **Units with no `net_id`.** `note_*` returns early; those units are also skipped by the
  checksum, so the log stays self-consistent.
- The **custom-map payload** is left empty by the recorder (`_live_map`). The transport wave is
  what has the validated challenge blob in hand and fills it in.

---

---

## Playback

### The whole contract with a replay-picker screen

```gdscript
var log: Dictionary = ReplayLog.load_from_file(path)   # {} when it is not a replay
var res: Dictionary = ReplayPlayback.launch(log)
# { "ok": true }                                  -> the battle scene is loading
# { "ok": false, "error": "invalid_replay" }      -> ReplayLog.validate refused it
# { "ok": false, "error": "version_mismatch" }    -> recorded by a different build
# { "ok": false, "error": "no_scene_tree" }       -> headless; nothing was staged
```

A refusal changes **nothing** — no scene change, no staged state, no engine log line — so the
menu shows the error and stays where it is. `ReplayLog.list_replays()` / `delete_replay(path)`
are the browse half.

### Booting a battle from a header

`GameWorldManager` picks the staged log up in three phases, mirroring the snapshot restore's
shape because it is the same problem — a battle whose initial state comes from a file:

| Phase | Where | What |
|---|---|---|
| 1 | `_maybe_begin_replay_playback`, before the recorder mount and the map load | consume the staged log, arm spectator mode, point `MapLoader.net_context_override` at the spectator slot |
| 2a | `_load_selected_map` | a custom map travels **with** the replay (the header's embedded payload, imported through `MapResource.import_from_json`); otherwise the header's path is what the ordinary loader reads |
| 2b | `_on_map_loaded`, after the command seam | overwrite the freshly negotiated solo match seed with `header.rng.match_seed` |
| 3 | `_finish_replay_boot`, after `_start_game` | stamp the recorded participants onto the roster, free any AI driver, mount the `ReplayDriver` |

**How each side fields its own squad, items and skins.** Staging publishes one
`MatchLoadouts` card per recorded participant and seats the viewer in
`ReplayPlayback.SPECTATOR_SLOT` (99 — a slot no participant can hold, since `MAX_PARTICIPANTS`
is 8). That one fact routes every recorded side through the code path a *networked* match
uses, so no slot is treated as "mine" and none of them is rebuilt from the viewer's local
inventory. There is no replay-specific spawn code.

The card's `equipped` / `team` / `skins` go across untouched, because the recorder wrote them
in that shape to begin with (see *The participant loadout is a `MatchLoadouts` card* above) —
there is no translation step here to get wrong, and a per-unit item cannot leak onto a
team-mate and trip the checksum.

### Spectator mode — three switches, all off `ReplayPlayback.is_playing()`

- **Input.** `UnitActionsPanel._player_is_human` returns false. That is the *one* gate:
  `_human_may_command` ends in it and End Player Turn calls it directly, so the whole command
  loop closes with a single guarded line. Selection, the cursor, the inspection panels and the
  camera are untouched — watching is still watching.
- **AI.** `_ensure_bot_driver` never mounts one, and `ReplayPlayback.disable_ai_drivers` frees
  any that exists. Every AI action is already *in* the log; a live driver would take it twice.
- **Recording.** `ReplayRecorder.recording_enabled` goes off in `begin_playback` and is
  restored in `end_playback`, which runs from the driver's `_exit_tree` — so *any* way of
  leaving the replay puts it back for the next real battle.

### Pacing

Each command buys a **beat** sized by what it is — cast `0.90s`, move `0.55s`, end-turn
`0.70s`, wait `0.12s` — and the next one waits it out. Speed (x1 / x2 / x4) multiplies how
fast a beat is *spent*; it deliberately never touches `Engine.time_scale`, which would also
speed up the animations, tweens and audio the beat exists to let you watch. Before each beat
the driver waits for `UnitAnimator`'s busy registry to go quiet (capped, exactly as
`BotTurnDriver` does), so a command never lands on top of the previous one's flourish.

`ReplayDriver.advance(delta)` is the entire clock and `_process` is a one-line caller, so
playback is drivable in a test by handing it deltas. `beat_for(type, speed)` is a static pure
function; `step_one()` applies exactly one command; the applier, the board, the checksum rows
and the animation gate are all injectable.

### Divergence

At every turn boundary — the **active** turn system's `turn_ended`, the same signal the
recorder stamped on — the driver recomputes `ReplayLog.state_checksum` over
`ReplayRecorder.board_state_rows()` and compares it to the recorded hash for that boundary. A
mismatch **stops playback dead**, names the turn, and banners
*"Replay diverged — recorded on a different version?"*. It never resumes: a replay that has
drifted is no longer a recording of anything, and showing it as one is the worst thing this
system could do. A log with no checksums left (a truncated recording) simply stops being
checkable — that is a handled outcome, not a divergence.

**Compatibility note — environmental damage no longer rolls.** Tile effects and
`TravelingHazard` bands now land unconditionally (`MoveContext.guaranteed_hit`, the rule
status ticks already followed), so a battle with terrain damage in it consumes fewer RNG
draws than it used to; a replay recorded before that change replays against a shifted stream
and trips the divergence guard above, which stops it at the offending turn and banners it —
the designed behaviour, not a regression.

**Compatibility note — abilities may now fire at battle start.** `ON_BATTLE_START` runs once
per unit when the first turn opens (Geode's opening 15 HP ward is the first user), so a log
recorded before that trigger existed replays against a board whose turn-0 state differs and
trips the same divergence guard — again by design; the grant is deterministic boot
resolution, so no command or RNG draw changed.

The transport bar (`game/ui/hud/ReplayHUD.gd`, mounted by `UILayoutManager` exactly as
`NetToast` is) is play/pause · step · speed · `Turn 4/12` · exit, plus that banner and the
recorded outcome when the log runs out. It hides itself unless a replay is playing, so a
normal battle pays one hidden `CanvasLayer`.

---

## Seams

Everything the *recording* core deliberately left for later. Playback has now taken the first
seven; the rest are still open for the picker screen and the attempt-report transport:

- **`ReplayLog.validate(raw)` / `load_from_file(path)`** — the single gate. Anything they
  return is normalised, capped and vocabulary-checked; anything else is `{}`.
- **`ReplayLog.decode_command(raw)`** — hands back a *live* command (cells as `Vector2i`) that
  `CommandApplier.apply_command` accepts as-is. This is the one call between a file on disk and
  the simulator. Drive playback through the **same** apply path with input and AI disabled.
- **`ReplayLog.matches_this_build(log)`** — the soft `game_version` gate to warn on.
  Format/protocol mismatches are already hard-refused before you see the log.
- **`ReplayLog.state_checksum(rows)` + `ReplayRecorder.collect_state_rows()`** — recompute at
  each turn end during playback and compare against `checksums[i].hash`. A divergence should
  bail gracefully *at the turn it diverged*, naming the turn.
- **`header.rng.match_seed`** — seed the playback `MatchRng` with it before the first command;
  per-command `rng_seed` values are already carried inside each entry.
- **`ReplayLog.list_replays()`** — cheap browse listing (path/filename/bytes, no parse) for a
  replay-picker screen; `delete_replay(path)` for its delete button.
- **`ReplayLog.set_replay_dir(path)`** — directory injection, already used by the tests; an
  "import this replay" flow can point it elsewhere.
- **`ReplayRecorder.GROUP`** (`&"replay_recorder"`) + **`get_log()`** (a deep copy) — how the
  attach-to-attempt-report transport reaches the live log without touching the file.
- **`ReplayRecorder.recording_enabled`** — set `false` around playback so a replay being
  watched cannot record itself.

## Tests

- `tests/unit/test_replay_log.gd` — codec round-trip, hostile/malformed input, checksum
  determinism / permutation invariance / sensitivity, container tampering, file I/O against an
  injected directory, and the participant loadout's structural whitelist (non-string ids
  dropped, maps and the team list capped).
- `tests/integration/test_replay_recorder.gd` — recorder lifecycle: header latch, entry order
  and turn stamping, checksums on the active turn system's `turn_ended`, finalize + outcome,
  truncation, normalization of the solo/AI commit statics, and where
  `participant_loadout` samples each slot from (local stores, an announced card, or nothing).
- `tests/unit/test_replay_playback.gd` — the CQRP container (round-trip, broken magic, wrong
  container version, tampered payload, declared-size bomb) and `launch`'s result shapes:
  version-mismatch and invalid-log refusals that change no scene and stage nothing, what
  staging points at (including the loadout card round-tripping into the reads the spawn path
  makes), and the spectator switches.
- `tests/integration/test_replay_driver.gd` — the transport against a fake applier (order,
  pacing, speed, pause/step, animation gate), the divergence stop, the end-of-log outcome, the
  input/AI gates, the transport bar, and one end-to-end drive of a recorded MOVE through the
  real `CommandApplier` on a real map.
