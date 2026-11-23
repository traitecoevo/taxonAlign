#' Align raw taxon names to a prepared taxonomic reference
#'
#' Attempts to match each name in `original_name` to a name in `resources` (produced by
#' [prepare_taxonomic_resources()]), trying, in order, exact matches (scientific name with
#' authorship, then canonical name), then progressively more lenient fuzzy matches, at species level
#' first and then at each higher taxonomic rank present in `resources`. See `match_taxa()` for the
#' full sequence of match attempts.
#'
#' @param original_name Character vector of raw taxon names to align.
#' @param resources The taxonomic reference to align against: the nested list produced by
#'  [prepare_taxonomic_resources()], or a reference table (or a list of them, such as
#'  [load_taxonomic_resources()]'s output), which is run through [prepare_taxonomic_resources()]
#'  automatically. Preparing it yourself first saves repeating that work when aligning several name
#'  lists against the same reference.
#' @param identifier A dataset, location or other identifier associated with each name in
#'  `original_name` -- used only to disambiguate `genus sp.`-style aligned names (see
#'  [prepare_taxonomic_resources()]/`match_taxa()`) as belonging to a specific dataset/location.
#'  Recycled if length 1; otherwise must be the same length as `original_name`. Defaults to `NA`.
#' @param fuzzy_abs_dist The number of characters allowed to differ for a fuzzy match.
#' @param fuzzy_rel_dist The proportion of characters allowed to differ for a fuzzy match.
#' @param fuzzy_matches Logical; whether fuzzy matching is attempted at all. Defaults to `TRUE`.
#' @param imprecise_fuzzy_matches Logical; reserved for a more lenient fuzzy-matching pass (not yet
#'  implemented -- see `match_taxa()`). Defaults to `FALSE`.
#' @param taxon_ranks_to_check Optional character vector of taxonomic ranks (besides species) to
#'  attempt higher-rank matches against. Defaults to `NULL`, which uses every higher rank present in
#'  `resources`.
#' @param hybrids Logical; if `TRUE` (the default, as APCalign always does), a hybrid name
#'  (`Genus x species`) that isn't itself a listed name is resolved to genus rank
#'  (`"Genus x [original name]"`) rather than left for later match attempts -- with `FALSE`,
#'  `"Banksia serrata x ericifolia"` aligns to *Banksia serrata*. See `?match_taxa`.
#' @param intergrades_affinis Logical; if `TRUE` (the default, as APCalign always does), names
#'  suggesting an intergrade (`--`), an indecision between taxa (`/`), or a graded/"affinis"/"cf."
#'  identification are resolved to genus rank the same way, unless the whole name is a listed name.
#'  See `?match_taxa`.
#' @param consider_english_name_endings Logical; if `TRUE`, before any fuzzy matching, try substituting
#'  a recognised informal English vernacular name ending (e.g. `"-id"`, `"-ine"`, `"-oid"`) for its
#'  formal Latin equivalent and attempt an exact match on the corrected name. Defaults to `FALSE`. See
#'  `?match_taxa`.
#' @param include_bracketed_info Logical. `FALSE` (the default) leaves a name that is nothing more
#'  than a genus, family or other higher-rank name (a bare `"Banksia"`, or a bare `"Genus (Subgenus)"`)
#'  as that name: `"Banksia"`, with no `" sp."` added, since the input didn't say `"sp."`. `TRUE` treats
#'  it as though it had ended in `"sp."`: `"Banksia sp. [<identifier>]"`, the same as `"Banksia sp."`
#'  gives either way (APCalign gives `"Banksia sp. [Banksia; <identifier>]"`). A name with more than
#'  the higher-rank name (`"Banksia sp. 1"`, `"Banksia aff. ericifolia"`) keeps it in brackets either
#'  way (`"Banksia sp. [Banksia sp. 1; <identifier>]"`).
#' @param quiet Accepted for compatibility with APCalign's function of the same name; this
#'  function prints nothing either way.
#' @param progress Logical; if `TRUE`, prints a text progress bar tracking what fraction of
#'  `original_name` has been resolved so far. Useful for large inputs, where matching can take a while.
#'  Defaults to `FALSE`. See `?match_taxa`.
#' @param full Logical; if `TRUE`, return every intermediate column `match_taxa()` computes (useful
#'  for inspecting *why* a name matched the way it did). If `FALSE` (the default), return just the
#'  key output columns.
#'
#' @return A tibble with one row per element of `original_name` (preserving its length, order and any
#'  duplicates/`NA`s), with columns `original_name`, `cleaned_name`, `aligned_name`,
#'  `taxonomic_dataset`, `taxon_rank`, `taxonomic_status`, `taxon_ID`, `accepted_name_usage_ID`,
#'  `aligned_reason`, `alignment_code`, `chars_changed` and `identifier` (or, if `full = TRUE`, every
#'  column `match_taxa()` computes along the way). `taxon_ID`/`accepted_name_usage_ID` identify which
#'  row of `resources` a name matched to, and are what `update_taxa()` uses to resolve a matched
#'  synonym forward to its current accepted name. `chars_changed` is the number of characters that
#'  differed between the name being matched and the reference name it matched -- `0` for every exact
#'  match, the actual edit distance (Damerau-Levenshtein) for a fuzzy match, and `NA` when nothing
#'  matched at all.
#'
#' @examples
#' reference <- data.frame(
#'   canonical_name = c("Boronia", "Boronia serrulata", "Boronia oldname"),
#'   scientific_name = c("Boronia Sm.", "Boronia serrulata Sm.", "Boronia oldname Sm."),
#'   taxon_rank = c("genus", "species", "species"),
#'   taxonomic_status = c("accepted", "accepted", "synonym"),
#'   taxonomic_dataset = "MY_LIST", genus = "Boronia",
#'   taxon_ID = c("1", "2", "3"), accepted_name_usage_ID = c("1", "2", "2")
#' )
#' # a misspelling and a synonym
#' aligned <- align_taxa(c("Boronia serulata", "Boronia oldname"), reference)
#' aligned[, c("original_name", "aligned_name", "taxonomic_status", "aligned_reason")]
#'
#' @export
align_taxa <- function(original_name,
                        resources = NULL,
                        identifier = NA_character_,
                        fuzzy_abs_dist = 3,
                        fuzzy_rel_dist = 0.2,
                        fuzzy_matches = TRUE,
                        imprecise_fuzzy_matches = FALSE,
                        taxon_ranks_to_check = NULL,
                        hybrids = TRUE,
                        intergrades_affinis = TRUE,
                        consider_english_name_endings = FALSE,
                        include_bracketed_info = FALSE,
                        progress = FALSE,
                        full = FALSE,
                        quiet = FALSE) {

  if (missing(original_name) || length(original_name) == 0) {
    stop("`original_name` is required and must have length > 0.")
  }

  if (is.null(resources)) {
    stop(
      "`resources` is required: a released reference from `load_taxonomic_resources()`, or your own ",
      "reference table (see `?taxonomic_reference_schema`).",
      call. = FALSE
    )
  }
  resources <- ensure_prepared_resources(resources)

  if (length(identifier) == 1) {
    identifier <- rep(identifier, length(original_name))
  } else if (length(identifier) != length(original_name)) {
    stop("`identifier` must have length 1 or the same length as `original_name`.")
  }

  taxa <- list()
  taxa[["tocheck"]] <-
    dplyr::tibble(
      original_name = original_name,
      identifier = identifier,
      cleaned_name = NA_character_,
      stripped_name = NA_character_,
      stripped_name2 = NA_character_,
      trinomial = NA_character_,
      binomial = NA_character_,
      word_one = NA_character_,
      word_one_stripped = NA_character_,
      genus = NA_character_,
      ignore_bracketed_words = NA_character_,
      aligned_name = NA_character_,
      aligned_reason = NA_character_,
      fuzzy_match_genus = NA_character_,
      fuzzy_match_genus_synonym = NA_character_,
      fuzzy_match_family = NA_character_,
      fuzzy_match_family_synonym = NA_character_,
      fuzzy_match_binomial = NA_character_,
      fuzzy_match_binomial_synonym = NA_character_,
      fuzzy_match_trinomial = NA_character_,
      fuzzy_match_trinomial_synonym = NA_character_,
      fuzzy_match_cleaned = NA_character_,
      fuzzy_match_cleaned_synonym = NA_character_,
      fuzzy_match_cleaned_imprecise = NA_character_,
      fuzzy_match_cleaned_synonym_imprecise = NA_character_,
      taxonomic_dataset = NA_character_,
      taxonomic_status = NA_character_,
      taxon_rank = NA_character_,
      taxon_ID = NA_character_,
      accepted_name_usage_ID = NA_character_,
      alignment_code = NA_character_,
      chars_changed = NA_integer_,
      checked = FALSE,
      known = FALSE
    ) |>
    # take unique original_name/identifier combinations, so each name is only processed once (or
    # multiple times if paired with distinct identifiers)
    dplyr::filter(!duplicated(paste0(.data$original_name, .data$identifier))) |>
    dplyr::filter(APCalign::standardise_names(.data$original_name) != "")

  taxa <- redistribute(taxa)

  if (nrow(taxa$tocheck) > 0) {
    taxa <- match_taxa(
      taxa = taxa,
      resources = resources,
      fuzzy_abs_dist = fuzzy_abs_dist,
      fuzzy_rel_dist = fuzzy_rel_dist,
      fuzzy_matches = fuzzy_matches,
      imprecise_fuzzy_matches = imprecise_fuzzy_matches,
      taxon_ranks_to_check = taxon_ranks_to_check,
      hybrids = hybrids,
      intergrades_affinis = intergrades_affinis,
      consider_english_name_endings = consider_english_name_endings,
      identifier = identifier,
      include_bracketed_info = include_bracketed_info,
      progress = progress
    )
  }

  out <- dplyr::bind_rows(taxa$checked, taxa$tocheck) |>
    dplyr::mutate(known = !is.na(.data$aligned_name))

  # matching ran on subgenus-free names; put the matched record's name back as its reference writes it
  # (with subgenus, and "Genus (Subgenus)" at subgenus rank) -- see restore_display_names()
  out$aligned_name <- restore_display_names(out$aligned_name, out$taxon_ID, flatten_resources(resources))

  if (!full) {
    out <- out |>
      dplyr::select(
        "original_name", "cleaned_name", "aligned_name", "taxonomic_dataset", "taxon_rank",
        "taxonomic_status", "taxon_ID", "accepted_name_usage_ID", "aligned_reason", "alignment_code",
        "chars_changed", "identifier"
      )
  }

  # left-join back onto the full input vector, so the result has the same length/order/duplicates as
  # `original_name` even though the working set above was deduplicated and blank names were dropped
  dplyr::tibble(original_name = original_name, identifier = identifier) |>
    dplyr::left_join(out, by = c("original_name", "identifier"))
}
