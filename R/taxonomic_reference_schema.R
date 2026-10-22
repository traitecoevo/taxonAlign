# The taxonomic reference format: the hand-off between taxonAlign and the packages that build
# reference tables for it (taxonAlign.dataprep, or a user's own scripts) -- taxonAlign issue #26. Kept
# deliberately small and stable: anything that reshapes a particular source into this format belongs
# with that source, not here.

# What each required column holds -- shown by taxonomic_reference_schema() and in its help page.
taxonAlign_required_col_descriptions <- c(
  canonical_name = "The name without authorship, e.g. \"Boronia serrulata\". Matched against.",
  scientific_name = "The name with authorship, e.g. \"Boronia serrulata Sm.\" (or the same as canonical_name if there's none).",
  taxon_rank = "The record's rank, e.g. \"species\", \"genus\", \"family\".",
  taxonomic_status = "\"accepted\" for a currently accepted name; anything else (\"synonym\", \"basionym\", \"misapplied\", ...) for a name that leads to one.",
  taxonomic_dataset = "The reference the record comes from, e.g. \"APC\", \"AFD\", \"GBIF\".",
  genus = "The genus of a genus-rank or narrower record (for a subgenus, the genus it belongs to); NA above genus rank.",
  taxon_ID = "An identifier for the record, unique within the table.",
  accepted_name_usage_ID = "The taxon_ID of the accepted name the record leads to -- its own taxon_ID for an accepted record."
)

#' The taxonomic reference format taxonAlign matches against
#'
#' Describes the columns a taxonomic reference table needs before it can be passed to
#' [prepare_taxonomic_resources()], [align_taxa()], [update_taxa()] or
#' [create_taxonomic_update_lookup()]. Every reference taxonAlign loads ([load_taxonomic_resources()])
#' is in this format, and any table you build yourself -- by hand, with your own scripts, or with
#' the `taxonAlign.dataprep` package -- just needs to be in it too.
#'
#' Eight columns are required: `canonical_name`, `scientific_name`, `taxon_rank`, `taxonomic_status`,
#' `taxonomic_dataset`, `genus`, `taxon_ID` and `accepted_name_usage_ID`. The names follow
#' [APCalign](https://traitecoevo.github.io/APCalign/)'s own; where a Darwin Core name exists
#' (`canonicalName`, `taxonRank`, ...), [prepare_taxonomic_resources()] renames it automatically.
#'
#' Any other column is kept. A character column named after a rank (`family`, `order`, `tribe`, ...)
#' is read as that rank's value for each row: [prepare_taxonomic_resources()] adds a row for every
#' family/order/... named this way that has no row of its own. `scientific_name_authorship` and
#' `extinct` (logical; see [load_taxonomic_resources()]) are recognised too.
#'
#' One record per row. A synonym (any `taxonomic_status` other than `"accepted"`) has its own row,
#' whose `accepted_name_usage_ID` is the `taxon_ID` of the accepted record it leads to. If a table has
#' several references in it, it's ordered from most to least preferred: when the same name appears
#' twice with the same status, taxonAlign uses the first.
#'
#' @return A tibble with one row per column: `column`, `required` (logical), `darwin_core` (the
#'  Darwin Core name it's renamed from, or `NA`) and `description`.
#'
#' @seealso [check_taxonomic_reference()] to check a table is in this format.
#'
#' @examples
#' taxonomic_reference_schema()
#'
#' @export
taxonomic_reference_schema <- function() {
  optional <- setdiff(c(names(taxonAlign_column_rename), "scientific_name_authorship", "extinct"), taxonAlign_required_cols)
  columns <- c(taxonAlign_required_cols, optional)
  dplyr::tibble(
    column = columns,
    required = columns %in% taxonAlign_required_cols,
    darwin_core = unname(taxonAlign_column_rename[columns]),
    description = dplyr::coalesce(
      unname(taxonAlign_required_col_descriptions[columns]),
      ifelse(columns == "extinct", "TRUE for a taxon its source flags as extinct (load_taxonomic_resources() leaves these out by default).", NA_character_),
      "Optional; kept as-is."
    )
  )
}

#' Check a table is in taxonAlign's taxonomic reference format
#'
#' Checks a reference table against [taxonomic_reference_schema()]: every required column is present,
#' every record has a name, rank, status, dataset and ID, `taxon_ID` is unique, and every record leads
#' somewhere in the table -- an accepted record to itself, any other to another record's `taxon_ID`. Every data
#' release [load_taxonomic_resources()] downloads passes this check.
#'
#' [prepare_taxonomic_resources()] is more forgiving than this: it renames Darwin Core columns, and
#' drops (with a warning) a record with no `canonical_name`. Use this check on a reference you're
#' going to share or release, so that other people get the same results from it that you do.
#'
#' @param x A data frame.
#' @param name What to call `x` in the error message. Defaults to the expression passed as `x`.
#'
#' @return `x`, invisibly, if it passes. Otherwise an error listing every problem found.
#'
#' @examples
#' reference <- tibble::tibble(
#'   canonical_name = c("Boronia serrulata", "Boronia oldname"),
#'   scientific_name = c("Boronia serrulata Sm.", "Boronia oldname Sm."),
#'   taxon_rank = "species", taxonomic_status = c("accepted", "synonym"),
#'   taxonomic_dataset = "MY_LIST", genus = "Boronia",
#'   taxon_ID = c("1", "2"), accepted_name_usage_ID = c("1", "1")
#' )
#' check_taxonomic_reference(reference)
#'
#' @export
check_taxonomic_reference <- function(x, name = deparse(substitute(x))) {
  if (!is.data.frame(x)) stop("`", name, "` must be a data frame.", call. = FALSE)

  missing_cols <- setdiff(taxonAlign_required_cols, names(x))
  if (length(missing_cols) > 0) {
    stop(
      "`", name, "` is missing required column(s): ", paste(missing_cols, collapse = ", "),
      ". See `?taxonomic_reference_schema`.", call. = FALSE
    )
  }

  problems <- character(0)
  count <- function(i) format(sum(i), big.mark = ",")
  for (col in setdiff(taxonAlign_required_cols, "genus")) {
    blank <- is.na(x[[col]]) | as.character(x[[col]]) == ""
    if (any(blank)) problems <- c(problems, paste0(count(blank), " record(s) have no `", col, "`"))
  }
  taxon_ID <- as.character(x$taxon_ID)
  accepted_ID <- as.character(x$accepted_name_usage_ID)
  duplicated_ID <- !is.na(taxon_ID) & duplicated(taxon_ID)
  if (any(duplicated_ID)) {
    problems <- c(problems, paste0(count(duplicated_ID), " record(s) share a `taxon_ID` with an earlier record"))
  }
  accepted <- x$taxonomic_status %in% "accepted"
  not_self <- accepted & !is.na(accepted_ID) & accepted_ID != taxon_ID
  if (any(not_self)) {
    problems <- c(problems, paste0(count(not_self), " accepted record(s) have an `accepted_name_usage_ID` other than their own `taxon_ID`"))
  }
  dangling <- !is.na(accepted_ID) & !accepted_ID %in% taxon_ID
  if (any(dangling)) {
    problems <- c(problems, paste0(count(dangling), " record(s) have an `accepted_name_usage_ID` that isn't any record's `taxon_ID`"))
  }

  if (length(problems) > 0) {
    stop(
      "`", name, "` isn't in taxonAlign's taxonomic reference format:\n",
      paste0("- ", problems, collapse = "\n"), "\nSee `?taxonomic_reference_schema`.", call. = FALSE
    )
  }
  invisible(x)
}
