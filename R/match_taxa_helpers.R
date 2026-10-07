# Vendored helper functions used by `match_taxa()`/`align_taxa()`.
#
# `fuzzy_match()`, `redistribute()` and `extract_genus()` all have close counterparts in APCalign
# (`APCalign:::fuzzy_match`, `APCalign:::redistribute`, `APCalign:::extract_genus`), but APCalign
# keeps them internal (not exported), so they're kept as local copies here instead.
# `extract_genus()` differs slightly from APCalign's current version.

#' Fuzzy match taxonomic names
#'
#' This function attempts to match input strings to a list of allowable
#'  taxonomic names.
#' It requires that the first letter (or digit) of each word is identical
#'  between the input and output strings to avoid mis-matches
#'
#' @param txt The string of text requiring a match
#' @param accepted_list The list of accepted names attempting to match to
#' @param max_distance_abs The maximum allowable number of characters
#'  differing between the input string and the match
#' @param max_distance_rel The maximum proportional difference between the
#'  input string and the match
#' @param n_allowed The number of allowable matches returned. Defaults to 1
#' @param epithet_letters A string specifying if 1 or 2 letters remain fixed
#'  at the start of the species epithet.
#'
#' @return A text string that matches a recognised taxon name or scientific
#'  name
#'
#'
#' @examples
#' fuzzy_match("Baksia serrata", c("Banksia serrata",
#'                                 "Banksia integrifolia"),
#'                                  max_distance_abs = 1,
#'                                  max_distance_rel = 1)
#'
#' @noRd
fuzzy_match <- function(txt, accepted_list,
                        max_distance_abs,
                        max_distance_rel,
                        n_allowed = 1,
                        epithet_letters = 1
                        ) {

  if (!epithet_letters %in% c(1,2)) {
    stop("Epithet must be 1 or 2.")
    }

  # An NA query can't match anything.
  if (is.na(txt)) return(NA)

  # A bare rank-category word ("genus", "species", "family", ...) is never itself a real taxon
  # name, even though it can look like a plausible short match to something unrelated -- the
  # query-side mirror of the resource-side check in prepare_taxonomic_resources() that drops a row
  # whose own canonical_name is just its rank's name. Shares that same rank vocabulary,
  # `taxonAlign_taxon_rank_specificity` (prepare_taxonomic_resources.R), plus "species" (excluded
  # from that vector since it's handled as its own bucket elsewhere).
  if (tolower(txt) %in% c(taxonAlign_taxon_rank_specificity, "species")) return(NA)

  accepted_list <- accepted_list[!is.na(accepted_list)]

  ## identify number of words in the text to match
  words_in_text <- 1 + stringr::str_count(txt," ")

  ## extract first letter of first word
  txt_word1_start <- stringr::str_extract(txt, "[:alpha:]") |>
                     stringr::str_to_lower()

  ## for text matches with 2 or more words,
  ## extract the first letter/digit of the second word
  if(words_in_text > 1 & epithet_letters == 2)
    {if(nchar(stringr::word(txt,2)) == 1) {
      txt_word2_start <- stringr::str_extract(stringr::word(txt,2),
                                              "[:alpha:]|[:digit:]")
    } else {
      txt_word2_start <- stringr::str_extract(stringr::word(txt,2),
                                          "[:alpha:][:alpha:]|[:digit:]")
    }
  }

  if(words_in_text > 1 & epithet_letters == 1) {
    txt_word2_start <- stringr::str_extract(stringr::word(txt,2), "[:alpha:]|[:digit:]")
  }

  ## for text matches with 3 or more words,
  ## extract the first letter/digit of the third word
  if(words_in_text > 2) {
    txt_word3_start <- stringr::str_extract(stringr::word(txt,3), "[:alpha:]|[:digit:]")
  }

  ## Subset accepted_list to entries sharing the query's first letter, to keep the stringdist() call
  ## below cheap. `accepted_list_word1_start`'s own first-letter extraction can return NA for a
  ## malformed entry (e.g. one with no alphabetic character at all); excluded explicitly with
  ## `!is.na(...)` rather than left to `%in%`/subsetting, which would otherwise inject a literal NA
  ## into the filtered list and poison every distance calculation downstream.
  accepted_list_word1_start <- stringr::str_extract(accepted_list, "[:alpha:]") |> stringr::str_to_lower()
  accepted_list <- accepted_list[
    !is.na(accepted_list_word1_start) & accepted_list_word1_start == (txt_word1_start |> stringr::str_to_lower())
  ] |>
                    unique()

  ## identify the number of characters that must change for the text string to
  ## match each of the possible accepted names
  if (length(accepted_list) > 0) {
  distance_c <- stringdist::stringdist(txt, accepted_list, method = "dl")

  ## identify the minimum number of characters that must change for the text
  ## string to match a string in the list of accepted names. `na.rm = TRUE` is a defensive
  ## backstop against any not-yet-seen data-quality issue producing an NA distance.
  min_dist_abs_c <-  min(distance_c, na.rm = TRUE)
  min_dist_per_c <-  min(distance_c, na.rm = TRUE) / stringr::str_length(txt)

  i <- which(distance_c==min_dist_abs_c)
  potential_matches <- accepted_list[i]

  ## Is there an acceptable fuzzy match? if not, break here
  if(!(
    ## Within allowable number of characters (absolute)
    min_dist_abs_c <= max_distance_abs &
    ## Within allowable number of characters (relative)
    min_dist_per_c <= max_distance_rel &
    ## Solution has up to n_allowed matches
    length(potential_matches) <= n_allowed
    ) ) {
    return(NA)
  }

  } else {
    return(NA)
  }

  # function to check if a match is ok
  check_match <- function(potential_match) {

    ## identify number of words in the matched string
    words_in_match <- 1 + stringr::str_count(potential_match," ")

    ## identify the first letter of the first word in the matched string
    match_word1_start <- stringr::str_extract(potential_match, "[:alpha:]") |>
                          stringr::str_to_lower()

    ## identify the first letter of the second word in the matched string
    ## (if the matched string includes 2+ words)
    if(words_in_text > 1 & epithet_letters == 2) {
      x <- stringr::word(potential_match,2)
      if(nchar(x) == 1) {
        match_word2_start <- stringr::str_extract(x, "[:alpha:]|[:digit:]")
      } else {
        match_word2_start <- stringr::str_extract(x, "[:alpha:][:alpha:]|[:digit:]")
      }
    }

    if(words_in_text > 1 & epithet_letters == 1) {
        match_word2_start <- stringr::str_extract(stringr::word(potential_match,2), "[:alpha:]|[:digit:]")
    }

    ## identify the first letter of the third word in the matched string
    ## (if the matched string includes 3+ words)
    if(words_in_text > 2) {
      match_word3_start <- stringr::str_extract(stringr::word(potential_match,3), "[:alpha:]|[:digit:]")
    }

    ## keep match if the first letters of the first three words
    ## (or fewer if applicable) in the string to match are identical to the
    ## first letters of the first three words in the matched string

    if(words_in_text == 1) {
      if (txt_word1_start == match_word1_start) {
        return(TRUE)
      }

    } else if(words_in_text == 2) {
      if (
          txt_word1_start == match_word1_start &
          txt_word2_start == match_word2_start
      ) {
        return(TRUE)
      }
    } else if(words_in_text > 2) {
      if (words_in_match > 2) {
        if (
          txt_word1_start == match_word1_start &
          txt_word2_start == match_word2_start &
          txt_word3_start == match_word3_start
        ) {
          return(TRUE)
        }
      } else if (
          txt_word1_start == match_word1_start &
          txt_word2_start == match_word2_start
        ) {
          return(TRUE)}
    }
    return(FALSE)
  }

  j <- purrr::map_lgl(potential_matches, check_match)

  if(!any(j)) return(NA)

  return(potential_matches[j])
}


