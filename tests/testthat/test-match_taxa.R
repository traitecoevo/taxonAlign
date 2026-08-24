# These tests exercise match_taxa()'s hybrid/intergrade/indecision/affinis handling (issue #9) via
# align_taxa(), since match_taxa() itself is @noRd. Both `hybrids`/`intergrades_affinis` default to
# FALSE and are forwarded straight through from align_taxa() -- see match_special_case_to_genus() in
# R/match_taxa.R for the shared implementation both toggles call into.

test_that("hybrids = FALSE (default) leaves a hybrid-looking name to ordinary match blocks", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia x hybrida", resources)

  # may still resolve via the *generic* higher-rank genus fallback (match_12b/12c) -- the point of
  # this test is that the hybrid-specific block (match_03*) never fires when the toggle is off
  expect_false(isTRUE(startsWith(out$alignment_code, "match_03")))
})

test_that("hybrids = TRUE resolves a hybrid name to genus rank via an exact genus match", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia x hybrida", resources, hybrids = TRUE)

  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$alignment_code, "match_03a_hybrid_exact_genus")
  expect_true(grepl("^Boronia x \\[", out$aligned_name))
})

test_that("hybrids = TRUE fuzzy-matches a misspelled genus, respecting fuzzy_matches", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  out_fuzzy <- align_taxa("Boronai x hybrida", resources, hybrids = TRUE) # fuzzy_matches defaults TRUE
  expect_equal(out_fuzzy$alignment_code, "match_03b_hybrid_fuzzy_genus")
  expect_true(grepl("^Boronia x \\[", out_fuzzy$aligned_name))
  # "Boronai" vs "Boronia" -- a single adjacent transposition, distance 1 under
  # Damerau-Levenshtein (confirmed directly, not assumed)
  expect_equal(out_fuzzy$chars_changed, 1L)

  # confirm fuzzy matching genuinely was disabled, not just coincidentally unnecessary
  out_nofuzzy <- align_taxa("Boronai x hybrida", resources, hybrids = TRUE, fuzzy_matches = FALSE)
  expect_equal(out_nofuzzy$alignment_code, "match_03c_hybrid_unresolved")
  expect_true(is.na(out_nofuzzy$aligned_name))
  expect_true(is.na(out_nofuzzy$chars_changed))
})

test_that("hybrids = TRUE degrades gracefully when the genus isn't in the reference at all", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Xylomelum x foobar", resources, hybrids = TRUE)

  expect_true(is.na(out$aligned_name))
  expect_equal(out$alignment_code, "match_03c_hybrid_unresolved")
})

test_that("intergrades_affinis = TRUE resolves an intergrade name (double dash) to genus rank", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia serrulata -- Boronia pinnata", resources, intergrades_affinis = TRUE)

  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$alignment_code, "match_04a_intergrade_affinis_exact_genus")
  expect_true(grepl("^Boronia sp\\. \\[", out$aligned_name))
})

test_that("intergrades_affinis = TRUE resolves an indecision name (slash) to genus rank", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia serrulata/pinnata", resources, intergrades_affinis = TRUE)

  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$alignment_code, "match_04a_intergrade_affinis_exact_genus")
})

test_that("intergrades_affinis = TRUE resolves a graded/'affinis'/'cf.' identification to genus rank", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  out_aff <- align_taxa("Boronia aff. serrulata", resources, intergrades_affinis = TRUE)
  expect_equal(out_aff$taxon_rank, "genus")
  expect_equal(out_aff$alignment_code, "match_04g_affinis_exact_genus")

  out_cf <- align_taxa("Boronia cf. serrulata", resources, intergrades_affinis = TRUE)
  expect_equal(out_cf$taxon_rank, "genus")
  expect_equal(out_cf$alignment_code, "match_04g_affinis_exact_genus")
})

