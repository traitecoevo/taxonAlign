# Synonyms that lead to more than one accepted taxon ("splits", in APCalign's terms): a species or
# infraspecific name listed as a synonym of two or more different accepted taxa. Deliberately narrow --
# only this genuinely ambiguous case; an accepted name, a genus, or a name matched with its authorship
# never goes through here. Found at scale
# reconciling the AFD format against the NSL format (see vignettes/AFD-data-processing.qmd): ~1,900
# species-level names. update_taxa() picks one accepted name for such a name and lists the others,
# following APCalign's `taxonomic_splits` convention ("most_likely_species" /
# "collapse_to_higher_taxon").
#
# Candidates are ordered by, in turn:
#  1. taxonomic status, via taxonAlign_taxonomic_status_priority (an accepted record beats a synonym,
#     a primary synonym beats a plain synonym, a synonym beats a misapplication, ...);
#  2. an accepted name sharing the name's own final epithet (usually the same type, i.e. a change of
#     genus);
#  3. an accepted name of the same rank as the name (as many words): a trinomial goes to the subspecies,
#     a binomial to the species -- separates a species from its own nominotypical subspecies;
#  4. an accepted name published no later than the name itself -- under priority, an older name can
#     only be a true junior synonym of something at least as old, so a link to a name described later
#     is more likely a misapplication or part usage;
#  5. the oldest accepted name, then the order the reference itself lists them in -- no principled
#     basis; the last is what APCalign does (its "most_likely_species" keeps the first record in APC's
#     own order, after status), so the two packages agree on APC data, e.g. "Justicia procumbens"
#     (11 equally ranked "pro parte misapplied" records, no years in botanical names) ->
#     "Rostellularia adscendens subsp. dallachyi".
# Rules 2 and 4 were chosen by testing against the NSL format's own resolutions of names that are a tie in
# the AFD format: together they decide 255 of 295 and agree with NSL in 252, where "oldest" alone
# agreed 57% of the time and "newest" 40% (about 50% expected by chance).
#
# Builds, from the flattened `resources` table (see flatten_resources()), one row per name that leads
# to more than one accepted name: the record to resolve it to (`chosen_ID`, a taxon_ID), the other
# candidates as APCalign-style "Name (status) | Name (status)" text, and whether every candidate
# shares one genus (for "collapse_to_higher_taxon").
#' @noRd
build_split_table <- function(all_taxa) {
  # only species/infraspecific synonym records: a name listed as a synonym of two or more different
  # accepted taxa is the one genuinely ambiguous case (a split, or a pro parte synonym)
  syn <- all_taxa[all_taxa$taxonomic_status != "accepted" &
    all_taxa$taxon_rank %in% c("species", "subspecies", "variety", "form", "subvariety", "subform"), ]
  repeated <- syn$canonical_name %in% syn$canonical_name[duplicated(syn$canonical_name)]
  r <- syn[repeated, ]
  if (nrow(r) == 0) return(empty_split_table())

  target <- all_taxa[match(r$accepted_name_usage_ID, all_taxa$taxon_ID), ]
  display <- if ("display_name" %in% names(all_taxa)) target$display_name else target$canonical_name
  last_word <- function(x) sub(".*\\s", "", x)

  cand <- dplyr::tibble(
    source_order = seq_len(nrow(r)),
    canonical_name = r$canonical_name,
    taxon_rank = r$taxon_rank,
    taxon_ID = r$taxon_ID,
    status = r$taxonomic_status,
    target_ID = r$accepted_name_usage_ID,
    target_name = display,
    target_canonical = target$canonical_name,
    target_status = target$taxonomic_status,
    target_genus = if ("genus" %in% names(target)) target$genus else NA_character_,
    record_year = scientific_name_year(r$scientific_name),
    target_year = scientific_name_year(target$scientific_name)
  ) |>
    # a record pointing at itself (e.g. "unplaced") or at nothing isn't a second accepted taxon
    dplyr::filter(!is.na(target_canonical) & target_ID != taxon_ID & target_status %in% "accepted") |>
    dplyr::group_by(canonical_name) |>
    dplyr::filter(dplyr::n_distinct(target_ID) > 1) |>
    dplyr::mutate(
      status_rank = taxonomic_status_rank(status),
      epithet_rank = as.integer(last_word(target_canonical) != last_word(canonical_name)),
      # same number of words: a trinomial goes to the subspecies, a binomial to the species
      word_count_rank = as.integer(stringr::str_count(target_canonical, "\\S+") != stringr::str_count(canonical_name, "\\S+")),
      older_rank = as.integer(!(!is.na(target_year) & !is.na(record_year) & target_year <= record_year)),
      year_rank = dplyr::coalesce(target_year, .Machine$integer.max)
    ) |>
    dplyr::arrange(status_rank, epithet_rank, word_count_rank, older_rank, year_rank, source_order, .by_group = TRUE) |>
    dplyr::distinct(target_ID, .keep_all = TRUE)

  if (nrow(cand) == 0) return(empty_split_table())

  cand |>
    dplyr::summarise(
      taxon_rank = taxon_rank[1],
      chosen_ID = taxon_ID[1],
      alternative_possible_names = paste0(target_name[-1], " (", status[-1], ")", collapse = " | "),
      all_possible_names = paste0(target_name, " (", status, ")", collapse = " | "),
      shared_genus = if (dplyr::n_distinct(target_genus) == 1 && !is.na(target_genus[1])) target_genus[1] else NA_character_,
      .groups = "drop"
    )
}

#' @noRd
empty_split_table <- function() {
  dplyr::tibble(
    canonical_name = character(0), taxon_rank = character(0), chosen_ID = character(0),
    alternative_possible_names = character(0), all_possible_names = character(0),
    shared_genus = character(0)
  )
}

# Position of each status in taxonAlign_taxonomic_status_priority; an unlisted status ranks last.
#' @noRd
taxonomic_status_rank <- function(status) {
  r <- match(status, taxonAlign_taxonomic_status_priority)
  ifelse(is.na(r), length(taxonAlign_taxonomic_status_priority) + 1L, r)
}

# Year of publication from the end of a scientific name's authorship, e.g. "(Gmelin, 1789)" -> 1789,
# "Guenée, [1858]" -> 1858, "Girault, 1956b" -> 1956; NA where there's none.
#' @noRd
scientific_name_year <- function(scientific_name) {
  as.integer(stringr::str_extract(scientific_name, "\\d{4}(?=[a-z]?\\]?\\)?\\s*$)"))
}