# Vectorized wrapper around `fuzzy_match()`, applying it to every element of `x` at once via
# `purrr::map_chr()` rather than looping and calling `fuzzy_match()` one row at a time. Mirrors the
# equivalent efficiency fix in upstream APCalign's internal `match_taxa()`.
fuzzy_match_column <- function(x, accepted_list, max_distance_abs, max_distance_rel,
                                n_allowed = 1, epithet_letters = 1) {
  purrr::map_chr(
    x,
    ~ fuzzy_match(
      txt = .x,
      accepted_list = accepted_list,
      max_distance_abs = max_distance_abs,
      max_distance_rel = max_distance_rel,
      n_allowed = n_allowed,
      epithet_letters = epithet_letters
    )
  )
}

update_na_with <- function(current, new) {
  ifelse(is.na(current), new, current)
}

# required to align taxa
redistribute <- function(data) {
  data[["checked"]] <- dplyr::bind_rows(data[["checked"]],
                                        data[["tocheck"]] |>
                                          dplyr::filter(checked))

  data[["tocheck"]] <-
    data[["tocheck"]] |> dplyr::filter(!checked)
  data
}

# Drop-in replacement for redistribute() used throughout match_taxa() that also advances a progress
# bar, if one was opened (`pb`, from utils::txtProgressBar()). Tracks *rows resolved* rather than
# *which match block is currently running*, since match blocks aren't equal-cost -- a block-count
# bar would jump to "nearly done" almost instantly then stall. `pb` is NULL when `progress = FALSE`
# (the default), in which case this has no overhead.
redistribute_progress <- function(data, pb) {
  data <- redistribute(data)
  if (!is.null(pb)) utils::setTxtProgressBar(pb, nrow(data$checked))
  data
}


