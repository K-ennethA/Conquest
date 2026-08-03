# Community Service API (v1)

The contract the Conquest client speaks to browse, vote on, download and upload
community **maps** and **challenges**. It is deliberately small and REST-ish so the
real service can be a free-tier serverless function/worker. The client ships with a
`LocalProvider` that fakes this whole surface offline, so nothing here needs a server
to develop against (see "Swapping in a real service" below).

- **Transport:** JSON over HTTPS.
- **Base URL:** configured client-side (see swap section). All paths are versioned
  under `/v1/` — bump the prefix when the wire shape changes.
- **Auth / identity:** an anonymous per-device UUID, generated once and stored at
  `user://community_device.txt`, sent as the `X-Community-Device` header. This is a
  *soft* identity for vote de-duplication and **base ownership** (who may retire a
  challenge) only. Real accounts, rate limiting and anti-abuse arrive with the live
  service and do **not** change these shapes.

## Item summary shape

Lists return an array of *summaries* (no payload) so a page stays small:

```json
{
  "id": "challenge_1a2b3c",
  "type": "map",                // "map" | "challenge"
  "name": "Skirmish Arena",
  "author": "Ada",
  "votes": 42,                  // net score (up minus down)
  "attempts": 40,              // plays recorded against it (0 for plain maps)
  "clears": 12,               // successful clears
  "owner": "9f2c…",           // uploader's device id ("" for builtin/seed content)
  "active": true,             // published; false = retired (see "Active bases")
  "created": "2026-08-01T00:00:00",
  "size_bytes": 4096,
  "checksum": "1837465028"     // content hash for tamper detection
}
```

