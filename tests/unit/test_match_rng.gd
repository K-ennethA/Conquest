extends GutTest

# MatchRng: the solo / replay deterministic per-command seed stream.

# The single-seed commit/entropy/reveal handshake that used to live here is superseded
# by the per-action commit-reveal (NetCommitReveal, tests/unit/test_net_commit_reveal.gd);
# MatchRng is now only the solo / replay per-command stream.

# --- seed derivation -------------------------------------------------------

func test_derive_match_seed_is_deterministic():
	assert_eq(MatchRng.derive_match_seed(3), MatchRng.derive_match_seed(3), "deterministic")
	assert_ne(MatchRng.derive_match_seed(3), MatchRng.derive_match_seed(5), "different entropy -> different seed")

func test_begin_from_seed_reproduces_a_recorded_stream():
	var a := MatchRng.new()
	a.begin_solo(99)
	var b := MatchRng.new()
	b.begin_from_seed(a.match_seed)
	assert_true(b.is_ready(), "a replay-seeded stream is ready")
	assert_eq(a.seed_for(7), b.seed_for(7), "and rolls exactly what the recorded one did")

func test_seed_for_is_deterministic_across_instances():
	var a := MatchRng.new()
	a.begin_solo(123)
	var b := MatchRng.new()
	b.begin_solo(123)
	assert_eq(a.match_seed, b.match_seed, "same source -> same match seed")
	for seq in [1, 2, 5, 100, 9999]:
		assert_eq(a.seed_for(seq), b.seed_for(seq), "same match_seed + seq -> same seed value")

func test_seed_for_differs_by_seq():
	var a := MatchRng.new()
	a.begin_solo(123)
	assert_ne(a.seed_for(1), a.seed_for(2), "consecutive seqs give different seeds")
	assert_ne(a.seed_for(2), a.seed_for(3), "and so on")

func test_seed_for_differs_by_match_seed():
	var a := MatchRng.new()
	a.begin_solo(1)
	var b := MatchRng.new()
	b.begin_solo(2)
	assert_ne(a.match_seed, b.match_seed, "different sources -> different match seeds")
	assert_ne(a.seed_for(1), b.seed_for(1), "a different match reseeds the whole per-command stream")

# --- rng_for ---------------------------------------------------------------

func test_rng_for_is_reproducible():
	var a := MatchRng.new()
	a.begin_solo(777)
	var r1 := a.rng_for(9)
	var r2 := a.rng_for(9)
	for _i in range(16):
		assert_eq(r1.randf(), r2.randf(), "two generators for the same seq walk the same stream")

func test_rng_for_differs_by_seq():
	var a := MatchRng.new()
	a.begin_solo(777)
	var r1 := a.rng_for(1)
	var r2 := a.rng_for(2)
	var diverged := false
	for _i in range(8):
		if r1.randf() != r2.randf():
			diverged = true
	assert_true(diverged, "different seqs give independent streams")

func test_solo_matches_the_networked_api():
	# Solo is the degenerate case: same public surface, immediately READY.
	var solo := MatchRng.new()
	solo.begin_solo(2024)
	assert_true(solo.is_ready(), "solo is ready without a handshake")
	assert_ne(solo.seed_for(1), 0, "and produces usable per-command seeds")
