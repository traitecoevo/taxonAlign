# Covers load_Australian_NSL() end to end against a small NSL-shaped fixture pair
# (helper-nsl-fixtures.R), entirely offline -- no need for the real, much larger
# inst/extdata/Australian_*/ files.

test_that("load_Australian_NSL errors clearly on an unknown taxon_group", {
  expect_error(
    load_Australian_NSL("not_a_real_group"),
    "`taxon_group` must be exactly one of"
  )
})

test_that("load_Australian_NSL errors clearly when the folder is missing", {
  expect_error(
    load_Australian_NSL("fungi", path = "/no/such/directory"),
    "Couldn't find the NSL reference folder"
  )
})

test_that("load_Australian_NSL returns a flat tibble with the required columns", {
  dir <- write_sample_nsl_dir()
  out <- load_Australian_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  expect_true(all(c(
    "canonical_name", "scientific_name", "taxon_rank", "taxonomic_status", "taxonomic_dataset",
    "genus", "taxon_ID", "accepted_name_usage_ID"
  ) %in% names(out)))
})

test_that("load_Australian_NSL: taxa take priority over names -- every duplicated name is dropped from the names file", {
  dir <- write_sample_nsl_dir()
  out <- load_Australian_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  # 5 taxon-file rows + exactly 1 names-only row ("Testusgenus informalis"), not 5 + 6
  expect_equal(nrow(out), 6)
  expect_equal(sum(out$canonical_name == "Testidae"), 1)
  expect_equal(sum(out$canonical_name == "Testusgenus alphus"), 1)

  # the surviving row for a name present in both files is the taxon-file version (real
  # taxon_ID/accepted_name_usage_ID resolution), never the names-file's self-referential one
  fam <- out |> dplyr::filter(canonical_name == "Testidae")
  expect_equal(fam$taxon_ID, "t-fam1")
  expect_equal(fam$taxonomic_dataset, "TFX")

  # the names-only row widens coverage but resolves to itself, having no accepted-name link of its own
  extra <- out |> dplyr::filter(canonical_name == "Testusgenus informalis")
  expect_equal(nrow(extra), 1)
  expect_equal(extra$taxon_ID, "n-extra1")
  expect_equal(extra$accepted_name_usage_ID, "n-extra1")
  expect_equal(extra$taxonomic_dataset, "NFX")
})

test_that("load_Australian_NSL derives genus correctly by rank, and strips the subgenus marker", {
  dir <- write_sample_nsl_dir()
  out <- load_Australian_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)

  fam <- out |> dplyr::filter(canonical_name == "Testidae")
  gen <- out |> dplyr::filter(canonical_name == "Testusgenus", taxon_rank == "Genus")
  subgen <- out |> dplyr::filter(taxon_rank == "Subgenus")
  sp <- out |> dplyr::filter(canonical_name == "Testusgenus alphus")
  syn <- out |> dplyr::filter(canonical_name == "Oldgenus alphus")

  expect_true(is.na(fam$genus))
  expect_equal(gen$genus, "Testusgenus")
  # the "Genus subg. Subgenusname" marker is stripped down to the bare subgenus name, matching AFD's
  # own bare-subgenus-name convention -- required for prepare_taxonomic_resources()'s subgenus_v2 to
  # build a correct, non-doubled "Genus (Subgenus)" key
  expect_equal(subgen$canonical_name, "Testussub")
  expect_equal(subgen$genus, "Testusgenus")
  expect_equal(sp$genus, "Testusgenus")
  # a synonym's genus is re-derived from its own name, not copied from the accepted row it resolves to
  expect_equal(syn$genus, "Oldgenus")
})

test_that("load_Australian_NSL caches the reshaped result, keyed by both files' mtime/size", {
  dir <- write_sample_nsl_dir()
  cache_dir <- withr::local_tempdir()

  expect_message(
    load_Australian_NSL("fungi", path = dir, cache_dir = cache_dir),
    "Reading and reshaping"
  )
  expect_message(
    load_Australian_NSL("fungi", path = dir, cache_dir = cache_dir),
    "Using cached"
  )
  expect_message(
    load_Australian_NSL("fungi", path = dir, cache_dir = cache_dir, refresh_cache = TRUE),
    "Reading and reshaping"
  )
})

test_that("prepare_taxonomic_resources(load_Australian_NSL(...)) runs end to end into align_taxa(), including the marker-form subgenus", {
  dir <- write_sample_nsl_dir()
  nsl <- load_Australian_NSL("fungi", path = dir, cache_dir = withr::local_tempdir(), quiet = TRUE)
  resources <- prepare_taxonomic_resources(nsl)

  # subgenus_v2 was built correctly from the stripped canonical_name + genus pairing
  expect_true("Testusgenus (Testussub)" %in% resources$subgenus_v2$genus_and_subgenus)

  out <- create_taxonomic_update_lookup(
    c("Testusgenus alphus", "Oldgenus alphus", "Testusgenus subg. Testussub", "Testusgenus informalis"),
    resources
  )

  expect_equal(out$accepted_name[1:2], c("Testusgenus alphus", "Testusgenus alphus"))
  expect_equal(out$taxonomic_status_aligned[1:2], c("accepted", "taxonomic synonym"))
  # the marker-form subgenus query (match_02x, issue #25) resolves via the taxon-file-derived resource
  expect_equal(out$taxon_rank[3], "subgenus")
  # the names-file-only row is still findable (it only ever widens coverage), but its own status
  # ("unplaced") is never literally "accepted", so accepted_name stays NA by design (update_taxa() only
  # reports accepted_name when the resolved record's own status is "accepted") -- suggested_name is the
  # guaranteed fallback
  expect_true(is.na(out$accepted_name[4]))
  expect_equal(out$suggested_name[4], "Testusgenus informalis")
})
