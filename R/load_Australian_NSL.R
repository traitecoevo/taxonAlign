# Groups load_Australian_NSL() knows how to load -- one `inst/extdata/Australian_<group>/` folder per
# group, each holding one "taxon" file (taxon-concept-level: acceptedNameUsageID/parentNameUsageID/
# taxonomicStatus, full synonym-to-accepted resolution) and one "names" file (name-level: a broader,
# flat index of every name coined for the group, including ones never promoted to a full taxon
# concept -- no acceptedNameUsageID at all). Both are exports from the National Species List (NSL,
# https://www.anbg.gov.au/chah/nsl/) sharing one column schema across every group, confirmed identical
# column-for-column across algae/fungi/lichens/bryophytes. Extend this vector (and, once its files
# exist, nothing else needs to change) when "Australian_animals" is added.
taxonAlign_NSL_known_groups <- c("algae", "bryophytes", "fungi", "lichens", "animals")

# NSL taxonRank values known, with certainty, to sit at family rank or broader (i.e. never genus-
# prefixed in canonicalName) -- used only for the *taxon* file, where there's no dedicated genus/
# genericName column to read from directly (see load_Australian_NSL()'s own comment on this). A
# bespoke list rather than reusing taxonAlign_taxon_rank_specificity (prepare_taxonomic_resources.R):
# that vector is tuned to AFD/GBIF/APC's own vocabulary (phylum/subphylum, no "division" concept at
# all), while NSL's fungal/algal/bryophyte data uses the botanical "division"/"subdivision" terms for
# the same concept, plus at least one raw spelling quirk seen in the real algae export
# ("Subphyllum", not "Subphylum") -- listed here defensively alongside the correct spelling. Extend as
# further above-genus rank spellings turn up, the same "extend, don't guess" convention
# `taxonAlign_taxon_rank_specificity`/`taxonAlign_taxonomic_status_priority` already use.
taxonAlign_NSL_above_genus_ranks <- tolower(c(
  "Kingdom", "Subkingdom", "Domain",
  "Phylum", "Subphylum", "Subphyllum", "Superphylum", "Division", "Subdivision", "Superdivision",
  "Class", "Subclass", "Superclass",
  "Order", "Suborder", "Superorder",
  "Family", "Subfamily", "Superfamily", "Epifamily",
  "Tribe", "Subtribe", "Supertribe"
))

