# Interactive column-mapping helpers for `prepare_taxonomic_resources(interactive = TRUE)` (issue #8).
#
# Modelled on `traits.build`'s `metadata_add_traits()`/`metadata_add_locations()`/
# `metadata_add_contexts()`/`metadata_create_template()` (see `traits.build`'s `R/setup.R`):
# `utils::menu()` for single-choice picks, a `readline()`-driven validated loop for ordered/multi
# selections, free-text `readline()` prompts where there's no column to pick, and -- critically for
# testability -- every prompt has a `user_response`/`user_responses` escape hatch that substitutes a
# supplied value for the real prompt, so tests never need a real interactive session.
#
# None of these are exported; they only ever run inside `prepare_taxonomic_resources()`.

# extra, non-column choices offered alongside real column names in various prompts below
.taxonAlign_same_as_canonical <- "(same as canonical_name)"
.taxonAlign_not_available <- "(not available)"
.taxonAlign_generate_automatically <- "(generate automatically)"
.taxonAlign_already_accepted <- "(every row is already an accepted name)"

# generic Yes/No prompt; `user_response`, if supplied, is a plain logical bypassing the real
# `utils::menu()` prompt
prompt_yes_no <- function(title, user_response = NULL) {
  if (!is.null(user_response)) return(isTRUE(user_response))

  choice <- utils::menu(c("Yes", "No"), title = title)
  if (choice == 0) stop("No selection made.", call. = FALSE)
  choice == 1
}

# The special "is this table already fully aligned?" gate asked once per table, before the per-field
# prompt sequence, when the automatic column_rename step didn't resolve everything on its own --
# e.g. the table may already be in taxonAlign's target shape (from an earlier
# prepare_taxonomic_resources()/generate_GBIF_taxonomic_reference_list() call) just under column names
# column_rename doesn't recognise. `user_response`, if supplied, is a plain logical.
prompt_already_aligned <- function(table_label, user_response = NULL) {
  prompt_yes_no(
    title = sprintf(
      paste0(
        "\n`%s` is missing some of the columns `prepare_taxonomic_resources()` expects by name. Is ",
        "it already fully aligned regardless (e.g. produced by an earlier `prepare_taxonomic_resources()`",
        " or `generate_GBIF_taxonomic_reference_list()` call, just under different column names)?"
      ),
      table_label
    ),
    user_response
  )
}

# single-choice pick from `names(data)` plus any `extra_choices`; `user_response`, if supplied,
# substitutes for the real `utils::menu()` prompt (and is validated against the same choice set)
prompt_select_column <- function(field, data, extra_choices = character(0), user_response = NULL) {
  choices <- c(names(data), extra_choices)

  if (!is.null(user_response)) {
    if (!user_response %in% choices) {
      stop(
        "`user_responses` value for `", field, "` (\"", user_response, "\") is not one of the ",
        "available choices: ", paste(choices, collapse = ", "), ".", call. = FALSE
      )
    }
    return(user_response)
  }

  i <- utils::menu(choices, title = sprintf("\nSelect a column (or option) for `%s`", field))
  if (i == 0) stop("No selection made for `", field, "`.", call. = FALSE)
  choices[i]
}

# free-text prompt (e.g. a typed taxonomic_dataset label); `user_response` bypasses `readline()`
prompt_free_text <- function(prompt_text, user_response = NULL) {
  if (!is.null(user_response)) return(user_response)
  readline(prompt = prompt_text)
}

# the "does this table have a column for `field`, or is every row the same value?" pattern used for
# `taxon_rank`/`taxonomic_status` -- returns list(column = ..., fixed_value = ...), exactly one non-NULL.
# `user_response`, if supplied, is itself that same list shape.
prompt_column_or_fixed_value <- function(field, data, example_value, user_response = NULL) {
  if (!is.null(user_response)) {
    if (!is.null(user_response$column)) return(list(column = user_response$column, fixed_value = NULL))
    return(list(column = NULL, fixed_value = user_response$fixed_value))
  }

  choice <- utils::menu(
    c("Select a column", "Every row has the same value"),
    title = sprintf("\nDoes the data have a column for `%s`, or is every row the same value?", field)
  )
  if (choice == 1) {
    list(column = prompt_select_column(field, data), fixed_value = NULL)
  } else if (choice == 2) {
    list(column = NULL, fixed_value = readline(
      prompt = sprintf("Enter the value for `%s` (e.g. \"%s\"): ", field, example_value)
    ))
  } else {
    stop("No selection made for `", field, "`.", call. = FALSE)
  }
}

