# ---- input validation -------------------------------------------------

test_that("taxon_name is required and cannot be missing/NA", {
  expect_error(generate_taxonomic_reference_list(), "`taxon_name` is required")
  expect_error(generate_taxonomic_reference_list(character(0)), "`taxon_name` is required")
  expect_error(generate_taxonomic_reference_list(NA_character_), "`taxon_name` is required")
  expect_error(generate_taxonomic_reference_list(c("Boronia", NA)), "`taxon_name` is required")
})

test_that("rank must be one of the known GBIF ranks", {
  expect_error(
    generate_taxonomic_reference_list("Boronia", rank = "not_a_rank"),
    "`rank` must be one of"
  )
})

test_that("rank matching is case-insensitive", {
  local_mocked_bindings(
    name_backbone = function(...) gbif_backbone_match(1, "Boronia Sm.", rank = "GENUS"),
    .package = "rgbif"
  )
  local_mocked_bindings(
    name_lookup = function(...) gbif_lookup_page(gbif_taxon_row(2, parentKey = 1, scientificName = "Boronia serrulata", rank = "SPECIES", genus = "Boronia")),
    name_usage = function(...) list(data = gbif_taxon_row(1, scientificName = "Boronia Sm.", rank = "GENUS")),
    .package = "rgbif"
  )

  out <- generate_taxonomic_reference_list("Boronia", rank = "SPECIES", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_true(all(out$taxon_rank == "species"))
})

test_that("name_rank/name_kingdom must be length 1 or match taxon_name", {
  expect_error(
    generate_taxonomic_reference_list(c("Boronia", "Zieria"), name_rank = c("genus", "genus", "genus")),
    "`name_rank` must have length 1"
  )
})

# ---- recycle_against_taxon_name -----------------------------------------

test_that("recycle_against_taxon_name recycles, passes through, or errors", {
  expect_null(recycle_against_taxon_name(NULL, c("a", "b"), "x"))
  expect_equal(recycle_against_taxon_name("genus", c("a", "b"), "x"), c("genus", "genus"))
  expect_equal(recycle_against_taxon_name(c("genus", "family"), c("a", "b"), "x"), c("genus", "family"))
  expect_error(
    recycle_against_taxon_name(c("genus", "family"), c("a", "b", "c"), "name_rank"),
    "`name_rank` must have length 1 or the same length as `taxon_name`"
  )
})

# ---- cache_is_fresh -------------------------------------------------------

test_that("cache_is_fresh reports FALSE for a missing file", {
  expect_false(cache_is_fresh(file.path(withr::local_tempdir(), "missing.rds"), max_cache_age_days = 30))
})

test_that("cache_is_fresh distinguishes fresh from stale files", {
  fresh_file <- withr::local_tempfile()
  writeLines("x", fresh_file)
  expect_true(cache_is_fresh(fresh_file, max_cache_age_days = 30))

  stale_file <- withr::local_tempfile()
  writeLines("x", stale_file)
  # backdate the file well past max_cache_age_days
  old_time <- Sys.time() - as.difftime(60, units = "days")
  Sys.setFileTime(stale_file, old_time)
  expect_false(cache_is_fresh(stale_file, max_cache_age_days = 30))
})

# ---- resolve_gbif_taxon ----------------------------------------------------

test_that("resolve_gbif_taxon returns the usageKey for an accepted match", {
  local_mocked_bindings(
    name_backbone = function(...) gbif_backbone_match(101, "Boronia Sm.", rank = "GENUS"),
    .package = "rgbif"
  )
  result <- resolve_gbif_taxon("Boronia", NULL, NULL)
  expect_equal(result$key, 101L)
  expect_equal(result$rank, "genus")
})

test_that("resolve_gbif_taxon follows a synonym to its accepted usage key", {
  local_mocked_bindings(
    name_backbone = function(...) {
      gbif_backbone_match(202, "Zieria Sm.", rank = "GENUS", status = "SYNONYM", acceptedUsageKey = 101)
    },
    .package = "rgbif"
  )
  result <- resolve_gbif_taxon("Zieria", NULL, NULL)
  expect_equal(result$key, 101L)
})

test_that("resolve_gbif_taxon errors clearly on no match", {
  local_mocked_bindings(
    name_backbone = function(...) gbif_backbone_match(NA, "", rank = NA, matchType = "NONE", note = "no match because of x"),
    .package = "rgbif"
  )
  expect_error(resolve_gbif_taxon("Nonexistantia", NULL, NULL), "no match because of x")
})

test_that("resolve_gbif_taxon errors clearly on an ambiguous HIGHERRANK match", {
  local_mocked_bindings(
    name_backbone = function(...) gbif_backbone_match(5, "Plantae", rank = "KINGDOM", matchType = "HIGHERRANK"),
    .package = "rgbif"
  )
  expect_error(resolve_gbif_taxon("Zieria", NULL, NULL), "ambiguous on GBIF")
})

test_that("resolve_gbif_taxon does not error when name_backbone returns zero rows", {
  # regression test: nrow(match) == 0 used to make `!is.na(match$note)` a
  # zero-length logical, which errors inside `if()` ("missing value where
  # TRUE/FALSE needed") instead of producing the intended error message.
  local_mocked_bindings(
    name_backbone = function(...) gbif_backbone_match(1, "x", rank = "GENUS")[0, ],
    .package = "rgbif"
  )
  expect_error(resolve_gbif_taxon("Nonexistantia", NULL, NULL), "Could not match")
})

test_that("resolve_gbif_taxon errors when name_backbone returns NULL", {
  local_mocked_bindings(name_backbone = function(...) NULL, .package = "rgbif")
  expect_error(resolve_gbif_taxon("Nonexistantia", NULL, NULL), "Could not match")
})

# ---- fetch_gbif_taxon_tree -------------------------------------------------

test_that("fetch_gbif_taxon_tree combines the root usage with its descendants and dedups", {
  cache_dir <- withr::local_tempdir()
  descendants <- gbif_taxon_row(2, parentKey = 1, scientificName = "Boronia serrulata", rank = "SPECIES", genus = "Boronia")

  local_mocked_bindings(
    name_lookup = function(...) gbif_lookup_page(descendants),
    name_usage = function(key, ...) list(data = gbif_taxon_row(key, scientificName = "Boronia Sm.", rank = "GENUS")),
    .package = "rgbif"
  )

  tree <- fetch_gbif_taxon_tree(root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
                                 max_cache_age_days = 30, quiet = TRUE)

  expect_setequal(tree$key, c(1L, 2L))
  expect_true(file.exists(file.path(cache_dir, "gbif_tree_1.rds")))
})

test_that("fetch_gbif_taxon_tree serves a fresh cache without calling the API again", {
  cache_dir <- withr::local_tempdir()
  descendants <- gbif_taxon_row(2, parentKey = 1, scientificName = "Boronia serrulata", rank = "SPECIES", genus = "Boronia")

  local_mocked_bindings(
    name_lookup = function(...) gbif_lookup_page(descendants),
    name_usage = function(key, ...) list(data = gbif_taxon_row(key, scientificName = "Boronia Sm.", rank = "GENUS")),
    .package = "rgbif"
  )
  first <- fetch_gbif_taxon_tree(root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
                                  max_cache_age_days = 30, quiet = TRUE)

  # any further calls to the API in this scope should fail the test
  local_mocked_bindings(
    name_lookup = function(...) stop("should not be called: cache should have been used"),
    name_usage = function(...) stop("should not be called: cache should have been used"),
    .package = "rgbif"
  )
  second <- fetch_gbif_taxon_tree(root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
                                   max_cache_age_days = 30, quiet = TRUE)

  expect_equal(first, second)
})

test_that("fetch_gbif_taxon_tree refuses a huge tree unless force_large_fetch = TRUE", {
  cache_dir <- withr::local_tempdir()
  local_mocked_bindings(
    name_lookup = function(...) gbif_lookup_page(gbif_taxon_row(2, scientificName = "x", rank = "SPECIES"), count = 999999),
    .package = "rgbif"
  )

  expect_error(
    fetch_gbif_taxon_tree(root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
                           max_cache_age_days = 30, quiet = TRUE, max_taxa = 50000),
    "more than `max_taxa`"
  )
})

test_that("fetch_gbif_taxon_tree pages through results beyond one page", {
  cache_dir <- withr::local_tempdir()
  page_limit <- 1000
  total <- 1500
  full_data <- gbif_taxon_row(
    key = seq_len(total) + 1L,
    scientificName = paste("Species", seq_len(total)),
    rank = "SPECIES",
    genus = "Boronia"
  )

  local_mocked_bindings(
    name_lookup = function(higherTaxonKey, datasetKey, limit, start, ...) {
      end <- min(start + limit, total)
      idx <- seq.int(start + 1, end)
      gbif_lookup_page(full_data[idx, ], count = total)
    },
    name_usage = function(key, ...) list(data = gbif_taxon_row(key, scientificName = "Boronia Sm.", rank = "GENUS")),
    .package = "rgbif"
  )

  tree <- fetch_gbif_taxon_tree(root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
                                 max_cache_age_days = 30, quiet = TRUE, max_taxa = 5000)

  # 1 root + `total` descendants, all unique
  expect_equal(nrow(tree), total + 1)
  expect_equal(length(unique(tree$key)), total + 1)
})

# ---- fetch_gbif_country_keys -----------------------------------------------

test_that("fetch_gbif_country_keys returns the taxonKey facet as integers", {
  cache_dir <- withr::local_tempdir()
  local_mocked_bindings(
    occ_search = function(...) gbif_occ_facet(c(101, 202)),
    .package = "rgbif"
  )

  keys <- fetch_gbif_country_keys(
    roots = list(list(key = 1L)), country = "au", cache_dir = cache_dir,
    refresh_cache = FALSE, max_cache_age_days = 30, facet_limit = 100000, quiet = TRUE
  )
  expect_setequal(keys, c(101L, 202L))
})

test_that("fetch_gbif_country_keys warns when the facet may be truncated", {
  cache_dir <- withr::local_tempdir()
  local_mocked_bindings(
    occ_search = function(...) gbif_occ_facet(c(101, 202)),
    .package = "rgbif"
  )

  expect_warning(
    fetch_gbif_country_keys(
      roots = list(list(key = 1L)), country = "AU", cache_dir = cache_dir,
      refresh_cache = FALSE, max_cache_age_days = 30, facet_limit = 2, quiet = TRUE
    ),
    "facet_limit"
  )
})

test_that("fetch_gbif_country_keys serves a fresh cache without calling the API again", {
  cache_dir <- withr::local_tempdir()
  local_mocked_bindings(occ_search = function(...) gbif_occ_facet(c(101)), .package = "rgbif")
  first <- fetch_gbif_country_keys(
    roots = list(list(key = 1L)), country = "AU", cache_dir = cache_dir,
    refresh_cache = FALSE, max_cache_age_days = 30, facet_limit = 100000, quiet = TRUE
  )

  local_mocked_bindings(
    occ_search = function(...) stop("should not be called: cache should have been used"),
    .package = "rgbif"
  )
  second <- fetch_gbif_country_keys(
    roots = list(list(key = 1L)), country = "AU", cache_dir = cache_dir,
    refresh_cache = FALSE, max_cache_age_days = 30, facet_limit = 100000, quiet = TRUE
  )
  expect_equal(first, second)
})

# ---- generate_taxonomic_reference_list (end to end, GBIF calls mocked) ----

local_mock_gbif_end_to_end <- function(.env = parent.frame()) {
  # tree for root key 1 ("Boronia"): itself (genus), an accepted species (2),
  # and a synonym of that species (3, accepted_key = 2)
  #
  # NB: `.env` must be forwarded to `local_mocked_bindings()` -- otherwise the
  # mock's lifetime is tied to *this* helper's own frame (which returns
  # immediately), undoing it before the calling `test_that()` block runs.
  local_mocked_bindings(
    name_backbone = function(name, ...) {
      if (identical(name, "Boronia")) {
        gbif_backbone_match(1, "Boronia Sm.", rank = "GENUS")
      } else {
        gbif_backbone_match(10, "Zieria Sm.", rank = "GENUS", kingdom = "Plantae")
      }
    },
    name_lookup = function(higherTaxonKey, ...) {
      if (higherTaxonKey == 1) {
        gbif_lookup_page(dplyr::bind_rows(
          gbif_taxon_row(2, parentKey = 1, scientificName = "Boronia serrulata Sm.",
                          canonicalName = "Boronia serrulata", rank = "SPECIES", genus = "Boronia"),
          gbif_taxon_row(3, parentKey = 1, acceptedKey = 2, scientificName = "Boronia pinnata var. x",
                         canonicalName = "Boronia pinnata var. x", rank = "VARIETY",
                         taxonomicStatus = "SYNONYM", genus = "Boronia")
        ))
      } else {
        gbif_lookup_page(gbif_taxon_row(20, parentKey = 10, scientificName = "Zieria smithii",
                                         rank = "SPECIES", genus = "Zieria"))
      }
    },
    name_usage = function(key, ...) {
      if (key == 1) {
        list(data = gbif_taxon_row(1, scientificName = "Boronia Sm.", rank = "GENUS", genus = NA_character_))
      } else {
        list(data = gbif_taxon_row(10, scientificName = "Zieria Sm.", rank = "GENUS", genus = NA_character_))
      }
    },
    occ_search = function(taxonKey, ...) {
      if (taxonKey == 1) gbif_occ_facet(c(2)) else gbif_occ_facet(c(20))
    },
    .package = "rgbif",
    .env = .env
  )
}

test_that("generate_taxonomic_reference_list returns the documented columns", {
  local_mock_gbif_end_to_end()
  out <- generate_taxonomic_reference_list("Boronia", cache_dir = withr::local_tempdir(), quiet = TRUE)

  expect_s3_class(out, "tbl_df")
  expect_setequal(
    names(out),
    c("gbif_key", "parent_key", "accepted_key", "taxon_name", "canonical_name",
      "taxon_rank", "taxonomic_status", "kingdom", "phylum", "class", "order",
      "family", "genus", "taxonomic_reference")
  )
  expect_equal(unique(out$taxonomic_reference), "GBIF")
  expect_setequal(out$gbif_key, c(1L, 2L, 3L))
})

test_that("include_synonyms = FALSE drops synonym rows", {
  local_mock_gbif_end_to_end()
  out <- generate_taxonomic_reference_list(
    "Boronia", include_synonyms = FALSE, cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_false("synonym" %in% out$taxonomic_status)
  expect_setequal(out$gbif_key, c(1L, 2L))
})

test_that("rank filters to that rank and narrower", {
  local_mock_gbif_end_to_end()
  out <- generate_taxonomic_reference_list(
    "Boronia", rank = "species", cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_true(all(out$taxon_rank %in% c("species", "variety")))
  expect_false("genus" %in% out$taxon_rank)
})

test_that("country restricts to taxa with an occurrence record there (including via accepted_key)", {
  local_mock_gbif_end_to_end()
  out <- generate_taxonomic_reference_list(
    "Boronia", country = "au", cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  # key 2 has the occurrence; key 3 (its synonym) is kept via accepted_key
  expect_setequal(out$gbif_key, c(2L, 3L))
})

test_that("multiple taxon_name values are resolved and merged with no duplicate keys", {
  local_mock_gbif_end_to_end()
  out <- generate_taxonomic_reference_list(
    c("Boronia", "Zieria"), cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_setequal(out$gbif_key, c(1L, 2L, 3L, 10L, 20L))
  expect_equal(anyDuplicated(out$gbif_key), 0)
})

test_that("output is deduplicated even if the same taxon is requested twice", {
  local_mock_gbif_end_to_end()
  out <- generate_taxonomic_reference_list(
    c("Boronia", "Boronia"), cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_equal(anyDuplicated(out$gbif_key), 0)
})
