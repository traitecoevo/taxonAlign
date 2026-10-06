# taxadb's own Darwin Core convention (confirmed against its `data-sources` vignette rather than
# guessed): every `taxonID`/`acceptedNameUsageID` is the provider's own integer id, prefixed by the
# provider's abbreviation in caps and a colon -- e.g. "GBIF:2440935", "ITIS:180092". Only the GBIF
# provider's ids are meaningful to rgbif::occ_search()'s `taxonKey` (used for country filtering below),
# so this strips the prefix and parses the integer specifically for that purpose.
strip_taxadb_gbif_prefix <- function(x) {
  as.integer(sub("^GBIF:", "", x))
}

# Columns generate_taxadb_taxonomic_reference_list()'s final transmute() needs from whatever table it's
# fed -- taxadb's own dwc schema, or (via `gbif_snapshot_url`) a directly-queried external parquet file
# whose schema isn't guaranteed stable by taxadb itself (see that argument's own doc). Checked explicitly
# so a schema drift in the latter surfaces as one clear, named error here, not a cryptic "object not
# found" failure deep inside the final dplyr::transmute() call.
taxonAlign_gbif_snapshot_required_cols <- c(
  "taxonID", "scientificName", "taxonRank", "taxonomicStatus", "acceptedNameUsageID",
  "kingdom", "phylum", "class", "order", "family", "genus"
)

# Queries a Darwin-Core-shaped parquet file directly (bypassing taxadb's own R-package registry
# entirely) and returns a lazy dplyr tbl in the same shape taxadb::taxa_tbl() returns -- so every
# downstream step in generate_taxadb_taxonomic_reference_list() (rank filtering, synonym filtering,
# country filtering, the final transmute) works unchanged regardless of which source fed it.
#
# Reuses taxadb::td_connect()'s own cached duckdb connection (an *exported* function, unlike its
# internal duckdb_view() helper -- deliberately not called via `taxadb:::`, both to avoid depending on
# an implementation detail that could change without notice and to avoid the R CMD check NOTE a `:::`
# call to another package triggers) rather than opening a fresh connection per call, so repeated calls
# in the same session reuse one connection rather than accumulating several. `CREATE VIEW IF NOT EXISTS`
# makes registering the view itself idempotent -- cheap regardless (it's metadata only; no download
# happens until a query actually runs against it) -- keyed by a short hash of the URL so two different
# snapshot URLs used in the same session don't collide on the same view name.
#' @noRd
gbif_snapshot_tbl <- function(url) {
  if (!requireNamespace("duckdb", quietly = TRUE) || !requireNamespace("DBI", quietly = TRUE)) {
    stop(
      "`duckdb`/`DBI` are required for `gbif_snapshot_url` but aren't installed. Both are dependencies ",
      "of `taxadb` itself, so `install.packages(\"taxadb\")` should already have pulled them in -- try ",
      "reinstalling if they're genuinely missing.",
      call. = FALSE
    )
  }

  con <- taxadb::td_connect()
  view_name <- paste0("taxonAlign_gbif_snapshot_", substr(rlang::hash(url), 1, 12))

  tryCatch(
    {
      # httpfs auto-installs/loads on first use of an http(s) path in current DuckDB, but installed
      # explicitly and idempotently here too, rather than relying on that default remaining true.
      DBI::dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
      DBI::dbExecute(
        con,
        paste0("CREATE VIEW IF NOT EXISTS \"", view_name, "\" AS SELECT * FROM read_parquet('", url, "')")
      )
    },
    error = function(e) {
      stop(
        "Couldn't query the GBIF snapshot at \"", url, "\" -- check the URL is reachable and points to ",
        "a Darwin-Core-shaped parquet file. Underlying error: ", conditionMessage(e),
        call. = FALSE
      )
    }
  )

  tbl <- dplyr::tbl(con, view_name)
  missing_cols <- setdiff(taxonAlign_gbif_snapshot_required_cols, colnames(tbl))
  if (length(missing_cols) > 0) {
    stop(
      "The file at `gbif_snapshot_url` (\"", url, "\") is missing expected column(s): ",
      paste(missing_cols, collapse = ", "), ". This direct-parquet path isn't wired into taxadb's own ",
      "schema guarantees (see `?generate_taxadb_taxonomic_reference_list`'s `gbif_snapshot_url` docs) -- ",
      "the file's own schema may have changed.",
      call. = FALSE
    )
  }
  tbl
}

