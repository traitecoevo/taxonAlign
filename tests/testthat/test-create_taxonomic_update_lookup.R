test_that("create_taxonomic_update_lookup runs align_taxa + update_taxa end to end", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  names <- c("Boronia serrulata Sm.", "Boronia oldname Sm.", "Boronella", "Completely unrelated nonsense taxon")
  out <- create_taxonomic_update_lookup(names, resources)

  expect_equal(nrow(out), length(names))
  expect_equal(out$original_name, names)
  expect_equal(out$accepted_name, c("Boronia serrulata", "Boronia serrulata", "Boronia", NA))
  # a bare genus synonym updates to its plain accepted genus (no "sp." added, user's decision 2026-11-22)
  expect_equal(out$suggested_name, c("Boronia serrulata", "Boronia serrulata", "Boronia", NA))
  expect_equal(out$taxonomic_status_aligned, c("accepted", "synonym", "synonym", NA))
  expect_equal(out$taxonomic_status, c("accepted", "accepted", "accepted", "unknown"))
})

test_that("create_taxonomic_update_lookup retains chars_changed (issue #20)", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- create_taxonomic_update_lookup(c("Boronia serulata", "Boronia serrulata Sm."), resources)

  expect_equal(out$chars_changed, c(1L, 0L))
})

test_that("create_taxonomic_update_lookup's default output has the documented slim column set", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- create_taxonomic_update_lookup("Boronia serrulata Sm.", resources)

  expect_setequal(
    names(out),
    c("original_name", "aligned_name", "accepted_name", "suggested_name", "genus", "taxon_rank",
      "taxonomic_dataset", "taxonomic_status", "scientific_name", "aligned_reason", "update_reason",
      "number_of_collapsed_taxa", "taxon_ID", "taxon_ID_genus", "scientific_name_ID", "family",
      "taxonomic_status_aligned", "alternative_possible_names", "chars_changed", "identifier")
  )
})

test_that("every column APCalign's lookup returns, taxonAlign's does too", {
  # the user's rule: taxonAlign's output includes everything APCalign's does (and may add more).
  # APCalign 2.0.1's create_taxonomic_update_lookup() columns, without and with `full = TRUE`
  apcalign_slim <- c(
    "original_name", "aligned_name", "accepted_name", "suggested_name", "genus", "taxon_rank",
    "taxonomic_dataset", "taxonomic_status", "scientific_name", "aligned_reason", "update_reason",
    "number_of_collapsed_taxa"
  )
  apcalign_full <- c(
    apcalign_slim, "family", "taxonomic_status_aligned", "subclass", "taxon_distribution", "taxon_ID",
    "taxon_ID_genus", "scientific_name_ID", "canonical_name", "row_number"
  )
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  slim <- create_taxonomic_update_lookup("Boronia serrulata Sm.", resources)
  full <- create_taxonomic_update_lookup("Boronia serrulata Sm.", resources, full = TRUE)
  expect_true(all(apcalign_slim %in% names(slim)))
  expect_true(all(apcalign_full %in% names(full)))
  # ...in APCalign's order, ahead of taxonAlign's own
  expect_equal(names(slim)[seq_along(apcalign_slim)], apcalign_slim)
})