test_that("intergrades_affinis distinguishes a real 'affinis' epithet from an affinity qualifier", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  # "affinis" immediately followed by an infraspecific rank marker is a genuine specific epithet
  # (e.g. the real "Gomphrena affinis subsp. pilbarensis"), not an affinity qualifier -- should NOT be
  # treated as an uncertain identification
  out_real_epithet <- align_taxa("Boronia affinis subsp. serrulata", resources, intergrades_affinis = TRUE)
  expect_false(isTRUE(startsWith(out_real_epithet$alignment_code, "match_04")))

  # "affinis" with no rank marker following, and no real listed name to exact-match, IS an affinity
  # qualifier
  out_qualifier <- align_taxa("Boronia affinis otherspecies", resources, intergrades_affinis = TRUE)
  expect_equal(out_qualifier$taxon_rank, "genus")
  expect_equal(out_qualifier$alignment_code, "match_04g_affinis_exact_genus")
})

test_that("intergrades_affinis = FALSE (default) leaves these names unhandled by match_04", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia aff. serrulata", resources)

  expect_false(isTRUE(startsWith(out$alignment_code, "match_04")))
})

# Issue #16: a real, resource-verified exact match must win over the affinis/cf. heuristic, since a
# bare "affinis" is genuinely ambiguous between the qualifier reading and a real specific epithet --
# guessing "a repeated word means a tautonym" would risk over-confidently upgrading a genuine hedge, so
# the fix instead performs its own explicit, untruncated exact-match check (match_04e/match_04f)
# before ever falling back to genus rank (match_04g-j).
test_that("a real, listed tautonymous subspecies ('Genus affinis affinis') exact-matches rather than falling back to genus", {
  tautonym <- dplyr::tibble(
    canonical_name = "Boronia affinis affinis", scientific_name = "Boronia affinis affinis Sm.",
    taxon_rank = "subspecies", taxonomic_status = "accepted", taxonomic_dataset = "TEST",
    genus = "Boronia", taxon_ID = "taut1", accepted_name_usage_ID = "taut1"
  )
  resources <- prepare_taxonomic_resources(dplyr::bind_rows(sample_taxonomic_resources(), tautonym))

  out <- align_taxa("Boronia affinis affinis", resources, intergrades_affinis = TRUE)

  expect_equal(out$taxon_rank, "subspecies")
  expect_equal(out$aligned_name, "Boronia affinis affinis")
  expect_equal(out$alignment_code, "match_04e_affinis_exact_species_accepted")
})

test_that("a genuine affinity hedge that ISN'T also a real, listed name still falls back to genus rank", {
  # same shape of query as the tautonym above, but "hedgeus" is not a real epithet anywhere in
  # resources -- confirms the exact-match-first fix doesn't accidentally suppress the genuine fallback
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia affinis hedgeus", resources, intergrades_affinis = TRUE)

  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$alignment_code, "match_04g_affinis_exact_genus")
})

test_that("a truncated binomial/trinomial coincidence doesn't fool the affinis exact-match check", {
  # regression test for the real APC-equivalence-test failure this fix's design was refined against:
  # a resource entry using its own informal "sp. aff. X (voucher)" naming convention reduces, once
  # stripped, to the same truncated 2-word binomial ("genus aff") as *any* fabricated "Genus aff.
  # <anything>" query -- match_04e/match_04f must not be fooled by that truncated coincidence, since
  # they compare the full, untruncated ignore_bracketed_words field, not binomial/trinomial
  placeholder <- dplyr::tibble(
    canonical_name = "Boronia sp. aff. serrulata (Somewhere XY12345)",
    scientific_name = "Boronia sp. aff. serrulata (Somewhere XY12345)",
    taxon_rank = "species", taxonomic_status = "accepted", taxonomic_dataset = "TEST",
    genus = "Boronia", taxon_ID = "voucher1", accepted_name_usage_ID = "voucher1"
  )
  resources <- prepare_taxonomic_resources(dplyr::bind_rows(sample_taxonomic_resources(), placeholder))

  out <- align_taxa("Boronia aff. completelyfakeepithet", resources, intergrades_affinis = TRUE)

  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$alignment_code, "match_04g_affinis_exact_genus")
})