#' Generate a taxonomic reference list from a taxadb-cached authority
#'
#' Builds a table of taxon names for one taxon group (e.g. a phylum, a class, a family), sourced from
#' [taxadb](https://docs.ropensci.org/taxadb/)'s own pre-processed, versioned, locally-cached snapshot
#' of a taxonomic authority, rather than fetching live from that authority's own API.
#'
#' @description
#' [generate_GBIF_taxonomic_reference_list()] fetches directly from GBIF's live API, paginating through
#' the whole taxonomic tree below `taxon_name` -- practical for a small clade, but slow and fragile for
#' a genuinely large one (GBIF's taxonomy-browsing endpoint refuses to serve pages past a 100,000-row
#' offset at all, forcing a large clade to be split recursively into smaller pieces; see that function's
#' own documentation). `taxadb` sidesteps this: it downloads and locally caches a small number of large,
#' pre-built snapshot files per provider, then answers a taxon-group filter as an ordinary local
#' database query -- fast and reliable regardless of how large the group is.
#'
#' **This currency trade-off is much larger in practice than taxadb's own documentation suggests, so
#' verify it yourself before relying on it.** taxadb's `data-sources` vignette describes "semi-annual"
#' snapshots, but `taxadb:::available_versions()` currently returns the same single version
#' (`"22.12"`, December 2022) for *every* provider it lists -- the underlying data pipeline appears to
#' have stopped publishing new snapshots years ago, not months. A raw usageKey-level comparison against
#' a live GBIF fetch for the same clade found meaningfully lower agreement than a few years' staleness
#' alone would suggest, though real end-to-end name-alignment tasks were affected far less. Re-check
#' `taxadb:::available_versions()` yourself before trusting this function for anything where currency
#' matters; this package can't control whether taxadb's maintainers resume publishing.
#'
#' **A genuinely current GBIF alternative exists outside taxadb's own R bindings -- `gbif_snapshot_url`
#' (see issue #23).** The maintainer confirmed (2026) that current-year GBIF snapshots are uploaded as
#' raw Darwin-Core parquet files to `source.coop` well before they're wired into `taxadb`'s own
#' `td_create()`/`taxa_tbl()` registry (which is what stays frozen at `"22.12"` regardless). Passing a
#' URL here (e.g. `"https://data.source.coop/cboettig/taxadb/2026/dwc_gbif_part_0.parquet"`) queries
#' that file directly via DuckDB, bypassing the stale registry entirely for `provider = "gbif"`.
#' Verified directly against a live GBIF fetch for the same real gap cases the `"22.12"` snapshot
#' missed (`"Trachytetra"` and its species, `"Austrocardiophorus"`, `"Onthophagus bulga"`, `"Trioza
#' melaleucae"`) -- all four now resolve. Opt-in, not the default, because the maintainer's own caveat
#' when confirming this ("I haven't had a chance to update the taxadb bindings themselves or verify we
#' don't have breaking changes") means schema stability here isn't a guarantee taxadb itself is making
#' -- `gbif_snapshot_tbl()` checks the expected columns are present and errors clearly if not, rather
#' than failing confusingly deeper in this function, but a column being *renamed* rather than dropped
#' could still slip through undetected.
#'
#' This function is deliberately narrower than `generate_GBIF_taxonomic_reference_list()`: it has no
#' concept of "a minimum rank to include below `taxon_name`" (every row taxadb has for the requested
#' group is returned, at whatever ranks that provider records), and `country` filtering is only
#' available for `provider = "gbif"` -- `taxadb` itself has no occurrence data at all for any provider,
#' so the country dimension still comes entirely from GBIF's own occurrence-record API (reusing the
#' same internal helper `generate_GBIF_taxonomic_reference_list()` uses for this), the one piece
#' `taxadb` genuinely can't supply.
#'
#' @param taxon_name Character, a single taxon name to build the reference list from (e.g.
#'  `"Chordata"`, `"Formicidae"`). Every row `taxadb` has below this name is included.
#' @param rank Character, the taxonomic rank of `taxon_name` (e.g. `"phylum"`, `"family"`) -- this
#'  picks which of the provider's hierarchy columns (`kingdom`/`phylum`/`class`/`order`/`family`/
#'  `genus`) to filter on. Required, and means something different from
#'  `generate_GBIF_taxonomic_reference_list()`'s own `rank` argument (which is an optional *minimum*
#'  rank filter applied after resolving `taxon_name`, not a required key telling the function which
#'  column to look in).
#' @param provider Character, which `taxadb`-supported authority to source from -- see [taxadb::td_create()]
#'  for the current list (`"gbif"`, `"itis"`, `"col"`, `"ncbi"`, `"ott"`, `"iucn"`, and some
#'  less-actively-maintained ones). Defaults to `"gbif"`. Only `"gbif"` supports `country` filtering.
#' @param country Optional ISO 3166-1 alpha-2 country code (e.g. `"AU"`). Only valid when
#'  `provider = "gbif"` -- see Description.
#' @param gbif_snapshot_url Optional character; when supplied, queries this Darwin-Core-shaped parquet
#'  file directly instead of `taxadb::taxa_tbl("gbif")` -- see Description. Only valid when
#'  `provider = "gbif"` (this is a GBIF-specific workaround for `taxadb`'s own registry being stale,
#'  not a general mechanism for other providers). Defaults to `NULL` (use `taxadb`'s own registry, as
#'  before).
#' @param include_synonyms Logical; if `FALSE`, only accepted names are returned. Defaults to `TRUE`.
#' @param facet_limit Numeric; forwarded to the same occurrence-facet lookup
#'  `generate_GBIF_taxonomic_reference_list()` uses when `country` is supplied. Defaults to `100000`.
#' @param cache_dir Directory used to cache the (small, GBIF-occurrence-only) country-key lookup when
#'  `country` is supplied -- `taxadb`'s own, much larger, provider-snapshot cache is managed entirely by
#'  `taxadb` itself (see [taxadb::taxadb_dir()]), not by this argument. Defaults to a per-user cache
#'  directory (see [tools::R_user_dir()]), the same one
#'  `generate_GBIF_taxonomic_reference_list()` uses.
#' @param refresh_cache Logical; if `TRUE`, ignore any cached country-key lookup and re-query GBIF's
#'  occurrence API. Has no effect on `taxadb`'s own snapshot cache -- see [taxadb::td_create()]'s own
#'  `overwrite` argument for that. Defaults to `FALSE`.
#' @param max_cache_age_days Numeric; as for `generate_GBIF_taxonomic_reference_list()`. Defaults to 30.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A tibble with one row per taxon, in the same column shape
#'  `generate_GBIF_taxonomic_reference_list()` returns (`taxon_ID`, `accepted_name_usage_ID`,
#'  `scientific_name`, `canonical_name`, `taxon_rank`, `taxonomic_status`, `kingdom`, `phylum`,
#'  `class`, `order`, `family`, `genus`, `taxonomic_dataset`) -- with one real difference worth
#'  knowing: `taxadb`'s own schema has no separate authorship field, so `scientific_name` and
#'  `canonical_name` are identical here (both authorship-free), unlike
#'  `generate_GBIF_taxonomic_reference_list()`'s output, where `scientific_name` includes authorship.
#'
#' @examples
#' \dontrun{
#' # every chordate taxadb's GBIF snapshot has, worldwide
#' generate_taxadb_taxonomic_reference_list("Chordata", rank = "phylum")
#'
#' # the same, restricted to taxa with an Australian GBIF occurrence record
#' generate_taxadb_taxonomic_reference_list("Chordata", rank = "phylum", country = "AU")
#'
#' # bypass taxadb's own stale ("22.12") registry and query a genuinely current GBIF snapshot directly
#' # -- see Description's `gbif_snapshot_url` paragraph before using this in anything automated, since
#' # its schema stability isn't guaranteed by taxadb itself
#' generate_taxadb_taxonomic_reference_list(
#'   "Chordata", rank = "phylum",
#'   gbif_snapshot_url = "https://data.source.coop/cboettig/taxadb/2026/dwc_gbif_part_0.parquet"
#' )
#' }
#'
#' @importFrom rlang .data
#' @export
generate_taxadb_taxonomic_reference_list <- function(taxon_name,
                                                       rank,
                                                       provider = "gbif",
                                                       country = NULL,
                                                       gbif_snapshot_url = NULL,
                                                       include_synonyms = TRUE,
                                                       facet_limit = 100000,
                                                       cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                                       refresh_cache = FALSE,
                                                       max_cache_age_days = 30,
                                                       quiet = FALSE) {

  if (!requireNamespace("taxadb", quietly = TRUE)) {
    stop(
      "The `taxadb` package is required for generate_taxadb_taxonomic_reference_list() but isn't ",
      "installed. Install it with `install.packages(\"taxadb\")`.",
      call. = FALSE
    )
  }
  if (missing(taxon_name) || length(taxon_name) != 1 || is.na(taxon_name)) {
    stop("`taxon_name` must be a single, non-missing taxon name (e.g. \"Chordata\").", call. = FALSE)
  }
  if (missing(rank) || length(rank) != 1 || is.na(rank)) {
    stop(
      "`rank` is required -- the taxonomic rank of `taxon_name` (e.g. \"phylum\"), used to pick which ",
      "hierarchy column of the taxadb table to filter on. Unlike ",
      "generate_GBIF_taxonomic_reference_list()'s own `rank` argument, this is not optional and does ",
      "not mean \"minimum rank to include\".",
      call. = FALSE
    )
  }
  if (!is.null(gbif_snapshot_url) && !identical(tolower(provider), "gbif")) {
    stop(
      "`gbif_snapshot_url` is only supported for `provider = \"gbif\"` -- it's a GBIF-specific ",
      "workaround for `taxadb`'s own registry being stale (see Description), not a general mechanism ",
      "for other providers.",
      call. = FALSE
    )
  }
  if (!is.null(country) && !identical(tolower(provider), "gbif")) {
    stop(
      "`country` filtering is only supported for `provider = \"gbif\"` -- GBIF's own occurrence-record ",
      "API is what supplies the country dimension here, and `taxadb` itself has no occurrence data for ",
      "any provider.",
      call. = FALSE
    )
  }
  if (!is.null(country) && !grepl("^[A-Za-z]{2}$", country)) {
    stop(
      "`country` must be a 2-letter ISO 3166-1 alpha-2 country code (e.g. \"AU\" for Australia), not ",
      "a country name -- got \"", country, "\".",
      call. = FALSE
    )
  }

  rank_col <- tolower(rank)

  if (is.null(gbif_snapshot_url)) {
    # deliberately no `overwrite` argument -- taxadb's own default (leave an already-cached, current
    # snapshot alone) is exactly the "idempotent, don't re-download unless needed" behaviour wanted
    # here; passing `overwrite = FALSE` explicitly instead hits a deprecation warning in taxadb 0.2.1.
    taxadb::td_create(provider)
    source_tbl <- taxadb::taxa_tbl(provider)
  } else {
    if (!quiet) {
      message(
        "Querying the GBIF snapshot at \"", gbif_snapshot_url, "\" directly, bypassing taxadb's own ",
        "(stale) registry."
      )
    }
    source_tbl <- gbif_snapshot_tbl(gbif_snapshot_url)
  }

  full_table <- source_tbl |>
    dplyr::filter(.data[[rank_col]] == !!taxon_name) |>
    dplyr::collect()

  if (nrow(full_table) == 0) {
    stop(
      "No rows found for `taxon_name` = \"", taxon_name, "\" at `rank` = \"", rank, "\" in ",
      if (is.null(gbif_snapshot_url)) paste0("taxadb's \"", provider, "\" provider") else "the GBIF snapshot",
      ". Check the name/rank/provider are correct, and that this taxon is present ",
      "in this provider's data.",
      call. = FALSE
    )
  }

  if (!include_synonyms) {
    full_table <- dplyr::filter(full_table, tolower(.data$taxonomicStatus) == "accepted")
  }

  if (!is.null(country)) {
    if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)

    # `taxadb` supplies the taxon-group slice; GBIF's own occurrence-record API still has to supply the
    # country dimension (see the Description above) -- resolved via the same resolve_gbif_taxon()/
    # fetch_gbif_country_keys() helpers generate_GBIF_taxonomic_reference_list() uses for exactly this,
    # rather than duplicating that logic. Only one, cheap name-resolution + occurrence-facet call is
    # needed here (scoped to `taxon_name` itself), not one per row of `full_table` -- the facet query
    # already covers every descendant of the resolved key, the same way it does for the sibling function.
    root <- resolve_gbif_taxon(taxon_name = taxon_name, name_rank = rank_col, name_kingdom = NULL)

    occ_keys <- fetch_gbif_country_keys(
      roots = list(root),
      country = country,
      cache_dir = cache_dir,
      refresh_cache = refresh_cache,
      max_cache_age_days = max_cache_age_days,
      facet_limit = facet_limit,
      quiet = quiet
    )

    full_table <- dplyr::filter(
      full_table,
      strip_taxadb_gbif_prefix(.data$taxonID) %in% occ_keys |
        strip_taxadb_gbif_prefix(.data$acceptedNameUsageID) %in% occ_keys
    )
  }

  full_table |>
    dplyr::transmute(
      taxon_ID = .data$taxonID,
      # taxadb already documents that a missing acceptedNameUsageID should be treated as
      # self-referential (an already-accepted row) -- matching the convention
      # generate_GBIF_taxonomic_reference_list() and real APC downloads also use.
      accepted_name_usage_ID = dplyr::coalesce(.data$acceptedNameUsageID, .data$taxonID),
      # taxadb's schema has no separate authorship field -- `scientific_name` and `canonical_name` are
      # identical here, unlike generate_GBIF_taxonomic_reference_list()'s output.
      scientific_name = .data$scientificName,
      canonical_name = .data$scientificName,
      taxon_rank = tolower(.data$taxonRank),
      taxonomic_status = tolower(.data$taxonomicStatus),
      kingdom = .data$kingdom,
      phylum = .data$phylum,
      class = .data$class,
      order = .data$order,
      family = .data$family,
      genus = .data$genus,
      taxonomic_dataset = toupper(provider)
    ) |>
    dplyr::distinct(.data$taxon_ID, .keep_all = TRUE) |>
    dplyr::arrange(.data$taxon_rank, .data$canonical_name)
}
