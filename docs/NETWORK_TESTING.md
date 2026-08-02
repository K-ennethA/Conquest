# Two-machine network testing

How to build Conquest, get it onto a second machine, and play a networked match — plus what
is honestly expected to work today and what is not. Follow it top to bottom the first time.

---

## 1. Build the shared exe (machine A, once per test round)

The project ships **`export_presets.cfg`** at the repo root with two presets:

| Preset | Platform | Runnable | Output |
|---|---|---|---|
| `Windows Desktop` | Windows Desktop | yes | `build/Conquest.exe` (PCK embedded — one file) |
| `Android (stub)` | Android | **no** | `build/Conquest.apk` (placeholder; mobile renderer work pending) |

The Windows preset embeds the PCK, so the export is a **single self-contained .exe** — that is
the only file you copy to the second machine.

**From the editor:** `Project → Export…` → select *Windows Desktop* → `Export Project…` →
save as `build/Conquest.exe` → untick *Export With Debug* for a release build.

**From the command line** (same result, no editor):

```bash
godot --headless --export-release "Windows Desktop" build/Conquest.exe
```

Requirements and gotchas:

- **Export templates must be installed** for your exact Godot version (`Editor → Manage Export
  Templates…`). Without them the export fails with "No export template found".
- `build/` is git-ignored; `export_presets.cfg` is **committed on purpose** so both machines
  build the identical exe. Never put a keystore password or encryption key in it.
- `dev_scripts/`, `tests/`, `docs/`, `tools/` and `addons/gut/` are excluded from the export —
  the shipped exe is the game, not the harness.
- The exe writes its save data and logs to `%APPDATA%\Godot\app_userdata\Conquest\`.

## 2. Get it onto machine B

Copy `build/Conquest.exe` to machine B (USB stick, network share, Drive — anything). **Both
machines must run the exe built from the same commit.** Mismatched builds are refused at
connect time (see §5), which is deliberate — a silent desync is far worse than a clean refusal.

Both machines must be on the **same LAN / router / Wi-Fi**. This is plain ENet over the local
network: there is no relay, no NAT punch-through, no matchmaking server. Playing across the
internet needs port forwarding on the host's router (TCP+UDP `8910`) and the host's public IP,
which is out of scope for a feature test.

## 3. Host on machine A

1. `Main Menu → Multiplayer → Network Multiplayer`.
2. Press **Host Game**.
3. **Windows Firewall will pop up the first time.** Tick **Private networks** and click
   *Allow access*. If you miss it, machine B will never connect. To fix it afterwards:
   `Windows Security → Firewall & network protection → Allow an app through firewall` → find
   *Conquest* → tick **Private**.
4. The screen now shows, in a banner that stays visible over the lobby:
   `Players on your network join:  192.168.x.x:8910`
   Read that address out to machine B. If it says *"No private network address found"*, the
   machine is not on a normal LAN (VPN, mobile hotspot, disconnected adapter) — fix that first.

## 4. Join from machine B

1. `Main Menu → Multiplayer → Network Multiplayer → Join Game`.
2. Type the address machine A displayed into **Address**, leave **Port** at `8910`, set a name.
   The address, port and name are remembered in `user://net.cfg` — the next run pre-fills them.
3. Press **Connect**. The status label walks through explicit states:
   - `Connecting to 192.168.x.x:8910 ... (7s)` — a visible countdown, never a frozen spinner.
   - `Connected to 192.168.x.x:8910. Waiting for the lobby...`
   - `Could not reach 192.168.x.x:8910 - check the address, that the host clicked Host, and
     that Windows Firewall allowed Conquest on both machines.` after ~8s.
   - `Version mismatch: host 0.1.0 (protocol 1), you 0.2.0 (protocol 2). Both machines must
     run the same build.` — you are on different builds; rebuild and recopy.
   Malformed input is caught before the socket is touched, so a typo'd address says so
   immediately instead of burning the timeout.

## 5. The version gate (why a mismatch is refused)

`NetProtocol.PROTOCOL_VERSION` is the wire-format version. A joining client's **first** message
is a hello carrying its protocol version and its game version
(`application/config/version`, or `"dev"` when unset). The server runs
`NetProtocol.validate_hello()` **before** giving the peer a roster slot:

- **Different `PROTOCOL_VERSION` → refused** with reason `version_mismatch`, and the client is
  told both sides' versions before being disconnected.
- **Same protocol, different game version → admitted**, but logged on the host
  (`[NET] Peer 2 joined on game version 'dev' while this host runs '0.1.0'`). Running the
  editor against an exported build is a legitimate test setup, so it is not fatal — but if you
  are chasing a desync, that log line is the first thing to check.

Bump `PROTOCOL_VERSION` whenever the command envelope or any command's data shape changes.

## 6. What SHOULD happen, end to end