#' Load an Australian National Species List (NSL) reference dataset
#'
#' Reads and reshapes the bundled Australian National Species List (NSL) export for one taxonomic
#' group -- `"algae"`, `"bryophytes"`, `"fungi"`, `"lichens"` or `"animals"` (once its files exist)
#' -- into taxonAlign's flat, [prepare_taxonomic_resources()]-ready column schema. Each group's raw
#' data ships as a *pair* of files under `inst/extdata/Australian_<group>/`: a "taxon" file (one row
#' per taxon concept, with real synonym-to-accepted resolution via `acceptedNameUsageID`) and a
#' "names" file (a broader name-level index, including names never promoted to a full taxon concept,
#' but with no accepted-name resolution of its own). Complements
#' [load_taxonomic_resources()]/[generate_GBIF_taxonomic_reference_list()] the same way, for this
#' source.
#'
#' The two files are combined with the taxon file always taking priority over the names file: every
#' name already represented in the taxon file (matched on its own `scientificNameID`) is dropped from
#' the names file's contribution before combining, so a name never enters the result twice. This
#' mirrors how `iNat`'s hardcoded `"accepted"` status is described elsewhere in this package's own
#' `development-history.qmd` vignette -- the names file can only *widen* matching coverage (informal/
#' unplaced/excluded names with no taxon concept of their own), never resolve a synonym forward, since
#' it carries no `acceptedNameUsageID` at all; the taxon file is the one source of real synonymy here.
#'
#' `genus` is read directly from the names file's own `genericName` column (blank whenever not
#' applicable), but has to be derived for the taxon file, which has no equivalent column: NSL's own
#' naming convention always prefixes an infrageneric/infraspecific canonical name with its governing
#' genus (e.g. the subgenus `"Agaricus subg. Homophron"`, the species `"Scutellinia badioberbis"`), so
#' `extract_genus()` on the *raw* `canonicalName` recovers it correctly for genus rank and everything
#' narrower -- `genus` is only forced to `NA` for family rank and broader
#' (`taxonAlign_NSL_above_genus_ranks`), where no such prefixing convention applies (e.g. the bare
#' tribe name `"Distomatina"`).
#'
#' Subgenus rank gets one further, separate correction: `canonical_name` itself is stripped down to
#' the bare subgenus name (`"Agaricus subg. Homophron"` -> `"Homophron"`, via
#' `strip_NSL_subgenus_marker()`) -- matching AFD's own bare-subgenus-name convention, and what
#' [prepare_taxonomic_resources()]'s `subgenus_v2`/bracketed-`"Genus (Subgenus)"` machinery (issue #14)
#' expects `canonical_name` to already be. Recognising `"Genus subg. Subgenusname"` itself as an
#' *input* naming convention when matching a query is the query-side half of this, handled in
#' `match_taxa()`'s `match_02x` block (see issue #25) -- not this function.
#'
#' @param taxon_group Character scalar naming the group to load: one of `"algae"`, `"bryophytes"`,
#'  `"fungi"`, `"lichens"`, `"animals"`.
#' @param path Directory containing that group's pair of NSL CSV files. Defaults to the bundled copy,
#'  `system.file("extdata", paste0("Australian_", taxon_group), package = "taxonAlign")` -- override
#'  once these files are no longer shipped in-package (e.g. downloaded from a versioned GitHub
#'  release) to point at wherever you've put your own copy.
#' @param refresh_cache Logical; if `TRUE`, re-reshapes the raw files even if a cached copy exists.
#'  Defaults to `FALSE`.
#' @param cache_dir Directory the reshaped result is cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A flat tibble in the column shape [prepare_taxonomic_resources()] expects -- pass it (or a
#'  list combining it with other tables) straight in, e.g.
#'  `prepare_taxonomic_resources(list(load_Australian_NSL("fungi"), load_Australian_NSL("lichens")))`.
#'
#' @export
load_Australian_NSL <- function(taxon_group,
                                 path = NULL,
                                 refresh_cache = FALSE,
                                 cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                 quiet = FALSE) {

  if (length(taxon_group) != 1 || !taxon_group %in% taxonAlign_NSL_known_groups) {
    stop(
      "`taxon_group` must be exactly one of: ", paste(taxonAlign_NSL_known_groups, collapse = ", "),
      ".", call. = FALSE
    )
  }

  if (is.null(path)) {
    path <- system.file("extdata", paste0("Australian_", taxon_group), package = "taxonAlign")
  }
  if (path == "" || !dir.exists(path)) {
    stop(
      "Couldn't find the NSL reference folder for \"", taxon_group, "\"",
      if (nzchar(path)) paste0(" at \"", path, "\"") else "",
      ". Pass `path` to point at the directory holding its \"-taxon-\"/\"-names-\" CSV pair.",
      call. = FALSE
    )
  }

  taxon_file <- find_NSL_file(path, "-taxon-", taxon_group)
  names_file <- find_NSL_file(path, "-names-", taxon_group)

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  cache_key <- paste(
    vapply(c(taxon_file, names_file), function(f) {
      info <- file.info(f)
      paste0(round(as.numeric(info$size)), "_", round(as.numeric(info$mtime)))
    }, character(1)),
    collapse = "_"
  )
  cache_file <- file.path(cache_dir, paste0("NSL_", taxon_group, "_", cache_key, ".rds"))

  if (!refresh_cache && file.exists(cache_file)) {
    if (!quiet) message("Using cached \"", taxon_group, "\" NSL reference (reshaped from \"", path, "\").")
    return(readRDS(cache_file))
  }

  if (!quiet) message("Reading and reshaping the \"", taxon_group, "\" NSL reference from \"", path, "\"...")

  # every column forced to character on read -- matches load_AFD()'s own reasoning: readr's sample-
  # based type-guessing can mis-infer a sparsely-populated column (e.g. infraspecificEpithet) as
  # logical, which breaks the moment a real value shows up
  col_types <- readr::cols(.default = readr::col_character())
  taxon_raw <- readr::read_csv(taxon_file, col_types = col_types, progress = FALSE)
  names_raw <- readr::read_csv(names_file, col_types = col_types, progress = FALSE)

  taxon_flat <- reshape_NSL_taxon(taxon_raw)
  # taxa always take priority over names: any name already represented as its own taxon concept is
  # dropped from the names file's contribution, rather than left to duplicate it
  names_flat <- reshape_NSL_names(names_raw[!names_raw$scientificNameID %in% taxon_raw$scientificNameID, ])

  reshaped <- dplyr::bind_rows(taxon_flat, names_flat)

  saveRDS(reshaped, cache_file)
  reshaped
}

