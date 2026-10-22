# Loading released reference data (issues #24, #26). Each data release holds, for every dataset, one
# ready-to-use parquet file already in taxonAlign's reference format (`<dataset>.parquet`), plus the
# verbatim source files it was built from and a `manifest.csv` describing every file. taxonAlign only
# ever reads the ready files -- reshaping a source into the format is taxonAlign.dataprep's job -- and
# learns which datasets a release has from its manifest, so a new dataset needs a new data release,
# not a new version of taxonAlign.

#' Load released taxonomic reference data
#'
#' Downloads one or more taxonomic reference datasets from a dated taxonAlign data release, ready to
#' pass to [create_taxonomic_update_lookup()], [align_taxa()] or [prepare_taxonomic_resources()].
#' Naming the release (`version`) makes an alignment reproducible. Downloaded files are cached, so each
#' is only downloaded once.
#'
#' The datasets in the first release are the Australian National Species List exports --
#' `"NSL_animals"` (the Australian Faunal Directory), `"NSL_algae"`, `"NSL_bryophytes"`, `"NSL_fungi"`
#' and `"NSL_lichens"` -- and `"GBIF_AU"`, every animal taxon in the GBIF backbone with occurrence
#' records in Australia, plus its synonyms. [data_release_datasets()] lists what a release holds, with
#' each dataset's source, retrieval date, licence and citation.
#'
#' When several datasets are loaded, they're returned in the order given, which is the order they're
#' preferred in when a name appears in more than one.
#'
#' Some datasets flag extinct taxa (an `extinct` column; currently `"GBIF_AU"`). GBIF's occurrence
#' records include fossil specimens, so these are left out by default, as they only produce spurious
#' matches against modern names. GBIF's flag doesn't distinguish fossils from recent extinctions,
#' though -- the thylacine (*Thylacinus cynocephalus*) is flagged extinct too -- so
#' `include_extinct = TRUE` keeps everything, with the `extinct` column showing which are which.
#'
#' The releases are built by the `taxonAlign.dataprep` package, which also has the functions for
#' building a reference from other sources (a live GBIF fetch, taxadb, the AFD's own export, APC).
#'
#' @param datasets Character vector of datasets to load, e.g. `c("NSL_animals", "GBIF_AU")`.
#' @param version Data release to load, a date (`"YYYY-MM-DD"`); see [data_release_versions()].
#'  Defaults to the latest release, or, with no internet connection, the newest release already
#'  downloaded.
#' @param include_extinct Logical; if `TRUE`, also keep taxa flagged as extinct, and their synonyms.
#'  Defaults to `FALSE`.
#' @param path Optional directory holding your own copy of a release's files (`manifest.csv` and
#'  the `<dataset>.parquet` files). `version` is then ignored.
#' @param refresh_cache Logical; if `TRUE`, re-downloads the files even if they're cached. Defaults to
#'  `FALSE`.
#' @param cache_dir Directory downloaded release files are cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A named list of tibbles, one per dataset, each in taxonAlign's reference format (see
#'  [taxonomic_reference_schema()]). The release it came from is recorded in each tibble's
#'  `"data_release"` attribute.
#'
#' @examples
#' \dontrun{
#' animals <- load_taxonomic_resources(c("NSL_animals", "GBIF_AU"), version = "2026-10-07")
#' create_taxonomic_update_lookup(c("Pardalotus striatus", "Cynthia cardui"), animals)
#' }
#'
#' @export
load_taxonomic_resources <- function(datasets,
                                     version = NULL,
                                     include_extinct = FALSE,
                                     path = NULL,
                                     refresh_cache = FALSE,
                                     cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                     quiet = FALSE) {
  if (missing(datasets) || !is.character(datasets) || length(datasets) == 0) {
    stop("`datasets` must name at least one dataset; see `data_release_datasets()`.", call. = FALSE)
  }

  manifest <- data_release_datasets(version, path, refresh_cache, cache_dir, quiet)
  release <- attr(manifest, "data_release")
  unknown <- setdiff(datasets, manifest$dataset)
  if (length(unknown) > 0) {
    stop(
      "Data release ", release, " has no dataset(s) called ", paste0("\"", unknown, "\"", collapse = ", "),
      ". It has: ", paste(manifest$dataset, collapse = ", "), ".", call. = FALSE
    )
  }

  assets <- manifest$asset[match(datasets, manifest$dataset)]
  files <- if (is.null(path)) {
    # the version the manifest came from, so every file is from the same release
    get_data_release_assets(assets, release, cache_dir, refresh_cache, quiet)
  } else {
    file.path(path, assets)
  }

  result <- lapply(files, function(file) {
    reference <- dplyr::as_tibble(arrow::read_parquet(file))
    if (!include_extinct && "extinct" %in% names(reference)) {
      reference <- reference[!(reference$extinct %in% TRUE), ]
    }
    attr(reference, "data_release") <- release
    reference
  })
  stats::setNames(result, datasets)
}

#' List the datasets in a taxonAlign data release
#'
#' Reads a data release's manifest: the datasets [load_taxonomic_resources()] can load from it, and
#' where each came from. Cite the sources of the datasets you use.
#'
#' @inheritParams load_taxonomic_resources
#'
#' @return A tibble with one row per dataset: `dataset`, `asset` (the release file), `rows`, `source`,
#'  `retrieved`, `licence` and `citation`. The release is recorded in its `"data_release"` attribute.
#'
#' @export
data_release_datasets <- function(version = NULL,
                                  path = NULL,
                                  refresh_cache = FALSE,
                                  cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                  quiet = FALSE) {
  if (is.null(path)) {
    file <- get_data_release_assets("manifest.csv", version, cache_dir, refresh_cache, quiet)[[1]]
    release <- basename(dirname(file))
  } else {
    file <- file.path(path, "manifest.csv")
    if (!file.exists(file)) stop("Couldn't find a data release manifest at \"", file, "\".", call. = FALSE)
    release <- path
  }
  manifest <- readr::read_csv(file, col_types = readr::cols(.default = readr::col_character()), progress = FALSE)
  if (!all(c("dataset", "asset", "type") %in% names(manifest))) {
    stop(
      "The manifest of data release ", release, " doesn't list datasets -- it may be from before ",
      "releases were built by taxonAlign.dataprep. Use a later release.", call. = FALSE
    )
  }
  ready <- manifest[manifest$type %in% "ready", ]
  out <- dplyr::transmute(
    ready, dataset, asset, rows = as.integer(rows), source, retrieved, licence, citation
  )
  attr(out, "data_release") <- release
  out
}
