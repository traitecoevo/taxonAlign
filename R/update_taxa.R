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
#'  [prepare_taxonomic_resources()] (the same one passed to `align_taxa()`), or a reference table (or
#'  list of them) -- see [align_taxa()].
#'
#' @param taxonomic_splits How to report a name that leads to more than one accepted name:
#'  `"most_likely_species"` (the default) suggests one and lists the others in brackets;
#'  `"collapse_to_higher_taxon"` collapses it to genus when all candidates share one. See Details.
#'
#' @return `aligned_data` with `taxon_rank`/`genus`/`family`/`taxonomic_dataset` refreshed to whatever
#'  the current record has (a synonym's may be outdated), the pre-update `taxonomic_status` renamed to
#'  `taxonomic_status_aligned`, and new columns `accepted_name` (the current accepted name, when the
#'  match resolves to one, otherwise `NA`), `suggested_name` (`accepted_name` if available, otherwise
#'  falls back to `aligned_name`), `taxonomic_status` (the *current* record's status) and
#'  `update_reason` (a short explanation, mirroring `aligned_reason`'s style), and
#'  `alternative_possible_names` (the other candidates for a name that leads to more than one accepted
#'  name, otherwise `NA`).
#'
#'  It also has every column APCalign's `update_taxonomy()` returns, meaning the same thing, all
#'  describing the taxon `suggested_name` names (its accepted record, or for a split collapsed to genus,
#'  that genus's):
#'  - `taxon_ID`: that accepted record's ID (`NA` when the name doesn't resolve to an accepted name).
#'    The ID of the record the name *matched* (a synonym's own ID, say), which `align_taxa()` returns as
#'    `taxon_ID`, is kept as `aligned_taxon_ID`.
#'  - `taxon_ID_genus`: the ID of its genus's accepted record.
#'  - `scientific_name` and `scientific_name_ID`: its name with authorship, and the reference's
#'    `scientific_name_ID` for it (e.g. an IPNI LSID for the WCVP; `NA` if the reference has none). For
#'    a name that matched but doesn't resolve to an accepted name (an unplaced name, say), those of the
#'    matched record.
#'  - `subclass`, `taxon_distribution`: the reference's own columns of those names, `NA` if it has none.
#'  - `canonical_name`: the same as `suggested_name`, as in APCalign.
#'  - `row_number`: the row's position in `aligned_data`.
#'  - `number_of_collapsed_taxa`: for a name leading to more than one accepted name, 1 when one is
#'    suggested, or the number of candidates when they're collapsed to genus; `NA` otherwise.
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
#' **A synonym that leads to more than one accepted taxon** (a species or infraspecific name listed as
#' a synonym of two or more different accepted taxa -- a split, or a pro parte synonym) follows
#' APCalign's `taxonomic_splits` convention. One accepted name is chosen -- by taxonomic status
#' precedence, then (for a tie) an accepted name sharing the name's epithet, then one of the same rank,
#' then one published no later than the name itself, then the oldest, then the order `resources` lists
#' them in -- and the others are listed with their status, both in `suggested_name`
#' (`"X [alternative possible names: Y (synonym) | Z (misapplied)]"`) and in a separate
#' `alternative_possible_names` column. With `taxonomic_splits = "collapse_to_higher_taxon"`, a name
#' whose candidates all share one genus is collapsed to that genus instead
#' (`"Genus sp. [collapsed names: ...]"`, `taxon_rank = "genus"`, `accepted_name = NA`). Only a match
#' to a synonym record is treated this way: a match to an accepted name, or to a name given with its
#' authorship (which identifies one record, e.g. one of two homonyms), is not.
#'
#' One thing this deliberately does **not** do, relative to APCalign's `update_taxonomy()`:
#' - **No genus-substring surgery.** APCalign's `update_taxonomy_APC_genus()` reconstructs a species'
#'   suggested name by splicing just the updated genus portion into the aligned name, when only the
#'   genus (not the species) has changed. That's a nice refinement but doesn't obviously generalize
#'   across arbitrary ranks the way the rest of this does, so it's omitted here.
#'
#' @export
update_taxa <- function(aligned_data, resources = NULL,
                        taxonomic_splits = c("most_likely_species", "collapse_to_higher_taxon")) {
  taxonomic_splits <- match.arg(taxonomic_splits)

  if (is.null(resources)) {
    stop(
      "`resources` is required: a released reference from `load_taxonomic_resources()`, or your own ",
      "reference table (see `?taxonomic_reference_schema`).",
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
  # taxonAlign.dataprep's `load_AFD()`), the more specific, more informative rank wins the tie rather than
  # whichever rank happened to bind first.
  # `matching_taxa` keeps the subgenus-free names matching used (what the split lookup below must
  # compare); `all_taxa` reports accepted names as their reference writes them (with subgenus;
  # "Genus (Subgenus)" at subgenus rank) -- see prepare_taxonomic_resources()
  matching_taxa <- flatten_resources(resources)
  all_taxa <- matching_taxa
  if ("display_name" %in% names(all_taxa)) all_taxa$canonical_name <- all_taxa$display_name

  # a name that leads to more than one accepted name: resolve it via the record chosen by
  # build_split_table() (see resolve_synonym_splits.R), not whichever record matching happened to hit
  # first, and keep the other candidates. Skipped when the name was matched together with its
  # authorship -- that already identifies one record (e.g. a homonym, "Camponotus reticulatus Kirby,
  # 1896" vs "... Roger, 1863").
  status_aligned <- aligned_data$taxonomic_status
  usage_ID <- aligned_data$accepted_name_usage_ID
  alternatives <- rep(NA_character_, nrow(aligned_data))
  collapsed <- rep(NA_character_, nrow(aligned_data))
  collapsed_genus <- rep(NA_character_, nrow(aligned_data))
  # APCalign's number_of_collapsed_taxa: 1 for a name resolved to one of several candidates, the
  # number of candidates when they're collapsed to genus, NA for a name that isn't a split
  n_collapsed <- rep(NA_integer_, nrow(aligned_data))
  splits <- build_split_table(matching_taxa)
  if (nrow(splits) > 0) {
    matched <- matching_taxa[match(aligned_data$taxon_ID, matching_taxa$taxon_ID), ]
    s <- match(
      paste(matched$canonical_name, matched$taxon_rank, sep = "\r"),
      paste(splits$canonical_name, splits$taxon_rank, sep = "\r")
    )
    by_authorship <- if ("alignment_code" %in% names(aligned_data)) {
      grepl("with_authorship", aligned_data$alignment_code)
    } else {
      FALSE
    }
    # only a match to a synonym record is ambiguous; a match to an accepted name is just that name
    s[!is.na(s) & (by_authorship | matched$taxonomic_status %in% "accepted")] <- NA
    hit <- !is.na(s)
    chosen <- all_taxa[match(splits$chosen_ID[s[hit]], all_taxa$taxon_ID), ]
    usage_ID[hit] <- chosen$accepted_name_usage_ID
    status_aligned[hit] <- chosen$taxonomic_status
    alternatives[hit] <- splits$alternative_possible_names[s[hit]]
    n_collapsed[hit] <- 1L
    if (taxonomic_splits == "collapse_to_higher_taxon") {
      collapsed[hit] <- ifelse(
        is.na(splits$shared_genus[s[hit]]), NA_character_,
        paste0(splits$shared_genus[s[hit]], " sp. [collapsed names: ", splits$all_possible_names[s[hit]], "]")
      )
      collapsed_genus[hit] <- splits$shared_genus[s[hit]]
      n_collapsed[hit] <- ifelse(is.na(collapsed[hit]), 1L, splits$n_possible_names[s[hit]])
    }
  }

  current <- all_taxa[match(usage_ID, all_taxa$taxon_ID), ]
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

  out <- aligned_data |>
    dplyr::mutate(
      taxonomic_status_aligned = status_aligned,
      accepted_name_usage_ID = usage_ID,
      alternative_possible_names = alternatives,
      accepted_name = dplyr::if_else(resolved & current$taxonomic_status == "accepted", current$canonical_name, NA_character_),
      suggested_name = dplyr::if_else(!is.na(accepted_name), accepted_name, aligned_name),
      # APCalign's convention: one name, with every other candidate in brackets
      suggested_name = dplyr::case_when(
        !is.na(collapsed) ~ collapsed,
        !is.na(alternatives) ~ paste0(suggested_name, " [alternative possible names: ", alternatives, "]"),
        TRUE ~ suggested_name
      ),
      accepted_name = dplyr::if_else(!is.na(collapsed), NA_character_, accepted_name),
      genus = dplyr::if_else(resolved, genus_current, genus_prior),
      family = dplyr::if_else(resolved, family_current, family_prior),
      taxon_rank = dplyr::case_when(
        !is.na(collapsed) ~ "genus",
        resolved ~ current$taxon_rank,
        TRUE ~ taxon_rank
      ),
      taxonomic_dataset = dplyr::if_else(resolved, current$taxonomic_dataset, taxonomic_dataset),
      taxonomic_status = dplyr::case_when(
        resolved ~ current$taxonomic_status,
        is.na(aligned_name) ~ "unknown",
        TRUE ~ taxonomic_status_aligned
      ),
      update_reason = dplyr::case_when(
        is.na(aligned_name) ~ NA_character_,
        !is.na(collapsed) ~
          "Aligned name leads to more than one accepted name in the same genus; collapsed to genus",
        !is.na(alternatives) & !is.na(accepted_name) ~
          "Aligned name leads to more than one accepted name; the most likely is suggested, alternatives in brackets",
        !is.na(accepted_name) & accepted_name == aligned_name ~
          "Aligned name is already the current accepted name",
        !is.na(accepted_name) ~ paste0("Updated to the current accepted name (", Sys.Date(), ")"),
        TRUE ~ "Aligned name's current status could not be resolved in `resources`"
      )
    )

  # APCalign's update_taxonomy() columns, describing the taxon `suggested_name` names: the current
  # accepted record, or for a split collapsed to genus, that genus's accepted record (its
  # `taxon_ID`/`taxon_ID_genus`/`scientific_name_ID` are what traits.build taxon lists record --
  # traitecoevo/taxonAlign.dataprep#1). taxonAlign's `taxon_ID` used to be the *matched* record's ID
  # here; that's now `aligned_taxon_ID`, so `taxon_ID` means what it means in APCalign.
  col_or_na <- function(table, col, i) if (col %in% names(table)) as.character(table[[col]][i]) else rep(NA_character_, length(i))
  accepted_genera <- all_taxa[all_taxa$taxon_rank %in% "genus" & all_taxa$taxonomic_status %in% "accepted", ]
  genus_record <- match(dplyr::coalesce(collapsed_genus, out$genus), accepted_genera$canonical_name)
  record <- match(usage_ID, all_taxa$taxon_ID)
  record[!(resolved & current$taxonomic_status %in% "accepted")] <- NA
  is_collapsed <- !is.na(collapsed)
  # an unresolved match (an unplaced name, say) still has a name, with its own authorship and ID
  name_record <- dplyr::coalesce(record, match(aligned_data$taxon_ID, all_taxa$taxon_ID))
  name_record[is_collapsed] <- NA

  out |>
    dplyr::mutate(
      aligned_taxon_ID = aligned_data$taxon_ID,
      subclass = dplyr::if_else(is_collapsed, NA_character_, col_or_na(all_taxa, "subclass", record)),
      taxon_distribution = dplyr::if_else(is_collapsed, NA_character_, col_or_na(all_taxa, "taxon_distribution", record)),
      scientific_name = dplyr::if_else(
        is_collapsed, accepted_genera$scientific_name[genus_record], all_taxa$scientific_name[name_record]
      ),
      taxon_ID = dplyr::if_else(is_collapsed, accepted_genera$taxon_ID[genus_record], all_taxa$taxon_ID[record]),
      taxon_ID_genus = accepted_genera$taxon_ID[genus_record],
      scientific_name_ID = dplyr::if_else(
        is_collapsed, col_or_na(accepted_genera, "scientific_name_ID", genus_record),
        col_or_na(all_taxa, "scientific_name_ID", name_record)
      ),
      canonical_name = suggested_name,
      row_number = seq_len(dplyr::n()),
      number_of_collapsed_taxa = n_collapsed
    )
}
