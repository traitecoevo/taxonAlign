# Groups load_NSL_resources() knows how to load -- one `inst/extdata/Australian_<group>/` folder per
# group, each holding one "taxon" file (taxon-concept-level: acceptedNameUsageID/parentNameUsageID/
# taxonomicStatus, full synonym-to-accepted resolution) and one "names" file (name-level: a broader,
# flat index of every name coined for the group, including ones never promoted to a full taxon
# concept -- no acceptedNameUsageID at all). Both are exports from the National Species List (NSL,
# https://www.anbg.gov.au/chah/nsl/). The four plant-side groups (algae/fungi/lichens/bryophytes) share
# one camelCase, comma-delimited schema; the "animals" export (the Australian Faunal Directory's own
# NSL export) carries the same concepts but as snake_case, pipe-delimited `.txt` files -- see
# read_NSL_file()/standardise_NSL_column_names(), which absorb that difference so every reshaping step
# below sees one schema regardless of group.
taxonAlign_NSL_known_groups <- c("algae", "bryophytes", "fungi", "lichens", "animals")

# NSL taxonRank values known, with certainty, to sit above genus rank (i.e. never genus-prefixed in
# canonical_name) -- used only for the *taxon* file, where there's no reliable own-genus column to read
# from (see load_NSL_resources()'s own doc on this). A bespoke list rather than reusing
# taxonAlign_taxon_rank_specificity (prepare_taxonomic_resources.R): that vector is tuned to
# AFD/GBIF/APC's own vocabulary, while NSL's plant-side data uses the botanical "division"/
# "subdivision" terms, plus at least one raw spelling quirk seen in the real algae export
# ("Subphyllum", not "Subphylum") -- listed here defensively alongside the correct spelling. The
# zoological ranks (cohort/infra-/parv-/subter- ranks, AFD's informal "Higher Taxon", and its
# "Generic Aggregate" -- an informal grouping of genera whose canonical name is written like
# "Subtribe Clerina", so extract_genus() would otherwise return the literal word "Subtribe") were
# added once the animals export turned them up. Compared case-insensitively (the animals export
# writes e.g. "SubFamily"/"InfraOrder"). Deliberately excludes "section": it's above genus in
# zoology (e.g. "Eubrachyura") but below genus in botany ("Genus sect. X") -- a single-word name at a
# non-genus rank gets `genus = NA` regardless (see derive_NSL_genus()), which covers the zoological
# case without breaking the botanical one. Extend as further above-genus rank spellings turn up, the
# same "extend, don't guess" convention `taxonAlign_taxon_rank_specificity`/
# `taxonAlign_taxonomic_status_priority` already use.
taxonAlign_NSL_above_genus_ranks <- tolower(c(
  "Kingdom", "Subkingdom", "Domain",
  "Phylum", "Subphylum", "Subphyllum", "Superphylum", "Infraphylum",
  "Division", "Subdivision", "Superdivision",
  "Class", "Subclass", "Superclass", "Infraclass", "Subterclass",
  "Cohort",
  "Order", "Suborder", "Superorder", "Infraorder", "Parvorder",
  "Family", "Subfamily", "Superfamily", "Epifamily",
  "Tribe", "Subtribe", "Supertribe",
  "Higher Taxon", "Generic Aggregate"
))

# NSL taxonomic_status values whose `accepted_name_usage_id` is *not* a synonymy link. Found in the
# AFD animals export (never in the plant-side groups, whose "excluded" rows are self-referential): an
# excluded/vagrant/intercepted taxon's `accepted_name_usage_id` points at its *parent* taxon (e.g. the
# vagrant species "Pernis ptilorhynchus" -> the family "Accipitridae"), recording where it sits in the
# classification, not what it's a synonym of. Left as-is, update_taxa() would "update" a perfectly
# valid species name to a family. Rows with these statuses are made self-referential instead (their
# own status is still preserved, so they remain distinguishable from accepted taxa).
taxonAlign_NSL_non_synonymy_statuses <- c(
  "excluded", "excluded name", "excluded other", "vagrant species", "intercepted"
)

