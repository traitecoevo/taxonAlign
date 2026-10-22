# Versioned data releases (issues #24, #26): version resolution, local caching, and loading the ready
# reference files from a release -- entirely offline (GitHub and downloads mocked).

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

# A release directory in the shape taxonalign.dataprep builds: a manifest plus one ready file per
# dataset (verbatim source files listed as "raw", which taxonAlign never reads).
write_sample_release <- function(dir = withr::local_tempdir(.local_envir = parent.frame())) {
  animals <- tibble::tibble(
    canonical_name = c("Pardalotus", "Pardalotus striatus", "Pardalotus ornatus"),
    scientific_name = c("Pardalotus Vieillot, 1816", "Pardalotus striatus (Gmelin, 1789)", "Pardalotus ornatus Temminck, 1826"),
    taxon_rank = c("genus", "species", "species"), taxonomic_status = c("accepted", "accepted", "synonym"),
    taxonomic_dataset = "AFD", genus = "Pardalotus", taxon_ID = c("g1", "s1", "s2"),
    accepted_name_usage_ID = c("g1", "s1", "s1")
  )
  gbif <- tibble::tibble(
    canonical_name = c("Vanessa", "Vanessa cardui", "Thylacinus cynocephalus"),
    scientific_name = canonical_name, taxon_rank = c("genus", "species", "species"),
    taxonomic_status = "accepted", taxonomic_dataset = "GBIF", genus = c("Vanessa", "Vanessa", "Thylacinus"),
    taxon_ID = c("1", "2", "3"), accepted_name_usage_ID = c("1", "2", "3"), extinct = c(NA, FALSE, TRUE)
  )
  arrow::write_parquet(animals, file.path(dir, "NSL_animals.parquet"))
  arrow::write_parquet(gbif, file.path(dir, "GBIF_AU.parquet"))
  readr::write_csv(tibble::tibble(
    dataset = c("NSL_animals", "GBIF_AU", NA), asset = c("NSL_animals.parquet", "GBIF_AU.parquet", "nsl_animals_taxon.parquet"),
    type = c("ready", "ready", "raw"), rows = c(3, 3, 10), columns = c(8, 9, 30), source = "test", retrieved = "2026-10-07",
    source_md5 = NA, licence = "CC BY", citation = "test"
  ), file.path(dir, "manifest.csv"))
  dir
}

test_that("data_release_datasets lists a release's ready datasets, not its verbatim source files", {
  datasets <- data_release_datasets(path = write_sample_release())
  expect_equal(datasets$dataset, c("NSL_animals", "GBIF_AU"))
  expect_equal(datasets$rows, c(3L, 3L))
})

test_that("load_taxonomic_resources returns the named datasets, in the order asked for, extant only unless asked", {
  release <- write_sample_release()
  out <- load_taxonomic_resources(c("GBIF_AU", "NSL_animals"), path = release)
  expect_named(out, c("GBIF_AU", "NSL_animals"))
  expect_equal(out$GBIF_AU$canonical_name, c("Vanessa", "Vanessa cardui"))
  expect_equal(attr(out$NSL_animals, "data_release"), release)

  all_taxa <- load_taxonomic_resources("GBIF_AU", path = release, include_extinct = TRUE)
  expect_true("Thylacinus cynocephalus" %in% all_taxa$GBIF_AU$canonical_name)

  expect_error(load_taxonomic_resources("NSL_plants", path = release), "no dataset.*NSL_plants.*It has: NSL_animals, GBIF_AU")
})

test_that("load_taxonomic_resources downloads every file from the release the manifest came from", {
  release <- write_sample_release()
  asked <- list()
  local_mocked_bindings(get_data_release_assets = function(assets, version, ...) {
    asked <<- c(asked, list(version))
    stats::setNames(file.path(release, assets), assets)
  })
  # (the manifest's folder name stands in for the release's version)
  out <- load_taxonomic_resources("NSL_animals")
  expect_null(asked[[1]])
  expect_equal(asked[[2]], basename(release))
  expect_equal(attr(out$NSL_animals, "data_release"), basename(release))
})

test_that("released datasets go straight into the matching functions, as a list", {
  animals <- load_taxonomic_resources(c("NSL_animals", "GBIF_AU"), path = write_sample_release())
  lookup <- create_taxonomic_update_lookup(c("Pardalotus ornatus", "Vanessa cardui"), animals)
  expect_equal(lookup$suggested_name, c("Pardalotus striatus", "Vanessa cardui"))
  expect_equal(lookup$taxonomic_dataset, c("AFD", "GBIF"))
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
