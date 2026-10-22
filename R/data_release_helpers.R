# Versioned data releases (issue #24). Reference data -- the National Species List exports and the
# GBIF Australia list -- is published as files attached to dated GitHub Releases, so a result can be
# reproduced by naming the release it used. Releases are built and published by the companion
# taxonAlign.dataprep package (issue #26), on its own repo; taxonAlign only downloads them. The
# mechanism follows APCalign's own (`traitecoevo/APCalign`): release tags are bare dates
# ("2026-10-15"), assets are downloaded from the plain public release URL, cached locally, and the
# newest locally cached release is used when there's no internet connection.

taxonAlign_data_release_repo <- "traitecoevo/taxonAlign.dataprep"

# session cache for the release list, so the GitHub API isn't queried on every load
.taxonAlign_release_cache <- new.env(parent = emptyenv())

#' List the available taxonAlign data releases
#'
#' The reference data [load_taxonomic_resources()] loads is published as dated releases, so that an
#' alignment can be reproduced exactly by naming the release it used. This lists the releases
#' available online, most recent first; [data_release_datasets()] lists what's in one.
#'
#' @param refresh Logical; if `TRUE`, query GitHub again rather than reusing the list already
#'  fetched in this session. Defaults to `FALSE`.
#'
#' @return A character vector of release versions (dates, `"YYYY-MM-DD"`), most recent first; empty
#'  if GitHub can't be reached.
#'
#' @export
data_release_versions <- function(refresh = FALSE) {
  if (!refresh && !is.null(.taxonAlign_release_cache$versions)) {
    return(.taxonAlign_release_cache$versions)
  }
  url <- paste0("https://api.github.com/repos/", taxonAlign_data_release_repo, "/releases?per_page=100")
  # a short time limit, so a slow or flaky connection falls back to the local copy straight away
  # rather than hanging (APCalign users hit exactly that when offline)
  releases <- tryCatch({
    response <- curl::curl_fetch_memory(url, handle = curl::new_handle(connecttimeout = 5, timeout = 10))
    if (response$status_code != 200) stop("GitHub returned status ", response$status_code)
    jsonlite::fromJSON(rawToChar(response$content))
  }, error = function(e) NULL)
  if (is.null(releases) || length(releases) == 0 || !"tag_name" %in% names(releases)) {
    return(character(0))
  }
  tags <- releases$tag_name[!releases$draft]
  versions <- sort(tags[grepl("^\\d{4}-\\d{2}-\\d{2}$", tags)], decreasing = TRUE)
  .taxonAlign_release_cache$versions <- versions
  versions
}

# Releases already downloaded into `cache_dir`, most recent first.
#' @noRd
local_data_release_versions <- function(cache_dir) {
  dirs <- list.dirs(file.path(cache_dir, "data_release"), full.names = FALSE, recursive = FALSE)
  sort(dirs[grepl("^\\d{4}-\\d{2}-\\d{2}$", dirs)], decreasing = TRUE)
}

# The release to use: `version` if given (never touches the network), otherwise the latest online,
# otherwise (offline, slow connection, GitHub unavailable) the newest one already cached locally.
#' @noRd
resolve_data_release_version <- function(version, cache_dir, quiet = FALSE) {
  if (!is.null(version)) return(version)
  online <- data_release_versions()
  if (length(online) > 0) return(online[1])
  local <- local_data_release_versions(cache_dir)
  if (length(local) > 0) {
    if (!quiet) message("Couldn't reach GitHub; using the most recent locally cached data release, ", local[1], ".")
    return(local[1])
  }
  stop(
    "Couldn't reach GitHub to find the latest taxonAlign data release, and no release is cached ",
    "locally. Connect to the internet, or pass `path` to load your own copy of the release files.",
    call. = FALSE
  )
}

# Local path to one release asset, downloading it into the cache first if it isn't already there.
#' @noRd
download_data_release_asset <- function(asset, version, cache_dir, refresh_cache = FALSE, quiet = FALSE) {
  dest_dir <- file.path(cache_dir, "data_release", version)
  dest <- file.path(dest_dir, asset)
  if (!refresh_cache && file.exists(dest)) return(dest)

  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  url <- paste0("https://github.com/", taxonAlign_data_release_repo, "/releases/download/", version, "/", asset)
  if (!quiet) message("Downloading ", asset, " (data release ", version, ")...")
  # into a temporary file first, so a failed download (e.g. `refresh_cache = TRUE` while offline)
  # never removes or truncates a copy that's already cached
  partial <- paste0(dest, ".part")
  ok <- tryCatch(
    utils::download.file(url, partial, mode = "wb", quiet = TRUE) == 0,
    error = function(e) FALSE, warning = function(w) FALSE
  )
  if (ok) ok <- file.rename(partial, dest)
  if (!ok) {
    unlink(partial)
    stop(
      "Couldn't download ", asset, " from taxonAlign data release ", version, " (", url, "). ",
      "Check the version exists (see `data_release_versions()`) and that you're online.",
      call. = FALSE
    )
  }
  dest
}

# Local paths to a set of release assets for `version` (or the latest), downloading any not already
# cached. If the latest release can't be downloaded (e.g. the connection drops), falls back to the
# newest release already cached locally that has every asset, rather than failing. An explicitly
# requested `version` is never swapped for another.
#' @noRd
get_data_release_assets <- function(assets, version, cache_dir, refresh_cache = FALSE, quiet = FALSE) {
  requested <- version
  version <- resolve_data_release_version(version, cache_dir, quiet = quiet)
  paths <- tryCatch(
    vapply(assets, download_data_release_asset, character(1), version = version,
           cache_dir = cache_dir, refresh_cache = refresh_cache, quiet = quiet),
    error = function(e) {
      if (!is.null(requested)) stop(e)
      have_all <- Filter(function(v) all(file.exists(file.path(cache_dir, "data_release", v, assets))),
                         local_data_release_versions(cache_dir))
      if (length(have_all) == 0) stop(e)
      if (!quiet) message("Couldn't download data release ", version, "; using the most recent locally cached release, ", have_all[1], ".")
      file.path(cache_dir, "data_release", have_all[1], assets)
    }
  )
  stats::setNames(unname(paths), assets)
}

#' Download files from a taxonAlign data release
#'
#' Downloads (or finds already cached) any files from a data release -- the ready datasets
#' [load_taxonomic_resources()] reads, or the verbatim source exports stored alongside them (e.g.
#' `"nsl_fungi_taxon.parquet"`), which `taxonAlign.dataprep` rebuilds references from. Most users
#' never need this directly. [data_release_versions()] lists the releases; each release's
#' `manifest.csv` lists its files.
#'
#' @param files Character vector of file names in the release.
#' @inheritParams load_taxonomic_resources
#'
#' @return A named character vector of local file paths, one per file. Downloaded files are cached
#'  under `<cache_dir>/data_release/<version>/`; if the latest release can't be downloaded, the newest
#'  release already cached that has every file is used instead (never when `version` is given).
#'
#' @export
download_data_release_files <- function(files,
                                        version = NULL,
                                        refresh_cache = FALSE,
                                        cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                        quiet = FALSE) {
  get_data_release_assets(files, version, cache_dir, refresh_cache, quiet)
}