#' Load an Australian National Species List (NSL) reference dataset
#'
#' Reads and reshapes the Australian National Species List (NSL) export for one taxonomic group --
#' `"animals"` (the Australian Faunal Directory's NSL export), `"algae"`, `"bryophytes"`, `"fungi"` or
#' `"lichens"` -- into taxonAlign's flat, [prepare_taxonomic_resources()]-ready column schema. Each
#' group's raw data is a *pair* of files: a "taxon" file (one row per taxon concept, with real
#' synonym-to-accepted resolution via `accepted_name_usage_id`) and a "names" file (a broader
#' name-level index, including names never promoted to a full taxon concept, but with no accepted-name
#' resolution of its own). Complements [load_taxonomic_resources()]/
#' [generate_GBIF_taxonomic_reference_list()] the same way, for this source.
#'
#' Both export shapes NSL currently produces are accepted: comma-delimited `.csv` files with camelCase
#' column names (the plant-side groups) and pipe-delimited `.txt` files with snake_case column names
#' (the animals export). Files are located by a `taxon`/`name(s)` marker in their filename (e.g.
#' `AFL-taxon-2026-09-18.csv`, `AFD_export_name_20260929.txt`).
#'
#' The two files are combined with the taxon file always taking priority over the names file: every
#' name already represented in the taxon file (matched on its own `scientific_name_id`) is dropped from
#' the names file's contribution before combining, and the taxon rows are bound first, so a name never
#' enters the result twice. The names file can only *widen* matching coverage (informal/unplaced names
#' with no taxon concept of their own), never resolve a synonym forward, since it carries no
#' `accepted_name_usage_id` at all; the taxon file is the one source of real synonymy here.
#'
#' `genus` is read directly from the names file's own `generic_name` column, but is derived from the
#' *raw* canonical name for the taxon file: there, `generic_name` (where present at all) is the genus
#' of the *accepted* name, not of the row's own name -- wrong for a synonym sitting under a different
#' genus. NSL's own convention always prefixes an infrageneric/infraspecific canonical name with its
#' governing genus (e.g. `"Agaricus subg. Homophron"`, `"Acanthiza (Geobasileus)"`,
#' `"Scutellinia badioberbis"`), so the first word recovers it for genus rank and everything narrower;
#' `genus` is `NA` above genus rank.
#'
#' Subgenus rank gets one further correction: `canonical_name` is stripped down to the bare subgenus
#' name, from either NSL's botanical `"Agaricus subg. Homophron"` form or the zoological
#' `"Acanthiza (Geobasileus)"` form -- matching what [prepare_taxonomic_resources()]'s bracketed
#' `"Genus (Subgenus)"` machinery expects `canonical_name` to already be.
#'
#' Excluded, vagrant and intercepted taxa (statuses `"excluded"`, `"excluded name"`,
#' `"excluded other"`, `"vagrant species"`, `"intercepted"`) are made self-referential: in the animals
#' export their `accepted_name_usage_id` points at the parent genus/family rather than at a synonym,
#' which [update_taxa()] would otherwise misread as "this name is now that family".
#'
#' @param taxon_group Character scalar naming the group to load: one of `"animals"`, `"algae"`,
#'  `"bryophytes"`, `"fungi"`, `"lichens"`.
#' @param path Directory containing that group's taxon/names file pair. Defaults to the bundled copy,
#'  `system.file("extdata", paste0("Australian_", taxon_group), package = "taxonAlign")` -- override to
#'  point at wherever you've put your own copy.
#' @param refresh_cache Logical; if `TRUE`, re-reshapes the raw files even if a cached copy exists.
#'  Defaults to `FALSE`.
#' @param cache_dir Directory the reshaped result is cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#'
#' @return A flat tibble in the column shape [prepare_taxonomic_resources()] expects -- pass it (or a
#'  list combining it with other tables) straight in, e.g.
#'  `prepare_taxonomic_resources(list(load_NSL_resources("fungi"), load_NSL_resources("lichens")))`.
#'
#' @export
load_NSL_resources <- function(taxon_group,
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
      ". Pass `path` to point at the directory holding its taxon/names file pair.",
      call. = FALSE
    )
  }

  taxon_file <- find_NSL_file(path, "taxon", taxon_group)
  names_file <- find_NSL_file(path, "names?", taxon_group)

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

  taxon_raw <- clean_NSL_canonical_names(read_NSL_file(taxon_file))
  names_raw <- clean_NSL_canonical_names(read_NSL_file(names_file))

  taxon_flat <- reshape_NSL_taxon(taxon_raw)
  # taxa always take priority over names: any name already represented as its own taxon concept is
  # dropped from the names file's contribution, rather than left to duplicate it
  names_flat <- reshape_NSL_names(names_raw[!names_raw$scientific_name_id %in% taxon_raw$scientific_name_id, ])

  reshaped <- dplyr::bind_rows(taxon_flat, names_flat)

  saveRDS(reshaped, cache_file)
  reshaped
}

