#' Load the GBIF Australia (extant animals) reference list
#'
#' Downloads the GBIF Australia reference list from a taxonAlign data release: every animal taxon in
#' the GBIF backbone with occurrence records in Australia, plus its synonyms. It's the same shape as
#' [generate_GBIF_taxonomic_reference_list()]'s output -- built with it, with `country = "AU"` -- so
#' it can be passed straight to [prepare_taxonomic_resources()], alone or with other references.
#'
#' GBIF's occurrence records include fossil specimens, so the full list includes fossil taxa, which
#' only produce spurious matches against modern names. By default, taxa GBIF flags as extinct (and
#' their synonyms) are therefore left out. GBIF's flag doesn't distinguish fossils from recent
#' extinctions, though -- the thylacine (*Thylacinus cynocephalus*) is flagged extinct too -- so
#' `include_extinct = TRUE` returns everything, with the `extinct` column showing which are which.
#'
#' Building this list live from GBIF takes many hours (millions of backbone records), so a fixed,
#' dated copy is released instead; naming the release makes an alignment reproducible. See the
#' release notes for when the GBIF data were retrieved.
#'
#' @param version Data release to download, a date (`"YYYY-MM-DD"`); see [data_release_versions()].
#'  Defaults to the latest release, or, with no internet connection, the newest release already
#'  downloaded. Ignored when `path` is given.
#' @param include_extinct Logical; if `TRUE`, also return taxa GBIF flags as extinct, and their
#'  synonyms. Defaults to `FALSE`.
#' @param path Optional path to your own copy of the release file (`gbif_au_animals.parquet`).
#' @param refresh_cache Logical; if `TRUE`, re-downloads the release file even if it's cached.
#'  Defaults to `FALSE`.
#' @param cache_dir Directory downloaded release files are cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A flat tibble with the columns [generate_GBIF_taxonomic_reference_list()] returns
#'  (`taxon_ID`, `accepted_name_usage_ID`, `canonical_name`, `taxon_rank`, `taxonomic_status`,
#'  `extinct`, `taxonomic_dataset` = `"GBIF"`, ...).
#'
#' @export
load_GBIF_AU_resources <- function(version = NULL,
                                   include_extinct = FALSE,
                                   path = NULL,
                                   refresh_cache = FALSE,
                                   cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                   quiet = FALSE) {
  if (is.null(path)) {
    path <- get_data_release_assets("gbif_au_animals.parquet", version, cache_dir, refresh_cache, quiet)[[1]]
  } else if (!file.exists(path)) {
    stop("Couldn't find the GBIF Australia file at \"", path, "\".", call. = FALSE)
  }
  gbif <- dplyr::as_tibble(arrow::read_parquet(path))
  if (!include_extinct && "extinct" %in% names(gbif)) {
    gbif <- gbif[!(gbif$extinct %in% TRUE), ]
  }
  gbif
}
