# GBIF's "backbone" checklist -- the single deduplicated taxonomy that
# occurrence records are matched against. Restricting `name_lookup()` calls
# to this dataset avoids pulling duplicate names from the hundreds of other
# checklists GBIF indexes.
gbif_backbone_dataset_key <- "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"

# GBIF's species/name_lookup search endpoint refuses to serve pages past this offset -- confirmed via a
# direct call against the raw GBIF REST API (not just rgbif's wrapper): `"Max offset of 100000
# exceeded."`. This is a hard server-side limit (a common deep-pagination guard on search-style APIs),
# not something more retries or more parallel requests can work around -- a clade with more descendants
# than this (e.g. Arthropoda: ~3.1M, Mollusca: ~484k) has to be split into its immediate children and
# fetched recursively instead (see fetch_gbif_taxon_tree_by_children()), each piece small enough to page
# directly. A bulk full-backbone download exists as an alternative
# (https://hosted-datasets.gbif.org/datasets/backbone/current/backbone.zip) but was deliberately not
# used: it's a ~1GB, infrequently-updated (checked: last modified over a year ago) snapshot covering
# every kingdom, and using it for just the huge clades would leave the combined reference with silently
# inconsistent currency (some phyla live/current, others years stale) -- worse than being slower but
# uniformly live.
gbif_max_lookup_offset <- 100000

# Every rgbif call in this file passes this explicitly, rather than relying on rgbif's own default
# (`list(http_version = 2)`, no timeout at all) -- found necessary in practice on a long, many-thousand-
# request fetch (Arthropoda's recursive split): a request occasionally hangs indefinitely rather than
# erroring or timing out on its own (observed directly -- worker processes sitting at ~0% CPU for 30+
# minutes with no error, no data, and no further log output), which blocks the entire fetch forever
# with no chance for fetch_page_with_retry() to ever kick in, since a retry can only happen after a
# request actually fails. An explicit `timeout` (in seconds, via libcurl's CURLOPT_TIMEOUT) turns a hang
# into an ordinary, retry-able error instead.
#
# `timeout = 120`, not something shorter, based on a direct measurement, not a guess: GBIF's own deep-
# pagination genuinely gets slower as the requested offset grows within a single higherTaxonKey query
# (normal for an Elasticsearch-backed search API -- each page costs more to compute the further in it
# is), confirmed by fetching all 29 pages of one persistently-timing-out large clade (GBIF key 542,
# Sarcoptiformes, one at a time with no concurrency) and finding legitimate response times up to 78s at
# high offsets, vs. 5-8s at low ones. An initial `timeout = 60` was hitting exactly this: individually
# borderline-slow-but-real pages, pushed over the edge by `parallel_requests`' own concurrent load
# (multiple pages competing for bandwidth at once) -- a self-inflicted contention issue, not GBIF
# actually failing. 120s gives real margin above the measured worst case.
gbif_curlopts <- list(http_version = 2, timeout = 120)

# Retries `thunk()` (a zero-argument function, so each attempt genuinely re-executes the call rather
# than reusing R's cached promise value) up to `max_attempts` times with a short backoff -- shared by
# every rgbif call in this file other than the paginated tree-page path, which has its own variant
# (fetch_page_with_retry(), below) since it needs to hand a try-error back to its caller for cross-page
# aggregation rather than stopping immediately. Used for name resolution, root usage lookups, children
# pages and the occurrence facet -- any of which can hit the same transient network/TLS/timeout issue
# found in practice on a very large, long-running fetch (see gbif_curlopts's own comment).
with_gbif_retry <- function(thunk, max_attempts = 3) {
  for (attempt in seq_len(max_attempts)) {
    result <- try(thunk(), silent = TRUE)
    if (!inherits(result, "try-error")) return(result)
    if (attempt < max_attempts) Sys.sleep(2 * attempt)
  }
  stop(attr(result, "condition")$message, call. = FALSE)
}