# Locates the one file in `dir` whose basename contains `marker` ("taxon", or "names?" to match both
# the plant-side "-names-" and the animals export's "_name_"), delimited by "-" or "_" on both sides.
# The raw export's own filename prefix varies per group (AAL/AFL/ALC/CAB/AFD_export for taxon;
# AANI/AFNI/ALNI/ABNI/AFD_export for names) but this marker doesn't.
#' @noRd
find_NSL_file <- function(dir, marker, taxon_group) {
  candidates <- list.files(dir, pattern = paste0("[-_]", marker, "[-_]"), full.names = TRUE)
  candidates <- candidates[tolower(tools::file_ext(candidates)) %in% c("csv", "txt")]
  if (length(candidates) != 1) {
    stop(
      "Expected exactly one \"", sub("?", "", marker, fixed = TRUE), "\" file (.csv or .txt) in \"",
      dir, "\" for taxon_group = \"", taxon_group, "\", found ", length(candidates), ".",
      call. = FALSE
    )
  }
  candidates
}

# Reads one NSL export file, sniffing the delimiter from its header line (the animals export is
# pipe-delimited, the plant-side groups comma-delimited) and normalising column names to snake_case.
# Every column is forced to character on read -- matches load_AFD()'s own reasoning: readr's sample-
# based type-guessing can mis-infer a sparsely-populated column (e.g. infraspecific_epithet) as
# logical, which breaks the moment a real value shows up.
#' @noRd
read_NSL_file <- function(file) {
  header <- readLines(file, n = 1, warn = FALSE)
  delim <- if (grepl("|", header, fixed = TRUE)) "|" else ","
  raw <- readr::read_delim(
    file, delim = delim, col_types = readr::cols(.default = readr::col_character()), progress = FALSE
  )
  names(raw) <- standardise_NSL_column_names(names(raw))
  raw
}

# camelCase -> snake_case (e.g. "acceptedNameUsageID" -> "accepted_name_usage_id",
# "scientificNameID" -> "scientific_name_id"); already-snake_case names pass through unchanged. Lets
# the plant-side (camelCase) and animals (snake_case) exports share every reshaping step below.
#' @noRd
standardise_NSL_column_names <- function(x) {
  tolower(gsub("([a-z0-9])([A-Z])", "\\1_\\2", x))
}

# Derives `genus` from a raw (pre-subgenus-stripping) canonical name: its first word, except above
# genus rank -- either a rank listed in taxonAlign_NSL_above_genus_ranks, or any single-word name at a
# rank other than genus itself (which catches e.g. zoological "Section" rows like "Eubrachyura",
# without breaking botanical sections, which are always written genus-prefixed, "Genus sect. X").
#' @noRd
derive_NSL_genus <- function(canonical_name, taxon_rank) {
  genus <- extract_genus(canonical_name)
  rank <- tolower(taxon_rank)
  single_word <- !grepl("\\s", stringr::str_trim(canonical_name))
  genus[rank %in% taxonAlign_NSL_above_genus_ranks | (single_word & rank != "genus")] <- NA_character_
  genus
}