test_that("the ID columns describe the suggested taxon, as in APCalign", {
  ref <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID, ~scientific_name_ID, ~taxon_distribution,
    "Eucalyptus", "Eucalyptus L'Her.", "genus", "accepted", "Eucalyptus", "g1", "g1", "ipni:g1", NA,
    "Eucalyptus globulus", "Eucalyptus globulus Labill.", "species", "accepted", "Eucalyptus", "s1", "s1", "ipni:s1", "Tas, Vic",
    "Eucalyptus gigantea", "Eucalyptus gigantea Dehnh.", "species", "synonym", "Eucalyptus", "s2", "s1", "ipni:s2", NA,
    "Eucalyptus dubia", "Eucalyptus dubia Sm.", "species", "unplaced", "Eucalyptus", "s3", "s3", "ipni:s3", NA,
    "Eucalyptus regnans", "Eucalyptus regnans F.Muell.", "species", "accepted", "Eucalyptus", "s4", "s4", "ipni:s4", "Vic",
    "Eucalyptus ambigua", "Eucalyptus ambigua Sm.", "species", "synonym", "Eucalyptus", "s5", "s1", "ipni:s5", NA,
    "Eucalyptus ambigua", "Eucalyptus ambigua Sm.", "species", "synonym", "Eucalyptus", "s6", "s4", "ipni:s6", NA
  ) |> dplyr::mutate(taxonomic_dataset = "TEST")
  q <- c("Eucalyptus gigantea", "Eucalyptus dubia", "Eucalyptus sp.", "Eucalyptus ambigua", "nonsense")
  out <- create_taxonomic_update_lookup(q, ref, full = TRUE)

  # a synonym: the accepted taxon's ID, name and authorship; the matched record's ID kept as aligned_taxon_ID
  expect_equal(out$taxon_ID, c("s1", NA, "g1", "s1", NA))
  expect_equal(out$aligned_taxon_ID, c("s2", "s3", "g1", "s5", NA))
  expect_equal(out$scientific_name_ID, c("ipni:s1", "ipni:s3", "ipni:g1", "ipni:s1", NA))
  expect_equal(out$scientific_name[1:3], c("Eucalyptus globulus Labill.", "Eucalyptus dubia Sm.", "Eucalyptus L'Her."))
  expect_equal(out$taxon_ID_genus, c("g1", "g1", "g1", "g1", NA))
  expect_equal(out$taxon_distribution[1], "Tas, Vic")
  expect_true(all(is.na(out$subclass)))
  expect_equal(out$canonical_name, out$suggested_name)
  expect_equal(out$row_number, 1:5)
  # a split: 1 when one name is suggested, the number of candidates when collapsed to genus
  expect_equal(out$number_of_collapsed_taxa, c(NA, NA, NA, 1L, NA))
  collapsed <- create_taxonomic_update_lookup("Eucalyptus ambigua", ref, taxonomic_splits = "collapse_to_higher_taxon")
  expect_equal(collapsed$number_of_collapsed_taxa, 2L)
  expect_equal(collapsed$taxon_ID, "g1")
  expect_equal(collapsed$scientific_name, "Eucalyptus L'Her.")
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

  # a bare name stays bare by default (user's decision, 2026-11-22: the input didn't say "sp.");
  # TRUE gives it as though it had ended in "sp."
  out_default <- create_taxonomic_update_lookup("Boronia", resources)
  out_bracketed <- create_taxonomic_update_lookup("Boronia", resources, include_bracketed_info = TRUE)

  expect_equal(out_default$aligned_name, "Boronia")
  expect_equal(out_bracketed$aligned_name, "Boronia sp.")
  expect_equal(out_default$suggested_name, "Boronia")
  expect_equal(out_bracketed$suggested_name, "Boronia sp.")
  # the update step is unaffected either way -- it resolves via taxon_ID, not the aligned_name string
  expect_equal(out_default$accepted_name, "Boronia")
  expect_equal(out_bracketed$accepted_name, "Boronia")
})

test_that("create_taxonomic_update_lookup gives a clear, actionable error when resources is missing", {
  expect_error(create_taxonomic_update_lookup("Boronia serrulata"), "load_taxonomic_resources")
})

test_that("create_taxonomic_update_lookup accepts a flat, already-formatted resources tibble directly", {
  out_direct <- create_taxonomic_update_lookup("Boronia oldname Sm.", resources = sample_taxonomic_resources())
  out_prepared <- create_taxonomic_update_lookup(
    "Boronia oldname Sm.", resources = prepare_taxonomic_resources(sample_taxonomic_resources())
  )

  expect_equal(out_direct, out_prepared)
  expect_equal(out_direct$accepted_name, "Boronia serrulata")
})
