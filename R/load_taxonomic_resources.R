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
  # AFD's 2026 CSV export renamed FULL_NAME to VALID_NAME (same content: the bare canonical name);
  # every other column this function reads is unchanged between the two export versions, so the old
  # and new files share one code path
  if (!"FULL_NAME" %in% names(afd) && "VALID_NAME" %in% names(afd)) {
    afd <- dplyr::rename(afd, FULL_NAME = VALID_NAME)
  }
  missing_cols <- setdiff(
    c("FULL_NAME", "COMPLETE_NAME", "GENUS", "SUB_GENUS", "SUB_SPECIES", "AUTHOR", "SYNONYMS", "CONCEPT_GUID"),
    names(afd)
  )
  if (length(missing_cols) > 0) {
    stop(
      "The AFD file at \"", path, "\" is missing expected column(s): ", paste(missing_cols, collapse = ", "),
      ". Is it an AFD CSV export?", call. = FALSE
    )
  }

  # a handful of names in the 2026 export carry stray control characters/tabs (e.g. "evanialis\u0010",
  # "Prosocratus \t carolinae") that would otherwise never exact-match a clean query
  name_cols <- intersect(c("FULL_NAME", "COMPLETE_NAME", "GENUS", "SUB_GENUS", "SPECIES", "SUB_SPECIES", "SYNONYMS", "CHANGED_COMBINATION_NAMES"), names(afd))
  afd[name_cols] <- lapply(afd[name_cols], function(x) stringr::str_squish(gsub("[[:cntrl:]]", " ", x)))
  # quote marks flagging a doubtful generic placement ("'Ochlerotatus' quasirubithorax") are kept in
  # COMPLETE_NAME but not in the name matched against -- the same treatment synonyms get
  afd$FULL_NAME <- strip_name_quotes(afd$FULL_NAME)
  # and trailing punctuation left on a name ("Wallagootacoris tasmaniensis,")
  afd$FULL_NAME <- stringr::str_remove(afd$FULL_NAME, "[,;]+$")

  # the 2026 export adds two kinds of "Unplaced" row, both flagged here:
  #  - "Unplaced Synonym(s)" holders (SPECIES or SUB_SPECIES = "Unplaced", 79 rows): names placed within
  #    a genus/species but not assigned to any taxon -- not a real taxon at all
  #  - species whose genus is unplaced (GENUS = "Unplaced", VALID_NAME e.g. "Unplaced vetula", 303
  #    rows): a real species, but "Unplaced vetula" isn't a name anyone would write or that could be
  #    usefully matched, and there's no current binomial to update anything to
  # Neither becomes an accepted row. Their SYNONYMS (for the second kind, almost always the original
  # combination, e.g. "Tinea vetula Meyrick, 1893") are kept (see afd_synonym_rows()) as
  # self-referential "unplaced" names, mirroring the NSL export's own "unplaced" status
  afd$UNPLACED <- grepl("^Unplaced", afd$FULL_NAME) | afd$SPECIES %in% "Unplaced" | afd$SUB_SPECIES %in% "Unplaced"

  accepted <- afd_accepted_rows(afd[!afd$UNPLACED, ])
  higher_ranks <- afd_higher_rank_rows(afd)
  # SYNONYMS holds synonyms proper; CHANGED_COMBINATION_NAMES holds other combinations of the same
  # species name (e.g. "Costalynia cardinalis" under accepted "Rissoina cardinalis"), not repeated in
  # SYNONYMS -- ~15k entries in the 2026 export. Labelled "Generic combination", matching the AFD's own
  # NSL export's status for the same records. A name listed in both columns for the same taxon is kept
  # once, as a synonym.
  synonyms <- afd_synonym_rows(afd)
  if ("CHANGED_COMBINATION_NAMES" %in% names(afd)) {
    combinations <- afd_synonym_rows(afd, "CHANGED_COMBINATION_NAMES", "Generic combination", "_comb")
    synonyms <- dplyr::bind_rows(synonyms, combinations) |>
      dplyr::distinct(canonical_name, accepted_name_usage_ID, .keep_all = TRUE)
  }

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
# through phylum). None of these ranks have a natural stable ID in the raw data (AFD's CONCEPT_GUID
# only exists at species/subspecies level), so `taxon_ID`/`accepted_name_usage_ID` fall back to the
# rank's own name, namespaced with the rank itself (`"<rank>:<name>"`), not the bare name alone -- a
# bare-name fallback would collide across ranks whenever the same string is used at two different
# ranks, which for genus/subgenus isn't a rare coincidence but the norm (every genus split into
# subgenera has a *nominotypical* subgenus sharing the genus's own name). Without namespacing,
# `update_taxa()`'s `taxon_ID`-keyed lookup (`match()`, first-hit semantics) would silently resolve a
# subgenus-rank match to whichever colliding row happens to bind first (genus, since it's listed before
# subgenus in `resources`) -- collapsing a correct subgenus-rank resolution down to genus rank.
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
    # the 2026 export uses "Unplaced"/"Unplaced to Family"/"Incertae sedis" as placeholders in the
    # hierarchy columns
    # for a taxon not yet assigned at that rank -- not a real taxon name, so never a row of its own
    values <- values[!is.na(values) & values != "" & !grepl("^(Unplaced|Incertae sedis)", values, ignore.case = TRUE)]
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
    dplyr::filter(!is.na(GENUS) & GENUS != "" & !grepl("^Unplaced", GENUS)) |>
    dplyr::distinct(GENUS) |>
    dplyr::transmute(
      canonical_name = GENUS, scientific_name = GENUS, taxon_rank = "genus",
      taxonomic_status = "accepted", taxonomic_dataset = "AFD", genus = GENUS,
      taxon_ID = paste0("genus:", GENUS), accepted_name_usage_ID = paste0("genus:", GENUS)
    )

  subgenus_rows <- afd |>
    dplyr::filter(!is.na(SUB_GENUS) & SUB_GENUS != "" & !grepl("^Unplaced", GENUS) & !grepl("^Unplaced", SUB_GENUS)) |>
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
afd_synonym_rows <- function(afd, column = "SYNONYMS", status = "synonym", id_suffix = "_syn") {
  known_authors <- unique(afd$AUTHOR[!is.na(afd$AUTHOR) & afd$AUTHOR != ""])

  afd$SYNONYMS <- afd[[column]]
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
  split_synonyms <- lapply(stringr::str_split(has_synonyms$SYNONYMS, "; "), rejoin_afd_synonym_fragments)
  n_synonyms <- lengths(split_synonyms)

  if (!"UNPLACED" %in% names(has_synonyms)) has_synonyms$UNPLACED <- FALSE
  synonym_entries <- has_synonyms[rep(seq_len(nrow(has_synonyms)), n_synonyms), c("CONCEPT_GUID", "COMPLETE_NAME", "FULL_NAME", "UNPLACED")]
  synonym_entries$synonym <- stringr::str_trim(unlist(split_synonyms))

  synonym_entries <- synonym_entries |>
    dplyr::filter(synonym != "" & synonym != COMPLETE_NAME & synonym != FULL_NAME) |>
    dplyr::mutate(
      canonical_name = strip_afd_authorship(synonym, known_authors),
      taxon_ID = paste0(CONCEPT_GUID, id_suffix, dplyr::row_number())
    ) |>
    # a self-reference written with different authorship formatting than COMPLETE_NAME (or a
    # same-name homonym), or just without the accepted name's subgenus ("Clivina tenuis" listed under
    # "Clivina (Clivina) tenuis", ~3.3k in the 2026 export), would otherwise become a "synonym" of
    # itself -- adds nothing a match on the accepted row doesn't already give
    dplyr::filter(canonical_name != FULL_NAME & canonical_name != strip_subgenus_from_name(FULL_NAME)) |>
    # an entry with no genus left once cleaned (e.g. "(Ciscadra) (G. Leraut, 2021)") isn't a name
    dplyr::filter(grepl("^\\p{L}", canonical_name, perl = TRUE))

  synonym_entries |>
    dplyr::transmute(
      canonical_name = canonical_name,
      scientific_name = synonym,
      # rank from the name itself: three or more words (once any bracketed subgenus is set aside) is a
      # subspecies. Labelling a trinomial synonym "species" made prepare_taxonomic_resources() give it
      # a two-word binomial key, so e.g. the subspecies synonym "Pardalotus striatus kingi" claimed the
      # binomial "Pardalotus striatus" and plain-binomial queries resolved to the subspecies.
      taxon_rank = ifelse(
        stringr::str_count(strip_subgenus_from_name(canonical_name), "\\S+") >= 3, "subspecies", "species"
      ),
      # a name held under an "Unplaced Synonym(s)" pseudo-row has no real taxon to resolve forward to,
      # so it's self-referential, with its own status, rather than a "synonym" of the pseudo-row
      # misapplied/part usages marked in the free text get their own status (see afd_usage_status())
      taxonomic_status = ifelse(UNPLACED, "unplaced", afd_usage_status(synonym, status)),
      taxonomic_dataset = "AFD",
      genus = extract_genus(canonical_name),
      taxon_ID = taxon_ID,
      accepted_name_usage_ID = ifelse(UNPLACED, taxon_ID, CONCEPT_GUID)
    )
}

