# match_taxa() follows APCalign's own match_taxa() (traitecoevo/APCalign, R/match_taxa.R) block for
# block, in the same order, with the same accepted-before-synonym precedence at every step, generalised
# from APC/APNI's fixed tables to any combination of references and any taxonomic rank:
#
#   APCalign                                taxonAlign
#   APC_accepted / APC_synonyms             resources$species$accepted / $synonym (every dataset, in
#                                           priority order)
#   genera_accepted / genera_synonym        resources$genus, split by taxonomic_status
#   family_accepted / family_synonym        resources$family -- and every other higher rank present
#   APNI (searched late, its own blocks)    no separate concept: a names-only dataset is listed after
#                                           the others and searched in the same blocks
#
# Kept to APCalign's sequence after a tester's run (taxonAlign.dataprep#1, 2026-11-14) showed the
# earlier port had drifted: blocks out of order (hybrid/affinis before fuzzy species matching), blocks
# missing (imprecise fuzzy 07, fuzzy trinomial 09c/d, fuzzy binomial 10c/d), and accepted and synonym
# genera fuzzy-matched together (so a misspelt name could land on a synonym genus when an accepted one
# was the APCalign answer). tests/testthat/test-apc_equivalence.R now runs APCalign's own benchmark
# names (tests/testthat/benchmarks/) through both packages, column by column.
#
# taxonAlign's own additions, in the positions they need:
#   match_02a/02x/02y  "Genus (Subgenus) sp.", "Genus subg. Subgenus", bare "Genus (Subgenus)" --
#                      quarantined before species-level matching can read the subgenus as an epithet
#   match_02z          opt-in English vernacular endings ("Coccinellid" -> Coccinellidae)
#   match_06a/06b      an "aff."/"cf." name that is exactly a real listed name (issue #16)
#   match_11a/11b      exact matches ignoring a bracketed word ("Genus (Subgenus) species")
#   match_12a          "Genus (Subgenus) <anything>" to subgenus rank
# and higher-rank fuzzy matching chooses the closest name across *all* ranks present (ties go to the
# broader rank, issue #12) rather than genus, then family only.

# ---- shared helpers ---------------------------------------------------------------------------------

# Per-call state apply_match() reads: the dataset versions of the `resources` being matched against.
match_state <- new.env(parent = emptyenv())

# Records a match for the rows of `taxa$tocheck` selected by the logical `i`, against rows `ii` of
# `table` (one per selected row; `table = NULL` records "checked, but nothing aligned"), then moves them
# to `taxa$checked`. `aligned_reason` is completed with the matched dataset and the date.
apply_match <- function(taxa, i, table, ii, aligned_name, aligned_reason, alignment_code,
                        taxon_rank = NULL, chars_changed = 0L, pb = NULL) {
  i[is.na(i)] <- FALSE
  if (!any(i)) return(taxa)
  n <- sum(i)
  from_table <- function(col) {
    if (is.null(table) || !col %in% names(table)) return(rep(NA_character_, n))
    as.character(table[[col]][ii])
  }
  dataset <- from_table("taxonomic_dataset")
  taxa$tocheck$taxonomic_dataset[i] <- dataset
  taxa$tocheck$taxon_rank[i] <- if (is.null(taxon_rank)) from_table("taxon_rank") else taxon_rank
  taxa$tocheck$taxonomic_status[i] <- from_table("taxonomic_status")
  taxa$tocheck$taxon_ID[i] <- from_table("taxon_ID")
  taxa$tocheck$accepted_name_usage_ID[i] <- from_table("accepted_name_usage_ID")
  taxa$tocheck$aligned_name[i] <- aligned_name
  # the data version, not the run date (APCalign #281): the same names against the same data give the
  # same output. Nothing when the version isn't known.
  version <- unname(match_state$versions[dataset])
  taxa$tocheck$aligned_reason[i] <- paste0(
    aligned_reason, ifelse(is.na(dataset), "", paste0(" in ", dataset)),
    ifelse(is.na(version), "", paste0(" (", version, ")"))
  )
  taxa$tocheck$chars_changed[i] <- as.integer(chars_changed)
  taxa$tocheck$alignment_code[i] <- alignment_code
  taxa$tocheck$known[i] <- TRUE
  taxa$tocheck$checked[i] <- TRUE
  redistribute_progress(taxa, pb)
}

# The commonest block: rows whose `key` column exactly matches `table[[name_type]]` take that row's
# name. `only` restricts which rows may match; `distance_from` (for a fuzzy block, where `key` holds the
# fuzzy result) is the query column the distance in `chars_changed` is measured from.
match_reference_name <- function(taxa, table, key, name_type, aligned_reason, alignment_code,
                                 only = TRUE, distance_from = NULL, pb = NULL) {
  if (is.null(table) || nrow(table) == 0 || nrow(taxa$tocheck) == 0) return(taxa)
  query <- taxa$tocheck[[key]]
  i <- only & !is.na(query) & query %in% table[[name_type]]
  i[is.na(i)] <- FALSE
  ii <- match(query[i], table[[name_type]])
  chars <- if (is.null(distance_from)) 0L else
    stringdist::stringdist(taxa$tocheck[[distance_from]][i], query[i], method = "dl")
  apply_match(taxa, i, table, ii, aligned_name = table$canonical_name[ii],
              aligned_reason = aligned_reason, alignment_code = alignment_code,
              chars_changed = chars, pb = pb)
}

# "Acacia sp.", or "Acacia sp. [Royal NP]" with an identifier: for a name that already ended in "sp.".
genus_sp_name <- function(taxa, i, stem) {
  identifier <- taxa$tocheck$identifier_string[i]
  paste0(stem, " sp.", ifelse(is.na(identifier), "", identifier))
}

# "Acacia sp. [Acacia aff. dealbata; Royal NP]", or with marker = " x", "Acacia x [...]": for a name
# with more below the rank it aligned to, which is kept in brackets. `bare` (see ?match_taxa's
# include_bracketed_info) gives just the stem instead.
higher_rank_name <- function(taxa, i, stem, marker = " sp.", bare = FALSE) {
  identifier <- taxa$tocheck$identifier_string2[i]
  out <- paste0(stem, marker, " [", taxa$tocheck$cleaned_name[i],
                ifelse(is.na(identifier), "", identifier), "]")
  bare <- rep_len(bare, length(out))
  out[bare] <- stem[bare]
  out
}