## function for extracting the first "genus" - including with hybrids
extract_genus <- function(taxon_name) {

  taxon_name <- APCalign::standardise_names(taxon_name)

  genus <- stringr::str_split_i(taxon_name, " |\\/", 1) |> stringr::str_to_sentence()

  # Deal with names that being with x,
  # e.g."x Taurodium x toveyanum" or "x Glossadenia tutelata"
  i <- !is.na(genus) & genus =="X"

  genus[i] <-
    paste("x", stringr::str_split_i(taxon_name[i], " |\\/", 2) |> stringr::str_to_sentence())

  genus
}

# Shape-check for `align_taxa()`/`update_taxa()`'s `resources` argument, once it's known not to be a
# plain data frame -- see `ensure_prepared_resources()` below.
validate_resources_shape <- function(resources) {
  if (is.data.frame(resources) || !is.list(resources) ||
      is.null(resources$species) || is.null(resources$species$accepted)) {
    stop(
      "`resources` doesn't look like the output of `prepare_taxonomic_resources()` (expected a ",
      "nested list with a `resources$species$accepted` element; got ", class(resources)[1], "). Did ",
      "you pass a raw taxonomic reference table (e.g. from `generate_GBIF_taxonomic_reference_list()`) ",
      "directly, instead of running it through `prepare_taxonomic_resources()` first?",
      call. = FALSE
    )
  }
}

# `align_taxa()`/`update_taxa()`/`create_taxonomic_update_lookup()` all need `resources` in the
# nested-by-rank shape `prepare_taxonomic_resources()` builds. A plain data frame is run through
# `prepare_taxonomic_resources()` automatically (non-interactively); an already-nested list is only
# shape-validated, not re-split.
ensure_prepared_resources <- function(resources) {
  if (is.data.frame(resources)) {
    return(prepare_taxonomic_resources(resources))
  }
  validate_resources_shape(resources)
  resources
}

# Removes a bracketed subgenus from a species-level name: "Pardalotus (Pardalotinus) striatus" ->
# "Pardalotus striatus". Only the zoological "Genus (Subgenus) epithet..." shape is touched -- a
# bracket directly after the genus, followed by at least one more word (it may hold more than one
# subgenus, "Nassa (Alectryon, Aciculina) macrocephalus") -- so e.g. "Agaricia papillosa (pars)" or
# "Calodema (regale species group)" are left as they are.
#' @noRd
strip_subgenus_from_name <- function(x) {
  stringr::str_replace(x, "^(\\S+) \\([^()]+\\) (\\S.*)$", "\\1 \\2")
}

# Flattens every rank/status sublist of a prepared `resources` list into one table keyed by
# `taxon_ID`, species first then `names(resources)`'s own most-specific-first order (`subgenus_v2`, a
# derived duplicate of `subgenus`, excluded). Shared by update_taxa() and restore_display_names().
#' @noRd
flatten_resources <- function(resources) {
  dplyr::bind_rows(c(resources$species, resources[setdiff(names(resources), c("species", "subgenus_v2"))]))
}

# Puts each matched record's `display_name` (the name as its reference writes it, incl. any subgenus --
# see prepare_taxonomic_resources()) back into an output name built from its matching form
# (`canonical_name`). Matching itself always works on the subgenus-free form; this runs afterwards.
# Replaces `canonical_name` only where it is the whole output name or its leading part (e.g.
# "Geobasileus sp." -> "Acanthiza (Geobasileus) sp."), and never where the display form is already
# there (e.g. "Leioproctus (Leioproctus) sp." built by the bracketed-subgenus match blocks). A no-op
# for `resources` prepared before `display_name` existed.
#' @noRd
restore_display_names <- function(name, taxon_ID, all_taxa) {
  if (!"display_name" %in% names(all_taxa)) return(name)
  i <- match(taxon_ID, all_taxa$taxon_ID)
  canonical <- all_taxa$canonical_name[i]
  display <- all_taxa$display_name[i]
  swap <- !is.na(name) & !is.na(display) & display != canonical &
    (name == canonical | startsWith(name, paste0(canonical, " "))) &
    !startsWith(name, display)
  name[swap] <- paste0(display[swap], substring(name[swap], nchar(canonical[swap]) + 1))
  name
}