# GBIF's `Rank` enum, ordered from broadest to narrowest. Used to answer
# "this rank and below" filtering without needing a live taxonomy lookup.
gbif_rank_order <- c(
  "domain", "kingdom", "subkingdom", "infrakingdom",
  "superphylum", "phylum", "subphylum", "infraphylum",
  "superclass", "class", "subclass", "infraclass", "parvclass",
  "superlegion", "legion", "sublegion", "infralegion",
  "supercohort", "cohort", "subcohort", "infracohort",
  "magnorder", "superorder", "grandorder", "order", "suborder", "infraorder", "parvorder",
  "superfamily", "family", "subfamily", "tribe", "subtribe",
  "genus", "subgenus", "section", "subsection", "series", "subseries",
  "species_aggregate", "species",
  "subspecies", "variety", "subvariety", "form", "subform",
  "cultivar_group", "cultivar", "strain", "other", "unranked"
)

#' Generate a taxonomic reference list from the GBIF backbone
#'
#' Builds a table of taxon names sourced from the
#' [GBIF backbone taxonomy](https://www.gbif.org/dataset/d7dddbf4-2cf0-4f39-9b2a-bb099caae36c),
#' optionally restricted to taxa recorded as occurring in a given country and/or to a
#' minimum taxonomic rank.
#'
#' The whole taxonomic tree below `taxon_name` is fetched once (in large, paginated
#' batches, rather than one API call per name) and cached to disk, so repeat calls --
#' including calls that filter by a different `country` or `rank` -- are served from
#' the cache and return almost instantly. Use `refresh_cache = TRUE` to force a fresh
#' download, e.g. once the cache is more than a few weeks old.
#'
#' @details
#' The full tree is always fetched (and cached) regardless of `country` -- `country`
#' only filters the already-fetched tree afterwards, it never narrows the download
#' itself. This is deliberate, not an easy optimisation left undone: GBIF's taxonomy
#' browsing endpoint (which the tree fetch uses) has no country concept at all --
#' only its *occurrence-record* endpoint does, and occurrence records are normally
#' tagged with a taxon's *accepted* usage, not its synonyms. Filtering to occurrence-
#' derived keys before fetching the tree would silently drop every synonym of a taxon
#' that occurs in `country` (a synonym itself essentially never has its own occurrence
#' records). Fetching the whole tree first, then filtering, is what preserves synonym
#' coverage. For a very large clade (e.g. an insect order), most of the wall-clock time
#' is this full-tree fetch; see `parallel_requests` to speed it up.
#'
#' A clade with more than 100,000 descendants (e.g. Arthropoda, Mollusca) can't be paged directly at
#' all -- GBIF's lookup endpoint refuses to serve pages past that offset. For a clade this large, the
#' tree is instead fetched by automatically splitting into its immediate children and fetching each one
#' recursively (splitting again if a child is itself still too large), then combining the pieces. Every
#' piece is cached under its own GBIF key exactly like a directly-fetched tree, so a very large fetch
#' interrupted partway through (a crash, a reboot, `Ctrl-C`) is resumable for free: re-running the same
#' call only re-fetches whichever pieces aren't already cached.
#'
#' @param taxon_name Character vector of one or more taxon names to build the
#'  reference list from (e.g. `"Rutaceae"`, `"Boronia"`, `"Lepidoptera"`). Every rank
#'  below each name is included; use `rank` to trim that back.
#' @param name_rank Optional character, the taxonomic rank of `taxon_name`
#'  (e.g. `"genus"`, `"family"`). Only needed to disambiguate homonyms that exist at
#'  more than one rank; passed to [rgbif::name_backbone()]. Recycled against
#'  `taxon_name` if both have length > 1.
#' @param name_kingdom Optional character, the kingdom of `taxon_name` (e.g.
#'  `"Plantae"`, `"Animalia"`). Only needed to disambiguate homonyms that exist in more
#'  than one kingdom (a common case -- e.g. the plant genus *Eremophila* and the bird
#'  genus *Eremophila* -- that `name_rank` alone cannot resolve). Recycled against
#'  `taxon_name` if both have length > 1.
#' @param country Optional ISO 3166-1 alpha-2 country code (e.g. `"AU"`). When
#'  supplied, the list is restricted to taxa with at least one GBIF occurrence record
#'  in that country.
#' @param rank Optional character, a rank from GBIF's rank enum (e.g. `"genus"`,
#'  `"species"`). When supplied, only taxa at this rank or below (i.e. more specific
#'  ranks, such as species and subspecies under `"genus"`) are returned.
#' @param include_synonyms Logical; if `FALSE`, only accepted names are returned.
#'  Defaults to `TRUE`.
#' @param cache_dir Directory used to cache downloaded taxonomy/occurrence data.
#'  Defaults to a per-user cache directory (see [tools::R_user_dir()]) so the cache
#'  persists across sessions.
#' @param refresh_cache Logical; if `TRUE`, ignore any cached data and re-download
#'  from GBIF. Defaults to `FALSE`.
#' @param max_cache_age_days Numeric; cached data older than this many days is
#'  treated as stale and re-downloaded. Defaults to 30.
#' @param facet_limit Numeric; the maximum number of distinct taxa to request when
#'  looking up which taxa occur in `country`. Increase this if a `warning` reports the
#'  result may be truncated. Defaults to 100000.
#' @param max_taxa Numeric; refuse to download a taxonomic tree with more than this
#'  many taxa unless `force_large_fetch = TRUE`. This is mainly a safety net for
#'  ambiguous names -- GBIF resolves some homonyms to their common ancestor (e.g. a
#'  whole kingdom) rather than erroring -- but also protects against accidentally
#'  requesting a very slow, very large first-time download. Defaults to 50000.
#' @param force_large_fetch Logical; set to `TRUE` to proceed with a fetch that would
#'  otherwise be blocked by `max_taxa`. Defaults to `FALSE`.
#' @param parallel_requests Numeric; how many of the paginated GBIF requests used to
#'  fetch a large taxonomic tree to run concurrently. The tree is always fetched in full
#'  regardless of `country` (see Details) -- for a large clade this can mean thousands of
#'  1000-row pages, previously fetched one at a time. Set to `1` to fetch strictly
#'  sequentially (the old behaviour). Only takes effect on Unix-alikes (macOS/Linux) --
#'  [parallel::mclapply()] silently falls back to sequential on Windows, where this has
#'  no effect. Defaults to 4; raise or lower depending on how many concurrent requests
#'  you're comfortable sending GBIF.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A tibble with one row per taxon, with column names matching those used by
#'  [APCalign](https://traitecoevo.github.io/APCalign/) (`traitecoevo/APCalign`) wherever an
#'  equivalent concept exists there, so this reference list can be combined with an
#'  APC/APNI-derived one: `taxon_ID` (the GBIF backbone usageKey), `parent_key` (GBIF-specific;
#'  no APCalign equivalent), `accepted_name_usage_ID` (the `taxon_ID` of the accepted usage --
#'  equal to `taxon_ID` itself for a row that is already accepted, matching how APC downloads
#'  fill this in), `scientific_name` (the full name, with authorship), `scientific_name_authorship`,
#'  `canonical_name` (the name without authorship), `taxon_rank`, `taxonomic_status`, `kingdom`,
#'  `phylum`, `class`, `order`, `family`, `genus` and `taxonomic_dataset` (always `"GBIF"`).
#'
#' @examples
#' \dontrun{
#' # every taxon below the genus Boronia
#' generate_GBIF_taxonomic_reference_list("Boronia")
#'
#' # species (and infraspecific taxa) of Boronia recorded in Australia
#' generate_GBIF_taxonomic_reference_list("Boronia", country = "AU", rank = "species")
#'
#' # combine several families in one call
#' generate_GBIF_taxonomic_reference_list(c("Rutaceae", "Sapindaceae"), country = "AU")
#' }
#'
#' @importFrom rlang .data
#' @export
generate_GBIF_taxonomic_reference_list <- function(taxon_name,
                                               name_rank = NULL,
                                               name_kingdom = NULL,
                                               country = NULL,
                                               rank = NULL,
                                               include_synonyms = TRUE,
                                               cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                               refresh_cache = FALSE,
                                               max_cache_age_days = 30,
                                               facet_limit = 100000,
                                               max_taxa = 50000,
                                               force_large_fetch = FALSE,
                                               parallel_requests = 4,
                                               quiet = FALSE) {

  if (missing(taxon_name) || length(taxon_name) == 0 || anyNA(taxon_name)) {
    stop("`taxon_name` is required and cannot contain missing values.")
  }

  if (!is.null(rank)) {
    rank <- tolower(rank)
    if (!rank %in% gbif_rank_order) {
      stop("`rank` must be one of: ", paste(gbif_rank_order, collapse = ", "))
    }
  }

  if (!is.null(country) && !grepl("^[A-Za-z]{2}$", country)) {
    stop(
      "`country` must be a 2-letter ISO 3166-1 alpha-2 country code (e.g. \"AU\" for Australia), not ",
      "a country name -- got \"", country, "\". See ",
      "https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2 for the full list of codes."
    )
  }

  name_rank <- recycle_against_taxon_name(name_rank, taxon_name, "name_rank")
  name_kingdom <- recycle_against_taxon_name(name_kingdom, taxon_name, "name_kingdom")

  if (!dir.exists(cache_dir)) {
    dir.create(cache_dir, recursive = TRUE)
  }

  # resolve each name to its backbone key once, and reuse it for both the
  # taxonomic tree fetch and (if requested) the country-occurrence fetch
  roots <- purrr::pmap(
    list(
      taxon_name = taxon_name,
      name_rank = name_rank %||% vector("list", length(taxon_name)),
      name_kingdom = name_kingdom %||% vector("list", length(taxon_name))
    ),
    resolve_gbif_taxon
  )

  full_tree <- purrr::map(roots, function(root) {
    fetch_gbif_taxon_tree(
      root_key = root$key,
      cache_dir = cache_dir,
      refresh_cache = refresh_cache,
      max_cache_age_days = max_cache_age_days,
      quiet = quiet,
      max_taxa = max_taxa,
      force_large_fetch = force_large_fetch,
      parallel_requests = parallel_requests
    )
  }) |>
    purrr::list_rbind() |>
    dplyr::distinct(.data$key, .keep_all = TRUE)

  # rgbif's name_lookup()/name_usage() responses omit a column entirely (rather than including it
  # as all-NA) whenever every row in the fetched batch lacks a value for it -- a jsonlite-flattening
  # artifact of the underlying GBIF API response, not a signal the field is genuinely unavailable.
  # A small clade with no synonyms at all (every row's `acceptedKey` is NA) is a real, easy-to-hit
  # case of this -- without this, the `dplyr::coalesce(.data$acceptedKey, ...)` below (and the
  # country filter, if requested) would error with "Column `acceptedKey` not found" rather than
  # treating it as the all-NA column it actually is. Ensure every column referenced from here on
  # always exists first.
  expected_int_cols <- c("key", "parentKey", "acceptedKey")
  expected_chr_cols <- c(
    "scientificName", "authorship", "canonicalName", "rank", "taxonomicStatus", "kingdom", "phylum",
    "class", "order", "family", "genus"
  )
  full_tree[setdiff(expected_int_cols, names(full_tree))] <- NA_integer_
  full_tree[setdiff(expected_chr_cols, names(full_tree))] <- NA_character_

  if (!is.null(country)) {
    # scoping the occurrence lookup per requested taxon (rather than per
    # descendant) keeps this to one cheap facet query per `taxon_name`
    occ_keys <- fetch_gbif_country_keys(
      roots = roots,
      country = country,
      cache_dir = cache_dir,
      refresh_cache = refresh_cache,
      max_cache_age_days = max_cache_age_days,
      facet_limit = facet_limit,
      quiet = quiet
    )
    full_tree <- dplyr::filter(
      full_tree,
      .data$key %in% occ_keys | .data$acceptedKey %in% occ_keys
    )
  }

  if (!include_synonyms) {
    full_tree <- dplyr::filter(full_tree, tolower(.data$taxonomicStatus) == "accepted")
  }

  if (!is.null(rank)) {
    keep_ranks <- gbif_rank_order[which(gbif_rank_order == rank):length(gbif_rank_order)]
    full_tree <- dplyr::filter(full_tree, tolower(.data$rank) %in% keep_ranks)
  }

  full_tree |>
    dplyr::transmute(
      taxon_ID = .data$key,
      parent_key = .data$parentKey,
      # GBIF only populates `acceptedKey` for synonyms; an already-accepted row
      # points to itself here, matching how `accepted_name_usage_ID` is filled
      # in for accepted names in APC downloads (never `NA`).
      accepted_name_usage_ID = dplyr::coalesce(.data$acceptedKey, .data$key),
      scientific_name = .data$scientificName,
      scientific_name_authorship = .data$authorship,
      canonical_name = .data$canonicalName,
      taxon_rank = tolower(.data$rank),
      taxonomic_status = tolower(.data$taxonomicStatus),
      kingdom = .data$kingdom,
      phylum = .data$phylum,
      class = .data$class,
      order = .data$order,
      family = .data$family,
      genus = .data$genus,
      taxonomic_dataset = "GBIF"
    ) |>
    dplyr::distinct(.data$taxon_ID, .keep_all = TRUE) |>
    dplyr::arrange(.data$taxon_rank, .data$canonical_name)
}

