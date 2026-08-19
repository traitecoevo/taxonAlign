# Column names APCalign::load_taxonomic_resources() renames APC/APNI's raw Darwin Core columns to --
# copied verbatim so a user's raw Darwin Core-cased data (or APC/APNI itself) lines up with
# taxonAlign's naming without any manual renaming. Columns already correctly named, or not in this map
# at all, pass through untouched.
taxonAlign_column_rename <- c(
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

# `taxonomic_dataset` has no APCalign equivalent to rename from -- APCalign hardcodes it ("APC"/"APNI")
# rather than reading it from the data, since it only ever combines those two fixed datasets.
# taxonAlign combines arbitrary user-supplied datasets instead, so it has to be a real required column.
taxonAlign_required_cols <- c(
  "canonical_name", "scientific_name", "taxon_rank", "taxonomic_status", "taxonomic_dataset",
  "genus", "taxon_ID", "accepted_name_usage_ID"
)

#' Prepare a combined taxonomic reference table for name matching
#'
#' Takes one or more taxonomic reference tables (the user's own, one produced by
#' [generate_taxonomic_reference_list()], or any mix of these) and turns them into the single nested
#' `resources` list that [align_taxa()]/`match_taxa()` expect: columns are normalised and any missing
#' ones resolved (see `interactive`, below), tables are combined if more than one was supplied, and the
#' result is split by rank (and, for species-level rows, by taxonomic status).
#'
#' Unlike [APCalign](https://traitecoevo.github.io/APCalign/)'s `load_taxonomic_resources()`, which
#' only ever assembles the fixed APC/APNI combination, this function works on whatever combined
#' reference data the user supplies -- at whatever set of taxonomic ranks it happens to contain, not
#' just genus/species/family.
#'
#' @param taxon_resources A tibble, a path to a CSV file, or a (optionally named) list of either --
#'  one element per taxonomic reference table to combine. Each table needs (at least) the columns
#'  `canonical_name`, `scientific_name`, `taxon_rank`, `taxonomic_status`, `taxonomic_dataset`,
#'  `genus`, `taxon_ID` and `accepted_name_usage_ID` -- the column names produced by
#'  [generate_taxonomic_reference_list()], and matching
#'  [APCalign](https://traitecoevo.github.io/APCalign/)'s own naming convention exactly (see Details)
#'  so there's one canonical name field, not two. A row whose `canonical_name` is `NA` has no usable
#'  name and is dropped, with a warning (real data occasionally has this -- e.g. some GBIF records
#'  genuinely lack a canonical name). `accepted_name_usage_ID` must be self-referential (equal to
#'  `taxon_ID`) for already-accepted rows, not `NA` -- this is what lets `update_taxa()` resolve a
#'  matched name forward to its current accepted name regardless of whether it matched an accepted
#'  name or a synonym.
#' @param taxon_ranks_to_check Optional character vector restricting which taxonomic ranks (besides
#'  species/infraspecific ranks) are retained in the returned `resources` for higher-rank matching
#'  (e.g. `c("genus", "family")`). Defaults to `NULL`, which keeps every rank present in
#'  `taxon_resources`.
#' @param interactive Logical; if `TRUE`, prompts (in the style of `traits.build`'s
#'  `metadata_add_traits()`/`metadata_add_locations()`) for any of the required columns a table is
#'  missing -- letting a column be picked from that table, or (for some fields) a fixed value typed in
#'  or auto-generated -- rather than erroring. A table that's already complete is never interrupted;
#'  one that isn't is first asked, once, whether it's already fully aligned regardless (e.g. it came
#'  from an earlier `prepare_taxonomic_resources()`/`generate_taxonomic_reference_list()` call, just
#'  under column names `interactive` didn't recognise) before being walked through the per-field
#'  prompts. Once every initially-supplied table is resolved, also asks whether there are any
#'  additional taxonomic reference(s) to include -- repeating for as many as the user has -- so a
#'  single file passed in via `taxon_resources` can grow into a combined set interactively, rather
#'  than requiring the whole set to be assembled up front. When more than one table ends up in the
#'  final set, also prompts once for a priority order across them. Defaults to `FALSE`, which errors
#'  immediately (as before) if any required column is missing, and skips both of the prompts above.
#' @param user_responses Optional named list bypassing the real prompts `interactive = TRUE` would
#'  otherwise show -- for scripting or testing. Keyed by table name (matching `taxon_resources`'s
#'  names, or `"table 1"`/`"table 2"`/... if unnamed), each holding the responses for that table's
#'  missing fields (`already_aligned` (logical), `taxonomic_dataset`, `canonical_name`,
#'  `scientific_name`, `taxon_rank`, `taxonomic_status`, `genus`, `taxon_ID`,
#'  `accepted_name_usage_ID` -- see `?map_missing_taxon_resources_columns` for exact shapes), plus two
#'  top-level elements: `additional_tables` (an optionally-named list of further tables/paths to add,
#'  bypassing the "any additional reference(s)?" prompt loop -- each is still resolved via its own
#'  entry in `user_responses`, keyed the same way) and `priority_order`, when the final set has more
#'  than one table. Ignored unless `interactive = TRUE`.
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
#' When multiple tables are supplied, priority is expressed purely through row order in the combined
#' table: `match_taxa()`'s exact-match blocks use `match()` (first-hit semantics), so whichever table
#' is row-bound first is preferred when a name exists in more than one.
#'
#' Two matching conventions for subgenus names are supported side by side: some input name lists
#' write the subgenus alone (e.g. `"Podosemum"`), others write the `Genus (Subgenus)` bracketed
#' convention (e.g. `"Boronia (Podosemum)"`). To support both, when `taxon_resources` contains
#' subgenus-rank rows, `resources$subgenus` holds the plain subgenus names (used for the first
#' convention) and `resources$subgenus_v2` additionally holds a `genus_and_subgenus` column (used for
#' the second).
#'
#' @export
prepare_taxonomic_resources <- function(taxon_resources,
                                         taxon_ranks_to_check = NULL,
                                         interactive = FALSE,
                                         user_responses = NULL) {

  tables <- normalise_taxon_resources_input(taxon_resources)

  resolved <- purrr::imap(
    tables,
    function(data, label) resolve_taxon_resources_table(data, label, interactive, user_responses[[label]])
  )

  # Interactively, keep asking for one more taxonomic reference until the user says there isn't one --
  # rather than requiring every table to be assembled into `taxon_resources` up front, this lets
  # someone start with just the one file they have open and add others as they think of them.
  # `user_responses$additional_tables` (a list of extra tables/paths, optionally named) bypasses the
  # real loop for scripting/testing -- each entry is resolved exactly like any other table, using
  # `user_responses[[its label]]` for its own missing-column prompts.
  if (interactive) {
    extra_tables <- user_responses$additional_tables
    extra_index <- 0

    repeat {
      if (!is.null(extra_tables)) {
        extra_index <- extra_index + 1
        if (extra_index > length(extra_tables)) break
        new_raw <- extra_tables[[extra_index]]
        new_label <- names(extra_tables)[extra_index]
      } else {
        if (!prompt_yes_no("\nDo you have any additional taxonomic reference(s) to include?")) break
        new_raw <- readline(prompt = "Enter the file path for the additional taxonomic reference: ")
        new_label <- NULL
      }

      if (is.null(new_label) || new_label == "") new_label <- paste("table", length(resolved) + 1)
      if (is.character(new_raw) && length(new_raw) == 1) new_raw <- read_taxon_resources_file(new_raw)

      resolved[[new_label]] <- resolve_taxon_resources_table(
        new_raw, new_label, interactive, user_responses[[new_label]]
      )
    }
  }

  if (length(resolved) > 1) {
    order <- if (interactive) {
      prompt_priority_order(names(resolved), user_responses$priority_order)
    } else {
      # no prompt: the order tables were supplied in already *is* the priority
      names(resolved)
    }
    taxon_resources <- dplyr::bind_rows(resolved[order])
  } else {
    taxon_resources <- resolved[[1]]
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

# Normalises `taxon_resources` (a data frame, a file path, or a list of either, optionally named) into
# a *named* list of data frames -- reading any file-path elements via readr::read_csv(). Unnamed (or
# partially named) lists get positional labels ("table 1", "table 2", ...) for prompts/error messages.
normalise_taxon_resources_input <- function(taxon_resources) {

  if (is.data.frame(taxon_resources)) {
    tables <- list(taxon_resources)
  } else if (is.character(taxon_resources) && length(taxon_resources) == 1) {
    tables <- list(read_taxon_resources_file(taxon_resources))
  } else if (is.list(taxon_resources) && length(taxon_resources) > 0) {
    tables <- purrr::map(
      taxon_resources,
      function(x) if (is.character(x) && length(x) == 1) read_taxon_resources_file(x) else x
    )
  } else {
    stop(
      "`taxon_resources` must be a tibble/data frame, a path to a CSV file, or a (optionally named) ",
      "list of either.", call. = FALSE
    )
  }

  labels <- names(tables)
  if (is.null(labels)) labels <- rep("", length(tables))
  unnamed <- which(labels == "")
  labels[unnamed] <- paste("table", unnamed)
  names(tables) <- labels

  tables
}

read_taxon_resources_file <- function(path) {
  if (!file.exists(path)) {
    stop("`taxon_resources` names a file that doesn't exist: ", path, call. = FALSE)
  }
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

# Applies the column_rename step to one table, then either returns it as-is (already complete),
# errors (interactive = FALSE), or interactively fills in whatever's missing (interactive = TRUE).
resolve_taxon_resources_table <- function(data, table_label, interactive, user_responses) {

  data <- data |> dplyr::rename(dplyr::any_of(taxonAlign_column_rename))
  missing_cols <- setdiff(taxonAlign_required_cols, names(data))

  if (length(missing_cols) == 0) {
    return(data)
  }

  if (!interactive) {
    stop(
      "`taxon_resources` (`", table_label, "`) is missing required column(s): ",
      paste(missing_cols, collapse = ", "), ". See `?prepare_taxonomic_resources` for the expected ",
      "input columns, or pass `interactive = TRUE` to be prompted for them.",
      call. = FALSE
    )
  }

  # Give the user a chance to assert the table is already fully aligned before launching into the
  # full per-field prompt sequence below -- e.g. it may already be in taxonAlign's target shape (from
  # an earlier prepare_taxonomic_resources()/generate_taxonomic_reference_list() call) just under
  # column names the automatic column_rename step above doesn't recognise. Only asked here, once
  # column_rename has already run and something is still missing -- a table that's already fully
  # resolved (the common case for generate_taxonomic_reference_list()'s own output) is never
  # interrupted with this question at all.
  if (prompt_already_aligned(table_label, user_responses$already_aligned)) {
    stop(
      "`", table_label, "` was indicated as already fully aligned, but is still missing required ",
      "column(s): ", paste(missing_cols, collapse = ", "), ". Answer \"No\" (or omit ",
      "`user_responses$already_aligned`) if it still needs column mapping.",
      call. = FALSE
    )
  }

  map_missing_taxon_resources_columns(data, missing_cols, table_label, user_responses)
}
