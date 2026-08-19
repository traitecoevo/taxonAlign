# GBIF's "backbone" checklist -- the single deduplicated taxonomy that
# occurrence records are matched against. Restricting `name_lookup()` calls
# to this dataset avoids pulling duplicate names from the hundreds of other
# checklists GBIF indexes.
gbif_backbone_dataset_key <- "d7dddbf4-2cf0-4f39-9b2a-bb099caae36c"

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
#' generate_taxonomic_reference_list("Boronia")
#'
#' # species (and infraspecific taxa) of Boronia recorded in Australia
#' generate_taxonomic_reference_list("Boronia", country = "AU", rank = "species")
#'
#' # combine several families in one call
#' generate_taxonomic_reference_list(c("Rutaceae", "Sapindaceae"), country = "AU")
#' }
#'
#' @importFrom rlang .data
#' @export
generate_taxonomic_reference_list <- function(taxon_name,
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
      force_large_fetch = force_large_fetch
    )
  }) |>
    purrr::list_rbind() |>
    dplyr::distinct(.data$key, .keep_all = TRUE)

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
  match <- rgbif::name_backbone(name = taxon_name, rank = name_rank, kingdom = name_kingdom, verbose = FALSE)

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
                                   max_taxa = 50000, force_large_fetch = FALSE) {

  cache_file <- file.path(cache_dir, paste0("gbif_tree_", root_key, ".rds"))

  if (!refresh_cache && cache_is_fresh(cache_file, max_cache_age_days)) {
    if (!quiet) message("Using cached taxonomic tree for GBIF key ", root_key, ".")
    return(readRDS(cache_file))
  }

  page_limit <- 1000
  first_page <- rgbif::name_lookup(
    higherTaxonKey = root_key,
    datasetKey = gbif_backbone_dataset_key,
    limit = page_limit,
    start = 0
  )
  total <- first_page$meta$count

  # a bare taxon name can resolve much higher than intended (see the
  # HIGHERRANK guard in `resolve_gbif_taxon()`); this is a second, independent
  # backstop so an unexpectedly huge clade doesn't silently trigger a fetch
  # that could take hours, rather than erroring in seconds
  if (total > max_taxa && !force_large_fetch) {
    stop(
      "GBIF key ", root_key, " has ", total, " descendant taxa, which is more than `max_taxa` (",
      max_taxa, "). This is either intentional (a very large clade) or a sign `taxon_name` resolved ",
      "more broadly than expected. Re-run with `force_large_fetch = TRUE` (and expect ",
      ceiling(total / page_limit), " GBIF API calls) if this is the taxon you meant."
    )
  }

  pages <- list(first_page$data)

  if (!quiet) {
    message(sprintf(
      "Fetching %d descendant taxa for GBIF key %d from GBIF (%d page%s)...",
      total, root_key, ceiling(max(total, 1) / page_limit), if (total > page_limit) "s" else ""
    ))
  }

  offsets <- if (total > page_limit) seq(page_limit, total - 1, by = page_limit) else integer(0)
  for (start in offsets) {
    page <- rgbif::name_lookup(
      higherTaxonKey = root_key,
      datasetKey = gbif_backbone_dataset_key,
      limit = page_limit,
      start = start
    )
    pages[[length(pages) + 1]] <- page$data
    if (!quiet) message(sprintf("  ...%d/%d", min(start + page_limit, total), total))
  }

  root_usage <- rgbif::name_usage(key = root_key)$data

  tree <- dplyr::bind_rows(root_usage, pages) |>
    dplyr::distinct(.data$key, .keep_all = TRUE)

  saveRDS(tree, cache_file)
  tree
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

    occ <- rgbif::occ_search(
      taxonKey = root$key,
      country = country,
      limit = 0,
      facet = "taxonKey",
      facetLimit = facet_limit
    )

    keys <- if (!is.null(occ$facets$taxonKey)) as.integer(occ$facets$taxonKey$name) else integer(0)

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
