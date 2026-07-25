extends RefCounted
class_name MatchRng

## Deterministic, anti-grind match RNG for authoritative-seed lockstep.
##
## Two jobs:
##   1. A commit-reveal handshake so a player-host cannot grind a favourable
##      match seed. The host commits to a hidden entropy value BEFORE it sees the
##      client's; the client contributes its own entropy in the clear; the host
##      then reveals, and the client verifies the reveal against the commit. The
##      final [member match_seed] mixes both, so neither side alone controls it.
##   2. From that one seed, a stable per-command stream: [method seed_for] and
##      [method rng_for] derive a fresh, reproducible [RandomNumberGenerator] for
##      a given command [code]seq[/code], so every peer resolving command N rolls
##      identically.
##
## Solo play is the degenerate case: [method begin_solo] seeds from a single local
## source and every other method behaves the same.
##
## SECURITY NOTE: [method _mix] is a fast non-cryptographic hash (FNV-1a-style over
## 64-bit ints). It provides the BINDING the anti-grind property needs — the host
## cannot change its entropy after committing — but it is not collision-resistant.
## A competitive/anti-cheat deployment should swap [method _mix] used by
## [method commit_for] for a cryptographic hash (e.g. SHA-256 over the bytes). The
## seed-derivation stream does not need cryptographic strength, only determinism.

## Handshake progression. Host and client walk the same phases from opposite ends.
enum Phase {
	UNSTARTED,      ## nothing seeded yet
	COMMITTED,      ## host: made its commit / client: received the host's commit
	CLIENT_SENT,    ## client entropy is known to this side
	READY,          ## match_seed is finalised; seed_for / rng_for are usable
}

## Domain-separation salts so commit hashes and seed hashes can never collide, and
## so per-command seeds never collide with the match seed.
const _SALT_COMMIT := 0x436F6D6D6974        # "Commit"
const _SALT_SEED := 0x5365656473            # "Seeds"
const _SALT_STREAM := 0x53747265616D        # "Stream"

## FNV-1a 64-bit constants (both fit signed int64; multiplication wraps mod 2^64).
const _FNV_OFFSET := 1469598103934665603
const _FNV_PRIME := 1099511628211

var phase: Phase = Phase.UNSTARTED
var match_seed: int = 0

var _host_entropy: int = 0
var _client_entropy: int = 0
var _commit: int = 0
var _have_host_entropy: bool = false
var _have_client_entropy: bool = false


# ---------------------------------------------------------------------------
# Pure hashing / derivation (static, deterministic, no state)
# ---------------------------------------------------------------------------

## FNV-1a-style fold of [param values] into a 64-bit int. Deterministic across
## peers running the same build; that is all the seam requires.
static func _mix(values: Array) -> int:
	var h: int = _FNV_OFFSET
	for v in values:
		h = (h ^ int(v)) * _FNV_PRIME
	return h

## The public commitment for [param host_entropy]. The host sends this before it
## has seen any client entropy; the client later checks the reveal against it.
static func commit_for(host_entropy: int) -> int:
	return _mix([_SALT_COMMIT, host_entropy])

## The final match seed from both contributions. Order-fixed (host, client) so both
## sides compute the same value.
static func derive_match_seed(host_entropy: int, client_entropy: int) -> int:
	return _mix([_SALT_SEED, host_entropy, client_entropy])

## Fresh entropy suitable for a commit or a client contribution. Not gameplay
## RNG — only used once, before any seeded stream exists, so a randomized source
## is correct here (it must be unpredictable to the other party).
static func fresh_entropy() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	# randi() is 32-bit; widen to fill the 64-bit space.
	return (int(r.randi()) << 32) ^ int(r.randi()) ^ r.seed


# ---------------------------------------------------------------------------
# Host handshake
# ---------------------------------------------------------------------------

## Host step 1: commit to [param host_entropy]. Returns the commit to broadcast.
func begin_host(host_entropy: int) -> int:
	_host_entropy = host_entropy
	_have_host_entropy = true
	_commit = commit_for(host_entropy)
	phase = Phase.COMMITTED
	return _commit

## Host step 2: record the client's entropy (received in the clear).
func set_client_entropy(client_entropy: int) -> void:
	_client_entropy = client_entropy
	_have_client_entropy = true
	if phase == Phase.COMMITTED:
		phase = Phase.CLIENT_SENT

## Host step 3: reveal the committed entropy and finalise the seed. Returns the
## host entropy to broadcast so clients can verify. Requires client entropy first.
func host_reveal() -> int:
	if not (_have_host_entropy and _have_client_entropy):
		push_warning("MatchRng: host_reveal before both contributions are present")
		return _host_entropy
	_finalize()
	return _host_entropy


# ---------------------------------------------------------------------------
# Client handshake
# ---------------------------------------------------------------------------

## Client step 1: store the host's commit.
func begin_client(commit: int) -> void:
	_commit = commit
	phase = Phase.COMMITTED

## Client step 2: adopt the entropy this client will send. (Same setter as the host
## uses, kept as a distinct name for readability at call sites.)
func set_own_client_entropy(client_entropy: int) -> void:
	set_client_entropy(client_entropy)

## Client step 3: accept the host's revealed entropy. Verifies it against the stored
## commit; on success finalises the seed and returns true, otherwise leaves the state
## untouched and returns false (a failed verify means the host tampered — abort).
func accept_reveal(host_entropy: int) -> bool:
	if not verify(host_entropy):
		return false
	_host_entropy = host_entropy
	_have_host_entropy = true
	if not _have_client_entropy:
		push_warning("MatchRng: accept_reveal before this client set its own entropy")
		return false
	_finalize()
	return true

## True if [param host_entropy] hashes to the stored commit. The heart of the
## anti-grind guarantee.
func verify(host_entropy: int) -> bool:
	return commit_for(host_entropy) == _commit


# ---------------------------------------------------------------------------
# Solo
# ---------------------------------------------------------------------------

## Solo/local match: seed from a single [param local_entropy] source. Same public
## API from here on, so single-player is the degenerate local case of lockstep.
func begin_solo(local_entropy: int) -> void:
	_host_entropy = local_entropy
	_client_entropy = local_entropy
	_have_host_entropy = true
	_have_client_entropy = true
	_finalize()


# ---------------------------------------------------------------------------
# Per-command stream (only valid once READY)
# ---------------------------------------------------------------------------

## Deterministic seed for command [param seq]: a stable hash of the match seed and
## the sequence number. Same match_seed + seq -> same value on every peer; different
## seq -> (almost surely) different value.
func seed_for(seq: int) -> int:
	return _mix([_SALT_STREAM, match_seed, seq])

## A [RandomNumberGenerator] seeded for command [param seq]. Inject this into
## [MoveExecutor.execute] so accuracy/crit rolls resolve identically everywhere.
func rng_for(seq: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = seed_for(seq)
	return r

func is_ready() -> bool:
	return phase == Phase.READY


func _finalize() -> void:
	match_seed = derive_match_seed(_host_entropy, _client_entropy)
	phase = Phase.READY
