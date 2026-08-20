# Taxonomic datasets `load_taxonomic_resources()` knows how to fetch/reshape into taxonAlign's flat,
# `prepare_taxonomic_resources()`-ready column schema (canonical_name, scientific_name, taxon_rank,
# taxonomic_status, taxonomic_dataset, genus, taxon_ID, accepted_name_usage_ID). Extend this vector
# (and the `switch()` in load_taxonomic_resources() below) as further known sources are added.
taxonAlign_known_datasets <- c("AFD", "APC")

#' Load a known taxonomic reference dataset
#'
#' Fetches/reshapes a fixed set of *known* taxonomic datasets into taxonAlign's flat,
#' [prepare_taxonomic_resources()]-ready column schema -- complementing
#' [prepare_taxonomic_resources()] the same way [generate_GBIF_taxonomic_reference_list()] does for
#' GBIF, but for sources that aren't fetched fresh from a live API: `"AFD"` (the Australian Faunal
#' Directory) reads and reshapes a one-off raw CSV export; `"APC"` is a thin wrapper around
#' [APCalign::load_taxonomic_resources()] that flattens its several accepted/synonym/genus/family
#' pieces into one combined table.
#'
#' @param taxonomic_dataset Character vector naming one or more known datasets to load. Currently
#'  `"AFD"` and `"APC"`.
#' @param path For `"AFD"` only: path to the raw AFD CSV export. Defaults to the copy bundled with the
#'  package (`system.file("extdata", "AFD.csv", package = "taxonAlign")`). Ignored for `"APC"`.
#' @param refresh_cache For `"AFD"` only: logical; if `TRUE`, re-reshapes the raw file even if a cached
#'  copy exists. Defaults to `FALSE`. Ignored for `"APC"` (`APCalign::load_taxonomic_resources()`
#'  manages its own caching).
#' @param cache_dir For `"AFD"` only: directory the reshaped result is cached in. Defaults to
#'  `tools::R_user_dir("taxonAlign", "cache")`. Ignored for `"APC"`.
#' @param quiet Logical; suppress progress messages. Defaults to `FALSE`.
#' @param ... For `"APC"` only: forwarded to [APCalign::load_taxonomic_resources()] (e.g.
#'  `stable_or_current_data`, `version`). Ignored for `"AFD"`.
#'
#' @return A named list of flat tibbles, one per element of `taxonomic_dataset` (named by dataset),
#'  each already in the column shape [prepare_taxonomic_resources()] expects -- pass it (or a list
#'  combining it with your own tables) straight in, e.g.
#'  `prepare_taxonomic_resources(load_taxonomic_resources(c("AFD", "APC")))`.
#'
#' @export
load_taxonomic_resources <- function(taxonomic_dataset,
                                      path = NULL,
                                      refresh_cache = FALSE,
                                      cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                                      quiet = FALSE,
                                      ...) {

  unknown <- setdiff(taxonomic_dataset, taxonAlign_known_datasets)
  if (length(unknown) > 0) {
    stop(
      "Unknown `taxonomic_dataset`: ", paste(unknown, collapse = ", "), ". Known datasets: ",
      paste(taxonAlign_known_datasets, collapse = ", "), ".",
      call. = FALSE
    )
  }

  result <- purrr::map(
    taxonomic_dataset,
    function(ds) {
      switch(
        ds,
        AFD = load_AFD(path = path, refresh_cache = refresh_cache, cache_dir = cache_dir, quiet = quiet),
        APC = load_APC(quiet = quiet, ...)
      )
    }
  )
  stats::setNames(result, taxonomic_dataset)
}