# The rows of a higher-rank table that first-word matching may use: one-word names only (a hybrid
# genus's "x" aside). A multi-word name filed at an odd rank (APNI's "[unranked]" cultivar names, say)
# used to be matched by its first word, aligning "Banksia ..." to "Banksia 'Allisoniana'".
rank_rows <- function(resources, rank, status = c("any", "accepted", "synonym")) {
  status <- match.arg(status)
  tbl <- resources[[rank]]
  if (is.null(tbl) || nrow(tbl) == 0) return(NULL)
  one_word <- !grepl("\\s", sub("^[xX\u00d7]\\s+", "", tbl$canonical_name))
  keep <- one_word & switch(status,
    any = TRUE,
    accepted = tbl$taxonomic_status %in% "accepted",
    synonym = !tbl$taxonomic_status %in% "accepted"
  )
  tbl[keep, ]
}

# The closest fuzzy match for each of `words` among the names at `ranks` with the given status: the
# smallest edit distance across all ranks, a tie going to the rank listed first (`ranks` is
# broadest-first, so the broader rank -- issue #12: "Coccinellid" means Coccinellidae, not a
# similarly spelt genus -- except that genus comes before subgenus). Returns the matched name, its rank
# and its row in that rank's table.
fuzzy_higher_rank <- function(words, resources, ranks, status, fuzzy_match_genera) {
  n <- length(words)
  out <- list(name = rep(NA_character_, n), rank = rep(NA_character_, n), row = rep(NA_integer_, n))
  best <- rep(Inf, n)
  todo <- !is.na(words)
  if (!any(todo)) return(out)
  for (r in ranks) {
    tbl <- rank_rows(resources, r, status)
    if (is.null(tbl) || nrow(tbl) == 0) next
    hit <- rep(NA_character_, n)
    hit[todo] <- fuzzy_match_genera(words[todo], tbl$word_one_stripped)
    d <- ifelse(is.na(hit), Inf, stringdist::stringdist(words, hit, method = "dl"))
    better <- d < best
    out$name[better] <- hit[better]
    out$rank[better] <- r
    out$row[better] <- match(hit[better], tbl$word_one_stripped)
    best[better] <- d[better]
  }
  out
}

# Hybrid, intergrade, indecision and affinis names, and the subgenus-form fallbacks, can only be aligned
# to genus: an exact genus (accepted or synonym), then a fuzzy accepted genus, then a fuzzy synonym genus
# (APCalign's 0Xa-0Xc), then "unresolved" (checked, nothing aligned, so the name can't fall through to
# an inappropriate later block). `detect_fn` takes `cleaned_name`; it's re-run after every step, since
# `taxa$tocheck` shrinks.
match_special_case_to_genus <- function(taxa, resources, detect_fn, bracket_sep, reason_text,
                                        alignment_code_exact, alignment_code_fuzzy,
                                        alignment_code_unresolved, alignment_code_no_resource,
                                        fuzzy_match_genera, pb = NULL) {
  marker <- sub(" \\[$", "", bracket_sep)
  genera <- rank_rows(resources, "genus")
  if (is.null(genera)) {
    i <- detect_fn(taxa$tocheck$cleaned_name)
    return(apply_match(taxa, i, NULL, NULL, NA_character_,
                       paste(reason_text, "No genus-rank reference is available to check it against"),
                       alignment_code_no_resource, chars_changed = NA_integer_, pb = pb))
  }

  i <- detect_fn(taxa$tocheck$cleaned_name) & taxa$tocheck$word_one_stripped %in% genera$word_one_stripped
  ii <- match(taxa$tocheck$word_one_stripped[i], genera$word_one_stripped)
  taxa <- apply_match(taxa, i, genera, ii,
                      higher_rank_name(taxa, i, genera$word_one_stripped[ii], marker),
                      paste(reason_text, "Exact match to a genus"), alignment_code_exact,
                      taxon_rank = "genus", pb = pb)
  if (nrow(taxa$tocheck) == 0) return(taxa)

  for (status in c("accepted", "synonym")) {
    tbl <- rank_rows(resources, "genus", status)
    if (is.null(tbl) || nrow(tbl) == 0) next
    detected <- detect_fn(taxa$tocheck$cleaned_name)
    hit <- rep(NA_character_, nrow(taxa$tocheck))
    if (any(detected)) hit[detected] <- fuzzy_match_genera(taxa$tocheck$word_one_stripped[detected], tbl$word_one_stripped)
    i <- detected & !is.na(hit)
    ii <- match(hit[i], tbl$word_one_stripped)
    taxa <- apply_match(taxa, i, tbl, ii,
                        higher_rank_name(taxa, i, tbl$word_one_stripped[ii], marker),
                        paste0(reason_text, " Fuzzy match to a", if (status == "accepted") "n accepted" else " synonymous", " genus"),
                        alignment_code_fuzzy, taxon_rank = "genus",
                        chars_changed = stringdist::stringdist(taxa$tocheck$word_one_stripped[i], hit[i], method = "dl"),
                        pb = pb)
    if (nrow(taxa$tocheck) == 0) return(taxa)
  }

  i <- detect_fn(taxa$tocheck$cleaned_name)
  apply_match(taxa, i, NULL, NULL, NA_character_,
              paste(reason_text, "Exact and fuzzy matches failed to resolve a genus"),
              alignment_code_unresolved, chars_changed = NA_integer_, pb = pb)
}