# resolve a taxon name (of any rank) to its GBIF backbone usageKey, following
# synonym links so we always walk the tree from the accepted usage
resolve_gbif_taxon <- function(taxon_name, name_rank, name_kingdom) {
  match <- with_gbif_retry(function() {
    rgbif::name_backbone(
      name = taxon_name, rank = name_rank, kingdom = name_kingdom, verbose = FALSE, curlopts = gbif_curlopts
    )
  })

  if (is.null(match) || nrow(match) == 0 || isTRUE(match$matchType == "NONE")) {
    # a homonym across kingdoms (e.g. the plant and bird genera both named
    # *Eremophila*) often lands here rather than as a HIGHERRANK match below;
    # GBIF explains why in `note` when that's the case
    note <- if ("note" %in% names(match) && length(match$note) == 1 && !is.na(match$note)) {
      paste0(" (", match$note, ")")
    } else {
      ""
    }
    stop(
      "Could not match `taxon_name` = \"", taxon_name, "\" to a GBIF backbone taxon", note, ". ",
      "If this name is a homonym, try passing `name_rank` and/or `name_kingdom` to disambiguate."
    )
  }

  # GBIF backs off to a broader rank ("HIGHERRANK") when `taxon_name` is a
  # homonym it can't confidently place -- e.g. "Zieria" matches both a plant
  # genus (Rutaceae) and an unrelated moss genus, so a bare name/rank lookup
  # resolves to their lowest common ancestor (Kingdom Plantae) instead of
  # erroring. Silently continuing here would try to fetch a whole kingdom, so
  # this must fail loudly instead.
  if (isTRUE(match$matchType == "HIGHERRANK")) {
    stop(
      "`taxon_name` = \"", taxon_name, "\" is ambiguous on GBIF (it matches more than one taxon, ",
      "e.g. a homonym in a different kingdom/family) and only resolved as far as its common ancestor, ",
      match$scientificName, " (", tolower(match$rank), "). Disambiguate by checking ",
      "https://www.gbif.org/species/search?q=", utils::URLencode(taxon_name, reserved = TRUE),
      " and either refine `taxon_name` (e.g. include authorship) or pass the exact GBIF usageKey instead."
    )
  }

  key <- as.integer(match$usageKey)
  if (isTRUE(tolower(match$status) == "synonym") && "acceptedUsageKey" %in% names(match) &&
      !is.na(match$acceptedUsageKey)) {
    key <- as.integer(match$acceptedUsageKey)
  }

  list(key = key, rank = tolower(match$rank))
}