test_that("progress = TRUE still reports progress when hybrids/intergrades_affinis resolve a name (issue #5)", {
  # match_special_case_to_genus() (the shared hybrid/intergrade_affinis helper) has its own internal
  # redistribute() checkpoints, separate from match_taxa()'s own -- confirms the progress bar (`pb`) is
  # threaded into those too, not just the top-level match blocks
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  expect_output(
    out <- align_taxa("Boronia x hybrida", resources, hybrids = TRUE, progress = TRUE),
    "%"
  )
  expect_equal(out$alignment_code, "match_03a_hybrid_exact_genus")
})

# include_bracketed_info (defaults to FALSE): APCalign's convention of formatting a higher-rank-only
# match as "<rank name> sp. [<original name>; <identifier>]" is only actually informative when there's
# something beyond the matched rank's own name to report -- an unresolved epithet, a morphospecies
# code, etc. When the name being matched is *nothing more* than the rank name itself (a bare single
# word, or a bare "Genus (Subgenus)"), the bracketed suffix is redundant (original_name already
# preserves the raw input as its own column regardless), so the default now returns just the bare
# matched name. include_bracketed_info = TRUE restores APCalign's always-bracketed convention exactly.
test_that("include_bracketed_info = FALSE (default) returns a bare name when nothing more was in the input", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  out_genus <- align_taxa("Boronia", resources)
  out_genus_synonym <- align_taxa("Boronella", resources)
  out_family <- align_taxa("Rutaceae", resources)
  out_subgenus_bracket <- align_taxa("Boronia (Valvatae)", resources)

  expect_equal(out_genus$aligned_name, "Boronia")
  expect_equal(out_genus$alignment_code, "match_12b_higher_rank_exact_accepted")
  expect_equal(out_genus_synonym$aligned_name, "Boronella") # the matched (synonym) row's own name
  expect_equal(out_family$aligned_name, "Rutaceae")
  expect_equal(out_subgenus_bracket$aligned_name, "Boronia (Valvatae)")
  expect_equal(out_subgenus_bracket$alignment_code, "match_02y_bracket_exact_subgenus")
})

# match_02y (issue #14): a bare "Genus (Subgenus)" query must never leak into species-level matching
# as a fake epithet -- regardless of whether the specific subgenus pair is actually in
# resources$subgenus_v2. Regression tests for the real bug found comparing AFD+iNat against AFD+GBIF
# on the same name list ("Lasioglossum (Parasphecodes)" resolved to subgenus rank against one resource,
# but silently mis-resolved to an unrelated real species against the other).
test_that("a bare 'Genus (Subgenus)' query falls back to genus rank when the pair isn't in resources", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  # "Boronia" (the genus) is real; "Nonexistentia" is not a subgenus of it anywhere in resources --
  # this must resolve to genus rank via the shared hybrid/intergrade-style genus fallback, never to an
  # unrelated species by treating "Nonexistentia" as a fake epithet
  out <- align_taxa("Boronia (Nonexistentia)", resources)

  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$alignment_code, "match_02y_bracket_genus_exact")
  expect_equal(out$aligned_name, "Boronia sp. [Boronia (Nonexistentia)]")
})

test_that("a genuine 'Genus (Subgenus) species' trinomial is unaffected by the bare-bracket quarantine", {
  # match_02y only ever fires for an exactly-two-token bracketed name -- a real trinomial (a species
  # epithet actually present after the bracket) must still be handled by the existing, later
  # match_11a/match_11b (ignore_bracketed_words) mechanism, not diverted to a genus-only fallback.
  # (The nominotypical-subgenus variant of this is already covered end-to-end in
  # test-match_taxa_typos.R; this checks a non-nominotypical bracket too.)
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia (Valvatae) serrulata", resources)

  expect_equal(out$aligned_name, "Boronia serrulata")
  expect_equal(out$taxon_rank, "species")
})

test_that("include_bracketed_info = FALSE also drops a bare match's identifier, not just the original name", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia", resources, identifier = "some_dataset")

  expect_equal(out$aligned_name, "Boronia") # no "[Boronia; some_dataset]" -- "nothing more" is literal
})