#' Match taxonomic names to names in a taxonomic reference
#'
#' @description
#' This function attempts to match input strings to a user-supplied combination of taxonomic
#' datasets (see [prepare_taxonomic_resources()]). It attempts:
#' 1. perfect matches and fuzzy matches
#' 2. matches to infraspecies, species, genus, family and any other taxonomic rank present in
#'  `resources`
#' 3. matches to the entire input string and subsets there-of
#' 4. searches for string patterns that suggest a specific taxon rank
#'
#' @details
#' The match blocks, and their order, are APCalign's own (see the comment at the top of this file),
#' generalised to any references and ranks.
#' - It prioritises matches that do not require fuzzy matching (i.e. synonyms,
#'  orthographic variants) over those that do, and accepted names over synonyms at every step.
#' - Taxonomic datasets are sorted, so names align to the top priority taxonomic dataset if a name is
#'  present in multiple lists.
#'
#' Hybrid names (`Genus x species`) and the various "uncertain/composite identification" naming
#' conventions (an intergrade between two taxa, a collector's indecision between two taxa, or a
#' graded/"affinis"/"cf." identification) are detected by default (`hybrids`/`intergrades_affinis`) -- both
#' resolve only to genus rank (never a specific species), since none of these naming conventions can
#' specify a genuine species. See `match_special_case_to_genus()` for the shared implementation.
#'
#' @param taxa The list of taxa requiring checking -- a list with (at least) elements `tocheck` (rows
#'  still needing a match) and `checked` (rows already resolved), in the shape [align_taxa()] builds.
#' @param resources The list(s) of accepted names to check against, produced by
#'  [prepare_taxonomic_resources()].
#' @param fuzzy_abs_dist The number of characters allowed to be different
#'  for a fuzzy match.
#' @param fuzzy_rel_dist The proportion of characters allowed to be different
#'  for a fuzzy match.
#' @param fuzzy_matches Fuzzy matches are turned on as a default. The relative
#'  and absolute distances allowed for fuzzy matches to species and
#'  infraspecific taxon names are defined by the parameters
#' `fuzzy_abs_dist` and `fuzzy_rel_dist`
#' @param imprecise_fuzzy_matches Imprecise fuzzy matches uses the fuzzy
#'  matching function with lenient levels set (absolute distance of
#'  5 characters; relative distance = 0.25).
#'  It offers a way to get a wider range of possible names, possibly
#'  corresponding to very distant spelling mistakes. This is FALSE as default
#'  and all outputs should be checked as it often makes erroneous matches.
#' @param taxon_ranks_to_check Character vector of taxonomic ranks (besides species) to attempt
#'  higher-rank matches against. Defaults to `NULL`, which uses every rank present in `resources`
#'  other than `"species"`/`"subgenus_v2"` (i.e. every higher-rank sublist `resources` contains).
#' @param hybrids Logical; if `TRUE`, a name containing `" x "`/`" X "` (indicating a hybrid taxon) that
#'  isn't itself a listed name is resolved to genus rank (`Genus x [original name]`). Defaults to `TRUE`
#'  (user's decision 2026-11-14, as APCalign always does; opt-in before, issue #9).
#' @param intergrades_affinis Logical; if `TRUE`, a name suggesting an intergrade between two taxa
#'  (a double dash, `--`), a collector's indecision between two taxa (a slash, `/`), or a graded/
#'  "affinis"/"cf." identification (`"aff."`, `"affinis"`, `"cf."`) is resolved to genus rank, unless
#'  it's actually an exact match to a real, listed name (a bare "affinis" is ambiguous between the
#'  qualifier reading and a real specific epithet, e.g. a tautonymous subspecies like "Genus affinis
#'  affinis" -- a real, resource-verified exact match takes priority over the heuristic). Defaults to
#'  `TRUE` (as `hybrids`).
#' @param consider_english_name_endings Logical; if `TRUE`, before any fuzzy matching, try substituting
#'  a recognised informal English vernacular name ending for its formal Latin equivalent (`"-id"` ->
#'  `"-idae"` for family, `"-ine"` -> `"-inae"` for subfamily, `"-oid"` -> `"-oidea"` for superfamily)
#'  and attempt an *exact* match on the corrected name -- useful for a morphospecies/voucher code that
#'  signals a broader taxonomic group this way (e.g. `"Coccinellid BF01"` meaning family Coccinellidae)
#'  rather than a specific genus. Defaults to `FALSE`.
#' @param identifier A dataset, location or other identifier,
#'  which defaults to NA.
#' @param include_bracketed_info Logical; `TRUE` (the default) gives every higher-rank-only match
#'  APCalign's `"<rank name> sp. [<original name>; <identifier>]"` form. `FALSE` drops the brackets when
#'  the name is nothing more than the matched rank's own name (a bare `"Banksia"`, or a bare
#'  `"Genus (Subgenus)"`), giving just that name; a name with anything more keeps the brackets either
#'  way.
#' @param progress Logical; if `TRUE`, prints a text progress bar (`utils::txtProgressBar()`) tracking
#'  what fraction of `taxa$tocheck` has been resolved so far, updated after every match block. Defaults
#'  to `FALSE`.
#'
#' @noRd
match_taxa <- function(
    taxa,
    resources,
    fuzzy_abs_dist = 3,
    fuzzy_rel_dist = 0.2,
    fuzzy_matches = TRUE,
    imprecise_fuzzy_matches = FALSE,
    taxon_ranks_to_check = NULL,
    hybrids = TRUE,
    intergrades_affinis = TRUE,
    consider_english_name_endings = FALSE,
    identifier = NA_character_,
    include_bracketed_info = TRUE,
    progress = FALSE
) {

  if (is.null(taxon_ranks_to_check)) {
    taxon_ranks_to_check <- setdiff(names(resources), c("species", "subgenus_v2"))
  }

  # `taxon_ranks_to_check` is most-specific-first (taxonAlign_taxon_rank_specificity, genus before
  # subgenus) -- the order for *exact* higher-rank matching. Fuzzy matching ties go to the broader rank
  # instead (issue #12), so it uses the reverse, keeping genus ahead of subgenus.
  taxon_ranks_to_check_fuzzy <- rev(taxon_ranks_to_check)
  genus_pos <- which(taxon_ranks_to_check_fuzzy == "genus")
  subgenus_pos <- which(taxon_ranks_to_check_fuzzy == "subgenus")
  if (length(genus_pos) == 1 && length(subgenus_pos) == 1 && subgenus_pos < genus_pos) {
    taxon_ranks_to_check_fuzzy[c(subgenus_pos, genus_pos)] <- taxon_ranks_to_check_fuzzy[c(genus_pos, subgenus_pos)]
  }

  previous_versions <- match_state$versions
  match_state$versions <- attr(resources, "dataset_versions", exact = TRUE)
  on.exit(match_state$versions <- previous_versions, add = TRUE)

  total_rows <- nrow(taxa$tocheck) + nrow(taxa$checked)
  pb <- if (progress) utils::txtProgressBar(min = 0, max = total_rows, style = 3) else NULL
  if (progress) on.exit(close(pb), add = TRUE)

  ## fuzzy matching at genus (and other one-word, higher) ranks
  if (fuzzy_matches == TRUE) {
    fuzzy_match_genera <- function(x, y) {
      fuzzy_match_column(x, y, max_distance_abs = 2, max_distance_rel = 0.35)
    }
  } else {
    fuzzy_match_genera <- function(x, y) {
      fuzzy_match_column(x, y, max_distance_abs = 0, max_distance_rel = 0.0)
    }
  }

  ## imprecise fuzzy matching parameters (APCalign's)
  imprecise_fuzzy_abs_dist <- 5
  imprecise_fuzzy_rel_dist <- 0.25

  if (fuzzy_matches == FALSE) {
    fuzzy_abs_dist <- 0
    fuzzy_rel_dist <- 0
    imprecise_fuzzy_abs_dist <- 0
    imprecise_fuzzy_rel_dist <- 0
  }

  accepted <- resources$species$accepted
  synonyms <- resources$species$synonym

  taxa$tocheck <- taxa$tocheck |>
    dplyr::mutate(
      # the column, not match_taxa()'s `identifier` argument (full length; the column is deduplicated)
      identifier_string = ifelse(is.na(.data$identifier), NA_character_, paste0(" [", .data$identifier, "]")),
      identifier_string2 = ifelse(is.na(.data$identifier), NA_character_, paste0("; ", .data$identifier))
    )

  ## Various stripped versions of the string to match, and versions with 1, 2 and 3 words (genus,
  ## binomial, trinomial).
  taxa$tocheck <- taxa$tocheck |>
    dplyr::mutate(
      cleaned_name = .data$cleaned_name |>
        update_na_with(APCalign::standardise_names(.data$original_name)),
      stripped_name = .data$stripped_name |>
        update_na_with(strip_names_keep_hyphens(.data$cleaned_name)),
      stripped_name2 = .data$stripped_name2 |>
        update_na_with(APCalign::strip_names_extra(.data$stripped_name)),
      trinomial = word(.data$stripped_name2, 1, 3),
      binomial = word(.data$stripped_name2, 1, 2),
      word_one = extract_genus(.data$original_name),
      word_one_stripped = extract_genus(.data$stripped_name),
      # `[^\\v]` rather than `.`: original_name is raw input, and ICU's `.` (stringr) stops at every line
      # terminator, PCRE's only at "\\n"; PCRE's `\\v` is exactly ICU's line terminators
      ignore_bracketed_words = re_replace(.data$original_name, " \\([^\\v]*\\)", "")
    )

  taxa <- redistribute_progress(taxa, pb)
  done <- function(taxa) nrow(taxa$tocheck) == 0
  if (done(taxa)) return(finish_match_taxa(taxa))

  # A name ending in "sp." -- "Genus sp.", or "Genus 1 sp." (APCalign allows only the first).
  is_genus_sp <- function(x) {
    re_detect(x, "[\\s\\p{Z}\\x85]sp\\.$") & count_fixed(x, " ") %in% c(1, 2)
  }
  # TRUE where the name is nothing more than one word -- see include_bracketed_info.
  bare_one_word <- function(taxa, i, words = 1) {
    !include_bracketed_info & re_count(trim(taxa$tocheck$cleaned_name[i]), "[^\\s\\p{Z}\\x85]+") == words
  }

  # ---- match_01: exact matches -----------------------------------------------------------------------
  # match_01a/01b: scientific name, with authorship; match_01c/01d: canonical name.
  taxa <- match_reference_name(taxa, accepted, "original_name", "scientific_name",
    "Exact match of taxon name to an accepted/valid scientific name (including authorship)",
    "match_01a_accepted_scientific_name_with_authorship", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa <- match_reference_name(taxa, synonyms, "original_name", "scientific_name",
    "Exact match of taxon name to a synonymous scientific name (including authorship)",
    "match_01b_synonym_scientific_name_with_authorship", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa <- match_reference_name(taxa, accepted, "cleaned_name", "canonical_name",
    "Exact match of taxon name to an accepted/valid canonical name once punctuation and filler words are removed",
    "match_01c_accepted_canonical_name", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa <- match_reference_name(taxa, synonyms, "cleaned_name", "canonical_name",
    "Exact match of taxon name to a synonymous canonical name once punctuation and filler words are removed",
    "match_01d_synonym_canonical_name", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))

  # ---- match_02a: "Genus (Subgenus) sp." ------------------------------------------------------------
  # Exact, then fuzzy, against the "Genus (Subgenus)" pairs; whatever's left of this shape falls back to
  # genus, keeping the bracket and "sp." in the aligned name. Shape-based, so a pair the references
  # don't have can't fall through to the generic higher-rank blocks and silently lose the subgenus
  # ("Hylaeus (Rhodhylaeus) sp.", a typo for Rhodohylaeus, once aligned to plain "Hylaeus sp.").
  is_bracketed_subgenus_sp <- function(x) {
    re_detect(x, "[\\s\\p{Z}\\x85]sp\\.$") &
      re_detect(second_word(x), "^\\(.*\\)$") &
      count_fixed(x, " ") == 2
  }
  sv2 <- resources$subgenus_v2
  if (any(is_bracketed_subgenus_sp(taxa$tocheck$cleaned_name))) {
    if (!is.null(sv2)) {
      pair <- word(taxa$tocheck$cleaned_name, 1, 2)
      i <- is_bracketed_subgenus_sp(taxa$tocheck$cleaned_name) & pair %in% sv2$genus_and_subgenus
      ii <- match(pair[i], sv2$genus_and_subgenus)
      taxa <- apply_match(taxa, i, sv2, ii, genus_sp_name(taxa, i, sv2$genus_and_subgenus[ii]),
                          "Exact match of taxon name ending with `sp.` to a subgenus",
                          "match_02a_exact_higher_level_accepted_or_synonym", taxon_rank = "subgenus", pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))

      detected <- is_bracketed_subgenus_sp(taxa$tocheck$cleaned_name)
      pair <- word(taxa$tocheck$cleaned_name, 1, 2)
      hit <- rep(NA_character_, nrow(taxa$tocheck))
      if (any(detected)) hit[detected] <- fuzzy_match_genera(pair[detected], sv2$genus_and_subgenus)
      i <- detected & !is.na(hit)
      ii <- match(hit[i], sv2$genus_and_subgenus)
      taxa <- apply_match(taxa, i, sv2, ii, genus_sp_name(taxa, i, sv2$genus_and_subgenus[ii]),
                          "Fuzzy match of taxon name ending with `sp.` to a subgenus",
                          "match_02a_fuzzy_higher_level_accepted_or_synonym", taxon_rank = "subgenus",
                          chars_changed = stringdist::stringdist(pair[i], hit[i], method = "dl"), pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))
    }
    taxa <- match_special_case_to_genus(
      taxa, resources, detect_fn = is_bracketed_subgenus_sp, bracket_sep = " sp. [",
      reason_text = "Taxon name has a \"Genus (Subgenus) sp.\" form whose subgenus could not be matched; falling back to genus rank.",
      alignment_code_exact = "match_02a_genus_fallback_exact",
      alignment_code_fuzzy = "match_02a_genus_fallback_fuzzy",
      alignment_code_unresolved = "match_02a_genus_fallback_unresolved",
      alignment_code_no_resource = "match_02a_genus_fallback_no_resource",
      fuzzy_match_genera = fuzzy_match_genera, pb = pb
    )
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_02x: bare "Genus subg. Subgenusname" (issue #25) ----------------------------------------
  # The NSL's marker form of the same subgenus concept, looked up as the equivalent "Genus (Subgenus)"
  # pair (taxonAlign.dataprep's load_NSL() stores the bare subgenus name in canonical_name).
  is_marker_subgenus <- function(x) {
    count_fixed(x, " ") == 2 &
      re_detect(second_word(x), "(?i)^subg\\.?$")
  }
  marker_key <- function(x) paste0(word(x, 1), " (", word(x, 3), ")")
  if (any(is_marker_subgenus(taxa$tocheck$cleaned_name))) {
    if (!is.null(sv2)) {
      key <- marker_key(taxa$tocheck$cleaned_name)
      i <- is_marker_subgenus(taxa$tocheck$cleaned_name) & key %in% sv2$genus_and_subgenus
      ii <- match(key[i], sv2$genus_and_subgenus)
      taxa <- apply_match(taxa, i, sv2, ii,
                          higher_rank_name(taxa, i, sv2$genus_and_subgenus[ii], bare = bare_one_word(taxa, i, 3)),
                          "Exact match of a \"Genus subg. Subgenusname\" name to a subgenus",
                          "match_02x_marker_exact_subgenus", taxon_rank = "subgenus", pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))

      detected <- is_marker_subgenus(taxa$tocheck$cleaned_name)
      key <- marker_key(taxa$tocheck$cleaned_name)
      hit <- rep(NA_character_, nrow(taxa$tocheck))
      if (any(detected)) hit[detected] <- fuzzy_match_genera(key[detected], sv2$genus_and_subgenus)
      i <- detected & !is.na(hit)
      ii <- match(hit[i], sv2$genus_and_subgenus)
      taxa <- apply_match(taxa, i, sv2, ii,
                          higher_rank_name(taxa, i, sv2$genus_and_subgenus[ii], bare = bare_one_word(taxa, i, 3)),
                          "Fuzzy match of a \"Genus subg. Subgenusname\" name to a subgenus",
                          "match_02x_marker_fuzzy_subgenus", taxon_rank = "subgenus",
                          chars_changed = stringdist::stringdist(key[i], hit[i], method = "dl"), pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))
    }
    taxa <- match_special_case_to_genus(
      taxa, resources, detect_fn = is_marker_subgenus, bracket_sep = " sp. [",
      reason_text = "Taxon name has a \"Genus subg. Subgenusname\" form whose subgenus could not be matched; falling back to genus rank.",
      alignment_code_exact = "match_02x_marker_genus_exact",
      alignment_code_fuzzy = "match_02x_marker_genus_fuzzy",
      alignment_code_unresolved = "match_02x_marker_genus_unresolved",
      alignment_code_no_resource = "match_02x_marker_genus_no_resource",
      fuzzy_match_genera = fuzzy_match_genera, pb = pb
    )
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_02y: bare "Genus (Subgenus)" (issue #14) -----------------------------------------------
  # Quarantined before species-level matching: strip_names() keeps the bracketed word, so it would sit
  # where a species epithet does and could fuzzy-match an unrelated species.
  is_bracketed_subgenus <- function(x) {
    count_fixed(x, " ") == 1 & re_detect(second_word(x), "^\\(.*\\)$")
  }
  if (any(is_bracketed_subgenus(taxa$tocheck$cleaned_name))) {
    if (!is.null(sv2)) {
      pair <- word(taxa$tocheck$cleaned_name, 1, 2)
      i <- is_bracketed_subgenus(taxa$tocheck$cleaned_name) & pair %in% sv2$genus_and_subgenus
      ii <- match(pair[i], sv2$genus_and_subgenus)
      taxa <- apply_match(taxa, i, sv2, ii,
                          higher_rank_name(taxa, i, sv2$genus_and_subgenus[ii], bare = bare_one_word(taxa, i, 2)),
                          "Exact match of a bracketed genus (subgenus) to a subgenus",
                          "match_02y_bracket_exact_subgenus", taxon_rank = "subgenus", pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))

      detected <- is_bracketed_subgenus(taxa$tocheck$cleaned_name)
      pair <- word(taxa$tocheck$cleaned_name, 1, 2)
      hit <- rep(NA_character_, nrow(taxa$tocheck))
      if (any(detected)) hit[detected] <- fuzzy_match_genera(pair[detected], sv2$genus_and_subgenus)
      i <- detected & !is.na(hit)
      ii <- match(hit[i], sv2$genus_and_subgenus)
      taxa <- apply_match(taxa, i, sv2, ii,
                          higher_rank_name(taxa, i, sv2$genus_and_subgenus[ii], bare = bare_one_word(taxa, i, 2)),
                          "Fuzzy match of a bracketed genus (subgenus) to a subgenus",
                          "match_02y_bracket_fuzzy_subgenus", taxon_rank = "subgenus",
                          chars_changed = stringdist::stringdist(pair[i], hit[i], method = "dl"), pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))
    }
    taxa <- match_special_case_to_genus(
      taxa, resources, detect_fn = is_bracketed_subgenus, bracket_sep = " sp. [",
      reason_text = "Taxon name has a bracketed \"Genus (Subgenus)\" form whose subgenus could not be matched; falling back to genus rank.",
      alignment_code_exact = "match_02y_bracket_genus_exact",
      alignment_code_fuzzy = "match_02y_bracket_genus_fuzzy",
      alignment_code_unresolved = "match_02y_bracket_genus_unresolved",
      alignment_code_no_resource = "match_02y_bracket_genus_no_resource",
      fuzzy_match_genera = fuzzy_match_genera, pb = pb
    )
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_02b: "Genus sp." exact (APCalign 02a, 02d) -----------------------------------------------
  # A genus or subgenus of any status; any other rank only when accepted (APCalign's 02d: accepted family
  # only). A synonym at a rank above genus is left for match_12b, which keeps the original name in
  # brackets, as APCalign's 12e does.
  for (ranks in taxon_ranks_to_check) {
    tbl <- rank_rows(resources, ranks, if (ranks %in% c("genus", "subgenus")) "any" else "accepted")
    if (is.null(tbl) || nrow(tbl) == 0) next
    i <- is_genus_sp(taxa$tocheck$cleaned_name) & taxa$tocheck$word_one_stripped %in% tbl$word_one_stripped
    ii <- match(taxa$tocheck$word_one_stripped[i], tbl$word_one_stripped)
    taxa <- apply_match(taxa, i, tbl, ii, genus_sp_name(taxa, i, tbl$word_one_stripped[ii]),
                        paste0("Exact match of taxon name ending with `sp.` to a ", ranks),
                        "match_02b_exact_higher_level_accepted_or_synonym", taxon_rank = ranks, pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_02z: English vernacular name endings (opt-in) -------------------------------------------
  # "Coccinellid BF01" -> family Coccinellidae: substitute the formal ending, then require an *exact*
  # match. Tribe ("-ini") and subtribe ("-ina") endings are already the formal Latin form.
  if (consider_english_name_endings) {
    english_ending_substitutions <- list(
      list(vernacular = "id$", formal = "idae", rank = "family"),
      list(vernacular = "ine$", formal = "inae", rank = "subfamily"),
      list(vernacular = "oid$", formal = "oidea", rank = "superfamily")
    )
    for (sub in english_ending_substitutions) {
      tbl <- rank_rows(resources, sub$rank)
      if (is.null(tbl) || nrow(tbl) == 0) next
      candidate <- re_replace(taxa$tocheck$word_one_stripped, paste0("(?i)", sub$vernacular), sub$formal)
      i <- !is.na(candidate) & candidate != taxa$tocheck$word_one_stripped & candidate %in% tbl$canonical_name
      ii <- match(candidate[i], tbl$canonical_name)
      taxa <- apply_match(taxa, i, tbl, ii,
                          higher_rank_name(taxa, i, candidate[i], bare = bare_one_word(taxa, i)),
                          paste0("Matched by substituting the formal ", sub$rank, " name ending for the English vernacular one"),
                          "match_02z_english_ending_accepted", taxon_rank = sub$rank, pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))
    }
  }

  # ---- match_02c: "Genus sp." fuzzy (APCalign 02b/02c) -----------------------------------------------
  # The closest higher-rank name, accepted names first, then synonyms. Aligned here only when that's a
  # genus; a closest match at another rank is left for match_12c, which formats it as APCalign's 12h/12i
  # do (original name in brackets) -- APCalign fuzzy-matches only genera for a "sp." name.
  sp <- is_genus_sp(taxa$tocheck$cleaned_name)
  if (any(sp)) {
    words <- ifelse(sp, taxa$tocheck$word_one_stripped, NA_character_)
    fz <- fuzzy_higher_rank(words, resources, taxon_ranks_to_check_fuzzy, "accepted", fuzzy_match_genera)
    i <- fz$rank %in% "genus"
    taxa <- apply_match(taxa, i, rank_rows(resources, "genus", "accepted"), fz$row[i],
                        genus_sp_name(taxa, i, fz$name[i]),
                        "Fuzzy match of taxon name ending with `sp.` to an accepted genus",
                        "match_02c_fuzzy_genus_accepted", taxon_rank = "genus",
                        chars_changed = stringdist::stringdist(words[i], fz$name[i], method = "dl"), pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
    # only names with no accepted match at any rank go on to synonym genera; the rest are for match_12c
    words <- ifelse(is.na(fz$rank[!i]), words[!i], NA_character_)
    fz <- fuzzy_higher_rank(words, resources, taxon_ranks_to_check_fuzzy, "synonym", fuzzy_match_genera)
    i <- fz$rank %in% "genus"
    taxa <- apply_match(taxa, i, rank_rows(resources, "genus", "synonym"), fz$row[i],
                        genus_sp_name(taxa, i, fz$name[i]),
                        "Fuzzy match of taxon name ending with `sp.` to a synonymous genus",
                        "match_02c_fuzzy_genus_synonym", taxon_rank = "genus",
                        chars_changed = stringdist::stringdist(words[i], fz$name[i], method = "dl"), pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_04: intergrade ("--") and indecision ("/") names, to genus (APCalign 03/04) -------------
  if (intergrades_affinis) {
    is_intergrade_indecision <- function(cleaned_name) {
      is_intergrade <- re_detect(cleaned_name, "\\ -- |\\--")
      is_indecision <- (re_detect(cleaned_name, "\\p{L}\\/") |
                          re_detect(cleaned_name, "[\\s\\p{Z}\\x85]\\/")) &
        !re_detect(cleaned_name, "\\p{Nd}") &
        !re_detect(cleaned_name, "\\(") &
        !re_detect(cleaned_name, "\\'")
      is_intergrade | is_indecision
    }
    taxa <- match_special_case_to_genus(
      taxa, resources, detect_fn = is_intergrade_indecision, bracket_sep = " sp. [",
      reason_text = "Taxon name suggests an intergrade or an indecision between taxa; can only be aligned to genus rank.",
      alignment_code_exact = "match_04a_intergrade_affinis_exact_genus",
      alignment_code_fuzzy = "match_04b_intergrade_affinis_fuzzy_genus",
      alignment_code_unresolved = "match_04c_intergrade_affinis_unresolved",
      alignment_code_no_resource = "match_04d_intergrade_affinis_no_genus_resource",
      fuzzy_match_genera = fuzzy_match_genera, pb = pb
    )
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_05: fuzzy canonical name --------------------------------------------------------------
  taxa$tocheck$fuzzy_match_cleaned <- fuzzy_match_column(
    taxa$tocheck$stripped_name, accepted$stripped_canonical, fuzzy_abs_dist, fuzzy_rel_dist
  )
  taxa <- match_reference_name(taxa, accepted, "fuzzy_match_cleaned", "stripped_canonical",
    "Fuzzy match of taxon name to an accepted/valid canonical name once punctuation and filler words are removed",
    "match_05a_fuzzy_accepted_canonical_name", distance_from = "stripped_name", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  if (!is.null(synonyms) && nrow(synonyms) > 0) {
    taxa$tocheck$fuzzy_match_cleaned_synonym <- fuzzy_match_column(
      taxa$tocheck$stripped_name, synonyms$stripped_canonical, fuzzy_abs_dist, fuzzy_rel_dist
    )
    taxa <- match_reference_name(taxa, synonyms, "fuzzy_match_cleaned_synonym", "stripped_canonical",
      "Fuzzy match of taxon name to a synonymous canonical name once punctuation and filler words are removed",
      "match_05b_fuzzy_synonym_canonical_name", distance_from = "stripped_name", pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_06: "aff."/"affinis"/"cf." names, to genus (APCalign 06) -------------------------------
  # After fuzzy matching, as in APCalign: some listed names (phrase names) contain "sp. aff.". 06a/06b
  # (taxonAlign, issue #16) first accept an exact match of the whole name, untouched by
  # standardise_names()'s "aff." abbreviation -- "Themognatha affinis affinis" is a real tautonymous
  # subspecies, not an affinity.
  if (intergrades_affinis) {
    not_before_rank_marker <- "(?![\\s\\p{Z}\\x85]+(?:subsp|ssp|subvar|var|forma|form|ser|series|cv|f)\\.?(?:[\\s\\p{Z}\\x85]|$))"
    affinis_qualifier <- paste0(" affinis", not_before_rank_marker, "[\\s\\p{Z}\\x85]")
    is_affinis <- function(cleaned_name) {
      re_detect(cleaned_name, "[Aa]ff[.\\s\\p{Z}\\x85]") |
        re_detect(cleaned_name, affinis_qualifier) |
        re_detect(cleaned_name, " cf[.\\s\\p{Z}\\x85]")
    }
    taxa <- match_reference_name(taxa, accepted, "ignore_bracketed_words", "canonical_name",
      "Taxon name suggests a graded/\"affinis\"/\"cf.\" identification, but exactly matches a real, accepted name",
      "match_06a_affinis_exact_species_accepted", only = is_affinis(taxa$tocheck$cleaned_name), pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
    taxa <- match_reference_name(taxa, synonyms, "ignore_bracketed_words", "canonical_name",
      "Taxon name suggests a graded/\"affinis\"/\"cf.\" identification, but exactly matches a real, synonymous name",
      "match_06b_affinis_exact_species_synonym", only = is_affinis(taxa$tocheck$cleaned_name), pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
    taxa <- match_special_case_to_genus(
      taxa, resources, detect_fn = is_affinis, bracket_sep = " sp. [",
      reason_text = "Taxon name suggests a graded/\"affinis\"/\"cf.\" identification (and isn't an exact match to a real, listed name); can only be aligned to genus rank.",
      alignment_code_exact = "match_06c_affinis_exact_genus",
      alignment_code_fuzzy = "match_06d_affinis_fuzzy_genus",
      alignment_code_unresolved = "match_06e_affinis_unresolved",
      alignment_code_no_resource = "match_06f_affinis_no_genus_resource",
      fuzzy_match_genera = fuzzy_match_genera, pb = pb
    )
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_07: imprecise fuzzy canonical name (opt-in; APCalign 07) -------------------------------
  # Up to 5 characters and 25% different, with the first two letters of the epithet agreeing.
  if (imprecise_fuzzy_matches) {
    taxa$tocheck$fuzzy_match_cleaned_imprecise <- fuzzy_match_column(
      taxa$tocheck$stripped_name, accepted$stripped_canonical,
      imprecise_fuzzy_abs_dist, imprecise_fuzzy_rel_dist, epithet_letters = 2
    )
    taxa <- match_reference_name(taxa, accepted, "fuzzy_match_cleaned_imprecise", "stripped_canonical",
      "Imprecise fuzzy match of taxon name to an accepted/valid canonical name once punctuation and filler words are removed",
      "match_07a_imprecise_fuzzy_accepted_canonical_name", distance_from = "stripped_name", pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
    if (!is.null(synonyms) && nrow(synonyms) > 0) {
      taxa$tocheck$fuzzy_match_cleaned_synonym_imprecise <- fuzzy_match_column(
        taxa$tocheck$stripped_name, synonyms$stripped_canonical,
        imprecise_fuzzy_abs_dist, imprecise_fuzzy_rel_dist, epithet_letters = 2
      )
      taxa <- match_reference_name(taxa, synonyms, "fuzzy_match_cleaned_synonym_imprecise", "stripped_canonical",
        "Imprecise fuzzy match of taxon name to a synonymous canonical name once punctuation and filler words are removed",
        "match_07b_imprecise_fuzzy_synonym_canonical_name", distance_from = "stripped_name", pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))
    }
  }

  # ---- match_08: hybrid names, to genus (opt-in; APCalign 08) ---------------------------------------
  # After every whole-name match, since listed names include hybrids ("Onopordum acanthium x
  # Onopordum illyricum", which a misspelling must still fuzzy-match in match_05).
  if (hybrids) {
    taxa <- match_special_case_to_genus(
      taxa, resources, detect_fn = function(x) re_detect(x, " [xX] "), bracket_sep = " x [",
      reason_text = "Taxon name includes ' x ', indicating a hybrid taxon; can only be aligned to genus rank.",
      alignment_code_exact = "match_08a_hybrid_exact_genus",
      alignment_code_fuzzy = "match_08b_hybrid_fuzzy_genus",
      alignment_code_unresolved = "match_08c_hybrid_unresolved",
      alignment_code_no_resource = "match_08d_hybrid_no_genus_resource",
      fuzzy_match_genera = fuzzy_match_genera, pb = pb
    )
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_09: the first three words ("trinomial") ------------------------------------------------
  # A valid trinomial followed by notes.
  taxa <- match_reference_name(taxa, accepted, "trinomial", "trinomial",
    "Exact match of the first three words of the taxon name to an accepted canonical name",
    "match_09a_trinomial_exact_accepted", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa <- match_reference_name(taxa, synonyms, "trinomial", "trinomial",
    "Exact match of the first three words of the taxon name to a synonymous canonical name",
    "match_09b_trinomial_exact_synonym", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa$tocheck$fuzzy_match_trinomial <- fuzzy_match_column(
    taxa$tocheck$trinomial, accepted$trinomial, fuzzy_abs_dist, fuzzy_rel_dist
  )
  taxa <- match_reference_name(taxa, accepted, "fuzzy_match_trinomial", "trinomial",
    "Fuzzy match of the first three words of the taxon name to an accepted canonical name",
    "match_09c_trinomial_fuzzy_accepted", distance_from = "trinomial", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  if (!is.null(synonyms) && nrow(synonyms) > 0) {
    taxa$tocheck$fuzzy_match_trinomial_synonym <- fuzzy_match_column(
      taxa$tocheck$trinomial, synonyms$trinomial, fuzzy_abs_dist, fuzzy_rel_dist
    )
    taxa <- match_reference_name(taxa, synonyms, "fuzzy_match_trinomial_synonym", "trinomial",
      "Fuzzy match of the first three words of the taxon name to a synonymous canonical name",
      "match_09d_trinomial_fuzzy_synonym", distance_from = "trinomial", pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_10: the first two words ("binomial") ---------------------------------------------------
  # A valid binomial followed by notes or an invalid infraspecific epithet. Not for "Genus (Subgenus)
  # ...": there the second word isn't an epithet.
  no_bracket <- function(taxa) {
    !re_detect(second_word(taxa$tocheck$cleaned_name), "^\\(") &
      !re_detect(second_word(taxa$tocheck$cleaned_name), "\\)$")
  }
  taxa <- match_reference_name(taxa, accepted, "binomial", "binomial",
    "Exact match of the first two words of the taxon name to an accepted canonical name",
    "match_10a_binomial_exact_accepted", only = no_bracket(taxa), pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa <- match_reference_name(taxa, synonyms, "binomial", "binomial",
    "Exact match of the first two words of the taxon name to a synonymous canonical name",
    "match_10b_binomial_exact_synonym", only = no_bracket(taxa), pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa$tocheck$fuzzy_match_binomial <- fuzzy_match_column(
    taxa$tocheck$binomial, accepted$binomial, fuzzy_abs_dist, fuzzy_rel_dist, epithet_letters = 2
  )
  taxa <- match_reference_name(taxa, accepted, "fuzzy_match_binomial", "binomial",
    "Fuzzy match of the first two words of the taxon name to an accepted canonical name",
    "match_10c_binomial_fuzzy_accepted", only = no_bracket(taxa), distance_from = "binomial", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  if (!is.null(synonyms) && nrow(synonyms) > 0) {
    taxa$tocheck$fuzzy_match_binomial_synonym <- fuzzy_match_column(
      taxa$tocheck$binomial, synonyms$binomial, fuzzy_abs_dist, fuzzy_rel_dist, epithet_letters = 2
    )
    taxa <- match_reference_name(taxa, synonyms, "fuzzy_match_binomial_synonym", "binomial",
      "Fuzzy match of the first two words of the taxon name to a synonymous canonical name",
      "match_10d_binomial_fuzzy_synonym", only = no_bracket(taxa), distance_from = "binomial", pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_11: exact matches ignoring a bracketed word (taxonAlign) -------------------------------
  # "Genus (Subgenus) species" -> "Genus species".
  taxa <- match_reference_name(taxa, accepted, "ignore_bracketed_words", "canonical_name",
    "Exact match of the taxon name, ignoring bracketed words, to an accepted canonical name",
    "match_11a_no_brackets_accepted", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))
  taxa <- match_reference_name(taxa, synonyms, "ignore_bracketed_words", "canonical_name",
    "Exact match of the taxon name, ignoring bracketed words, to a synonymous canonical name",
    "match_11b_no_brackets_synonym", pb = pb)
  if (done(taxa)) return(finish_match_taxa(taxa))

  # ---- match_12a: "Genus (Subgenus) <anything>" to subgenus (taxonAlign) ----------------------------
  if (!is.null(sv2)) {
    pair <- word(taxa$tocheck$cleaned_name, 1, 2)
    i <- re_detect(second_word(taxa$tocheck$cleaned_name), "^\\(.*\\)$") & pair %in% sv2$genus_and_subgenus
    ii <- match(pair[i], sv2$genus_and_subgenus)
    taxa <- apply_match(taxa, i, sv2, ii,
                        higher_rank_name(taxa, i, sv2$genus_and_subgenus[ii], bare = bare_one_word(taxa, i, 2)),
                        "Exact match of a genus (subgenus) to a subgenus",
                        "match_12a_exact_subgenus_accepted_or_synonym", taxon_rank = "subgenus", pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_12b: the first word, exactly, at a higher rank (APCalign 12a-12e) ----------------------
  # Most specific rank first (genus before family, ...); within a rank the table is in
  # taxonomic-status priority order, so an accepted name wins.
  for (ranks in taxon_ranks_to_check) {
    tbl <- rank_rows(resources, ranks)
    if (is.null(tbl) || nrow(tbl) == 0) next
    i <- taxa$tocheck$word_one_stripped %in% tbl$word_one_stripped
    ii <- match(taxa$tocheck$word_one_stripped[i], tbl$word_one_stripped)
    taxa <- apply_match(taxa, i, tbl, ii,
                        higher_rank_name(taxa, i, tbl$word_one_stripped[ii], bare = bare_one_word(taxa, i)),
                        paste0("Exact match of the first word of the taxon name to a ", ranks),
                        "match_12b_higher_rank_exact_accepted", taxon_rank = ranks, pb = pb)
    if (done(taxa)) return(finish_match_taxa(taxa))
  }

  # ---- match_12c: the first word, fuzzily, at a higher rank (APCalign 12f-12i) ----------------------
  # Accepted names first, then synonyms; the closest name across ranks, ties to the broader rank.
  for (status in c("accepted", "synonym")) {
    fz <- fuzzy_higher_rank(taxa$tocheck$word_one_stripped, resources, taxon_ranks_to_check_fuzzy, status, fuzzy_match_genera)
    for (ranks in unique(stats::na.omit(fz$rank))) {
      tbl <- rank_rows(resources, ranks, status)
      i <- fz$rank %in% ranks
      ii <- fz$row[i]
      taxa <- apply_match(taxa, i, tbl, ii,
                          higher_rank_name(taxa, i, fz$name[i], bare = bare_one_word(taxa, i)),
                          paste0("Fuzzy match of the first word of the taxon name to a", if (status == "accepted") "n accepted " else " synonymous ", ranks),
                          paste0("match_12c_higher_rank_fuzzy_", status), taxon_rank = ranks,
                          chars_changed = stringdist::stringdist(taxa$tocheck$word_one_stripped[i], fz$name[i], method = "dl"),
                          pb = pb)
      if (done(taxa)) return(finish_match_taxa(taxa))
      fz <- lapply(fz, function(v) v[!i])
    }
  }

  finish_match_taxa(taxa)
}

# Drops the columns only used while matching.
finish_match_taxa <- function(taxa) {
  scratch <- c("identifier_string", "identifier_string2", "aligned_name_tmp")
  taxa$tocheck <- taxa$tocheck |> dplyr::select(-dplyr::any_of(scratch))
  taxa$checked <- taxa$checked |> dplyr::select(-dplyr::any_of(scratch))
  taxa
}