# Removes editorial annotations the AFD CSV writes into otherwise ordinary names in its SYNONYMS/
# CHANGED_COMBINATION_NAMES free text, which its NSL export has already cleaned off the same names:
# "[sic]"/"[sic!]" ("Iodis [sic] iosticta"), a leading "?"/"(?)" query mark ("? Goniada peruana"), a
# whole name in square brackets ("[Spongia clathrus]"), a quoted manuscript author at the end
# ("Conus ponderosa 'Beck'", 'Mytilus tortus "Dunker"') and stray quote marks ("Hypomecis” conspersa").
#' @noRd
clean_afd_name_annotations <- function(x) {
  x <- stringr::str_remove_all(x, "<[^>]*>")
  x <- stringr::str_remove_all(x, stringr::regex("\\s*[\\[(]sic!?[\\])]", ignore_case = TRUE))
  x <- strip_afd_usage_markers(x)
  # uncertainty marks anywhere: "? Goniada peruana", "Acanthoglossa? setigera", "Eristalis ?aenescens",
  # "Megascolides(?) pygmaeus", "Rissoa (Ceratia ?) subtruncata", "Kimosina (? Kimosina) popularis"
  x <- stringr::str_remove_all(x, "\\(\\s*\\?\\s*\\)")
  x <- stringr::str_remove_all(x, "\\?")
  x <- stringr::str_replace_all(x, "\\(\\s+", "(")
  x <- stringr::str_replace_all(x, "\\s+\\)", ")")
  x <- stringr::str_remove_all(x, "\\(\\)")
  # a doubled closing bracket only where brackets don't balance ("Mangilia (Glyphostoma)) jousseaumei"),
  # not a genuinely nested one ("Pyramidella (Chrysallida (section Styloptygma)) typica")
  unbalanced <- stringr::str_count(x, "\\)") > stringr::str_count(x, "\\(")
  x[unbalanced] <- stringr::str_replace_all(x[unbalanced], "\\)\\)", ")")
  # authorship cut off inside square brackets ("Tinea lactella [Denis & Schiffermüller], 1775" arrives as
  # "Tinea lactella [Denis"), then square brackets around part of a name, kept as the NSL format keeps
  # them: "H[yla] jacksonii" -> "Hyla jacksonii", "[Spongia clathrus]" -> "Spongia clathrus"
  x <- stringr::str_remove(x, "\\s+\\[\\p{Lu}[^\\]]*$")
  x <- stringr::str_remove_all(x, "[\\[\\]]")
  # authorship with the year outside its bracket, "(Johnston & Simpson), 1939" -> "(Johnston & Simpson, 1939)"
  x <- stringr::str_replace(x, "\\s+\\(([^()]*)\\),\\s*(\\d{4})\\s*$", " (\\1, \\2)")
  x <- stringr::str_remove(x, "\\s+['\"\u2018\u2019\u201c\u201d][^'\"\u2018\u2019\u201c\u201d]+['\"\u2018\u2019\u201c\u201d]\\s*$")
  x <- strip_name_quotes(x)
  stringr::str_squish(x)
}

