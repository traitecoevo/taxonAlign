#' Prepare a combined taxonomic reference table for name matching
#'
#' Takes a single combined taxonomic reference table (the user's own, or one produced by
#' [generate_taxonomic_reference_list()], or several such tables row-bound together) and turns it
#' into the nested `resources` list that [align_taxa()]/`match_taxa()` expect: extra columns used by
#' the matching engine are added, then the table is split by rank (and, for species-level rows, by
#' taxonomic status).
#'
#' Unlike [APCalign](https://traitecoevo.github.io/APCalign/)'s `load_taxonomic_resources()`, which
#' only ever assembles the fixed APC/APNI combination, this function works on whatever combined
#' reference table the user supplies -- at whatever set of taxonomic ranks it happens to contain, not
#' just genus/species/family.
#'
#' @param taxon_resources A tibble with (at least) the columns `canonical_name`, `scientific_name`,
#'  `taxon_rank`, `taxonomic_status`, `taxonomic_dataset`, `genus`, `taxon_ID` and
#'  `accepted_name_usage_ID` -- the column names produced by [generate_taxonomic_reference_list()],
#'  and matching [APCalign](https://traitecoevo.github.io/APCalign/)'s own naming convention exactly
#'  (see Details) so there's one canonical name field, not two. A row whose `canonical_name` is `NA`
#'  has no usable name and is dropped, with a warning (real data occasionally has this -- e.g. some
#'  GBIF records genuinely lack a canonical name). `accepted_name_usage_ID` must be self-referential
#'  (equal to `taxon_ID`) for already-accepted rows, not `NA` -- this is what lets `update_taxa()`
#'  resolve a matched name forward to its current accepted name regardless of whether it matched an
#'  accepted name or a synonym.
#' @param taxon_ranks_to_check Optional character vector restricting which taxonomic ranks (besides
#'  species/infraspecific ranks) are retained in the returned `resources` for higher-rank matching
#'  (e.g. `c("genus", "family")`). Defaults to `NULL`, which keeps every rank present in
#'  `taxon_resources`.
#'
#' @return A named list of tibbles (and, for `species`, a further named list split by
#'  `taxonomic_status`): one element per taxonomic rank present in `taxon_resources` (after applying
#'  `taxon_ranks_to_check`, if supplied), plus `subgenus_v2` when subgenus-rank rows are present (see
#'  Details).
#'
#' @details
#' Column names are normalised on the way in, exactly the way
#' [APCalign::load_taxonomic_resources()] normalises APC/APNI's raw Darwin Core column names to its
#' own convention -- e.g. a raw `canonicalName`/`taxonRank`/`taxonomicStatus`/`scientificName` column
#' is renamed to `canonical_name`/`taxon_rank`/`taxonomic_status`/`scientific_name`. This keeps
#' `canonical_name` the *only* name field taxonAlign ever refers to -- unlike the ported
#' `AusInvertAlign` prototype this package originated from, which had a separate `taxon_name` fallback
#' column, there's no second, ambiguous name field to keep in sync.
#'
#' Two matching conventions for subgenus names are supported side by side: some input name lists
#' write the subgenus alone (e.g. `"Podosemum"`), others write the `Genus (Subgenus)` bracketed
#' convention (e.g. `"Boronia (Podosemum)"`). To support both, when `taxon_resources` contains
#' subgenus-rank rows, `resources$subgenus` holds the plain subgenus names (used for the first
#' convention) and `resources$subgenus_v2` additionally holds a `genus_and_subgenus` column (used for
#' the second).
#'
#' @export
prepare_taxonomic_resources <- function(taxon_resources, taxon_ranks_to_check = NULL) {

  # Normalise column names exactly the way APCalign::load_taxonomic_resources() does for APC/APNI's
  # raw Darwin Core columns -- this is APCalign's own `column_rename` vector verbatim, so a user's raw
  # Darwin Core-cased data (or APC/APNI itself) lines up with taxonAlign's naming without any manual
  # renaming. Columns already correctly named, or not in this map at all, pass through untouched.
  column_rename <- c(
    taxon_ID = "taxonID",
    taxon_rank = "taxonRank",
    name_type = "nameType",
    taxonomic_status = "taxonomicStatus",
    pro_parte = "proParte",
    scientific_name = "scientificName",
    scientific_name_ID = "scientificNameID",
    accepted_name_usage_ID = "acceptedNameUsageID",
    accepted_name_usage = "acceptedNameUsage",
    canonical_name = "canonicalName",
    scientific_name_authorship = "scientificNameAuthorship",
    taxon_rank_sort_order = "taxonRankSortOrder",
    taxon_remarks = "taxonRemarks",
    taxon_distribution = "taxonDistribution",
    higher_classification = "higherClassification",
    nomenclatural_code = "nomenclaturalCode",
    dataset_name = "datasetName",
    name_element = "nameElement"
  )
  taxon_resources <- taxon_resources |> dplyr::rename(dplyr::any_of(column_rename))

  # `taxonomic_dataset` has no APCalign equivalent to rename from -- APCalign hardcodes it ("APC"/
  # "APNI") rather than reading it from the data, since it only ever combines those two fixed
  # datasets. taxonAlign combines arbitrary user-supplied datasets instead, so it has to be a real
  # required input column here.
  required_cols <- c(
    "canonical_name", "scientific_name", "taxon_rank", "taxonomic_status", "taxonomic_dataset",
    "genus", "taxon_ID", "accepted_name_usage_ID"
  )
  missing_cols <- setdiff(required_cols, names(taxon_resources))
  if (length(missing_cols) > 0) {
    stop(
      "`taxon_resources` is missing required column(s): ", paste(missing_cols, collapse = ", "), ". ",
      "See `?prepare_taxonomic_resources` for the expected input columns -- these match the output ",
      "of `generate_taxonomic_reference_list()`."
    )
  }

  # dummy placeholder for blank cells -- fuzzy matching doesn't cope with blank/duplicate cells
  zzz <- "zzzz zzzz"

  taxon_resources <- taxon_resources |>
    dplyr::mutate(
      # normalise to character regardless of the source column's type (our own
      # generate_taxonomic_reference_list() gives integer taxon_IDs; real APC/AFD data gives URI/UUID
      # strings) so downstream code never has to worry about integer-vs-character mismatches
      taxon_ID = as.character(taxon_ID),
      accepted_name_usage_ID = as.character(accepted_name_usage_ID)
    )

  # A row with no usable name (canonical_name is NA -- real data occasionally has this, e.g. some GBIF
  # records genuinely lack a canonicalName) can never be matched *against* anyway, so it's dropped
  # here rather than kept around as a resource-table row. This isn't just tidying: leaving it in is an
  # active hazard downstream, because `NA %in% x` is TRUE whenever `x` itself contains an NA -- so a
  # fuzzy_match() call that legitimately finds no match (returning NA) would otherwise spuriously
  # "match" this row's NA canonical_name instead of correctly matching nothing, in every match block
  # that does `i <- some_value %in% resources$...$canonical_name`-style lookups.
  n_before <- nrow(taxon_resources)
  taxon_resources <- taxon_resources |> dplyr::filter(!is.na(canonical_name))
  n_dropped <- n_before - nrow(taxon_resources)
  if (n_dropped > 0) {
    warning(
      n_dropped, " row(s) in `taxon_resources` have a missing (NA) `canonical_name` and were dropped ",
      "-- they could never be matched against anyway.",
      call. = FALSE
    )
  }

  taxon_resources <- taxon_resources |>
    dplyr::mutate(
      word_one = extract_genus(canonical_name),
      taxon_rank = APCalign::standardise_taxon_rank(taxon_rank),
      taxon_rank2 = ifelse(taxon_rank %in% c("subspecies", "species", "form", "variety"), "species", taxon_rank),
      ## strip_names removes punctuation and filler words associated with infraspecific taxa (subsp,
      ## var, f, ser)
      stripped_canonical = APCalign::strip_names(canonical_name),
      ## strip_names_extra removes extra filler words associated with species name cases (x, sp) --
      ## essential for the 2/3-word matches, since those words shouldn't count as one of the words
      stripped_canonical2 = APCalign::strip_names_extra(stripped_canonical),
      stripped_scientific = APCalign::strip_names(scientific_name),
      binomial = ifelse(taxon_rank == "species", stringr::word(stripped_canonical2, start = 1, end = 2), zzz),
      binomial = ifelse(is.na(binomial), zzz, binomial),
      binomial = base::replace(binomial, duplicated(binomial), zzz),
      word_one_stripped = extract_genus(stripped_canonical),
      trinomial = stringr::word(stripped_canonical2, start = 1, end = 3),
      trinomial = ifelse(is.na(trinomial), zzz, trinomial),
      trinomial = base::replace(trinomial, duplicated(trinomial), zzz)
    )

  # split by taxon rank -- unlike APCalign, higher ranks beyond genus/family are expected and kept
  resources <- split(taxon_resources, taxon_resources$taxon_rank2)

  if (is.null(resources[["species"]])) {
    stop("`taxon_resources` contains no rows at species/infraspecific rank -- nothing to align names against.")
  }

  # for species, split further by taxonomic status
  resources$species <- split(resources$species, resources$species$taxonomic_status)

  # keep both subgenus conventions available: the plain split-by-rank table (`subgenus`, for input
  # names that write the subgenus alone) and a `genus_and_subgenus` variant (`subgenus_v2`, for input
  # names that write the bracketed `Genus (Subgenus)` convention) -- see @details.
  if (!is.null(resources[["subgenus"]])) {
    resources$subgenus_v2 <- resources$subgenus |>
      dplyr::mutate(genus_and_subgenus = paste0(genus, " (", canonical_name, ")"))
  }

  if (!is.null(taxon_ranks_to_check)) {
    higher_ranks_present <- setdiff(names(resources), c("species", "subgenus_v2"))
    unknown_ranks <- setdiff(taxon_ranks_to_check, higher_ranks_present)
    if (length(unknown_ranks) > 0) {
      warning(
        "`taxon_ranks_to_check` includes rank(s) not present in `taxon_resources`: ",
        paste(unknown_ranks, collapse = ", "), ". They will have no effect.",
        call. = FALSE
      )
    }
    ranks_to_drop <- setdiff(higher_ranks_present, taxon_ranks_to_check)
    ranks_to_drop <- setdiff(ranks_to_drop, "subgenus_v2")
    if ("subgenus" %in% ranks_to_drop && !"subgenus" %in% taxon_ranks_to_check) {
      # dropping `subgenus` should also drop its bracketed-name counterpart
      resources$subgenus_v2 <- NULL
    }
    resources[ranks_to_drop] <- NULL
  }

  resources
}
