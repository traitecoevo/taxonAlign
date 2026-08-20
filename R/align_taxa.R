#' Align raw taxon names to a prepared taxonomic reference
#'
#' Attempts to match each name in `original_name` to a name in `resources` (produced by
#' [prepare_taxonomic_resources()]), trying, in order, exact matches (scientific name with
#' authorship, then canonical name), then progressively more lenient fuzzy matches, at species level
#' first and then at each higher taxonomic rank present in `resources`. See `match_taxa()` for the
#' full sequence of match attempts.
#'
#' @param original_name Character vector of raw taxon names to align.
#' @param resources The nested list of reference tibbles produced by
#'  [prepare_taxonomic_resources()]. A plain (already fully-formatted) taxonomic reference tibble is
#'  also accepted directly -- it's run through [prepare_taxonomic_resources()] automatically -- which
#'  saves the extra call for a single reference table that doesn't need any interactive column
#'  mapping; call [prepare_taxonomic_resources()] yourself first if it does (e.g. `interactive = TRUE`)
#'  or if you're combining more than one reference table.
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
#' @param hybrids Logical; if `TRUE`, resolve hybrid names (`Genus x species`) to genus rank rather
#'  than leaving them for later, inappropriate match attempts. Defaults to `FALSE`. See `?match_taxa`.
#' @param intergrades_affinis Logical; if `TRUE`, resolve names suggesting an intergrade, an
#'  indecision between taxa, or a graded/"affinis"/"cf." identification to genus rank the same way.
#'  Defaults to `FALSE`. See `?match_taxa`.
#' @param include_bracketed_info Logical; controls the `"<rank name> sp. [<original name>;
#'  <identifier>]"` formatting used for a higher-rank-only match. When `FALSE` (the default) and the
#'  name being matched is nothing more than the matched rank's own name (a bare single word, or a bare
#'  `"Genus (Subgenus)"`), the bracketed suffix is dropped and `aligned_name` is just the bare matched
#'  name -- `original_name` already preserves the raw input as its own column regardless. Whenever
#'  there's anything beyond the rank name itself to report, the bracketed format is used regardless of
#'  this argument. Set to `TRUE` to always use the bracketed format (matching APCalign's convention
#'  exactly). Defaults to `FALSE`. See `?match_taxa`.
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
#'  `aligned_reason`, `alignment_code` and `identifier` (or, if `full = TRUE`, every column
#'  `match_taxa()` computes along the way). `taxon_ID`/`accepted_name_usage_ID` identify which row of
#'  `resources` a name matched to, and are what `update_taxa()` uses to resolve a matched synonym
#'  forward to its current accepted name.
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
                        hybrids = FALSE,
                        intergrades_affinis = FALSE,
                        include_bracketed_info = FALSE,
                        progress = FALSE,
                        full = FALSE) {

  if (missing(original_name) || length(original_name) == 0) {
    stop("`original_name` is required and must have length > 0.")
  }

  if (is.null(resources)) {
    stop(
      "`resources` is required. Build one with `prepare_taxonomic_resources()`, using your own ",
      "combined taxonomic reference table or one produced by `generate_GBIF_taxonomic_reference_list()`. ",
      "See `?prepare_taxonomic_resources`.",
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
      checked = FALSE,
      known = FALSE
    ) |>
    # take unique original_name/identifier combinations, so each name is only processed once (or
    # multiple times if paired with distinct identifiers)
    dplyr::filter(!duplicated(paste0(original_name, identifier))) |>
    dplyr::filter(APCalign::standardise_names(original_name) != "")

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
      identifier = identifier,
      include_bracketed_info = include_bracketed_info,
      progress = progress
    )
  }

  out <- dplyr::bind_rows(taxa$checked, taxa$tocheck) |>
    dplyr::mutate(known = !is.na(aligned_name))

  if (!full) {
    out <- out |>
      dplyr::select(
        original_name, cleaned_name, aligned_name, taxonomic_dataset, taxon_rank,
        taxonomic_status, taxon_ID, accepted_name_usage_ID, aligned_reason, alignment_code, identifier
      )
  }

  # left-join back onto the full input vector, so the result has the same length/order/duplicates as
  # `original_name` even though the working set above was deduplicated and blank names were dropped
  dplyr::tibble(original_name = original_name, identifier = identifier) |>
    dplyr::left_join(out, by = c("original_name", "identifier"))
}
