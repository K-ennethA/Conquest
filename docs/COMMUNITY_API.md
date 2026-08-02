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
  *soft* identity for vote de-duplication only. Real accounts, rate limiting and
  anti-abuse arrive with the live service and do **not** change these shapes.

## Item summary shape

Lists return an array of *summaries* (no payload) so a page stays small:

```json
{
  "id": "challenge_1a2b3c",
  "type": "map",                // "map" | "challenge"
  "name": "Skirmish Arena",
  "author": "Ada",
  "votes": 42,                  // net score (up minus down)
  "attempts": 40,              // challenge play attempts (0 for plain maps)
  "clears": 12,               // successful clears (Held% = 1 - clears/attempts)
  "created": "2026-08-01T00:00:00",
  "size_bytes": 4096,
  "checksum": "1837465028"     // content hash for tamper detection
}
```

## Endpoints

| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/v1/items?sort=top\|new\|daily&type=map\|challenge\|all&page=N` | List item summaries. `page` is 0-based; empty array = end. |
| `GET` | `/v1/items/{id}` | Full payload for one item (the map or challenge JSON). |
| `POST` | `/v1/items` | Upload. Body `{type, name, author, payload, checksum}`; server **re-validates** and re-computes the checksum, ignoring the client's. Returns the created summary. |
| `POST` | `/v1/items/{id}/vote` | Body `{dir: 1 \| -1 \| 0}`. **Idempotent per device**: re-sending the same dir is a no-op; `0` clears this device's vote. Returns the item's new `votes`. |
| `GET` | `/v1/daily` | `{id}` of the server's daily featured pick. |

### Responses

- Success: `200` with the JSON body described above.
- Client error (bad type, unknown id, oversized payload): `4xx` with
  `{"error": "human readable reason"}`.
- The client maps any non-2xx / transport failure to a uniform
  `{ok:false, error:...}` result and surfaces it in the UI.

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
