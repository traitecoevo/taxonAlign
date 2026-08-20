test_that("create_taxonomic_update_lookup runs align_taxa + update_taxa end to end", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
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
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- create_taxonomic_update_lookup("Boronia serrulata Sm.", resources)

  expect_setequal(
    names(out),
    c("original_name", "aligned_name", "accepted_name", "suggested_name", "genus", "family",
      "taxon_rank", "taxonomic_dataset", "taxonomic_status", "taxonomic_status_aligned",
      "aligned_reason", "update_reason", "identifier")
  )
})

test_that("create_taxonomic_update_lookup(full = TRUE) returns the fuller intermediate columns too", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- create_taxonomic_update_lookup("Boronia serrulata Sm.", resources, full = TRUE)

  expect_true(all(c("stripped_name", "trinomial", "binomial", "taxon_ID", "accepted_name_usage_ID") %in% names(out)))
})

test_that("create_taxonomic_update_lookup forwards fuzzy-matching arguments to align_taxa", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
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

test_that("create_taxonomic_update_lookup forwards include_bracketed_info to align_taxa", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  out_default <- create_taxonomic_update_lookup("Boronia", resources)
  out_bracketed <- create_taxonomic_update_lookup("Boronia", resources, include_bracketed_info = TRUE)

  expect_equal(out_default$aligned_name, "Boronia")
  expect_equal(out_bracketed$aligned_name, "Boronia sp. [Boronia]")
  # the update step downstream is unaffected either way -- it resolves via taxon_ID, not the
  # aligned_name string
  expect_equal(out_default$accepted_name, "Boronia")
  expect_equal(out_bracketed$accepted_name, "Boronia")
})

test_that("create_taxonomic_update_lookup gives a clear, actionable error when resources is missing", {
  expect_error(create_taxonomic_update_lookup("Boronia serrulata"), "prepare_taxonomic_resources")
})

test_that("create_taxonomic_update_lookup accepts a flat, already-formatted resources tibble directly", {
  out_direct <- create_taxonomic_update_lookup("Boronia oldname Sm.", resources = sample_taxonomic_resources())
  out_prepared <- create_taxonomic_update_lookup(
    "Boronia oldname Sm.", resources = prepare_taxonomic_resources(sample_taxonomic_resources())
  )

  expect_equal(out_direct, out_prepared)
  expect_equal(out_direct$accepted_name, "Boronia serrulata")
})
