# ---- input validation (no taxadb/network call needed) -----------------------------------------
# (The "taxadb isn't installed" guard itself -- a plain `if (!requireNamespace(...)) stop(...)` --
# isn't tested directly here: requireNamespace() is a base function, not a package-namespace
# binding local_mocked_bindings() can intercept, and genuinely uninstalling taxadb just to test the
# error message isn't worth the disruption to every other test in this file.)

test_that("taxon_name is required and cannot be missing/NA", {
  skip_if_not_installed("taxadb")
  expect_error(generate_taxadb_taxonomic_reference_list(), "`taxon_name` must be a single")
  expect_error(generate_taxadb_taxonomic_reference_list(character(0)), "`taxon_name` must be a single")
  expect_error(generate_taxadb_taxonomic_reference_list(NA_character_), "`taxon_name` must be a single")
})

test_that("rank is required, and its error message explains it means something different from the sibling function's own `rank`", {
  skip_if_not_installed("taxadb")
  expect_error(
    generate_taxadb_taxonomic_reference_list("Chordata"),
    "`rank` is required"
  )
  expect_error(
    generate_taxadb_taxonomic_reference_list("Chordata"),
    "generate_GBIF_taxonomic_reference_list"
  )
})

test_that("country filtering is only supported for provider = 'gbif'", {
  skip_if_not_installed("taxadb")
  expect_error(
    generate_taxadb_taxonomic_reference_list("Mammalia", rank = "class", provider = "itis_test", country = "AU"),
    "only supported for `provider = \"gbif\"`"
  )
})

test_that("country must be a 2-letter ISO code, not a country name", {
  skip_if_not_installed("taxadb")
  expect_error(
    generate_taxadb_taxonomic_reference_list("Chordata", rank = "phylum", provider = "gbif", country = "Australia"),
    "2-letter ISO 3166-1 alpha-2"
  )
})

# ---- core reshape, against taxadb's own tiny bundled "itis_test" fixture (real, offline, fast --
# no network and no mocking needed, since this is a small subset of ITIS shipped inside the taxadb
# package itself purely for testing purposes) -----------------------------------------------------

test_that("returns taxonAlign's flat schema, reshaped from taxadb's Darwin Core columns", {
  skip_if_not_installed("taxadb")
  out <- generate_taxadb_taxonomic_reference_list("Mammalia", rank = "class", provider = "itis_test", quiet = TRUE)

  expect_setequal(
    names(out),
    c("taxon_ID", "accepted_name_usage_ID", "scientific_name", "canonical_name", "taxon_rank",
      "taxonomic_status", "kingdom", "phylum", "class", "order", "family", "genus", "taxonomic_dataset")
  )
  expect_true(all(out$taxonomic_dataset == "ITIS_TEST"))
  expect_true(all(out$taxon_rank == tolower(out$taxon_rank)))
  # taxadb has no separate authorship field -- scientific_name and canonical_name are identical here,
  # unlike generate_GBIF_taxonomic_reference_list()'s output
  expect_equal(out$scientific_name, out$canonical_name)
})

test_that("filters on the requested rank's own column, not just any column", {
  skip_if_not_installed("taxadb")
  out <- generate_taxadb_taxonomic_reference_list("Callitrichidae", rank = "family", provider = "itis_test", quiet = TRUE)

  expect_true(nrow(out) > 0)
  expect_true(all(out$family == "Callitrichidae"))
})

test_that("accepted_name_usage_ID is self-referential for an accepted row and points forward for a synonym", {
  skip_if_not_installed("taxadb")
  out <- generate_taxadb_taxonomic_reference_list("Mammalia", rank = "class", provider = "itis_test", quiet = TRUE)

  accepted <- out[out$taxonomic_status == "accepted", ][1, ]
  synonym <- out[out$taxonomic_status == "synonym", ][1, ]

  expect_equal(accepted$taxon_ID, accepted$accepted_name_usage_ID)
  expect_false(synonym$taxon_ID == synonym$accepted_name_usage_ID)
})

test_that("include_synonyms = FALSE drops synonym rows", {
  skip_if_not_installed("taxadb")
  out_all <- generate_taxadb_taxonomic_reference_list("Mammalia", rank = "class", provider = "itis_test", quiet = TRUE)
  out_accepted <- generate_taxadb_taxonomic_reference_list(
    "Mammalia", rank = "class", provider = "itis_test", include_synonyms = FALSE, quiet = TRUE
  )

  expect_true(any(out_all$taxonomic_status == "synonym"))
  expect_true(all(out_accepted$taxonomic_status == "accepted"))
  expect_true(nrow(out_accepted) < nrow(out_all))
})

test_that("errors clearly when no rows match the requested name/rank/provider", {
  skip_if_not_installed("taxadb")
  expect_error(
    generate_taxadb_taxonomic_reference_list("NotARealTaxon", rank = "class", provider = "itis_test", quiet = TRUE),
    "No rows found"
  )
})

# ---- country filtering (provider = "gbif"), fully mocked -- taxadb's own td_create()/taxa_tbl()
# stubbed to a small hand-built tibble (in taxadb's real "GBIF:<key>"-prefixed ID format) rather than
# downloading the real GBIF snapshot, and rgbif's name_backbone()/occ_search() mocked the same way
# test-generate_GBIF_taxonomic_reference_list.R already mocks them for the sibling function ---------

test_that("country filtering keeps a row whose own key occurs, or whose accepted key's does, and drops the rest", {
  skip_if_not_installed("taxadb")

  fake_gbif_table <- tibble::tibble(
    taxonID = c("GBIF:1", "GBIF:2", "GBIF:3", "GBIF:4"),
    scientificName = c("Chordata", "Genus alpha", "Genus beta", "Genus gamma"),
    taxonRank = c("phylum", "species", "species", "species"),
    taxonomicStatus = c("accepted", "accepted", "accepted", "synonym"),
    # row 4 is a synonym of row 2 (Genus alpha) -- its own key (4) has no occurrence record, but its
    # accepted usage's key (1... deliberately wrong on purpose below to prove which key is checked)
    acceptedNameUsageID = c(NA, NA, NA, "GBIF:2"),
    kingdom = "Animalia", phylum = "Chordata", class = NA_character_, order = NA_character_,
    family = NA_character_, genus = c(NA, "Genus", "Genus", "Genus")
  )

  local_mocked_bindings(
    td_create = function(...) invisible(NULL),
    taxa_tbl = function(provider, ...) fake_gbif_table,
    .package = "taxadb"
  )
  local_mocked_bindings(
    name_backbone = function(...) gbif_backbone_match(1, "Chordata", rank = "PHYLUM"),
    .package = "rgbif"
  )
  local_mocked_bindings(
    # only key 2 (Genus alpha) has an occurrence record in the fake facet -- key 3 (Genus beta) has
    # none of its own, and key 4 (the synonym) has none either, but should still be kept because its
    # *accepted* usage (key 2) does
    occ_search = function(...) gbif_occ_facet(c(2)),
    .package = "rgbif"
  )

  out <- generate_taxadb_taxonomic_reference_list(
    "Chordata", rank = "phylum", provider = "gbif", country = "AU",
    cache_dir = withr::local_tempdir(), quiet = TRUE
  )

  expect_setequal(out$canonical_name, c("Genus alpha", "Genus gamma"))
})