test_that("include_bracketed_info = FALSE still brackets a fuzzy bare-name match (match_12c)", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronela", resources) # one letter short of the genus synonym "Boronella"

  # the *matched* reference name is bare, but the *input* itself was still just one (mis-spelled) word
  # with nothing else -- still qualifies for the simplified format
  expect_equal(out$aligned_name, "Boronella")
  expect_equal(out$alignment_code, "match_12c_higher_rank_fuzzy_accepted")
})

test_that("include_bracketed_info = FALSE keeps the bracketed format whenever there's more to report", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  # extra, unresolved content beyond the genus itself -- dropping it would lose real information
  out_extra_epithet <- align_taxa("Boronia unresolvedepithet", resources)
  out_morphospecies <- align_taxa("Boronia sp. 1", resources)

  expect_true(grepl("^Boronia sp\\. \\[Boronia unresolvedepithet\\]$", out_extra_epithet$aligned_name))
  expect_true(grepl("^Boronia sp\\. \\[Boronia sp\\. 1\\]$", out_morphospecies$aligned_name))
})

test_that("include_bracketed_info = TRUE always uses the bracketed format, matching APCalign's convention", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  out_genus <- align_taxa("Boronia", resources, include_bracketed_info = TRUE)
  out_subgenus_bracket <- align_taxa("Boronia (Valvatae)", resources, include_bracketed_info = TRUE)

  expect_equal(out_genus$aligned_name, "Boronia sp. [Boronia]")
  expect_equal(out_subgenus_bracket$aligned_name, "Boronia (Valvatae) sp. [Boronia (Valvatae)]")
})

# Fuzzy higher-rank matching defaults to broadest-first, the reverse of exact matching (issue #12) --
# found via a real, large validation that 52% of fuzzy higher-rank matches were also fuzzy-matching a
# real candidate at a *different* rank, overwhelmingly not coincidence but a systematic pattern
# (informal English vernacular name endings meant to signal a broader group, not a specific genus).

test_that("fuzzy higher-rank matching defaults to broadest-first, unlike exact matching", {
  # deliberately engineered so the same query fuzzy-matches both a genus and an unrelated order within
  # tolerance -- confirms the *fuzzy* order is broadest-first (order wins), the reverse of exact
  # matching's most-specific-first default.
  resources <- prepare_taxonomic_resources(tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Zelia alpha Sm.", "Zelia alpha", "species", "accepted", "TEST", "Zelia", "sp1", "sp1",
    "Zelia Sm.", "Zelia", "genus", "accepted", "TEST", NA_character_, "g1", "g1",
    "Zelda Sm.", "Zelda", "order", "accepted", "TEST", NA_character_, "o1", "o1"
  ))

  out <- align_taxa("Zelca sp.", resources, full = TRUE)

  expect_equal(out$taxon_rank, "order")
})

test_that("genus still resolves before subgenus under the broadest-first fuzzy order", {
  # the genus-before-subgenus exception is a guaranteed nomenclatural convention (a nominotypical
  # subgenus sharing its genus's own name), not a coincidental fuzzy collision -- it must survive the
  # broadest-first reversal above, not get flipped along with everything else.
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Aporocera zzzzzzzzzz", resources, full = TRUE)

  expect_equal(out$taxon_rank, "genus")
})

# consider_english_name_endings (issue #12): before any fuzzy matching, try substituting a recognised
# informal English vernacular name ending for its formal Latin equivalent, and attempt an exact match
# on the corrected name.

test_that("consider_english_name_endings = FALSE (default) leaves vernacular endings to ordinary fuzzy matching", {
  resources <- prepare_taxonomic_resources(tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Testus alpha Sm.", "Testus alpha", "species", "accepted", "TEST", "Testus", "sp1", "sp1",
    "Testidae Sm.", "Testidae", "family", "accepted", "TEST", NA_character_, "f1", "f1",
    "Testinae Sm.", "Testinae", "subfamily", "accepted", "TEST", NA_character_, "sf1", "sf1"
  ))

  # "Testine" is within ordinary fuzzy tolerance of both "Testidae" (family) and "Testinae" (subfamily)
  # -- with the toggle off, broadest-first fuzzy matching (not the exact-substitution logic) resolves
  # it, landing on the broader of the two (family), not necessarily the rank the "-ine" ending would
  # conventionally suggest (subfamily)
  out <- align_taxa("Testine sp.", resources, full = TRUE)

  expect_equal(out$taxon_rank, "family")
  expect_false(isTRUE(out$alignment_code == "match_02z_english_ending_accepted"))
})