# Reshapes the raw AFD CSV export (one row per species/subspecies, every higher rank spread across its
# own ALL-CAPS column, synonyms embedded as a single free-text semicolon-joined field mixing name +
# author + year) into taxonAlign's flat schema. Ports the *approach* of
# ausinvertraits.addons/scripts/02_AFD_checklist_clean.R (the current, canonical version of that
# repo's AFD-cleaning script), reimplemented directly against taxonAlign's target schema rather than
# translated line-by-line. Deliberately does not replicate that repo's AusInvertTraits-specific
# GRIIS/WoRMS invasive-and-marine-species filtering or "improper name" removal -- those are curation
# decisions about *which* taxa to include, not part of reshaping the data into taxonAlign's format.
#
# The reshaped result (which expands AFD's ~117k raw rows into several hundred thousand output rows,
# once every higher rank and every synonym gets its own row) is cached as a single .rds, keyed by the
# source file's own size/mtime rather than a time-based freshness window -- so swapping in an updated
# AFD.csv is picked up automatically, without the user needing to remember `refresh_cache = TRUE`.
#' @noRd
load_AFD <- function(path = NULL, refresh_cache = FALSE, cache_dir = tools::R_user_dir("taxonAlign", "cache"),
                      quiet = FALSE) {

  if (is.null(path)) {
    path <- system.file("extdata", "AFD.csv", package = "taxonAlign")
  }
  if (path == "" || !file.exists(path)) {
    stop(
      "Couldn't find the AFD reference file", if (nzchar(path)) paste0(" at \"", path, "\"") else "",
      ". Pass `path` to point at your copy of the raw AFD export.",
      call. = FALSE
    )
  }

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  file_info <- file.info(path)
  cache_key <- paste0(round(as.numeric(file_info$size)), "_", round(as.numeric(file_info$mtime)))
  cache_file <- file.path(cache_dir, paste0("AFD_", cache_key, ".rds"))

  if (!refresh_cache && file.exists(cache_file)) {
    if (!quiet) message("Using cached AFD reference (reshaped from \"", path, "\").")
    return(readRDS(cache_file))
  }

  if (!quiet) message("Reading and reshaping the AFD reference from \"", path, "\"...")

  # every column forced to character on the way in -- several (SUB_GENUS, SUB_SPECIES, and a handful
  # of the free-text/logical-looking columns this function doesn't use) are sparsely populated enough
  # that readr's sample-based type-guessing can mis-infer them as logical, which would break every
  # string operation below the moment a real value showed up
  afd <- readr::read_csv(
    path, col_types = readr::cols(.default = readr::col_character()), progress = FALSE
  )

  accepted <- afd_accepted_rows(afd)
  higher_ranks <- afd_higher_rank_rows(afd)
  synonyms <- afd_synonym_rows(afd)

  reshaped <- dplyr::bind_rows(accepted, higher_ranks, synonyms)

  saveRDS(reshaped, cache_file)
  reshaped
}

# Species/subspecies rows -- one row per raw AFD row, `taxon_rank` derived from whether SUB_SPECIES is
# filled. `taxon_ID`/`accepted_name_usage_ID` are both AFD's own stable CONCEPT_GUID (self-referential,
# matching the accepted-row convention prepare_taxonomic_resources() requires).
#' @noRd
afd_accepted_rows <- function(afd) {
  afd |>
    dplyr::transmute(
      canonical_name = FULL_NAME,
      scientific_name = COMPLETE_NAME,
      taxon_rank = ifelse(is.na(SUB_SPECIES) | SUB_SPECIES == "", "species", "subspecies"),
      taxonomic_status = "accepted",
      taxonomic_dataset = "AFD",
      genus = GENUS,
      taxon_ID = CONCEPT_GUID,
      accepted_name_usage_ID = CONCEPT_GUID
    )
}