# Locates the one file in `dir` whose basename contains `marker` ("-taxon-" or "-names-") -- the raw
# NSL export's own filename prefix (AAL/AFL/ALC/CAB for taxon; AANI/AFNI/ALNI/ABNI for names) varies
# per group, but this substring doesn't, so matching on it (rather than a fixed prefix-to-group map)
# generalises automatically to a group not yet seen, including the eventual "animals" folder.
#' @noRd
find_NSL_file <- function(dir, marker, taxon_group) {
  candidates <- list.files(dir, pattern = marker, full.names = TRUE)
  candidates <- candidates[tools::file_ext(candidates) == "csv"]
  if (length(candidates) != 1) {
    stop(
      "Expected exactly one \"", marker, "\" CSV file in \"", dir, "\" for taxon_group = \"",
      taxon_group, "\", found ", length(candidates), ".",
      call. = FALSE
    )
  }
  candidates
}

# Strips NSL's own "Genus subg. Subgenusname" prefix down to the bare subgenus name (e.g.
# "Hygrocybe subg. Cuphophyllus" -> "Cuphophyllus"), for rows at subgenus rank only. Needed so
# `canonical_name` matches AFD's own bare-subgenus-name convention (e.g. bare "Podosemum" alongside
# `genus = "Boronia"`) -- prepare_taxonomic_resources()'s `subgenus_v2` construction
# (`genus_and_subgenus = paste0(genus, " (", canonical_name, ")")`) assumes exactly that, and without
# stripping first would double up into a broken, unmatchable key ("Hygrocybe (Hygrocybe subg.
# Cuphophyllus)"). Must run *after* `genus` has already been extracted from the unstripped name (see
# both callers) -- `extract_genus()` relies on the genus being the name's own first word. Left
# unchanged if the shape doesn't match (defensive; every real Subgenus-rank row seen so far does).
# See issue #25 for the query-side half of this fix (recognising this same syntax in a name being
# matched, `match_02x` in match_taxa.R).
#' @noRd
strip_NSL_subgenus_marker <- function(canonical_name, taxon_rank) {
  is_subgenus <- taxon_rank == "Subgenus"
  canonical_name[is_subgenus] <- stringr::str_remove(
    canonical_name[is_subgenus], stringr::regex("^\\S+\\s+subg\\.\\s+", ignore_case = TRUE)
  )
  canonical_name
}

# Reshapes the "taxon" file (one row per taxon concept) into taxonAlign's flat schema.
# `accepted_name_usage_ID` is read straight off `acceptedNameUsageID` -- unlike AFD/GBIF, NSL's own
# export already resolves this itself, including self-referentially for already-accepted rows.
#' @noRd
reshape_NSL_taxon <- function(taxon_raw) {
  genus <- extract_genus(taxon_raw$canonicalName)
  genus[tolower(taxon_raw$taxonRank) %in% taxonAlign_NSL_above_genus_ranks] <- NA_character_

  dplyr::transmute(
    taxon_raw,
    canonical_name = strip_NSL_subgenus_marker(canonicalName, taxonRank),
    scientific_name = scientificName,
    taxon_rank = taxonRank,
    taxonomic_status = taxonomicStatus,
    taxonomic_dataset = datasetName,
    genus = genus,
    taxon_ID = taxonID,
    accepted_name_usage_ID = acceptedNameUsageID
  )
}

# Reshapes the (already taxon-file-deduplicated) "names" file into taxonAlign's flat schema. No
# acceptedNameUsageID exists at this level, so `taxon_ID`/`accepted_name_usage_ID` are both the row's
# own `scientificNameID` -- self-referential, since a bare name-index entry can't be resolved forward
# to anything more authoritative than itself (see this function's own doc for why that's fine: these
# rows only ever widen coverage, they're never relied on to resolve a synonym).
#' @noRd
reshape_NSL_names <- function(names_raw) {
  dplyr::transmute(
    names_raw,
    canonical_name = strip_NSL_subgenus_marker(canonicalName, taxonRank),
    scientific_name = scientificName,
    taxon_rank = taxonRank,
    taxonomic_status = taxonomicStatus,
    taxonomic_dataset = datasetName,
    genus = dplyr::na_if(genericName, ""),
    taxon_ID = scientificNameID,
    accepted_name_usage_ID = scientificNameID
  )
}
