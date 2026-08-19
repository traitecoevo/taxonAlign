test_that("create_taxonomic_update_lookup runs align_taxa + update_taxa end to end", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  names <- c("Boronia serrulata Sm.", "Boronia oldname Sm.", "Boronella", "Completely unrelated nonsense taxon")
  out <- create_taxonomic_update_lookup(names, resources)

  expect_equal(nrow(out), length(names))
  expect_equal(out$original_name, names)
  expect_equal(out$accepted_name, c("Boronia serrulata", "Boronia serrulata", "Boronia", NA))
  expect_equal(out$suggested_name, c("Boronia serrulata", "Boronia serrulata", "Boronia", NA))
  expect_equal(out$taxonomic_status_aligned, c("accepted", "synonym", "synonym", NA))
  expect_equal(out$taxonomic_status, c("accepted", "accepted", "accepted", "unknown"))
})

test_that("create_taxonomic_update_lookup's default output has the documented slim column set", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  out <- create_taxonomic_update_lookup("Boronia serrulata Sm.", resources)

  expect_setequal(
    names(out),
    c("original_name", "aligned_name", "accepted_name", "suggested_name", "genus", "family",
      "taxon_rank", "taxonomic_dataset", "taxonomic_status", "taxonomic_status_aligned",
      "aligned_reason", "update_reason", "identifier")
  )
})

test_that("create_taxonomic_update_lookup(full = TRUE) returns the fuller intermediate columns too", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  out <- create_taxonomic_update_lookup("Boronia serrulata Sm.", resources, full = TRUE)

  expect_true(all(c("stripped_name", "trinomial", "binomial", "taxon_ID", "accepted_name_usage_ID") %in% names(out)))
})

test_that("create_taxonomic_update_lookup forwards fuzzy-matching arguments to align_taxa", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  # with fuzzy matching off, the misspelled species epithet ("serulata") no longer fuzzy-matches at
  # species level -- but the correctly-spelled genus ("Boronia") still resolves via the (non-fuzzy)
  # genus-level fallback block, so this isn't left entirely unmatched, just resolved at a coarser rank
  out <- create_taxonomic_update_lookup("Boronia serulata", resources, fuzzy_matches = FALSE)

  expect_false(is.na(out$aligned_name))
  expect_equal(out$taxon_rank, "genus")
  expect_equal(out$accepted_name, "Boronia")

  # confirm fuzzy matching genuinely was disabled: with it on (the default), the same name resolves
  # to the species itself, not just its genus
  out_fuzzy <- create_taxonomic_update_lookup("Boronia serulata", resources, fuzzy_matches = TRUE)
  expect_equal(out_fuzzy$accepted_name, "Boronia serrulata")
})
