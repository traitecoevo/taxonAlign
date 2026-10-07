# Versioned data releases (issue #24): version resolution, local caching, and loading NSL / GBIF
# reference data from release parquet files -- entirely offline (GitHub and downloads mocked).

test_that("data_release_versions keeps published, date-tagged releases, most recent first", {
  local_mocked_bindings(
    curl_fetch_memory = function(...) list(status_code = 200, content = charToRaw(jsonlite::toJSON(data.frame(
      tag_name = c("2026-01-10", "v0.1.0", "2026-10-08", "2026-12-01"),
      draft = c(FALSE, FALSE, FALSE, TRUE)
    )))),
    .package = "curl"
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
    get_data_release_assets = function(assets, ...) stats::setNames(file.path(release, assets), assets)
  )
  out <- load_NSL_resources("animals", cache_dir = withr::local_tempdir(), quiet = TRUE)

  # the same result as loading the same export from its original pipe-delimited files
  from_files <- load_NSL_resources("animals", path = write_sample_nsl_animals_dir(),
                                   cache_dir = withr::local_tempdir(), quiet = TRUE)
  expect_equal(out, from_files)
})

test_that("load_GBIF_AU_resources reads the release file, extant taxa only unless asked", {
  f <- withr::local_tempfile(fileext = ".parquet")
  gbif <- tibble::tibble(taxon_ID = 1:3, accepted_name_usage_ID = 1:3,
                         canonical_name = c("Aus", "Aus bus", "Thylacinus cynocephalus"),
                         taxon_rank = c("genus", "species", "species"), taxonomic_status = "accepted",
                         extinct = c(NA, FALSE, TRUE), taxonomic_dataset = "GBIF")
  arrow::write_parquet(gbif, f)
  expect_equal(load_GBIF_AU_resources(path = f, quiet = TRUE), gbif[1:2, ])
  expect_equal(load_GBIF_AU_resources(path = f, include_extinct = TRUE, quiet = TRUE), gbif)
  expect_error(load_GBIF_AU_resources(path = "/no/such/file.parquet"), "Couldn't find")
})

test_that("data_release_versions returns nothing, rather than erroring or hanging, when GitHub can't be reached", {
  local_mocked_bindings(curl_fetch_memory = function(...) stop("Could not resolve host"), .package = "curl")
  withr::defer(rm(list = ls(.taxonAlign_release_cache), envir = .taxonAlign_release_cache))
  expect_equal(data_release_versions(refresh = TRUE), character(0))
})

test_that("a named release that's already downloaded is used without touching the network", {
  cache <- withr::local_tempdir()
  dir.create(file.path(cache, "data_release", "2026-10-08"), recursive = TRUE)
  writeLines("x", file.path(cache, "data_release", "2026-10-08", "gbif_au_animals.parquet"))
  local_mocked_bindings(data_release_versions = function(...) stop("network used"))
  local_mocked_bindings(curl_fetch_memory = function(...) stop("network used"), .package = "curl")
  expect_equal(
    unname(get_data_release_assets("gbif_au_animals.parquet", "2026-10-08", cache)),
    file.path(cache, "data_release", "2026-10-08", "gbif_au_animals.parquet")
  )
})

test_that("if the latest release can't be downloaded, the newest complete local copy is used", {
  cache <- withr::local_tempdir()
  for (v in c("2026-01-10", "2026-03-01")) {
    dir.create(file.path(cache, "data_release", v), recursive = TRUE)
  }
  # only the older local release has the file
  writeLines("x", file.path(cache, "data_release", "2026-01-10", "gbif_au_animals.parquet"))
  local_mocked_bindings(
    resolve_data_release_version = function(version, ...) if (is.null(version)) "2026-10-08" else version,
    download_data_release_asset = function(...) stop("download failed")
  )
  expect_message(p <- get_data_release_assets("gbif_au_animals.parquet", NULL, cache), "most recent locally cached")
  expect_equal(unname(p), file.path(cache, "data_release", "2026-01-10", "gbif_au_animals.parquet"))
  # an explicitly requested release is never swapped for another
  expect_error(get_data_release_assets("gbif_au_animals.parquet", "2026-10-08", cache), "download failed")
})
