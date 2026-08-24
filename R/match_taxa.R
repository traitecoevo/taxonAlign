# Shared implementation for the hybrid/intergrade/indecision/affinis match blocks in match_taxa()
# below. Real APCalign's internal match_taxa() implements these as ~20 separate, near-identical
# blocks (5 sub-blocks each for 4 pattern families: try an exact match against accepted genera, a
# fuzzy match against accepted genera, a fuzzy match against synonym genera, an APNI-only variant,
# and an "unknown genus" fallback) because APC/APNI's resources keep accepted/synonym/APNI genera in
# three separate tables. taxonAlign's `resources$genus` is already one combined table (both statuses
# together -- only `species` gets split by taxonomic_status in prepare_taxonomic_resources()), so
# that split doesn't apply here -- one generic function suffices for both callers.
#
# `detect_fn` is a function of a `cleaned_name` character vector returning a logical vector (not a
# pre-computed logical vector) because `taxa$tocheck` shrinks after each `redistribute()` call below
# -- recomputing detect_fn(taxa$tocheck$cleaned_name) fresh each time keeps it aligned with whatever
# rows are still actually in `tocheck`, rather than relying on stale positions/length from before
# rows were removed.
#
# `alignment_code_*` are the four fully-formed codes for this match family's sub-cases (exact/fuzzy/
# unresolved/no-genus-resource) rather than a single prefix the helper appends suffixes to -- this
# keeps each match family's codes numbered sequentially (`match_03a`..`match_03d`, `match_04a`..
# `match_04d`, ...) in execution order, the same convention the numbered match_NNx blocks elsewhere in
# `match_taxa()` use, so sorting a result by `alignment_code` reproduces the order taxa were matched in.
match_special_case_to_genus <- function(taxa, resources, detect_fn, bracket_sep, reason_text,
                                         alignment_code_exact, alignment_code_fuzzy,
                                         alignment_code_unresolved, alignment_code_no_resource,
                                         fuzzy_match_genera, pb = NULL) {

  if (is.null(resources$genus)) {
    # no genus-rank reference at all to check against -- still flag matching rows as checked (so they
    # don't fall through to later, inappropriate blocks) rather than silently leaving them untouched
    i <- detect_fn(taxa$tocheck$cleaned_name)
    taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
      dplyr::mutate(
        taxonomic_dataset = NA_character_,
        taxon_rank = NA_character_,
        taxonomic_status = NA_character_,
        taxon_ID = NA_character_,
        accepted_name_usage_ID = NA_character_,
        aligned_name = NA_character_,
        aligned_reason = paste0(
          reason_text, " No genus-rank reference is available to check it against (", Sys.Date(), ")."
        ),
        chars_changed = NA_integer_,
        known = TRUE,
        checked = TRUE,
        alignment_code = alignment_code_no_resource
      )
    return(redistribute_progress(taxa, pb))
  }

  # exact genus match
  i <- detect_fn(taxa$tocheck$cleaned_name) & taxa$tocheck$word_one_stripped %in% resources$genus$canonical_name
  ii <- match(taxa$tocheck[i, ]$word_one_stripped, resources$genus$canonical_name)
  taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
    dplyr::mutate(
      taxonomic_dataset = resources$genus$taxonomic_dataset[ii],
      taxon_rank = "genus",
      taxonomic_status = resources$genus$taxonomic_status[ii],
      taxon_ID = resources$genus$taxon_ID[ii],
      accepted_name_usage_ID = resources$genus$accepted_name_usage_ID[ii],
      aligned_name_tmp = paste0(resources$genus$canonical_name[ii], bracket_sep, cleaned_name),
      aligned_name = ifelse(is.na(identifier_string2),
                            paste0(aligned_name_tmp, "]"),
                            paste0(aligned_name_tmp, identifier_string2, "]")),
      aligned_reason = paste0(reason_text, " Exact match to a genus in ", taxonomic_dataset, " (", Sys.Date(), ")."),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = alignment_code_exact
    )
  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # fuzzy genus match
  taxa$tocheck <- taxa$tocheck |>
    dplyr::mutate(fuzzy_match_genus = fuzzy_match_genera(word_one_stripped, resources$genus$canonical_name))
  i <- detect_fn(taxa$tocheck$cleaned_name) & taxa$tocheck$fuzzy_match_genus %in% resources$genus$canonical_name
  ii <- match(taxa$tocheck[i, ]$fuzzy_match_genus, resources$genus$canonical_name)
  taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
    dplyr::mutate(
      taxonomic_dataset = resources$genus$taxonomic_dataset[ii],
      taxon_rank = "genus",
      taxonomic_status = resources$genus$taxonomic_status[ii],
      taxon_ID = resources$genus$taxon_ID[ii],
      accepted_name_usage_ID = resources$genus$accepted_name_usage_ID[ii],
      aligned_name_tmp = paste0(resources$genus$canonical_name[ii], bracket_sep, cleaned_name),
      aligned_name = ifelse(is.na(identifier_string2),
                            paste0(aligned_name_tmp, "]"),
                            paste0(aligned_name_tmp, identifier_string2, "]")),
      aligned_reason = paste0(reason_text, " Fuzzy match to a genus in ", taxonomic_dataset, " (", Sys.Date(), ")."),
      chars_changed = as.integer(stringdist::stringdist(word_one_stripped, fuzzy_match_genus, method = "dl")),
      known = TRUE,
      checked = TRUE,
      alignment_code = alignment_code_fuzzy
    )
  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # unresolved fallback: still flag as checked (so it doesn't fall through to later, inappropriate
  # matches, e.g. an unrelated trinomial/binomial exact-match) but leave the alignment itself NA
  i <- detect_fn(taxa$tocheck$cleaned_name)
  taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
    dplyr::mutate(
      taxonomic_dataset = NA_character_,
      taxon_rank = NA_character_,
      taxonomic_status = NA_character_,
      taxon_ID = NA_character_,
      accepted_name_usage_ID = NA_character_,
      aligned_name = NA_character_,
      aligned_reason = paste0(
        reason_text, " Exact and fuzzy matches failed to resolve a genus (", Sys.Date(), ")."
      ),
      chars_changed = NA_integer_,
      known = TRUE,
      checked = TRUE,
      alignment_code = alignment_code_unresolved
    )
  redistribute_progress(taxa, pb)
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
#' - It cycles through more than 20 different string patterns, sequentially
#'  searching for additional match patterns.
#' - It identifies string patterns in input names that suggest a name can only be
#'  aligned to a higher rank (e.g. taxa not identified to species, `genus sp.`).
#' - It prioritises matches that do not require fuzzy matching (i.e. synonyms,
#'  orthographic variants) over those that do.
#' - Taxonomic datasets are sorted, so names align to the top priority taxonomic dataset if a name is
#'  present in multiple lists.
#'
#' Hybrid names (`Genus x species`) and the various "uncertain/composite identification" naming
#' conventions (an intergrade between two taxa, a collector's indecision between two taxa, or a
#' graded/"affinis"/"cf." identification) are opt-in via `hybrids`/`intergrades_affinis` -- both
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
#' @param hybrids Logical; if `TRUE`, a name containing `" x "`/`" X "` (indicating a hybrid taxon) is
#'  resolved to genus rank (`Genus x [original name]`) rather than left for later, inappropriate match
#'  blocks to potentially mishandle. Defaults to `FALSE`.
#' @param intergrades_affinis Logical; if `TRUE`, a name suggesting an intergrade between two taxa
#'  (a double dash, `--`), a collector's indecision between two taxa (a slash, `/`), or a graded/
#'  "affinis"/"cf." identification (`"aff."`, `"affinis"`, `"cf."`) is resolved to genus rank, unless
#'  it's actually an exact match to a real, listed name -- see match_11c below (issue #16): a bare
#'  "affinis" is genuinely ambiguous between the qualifier reading and a real specific epithet (e.g.
#'  a tautonymous subspecies like "Genus affinis affinis"), and `APCalign::standardise_names()`
#'  abbreviates it the same way either way, so the two are indistinguishable by text shape alone -- a
#'  real, resource-verified exact match is given priority over the heuristic rather than guessing.
#'  Defaults to `FALSE`.
#' @param consider_english_name_endings Logical; if `TRUE`, before any fuzzy matching, try substituting
#'  a recognised informal English vernacular name ending for its formal Latin equivalent (`"-id"` ->
#'  `"-idae"` for family, `"-ine"` -> `"-inae"` for subfamily, `"-oid"` -> `"-oidea"` for superfamily)
#'  and attempt an *exact* match on the corrected name. Real invertebrate morphospecies/voucher codes
#'  commonly use these informal forms to signal a broader taxonomic group without specifying an exact
#'  genus (e.g. `"Coccinellid BF01"` meaning family Coccinellidae) -- left to ordinary fuzzy matching,
#'  these very often resolved to a coincidentally-similar but unrelated genus instead (see issue #12).
#'  Defaults to `FALSE`.
#' @param identifier A dataset, location or other identifier,
#'  which defaults to NA.
#' @param include_bracketed_info Logical; controls the `"<rank name> sp. [<original name>; <identifier>]"`
#'  formatting APCalign uses for every higher-rank-only match. When `FALSE` (the default) *and* the
#'  name being matched reduces to nothing more than the matched rank's own name (a bare single word for
#'  an ordinary rank, or a bare `"Genus (Subgenus)"` for the bracketed-subgenus convention -- see
#'  `?prepare_taxonomic_resources`) -- i.e. there's nothing beyond the rank name itself worth echoing
#'  back, since `original_name` already preserves the raw input as its own column regardless -- the
#'  bracketed suffix (and any `identifier`) is dropped entirely and `aligned_name` is just the bare
#'  matched name. Whenever the name being matched has anything beyond the rank name itself (an
#'  unresolved epithet, a morphospecies code, a hybrid/intergrade/indecision/affinis marker, ...), the
#'  bracketed format is used regardless of this argument, since dropping it there would lose real
#'  information. Set to `TRUE` to always use the bracketed format, matching APCalign's convention
#'  exactly. Defaults to `FALSE`.
#' @param progress Logical; if `TRUE`, prints a text progress bar (`utils::txtProgressBar()`) tracking
#'  what fraction of `taxa$tocheck` has been resolved so far, updated after every match block. Tracks
#'  rows resolved rather than which match block is currently running, since blocks aren't equal-cost --
#'  the fuzzy-matching blocks typically do most of the real work on large inputs, so a block-count-based
#'  bar would jump to "nearly done" almost instantly and then stall. Defaults to `FALSE`.
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
    hybrids = FALSE,
    intergrades_affinis = FALSE,
    consider_english_name_endings = FALSE,
    identifier = NA_character_,
    include_bracketed_info = FALSE,
    progress = FALSE
) {

  if (is.null(taxon_ranks_to_check)) {
    taxon_ranks_to_check <- setdiff(names(resources), c("species", "subgenus_v2"))
  }

  # `taxon_ranks_to_check` is most-specific-first (see taxonAlign_taxon_rank_specificity in
  # prepare_taxonomic_resources.R), which is the right default for *exact* higher-rank matching
  # (match_02b/match_12b) -- an exact string collision across unrelated ranks is rare, and when it does
  # happen (a genus and its own nominotypical subgenus sharing a name) it's already handled by that
  # ordering's own deliberate genus-before-subgenus exception. Fuzzy matching (match_02c/match_12c) is a
  # different story: checked in practice against a real, large, combined AFD+GBIF reference and the
  # full real AusInvertTraits name list, 52% of names resolved via a fuzzy higher-rank match *also*
  # fuzzy-matched a real candidate at a different rank -- overwhelmingly not coincidence, but a
  # systematic pattern (see issue #12): informal English vernacular adjective forms derived from a
  # family/subfamily/tribe root (e.g. "Melolonthine BF01 Heteronyx", "Coccinellid BF01", "Dynastine
  # BF01") are, by convention, meant to signal the broader group they're derived from, not a specific
  # genus -- but most-specific-first ordering was resolving nearly all of them to a coincidentally
  # similar *genus* instead of the intended tribe/subfamily/family. `taxon_ranks_to_check_fuzzy` is the
  # broadest-first reverse of `taxon_ranks_to_check`, used only by the fuzzy blocks -- broader is no
  # worse than narrower for the genuinely coincidental collisions (a minority of the 52%, e.g. genus
  # "Adotela" vs unrelated order "Acoela"), and a real improvement for the systematic vernacular-suffix
  # majority. Genus-before-subgenus is preserved even under this reversal -- that exception is a
  # guaranteed nomenclatural convention, not a coincidental fuzzy collision, so it should stay put
  # regardless of which direction the rest of the order runs.
  taxon_ranks_to_check_fuzzy <- rev(taxon_ranks_to_check)
  genus_pos <- which(taxon_ranks_to_check_fuzzy == "genus")
  subgenus_pos <- which(taxon_ranks_to_check_fuzzy == "subgenus")
  if (length(genus_pos) == 1 && length(subgenus_pos) == 1 && subgenus_pos < genus_pos) {
    taxon_ranks_to_check_fuzzy[c(subgenus_pos, genus_pos)] <- taxon_ranks_to_check_fuzzy[c(genus_pos, subgenus_pos)]
  }

  # `pb` (NULL unless `progress = TRUE`) is threaded through every match block below via
  # redistribute_progress() (match_taxa_helpers.R), including into match_special_case_to_genus()'s own
  # internal checkpoints -- on.exit() guarantees it's closed on every exit path (the ~20 early returns
  # scattered through this function, not just the final one at the bottom).
  total_rows <- nrow(taxa$tocheck) + nrow(taxa$checked)
  pb <- if (progress) utils::txtProgressBar(min = 0, max = total_rows, style = 3) else NULL
  if (progress) on.exit(close(pb), add = TRUE)

  ## A function that specifies particular fuzzy matching conditions (for the
  ## function fuzzy_match_column) when matching is being done at the genus level.
  if (fuzzy_matches == TRUE) {
    fuzzy_match_genera <- function(x, y) {
      fuzzy_match_column(x, y, max_distance_abs = 2, max_distance_rel = 0.35)
    }
  } else {
    fuzzy_match_genera <- function(x, y) {
      fuzzy_match_column(x, y, max_distance_abs = 0, max_distance_rel = 0.0)
    }
  }

  ## set default imprecise fuzzy matching parameters
  imprecise_fuzzy_abs_dist <- 5
  imprecise_fuzzy_rel_dist <- 0.25

  ## override all fuzzy matching parameters with absolute and
  ## relative distances of 0 if fuzzy matching is turned off
  if (fuzzy_matches == FALSE) {
    fuzzy_abs_dist <- 0
    fuzzy_rel_dist <- 0
    imprecise_fuzzy_abs_dist <- 0
    imprecise_fuzzy_rel_dist <- 0
  }

  ## Repeatedly used identifier strings are created.
  ## These identifier strings are added to the aligned names of taxa that do
  ## not match to a species or infra-specific level name.
  taxa$tocheck <- taxa$tocheck |>
    dplyr::mutate(
      identifier_string = ifelse(is.na(identifier), NA_character_, paste0(" [", identifier, "]")),
      identifier_string2 = ifelse(is.na(identifier), NA_character_, paste0("; ", identifier)),
      aligned_name_tmp = NA_character_
    )

  ## In the tocheck dataframe, add columns with manipulated versions of the string to match
  ## Various stripped versions of the string to match, versions with 1, 2 and 3 words (genus, binomial, trinomial), and fuzzy-matched genera are propagated.
  taxa$tocheck <- taxa$tocheck |>
    dplyr::mutate(
      cleaned_name = cleaned_name |>
        update_na_with(APCalign::standardise_names(original_name)),
      stripped_name = stripped_name |>
        update_na_with(APCalign::strip_names(cleaned_name)),
      stripped_name2 = stripped_name2 |>
        update_na_with(APCalign::strip_names_extra(stripped_name)),
      trinomial = stringr::word(stripped_name2, start = 1, end = 3),
      binomial = stringr::word(stripped_name2, start = 1, end = 2),
      word_one = extract_genus(original_name),
      word_one_stripped = extract_genus(stripped_name),
      ignore_bracketed_words = stringr::str_remove(original_name, " \\(.*\\)")
    )

  ## Taxa that have been checked are moved from `taxa$tocheck` to `taxa$checked`
  ## These lines of code are repeated after each matching cycle to
  ## progressively move taxa from `tocheck` to `checked`

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # START MATCHES
  # match_01a: Scientific name matches
  # Taxon names that are an accepted scientific name, with authorship.

  i <-
    taxa$tocheck$original_name %in% resources$species$accepted$scientific_name

  ii <-
    match(
      taxa$tocheck[i,]$original_name,
      resources$species$accepted$scientific_name
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$accepted$taxonomic_dataset[ii],
      taxon_rank = resources$species$accepted$taxon_rank[ii],
      taxonomic_status = "accepted",
      taxon_ID = resources$species$accepted$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$accepted$accepted_name_usage_ID[ii],
      aligned_name = resources$species$accepted$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of taxon name to an accepted/valid scientific name (including authorship) in ", resources$species$accepted$taxonomic_dataset[ii], " (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_01a_accepted_scientific_name_with_authorship"
    )

  taxa <- redistribute_progress(taxa, pb)

  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_01b: Scientific name matches
  # Taxon names that are exact matches to a synonymmous scientific name, with authorship.

  i <-
    taxa$tocheck$original_name %in% resources$species$synonym$scientific_name

  ii <-
    match(
      taxa$tocheck[i,]$original_name,
      resources$species$synonym$scientific_name
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$synonym$taxonomic_dataset[ii],
      taxon_rank = resources$species$synonym$taxon_rank[ii],
      taxonomic_status = resources$species$synonym$taxonomic_status[ii],
      taxon_ID = resources$species$synonym$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$synonym$accepted_name_usage_ID[ii],
      aligned_name = resources$species$synonym$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of taxon name to a synonymous scientific name (including authorship) in ", resources$species$accepted$taxonomic_dataset[ii], " (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_01b_synonym_scientific_name_with_authorship"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_01c: Accepted/valid canonical name
  # Taxon names that are exact matches to canonical names, once filler words and punctuation are removed.
  i <-
    taxa$tocheck$cleaned_name %in% resources$species$accepted$canonical_name

  ii <-
    match(
      taxa$tocheck[i,]$cleaned_name,
      resources$species$accepted$canonical_name
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$accepted$taxonomic_dataset[ii],
      taxon_rank = resources$species$accepted$taxon_rank[ii],
      taxonomic_status = "accepted",
      taxon_ID = resources$species$accepted$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$accepted$accepted_name_usage_ID[ii],
      aligned_name = resources$species$accepted$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of taxon name to an accepted/valid canonical name in ", resources$species$accepted$taxonomic_dataset[ii], " once punctuation and filler words are removed (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_01c_accepted_canonical_name"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_01d: canonical name, synonyms
  # Taxon names that are exact matches to a synonymous canonical name once filler words and punctuation are removed.
  i <-
    taxa$tocheck$cleaned_name %in% resources$species$synonym$canonical_name

  ii <-
    match(
      taxa$tocheck[i,]$cleaned_name,
      resources$species$synonym$canonical_name
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$synonym$taxonomic_dataset[ii],
      taxon_rank = resources$species$synonym$taxon_rank[ii],
      taxonomic_status = resources$species$synonym$taxonomic_status[ii],
      taxon_ID = resources$species$synonym$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$synonym$accepted_name_usage_ID[ii],
      aligned_name = resources$species$synonym$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of taxon name to a synonymous canonical name in ", resources$species$accepted$taxonomic_dataset[ii], ", once punctuation and filler words are removed (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_01d_synonym_canonical_name"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)


  # match_02a: Higher level exact matches, retaining subgenus in brackets
  # Exact matches to higher level taxa for names where the final "word" is `sp` or `spp` and there is a subgenus term to retain
  # Aligned name includes identifier to indicate `genus (subgenus) sp.` refers to a specific species (or infra-specific taxon), associated with a specific dataset/location.
  # This is one of two ways a subgenus-rank match can be made -- the other, for input names that
  # write the subgenus alone (no genus prefix), is via the generic `taxon_ranks_to_check` loop below
  # (match_02b/12b/12c), against the plain `resources$subgenus` table.

  if (!is.null(resources$subgenus_v2)) {

    i <-
      stringr::str_detect(taxa$tocheck$cleaned_name, "[:space:]sp\\.$") &
      stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "^\\(") &
      stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "\\)$") &
      stringr::str_count(taxa$tocheck$cleaned_name, " ") == 2 &
      stringr::word(taxa$tocheck$cleaned_name, start = 1, end = 2) %in% resources$subgenus_v2$genus_and_subgenus

    ii <-
      match(
        stringr::word(taxa$tocheck[i,]$cleaned_name, start = 1, end = 2),
        resources$subgenus_v2$genus_and_subgenus
      )

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources$subgenus_v2$taxonomic_dataset[ii],
        taxon_rank = "subgenus",
        taxonomic_status = resources$subgenus_v2$taxonomic_status[ii],
        taxon_ID = resources$subgenus_v2$taxon_ID[ii],
        accepted_name_usage_ID = resources$subgenus_v2$accepted_name_usage_ID[ii],
        aligned_name_tmp = paste0(resources$subgenus_v2$genus_and_subgenus[ii], " sp."),
        aligned_name = ifelse(is.na(identifier_string),
                              aligned_name_tmp,
                              paste0(aligned_name_tmp, identifier_string)
        ),
        aligned_reason = paste0(
          "Exact match of taxon name ending with `sp.` to a ", taxonomic_status, taxon_rank, " in ",
          taxonomic_dataset,
          " (",
          Sys.Date(),
          ")"
        ),
        chars_changed = 0L,
        checked = TRUE,
        known = TRUE,
        alignment_code = "match_02a_exact_higher_level_accepted_or_synonym"
      )

    taxa <- redistribute_progress(taxa, pb)

    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_02y: quarantine a *bare* "Genus (Subgenus)" input -- exactly two whitespace-delimited tokens,
  # nothing beyond the bracketed subgenus itself -- before it can reach later, generic
  # species/genus-level matching. This has to run this early (right after match_02a, well before
  # match_05's species-level blocks), not only as a late fallback the way the old match_12a used to.
  #
  # Found via a real comparison of the same AusInvertTraits name list against two different resource
  # combinations (AFD+iNat vs AFD+GBIF): "Lasioglossum (Parasphecodes)" resolved correctly to subgenus
  # rank against one, but silently mis-resolved to an unrelated real SPECIES
  # ("Lasioglossum parasphecodum") against the other. Root cause: `cleaned_name` (computed from
  # `APCalign::standardise_names()` alone, before any stripping) keeps the "(Subgenus)" bracket intact
  # -- match_02a and this block correctly use it -- but `stripped_name`/`stripped_name2` (and hence
  # `binomial`/`trinomial`/`word_one_stripped`, which every earlier species-level block works off) only
  # strip the *parenthesis characters*, not the bracketed word itself: `APCalign::strip_names(
  # "Lasioglossum (Parasphecodes)")` returns `"lasioglossum parasphecodes"`, not `"lasioglossum"`. For a
  # *bare* bracketed name (no real species epithet at all), the subgenus name then sits exactly where a
  # species epithet would, and ordinary exact/fuzzy species-level matching can genuinely find a real,
  # unrelated species that happens to be a close spelling match to it.
  #
  # Deliberately scoped to *only* the bare, two-token case -- a genuine `"Genus (Subgenus) species"`
  # trinomial (a real species epithet actually present, e.g. the nominotypical-subgenus convention
  # `"Aporocera (Aporocera) t-viride"`, see test-match_taxa_typos.R) is already handled correctly and
  # safely further down by match_11a/match_11b's `ignore_bracketed_words` (computed from
  # `original_name` directly via `stringr::str_remove(original_name, " \\(.*\\)")`, which drops the
  # *entire* "(...)" -- parens and contents both -- rather than just the parenthesis characters, so it
  # never suffers the same false-epithet problem). Quarantining every bracketed name regardless of
  # length here would pre-empt that correct, later mechanism for no benefit -- confirmed by this
  # actually breaking that exact test when first tried.
  #
  # Detection is purely shape-based (a parenthesised second word, and nothing after it), not
  # membership-based, precisely so a pair *absent* from resources$subgenus_v2 (or resources with no
  # subgenus_v2 table at all) is still caught and safely quarantined rather than leaking through --
  # membership is only checked inside each resolution step below, the same detect_fn/resolution split
  # match_special_case_to_genus() uses.
  is_bracketed_subgenus <-
    stringr::str_count(taxa$tocheck$cleaned_name, " ") == 1 &
    stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "^\\(.*\\)$")

  if (any(is_bracketed_subgenus)) {

    if (!is.null(resources$subgenus_v2)) {

      # exact match against the bracketed "Genus (Subgenus)" pair itself
      i <- is_bracketed_subgenus &
        stringr::word(taxa$tocheck$cleaned_name, start = 1, end = 2) %in% resources$subgenus_v2$genus_and_subgenus
      ii <- match(
        stringr::word(taxa$tocheck[i, ]$cleaned_name, start = 1, end = 2),
        resources$subgenus_v2$genus_and_subgenus
      )

      # TRUE where the name being matched is *nothing more* than "Genus (Subgenus)" itself (exactly
      # two whitespace-delimited tokens) -- no species epithet, "sp." marker, morphospecies code, or
      # anything else. See ?match_taxa's include_bracketed_info.
      bare_rank_name <- !include_bracketed_info &
        stringr::str_count(stringr::str_trim(taxa$tocheck[i, ]$cleaned_name), "\\S+") == 2

      taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
        dplyr::mutate(
          taxonomic_dataset = resources$subgenus_v2$taxonomic_dataset[ii],
          taxon_rank = "subgenus",
          taxonomic_status = resources$subgenus_v2$taxonomic_status[ii],
          taxon_ID = resources$subgenus_v2$taxon_ID[ii],
          accepted_name_usage_ID = resources$subgenus_v2$accepted_name_usage_ID[ii],
          aligned_name_tmp = paste0(resources$subgenus_v2$genus_and_subgenus[ii], " sp. [", cleaned_name),
          aligned_name = dplyr::case_when(
            bare_rank_name ~ resources$subgenus_v2$genus_and_subgenus[ii],
            is.na(identifier_string2) ~ paste0(aligned_name_tmp, "]"),
            TRUE ~ paste0(aligned_name_tmp, identifier_string2, "]")
          ),
          aligned_reason = paste0(
            "Exact match of a bracketed genus (subgenus) to a ", taxonomic_status, " ", taxon_rank,
            " in ", taxonomic_dataset, " (", Sys.Date(), ")"
          ),
          chars_changed = 0L,
          checked = TRUE,
          known = TRUE,
          alignment_code = "match_02y_bracket_exact_subgenus"
        )
      taxa <- redistribute_progress(taxa, pb)

      if (nrow(taxa$tocheck) > 0) {

        # fuzzy match against the bracketed "Genus (Subgenus)" pair -- new; the old match_12a had no
        # fuzzy step at all, so a merely-misspelled subgenus bracket fell straight through into the
        # same species-level mis-parsing this whole block exists to prevent. Reuses the already-built
        # `fuzzy_match_genera()` closure (genus-level tolerance, and a no-op when `fuzzy_matches =
        # FALSE`) rather than inventing separate tolerance parameters for this one case.
        # recomputed against the current (post-exact-match, shrunk) taxa$tocheck, not the
        # outer-scope is_bracketed_subgenus from before that redistribute()
        is_bracketed_subgenus2 <-
          stringr::str_count(taxa$tocheck$cleaned_name, " ") == 1 &
          stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "^\\(.*\\)$")

        fuzzy_bracket <- rep(NA_character_, nrow(taxa$tocheck))
        if (any(is_bracketed_subgenus2)) {
          fuzzy_bracket[is_bracketed_subgenus2] <- fuzzy_match_genera(
            stringr::word(taxa$tocheck$cleaned_name[is_bracketed_subgenus2], start = 1, end = 2),
            resources$subgenus_v2$genus_and_subgenus
          )
        }
        i <- !is.na(fuzzy_bracket) & fuzzy_bracket %in% resources$subgenus_v2$genus_and_subgenus
        ii <- match(fuzzy_bracket[i], resources$subgenus_v2$genus_and_subgenus)

        bare_rank_name <- !include_bracketed_info &
          stringr::str_count(stringr::str_trim(taxa$tocheck[i, ]$cleaned_name), "\\S+") == 2

        taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
          dplyr::mutate(
            taxonomic_dataset = resources$subgenus_v2$taxonomic_dataset[ii],
            taxon_rank = "subgenus",
            taxonomic_status = resources$subgenus_v2$taxonomic_status[ii],
            taxon_ID = resources$subgenus_v2$taxon_ID[ii],
            accepted_name_usage_ID = resources$subgenus_v2$accepted_name_usage_ID[ii],
            aligned_name_tmp = paste0(resources$subgenus_v2$genus_and_subgenus[ii], " sp. [", cleaned_name),
            aligned_name = dplyr::case_when(
              bare_rank_name ~ resources$subgenus_v2$genus_and_subgenus[ii],
              is.na(identifier_string2) ~ paste0(aligned_name_tmp, "]"),
              TRUE ~ paste0(aligned_name_tmp, identifier_string2, "]")
            ),
            aligned_reason = paste0(
              "Fuzzy match of a bracketed genus (subgenus) to a ", taxonomic_status, " ", taxon_rank,
              " in ", taxonomic_dataset, " (", Sys.Date(), ")"
            ),
            chars_changed = as.integer(stringdist::stringdist(
              stringr::word(cleaned_name, start = 1, end = 2), fuzzy_bracket[i], method = "dl"
            )),
            checked = TRUE,
            known = TRUE,
            alignment_code = "match_02y_bracket_fuzzy_subgenus"
          )
        taxa <- redistribute_progress(taxa, pb)
      }
    }

    if (nrow(taxa$tocheck) == 0)
      return(taxa)

    # Anything still matching the bare-bracketed shape at this point has no usable subgenus match
    # (either resources$subgenus_v2 doesn't exist at all, or this specific pair isn't in it) -- fall
    # back to resolving just the *genus* part, via the same shared helper used for hybrids/intergrades,
    # rather than letting the bracketed subgenus word leak into species-level matching as a fake epithet.
    taxa <- match_special_case_to_genus(
      taxa, resources,
      detect_fn = function(cleaned_name) {
        stringr::str_count(cleaned_name, " ") == 1 &
          stringr::str_detect(stringr::word(cleaned_name, start = 2, end = 2), "^\\(.*\\)$")
      },
      bracket_sep = " sp. [",
      reason_text = paste(
        "Taxon name has a bracketed \"Genus (Subgenus)\" form whose subgenus could not be matched;",
        "falling back to genus rank."
      ),
      alignment_code_exact = "match_02y_bracket_genus_exact",
      alignment_code_fuzzy = "match_02y_bracket_genus_fuzzy",
      alignment_code_unresolved = "match_02y_bracket_genus_unresolved",
      alignment_code_no_resource = "match_02y_bracket_genus_no_resource",
      fuzzy_match_genera = fuzzy_match_genera,
      pb = pb
    )

    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_02b: Higher level exact matches
  # Exact matches to higher level taxa for names where the final "word" is `sp` or `spp`
  # Aligned name includes identifier to indicate `genus sp.`, `family sp.`, etc refers to a specific species (or infra-specific taxon), associated with a specific dataset/location.

  for (ranks in taxon_ranks_to_check) {

    i <-
      stringr::str_detect(taxa$tocheck$cleaned_name, "[:space:]sp\\.$") &
      taxa$tocheck$word_one_stripped %in% resources[[ranks]]$canonical_name &
      stringr::str_count(taxa$tocheck$cleaned_name, " ") == 2

    ii <-
      match(
        taxa$tocheck[i,]$word_one_stripped,
        resources[[ranks]]$canonical_name
      )

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources[[ranks]]$taxonomic_dataset[ii],
        taxon_rank = ranks,
        taxonomic_status = resources[[ranks]]$taxonomic_status[ii],
        taxon_ID = resources[[ranks]]$taxon_ID[ii],
        accepted_name_usage_ID = resources[[ranks]]$accepted_name_usage_ID[ii],
        aligned_name_tmp = paste0(resources[[ranks]]$word_one_stripped[ii], " sp."),
        aligned_name = ifelse(is.na(identifier_string),
                              aligned_name_tmp,
                              paste0(aligned_name_tmp, identifier_string)
        ),
        aligned_reason = paste0(
          "Exact match of taxon name ending with `sp.` to a ", taxonomic_status, taxon_rank, " in ",
          taxonomic_dataset,
          " (",
          Sys.Date(),
          ")"
        ),
        chars_changed = 0L,
        checked = TRUE,
        known = TRUE,
        alignment_code = "match_02b_exact_higher_level_accepted_or_synonym"
      )

    taxa <- redistribute_progress(taxa, pb)

    if (nrow(taxa$tocheck) == 0)
    return(taxa)

  }

  # match_02z: English vernacular name-ending substitution (issue #12; opt-in via
  # `consider_english_name_endings`, default FALSE). Real invertebrate morphospecies/voucher codes
  # commonly use an informal English adjective form derived from a family/subfamily/superfamily root,
  # which by convention is meant to signal that broader group, not any specific genus -- e.g.
  # "Coccinellid BF01" (family Coccinellidae), "Melolonthine BF01 Heteronyx" (subfamily Melolonthinae),
  # "Curculionoid sp." (superfamily Curculionoidea). Left to ordinary fuzzy matching, names like these
  # almost always resolved to a coincidentally-similar but unrelated *genus* instead -- confirmed
  # empirically, not theoretically: checked against a real, large combined reference and the full real
  # AusInvertTraits name list, 52% of names resolved via a fuzzy higher-rank match *also* fuzzy-matched
  # a real candidate at a different rank, and the large majority of those were this exact systematic
  # pattern. Tried here, before any fuzzy matching, as an *exact* match on the corrected name -- safer
  # than fuzzy matching or reordering alone, since it only ever succeeds when the corrected name is a
  # real, present taxon, and costs nothing (falls through to ordinary fuzzy matching unchanged) when it
  # isn't. Placed after match_02b (so a name that's already an exact match to something real never
  # reaches this substitution logic at all) and before match_02c/match_12c (so it gets first refusal,
  # covering both the "ends in sp." and generic fuzzy-fallback cases in one place).
  if (consider_english_name_endings) {
    # (vernacular ending, formal Latin ending, target rank) -- tribe ("-ini") and subtribe ("-ina")
    # endings are already the formal Latin form, so no vernacular variant is needed for those.
    english_ending_substitutions <- list(
      list(vernacular = "id$", formal = "idae", rank = "family"),
      list(vernacular = "ine$", formal = "inae", rank = "subfamily"),
      list(vernacular = "oid$", formal = "oidea", rank = "superfamily")
    )

    for (sub in english_ending_substitutions) {
      if (!sub$rank %in% names(resources)) next

      candidate <- stringr::str_replace(
        taxa$tocheck$word_one_stripped, stringr::regex(sub$vernacular, ignore_case = TRUE), sub$formal
      )

      i <- !is.na(candidate) & candidate != taxa$tocheck$word_one_stripped &
        candidate %in% resources[[sub$rank]]$canonical_name

      ii <- match(candidate[i], resources[[sub$rank]]$canonical_name)

      # see ?match_taxa's include_bracketed_info -- a bare, unbracketed rank name is used whenever the
      # name being matched is nothing more than the single (vernacular-suffixed) token itself
      bare_rank_name <- !include_bracketed_info &
        stringr::str_count(stringr::str_trim(taxa$tocheck[i, ]$cleaned_name), "\\S+") == 1

      taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
        dplyr::mutate(
          taxonomic_dataset = resources[[sub$rank]]$taxonomic_dataset[ii],
          taxon_rank = sub$rank,
          taxonomic_status = resources[[sub$rank]]$taxonomic_status[ii],
          taxon_ID = resources[[sub$rank]]$taxon_ID[ii],
          accepted_name_usage_ID = resources[[sub$rank]]$accepted_name_usage_ID[ii],
          aligned_name_tmp = paste0(candidate[i], " sp. [", cleaned_name),
          aligned_name = dplyr::case_when(
            bare_rank_name ~ candidate[i],
            is.na(identifier_string2) ~ paste0(aligned_name_tmp, "]"),
            TRUE ~ paste0(aligned_name_tmp, identifier_string2, "]")
          ),
          aligned_reason = paste0(
            "Matched by substituting the English vernacular name ending for the formal one (\"",
            word_one_stripped, "\" -> \"", candidate[i], "\") to a ", taxonomic_status, " ", taxon_rank,
            " in ", taxonomic_dataset, " (", Sys.Date(), ")"
          ),
          chars_changed = 0L,
          known = TRUE,
          checked = TRUE,
          alignment_code = "match_02z_english_ending_accepted"
        )

      taxa <- redistribute_progress(taxa, pb)
      if (nrow(taxa$tocheck) == 0) return(taxa)
    }
  }

  # match_02c: Higher-level resolution
  # Fuzzy matches of accepted higher-level names where the final "word" is `sp` or `spp` and
  # there isn't an exact match to an accepted higher-level name
  # Aligned name includes identifier to indicate `genus sp.` refers to a specific species (or infra-specific taxon), associated with a specific dataset/location.
  # Broadest-first (taxon_ranks_to_check_fuzzy, not taxon_ranks_to_check) -- see that variable's own
  # comment above.

  for (ranks in taxon_ranks_to_check_fuzzy) {
    taxa$tocheck <- taxa$tocheck |>
      dplyr::mutate(
        fuzzy_match_genus =
          fuzzy_match_genera(word_one_stripped, resources[[ranks]]$canonical_name)
      )

    i <-
      stringr::str_detect(taxa$tocheck$cleaned_name, "[:space:]sp\\.$") &
      taxa$tocheck$fuzzy_match_genus %in% resources[[ranks]]$canonical_name

    ii <-
      match(
        taxa$tocheck[i,]$fuzzy_match_genus,
        resources[[ranks]]$canonical_name
      )

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources[[ranks]]$taxonomic_dataset[ii],
        taxon_rank = ranks,
        taxonomic_status = resources[[ranks]]$taxonomic_status[ii],
        taxon_ID = resources[[ranks]]$taxon_ID[ii],
        accepted_name_usage_ID = resources[[ranks]]$accepted_name_usage_ID[ii],
        aligned_name_tmp =
          paste0(resources[[ranks]]$canonical_name[ii], " sp."),
        aligned_name = ifelse(is.na(identifier_string),
                              aligned_name_tmp,
                              paste0(aligned_name_tmp, identifier_string)
        ),
        aligned_reason = paste0(
          "Exact match of taxon name ending with `sp.` to a ", taxonomic_status, taxon_rank, " in ",
          taxonomic_dataset,
          " (",
          Sys.Date(),
          ")"
        ),
        chars_changed = as.integer(stringdist::stringdist(word_one_stripped, fuzzy_match_genus, method = "dl")),
        known = TRUE,
        checked = TRUE,
        alignment_code = "match_02c_fuzzy_genus_accepted"
      )

    taxa <- redistribute_progress(taxa, pb)
    if (nrow(taxa$tocheck) == 0)
      return(taxa)

  }

  # match_03: hybrid names (`Genus x species`) can only be aligned to genus rank -- placed here,
  # before general species-level fuzzy matching gets a chance to, since a name containing ' x ' is
  # definitively not an ordinary binomial regardless of whether it would coincidentally fuzzy-match
  # something. Opt-in (off by default) -- see `?match_taxa`.
  if (hybrids) {
    is_hybrid <- function(cleaned_name) stringr::str_detect(cleaned_name, " [xX] ")

    taxa <- match_special_case_to_genus(
      taxa, resources,
      detect_fn = is_hybrid,
      bracket_sep = " x [",
      reason_text = "Taxon name includes ' x ', indicating a hybrid taxon; can only be aligned to genus rank.",
      alignment_code_exact = "match_03a_hybrid_exact_genus",
      alignment_code_fuzzy = "match_03b_hybrid_fuzzy_genus",
      alignment_code_unresolved = "match_03c_hybrid_unresolved",
      alignment_code_no_resource = "match_03d_hybrid_no_genus_resource",
      fuzzy_match_genera = fuzzy_match_genera,
      pb = pb
    )
    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_04: intergrade (double dash) and indecision (slash) names can only be aligned to genus rank
  # -- placed here, early, before any species-level matching, since neither pattern character ("--",
  # "/") can ever appear inside a real species epithet, so there's no ambiguity and no benefit to
  # delaying them. (The third pattern family this toggle also covers -- a graded/"affinis"/"cf."
  # identification -- is handled separately, right below, since it needs its own explicit exact-match
  # step first rather than just relying on this early placement. Issue #16.)
  if (intergrades_affinis) {
    is_intergrade_indecision <- function(cleaned_name) {
      is_intergrade <- stringr::str_detect(cleaned_name, "\\ -- |\\--")
      is_indecision <- (stringr::str_detect(cleaned_name, "[:alpha:]\\/") |
                           stringr::str_detect(cleaned_name, "\\s\\/")) &
        !stringr::str_detect(cleaned_name, "[:digit:]") &
        !stringr::str_detect(cleaned_name, "\\(") &
        !stringr::str_detect(cleaned_name, "\\'")
      is_intergrade | is_indecision
    }

    taxa <- match_special_case_to_genus(
      taxa, resources,
      detect_fn = is_intergrade_indecision,
      bracket_sep = " sp. [",
      reason_text = "Taxon name suggests an intergrade or an indecision between taxa; can only be aligned to genus rank.",
      alignment_code_exact = "match_04a_intergrade_affinis_exact_genus",
      alignment_code_fuzzy = "match_04b_intergrade_affinis_fuzzy_genus",
      alignment_code_unresolved = "match_04c_intergrade_affinis_unresolved",
      alignment_code_no_resource = "match_04d_intergrade_affinis_no_genus_resource",
      fuzzy_match_genera = fuzzy_match_genera,
      pb = pb
    )
    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_04e-j: a graded/"affinis"/"cf." identification -- also placed early (same position as
  # match_04's intergrade/indecision above), but unlike those two patterns, this one performs its own
  # explicit, untruncated exact-match check first, before ever falling back to genus. (Issue #16.)
  #
  # "affinis" is genuinely ambiguous in a way "--" and "/" are not: it's both an affinity qualifier
  # ("Acacia affinis dealbata" = "resembles A. dealbata, not confidently identified") *and* a
  # legitimate specific epithet in its own right ("Gomphrena affinis subsp. pilbarensis" is a real,
  # accepted name) -- and critically, a *repeated* bare epithet ("Themognatha affinis affinis", the
  # zoological tautonym convention for a nominotypical subspecies) is genuinely indistinguishable from
  # the qualifier reading by text shape alone, since "affinis" is also just a common, real epithet.
  # `APCalign::standardise_names()` unconditionally abbreviates a bare "affinis" (not immediately
  # followed by an infraspecific rank marker) to "aff." -- so "Themognatha affinis affinis" becomes
  # "Themognatha aff. affinis" in `cleaned_name` regardless of this toggle, indistinguishable from a
  # genuine hedge by text shape alone. Guessing "a repeated word must mean the tautonym" would be just
  # as wrong in the other direction -- it would silently upgrade a genuine, deliberately uncertain
  # hedge to a false, over-confident subspecies match.
  #
  # The fix is to not guess at all: let a real, resource-verified exact match win first, using the same
  # *untruncated* field match_11a/match_11b use (`ignore_bracketed_words`, built straight from
  # `original_name`, never touched by the "aff." abbreviation). This deliberately does NOT just rely on
  # running after match_09/match_10 (trinomial/binomial exact matching) instead -- confirmed via a real
  # APC-equivalence-test failure that those blocks aren't safe evidence for this specific ambiguity:
  # `binomial`/`trinomial` are truncated to the first 2-3 words of the *already-abbreviated*
  # `stripped_name2`, and real reference data can have its own informally-named placeholder entries
  # using the same "sp. aff. X" convention (a real APC entry, "Acacia sp. aff. rigens (Gerang Gerung)",
  # reduces to the same truncated "acacia aff" binomial as *any* fabricated "Acacia aff. <anything>"
  # query once stripped) -- so a truncated exact "match" there is coincidence, not evidence the query
  # is a real, listed name. The untruncated `ignore_bracketed_words` field doesn't have this problem
  # (the whole string has to match, not just a truncated prefix), so it's the only field trusted here.
  if (intergrades_affinis) {
    not_before_rank_marker <- "(?!\\s+(?:subsp|ssp|subvar|var|forma|form|ser|series|cv|f)\\.?(?:\\s|$))"
    affinis_qualifier <- paste0(" affinis", not_before_rank_marker, "\\s")

    is_affinis <- function(cleaned_name) {
      stringr::str_detect(cleaned_name, "[Aa]ff[\\.\\s]") |
        stringr::str_detect(cleaned_name, affinis_qualifier) |
        stringr::str_detect(cleaned_name, " cf[\\.\\s]")
    }

    # match_04e: exact match (ignoring brackets) to an accepted species/infraspecific name
    i <- is_affinis(taxa$tocheck$cleaned_name) &
      taxa$tocheck$ignore_bracketed_words %in% resources$species$accepted$canonical_name
    ii <- match(taxa$tocheck[i, ]$ignore_bracketed_words, resources$species$accepted$canonical_name)
    taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
      dplyr::mutate(
        taxonomic_dataset = resources$species$accepted$taxonomic_dataset[ii],
        taxon_rank = resources$species$accepted$taxon_rank[ii],
        taxonomic_status = resources$species$accepted$taxonomic_status[ii],
        taxon_ID = resources$species$accepted$taxon_ID[ii],
        accepted_name_usage_ID = resources$species$accepted$accepted_name_usage_ID[ii],
        aligned_name = resources$species$accepted$canonical_name[ii],
        aligned_reason = paste0(
          "Taxon name suggests a graded/\"affinis\"/\"cf.\" identification, but exactly matches a real, ",
          "accepted name (ignoring brackets) in ", taxonomic_dataset, " -- resolved to that name rather ",
          "than treated as an uncertain identification (", Sys.Date(), ")"
        ),
        chars_changed = 0L,
        known = TRUE,
        checked = TRUE,
        alignment_code = "match_04e_affinis_exact_species_accepted"
      )
    taxa <- redistribute_progress(taxa, pb)

    if (nrow(taxa$tocheck) > 0) {
      # match_04f: exact match (ignoring brackets) to a synonymous species/infraspecific name
      i <- is_affinis(taxa$tocheck$cleaned_name) &
        taxa$tocheck$ignore_bracketed_words %in% resources$species$synonym$canonical_name
      ii <- match(taxa$tocheck[i, ]$ignore_bracketed_words, resources$species$synonym$canonical_name)
      taxa$tocheck[i, ] <- taxa$tocheck[i, ] |>
        dplyr::mutate(
          taxonomic_dataset = resources$species$synonym$taxonomic_dataset[ii],
          taxon_rank = resources$species$synonym$taxon_rank[ii],
          taxonomic_status = resources$species$synonym$taxonomic_status[ii],
          taxon_ID = resources$species$synonym$taxon_ID[ii],
          accepted_name_usage_ID = resources$species$synonym$accepted_name_usage_ID[ii],
          aligned_name = resources$species$synonym$canonical_name[ii],
          aligned_reason = paste0(
            "Taxon name suggests a graded/\"affinis\"/\"cf.\" identification, but exactly matches a real, ",
            "synonymous name (ignoring brackets) in ", taxonomic_dataset, " -- resolved to that name ",
            "rather than treated as an uncertain identification (", Sys.Date(), ")"
          ),
          chars_changed = 0L,
          known = TRUE,
          checked = TRUE,
          alignment_code = "match_04f_affinis_exact_species_synonym"
        )
      taxa <- redistribute_progress(taxa, pb)
    }

    if (nrow(taxa$tocheck) == 0)
      return(taxa)

    # match_04g-j: anything still matching the affinis/cf. pattern here has no exact species-level
    # match, so it really is an uncertain identification -- fall back to genus rank via the shared
    # helper, exactly as intergrade/indecision above.
    taxa <- match_special_case_to_genus(
      taxa, resources,
      detect_fn = is_affinis,
      bracket_sep = " sp. [",
      reason_text = paste(
        "Taxon name suggests a graded/\"affinis\"/\"cf.\" identification (and isn't an exact match to a",
        "real, listed name); can only be aligned to genus rank."
      ),
      alignment_code_exact = "match_04g_affinis_exact_genus",
      alignment_code_fuzzy = "match_04h_affinis_fuzzy_genus",
      alignment_code_unresolved = "match_04i_affinis_unresolved",
      alignment_code_no_resource = "match_04j_affinis_no_genus_resource",
      fuzzy_match_genera = fuzzy_match_genera,
      pb = pb
    )
    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_05a: fuzzy match to accepted/valid canonical name
  # Fuzzy match of taxon name to an accepted canonical name, once filler words and punctuation are removed.
  taxa$tocheck$fuzzy_match_cleaned <- fuzzy_match_column(
    x = taxa$tocheck$stripped_name,
    accepted_list = resources$species$accepted$stripped_canonical,
    max_distance_abs = fuzzy_abs_dist,
    max_distance_rel = fuzzy_rel_dist
  )

  i <-
    taxa$tocheck$fuzzy_match_cleaned %in% resources$species$accepted$stripped_canonical

  ii <-
    match(
      taxa$tocheck[i,]$fuzzy_match_cleaned,
      resources$species$accepted$stripped_canonical
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$accepted$taxonomic_dataset[ii],
      taxon_rank = resources$species$accepted$taxon_rank[ii],
      taxonomic_status = resources$species$accepted$taxonomic_status[ii],
      taxon_ID = resources$species$accepted$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$accepted$accepted_name_usage_ID[ii],
      aligned_name = resources$species$accepted$canonical_name[ii],
      aligned_reason = paste0(
        "Fuzzy match of taxon name to an accepted canonical name in ", taxonomic_dataset, " once punctuation and filler words are removed (",
        Sys.Date(),
        ")"
      ),
      chars_changed = as.integer(stringdist::stringdist(stripped_name, fuzzy_match_cleaned, method = "dl")),
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_05a_fuzzy_accepted_canonical_name"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_05b: fuzzy match to synonymous canonical name
  # Fuzzy match of taxon name to an synonymous canonical name, once filler words and punctuation are removed.
  taxa$tocheck$fuzzy_match_cleaned_synonym <- fuzzy_match_column(
    x = taxa$tocheck$stripped_name,
    accepted_list = resources$species$synonym$stripped_canonical,
    max_distance_abs = fuzzy_abs_dist,
    max_distance_rel = fuzzy_rel_dist
  )

  i <-
    taxa$tocheck$fuzzy_match_cleaned_synonym %in% resources$species$synonym$stripped_canonical

  ii <-
    match(
      taxa$tocheck[i,]$fuzzy_match_cleaned_synonym,
      resources$species$synonym$stripped_canonical
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$synonym$taxonomic_dataset[ii],
      taxon_rank = resources$species$synonym$taxon_rank[ii],
      taxonomic_status = resources$species$synonym$taxonomic_status[ii],
      taxon_ID = resources$species$synonym$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$synonym$accepted_name_usage_ID[ii],
      aligned_name = resources$species$synonym$canonical_name[ii],
      aligned_reason = paste0(
        "Fuzzy match of taxon name to a synonymous canonical name in ", taxonomic_dataset, " once punctuation and filler words are removed (",
        Sys.Date(),
        ")"
      ),
      chars_changed = as.integer(stringdist::stringdist(stripped_name, fuzzy_match_cleaned_synonym, method = "dl")),
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_05b_fuzzy_synonym_canonical_name"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_09a: exact trinomial matches, accepted
  # Exact match of first three words of taxon name ("trinomial") to an accepted canonical name.
  # The purpose of matching only the first three words only to an accepted names is that
  # sometimes the submitted taxon name is a valid trinomial + notes and
  # such names will only be aligned by matches considering only the first three words of the stripped name.
  i <-
    taxa$tocheck$trinomial %in% resources$species$accepted$trinomial

  ii <-
    match(
      taxa$tocheck[i,]$trinomial,
      resources$species$accepted$trinomial
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$accepted$taxonomic_dataset[ii],
      taxon_rank = resources$species$accepted$taxon_rank[ii],
      taxonomic_status = resources$species$accepted$taxonomic_status[ii],
      taxon_ID = resources$species$accepted$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$accepted$accepted_name_usage_ID[ii],
      aligned_name = resources$species$accepted$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of the first three words of the taxon name to an accepted canonical name (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_09a_trinomial_exact_accepted"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_09b: exact trinomial matches, synonyms
  # Exact match of first three words of taxon name ("trinomial") to a synonymous canonical name.
  i <-
    taxa$tocheck$trinomial %in% resources$species$synonym$trinomial

  ii <-
    match(
      taxa$tocheck[i,]$trinomial,
      resources$species$synonym$trinomial
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$synonym$taxonomic_dataset[ii],
      taxon_rank = resources$species$synonym$taxon_rank[ii],
      taxonomic_status = resources$species$synonym$taxonomic_status[ii],
      taxon_ID = resources$species$synonym$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$synonym$accepted_name_usage_ID[ii],
      aligned_name = resources$species$synonym$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of the first three words of the taxon name to a synonymous canonical name (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_09b_trinomial_exact_synonym"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_10a: exact binomial matches, accepted
  # Exact match of first two words of taxon name ("binomial") to an accepted canonical name.
  # The purpose of matching only the first two words only to an accepted names is that
  # sometimes the submitted taxon name is a valid binomial + notes
  # or a valid binomial + invalid infraspecific epithet.

  i <-
    taxa$tocheck$binomial %in% resources$species$accepted$binomial &
    # needed to avoid names with subgenus in brackets - in that case a binomial means nothing
    !stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "^\\(") &
    !stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "\\)$")

  ii <-
    match(
      taxa$tocheck[i,]$binomial,
      resources$species$accepted$binomial
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$accepted$taxonomic_dataset[ii],
      taxon_rank = resources$species$accepted$taxon_rank[ii],
      taxonomic_status = resources$species$accepted$taxonomic_status[ii],
      taxon_ID = resources$species$accepted$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$accepted$accepted_name_usage_ID[ii],
      aligned_name = resources$species$accepted$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of the first two words of the taxon name to an accepted canonical name (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_10a_binomial_exact_accepted"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_10b: exact binomial matches, synonyms
  # Exact match of first two words of taxon name ("binomial") to a synonymous canonical name.

  i <-
    taxa$tocheck$binomial %in% resources$species$synonym$binomial &
    # needed to avoid names with subgenus in brackets - in that case a binomial means nothing
    !stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "^\\(") &
    !stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "\\)$")

  ii <-
    match(
      taxa$tocheck[i,]$binomial,
      resources$species$synonym$binomial
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$synonym$taxonomic_dataset[ii],
      taxon_rank = resources$species$synonym$taxon_rank[ii],
      taxonomic_status = resources$species$synonym$taxonomic_status[ii],
      taxon_ID = resources$species$synonym$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$synonym$accepted_name_usage_ID[ii],
      aligned_name = resources$species$synonym$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of the first two words of the taxon name to a synonymous canonical name (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_10b_binomial_exact_synonym"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_11a: exact matches ignoring bracketed words (accepted/valid)

  i <-
    taxa$tocheck$ignore_bracketed_words %in% resources$species$accepted$canonical_name

  ii <-
    match(
      taxa$tocheck[i,]$ignore_bracketed_words,
      resources$species$accepted$canonical_name
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$accepted$taxonomic_dataset[ii],
      taxon_rank = resources$species$accepted$taxon_rank[ii],
      taxonomic_status = resources$species$accepted$taxonomic_status[ii],
      taxon_ID = resources$species$accepted$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$accepted$accepted_name_usage_ID[ii],
      aligned_name = resources$species$accepted$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of the first two words of the taxon name to an accepted canonical name, ignoring brackets (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_11a_no_brackets_accepted"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_11b: exact matches ignoring bracketed words (synonyms)

  i <-
    taxa$tocheck$ignore_bracketed_words %in% resources$species$synonym$canonical_name

  ii <-
    match(
      taxa$tocheck[i,]$ignore_bracketed_words,
      resources$species$synonym$canonical_name
    )

  taxa$tocheck[i,] <- taxa$tocheck[i,] |>
    dplyr::mutate(
      taxonomic_dataset = resources$species$synonym$taxonomic_dataset[ii],
      taxon_rank = resources$species$synonym$taxon_rank[ii],
      taxonomic_status = resources$species$synonym$taxonomic_status[ii],
      taxon_ID = resources$species$synonym$taxon_ID[ii],
      accepted_name_usage_ID = resources$species$synonym$accepted_name_usage_ID[ii],
      aligned_name = resources$species$synonym$canonical_name[ii],
      aligned_reason = paste0(
        "Exact match of to a synonymous canonical name recorded in ", taxonomic_dataset,
        "when any bracketed words are removed (",
        Sys.Date(),
        ")"
      ),
      chars_changed = 0L,
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_11b_no_brackets_synonym"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_12a: subgenus alignment with bracketed subgenera, unconditional on trailing content
  # Toward the end of the alignment function, see if the first two words of an unmatched taxon are a
  # "Genus (Subgenus)" pair in one of the taxonomic references. Unlike match_02y above (which only
  # quarantines a *bare* two-token "Genus (Subgenus)" early, before species-level matching gets a
  # chance), this block deliberately has NO restriction on what follows the bracket -- it's what's left
  # once every species-level exact block (match_05/09/10/11) has already had first refusal and failed,
  # so recognising the genus/subgenus pair here is strictly better than falling through further to
  # match_12b's genus-only fallback and silently losing subgenus-level specificity. Needed for e.g. a
  # real "Genus (Subgenus) unmatched_epithet" query where the epithet genuinely isn't in the reference
  # (so no species block can ever succeed) but the subgenus pair itself is -- see
  # test-load_taxonomic_resources.R's "namespaces taxon_ID by rank..." test.

  if (!is.null(resources$subgenus_v2)) {

    i <-
      stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "^\\(") &
      stringr::str_detect(stringr::word(taxa$tocheck$cleaned_name, start = 2, end = 2), "\\)$") &
      stringr::word(taxa$tocheck$cleaned_name, start = 1, end = 2) %in% resources$subgenus_v2$genus_and_subgenus

    ii <-
      match(
        stringr::word(taxa$tocheck[i,]$cleaned_name, start = 1, end = 2),
        resources$subgenus_v2$genus_and_subgenus
      )

    # TRUE where the name being matched is *nothing more* than "Genus (Subgenus)" itself (exactly two
    # whitespace-delimited tokens -- the bracketed part counts as its own token) -- no species epithet,
    # "sp." marker, morphospecies code, or anything else. See ?match_taxa's include_bracketed_info.
    # In practice this case is now caught earlier by match_02y, so bare_rank_name is normally FALSE by
    # the time a row reaches here -- kept as a defensive fallback, not relied on as the primary gate.
    bare_rank_name <- !include_bracketed_info &
      stringr::str_count(stringr::str_trim(taxa$tocheck[i,]$cleaned_name), "\\S+") == 2

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources$subgenus_v2$taxonomic_dataset[ii],
        taxon_rank = "subgenus",
        taxonomic_status = resources$subgenus_v2$taxonomic_status[ii],
        taxon_ID = resources$subgenus_v2$taxon_ID[ii],
        accepted_name_usage_ID = resources$subgenus_v2$accepted_name_usage_ID[ii],
        aligned_name_tmp = paste0(resources$subgenus_v2$genus_and_subgenus[ii], " sp. [", cleaned_name),
        aligned_name = dplyr::case_when(
          bare_rank_name ~ resources$subgenus_v2$genus_and_subgenus[ii],
          is.na(identifier_string2) ~ paste0(aligned_name_tmp, "]"),
          TRUE ~ paste0(aligned_name_tmp, identifier_string2, "]")
        ),
        aligned_reason = paste0(
          "Exact match a genus (subgenus) to a ", taxon_rank, " in ", taxonomic_dataset, " (",
          Sys.Date(),
          ")"
        ),
        chars_changed = 0L,
        checked = TRUE,
        known = TRUE,
        alignment_code = "match_12a_exact_subgenus_accepted_or_synonym"
      )

    taxa <- redistribute_progress(taxa, pb)

    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_12b: higher-level alignment
  # Toward the end of the alignment function, see if first word of unmatched taxa is a
  # higher order taxon name in one of the taxonomic references.
  # The 'taxon name' is then reformatted as `genus sp.` with the original name in square brackets.
  for (ranks in taxon_ranks_to_check) {

   i <-
    taxa$tocheck$word_one_stripped %in% resources[[ranks]]$word_one_stripped

    ii <-
      match(
        taxa$tocheck[i,]$word_one_stripped,
        resources[[ranks]]$word_one_stripped
      )

    # TRUE where the name being matched is *nothing more* than this rank's own name -- a single
    # whitespace-delimited token, no epithet/"sp."/morphospecies code/etc. beyond it. See ?match_taxa's
    # include_bracketed_info.
    bare_rank_name <- !include_bracketed_info &
      stringr::str_count(stringr::str_trim(taxa$tocheck[i,]$cleaned_name), "\\S+") == 1

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources[[ranks]]$taxonomic_dataset[ii],
        taxon_rank = ranks,
        taxonomic_status = resources[[ranks]]$taxonomic_status[ii],
        taxon_ID = resources[[ranks]]$taxon_ID[ii],
        accepted_name_usage_ID = resources[[ranks]]$accepted_name_usage_ID[ii],
        aligned_name_tmp = paste0(resources[[ranks]]$word_one_stripped[ii], " sp. [", cleaned_name),
        aligned_name = dplyr::case_when(
          bare_rank_name ~ resources[[ranks]]$word_one_stripped[ii],
          is.na(identifier_string2) ~ paste0(aligned_name_tmp, "]"),
          TRUE ~ paste0(aligned_name_tmp, identifier_string2, "]")
        ),
        aligned_reason = paste0(
          "Exact match of the first word of the taxon name to a ", taxon_rank, " in ", taxonomic_dataset, " (",
          Sys.Date(),
          ")"
        ),
        chars_changed = 0L,
        known = TRUE,
        checked = TRUE,
        alignment_code = "match_12b_higher_rank_exact_accepted"
      )

    taxa <- redistribute_progress(taxa, pb)
    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_12c: higher-level fuzzy alignment
  # The final alignment step is to see if a fuzzy match can be made for the first word of unmatched taxa to an
  # higher order taxon name in one of the taxonomic references.
  # The 'taxon name' is then reformatted as `genus sp.` with the original name in square brackets.
  # Broadest-first (taxon_ranks_to_check_fuzzy, not taxon_ranks_to_check) -- see that variable's own
  # comment above.
  for (ranks in taxon_ranks_to_check_fuzzy) {
    # `fuzzy_match_genus` must be recomputed fresh against *this* rank's word_one_stripped on every
    # iteration -- reusing whatever match_02c's loop last left it as (whichever rank happened to be
    # last in taxon_ranks_to_check, not necessarily this one) meant this block only ever fuzzy-matched
    # correctly by coincidence. Found via real AusInvertTraits data: morphospecies "voucher code" names
    # like "Aderid BF05" should fuzzy-match the tribe "Aderini" (distance 2, well within tolerance) but
    # didn't, because fuzzy_match_genus held a stale result against an unrelated, usually near-empty
    # rank instead.
    taxa$tocheck <- taxa$tocheck |>
      dplyr::mutate(
        fuzzy_match_genus = fuzzy_match_genera(word_one_stripped, resources[[ranks]]$word_one_stripped)
      )

    i <-
      taxa$tocheck$fuzzy_match_genus %in% resources[[ranks]]$word_one_stripped

    # `ii` must look up the *fuzzy match result* (fuzzy_match_genus), not the original query's own
    # word_one_stripped -- the original word is (by definition, since this is the fuzzy fallback) not
    # itself present in resources[[ranks]], so looking it up here always returned NA, silently
    # corrupting every match this block did find via `i` with entirely blank taxonomic_dataset/
    # taxon_ID/etc. columns.
    ii <-
      match(
        taxa$tocheck[i,]$fuzzy_match_genus,
        resources[[ranks]]$word_one_stripped
      )

    # TRUE where the name being matched is *nothing more* than a single (mis-spelled) token fuzzy-matching
    # this rank's own name -- see ?match_taxa's include_bracketed_info.
    bare_rank_name <- !include_bracketed_info &
      stringr::str_count(stringr::str_trim(taxa$tocheck[i,]$cleaned_name), "\\S+") == 1

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources[[ranks]]$taxonomic_dataset[ii],
        taxon_rank = ranks,
        taxonomic_status = resources[[ranks]]$taxonomic_status[ii],
        taxon_ID = resources[[ranks]]$taxon_ID[ii],
        accepted_name_usage_ID = resources[[ranks]]$accepted_name_usage_ID[ii],
        aligned_name_tmp = paste0(fuzzy_match_genus, " sp. [", cleaned_name),
        aligned_name = dplyr::case_when(
          bare_rank_name ~ fuzzy_match_genus,
          is.na(identifier_string2) ~ paste0(aligned_name_tmp, "]"),
          TRUE ~ paste0(aligned_name_tmp, identifier_string2, "]")
        ),
        aligned_reason = paste0(
          "Fuzzy match of the first word of the taxon name to a ", taxon_rank, " in ", taxonomic_dataset, " (",
          Sys.Date(),
          ")"
        ),
        chars_changed = as.integer(stringdist::stringdist(word_one_stripped, fuzzy_match_genus, method = "dl")),
        known = TRUE,
        checked = TRUE,
        alignment_code = "match_12c_higher_rank_fuzzy_accepted"
      )

    taxa <- redistribute_progress(taxa, pb)
    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  taxa$tocheck <- taxa$tocheck |> dplyr::select(-identifier_string, -identifier_string2, -aligned_name_tmp)
  taxa$checked <- taxa$checked |> dplyr::select(-identifier_string, -identifier_string2, -aligned_name_tmp)

  taxa
}