# fetch (and cache) the full set of backbone taxa below `root_key`, in large
# paginated batches -- this is the piece that replaces the old one-API-call-
# per-taxon loop and is what makes repeat/filtered lookups fast
fetch_gbif_taxon_tree <- function(root_key, cache_dir, refresh_cache, max_cache_age_days, quiet,
                                   max_taxa = 50000, force_large_fetch = FALSE, parallel_requests = 4,
                                   .depth = 0) {

  cache_file <- file.path(cache_dir, paste0("gbif_tree_", root_key, ".rds"))

  if (!refresh_cache && cache_is_fresh(cache_file, max_cache_age_days)) {
    if (!quiet) message("Using cached taxonomic tree for GBIF key ", root_key, ".")
    return(readRDS(cache_file))
  }

  page_limit <- 1000
  # unlike every other rgbif call in this file, this one had no retry wrapper at all until a real
  # failure here (deep inside a large recursive split -- ~5,400 children into fetching Insecta's own
  # breakdown) took down the entire branch on a single transient failure, with no chance to recover.
  first_page <- with_gbif_retry(function() {
    rgbif::name_lookup(
      higherTaxonKey = root_key,
      datasetKey = gbif_backbone_dataset_key,
      limit = page_limit,
      start = 0,
      curlopts = gbif_curlopts
    )
  })
  total <- first_page$meta$count

  # a bare taxon name can resolve much higher than intended (see the
  # HIGHERRANK guard in `resolve_gbif_taxon()`); this is a second, independent
  # backstop so an unexpectedly huge clade doesn't silently trigger a fetch
  # that could take hours, rather than erroring in seconds. Only checked at the top level (.depth == 0)
  # -- a recursive call (see fetch_gbif_taxon_tree_by_children()) is fetching one piece of a clade the
  # caller already explicitly committed to via force_large_fetch, so it always proceeds regardless of
  # how that one piece's own size compares to max_taxa.
  if (.depth == 0 && total > max_taxa && !force_large_fetch) {
    stop(
      "GBIF key ", root_key, " has ", total, " descendant taxa, which is more than `max_taxa` (",
      max_taxa, "). This is either intentional (a very large clade) or a sign `taxon_name` resolved ",
      "more broadly than expected. Re-run with `force_large_fetch = TRUE` (and expect ",
      ceiling(total / page_limit), " GBIF API calls) if this is the taxon you meant."
    )
  }

  # GBIF's name_lookup() can't page past offset `gbif_max_lookup_offset` at all (a hard server-side
  # limit -- see that constant's own comment) -- split into root_key's immediate children and fetch
  # each recursively instead, rather than attempting (and failing) to page this directly.
  if (total > gbif_max_lookup_offset) {
    return(fetch_gbif_taxon_tree_by_children(
      root_key = root_key, total = total, cache_file = cache_file, cache_dir = cache_dir,
      refresh_cache = refresh_cache, max_cache_age_days = max_cache_age_days, quiet = quiet,
      max_taxa = max_taxa, parallel_requests = parallel_requests, .depth = .depth
    ))
  }

  offsets <- if (total > page_limit) seq(page_limit, total - 1, by = page_limit) else integer(0)
  n_workers <- max(1, min(parallel_requests, length(offsets)))

  if (!quiet) {
    message(sprintf(
      "Fetching %d descendant taxa for GBIF key %d from GBIF (%d page%s%s)...",
      total, root_key, ceiling(max(total, 1) / page_limit), if (total > page_limit) "s" else "",
      if (n_workers > 1) sprintf(", %d at a time", n_workers) else ""
    ))
  }

  fetch_page <- function(start) {
    rgbif::name_lookup(
      higherTaxonKey = root_key,
      datasetKey = gbif_backbone_dataset_key,
      limit = page_limit,
      start = start,
      curlopts = gbif_curlopts
    )$data
  }

  # a single page occasionally fails with a transient network/TLS error (observed in practice on a
  # large, thousands-of-pages fetch -- e.g. "LibreSSL SSL_read... bad decrypt") rather than anything
  # wrong with the request itself; retrying a couple of times with a short backoff resolves it almost
  # always. Without this, one flaky page would fail the *entire* tree fetch (see the "no silent partial
  # data" check below) even after every other page of a very large, slow fetch already succeeded --
  # wasteful for a clade with thousands of pages, where redoing the whole fetch from scratch is
  # expensive. Retried inside fetch_page() itself (not at the mclapply()/lapply() call site) so it
  # applies identically whichever of those two actually runs it.
  fetch_page_with_retry <- function(start, max_attempts = 3) {
    for (attempt in seq_len(max_attempts)) {
      result <- try(fetch_page(start), silent = TRUE)
      if (!inherits(result, "try-error")) return(result)
      if (attempt < max_attempts) Sys.sleep(2 * attempt)
    }
    result
  }

  # the remaining pages (beyond the first, already fetched above) are independent requests -- fetch
  # them concurrently via parallel::mclapply() rather than one at a time. This is a fork-based
  # parallelism (Unix-alike only -- mclapply silently falls back to sequential on Windows, so this is
  # always correct, just not always faster) chosen over adding a new async-HTTP dependency, since
  # rgbif::name_lookup() itself has no batching/async option to hook into. For a large clade (tens of
  # thousands of pages of descendants) this is where nearly all the wall-clock time goes, so this is a
  # meaningful speedup, not a cosmetic one.
  remaining_pages <- if (length(offsets) == 0) {
    list()
  } else if (n_workers > 1) {
    parallel::mclapply(offsets, fetch_page_with_retry, mc.cores = n_workers)
  } else {
    lapply(offsets, fetch_page_with_retry)
  }

  # mclapply() doesn't propagate a worker's error to the caller -- it captures it and returns a
  # "try-error" object for that one job instead, so a page silently going missing would otherwise
  # produce an incomplete tree with no indication anything went wrong. Fail loudly instead, naming how
  # many pages were lost, matching this package's existing "clear error over silent partial data"
  # convention (e.g. the `country` code / `canonical_name`-NA checks elsewhere in the package).
  failed <- vapply(remaining_pages, function(x) inherits(x, "try-error"), logical(1))
  if (any(failed)) {
    stop(
      "Fetching GBIF key ", root_key, "'s taxonomic tree failed on ", sum(failed), " of ",
      length(offsets), " page(s). First error: ", attr(remaining_pages[failed][[1]], "condition")$message
    )
  }

  if (!quiet && length(offsets) > 0) {
    message(sprintf("  ...fetched all %d page(s).", length(offsets) + 1))
  }

  pages <- c(list(first_page$data), remaining_pages)

  root_usage <- with_gbif_retry(function() rgbif::name_usage(key = root_key, curlopts = gbif_curlopts)$data)

  tree <- dplyr::bind_rows(root_usage, pages) |>
    dplyr::distinct(.data$key, .keep_all = TRUE)

  saveRDS(tree, cache_file)
  tree
}