# One synthesised row per distinct, non-blank value of every higher-rank column AFD provides (subgenus
# through phylum) -- mirrors 02_AFD_checklist_clean.R's own "one rank at a time, distinct() the column,
# blank out finer ranks" approach. None of these ranks have a natural stable ID in the raw data (AFD's
# CONCEPT_GUID only exists at species/subspecies level), so `taxon_ID`/`accepted_name_usage_ID` fall
# back to the rank's own name -- the same fallback 02_AFD_checklist_clean.R uses -- but namespaced with
# the rank itself (`"<rank>:<name>"`), not the bare name alone. A bare-name fallback collides across
# ranks whenever the same string is used at two different ranks -- which, for genus/subgenus, isn't a
# rare coincidence but the norm: by nomenclatural convention every genus that has been split into
# subgenera has a *nominotypical* subgenus sharing the genus's own name (e.g. genus "Agrilus" / its
# nominotypical subgenus "Agrilus"). Real AFD data hits this for 572 of 1725 distinct genus/subgenus
# pairs (~1180 higher-rank rows total, a handful more at family/order/subfamily/etc.). Without
# namespacing, `update_taxa()`'s `taxon_ID`-keyed lookup (`match()`, first-hit semantics) would
# silently resolve a subgenus-rank match to whichever colliding row happens to bind first (genus, since
# it's listed before subgenus in `resources`) -- collapsing a correct subgenus-rank resolution down to
# genus rank, discarding the subgenus, on every affected name. Confirmed and fixed after real user
# testing against the full AFD.csv surfaced exactly this: names that used to align to subgenus rank
# were coming out of `update_taxa()` at genus rank instead.
#
# `genus` is only populated for genus- and subgenus-rank rows (subgenus rows need their owning genus so
# prepare_taxonomic_resources() can build the bracketed `Genus (Subgenus)` convention automatically) --
# every other higher rank leaves `genus` NA, matching how e.g. family-rank rows work elsewhere in
# taxonAlign (GBIF/APC alike).
#' @noRd
afd_higher_rank_rows <- function(afd) {
  # broadest-to-narrowest order isn't load-bearing here (each rank's rows are independent), but keeping
  # it makes the source easier to scan against AFD's own column order
  plain_ranks <- c(
    PHYLUM = "phylum", SUBPHYLUM = "subphylum", SUPERCLASS = "superclass", CLASS = "class",
    SUBCLASS = "subclass", SUPERORDER = "superorder", ORDER = "order", SUBORDER = "suborder",
    SUPERFAMILY = "superfamily", FAMILY = "family", SUBFAMILY = "subfamily", SUPERTRIBE = "supertribe",
    TRIBE = "tribe", SUBTRIBE = "subtribe"
  )

  plain_rank_rows <- purrr::imap(plain_ranks, function(rank_label, column) {
    values <- afd[[column]]
    values <- values[!is.na(values) & values != ""]
    # AFD's own export renders family-and-above ranks (family, superfamily, order, ..., phylum)
    # ALL CAPS ("BUPRESTIDAE") but subfamily-and-below (subfamily, tribe, subtribe) in normal title
    # case ("Agrilinae") -- inconsistent within the same file. Normalising every rank here to
    # sentence case regardless is harmless on the already-correctly-cased ones and fixes the
    # ALL-CAPS ones, which would otherwise never exact-match a normally-cased input name.
    values <- unique(stringr::str_to_sentence(values))
    if (length(values) == 0) return(NULL)
    ids <- paste0(rank_label, ":", values)
    dplyr::tibble(
      canonical_name = values, scientific_name = values, taxon_rank = rank_label,
      taxonomic_status = "accepted", taxonomic_dataset = "AFD", genus = NA_character_,
      taxon_ID = ids, accepted_name_usage_ID = ids
    )
  })

  genus_rows <- afd |>
    dplyr::filter(!is.na(GENUS) & GENUS != "") |>
    dplyr::distinct(GENUS) |>
    dplyr::transmute(
      canonical_name = GENUS, scientific_name = GENUS, taxon_rank = "genus",
      taxonomic_status = "accepted", taxonomic_dataset = "AFD", genus = GENUS,
      taxon_ID = paste0("genus:", GENUS), accepted_name_usage_ID = paste0("genus:", GENUS)
    )

  subgenus_rows <- afd |>
    dplyr::filter(!is.na(SUB_GENUS) & SUB_GENUS != "") |>
    dplyr::distinct(GENUS, SUB_GENUS) |>
    dplyr::transmute(
      canonical_name = SUB_GENUS, scientific_name = SUB_GENUS, taxon_rank = "subgenus",
      taxonomic_status = "accepted", taxonomic_dataset = "AFD", genus = GENUS,
      taxon_ID = paste0("subgenus:", SUB_GENUS), accepted_name_usage_ID = paste0("subgenus:", SUB_GENUS)
    )

  dplyr::bind_rows(c(plain_rank_rows, list(genus_rows, subgenus_rows)))
}

# Synonym rows, parsed out of AFD's SYNONYMS field -- a single free-text string per accepted taxon,
# semicolon-joining every synonym as "Name [author], [year]" with no other separator between the
# taxonomic name and its authorship. Splits on "; ", drops entries identical to the taxon's own
# COMPLETE_NAME (self-referential noise present in the raw data), then strips authorship from what's
# left via strip_afd_authorship().
#
# `genus` is re-derived from each synonym's own (post-authorship-stripped) name via extract_genus() --
# not copied from the accepted row's GENUS -- since a synonym can sit under a different genus than the
# name it's now a synonym of (e.g. "Cisseis fossicollis" as a synonym of accepted "Aaaaba
# fossicollis"). `taxon_ID` is synthesised per synonym row (AFD has no ID at this level);
# `accepted_name_usage_ID` is the accepted row's own CONCEPT_GUID, pointing forward to the current name
# -- exactly what update_taxa() needs to resolve a matched synonym.
#' @noRd
afd_synonym_rows <- function(afd) {
  known_authors <- unique(afd$AUTHOR[!is.na(afd$AUTHOR) & afd$AUTHOR != ""])

  has_synonyms <- afd |> dplyr::filter(!is.na(SYNONYMS) & SYNONYMS != "")
  if (nrow(has_synonyms) == 0) {
    return(has_synonyms |>
      dplyr::transmute(
        canonical_name = character(0), scientific_name = character(0), taxon_rank = character(0),
        taxonomic_status = character(0), taxonomic_dataset = character(0), genus = character(0),
        taxon_ID = character(0), accepted_name_usage_ID = character(0)
      ))
  }

  # one taxon's SYNONYMS field becomes a list of synonym strings; expand into one row per synonym via
  # base recycling (rep()/unlist()) rather than adding tidyr just for unnest()
  split_synonyms <- stringr::str_split(has_synonyms$SYNONYMS, "; ")
  n_synonyms <- lengths(split_synonyms)

  synonym_entries <- has_synonyms[rep(seq_len(nrow(has_synonyms)), n_synonyms), c("CONCEPT_GUID", "COMPLETE_NAME", "FULL_NAME")]
  synonym_entries$synonym <- stringr::str_trim(unlist(split_synonyms))

  synonym_entries <- synonym_entries |>
    dplyr::filter(synonym != "" & synonym != COMPLETE_NAME & synonym != FULL_NAME) |>
    dplyr::mutate(
      canonical_name = strip_afd_authorship(synonym, known_authors),
      taxon_ID = paste0(CONCEPT_GUID, "_syn", dplyr::row_number())
    )

  synonym_entries |>
    dplyr::transmute(
      canonical_name = canonical_name,
      scientific_name = synonym,
      taxon_rank = "species",
      taxonomic_status = "synonym",
      taxonomic_dataset = "AFD",
      genus = extract_genus(canonical_name),
      taxon_ID = taxon_ID,
      accepted_name_usage_ID = CONCEPT_GUID
    )
}

