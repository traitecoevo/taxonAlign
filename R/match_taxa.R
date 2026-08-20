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
#'  "affinis"/"cf." identification (`"aff."`, `"affinis"`, `"cf."`) is resolved to genus rank the same
#'  way. Defaults to `FALSE`.
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
    identifier = NA_character_,
    include_bracketed_info = FALSE,
    progress = FALSE
) {

  if (is.null(taxon_ranks_to_check)) {
    taxon_ranks_to_check <- setdiff(names(resources), c("species", "subgenus_v2"))
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
        checked = TRUE,
        known = TRUE,
        alignment_code = "match_02a_exact_higher_level_accepted_or_synonym"
      )

    taxa <- redistribute_progress(taxa, pb)

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
        checked = TRUE,
        known = TRUE,
        alignment_code = "match_02b_exact_higher_level_accepted_or_synonym"
      )

    taxa <- redistribute_progress(taxa, pb)

    if (nrow(taxa$tocheck) == 0)
    return(taxa)

  }


  # match_02c: Higher-level resolution
  # Fuzzy matches of accepted higher-level names where the final "word" is `sp` or `spp` and
  # there isn't an exact match to an accepted higher-level name
  # Aligned name includes identifier to indicate `genus sp.` refers to a specific species (or infra-specific taxon), associated with a specific dataset/location.

  for (ranks in taxon_ranks_to_check) {
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

  # match_04: consolidates what APCalign implements as three separate pattern families (intergrade,
  # indecision, graded/"affinis"/"cf." identification) -- all share the same "resolve to genus, or flag
  # as unresolved" shape, and are rarer than hybrids, so are grouped under one opt-in toggle (off by
  # default) rather than one each. See `?match_taxa`.
  if (intergrades_affinis) {
    # "affinis" is genuinely ambiguous: it's both an affinity qualifier ("Acacia affinis dealbata" =
    # "resembles A. dealbata, not confidently identified") *and* a legitimate specific epithet in its
    # own right ("Gomphrena affinis subsp. pilbarensis" is a real, accepted name). The lookahead below
    # (matching a fix applied upstream in APCalign) only treats "affinis" as an affinity qualifier
    # when it's *not* immediately followed by an infraspecific rank marker.
    not_before_rank_marker <- "(?!\\s+(?:subsp|ssp|subvar|var|forma|form|ser|series|cv|f)\\.?(?:\\s|$))"
    affinis_qualifier <- paste0(" affinis", not_before_rank_marker, "\\s")

    is_intergrade_affinis <- function(cleaned_name) {
      is_intergrade <- stringr::str_detect(cleaned_name, "\\ -- |\\--")
      is_indecision <- (stringr::str_detect(cleaned_name, "[:alpha:]\\/") |
                           stringr::str_detect(cleaned_name, "\\s\\/")) &
        !stringr::str_detect(cleaned_name, "[:digit:]") &
        !stringr::str_detect(cleaned_name, "\\(") &
        !stringr::str_detect(cleaned_name, "\\'")
      is_affinis <- stringr::str_detect(cleaned_name, "[Aa]ff[\\.\\s]") |
        stringr::str_detect(cleaned_name, affinis_qualifier) |
        stringr::str_detect(cleaned_name, " cf[\\.\\s]")
      is_intergrade | is_indecision | is_affinis
    }

    taxa <- match_special_case_to_genus(
      taxa, resources,
      detect_fn = is_intergrade_affinis,
      bracket_sep = " sp. [",
      reason_text = paste(
        "Taxon name suggests an intergrade, an indecision between taxa, or a graded/\"affinis\"/\"cf.\"",
        "identification; can only be aligned to genus rank."
      ),
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
      known = TRUE,
      checked = TRUE,
      alignment_code = "match_11b_no_brackets_synonym"
    )

  taxa <- redistribute_progress(taxa, pb)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_12a: subgenus alignment with bracketed subgenera
  # Toward the end of the alignment function, see if first word of unmatched taxa is a
  # higher order taxon name in one of the taxonomic references.
  # The 'taxon name' is then reformatted as `genus (subgenus) sp.` with the original name in square brackets.

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
  for (ranks in taxon_ranks_to_check) {
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
