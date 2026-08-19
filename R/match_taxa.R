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
#' Not yet implemented (see CLAUDE.md for the current status): hybrid names, graded/"affinis" names,
#' and indecision/intergrade names -- real-world equivalents of these all have dedicated match blocks
#' in [APCalign](https://traitecoevo.github.io/APCalign/)'s internal `match_taxa()`.
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
#' @param identifier A dataset, location or other identifier,
#'  which defaults to NA.
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
    identifier = NA_character_
) {

  if (is.null(taxon_ranks_to_check)) {
    taxon_ranks_to_check <- setdiff(names(resources), c("species", "subgenus_v2"))
  }

  ## A function that specifies particular fuzzy matching conditions (for the
  ## function fuzzy_match) when matching is being done at the genus level.
  if (fuzzy_matches == TRUE) {
    fuzzy_match_genera <- function(x, y) {
      purrr::map_chr(x, ~ fuzzy_match(.x, y, max_distance_abs = 2, max_distance_rel = 0.35, n_allowed = 1))
    }
  } else {
    fuzzy_match_genera <- function(x, y) {
      purrr::map_chr(x, ~ fuzzy_match(.x, y, max_distance_abs = 0, max_distance_rel = 0.0, n_allowed = 1))
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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)

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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

    taxa <- redistribute(taxa)

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
        alignment_code = "match_02a_exact_higher_level_accepted_or_synonym"
      )

    taxa <- redistribute(taxa)

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
        alignment_code = "match_02b_fuzzy_genus_accepted"
      )

    taxa <- redistribute(taxa)
    if (nrow(taxa$tocheck) == 0)
      return(taxa)

  }

  ## removed matches 3, 4 for simplicity, since I don't think they would be triggered by any names (for specific weird informal names)
  ## XXX-TODO reinstate matches for hybrid names, graded/"affinis" names and indecision/intergrade
  ## names from APCalign's internal match_taxa function -- see CLAUDE.md

  # match_05a: fuzzy match to accepted/valid canonical name
  # Fuzzy match of taxon name to an accepted canonical name, once filler words and punctuation are removed.
  for (i in seq_len(nrow(taxa$tocheck))) {
    taxa$tocheck$fuzzy_match_cleaned[i] <-
      fuzzy_match(
        txt = taxa$tocheck$stripped_name[i],
        accepted_list = resources$species$accepted$stripped_canonical,
        max_distance_abs = fuzzy_abs_dist,
        max_distance_rel = fuzzy_rel_dist,
        n_allowed = 1
      )
  }

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

  taxa <- redistribute(taxa)
  if (nrow(taxa$tocheck) == 0)
    return(taxa)

  # match_05b: fuzzy match to synonymous canonical name
  # Fuzzy match of taxon name to an synonymous canonical name, once filler words and punctuation are removed.
  for (i in seq_len(nrow(taxa$tocheck))) {
    taxa$tocheck$fuzzy_match_cleaned_synonym[i] <-
      fuzzy_match(
        txt = taxa$tocheck$stripped_name[i],
        accepted_list = resources$species$synonym$stripped_canonical,
        max_distance_abs = fuzzy_abs_dist,
        max_distance_rel = fuzzy_rel_dist,
        n_allowed = 1
      )
  }

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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

  taxa <- redistribute(taxa)
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

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources$subgenus_v2$taxonomic_dataset[ii],
        taxon_rank = "subgenus",
        taxonomic_status = resources$subgenus_v2$taxonomic_status[ii],
        aligned_name_tmp = paste0(resources$subgenus_v2$genus_and_subgenus[ii], " sp. [", cleaned_name),
        aligned_name = ifelse(is.na(identifier_string2),
                              paste0(aligned_name_tmp, "]"),
                              paste0(aligned_name_tmp, identifier_string2, "]")
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

    taxa <- redistribute(taxa)

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

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources[[ranks]]$taxonomic_dataset[ii],
        taxon_rank = ranks,
        taxonomic_status = resources[[ranks]]$taxonomic_status[ii],
        aligned_name_tmp = paste0(resources[[ranks]]$word_one_stripped[ii], " sp. [", cleaned_name),
        aligned_name = ifelse(is.na(identifier_string2),
                              paste0(aligned_name_tmp, "]"),
                              paste0(aligned_name_tmp, identifier_string2, "]")
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

    taxa <- redistribute(taxa)
    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  # match_12c: higher-level fuzzy alignment
  # The final alignment step is to see if a fuzzy match can be made for the first word of unmatched taxa to an
  # higher order taxon name in one of the taxonomic references.
  # The 'taxon name' is then reformatted as `genus sp.` with the original name in square brackets.
  for (ranks in taxon_ranks_to_check) {
    i <-
      taxa$tocheck$fuzzy_match_genus %in% resources[[ranks]]$word_one_stripped

    ii <-
      match(
        taxa$tocheck[i,]$word_one_stripped,
        resources[[ranks]]$word_one_stripped
      )

    taxa$tocheck[i,] <- taxa$tocheck[i,] |>
      dplyr::mutate(
        taxonomic_dataset = resources[[ranks]]$taxonomic_dataset[ii],
        taxon_rank = ranks,
        taxonomic_status = resources[[ranks]]$taxonomic_status[ii],
        aligned_name_tmp = paste0(fuzzy_match_genus, " sp. [", cleaned_name),
        aligned_name = ifelse(is.na(identifier_string2),
                              paste0(aligned_name_tmp, "]"),
                              paste0(aligned_name_tmp, identifier_string2, "]")
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

    taxa <- redistribute(taxa)
    if (nrow(taxa$tocheck) == 0)
      return(taxa)
  }

  taxa$tocheck <- taxa$tocheck |> dplyr::select(-identifier_string, -identifier_string2, -aligned_name_tmp)
  taxa$checked <- taxa$checked |> dplyr::select(-identifier_string, -identifier_string2, -aligned_name_tmp)

  taxa
}