# Removes quote marks around a word or name ("'Ochlerotatus' notoscriptus", "\"Ziba\" flammea",
# "'Callidium signiferum'") -- both AFD formats use them to flag a doubtful generic placement, which the
# scientific name keeps -- but not an apostrophe inside a word ("Allotria d'arci", "Geoplana m'mahoni").
#' @noRd
strip_name_quotes <- function(x) {
  x <- stringr::str_remove_all(x, "(?<!\\p{L})['\"\u2018\u2019\u201c\u201d]|['\"\u2018\u2019\u201c\u201d](?!\\p{L})")
  stringr::str_squish(x)
}

# The AFD format marks misapplied and part usages inside its SYNONYMS free text -- "sensu Author",
# "auct."/"auctt."/"auctorum", "non Author", "(part)"/"[part]"/"(part.)"/"[pars]" -- which the NSL format
# drops, labelling the name plain "synonym". afd_usage_status() reads them (they matter for choosing
# between a name's several accepted names); this removes them, and anything after "sensu"/"non", from
# the name itself.
#' @noRd
strip_afd_usage_markers <- function(x) {
  x <- stringr::str_remove_all(x, stringr::regex("\\s*[\\[(]\\s*(part|pars)\\.?\\s*[\\])]", ignore_case = TRUE))
  x <- stringr::str_remove(x, "\\s+(sensu|non|nec)\\b.*$")
  x <- stringr::str_remove_all(x, "\\s*\\[?\\b(auctt?\\.?|auctorum)\\]?(?=\\s|,|$)")
  stringr::str_squish(stringr::str_remove(x, "\\s*,\\s*$"))
}

