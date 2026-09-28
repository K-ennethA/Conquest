extends RefCounted
class_name MatchRng

## The SOLO / replay match RNG stream: one match seed, and from it a stable per-command
## stream ([method seed_for] / [method rng_for] derive a fresh, reproducible
## [RandomNumberGenerator] for command [code]seq[/code]).
##
## NETWORK PLAY DOES NOT USE THIS. It used to also run a single-seed commit/entropy/reveal
## handshake for networked matches; that is superseded by the per-ACTION commit-reveal in
## [NetCommitReveal] (every accepted action carries its own verified seed, so nobody --
## the host included -- can predict or grind a roll). What is left is the degenerate local
## case: [method begin_solo] seeds a battle from one local source, the battle seam
## ([CommandApplier]) draws unstamped commands from it by seq, and a replay header records
## [member match_seed] so playback can re-seed the same stream.
##
## [method _mix] is a fast non-cryptographic FNV-1a-style fold, shared by the replay
## checksum. The stream only needs determinism, not cryptographic strength.

enum Phase {
	UNSTARTED,      ## nothing seeded yet
	READY,          ## match_seed is set; seed_for / rng_for are usable
}

## Domain-separation salts so the match seed and per-command seeds never collide.
const _SALT_SEED := 0x5365656473            # "Seeds"
const _SALT_STREAM := 0x53747265616D        # "Stream"

## FNV-1a 64-bit constants (both fit signed int64; multiplication wraps mod 2^64).
const _FNV_OFFSET := 1469598103934665603
const _FNV_PRIME := 1099511628211

var phase: Phase = Phase.UNSTARTED
var match_seed: int = 0


## FNV-1a-style fold of [param values] into a 64-bit int. Deterministic across
## peers running the same build; that is all the seam requires.
static func _mix(values: Array) -> int:
	var h: int = _FNV_OFFSET
	for v in values:
		h = (h ^ int(v)) * _FNV_PRIME
	return h

## The match seed derived from [param local_entropy].
static func derive_match_seed(local_entropy: int) -> int:
	return _mix([_SALT_SEED, local_entropy, local_entropy])

## Fresh entropy for a solo seed. Not gameplay RNG -- only used once, before any
## seeded stream exists.
static func fresh_entropy() -> int:
	var r := RandomNumberGenerator.new()
	r.randomize()
	# randi() is 32-bit; widen to fill the 64-bit space.
	return (int(r.randi()) << 32) ^ int(r.randi()) ^ r.seed


## Solo/local match: seed from a single [param local_entropy] source.
func begin_solo(local_entropy: int) -> void:
	match_seed = derive_match_seed(local_entropy)
	phase = Phase.READY


## Adopt a known [param seed_value] (replay playback re-seeds the recorded stream).
func begin_from_seed(seed_value: int) -> void:
	match_seed = seed_value
	phase = Phase.READY


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
