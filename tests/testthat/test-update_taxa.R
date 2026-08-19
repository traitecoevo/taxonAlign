# These tests deliberately exercise update_taxa()'s single, rank-agnostic lookup at three distinct
# ranks (species, genus, order) using the *same* function with no per-rank branching -- proving the
# "one uniform function, not five APCalign-style rank/dataset-specific ones" design, not just
# asserting it in prose.

test_that("update_taxa leaves an already-accepted species name unchanged", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  aligned <- align_taxa("Boronia serrulata Sm.", resources)
  out <- update_taxa(aligned, resources)

  expect_equal(out$accepted_name, "Boronia serrulata")
  expect_equal(out$suggested_name, "Boronia serrulata")
  expect_equal(out$taxonomic_status_aligned, "accepted")
  expect_equal(out$taxonomic_status, "accepted")
  expect_match(out$update_reason, "already the current accepted name")
})

test_that("update_taxa resolves a species-level synonym forward, refreshing its outdated genus", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  aligned <- align_taxa("Boronia oldname Sm.", resources)
  out <- update_taxa(aligned, resources)

  expect_equal(aligned$taxonomic_status, "synonym") # sanity check on the pre-update state
  expect_equal(out$accepted_name, "Boronia serrulata")
  expect_equal(out$suggested_name, "Boronia serrulata")
  expect_equal(out$taxonomic_status_aligned, "synonym")
  expect_equal(out$taxonomic_status, "accepted")
  # "Zieria" in the fixture is a deliberately outdated genus for this synonym -- it should refresh to
  # the accepted record's genus, not stay as whatever the synonym row recorded
  expect_equal(out$genus, "Boronia")
  expect_match(out$update_reason, "Updated to the current accepted name")
})

test_that("update_taxa resolves a genus-level synonym forward (not just species)", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  aligned <- align_taxa("Boronella", resources)
  out <- update_taxa(aligned, resources)

  expect_equal(aligned$taxon_rank, "genus")
  expect_equal(out$accepted_name, "Boronia")
  expect_equal(out$suggested_name, "Boronia")
  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$taxonomic_status_aligned, "synonym")
  expect_equal(out$taxonomic_status, "accepted")
})

test_that("update_taxa resolves a synonym at a third, arbitrary higher rank ('order')", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  aligned <- align_taxa("Oldorderia", resources)
  out <- update_taxa(aligned, resources)

  expect_equal(aligned$taxon_rank, "order")
  expect_equal(out$accepted_name, "Sapindales")
  expect_equal(out$suggested_name, "Sapindales")
  expect_equal(out$taxon_rank, "order")
  expect_equal(out$taxonomic_status_aligned, "synonym")
  expect_equal(out$taxonomic_status, "accepted")
})

test_that("update_taxa degrades gracefully when accepted_name_usage_ID doesn't resolve", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  aligned <- align_taxa("Boronia missingaccepted Sm.", resources)
  out <- update_taxa(aligned, resources)

  expect_equal(aligned$taxonomic_status, "synonym")
  expect_true(is.na(out$accepted_name))
  expect_equal(out$suggested_name, aligned$aligned_name) # falls back to the aligned name
  expect_equal(out$taxonomic_status, "synonym") # unresolved -- keeps the pre-update status, not "unknown"
  expect_match(out$update_reason, "could not be resolved")
})

test_that("update_taxa reports 'unknown' status and NA names for a completely unmatched name", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  aligned <- align_taxa("Completely unrelated nonsense taxon", resources)
  out <- update_taxa(aligned, resources)

  expect_true(is.na(aligned$aligned_name))
  expect_true(is.na(out$accepted_name))
  expect_true(is.na(out$suggested_name))
  expect_equal(out$taxonomic_status, "unknown")
  expect_true(is.na(out$update_reason))
})

test_that("update_taxa errors clearly when aligned_data is missing required columns", {
  expect_error(
    update_taxa(dplyr::tibble(aligned_name = "x"), resources = list()),
    "missing required column"
  )
})