# taxonomic_status implied by the AFD format's usage markers (see strip_afd_usage_markers()), or `status`
# unchanged when there are none.
#' @noRd
afd_usage_status <- function(x, status) {
  misapplied <- grepl("\\s(sensu|non|nec)\\b|\\b(auctt?\\.?|auctorum)(?=[\\s,\\]]|$)", x, perl = TRUE)
  part <- grepl("(?i)[\\[(]\\s*(part|pars)\\.?\\s*[\\])]", x, perl = TRUE)
  dplyr::case_when(
    misapplied & part ~ "pro parte misapplied",
    misapplied ~ "misapplied",
    part ~ "pro parte synonym",
    TRUE ~ status
  )
}

# Re-attaches an orphaned "<author>, <year>" fragment to the synonym entry before it. AFD writes a
# subsequent usage (typically a misspelling) with a "; " between the name and its citation, e.g.
# "Phalaena inquinalis; Swinhoe, 1892", so splitting the SYNONYMS field on "; " would otherwise turn
# "Swinhoe, 1892" into a bogus synonym of its own. A fragment is recognised conservatively: no word
# starting lowercase or with "(" (so no epithet), ends in a year, *and* the preceding entry has no
# year of its own -- old names with capitalised epithets ("Ixodes Moreliae Koch, 1867") fail the last
# test and are left alone. Seen ~176 times in the 2026 CSV export, 6 times in the older one.
#' @noRd
rejoin_afd_synonym_fragments <- function(entries) {
  if (length(entries) < 2) return(entries)
  # a leading lowercase name particle ("van Eecke, 1925") is part of the author, not an epithet
  without_particle <- sub("^((van|von|de|da|di|du|der|den|del|della|la|le|ter)\\s+)+", "", entries)
  # ... and so are connectors between authors ("Haines in Dowling & Haines, 1963", "Smith et al., 1990")
  without_particle <- gsub("\\s(in|et|and|al\\.)(?=\\s)", " ", without_particle, perl = TRUE)
  is_fragment <- !grepl("(^|\\s)[a-z(]", without_particle) & grepl("\\d{4}\\)?\\s*$", entries) &
    c(FALSE, !grepl("\\d{4}", entries[-length(entries)]))
  # a misapplication marker split off the same way ("Paracharactis vestianella; auctt., ;") belongs to
  # the name before it
  is_fragment <- is_fragment | (grepl("^(auctt?\\.?|auctorum|sensu|non|nec)\\b", entries) & seq_along(entries) > 1)
  for (i in rev(which(is_fragment))) {
    entries[i - 1] <- paste(entries[i - 1], entries[i])
  }
  entries[!is_fragment]
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
  synonym_strings <- clean_afd_name_annotations(synonym_strings)
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
    # optionally wrapped in parentheses -- a changed-combination's original authorship, e.g.
    # "Otobothrium curtum (Linton, 1909)", common in AFD's 2026 export
    dictionary_pattern <- paste0("\\s+\\(?", author_pattern, ",?\\s*\\d{4}\\)?\\s*$")
    out <- stringr::str_remove(out, dictionary_pattern)
  }

  # generic fallback for anything the dictionary pass didn't change: one or more capitalised
  # author-name tokens (optionally joined by "&"/"and"/"in"/",", optionally ending "et al."), then an
  # optional comma and a year, the whole thing optionally parenthesised
  generic_pattern <- "\\s+\\(?[A-Z][\\p{L}.\\-']*(?:,?\\s*(?:&|and|in)\\s+[A-Z][\\p{L}.\\-']*)*(?:\\s+et al\\.)?,?\\s*\\d{4}\\)?\\s*$"
  unchanged <- out == synonym_strings
  out[unchanged] <- stringr::str_remove(out[unchanged], generic_pattern)

  tidy_afd_authorship_debris(stringr::str_trim(out))
}

