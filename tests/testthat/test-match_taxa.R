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

  # confirm fuzzy matching genuinely was disabled, not just coincidentally unnecessary
  out_nofuzzy <- align_taxa("Boronai x hybrida", resources, hybrids = TRUE, fuzzy_matches = FALSE)
  expect_equal(out_nofuzzy$alignment_code, "match_03c_hybrid_unresolved")
  expect_true(is.na(out_nofuzzy$aligned_name))
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
  expect_equal(out_aff$alignment_code, "match_04a_intergrade_affinis_exact_genus")

  out_cf <- align_taxa("Boronia cf. serrulata", resources, intergrades_affinis = TRUE)
  expect_equal(out_cf$taxon_rank, "genus")
  expect_equal(out_cf$alignment_code, "match_04a_intergrade_affinis_exact_genus")
})

test_that("intergrades_affinis distinguishes a real 'affinis' epithet from an affinity qualifier", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  # "affinis" immediately followed by an infraspecific rank marker is a genuine specific epithet
  # (e.g. the real "Gomphrena affinis subsp. pilbarensis"), not an affinity qualifier -- should NOT be
  # treated as an uncertain identification
  out_real_epithet <- align_taxa("Boronia affinis subsp. serrulata", resources, intergrades_affinis = TRUE)
  expect_false(isTRUE(startsWith(out_real_epithet$alignment_code, "match_04")))

  # "affinis" with no rank marker following IS an affinity qualifier
  out_qualifier <- align_taxa("Boronia affinis otherspecies", resources, intergrades_affinis = TRUE)
  expect_equal(out_qualifier$taxon_rank, "genus")
  expect_equal(out_qualifier$alignment_code, "match_04a_intergrade_affinis_exact_genus")
})

test_that("intergrades_affinis = FALSE (default) leaves these names unhandled by match_04", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia aff. serrulata", resources)

  expect_false(isTRUE(startsWith(out$alignment_code, "match_04")))
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