# `total` exceeds gbif_max_lookup_offset -- name_lookup() can't page root_key's descendants directly
# (see that constant's own comment). Splits into root_key's immediate children instead and fetches each
# one recursively via fetch_gbif_taxon_tree() itself -- a child may still be too large and need
# splitting again (hence the .depth-guarded recursion), but every taxon's children are smaller than the
# taxon itself, so this always terminates.
#
# Each recursive call caches its own result under its own key, exactly like the direct-fetch path --
# this makes a large, multi-child fetch naturally resumable for free: if interrupted partway through
# (a crash, a reboot, hitting Ctrl-C), whichever children already finished are cached on disk, and
# simply calling generate_GBIF_taxonomic_reference_list() again only re-fetches whatever's still
# missing, rather than restarting the whole clade from scratch. No separate checkpointing mechanism
# needed -- the disk cache already used by every fetch (of any size) *is* the checkpoint.
#
# Children are fetched one at a time (not in parallel) -- each child's own fetch already parallelises
# across *its* pages internally (parallel_requests), and nesting mclapply() inside mclapply() would
# oversubscribe cores (e.g. 4 children x 4 pages each = 16-way contention on what might be a 4-8 core
# machine) for no real benefit, since the expensive part (many pages within one large child) is already
# concurrent.
fetch_gbif_taxon_tree_by_children <- function(root_key, total, cache_file, cache_dir, refresh_cache,
                                               max_cache_age_days, quiet, max_taxa, parallel_requests,
                                               .depth) {

  # a taxon's children should always be smaller than the taxon itself -- if we're still hitting the
  # offset limit after several levels of splitting, something is structurally wrong with this part of
  # the backbone (or a bug in this function) rather than a clade that just genuinely needs one more
  # split; fail clearly rather than recursing indefinitely.
  if (.depth >= 6) {
    stop(
      "GBIF key ", root_key, " (", total, " descendants) still exceeds GBIF's max lookup offset (",
      gbif_max_lookup_offset, ") after splitting into children ", .depth, " levels deep. This is ",
      "unexpected -- a taxon's children should be smaller than the taxon itself -- and likely means ",
      "something is wrong with this part of the GBIF backbone. Investigate manually at ",
      "https://www.gbif.org/species/", root_key, "."
    )
  }

  if (!quiet) {
    message(sprintf(
      "GBIF key %d has %d descendants, more than GBIF's max lookup offset (%d) allows to page directly -- splitting into its immediate children...",
      root_key, total, gbif_max_lookup_offset
    ))
  }

  children <- fetch_gbif_taxon_children(root_key)

  if (nrow(children) == 0) {
    stop(
      "GBIF key ", root_key, " has ", total, " descendants (more than GBIF's max lookup offset allows ",
      "to page directly) but reports no children to split into -- can't fetch this taxon's tree this ",
      "way. Investigate manually at https://www.gbif.org/species/", root_key, "."
    )
  }

  child_trees <- purrr::map(children$key, function(child_key) {
    fetch_gbif_taxon_tree(
      root_key = child_key, cache_dir = cache_dir, refresh_cache = refresh_cache,
      max_cache_age_days = max_cache_age_days, quiet = quiet, max_taxa = max_taxa,
      # already committed to fetching this whole clade -- every child is fetched regardless of its own
      # size relative to max_taxa
      force_large_fetch = TRUE, parallel_requests = parallel_requests, .depth = .depth + 1
    )
  })

  root_usage <- with_gbif_retry(function() rgbif::name_usage(key = root_key, curlopts = gbif_curlopts)$data)

  tree <- dplyr::bind_rows(c(list(root_usage), child_trees)) |>
    dplyr::distinct(.data$key, .keep_all = TRUE)

  saveRDS(tree, cache_file)
  tree
}