`attempts` and `clears` are **server-maintained counters**. Rates are **derived by
readers, never stored**: Held% = `1 - clears/attempts`, clear rate = `clears/attempts`,
both undefined at `attempts == 0`. Storing a rate would mean two sources of truth for the
same fact and a rounding to argue about; the counters are the fact.

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/items?sort=recommended\|top\|new\|daily&type=map\|challenge\|all&page=N&q=needle` | List item summaries. `page` is 0-based; empty array = end. `q` is optional (see *Search*). Retired items are **never** listed. |
| `GET` | `/v1/items/{id}` | Full payload for one item (the map or challenge JSON). Works for **retired** items too — a friend with the code can always play the base. |
| `POST` | `/v1/items` | Upload. Body `{type, name, author, payload, checksum}`; server **re-validates** and re-computes the checksum, ignoring the client's. Stamps `owner` from the device header. Returns the created summary. |
| `POST` | `/v1/items/{id}/vote` | Body `{dir: 1 \| -1 \| 0}`. **Idempotent per device**: re-sending the same dir is a no-op; `0` clears this device's vote. Returns the item's new `votes`. |
| `GET` | `/v1/daily` | `{id}` of the server's daily featured pick (active items only). |
| `POST` | `/v1/items/{id}/attempts` | Record one play. Body `{cleared, score, turns}`. **Not** idempotent — see *Attempt ledger*. Returns `{id, attempts, clears, outcome}`. |
| `GET` | `/v1/me/bases` | The calling device's own uploaded challenges, **active and retired**, with their counters. Array of summaries, newest first. |
| `POST` | `/v1/items/{id}/active` | Body `{active: bool}`. Publish or retire an owned base. Returns `{id, active}`. |

### Responses

- Success: `200` with the JSON body described above.
- Client error (bad type, unknown id, oversized payload): `4xx` with
  `{"error": "human readable reason"}`.
- The newer endpoints return **machine-readable** error codes instead of prose, because
  callers switch on them: `not_found` (unknown id, `404`), `not_owner` (someone else's
  item, `403`), `base_limit` (would exceed 3 active, `409`).
- The client maps any non-2xx / transport failure to a uniform
  `{ok:false, error:...}` result and surfaces it in the UI.

## Search (`q`)

`q` filters by **case-insensitive substring on the title *or* the author name**, applied
**before** sorting and pagination — so page 0 of a search is genuinely the top of the
matching set, not the top of the catalogue with non-matches punched out.

Sanitised at the boundary, on both sides: leading/trailing whitespace stripped, truncated
to **64 characters**, and *empty-after-strip means no query at all* — an all-whitespace
search is not a filter that matches nothing.

## Recommended feed

`sort=recommended` is the default feed. The contract is only:

> **The server ranks. The client renders.**

The client never re-sorts a page, so the live service can refine the formula whenever it
likes without a client release. What follows is the **reference** ranking, implemented in
`LocalProvider._recommended_score` so the offline sandbox behaves like a plausible server
(and so the formula is arguable in review rather than hidden in a worker).

Four terms, each normalised to ~0..1 (votes to −1..1) and blended:

| Term | Formula | Weight | Why |
| --- | --- | --- | --- |
| Votes | `v / (abs(v) + 25)` | 0.45 | The crowd's opinion, soft-saturating so one viral score can't drown out everything else. |
| Fairness | `max(0, 1 − ((r − 0.4)/0.4)²)`, `r = clears/attempts` | 0.35 | Inverted parabola peaking at a **40% clear rate**. |
| Engagement | `a / (a + 25)`, `a = attempts` | 0.12 | Rewards bases people actually play — and is the counterweight that stops a 2-attempt fluke rate from topping the feed. |
| Freshness | `1 / (1 + age_days/14)` | 0.08 | A small nudge so new bases surface at all. Deliberately the smallest weight: a boost onto the page, not a free pass to the top. |

The fairness term is the point of the whole thing. A base **nobody can clear** (`r = 0`)
and a **pushover** (`r ≥ 0.8`) both score **0**; a base that is *cleared sometimes but not
always* scores up to 1. An **unplayed** base (`attempts == 0`) also scores 0 — an unknown
base has not *earned* the fairness bonus, though it still ranks on votes and freshness.

Ties break by score, then `votes`, then `id` — a total order, so pagination can never lose
or repeat an item between two calls.

## Attempt ledger

`POST /v1/items/{id}/attempts` records **one play**. Body:

```json
{ "cleared": true, "score": 1200, "turns": 9 }
```

**Deliberately not idempotent.** Unlike voting, *every* attempt counts, including repeats
from the same device: the ledger measures how the base performs, not how many people tried
it once. Retired bases still accept attempts — a friend playing from a share code is
exactly the traffic the author wants reflected.

Validated at the boundary (client *and* server — the client is never a validator):
unknown keys are **dropped**, a non-boolean `cleared` reads as `false`, and `score` /
`turns` are clamped to non-negative ints within `0..1000000` / `0..999`. Unknown id →
`not_found`.

**Where the id comes from:** when a challenge is installed, `CommunityClient` stamps the
service's item id into the saved challenge JSON as a top-level **`community_id`** field
(`ChallengeCodec.content_hash` hashes a fixed field list, so the extra key does not disturb
the checksum). The challenge-completion flow reads that field off the challenge it just
finished and calls `CommunityClient.report_attempt(community_id, …)`. A locally authored
challenge has no `community_id` and simply reports nothing. Bare maps are not stamped —
nothing "attempts" a map.

## Active bases (max 3)

Each item carries `active`. A player may have at most **3 active challenge items** at a
time; maps are not capped.

- **Retiring always succeeds.** An author can always pull a base out of the feeds.
- **Activating a 4th** fails with `base_limit`. Retire one and the slot frees immediately.
- **Someone else's item** fails with `not_owner` (ownership is the `owner` device id
  stamped at upload — never taken from the payload, or anyone could upload "as" someone
  else and retire their bases).
- **Uploading a 4th** does not sneak past the cap: the new item lands **retired**
  (`active: false`) rather than being refused, so nothing is lost and the uploader's screen
  can offer to swap one out.
- Inactive bases are excluded from `/v1/items` (every sort, including search and daily) but
  remain **fetchable by direct id**. Share codes stay the friend path: retiring a base
  removes it from the storefront, it does not delete it.

## Payload validation (server MUST mirror the client)

A payload is **untrusted, player-authored content**. The server MUST run the *same*
catalog-strict validation the client runs before accepting an upload, and reject
anything that fails — it is never enough to trust the client:

- **Maps** — validated exactly as `MapResource.validate_map(strict_catalog = true)`
  (via `MapResource.import_from_json`): known tile/character ids only, in-bounds
  cells, size within `MIN_MAP_SIZE..MAX_MAP_SIZE`, no spawns on impassable terrain,
  at least two players.
- **Challenges** — validated exactly as `ChallengeCodec.validate`: supported
  `format_version`, required keys, the embedded map passes the strict map validation
  above, at least one defender, squad size in band, and a matching content checksum.

The checksum is a plain content hash for **tamper detection only** — it is not a
signature and not a security boundary. The client never instantiates a downloaded
payload except through these two hardened importers (no `ResourceLoader` on shared
bytes → no arbitrary-code-execution vector).

Where an accepted download lands, always as **inert JSON**, never a `.tres`:

| Type | Path | Written by |
| --- | --- | --- |
| Map | `user://maps/<name>.json` | the validated `MapResource` re-exported via `export_to_json` — the same directory + format the in-game Map Creator writes, so a download shows up in the pickers (`MapLoader.get_available_map_entries`, origin `custom`). |
| Challenge | `user://challenges/<name>.json` | `ChallengeCodec.save_to_file`, alongside locally authored challenges. |

Re-exporting from the validated in-memory resource (rather than echoing the bytes that
arrived) also normalises the file to exactly the importer's schema and drops anything
extra the payload carried.

## Swapping in a real service

The client chooses its provider by the presence of `user://community.cfg`:

```ini
[service]
base_url = "https://your-worker.example.dev"
```

- **File absent** → `LocalProvider` (offline sandbox; the UI shows a local-mode banner).
- **File present with a `base_url`** → `HttpProvider` pointed at that origin.

That single file is the whole switch: no code change flips the client from the local
sandbox to a live service. The reference server in `tools/community_server/` implements
this exact contract for local testing; the production deployment should be a free-tier
worker/function port of the same endpoints.
