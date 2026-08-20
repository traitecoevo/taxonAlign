#' Resolve aligned names forward to their current accepted name
#'
#' Takes the output of [align_taxa()] and, for every row that matched something in `resources`
#' (whether an accepted name or a synonym), looks up the *current* record for that match via
#' `accepted_name_usage_ID` and reports its accepted name (when it resolves to one).
#'
#' @param aligned_data A tibble in the shape [align_taxa()] returns -- in particular, it must have
#'  `aligned_name`, `taxonomic_status`, `taxon_rank`, `taxonomic_dataset`, `taxon_ID` and
#'  `accepted_name_usage_ID` columns (both `align_taxa()`'s default, `full = FALSE`, output and its
#'  `full = TRUE` output include these).
#' @param resources The nested list of reference tibbles produced by
#'  [prepare_taxonomic_resources()] (the same one passed to `align_taxa()`). A plain (already
#'  fully-formatted) taxonomic reference tibble is also accepted directly -- see `align_taxa()`'s
#'  `resources` documentation.
#'
#' @return `aligned_data` with `taxon_rank`/`genus`/`family`/`taxonomic_dataset` refreshed to whatever
#'  the current record has (a synonym's may be outdated), the pre-update `taxonomic_status` renamed to
#'  `taxonomic_status_aligned`, and new columns `accepted_name` (the current accepted name, when the
#'  match resolves to one, otherwise `NA`), `suggested_name` (`accepted_name` if available, otherwise
#'  falls back to `aligned_name`), `taxonomic_status` (the *current* record's status) and
#'  `update_reason` (a short explanation, mirroring `aligned_reason`'s style).
#'
#' @details
#' Unlike [APCalign](https://traitecoevo.github.io/APCalign/)'s `update_taxonomy()` -- five separate
#' functions, each hand-written for one specific rank/dataset combination (`update_taxonomy_APC_genus`,
#' `update_taxonomy_APC_family`, ...) -- this is a **single, rank-agnostic** lookup: every rank present
#' in `resources` is resolved the same way, by matching each row's `accepted_name_usage_ID` against a
#' `taxon_ID` in a table combining every rank/status sublist in `resources`. A row that's already
#' accepted resolves to itself (its own `accepted_name_usage_ID` is self-referential, per
#' [prepare_taxonomic_resources()]'s requirements); a synonym resolves to whatever its
#' `accepted_name_usage_ID` points to.
#'
#' Two things this deliberately does **not** do, relative to APCalign's `update_taxonomy()`:
#' - **No splits handling.** APCalign's `taxonomic_splits` argument disambiguates a synonym that has
#'   since been split into several modern species (`"most_likely_species"` picks one;
#'   `"collapse_to_higher_taxon"` collapses to genus). That's specific to APC's documented split
#'   history, which an arbitrary user-supplied reference can't be expected to carry -- if
#'   `accepted_name_usage_ID` doesn't resolve to exactly one current record, `accepted_name`/
#'   `suggested_name` are simply left as described above, with no attempt to pick among alternatives.
#' - **No genus-substring surgery.** APCalign's `update_taxonomy_APC_genus()` reconstructs a species'
#'   suggested name by splicing just the updated genus portion into the aligned name, when only the
#'   genus (not the species) has changed. That's a nice refinement but doesn't obviously generalize
#'   across arbitrary ranks the way the rest of this does, so it's omitted here.
#'
#' @export
update_taxa <- function(aligned_data, resources = NULL) {

  if (is.null(resources)) {
    stop(
      "`resources` is required. Build one with `prepare_taxonomic_resources()`, using your own ",
      "combined taxonomic reference table or one produced by `generate_GBIF_taxonomic_reference_list()`. ",
      "See `?prepare_taxonomic_resources`.",
      call. = FALSE
    )
  }
  resources <- ensure_prepared_resources(resources)

  required_cols <- c(
    "aligned_name", "taxonomic_status", "taxon_rank", "taxonomic_dataset",
    "taxon_ID", "accepted_name_usage_ID"
  )
  missing_cols <- setdiff(required_cols, names(aligned_data))
  if (length(missing_cols) > 0) {
    stop(
      "`aligned_data` is missing required column(s): ", paste(missing_cols, collapse = ", "), ". ",
      "`update_taxa()` expects the output of `align_taxa()`."
    )
  }

  # flatten every rank/status sublist in `resources` into one combined lookup table, keyed by
  # `taxon_ID` -- this is what makes the lookup below rank-agnostic (one table, not one per rank).
  # `subgenus_v2` is excluded: it's a derived duplicate of `subgenus` (adds a `genus_and_subgenus`
  # column for the bracketed-name matching convention), not a distinct set of taxa.
  #
  # Bound most-specific-rank-first (species, then `names(resources)`'s own order -- see
  # `taxonAlign_taxon_rank_specificity` in `prepare_taxonomic_resources.R`, which is what orders
  # `resources` itself this way): `match()` below is first-hit, so if `taxon_ID` were ever to repeat
  # across ranks (as it did before AFD's higher-rank `taxon_ID` fallback was namespaced by rank -- see
  # `load_taxonomic_resources.R`), the more specific, more informative rank wins the tie rather than
  # whichever rank happened to bind first.
  rank_tables <- c(resources$species, resources[setdiff(names(resources), c("species", "subgenus_v2"))])
  all_taxa <- dplyr::bind_rows(rank_tables)

  current <- all_taxa[match(aligned_data$accepted_name_usage_ID, all_taxa$taxon_ID), ]
  resolved <- !is.na(current$taxon_ID)

  # `genus`/`family` aren't required columns (unlike taxon_rank/taxonomic_dataset/taxonomic_status,
  # which prepare_taxonomic_resources()/align_taxa() both guarantee) -- fall back to NA on either side
  # if simply absent, rather than erroring. (`aligned_data$genus`, when `align_taxa()` provided one, is
  # never actually populated by any match block -- it's always NA pre-update -- so resolved rows'
  # genus always comes from `resources`, never from `aligned_data` itself.)
  genus_current <- if ("genus" %in% names(all_taxa)) current$genus else NA_character_
  genus_prior <- if ("genus" %in% names(aligned_data)) aligned_data$genus else NA_character_
  family_current <- if ("family" %in% names(all_taxa)) current$family else NA_character_
  family_prior <- if ("family" %in% names(aligned_data)) aligned_data$family else NA_character_

  aligned_data |>
    dplyr::mutate(
      taxonomic_status_aligned = taxonomic_status,
      accepted_name = dplyr::if_else(resolved & current$taxonomic_status == "accepted", current$canonical_name, NA_character_),
      suggested_name = dplyr::if_else(!is.na(accepted_name), accepted_name, aligned_name),
      genus = dplyr::if_else(resolved, genus_current, genus_prior),
      family = dplyr::if_else(resolved, family_current, family_prior),
      taxon_rank = dplyr::if_else(resolved, current$taxon_rank, taxon_rank),
      taxonomic_dataset = dplyr::if_else(resolved, current$taxonomic_dataset, taxonomic_dataset),
      taxonomic_status = dplyr::case_when(
        resolved ~ current$taxonomic_status,
        is.na(aligned_name) ~ "unknown",
        TRUE ~ taxonomic_status_aligned
      ),
      update_reason = dplyr::case_when(
        is.na(aligned_name) ~ NA_character_,
        !is.na(accepted_name) & accepted_name == aligned_name ~
          "Aligned name is already the current accepted name",
        !is.na(accepted_name) ~ paste0("Updated to the current accepted name (", Sys.Date(), ")"),
        TRUE ~ "Aligned name's current status could not be resolved in `resources`"
      )
    )
}