# the immediate (one-rank-below) children of `root_key`, not its full descendant subtree -- paginated
# the same way as the main tree fetch, since a very large clade can have more direct children than
# name_usage()'s own default page size (e.g. hundreds of families under a huge order). Unlike
# name_lookup()'s paged response, name_usage(data = "children")'s `meta` has no `count` field -- only
# `endOfRecords` -- so pages are fetched until that flag is set (or an empty page is returned) rather
# than computed from a known total up front.
fetch_gbif_taxon_children <- function(root_key) {
  page_limit <- 1000
  pages <- list()
  start <- 0

  repeat {
    page <- with_gbif_retry(function() {
      rgbif::name_usage(
        key = root_key, data = "children", datasetKey = gbif_backbone_dataset_key,
        limit = page_limit, start = start, curlopts = gbif_curlopts
      )
    })
    pages[[length(pages) + 1]] <- page$data
    if (isTRUE(page$meta$endOfRecords) || nrow(page$data) == 0) break
    start <- start + page_limit
  }

  dplyr::bind_rows(pages)
}

# fetch (and cache) the set of backbone taxonKeys with at least one GBIF
# occurrence record in `country`, scoped per requested taxon name so each
# facet query stays cheap and returns in a single API call
fetch_gbif_country_keys <- function(roots, country, cache_dir,
                                     refresh_cache, max_cache_age_days, facet_limit, quiet) {

  country <- toupper(country)

  purrr::map(roots, function(root) {
    cache_file <- file.path(cache_dir, paste0("gbif_occ_", root$key, "_", country, ".rds"))

    if (!refresh_cache && cache_is_fresh(cache_file, max_cache_age_days)) {
      if (!quiet) message("Using cached occurrence keys for GBIF key ", root$key, " in ", country, ".")
      return(readRDS(cache_file))
    }

    if (!quiet) message("Querying GBIF occurrences in ", country, " for GBIF key ", root$key, "...")

    occ <- with_gbif_retry(function() {
      rgbif::occ_search(
        taxonKey = root$key,
        country = country,
        limit = 0,
        facet = "taxonKey",
        facetLimit = facet_limit,
        curlopts = gbif_curlopts
      )
    })

    keys <- if ("name" %in% names(occ$facets$taxonKey)) as.integer(occ$facets$taxonKey$name) else integer(0)

    if (length(keys) == facet_limit) {
      warning(
        "The number of taxa occurring in ", country, " for GBIF key ", root$key,
        " may exceed `facet_limit` (", facet_limit, "); results may be truncated. ",
        "Consider increasing `facet_limit`.",
        call. = FALSE
      )
    }

    saveRDS(keys, cache_file)
    keys
  }) |>
    purrr::list_c() |>
    unique()
}

cache_is_fresh <- function(cache_file, max_cache_age_days) {
  file.exists(cache_file) &&
    as.numeric(difftime(Sys.time(), file.info(cache_file)$mtime, units = "days")) <= max_cache_age_days
}

# recycle a length-1 hint (e.g. `name_rank`) up to length(taxon_name), or
# validate it already matches
recycle_against_taxon_name <- function(x, taxon_name, arg_name) {
  if (is.null(x)) return(x)
  if (length(x) == 1) return(rep(x, length(taxon_name)))
  if (length(x) != length(taxon_name)) {
    stop("`", arg_name, "` must have length 1 or the same length as `taxon_name`.")
  }
  x
}

`%||%` <- function(x, y) if (is.null(x)) y else x
