extends GutTest

# MatchRng: the commit-reveal handshake (anti-grind match seed) and the
# deterministic per-command seed stream built on top of it.

# --- commit-reveal ---------------------------------------------------------

func test_honest_reveal_verifies_and_both_sides_agree():
	var host := MatchRng.new()
	var host_entropy := 424242
	var commit := host.begin_host(host_entropy)

	var client := MatchRng.new()
	client.begin_client(commit)
	var client_entropy := 99
	client.set_own_client_entropy(client_entropy)

	# The host learns the client's entropy, then reveals.
	host.set_client_entropy(client_entropy)
	var revealed := host.host_reveal()

	assert_true(client.accept_reveal(revealed), "an honest reveal passes verification")
	assert_true(host.is_ready(), "the host finalised its seed")
	assert_true(client.is_ready(), "the client finalised its seed")
	assert_eq(host.match_seed, client.match_seed, "both sides derive the same match seed")

func test_tampered_reveal_is_rejected():
	var host := MatchRng.new()
	var commit := host.begin_host(1000)

	var client := MatchRng.new()
	client.begin_client(commit)
	client.set_own_client_entropy(7)

	assert_false(client.accept_reveal(1001), "a reveal that does not match the commit is rejected")
	assert_false(client.is_ready(), "and the client does not finalise a seed off a bad reveal")

func test_verify_checks_entropy_against_the_commit():
	var host := MatchRng.new()
	var commit := host.begin_host(555)
	var client := MatchRng.new()
	client.begin_client(commit)
	assert_true(client.verify(555), "the true entropy verifies against the commit")
	assert_false(client.verify(556), "anything else does not")

func test_commit_binds_the_host_to_one_value():
	# The whole point: hash(host_entropy) is fixed at commit time, so the host cannot
	# later swap in a different, more favourable entropy.
	assert_eq(MatchRng.commit_for(12345), MatchRng.commit_for(12345), "the commit is deterministic")
	assert_ne(MatchRng.commit_for(12345), MatchRng.commit_for(12346), "different entropy -> different commit")

# --- seed derivation -------------------------------------------------------

func test_derive_match_seed_is_order_fixed():
	assert_eq(MatchRng.derive_match_seed(3, 5), MatchRng.derive_match_seed(3, 5), "deterministic")
	assert_ne(MatchRng.derive_match_seed(3, 5), MatchRng.derive_match_seed(5, 3),
		"host/client order is fixed, so the two contributions are not interchangeable")

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