# Strips a trailing "<author>, <year>" (or "<author> <year>") from a free-text synonym string, e.g.
# "Cisseis fossicollis Kerremans, 1903" -> "Cisseis fossicollis". `known_authors` is the AFD file's own
# AUTHOR column (a real, closed vocabulary of the taxonomists whose names appear in it) -- used as a
# de-facto authorship dictionary, since there's no other separator in the raw SYNONYMS field between
# the taxonomic name and its authorship. Sorted longest-first so a longer author string (e.g.
# "Kerremans & Boucher") is matched before a shorter one that happens to be its prefix (e.g.
# "Kerremans"). A generic trailing-year fallback (any capitalised author-looking token(s) before a
# 4-digit year) catches entries whose author isn't in the dictionary for some reason -- if neither
# matches, the entry is returned unchanged (including its authorship) rather than guessed at further.
#' @noRd
strip_afd_authorship <- function(synonym_strings, known_authors) {
  known_authors <- unique(known_authors[!is.na(known_authors) & known_authors != ""])
  known_authors <- known_authors[order(-nchar(known_authors))]
  # sequential fixed=TRUE substitutions rather than a single regex character class -- simpler and
  # avoids escaping edge cases entirely (fixed=TRUE treats both pattern and replacement as literal
  # strings, so no regex-metacharacter interplay to get wrong); backslash must be escaped first, or the
  # backslashes introduced by escaping every other character would themselves get double-escaped
  escape_regex <- function(x) {
    for (ch in c("\\", ".", "^", "$", "|", "(", ")", "[", "]", "{", "}", "*", "+", "?")) {
      x <- gsub(ch, paste0("\\", ch), x, fixed = TRUE)
    }
    x
  }

  out <- synonym_strings
  if (length(known_authors) > 0) {
    author_pattern <- paste0("(", paste(escape_regex(known_authors), collapse = "|"), ")")
    dictionary_pattern <- paste0("\\s+", author_pattern, ",?\\s*\\d{4}\\s*$")
    out <- stringr::str_remove(out, dictionary_pattern)
  }

  # generic fallback for anything the dictionary pass didn't change: one or more capitalised
  # author-name tokens (optionally joined by "&"/"and"/"in"/","), then an optional comma and a year
  generic_pattern <- "\\s+[A-Z][\\p{L}.\\-']*(?:,?\\s*(?:&|and|in)\\s+[A-Z][\\p{L}.\\-']*)*,?\\s*\\d{4}\\s*$"
  unchanged <- out == synonym_strings
  out[unchanged] <- stringr::str_remove(out[unchanged], generic_pattern)

  stringr::str_trim(out)
}

# Thin wrapper around APCalign::load_taxonomic_resources() -- flattens its several accepted/synonym/
# genus/family pieces into one combined, taxonAlign-shaped flat tibble. `family_accepted` is the one
# piece missing a `taxonomic_dataset` column (unlike every other piece here), backfilled with "APC" to
# match. No caching here: APCalign::load_taxonomic_resources() already caches internally.
#' @noRd
load_APC <- function(quiet = FALSE, ...) {
  APC <- APCalign::load_taxonomic_resources(quiet = quiet, ...)
  dplyr::bind_rows(
    APC$APC_accepted, APC$APC_synonyms,
    APC$genera_accepted, APC$genera_synonym,
    APC$family_accepted |> dplyr::mutate(taxonomic_dataset = "APC"),
    APC$family_synonym
  )
}