# Cleans up authorship fragments strip_afd_authorship()'s dictionary pass leaves behind when only the
# *last* author of a multi-author/particle-prefixed citation is in the AUTHOR dictionary -- e.g.
# "Gymnothorax griffini Whitley & Hutchins, 1988" -> "Gymnothorax griffini Whitley &", or
# "Platydemus manokwari de Beauchamp, 1962" -> "Platydemus manokwari de". Found in ~2k of ~103k
# synonyms in AFD's 2026 CSV export. Three conservative steps:
#  1. truncate at the first capitalised token following a lowercase one -- after the first (lowercase)
#     epithet, a zoological name only ever continues with lowercase epithets, "(Subgenus)" brackets or
#     lowercase rank markers, never a capitalised word; old names with a capitalised *second* word
#     ("Ixodes Moreliae") have no preceding lowercase token, so are left alone
#  2. strip a residual trailing (optionally bracketed) year plus the token before it (a lowercase-typed
#     author, e.g. "Iphiaulax morleyi froggatt, 1916")
#  3. strip trailing connectors/name particles ("&", "in", "de", "van der", "et al.", ...) and commas
#' @noRd
tidy_afd_authorship_debris <- function(x) {
  # each step can expose debris for an earlier one (e.g. removing "Madhavi, Narasimhulu &" leaves
  # "(Bilqees, 1971)" trailing), so repeat until nothing changes
  repeat {
    tidied <- tidy_afd_authorship_debris_once(x)
    if (identical(tidied, x)) return(x)
    x <- tidied
  }
}

#' @noRd
tidy_afd_authorship_debris_once <- function(x) {
  # malformed parenthesised authorship left at the end of a name of two or more words: empty
  # ("Coccus citri (, )"), year missing ("(Milne Edwards, )"), reversed ("(1876, Bergh)"), doubled
  # closing bracket ("(Turner, 1908))"), bracketed year ("(Guenée, [1858])") -- any trailing "(...)"
  # holding a comma, digit or capital letter, or nothing at all -- and authorship cut off before its
  # closing bracket ("Anatoma turbinata (Adams", "Chlamys challengeri (E.A")
  two_words <- "^(\\S+\\s+\\S+.*?)"
  x <- stringr::str_replace(x, paste0(two_words, "\\s*\\((?:[^()]*[,\\d\\p{Lu}][^()]*|\\s*)\\)+\\s*$"), "\\1")
  x <- stringr::str_replace(x, paste0(two_words, "\\s+\\([^()]*$"), "\\1")
  # (an author may also start "d'"/"l'", "Myllita deshayesi d'Orbigny", or follow a numbered informal
  # name, "Phyllodistomum sp. 2 Cutmore, Miller, ...")
  x <- stringr::str_remove(x, "(?<=\\s[a-z0-9][^\\s]{0,100})\\s+(?:\\p{Lu}|[dl]['’]\\p{Lu}).*$")
  x <- stringr::str_remove(x, "(\\s+[^\\s(]+,?)?\\s*\\[?\\d{4}\\]?,?\\s*$")
  particles <- "(&|and|in|e|et|et al\\.?|y|de|da|di|du|des|del|della|van|von|der|den|la|le|ter|of)"
  repeat {
    tidied <- stringr::str_remove(x, paste0("(\\s+", particles, "|\\s*[,&])\\s*$"))
    if (identical(tidied, x)) break
    x <- tidied
  }
  stringr::str_trim(x)
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
