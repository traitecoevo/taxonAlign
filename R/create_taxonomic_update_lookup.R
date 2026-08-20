#' Align and update a list of taxon names in one call
#'
#' The one-call convenience pipeline: [align_taxa()] followed by [update_taxa()]. Matches each name in
#' `original_name` against `resources`, then resolves that match forward to its current accepted name.
#'
#' @param original_name Character vector of raw taxon names to align and update.
#' @param resources The nested list of reference tibbles produced by
#'  [prepare_taxonomic_resources()]. A plain (already fully-formatted) taxonomic reference tibble is
#'  also accepted directly -- see `align_taxa()`'s `resources` documentation.
#' @param identifier,fuzzy_abs_dist,fuzzy_rel_dist,fuzzy_matches,imprecise_fuzzy_matches,taxon_ranks_to_check,hybrids,intergrades_affinis,include_bracketed_info,progress
#'  Forwarded to [align_taxa()]; see its documentation.
#' @param full Logical; if `TRUE`, return every intermediate column [align_taxa()]/[update_taxa()]
#'  compute. If `FALSE` (the default), return just the key output columns: `original_name`,
#'  `aligned_name`, `accepted_name`, `suggested_name`, `genus`, `family`, `taxon_rank`,
#'  `taxonomic_dataset`, `taxonomic_status`, `taxonomic_status_aligned`, `aligned_reason` and
#'  `update_reason`.
#'
#' @return A tibble with one row per element of `original_name`; see [update_taxa()] for column
#'  details.
#'
#' @export
create_taxonomic_update_lookup <- function(original_name,
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

  if (is.null(resources)) {
    stop(
      "`resources` is required. Build one with `prepare_taxonomic_resources()`, using your own ",
      "combined taxonomic reference table or one produced by `generate_GBIF_taxonomic_reference_list()`. ",
      "See `?prepare_taxonomic_resources`.",
      call. = FALSE
    )
  }
  # prepared once here (rather than separately inside align_taxa()/update_taxa() below) so a flat
  # `resources` table is only ever run through prepare_taxonomic_resources() a single time
  resources <- ensure_prepared_resources(resources)

  aligned_data <- align_taxa(
    original_name = original_name,
    resources = resources,
    identifier = identifier,
    fuzzy_abs_dist = fuzzy_abs_dist,
    fuzzy_rel_dist = fuzzy_rel_dist,
    fuzzy_matches = fuzzy_matches,
    imprecise_fuzzy_matches = imprecise_fuzzy_matches,
    taxon_ranks_to_check = taxon_ranks_to_check,
    hybrids = hybrids,
    intergrades_affinis = intergrades_affinis,
    include_bracketed_info = include_bracketed_info,
    progress = progress,
    full = TRUE
  )

  updated_data <- update_taxa(aligned_data, resources)

  if (!full) {
    updated_data <- updated_data |>
      dplyr::select(
        original_name, aligned_name, accepted_name, suggested_name, genus, family, taxon_rank,
        taxonomic_dataset, taxonomic_status, taxonomic_status_aligned, aligned_reason, update_reason,
        identifier
      )
  }

  updated_data
}