# fills in whichever of `missing_cols` this table is missing, prompting (or consulting
# `user_responses`, a named list keyed by field) for each -- only ever called with a non-empty
# `missing_cols`, from `resolve_taxon_resources_table()`
map_missing_taxon_resources_columns <- function(data, missing_cols, table_label, user_responses = NULL) {

  if ("taxonomic_dataset" %in% missing_cols) {
    data$taxonomic_dataset <- prompt_free_text(
      sprintf(
        "Enter a label for the taxonomic dataset/source of `%s` (e.g. \"AFD\", \"iNaturalist\"): ",
        table_label
      ),
      user_responses$taxonomic_dataset
    )
  }

  if ("canonical_name" %in% missing_cols) {
    col <- prompt_select_column("canonical_name", data, user_response = user_responses$canonical_name)
    data$canonical_name <- data[[col]]
  }

  if ("scientific_name" %in% missing_cols) {
    col <- prompt_select_column(
      "scientific_name", data,
      extra_choices = .taxonAlign_same_as_canonical, user_response = user_responses$scientific_name
    )
    data$scientific_name <- if (identical(col, .taxonAlign_same_as_canonical)) data$canonical_name else data[[col]]
  }

  if ("taxon_rank" %in% missing_cols) {
    res <- prompt_column_or_fixed_value("taxon_rank", data, "species", user_responses$taxon_rank)
    data$taxon_rank <- if (!is.null(res$column)) data[[res$column]] else res$fixed_value
  }

  if ("taxonomic_status" %in% missing_cols) {
    res <- prompt_column_or_fixed_value("taxonomic_status", data, "accepted", user_responses$taxonomic_status)
    data$taxonomic_status <- if (!is.null(res$column)) data[[res$column]] else res$fixed_value
  }

  if ("genus" %in% missing_cols) {
    col <- prompt_select_column(
      "genus", data,
      extra_choices = .taxonAlign_not_available, user_response = user_responses$genus
    )
    data$genus <- if (identical(col, .taxonAlign_not_available)) NA_character_ else data[[col]]
  }

  # taxon_ID before accepted_name_usage_ID: the "every row is already accepted" self-reference option
  # below needs taxon_ID to already exist on `data`.
  if ("taxon_ID" %in% missing_cols) {
    col <- prompt_select_column(
      "taxon_ID", data,
      extra_choices = .taxonAlign_generate_automatically, user_response = user_responses$taxon_ID
    )
    data$taxon_ID <- if (identical(col, .taxonAlign_generate_automatically)) {
      paste0(table_label, "_", seq_len(nrow(data)))
    } else {
      as.character(data[[col]])
    }
  }

  if ("accepted_name_usage_ID" %in% missing_cols) {
    col <- prompt_select_column(
      "accepted_name_usage_ID", data,
      extra_choices = c(.taxonAlign_already_accepted, .taxonAlign_not_available),
      user_response = user_responses$accepted_name_usage_ID
    )
    if (identical(col, .taxonAlign_already_accepted)) {
      data$accepted_name_usage_ID <- data$taxon_ID
    } else if (identical(col, .taxonAlign_not_available)) {
      data$accepted_name_usage_ID <- NA_character_
      warning(
        "`accepted_name_usage_ID` was left unavailable for `", table_label, "` -- synonym rows in ",
        "this table won't resolve to a current accepted name via `update_taxa()` (they'll still align ",
        "via `align_taxa()`).", call. = FALSE
      )
    } else {
      data$accepted_name_usage_ID <- as.character(data[[col]])
    }
  }

  data
}

# prompts for a priority order across multiple tables (most authoritative first) when more than one
# is supplied; `user_response`, if supplied (`user_responses$priority_order`), is a vector of
# `table_labels` (or their positions) in the desired order, bypassing the real prompt
prompt_priority_order <- function(table_labels, user_response = NULL) {
  if (!is.null(user_response)) {
    idx <- if (is.character(user_response)) match(user_response, table_labels) else as.integer(user_response)
    if (anyNA(idx) || !setequal(idx, seq_along(table_labels))) {
      stop(
        "`user_responses$priority_order` must name (or index) each of the supplied tables exactly ",
        "once: ", paste(table_labels, collapse = ", "), ".", call. = FALSE
      )
    }
    return(table_labels[idx])
  }

  txt <- sprintf(
    paste0(
      "\nMultiple taxonomic reference tables were supplied. Enter their priority order (most ",
      "authoritative first -- i.e. which to prefer when a name appears in more than one), by number, ",
      "separated by spaces (e.g. '2 1 3'):\n%s\n"
    ),
    paste(sprintf("%d: %s", seq_along(table_labels), table_labels), collapse = "\n")
  )

  success <- FALSE
  while (!success) {
    cat(txt)
    i <- readline("\nPriority order: ")
    i <- suppressWarnings(as.integer(strsplit(i, " ")[[1]]))
    if (length(i) == length(table_labels) && setequal(i, seq_along(table_labels)) && !anyNA(i)) {
      success <- TRUE
    } else {
      message("Invalid selection -- please enter each table's number exactly once, separated by spaces.\n")
    }
  }
  table_labels[i]
}