test_that("consider_english_name_endings = TRUE resolves a vernacular '-ine' ending to the correct subfamily", {
  resources <- prepare_taxonomic_resources(tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Testus alpha Sm.", "Testus alpha", "species", "accepted", "TEST", "Testus", "sp1", "sp1",
    "Testidae Sm.", "Testidae", "family", "accepted", "TEST", NA_character_, "f1", "f1",
    "Testinae Sm.", "Testinae", "subfamily", "accepted", "TEST", NA_character_, "sf1", "sf1"
  ))

  out <- align_taxa("Testine sp.", resources, consider_english_name_endings = TRUE, full = TRUE)

  # the exact substitution ("Testine" -> "Testinae") correctly lands on subfamily specifically, unlike
  # the broadest-first fuzzy fallback above, which only ever finds "the broadest thing within tolerance"
  expect_equal(out$taxon_rank, "subfamily")
  expect_equal(out$alignment_code, "match_02z_english_ending_accepted")
  expect_true(grepl("^Testinae sp\\. \\[Testine sp\\.\\]$", out$aligned_name))
})

test_that("consider_english_name_endings = TRUE resolves a vernacular '-id' ending to family", {
  resources <- prepare_taxonomic_resources(tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Quixus alpha Sm.", "Quixus alpha", "species", "accepted", "TEST", "Quixus", "sp1", "sp1",
    "Quixidae Sm.", "Quixidae", "family", "accepted", "TEST", NA_character_, "f1", "f1"
  ))

  out <- align_taxa("Quixid BF01", resources, consider_english_name_endings = TRUE, full = TRUE)

  expect_equal(out$taxon_rank, "family")
  expect_equal(out$alignment_code, "match_02z_english_ending_accepted")
})

test_that("consider_english_name_endings = TRUE resolves a vernacular '-oid' ending to superfamily", {
  resources <- prepare_taxonomic_resources(tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Yorbus alpha Sm.", "Yorbus alpha", "species", "accepted", "TEST", "Yorbus", "sp1", "sp1",
    "Yorboidea Sm.", "Yorboidea", "superfamily", "accepted", "TEST", NA_character_, "sup1", "sup1"
  ))

  out <- align_taxa("Yorboid sp.", resources, consider_english_name_endings = TRUE, full = TRUE)

  expect_equal(out$taxon_rank, "superfamily")
  expect_equal(out$alignment_code, "match_02z_english_ending_accepted")
})

test_that("consider_english_name_endings = TRUE falls through harmlessly when the corrected name isn't real", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  # "Boroniid" has a recognised vernacular ending, but "Boroniidae" doesn't exist anywhere in this
  # fixture -- the substitution should cost nothing and fall through to ordinary handling, not error
  # or spuriously match anything
  expect_no_error(
    out <- align_taxa("Boroniid BF01", resources, consider_english_name_endings = TRUE, full = TRUE)
  )
  expect_false(isTRUE(out$alignment_code == "match_02z_english_ending_accepted"))
})

test_that("consider_english_name_endings = TRUE doesn't fire on a name that's already an exact match", {
  # match_02z runs after match_02b (exact higher-level matches), so a name that's already an exact
  # match to something real should never reach the substitution logic at all
  resources <- prepare_taxonomic_resources(tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Wexus alpha Sm.", "Wexus alpha", "species", "accepted", "TEST", "Wexus", "sp1", "sp1",
    "Wexid Sm.", "Wexid", "genus", "accepted", "TEST", NA_character_, "g1", "g1"
  ))

  out <- align_taxa("Wexid sp.", resources, consider_english_name_endings = TRUE, full = TRUE)

  expect_equal(out$taxon_rank, "genus")
  expect_false(isTRUE(out$alignment_code == "match_02z_english_ending_accepted"))
})
