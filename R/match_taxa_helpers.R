# Vendored helper functions used by `match_taxa()`/`align_taxa()`.
#
# `fuzzy_match()`, `redistribute()` and `extract_genus()` all have close counterparts in APCalign
# (`APCalign:::fuzzy_match`, `APCalign:::redistribute`, `APCalign:::extract_genus`), but APCalign
# keeps them internal (not exported), so they can't be imported here -- they're intentionally kept
# as local copies instead. `redistribute()` below is byte-for-byte identical to
# `APCalign:::redistribute`; `extract_genus()` differs slightly (APCalign's version now delegates to
# an `extract_genus_clean()` helper) -- that divergence is left as-is rather than reconciled here.

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

  ## a query string that's itself NA can't usefully match anything; and real-world reference
  ## lists occasionally contain NA canonical names (e.g. doubtful/unranked GBIF records) -- left
  ## in, these silently turn `min(distance_c)` into NA further down, which then blows up the
  ## `if (!(min_dist_abs_c <= ...))` check below with "missing value where TRUE/FALSE needed"
  if (is.na(txt)) return(NA)
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

  ## subset accepted list to taxa that begin with the same first letter to
  ## reduce the number of fuzzy matches that are made in the next step.
  ## has also wanted to do this for the second word, but then need to separate
  ## different lists of reference names - smaller time saving and not worth it.
  ## need to add `unique`, because for `APC-known`,
  ## sometimes duplicate canonical names each with a different taxonomic
  ## status, and then you just want to retain the first one
  accepted_list <- accepted_list[(stringr::str_extract(accepted_list, "[:alpha:]") |>
                                    stringr::str_to_lower()) ==
                                    (txt_word1_start |> stringr::str_to_lower())] |>
                    unique()

  ## identify the number of characters that must change for the text string to
  ## match each of the possible accepted names
  if (length(accepted_list) > 0) {
  distance_c <- stringdist::stringdist(txt, accepted_list, method = "dl")
  
  ## identify the minimum number of characters that must change for the text
  ## string to match a string in the list of accepted names
  min_dist_abs_c <-  min(distance_c)
  min_dist_per_c <-  min(distance_c) / stringr::str_length(txt)

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
    ## next line is no longer being used,
    ## since only comparing to first-letter matches
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

# Shared shape-check for `align_taxa()`/`update_taxa()`'s `resources` argument, used once it's
# already known *not* to be a plain data frame (see `ensure_prepared_resources()` below, which handles
# that case by preparing it automatically instead of erroring).
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
# nested-by-rank shape `prepare_taxonomic_resources()` builds -- but a user with a single reference
# table that's *already* fully formatted (e.g. generate_GBIF_taxonomic_reference_list()'s own output)
# shouldn't have to remember to call that function themselves first just to get past a shape check.
# If `resources` is a plain data frame, prepare it automatically (non-interactively -- if it turns out
# to need column mapping, that surfaces the same clear "missing required column(s)... pass
# `interactive = TRUE`" error `prepare_taxonomic_resources()` always gives, just one call deep); if
# it's already a list, only validate its shape, since re-preparing an already-prepared `resources`
# would be wrong (splitting an already-split structure).
ensure_prepared_resources <- function(resources) {
  if (is.data.frame(resources)) {
    return(prepare_taxonomic_resources(resources))
  }
  validate_resources_shape(resources)
  resources
}