# Strips a subgenus-rank canonical name down to the bare subgenus name, from either NSL's botanical
# "Genus subg. Subgenusname" form ("Hygrocybe subg. Cuphophyllus" -> "Cuphophyllus") or the zoological
# "Genus (Subgenusname)" form the animals export uses ("Acanthiza (Geobasileus)" -> "Geobasileus").
# Needed so `canonical_name` matches AFD's own bare-subgenus-name convention --
# prepare_taxonomic_resources()'s `subgenus_v2` construction
# (`genus_and_subgenus = paste0(genus, " (", canonical_name, ")")`) assumes exactly that, and without
# stripping first would double up into a broken, unmatchable key ("Hygrocybe (Hygrocybe subg.
# Cuphophyllus)"). Must run *after* `genus` has already been derived from the unstripped name (see
# both callers). Left unchanged if neither shape matches. See issue #25 for the query-side half of this
# fix (recognising the "subg." syntax in a name being matched, `match_02x` in match_taxa.R).
#' @noRd
strip_NSL_subgenus_marker <- function(canonical_name, taxon_rank) {
  is_subgenus <- tolower(taxon_rank) == "subgenus"
  stripped <- canonical_name[is_subgenus]
  stripped <- stringr::str_remove(stripped, stringr::regex("^\\S+\\s+subg\\.\\s+", ignore_case = TRUE))
  stripped <- stringr::str_replace(stripped, "^\\S+\\s+\\(([^()]+)\\)$", "\\1")
  canonical_name[is_subgenus] <- stripped
  canonical_name
}

# Reshapes the "taxon" file (one row per taxon concept) into taxonAlign's flat schema.
# `accepted_name_usage_ID` is read straight off `accepted_name_usage_id` -- unlike AFD's CSV export or
# GBIF, NSL's own export already resolves this itself, including self-referentially for
# already-accepted rows -- except for the non-synonymy statuses (taxonAlign_NSL_non_synonymy_statuses),
# made self-referential instead.
#' @noRd
reshape_NSL_taxon <- function(taxon_raw) {
  not_synonymy <- tolower(taxon_raw$taxonomic_status) %in% taxonAlign_NSL_non_synonymy_statuses

  dplyr::transmute(
    taxon_raw,
    canonical_name = add_NSL_subgenus(taxon_raw, strip_NSL_subgenus_marker(canonical_name, taxon_rank)),
    scientific_name = scientific_name,
    taxon_rank = taxon_rank,
    taxonomic_status = taxonomic_status,
    taxonomic_dataset = dataset_name,
    genus = derive_NSL_genus(taxon_raw$canonical_name, taxon_raw$taxon_rank),
    taxon_ID = taxon_id,
    accepted_name_usage_ID = ifelse(not_synonymy, taxon_id, accepted_name_usage_id)
  )
}

