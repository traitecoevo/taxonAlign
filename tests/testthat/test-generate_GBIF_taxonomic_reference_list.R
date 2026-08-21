# ---- input validation -------------------------------------------------

test_that("taxon_name is required and cannot be missing/NA", {
  expect_error(generate_GBIF_taxonomic_reference_list(), "`taxon_name` is required")
  expect_error(generate_GBIF_taxonomic_reference_list(character(0)), "`taxon_name` is required")
  expect_error(generate_GBIF_taxonomic_reference_list(NA_character_), "`taxon_name` is required")
  expect_error(generate_GBIF_taxonomic_reference_list(c("Boronia", NA)), "`taxon_name` is required")
})

test_that("rank must be one of the known GBIF ranks", {
  expect_error(
    generate_GBIF_taxonomic_reference_list("Boronia", rank = "not_a_rank"),
    "`rank` must be one of"
  )
})

test_that("country must be a 2-letter ISO code, not a country name", {
  # regression test: a country *name* (e.g. "Australia") silently passes through to
  # rgbif::occ_search(), which doesn't recognise it and returns an empty facet result -- rather than
  # erroring, this used to warn "Unknown or uninitialised column: `name`" and silently produce an
  # empty reference list.
  expect_error(
    generate_GBIF_taxonomic_reference_list("Boronia", country = "Australia"),
    "2-letter ISO 3166-1 alpha-2"
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

  out <- generate_GBIF_taxonomic_reference_list("Boronia", rank = "SPECIES", cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_true(all(out$taxon_rank == "species"))
})

test_that("name_rank/name_kingdom must be length 1 or match taxon_name", {
  expect_error(
    generate_GBIF_taxonomic_reference_list(c("Boronia", "Zieria"), name_rank = c("genus", "genus", "genus")),
    "`name_rank` must have length 1"
  )
})

# ---- with_gbif_retry (shared retry wrapper for non-paginated rgbif calls) ----------------------

test_that("resolve_gbif_taxon recovers from a transient name_backbone() failure via with_gbif_retry", {
  attempts <- 0
  local_mocked_bindings(
    name_backbone = function(...) {
      attempts <<- attempts + 1
      if (attempts < 3) stop("simulated transient network failure")
      gbif_backbone_match(1, "Boronia Sm.", rank = "GENUS")
    },
    .package = "rgbif"
  )

  root <- resolve_gbif_taxon("Boronia", name_rank = NULL, name_kingdom = NULL)

  expect_equal(attempts, 3)
  expect_equal(root$key, 1L)
})

test_that("with_gbif_retry gives up and errors clearly after exhausting attempts", {
  local_mocked_bindings(
    name_backbone = function(...) stop("persistent simulated failure"),
    .package = "rgbif"
  )

  expect_error(
    resolve_gbif_taxon("Boronia", name_rank = NULL, name_kingdom = NULL),
    "persistent simulated failure"
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

test_that("fetch_gbif_taxon_tree fetches pages concurrently via parallel_requests > 1, with no data loss", {
  # regression/coverage test for the parallel::mclapply() path specifically -- the previous test above
  # only ever has one *remaining* page (total = 1500, page_limit = 1000), so n_workers collapses to 1
  # and it never actually exercises mclapply(). Here total = 3500 gives 3 remaining pages (1000, 2000,
  # 3000), with parallel_requests = 2 forcing genuine concurrent fetching. Also confirms
  # local_mocked_bindings()'s mock survives mclapply()'s fork (each worker is a forked copy of this
  # process, inheriting whatever's already mocked at fork time) -- if it didn't, the mocked
  # `name_lookup`/`name_usage` wouldn't be visible in the child and this would error trying to hit the
  # real network instead.
  cache_dir <- withr::local_tempdir()
  page_limit <- 1000
  total <- 3500
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

  tree <- fetch_gbif_taxon_tree(
    root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
    max_cache_age_days = 30, quiet = TRUE, max_taxa = 5000, parallel_requests = 2
  )

  # 1 root + `total` descendants, all unique -- every page accounted for, none dropped/duplicated by
  # fetching them out of sequence
  expect_equal(nrow(tree), total + 1)
  expect_equal(length(unique(tree$key)), total + 1)
  expect_setequal(tree$key, c(1L, seq_len(total) + 1L))
})

test_that("fetch_gbif_taxon_tree errors clearly if a page fails, rather than silently losing it", {
  cache_dir <- withr::local_tempdir()
  page_limit <- 1000
  total <- 3500
  full_data <- gbif_taxon_row(
    key = seq_len(total) + 1L,
    scientificName = paste("Species", seq_len(total)),
    rank = "SPECIES",
    genus = "Boronia"
  )

  local_mocked_bindings(
    name_lookup = function(higherTaxonKey, datasetKey, limit, start, ...) {
      if (start == 2000) stop("simulated network failure")
      end <- min(start + limit, total)
      idx <- seq.int(start + 1, end)
      gbif_lookup_page(full_data[idx, ], count = total)
    },
    name_usage = function(key, ...) list(data = gbif_taxon_row(key, scientificName = "Boronia Sm.", rank = "GENUS")),
    .package = "rgbif"
  )

  expect_error(
    fetch_gbif_taxon_tree(
      root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
      max_cache_age_days = 30, quiet = TRUE, max_taxa = 5000, parallel_requests = 2
    ),
    "failed on"
  )
})

test_that("fetch_gbif_taxon_tree retries a page that fails transiently, rather than giving up immediately", {
  # a page that fails once or twice before succeeding (a transient network/TLS blip, observed in
  # practice on a large fetch) should still end up in the final tree -- not be treated as a permanent
  # failure. Uses parallel_requests = 1 to keep the attempt counter (an ordinary R environment, `<<-`'d
  # into) meaningful without any fork-related complications -- the retry logic itself lives inside
  # fetch_page_with_retry(), called identically whether or not mclapply() is used, so this exercises
  # the same code the parallel path relies on.
  cache_dir <- withr::local_tempdir()
  page_limit <- 1000
  total <- 2500
  full_data <- gbif_taxon_row(
    key = seq_len(total) + 1L,
    scientificName = paste("Species", seq_len(total)),
    rank = "SPECIES",
    genus = "Boronia"
  )

  attempts_at_1000 <- 0

  local_mocked_bindings(
    name_lookup = function(higherTaxonKey, datasetKey, limit, start, ...) {
      if (start == 1000) {
        attempts_at_1000 <<- attempts_at_1000 + 1
        if (attempts_at_1000 < 3) stop("simulated transient network failure")
      }
      end <- min(start + limit, total)
      idx <- seq.int(start + 1, end)
      gbif_lookup_page(full_data[idx, ], count = total)
    },
    name_usage = function(key, ...) list(data = gbif_taxon_row(key, scientificName = "Boronia Sm.", rank = "GENUS")),
    .package = "rgbif"
  )

  tree <- fetch_gbif_taxon_tree(
    root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
    max_cache_age_days = 30, quiet = TRUE, max_taxa = 5000, parallel_requests = 1
  )

  expect_equal(attempts_at_1000, 3)
  expect_equal(nrow(tree), total + 1)
})

test_that("parallel_requests = 1 fetches strictly sequentially and still returns the full tree", {
  cache_dir <- withr::local_tempdir()
  page_limit <- 1000
  total <- 2500
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

  tree <- fetch_gbif_taxon_tree(
    root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
    max_cache_age_days = 30, quiet = TRUE, max_taxa = 5000, parallel_requests = 1
  )

  expect_equal(nrow(tree), total + 1)
})

# ---- fetch_gbif_taxon_tree_by_children (clades exceeding GBIF's max lookup offset) -----------------

test_that("fetch_gbif_taxon_tree splits into children and recurses when a clade exceeds the max lookup offset", {
  # root_key = 1 has (mocked) more descendants than gbif_max_lookup_offset allows to page directly --
  # it should split into its two children (10, 20) and fetch each one's own (small, directly pageable)
  # tree instead, combining the pieces into one result equivalent to what a direct fetch would have
  # returned had GBIF allowed it.
  cache_dir <- withr::local_tempdir()

  local_mocked_bindings(
    name_lookup = function(higherTaxonKey, datasetKey, limit, start, ...) {
      if (higherTaxonKey == 1) {
        # huge -- content doesn't matter, only `count` (this page's data is never used once the
        # children-split path is taken)
        return(gbif_lookup_page(gbif_taxon_row(integer(0), scientificName = character(0), rank = character(0)), count = 999999))
      }
      if (higherTaxonKey == 10) {
        data <- gbif_taxon_row(key = 101:105, scientificName = paste("Childaxa alpha", 1:5), rank = "SPECIES", genus = "Childaxa")
        return(gbif_lookup_page(data, count = nrow(data)))
      }
      if (higherTaxonKey == 20) {
        data <- gbif_taxon_row(key = 201:207, scientificName = paste("Childbeta beta", 1:7), rank = "SPECIES", genus = "Childbeta")
        return(gbif_lookup_page(data, count = nrow(data)))
      }
      stop("unexpected higherTaxonKey in mock: ", higherTaxonKey)
    },
    name_usage = function(key, data = NULL, ...) {
      if (!is.null(data) && identical(data, "children")) {
        if (key == 1) {
          return(list(
            meta = list(offset = 0, limit = 1000, endOfRecords = TRUE),
            data = tibble::tibble(key = c(10L, 20L), canonicalName = c("Childaxa", "Childbeta"), rank = c("SUBORDER", "SUBORDER"))
          ))
        }
        return(list(meta = list(offset = 0, limit = 1000, endOfRecords = TRUE), data = tibble::tibble()))
      }
      list(data = gbif_taxon_row(key, scientificName = paste0("Root", key), rank = "ORDER"))
    },
    .package = "rgbif"
  )

  tree <- fetch_gbif_taxon_tree(
    root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
    max_cache_age_days = 30, quiet = TRUE, max_taxa = 10^7, force_large_fetch = TRUE
  )

  # root (1) + child roots (10, 20) + 5 + 7 species = 15 rows total
  expect_equal(nrow(tree), 15)
  expect_setequal(tree$key, c(1L, 10L, 20L, 101:105, 201:207))
})

test_that("fetch_gbif_taxon_tree_by_children resumes from cache without refetching an already-completed child", {
  # a child whose tree is already cached (e.g. from an earlier, interrupted run) should be read straight
  # from disk, not refetched -- the mock errors if name_lookup is ever called for that child's key, so
  # this fails loudly if the caching/resume behaviour regresses
  cache_dir <- withr::local_tempdir()

  # pre-populate child 10's cache, exactly as fetch_gbif_taxon_tree() itself would have written it
  saveRDS(
    gbif_taxon_row(key = c(10L, 101L, 102L), scientificName = c("Childaxa", "Childaxa one", "Childaxa two"), rank = c("SUBORDER", "SPECIES", "SPECIES"), genus = c(NA, "Childaxa", "Childaxa")),
    file.path(cache_dir, "gbif_tree_10.rds")
  )

  local_mocked_bindings(
    name_lookup = function(higherTaxonKey, datasetKey, limit, start, ...) {
      if (higherTaxonKey == 1) {
        return(gbif_lookup_page(gbif_taxon_row(integer(0), scientificName = character(0), rank = character(0)), count = 999999))
      }
      if (higherTaxonKey == 20) {
        data <- gbif_taxon_row(key = 201:203, scientificName = paste("Childbeta beta", 1:3), rank = "SPECIES", genus = "Childbeta")
        return(gbif_lookup_page(data, count = nrow(data)))
      }
      stop("name_lookup should not have been called for an already-cached child (key ", higherTaxonKey, ")")
    },
    name_usage = function(key, data = NULL, ...) {
      if (!is.null(data) && identical(data, "children")) {
        if (key == 1) {
          return(list(
            meta = list(offset = 0, limit = 1000, endOfRecords = TRUE),
            data = tibble::tibble(key = c(10L, 20L), canonicalName = c("Childaxa", "Childbeta"), rank = c("SUBORDER", "SUBORDER"))
          ))
        }
        return(list(meta = list(offset = 0, limit = 1000, endOfRecords = TRUE), data = tibble::tibble()))
      }
      if (key == 10) stop("name_usage(key=10) should not have been called for an already-cached child")
      list(data = gbif_taxon_row(key, scientificName = paste0("Root", key), rank = "ORDER"))
    },
    .package = "rgbif"
  )

  tree <- fetch_gbif_taxon_tree(
    root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
    max_cache_age_days = 30, quiet = TRUE, max_taxa = 10^7, force_large_fetch = TRUE
  )

  # child 10's cached tree (3 rows) + root (1) + child 20's freshly-fetched tree (20 + 3 species = 4 rows)
  expect_setequal(tree$key, c(1L, 10L, 101L, 102L, 20L, 201:203))
})

test_that("fetch_gbif_taxon_tree errors clearly if splitting into children never gets small enough", {
  # a taxon whose children are (implausibly) reported as no smaller than itself should error clearly
  # after a bounded number of recursive splits, rather than recursing forever
  cache_dir <- withr::local_tempdir()

  local_mocked_bindings(
    name_lookup = function(higherTaxonKey, datasetKey, limit, start, ...) {
      gbif_lookup_page(gbif_taxon_row(integer(0), scientificName = character(0), rank = character(0)), count = 999999)
    },
    name_usage = function(key, data = NULL, ...) {
      if (!is.null(data) && identical(data, "children")) {
        # every taxon reports exactly one child, itself no smaller -- never terminates on its own
        return(list(
          meta = list(offset = 0, limit = 1000, endOfRecords = TRUE),
          data = tibble::tibble(key = key + 1L, canonicalName = "Stillhuge", rank = "SUBORDER")
        ))
      }
      list(data = gbif_taxon_row(key, scientificName = paste0("Root", key), rank = "ORDER"))
    },
    .package = "rgbif"
  )

  expect_error(
    fetch_gbif_taxon_tree(
      root_key = 1, cache_dir = cache_dir, refresh_cache = FALSE,
      max_cache_age_days = 30, quiet = TRUE, max_taxa = 10^7, force_large_fetch = TRUE
    ),
    "levels deep"
  )
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

# ---- generate_GBIF_taxonomic_reference_list (end to end, GBIF calls mocked) ----

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

test_that("generate_GBIF_taxonomic_reference_list returns the documented columns", {
  local_mock_gbif_end_to_end()
  out <- generate_GBIF_taxonomic_reference_list("Boronia", cache_dir = withr::local_tempdir(), quiet = TRUE)

  expect_s3_class(out, "tbl_df")
  expect_setequal(
    names(out),
    c("taxon_ID", "parent_key", "accepted_name_usage_ID", "scientific_name",
      "scientific_name_authorship", "canonical_name", "taxon_rank", "taxonomic_status",
      "kingdom", "phylum", "class", "order", "family", "genus", "taxonomic_dataset")
  )
  expect_equal(unique(out$taxonomic_dataset), "GBIF")
  expect_setequal(out$taxon_ID, c(1L, 2L, 3L))
})

test_that("accepted_name_usage_ID is filled in for accepted names (self-referential, as in APC downloads)", {
  local_mock_gbif_end_to_end()
  out <- generate_GBIF_taxonomic_reference_list("Boronia", cache_dir = withr::local_tempdir(), quiet = TRUE)

  accepted <- out[out$taxonomic_status == "accepted", ]
  expect_false(anyNA(accepted$accepted_name_usage_ID))
  expect_equal(accepted$accepted_name_usage_ID, accepted$taxon_ID)

  # key 3 is a synonym of key 2 -- its accepted_name_usage_ID should point there, not to itself
  synonym <- out[out$taxon_ID == 3, ]
  expect_equal(synonym$accepted_name_usage_ID, 2L)
})

test_that("include_synonyms = FALSE drops synonym rows", {
  local_mock_gbif_end_to_end()
  out <- generate_GBIF_taxonomic_reference_list(
    "Boronia", include_synonyms = FALSE, cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_false("synonym" %in% out$taxonomic_status)
  expect_setequal(out$taxon_ID, c(1L, 2L))
})

test_that("rank filters to that rank and narrower", {
  local_mock_gbif_end_to_end()
  out <- generate_GBIF_taxonomic_reference_list(
    "Boronia", rank = "species", cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_true(all(out$taxon_rank %in% c("species", "variety")))
  expect_false("genus" %in% out$taxon_rank)
})

test_that("country restricts to taxa with an occurrence record there (including via accepted_name_usage_ID)", {
  local_mock_gbif_end_to_end()
  out <- generate_GBIF_taxonomic_reference_list(
    "Boronia", country = "au", cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  # key 2 has the occurrence; key 3 (its synonym) is kept via accepted_name_usage_ID
  expect_setequal(out$taxon_ID, c(2L, 3L))
})

test_that("multiple taxon_name values are resolved and merged with no duplicate keys", {
  local_mock_gbif_end_to_end()
  out <- generate_GBIF_taxonomic_reference_list(
    c("Boronia", "Zieria"), cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_setequal(out$taxon_ID, c(1L, 2L, 3L, 10L, 20L))
  expect_equal(anyDuplicated(out$taxon_ID), 0)
})

test_that("output is deduplicated even if the same taxon is requested twice", {
  local_mock_gbif_end_to_end()
  out <- generate_GBIF_taxonomic_reference_list(
    c("Boronia", "Boronia"), cache_dir = withr::local_tempdir(), quiet = TRUE
  )
  expect_equal(anyDuplicated(out$taxon_ID), 0)
})

test_that("a clade with no synonyms at all doesn't error when acceptedKey is entirely absent", {
  # regression test: rgbif's name_lookup()/name_usage() responses omit a column entirely (rather
  # than including it as all-NA) whenever every row in the fetched batch lacks a value for it -- a
  # real, jsonlite-flattening artifact hit on a real, small, no-synonym GBIF genus ("Aporocera").
  # Simulated here by building the mocked page *without* an acceptedKey column at all, rather than
  # via gbif_taxon_row()'s usual all-NA default -- this used to error ("Column `acceptedKey` not
  # found") rather than treating every row as already-accepted.
  local_mocked_bindings(
    name_backbone = function(...) gbif_backbone_match(1, "Aporocera Sm.", rank = "GENUS"),
    name_lookup = function(...) {
      page <- gbif_taxon_row(2, parentKey = 1, scientificName = "Aporocera viridis Sm.",
                              canonicalName = "Aporocera viridis", rank = "SPECIES", genus = "Aporocera")
      gbif_lookup_page(page[, setdiff(names(page), "acceptedKey")])
    },
    name_usage = function(...) {
      list(data = gbif_taxon_row(1, scientificName = "Aporocera Sm.", rank = "GENUS", genus = NA_character_))
    },
    .package = "rgbif"
  )

  out <- generate_GBIF_taxonomic_reference_list("Aporocera", cache_dir = withr::local_tempdir(), quiet = TRUE)

  expect_setequal(out$taxon_ID, c(1L, 2L))
  expect_false(anyNA(out$accepted_name_usage_ID))
  expect_equal(out$accepted_name_usage_ID, out$taxon_ID) # every row self-referential (all accepted)
})
