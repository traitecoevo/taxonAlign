#' Align and update a list of taxon names in one call
#'
#' The one-call convenience pipeline: [align_taxa()] followed by [update_taxa()]. Matches each name in
#' `original_name` against `resources`, then resolves that match forward to its current accepted name.
#'
#' @param original_name Character vector of raw taxon names to align and update.
#' @param resources The nested list of reference tibbles produced by
#'  [prepare_taxonomic_resources()], or a reference table (or list of them) -- see [align_taxa()].
#' @param identifier,fuzzy_abs_dist,fuzzy_rel_dist,fuzzy_matches,imprecise_fuzzy_matches,taxon_ranks_to_check,hybrids,intergrades_affinis,consider_english_name_endings,include_bracketed_info,progress
#'  Forwarded to [align_taxa()]; see its documentation.
#' @param taxonomic_splits Passed to [update_taxa()]: how to report a name that leads to more than one
#'  accepted name (`"most_likely_species"`, the default, or `"collapse_to_higher_taxon"`).
#' @param full Logical; if `TRUE`, return every intermediate column [align_taxa()]/[update_taxa()]
#'  compute. If `FALSE` (the default), return just the key output columns: `original_name`,
#'  `aligned_name`, `accepted_name`, `suggested_name`, `genus`, `family`, `taxon_rank`,
#'  `taxonomic_dataset`, `taxonomic_status`, `taxonomic_status_aligned`, `aligned_reason`,
#'  `update_reason` and `chars_changed` (the number of characters that differed between the name being
#'  matched and the reference name it matched -- `0` for an exact match, the edit distance for a fuzzy
#'  match, `NA` when nothing matched).
#'
#' @param quiet Logical; if `FALSE` (the default), ends by printing a summary, as APCalign's does: how
#'  many distinct names aligned to a species or infraspecific taxon (by dataset), only to a genus or a
#'  family, or to another rank; how many couldn't be aligned; how many were updated to a different
#'  name; and how many could refer to more than one accepted taxon. `TRUE` prints nothing.
#'
#' @return A tibble with one row per element of `original_name`; see [update_taxa()] for column
#'  details.
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
#' create_taxonomic_update_lookup(
#'   c("Boronia serulata", "Boronia oldname", "Boronia sp."),
#'   reference
#' )
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
                                            hybrids = TRUE,
                                            intergrades_affinis = TRUE,
                                            consider_english_name_endings = FALSE,
                                            include_bracketed_info = FALSE,
                                            progress = FALSE,
                                            taxonomic_splits = c("most_likely_species", "collapse_to_higher_taxon"),
                                            full = FALSE,
                                            quiet = FALSE) {
  taxonomic_splits <- match.arg(taxonomic_splits)

  if (is.null(resources)) {
    stop(
      "`resources` is required: a released reference from `load_taxonomic_resources()`, or your own ",
      "reference table (see `?taxonomic_reference_schema`).",
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
    consider_english_name_endings = consider_english_name_endings,
    include_bracketed_info = include_bracketed_info,
    progress = progress,
    full = TRUE
  )

  updated_data <- update_taxa(aligned_data, resources, taxonomic_splits = taxonomic_splits)

  if (!quiet) {
    message(paste(summarise_update_lookup(aligned_data, updated_data, taxonomic_splits), collapse = "\n"))
  }

  if (!full) {
    updated_data <- updated_data |>
      dplyr::select(
        # APCalign's own create_taxonomic_update_lookup() columns, in its order...
        "original_name", "aligned_name", "accepted_name", "suggested_name", "genus", "taxon_rank",
        "taxonomic_dataset", "taxonomic_status", "scientific_name", "aligned_reason", "update_reason",
        "number_of_collapsed_taxa",
        # ...then taxonAlign's: the IDs traits.build taxon lists need (APCalign has these only with
        # `full = TRUE`), and the rest
        "taxon_ID", "taxon_ID_genus", "scientific_name_ID", "family", "taxonomic_status_aligned",
        "alternative_possible_names", "chars_changed", "identifier"
      )
  }

  updated_data
}

# The closing summary create_taxonomic_update_lookup() prints, ported from APCalign's
# summarise_update_lookup() (its #131), counting by dataset rather than APC/APNI. Returns the lines.
# Alignment counts come from `aligned` (its taxon_rank/taxonomic_dataset describe the aligned name);
# every count is of distinct input names.
#' @noRd
summarise_update_lookup <- function(aligned, updated, taxonomic_splits) {
  if (is.null(aligned) || is.null(updated)) return(character(0))
  first <- !is.na(aligned$original_name) & !duplicated(aligned$original_name)
  aligned <- aligned[first, ]
  rank <- aligned$taxon_rank
  dataset <- aligned$taxonomic_dataset
  is_aligned <- !is.na(aligned$aligned_name)
  is_species <- is_aligned & rank %in% c("species", "subspecies", "variety", "form")
  is_genus <- is_aligned & rank %in% "genus"
  is_family <- is_aligned & rank %in% "family"
  is_other <- is_aligned & !is_species & !is_genus & !is_family

  # a name changed if its accepted name (or, with none, its suggested name) differs from the aligned
  # name -- "Dryandra sp." -> "Banksia sp." counts
  upd <- updated[!is.na(updated$original_name) & !duplicated(updated$original_name), ]
  upd <- upd[match(aligned$original_name, upd$original_name), ]
  # the suggested name, not accepted_name: taxonAlign fills accepted_name for a genus/family match
  # ("Asteraceae" for "Asteraceae sp."), which APCalign leaves NA
  new_name <- sub(" \\[alternative possible names: .*\\]$", "", upd$suggested_name)
  split <- if (taxonomic_splits == "collapse_to_higher_taxon") {
    dplyr::coalesce(upd$number_of_collapsed_taxa, 0L) > 1
  } else {
    !is.na(upd$alternative_possible_names)
  }
  changed <- !is.na(new_name) & !is.na(upd$aligned_name) & new_name != upd$aligned_name & !split

  # counts in blue, as APCalign prints them (plain text where the console has no colour)
  num <- function(x) cli::col_blue(sum(x))
  by_dataset <- table(dataset[is_species])
  lines <- c(
    paste0("Summary of ", num(rep(TRUE, nrow(aligned))), " names:"),
    paste0("  -> ", num(is_species), " aligned to a species or infraspecific taxon",
           if (length(by_dataset) > 0) paste0(" (", paste(cli::col_blue(by_dataset), "in", names(by_dataset), collapse = ", "), ")")),
    paste0("  -> ", num(is_genus), " aligned only to a genus and ", num(is_family), " only to a family"),
    if (any(is_other)) paste0("  -> ", num(is_other), " aligned to another rank"),
    paste0("  -> ", num(!is_aligned), " could not be aligned"),
    paste0("  -> ", num(changed), " aligned names were updated to a different name (e.g. a synonym to ",
           "its accepted name, or an outdated genus to the current one)")
  )
  if (any(split)) {
    note <- if (taxonomic_splits == "collapse_to_higher_taxon") {
      "they were collapsed to genus, and `suggested_name` lists the possible names"
    } else {
      "`suggested_name` gives the most likely species and lists the alternatives in square brackets"
    }
    lines <- c(lines, paste0("  -> ", num(split), " names could refer to more than one currently accepted taxon. ",
                             "With `taxonomic_splits = \"", taxonomic_splits, "\"`, ", note, "."))
  }
  lines
}