# Writes the subgenus back into a zoological species-level name, e.g. "Pardalotus striatus" ->
# "Pardalotus (Pardalotinus) striatus", so the NSL export gives the same full name the AFD's CSV export
# does. The NSL export's own canonical_name never includes the subgenus; it's recorded only in the
# classification, as an ancestor reached through parent_name_usage_id (a species' parent, a
# subspecies' grandparent, or via a "Species Aggregate"). prepare_taxonomic_resources() matches on the
# subgenus-free form regardless and puts this full form back into the output afterwards.
#
# Only for ICZN names (`nomenclatural_code`): botanical/mycological names never write a subgenus inside
# a binomial. Only accepted (or other) records that actually have a parent link get one -- synonym
# records have none, and are left as written. The subgenus must belong to the name's own genus (first
# word), or nothing is added.
#' @noRd
add_NSL_subgenus <- function(taxon_raw, canonical_name) {
  if (!all(c("parent_name_usage_id", "nomenclatural_code") %in% names(taxon_raw))) return(canonical_name)

  ids <- taxon_raw$taxon_id
  parent <- taxon_raw$parent_name_usage_id
  rank <- tolower(taxon_raw$taxon_rank)
  species_level <- rank %in% c("species", "subspecies", "variety", "form") &
    taxon_raw$nomenclatural_code %in% "ICZN" & !grepl("(", canonical_name, fixed = TRUE)

  subgenus <- rep(NA_character_, length(ids))
  subgenus_genus <- rep(NA_character_, length(ids))
  current <- ifelse(species_level, parent, NA_character_)
  # walk up the classification until a subgenus (use it) or a genus (no subgenus) is reached -- a few
  # steps at most (subspecies -> species -> species aggregate -> subgenus)
  for (step in 1:5) {
    j <- match(current, ids)
    hit <- !is.na(j) & rank[j] %in% "subgenus"
    subgenus[hit] <- canonical_name[j[hit]]
    subgenus_genus[hit] <- extract_genus(taxon_raw$canonical_name[j[hit]])
    current <- ifelse(is.na(j) | hit | rank[j] %in% "genus", NA_character_, parent[j])
    if (all(is.na(current))) break
  }

  add <- !is.na(subgenus) & subgenus_genus == extract_genus(canonical_name)
  canonical_name[add] <- stringr::str_replace(
    canonical_name[add], "^(\\S+) ", paste0("\\1 (", subgenus[add], ") ")
  )
  canonical_name
}

# Reshapes the (already taxon-file-deduplicated) "names" file into taxonAlign's flat schema. No
# accepted_name_usage_id exists at this level, so `taxon_ID`/`accepted_name_usage_ID` are both the
# row's own `scientific_name_id` -- self-referential, since a bare name-index entry can't be resolved
# forward to anything more authoritative than itself (these rows only ever widen coverage, they're
# never relied on to resolve a synonym). Unlike the taxon file, `generic_name` here is the name's own
# genus, so it's used directly (still masked above genus rank).
#' @noRd
reshape_NSL_names <- function(names_raw) {
  genus <- dplyr::na_if(names_raw$generic_name, "")
  genus[is.na(derive_NSL_genus(names_raw$canonical_name, names_raw$taxon_rank))] <- NA_character_

  dplyr::transmute(
    names_raw,
    canonical_name = strip_NSL_subgenus_marker(canonical_name, taxon_rank),
    scientific_name = scientific_name,
    taxon_rank = taxon_rank,
    taxonomic_status = taxonomic_status,
    taxonomic_dataset = dataset_name,
    genus = genus,
    taxon_ID = scientific_name_id,
    accepted_name_usage_ID = scientific_name_id
  )
}

# Removes quote marks around a word or name from `canonical_name` ("'Ochlerotatus' notoscriptus" ->
# "Ochlerotatus notoscriptus"; the quotes flag a doubtful generic placement, kept in `scientific_name`)
# and stray control characters ("Mesomyzostoma lobus\u009d") -- the same treatment the AFD-format loader
# gives the same names, so the two formats are compared, and matched, like for like.
#' @noRd
clean_NSL_canonical_names <- function(raw) {
  raw$canonical_name <- strip_name_quotes(gsub("[[:cntrl:]]", " ", raw$canonical_name))
  # a few canonical names still carry the AFD's misapplication/part markers ("Saragus auctt. nec",
  # "Entomobrya clitellaria sensu"): read them as the AFD-format loader does, but only to sharpen a
  # plain "synonym" status, never to override a more specific NSL status
  marked <- strip_afd_usage_markers(raw$canonical_name) != raw$canonical_name
  if ("taxonomic_status" %in% names(raw)) {
    plain <- marked & raw$taxonomic_status %in% "synonym"
    raw$taxonomic_status[plain] <- afd_usage_status(raw$canonical_name[plain], "synonym")
  }
  raw$canonical_name[marked] <- strip_afd_usage_markers(raw$canonical_name[marked])
  raw
}
