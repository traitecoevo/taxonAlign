# Versioned data releases (issue #24): version resolution, local caching, and loading NSL / GBIF
# reference data from release parquet files -- entirely offline (GitHub and downloads mocked).

test_that("data_release_versions keeps published, date-tagged releases, most recent first", {
  local_mocked_bindings(
    fromJSON = function(...) data.frame(
      tag_name = c("2026-01-10", "v0.1.0", "2026-10-08", "2026-12-01"),
      draft = c(FALSE, FALSE, FALSE, TRUE)
    ),
    .package = "jsonlite"
  )
  withr::defer(rm(list = ls(.taxonAlign_release_cache), envir = .taxonAlign_release_cache))
  expect_equal(data_release_versions(refresh = TRUE), c("2026-10-08", "2026-01-10"))
})

test_that("resolve_data_release_version: explicit > latest online > newest cached > clear error", {
  cache <- withr::local_tempdir()
  expect_equal(resolve_data_release_version("2026-01-10", cache), "2026-01-10")

  local_mocked_bindings(data_release_versions = function(...) c("2026-10-08", "2026-01-10"))
  expect_equal(resolve_data_release_version(NULL, cache), "2026-10-08")

  # offline: fall back to the newest release already downloaded
  local_mocked_bindings(data_release_versions = function(...) character(0))
  dir.create(file.path(cache, "data_release", "2026-01-10"), recursive = TRUE)
  dir.create(file.path(cache, "data_release", "2026-03-01"), recursive = TRUE)
  expect_message(v <- resolve_data_release_version(NULL, cache), "most recent locally cached")
  expect_equal(v, "2026-03-01")

  expect_error(resolve_data_release_version(NULL, withr::local_tempdir()), "no release is cached")
})

test_that("download_data_release_asset reuses an already-downloaded file", {
  cache <- withr::local_tempdir()
  dest <- file.path(cache, "data_release", "2026-10-08", "nsl_fungi_taxon.parquet")
  dir.create(dirname(dest), recursive = TRUE)
  writeLines("cached", dest)
  expect_equal(download_data_release_asset("nsl_fungi_taxon.parquet", "2026-10-08", cache), dest)
})

test_that("load_NSL_resources reads a group from data release parquet files", {
  release <- withr::local_tempdir()
  arrow::write_parquet(sample_nsl_animals_taxon_raw(), file.path(release, "nsl_animals_taxon.parquet"))
  arrow::write_parquet(sample_nsl_animals_names_raw(), file.path(release, "nsl_animals_names.parquet"))
  local_mocked_bindings(
    resolve_data_release_version = function(version, ...) "2026-10-08",
    download_data_release_asset = function(asset, ...) file.path(release, asset)
  )
  out <- load_NSL_resources("animals", cache_dir = withr::local_tempdir(), quiet = TRUE)

  # the same result as loading the same export from its original pipe-delimited files
  from_files <- load_NSL_resources("animals", path = write_sample_nsl_animals_dir(),
                                   cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_equal(out, from_files)
})

test_that("load_GBIF_AU_resources reads the release file", {
  f <- withr::local_tempfile(fileext = ".parquet")
  gbif <- tibble::tibble(taxon_ID = 1:2, accepted_name_usage_ID = 1:2, canonical_name = c("Aus", "Aus bus"),
                         taxon_rank = c("genus", "species"), taxonomic_status = "accepted", taxonomic_dataset = "GBIF")
  arrow::write_parquet(gbif, f)
  expect_equal(load_GBIF_AU_resources(path = f, quiet = TRUE), gbif)
  expect_error(load_GBIF_AU_resources(path = "/no/such/file.parquet"), "Couldn't find")
})