| Stage | Expected on machine A (host) | Expected on machine B (client) |
|---|---|---|
| Lobby | Client appears in the player list | Lobby opens, both players listed |
| Map vote | Both vote; matching votes win, differing votes coin-flip | same map resolved on both |
| Battle load | `GameWorld` loads the agreed map | same map, same unit placement |
| Move a unit | unit slides to the cell | **the same move plays here** |
| Cast a move | damage/heal numbers, status icons | **identical numbers** (per-command seeded RNG) |
| End turn | turn passes | turn indicator flips in step |

The seam that makes this work: the acting peer never mutates its own board. It calls
`NetSession.submit_intent()`; the **host** validates, stamps a monotonic `seq` plus a
per-command RNG seed derived from the commit-reveal match seed, and broadcasts the resolved
command; **every** peer (host included) applies it through the one `CommandApplier`. So both
machines roll the same crit off the same seed. If the two screens ever disagree, that is a
desync bug and worth a report.

## 7. Known limitations — test around these, don't report them as new

1. **Input is gated per slot, but a rejected action is silent.** Host/Join, the lobby and the
   battle now all run on **one** transport (`NetSession`) — §6's table, battle rows included,
   is what to expect, and a divergence between the two screens is a real bug worth reporting.
   The host is roster slot 0 = player 0, the joiner is slot 1 = player 1, and the UI's
   ownership/turn gates read that slot, so you can only command your own units on your own
   turn. What is *missing* is feedback when the host refuses an action anyway (a race, a stale
   selection): the intent is rejected server-side and simply does nothing, with no on-screen
   message. Check the log for `intent_rejected` / `not_your_turn` before reporting "the button
   did nothing".

   Still cosmetic-only / local-only in a networked match:
   - **Ultimate cut-in does not play network-side** (see #2 below).
   - **Items and skins do nothing online** (see #3 below).
   - The "your units" highlight tint on the joining machine still keys off the legacy local
     id, so it can outline the wrong side. Purely a tint — ownership itself is correct.
   - The legacy stack (`systems/multiplayer/`, `systems/networking/`,
     `game_core/*NetworkHandler*`) is **gone** — deleted along with the Dictionary-based
     state simulator it wrapped. `NetSession` is the only transport; `GameModeManager` is
     kept purely for the local (solo / hot-seat) session and the lobby's fallback envelope.
2. **Ultimate cut-in does not play network-side.** The full-screen ultimate flash fires only on
   the local/single-player cast path; the networked cast returns before it. The apply-side hook
   (in `CommandApplier`'s `CAST_MOVE` handler, so every peer flashes in sync) is designed but
   not wired. Damage still resolves correctly — only the flourish is missing.
3. **Items and skins are local-only cosmetics in MP.** `ItemSystem` excludes networked matches
   outright (`_is_player_unit` returns false), because replicating each side's loadout needs a
   MatchSettings channel that does not exist yet. Both peers therefore simulate identical base
   stats — which is the safe behaviour, but it means your equipped items do nothing online.
4. **Cast turn-consumption is apply-side.** A resolved `CAST_MOVE` spends the unit's *action*
   (`mark_action_completed`); the movement half arrives as a separate `MOVE_UNIT` command that
   spends the *move*. If a unit ever ends up able to act twice, that split is the place to look.
5. **`Host + Auto Client (Testing)`** is a dev-only two-instance harness, hidden and disabled
   (`ENABLE_HOST_AUTO_CLIENT = false`). It is not a substitute for a real two-machine test.

## 8. Capturing logs for a bug report

Godot writes a rolling log per run on both machines:

```
%APPDATA%\Godot\app_userdata\Conquest\logs\godot.log
```

(Paste that path into Explorer's address bar. Older runs are kept alongside as
`godot_YYYY-MM-DD_HH.MM.SS.log`.) The join prefs live next to it in
`%APPDATA%\Godot\app_userdata\Conquest\net.cfg`.

For a useful report:

1. Reproduce, then **close both games** so the logs are flushed.
2. Grab the newest `godot*.log` from **both** machines — a networked bug is only diagnosable
   with both halves.
3. Note which machine hosted, both game versions (the host prints them when a peer joins on a
   different build), and the wall-clock time of the divergence.
4. Useful greps: `[NET]` (join refusals and version notices), `[HOST]` / `[CLIENT]` (the setup
   screen's flow), `Refusing peer`.

To watch a run live instead, launch from a terminal — the same lines go to stdout:

```bash
Conquest.exe --verbose
```

## 9. Fast checklist

- [ ] Same commit on both machines, exe rebuilt after any code change
- [ ] Both on the same router; host firewall prompt allowed for **Private** networks
- [ ] Host clicked **Host Game** and is showing a `192.168.x.x:8910`-style address
- [ ] Client typed that exact address (not `127.0.0.1` — that only reaches its own machine)
- [ ] Status reached *Connected*, both names in the lobby
- [ ] Logs from **both** machines saved before filing anything
