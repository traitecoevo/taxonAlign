#' Load the GBIF Australia (extant animals) reference list
#'
#' Downloads the GBIF Australia reference list from a taxonAlign data release: every animal taxon in
#' the GBIF backbone with occurrence records in Australia, plus its synonyms, with taxa GBIF flags as
#' extinct (and their synonyms) removed. It's the same shape as
#' [generate_GBIF_taxonomic_reference_list()]'s output -- built with it, with `country = "AU"` -- so
#' it can be passed straight to [prepare_taxonomic_resources()], alone or with other references.
#'
#' Building this list live from GBIF takes many hours (millions of backbone records), so a fixed,
#' dated copy is released instead; naming the release makes an alignment reproducible. See the
#' release notes for when the GBIF data were retrieved.
#'
#' @param version Data release to download, a date (`"YYYY-MM-DD"`); see [data_release_versions()].
#'  Defaults to the latest release, or, with no internet connection, the newest release already
#'  downloaded. Ignored when `path` is given.
#' @param path Optional path to your own copy of the release file (`gbif_au_extant.parquet`).
#' @param refresh_cache Logical; if `TRUE`, re-downloads the release file even if it's cached.
#'  Defaults to `FALSE`.
#' @param cache_dir Directory downloaded release files are cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A flat tibble with the columns [generate_GBIF_taxonomic_reference_list()] returns
#'  (`taxon_ID`, `accepted_name_usage_ID`, `canonical_name`, `taxon_rank`, `taxonomic_status`,
#'  `taxonomic_dataset` = `"GBIF"`, ...).
#'
#' @export
load_GBIF_AU_resources <- function(version = NULL,
                                   path = NULL,
                                   refresh_cache = FALSE,
                                   cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                   quiet = FALSE) {
  if (is.null(path)) {
    version <- resolve_data_release_version(version, cache_dir, quiet = quiet)
    path <- download_data_release_asset("gbif_au_extant.parquet", version, cache_dir, refresh_cache, quiet)
  } else if (!file.exists(path)) {
    stop("Couldn't find the GBIF Australia file at \"", path, "\".", call. = FALSE)
  }
  dplyr::as_tibble(arrow::read_parquet(path))
}
