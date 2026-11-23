# Three APCalign features ported in bb134cb (2026-11-14) and kept by the user (2026-11-23): the
# closing summary create_taxonomic_update_lookup() prints (APCalign's summarise_update_lookup(), its
# #131), the `quiet` argument, and the data version stamped on aligned_reason (APCalign #281). Their
# tests went with test-apcalign_ported.R, which ran against the whole live APC; these use the small
# hand-built fixtures instead.

lookup_message <- function(...) {
  withr::local_options(cli.num_colors = 1) # no colour codes in the counts
  msgs <- character(0)
  withCallingHandlers(
    create_taxonomic_update_lookup(...),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  strsplit(paste(msgs, collapse = ""), "\n")[[1]]
}

test_that("create_taxonomic_update_lookup() prints a summary of what it did", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  names <- c("Boronia serrulata", "Boronia oldname", "Boronia sp.", "Rutaceae", "Oldorderia",
             "Completely unrelated nonsense")

  expect_equal(lookup_message(names, resources), c(
    "Summary of 6 names:",
    "  -> 2 aligned to a species or infraspecific taxon (2 in TEST)",
    "  -> 1 aligned only to a genus and 1 only to a family",
    "  -> 1 aligned to another rank",
    "  -> 1 could not be aligned",
    # the species synonym and the order synonym
    "  -> 2 aligned names were updated to a different name (e.g. a synonym to its accepted name, or an outdated genus to the current one)"
  ))
})

test_that("the summary counts each input name once, and leaves out the 'another rank' line when there are none", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  expect_equal(lookup_message(c("Boronia serrulata", "Boronia serrulata", "Boronia oldname"), resources), c(
    "Summary of 2 names:",
    "  -> 2 aligned to a species or infraspecific taxon (2 in TEST)",
    "  -> 0 aligned only to a genus and 0 only to a family",
    "  -> 0 could not be aligned",
    "  -> 1 aligned names were updated to a different name (e.g. a synonym to its accepted name, or an outdated genus to the current one)"
  ))
})

test_that("the summary reports names leading to more than one accepted name, under either taxonomic_splits option", {
  # "Oldgenus alba" is a synonym of two accepted species in one genus. This is the case whose summary
  # once built a two-billion-element vector and hung (collapse_to_higher_taxon)
  # (with authorships: a name matched exactly with its authorship isn't treated as a split)
  reference <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Newgenus alba", "Newgenus alba (Smith, 1900)", "species", "accepted", "Newgenus", "a1", "a1",
    "Newgenus beta", "Newgenus beta Jones, 1850", "species", "accepted", "Newgenus", "a2", "a2",
    "Oldgenus alba", "Oldgenus alba Smith, 1900", "species", "synonym", "Oldgenus", "s1", "a1",
    "Oldgenus alba", "Oldgenus alba Smith, 1900", "species", "synonym", "Oldgenus", "s2", "a2"
  ) |>
    dplyr::mutate(taxonomic_dataset = "T")
  resources <- prepare_taxonomic_resources(reference)

  most_likely <- lookup_message("Oldgenus alba", resources)
  expect_equal(most_likely[length(most_likely)], paste0(
    "  -> 1 names could refer to more than one currently accepted taxon. With `taxonomic_splits = ",
    "\"most_likely_species\"`, `suggested_name` gives the most likely species and lists the alternatives in square brackets."
  ))
  # a split isn't counted as an update to a different name
  expect_true("  -> 0 aligned names were updated to a different name (e.g. a synonym to its accepted name, or an outdated genus to the current one)" %in% most_likely)

  collapsed <- lookup_message("Oldgenus alba", resources, taxonomic_splits = "collapse_to_higher_taxon")
  expect_equal(collapsed[length(collapsed)], paste0(
    "  -> 1 names could refer to more than one currently accepted taxon. With `taxonomic_splits = ",
    "\"collapse_to_higher_taxon\"`, they were collapsed to genus, and `suggested_name` lists the possible names."
  ))
})

test_that("quiet = TRUE turns the summary off", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  expect_message(create_taxonomic_update_lookup("Boronia serrulata", resources), "Summary of")
  expect_no_message(create_taxonomic_update_lookup("Boronia serrulata", resources, quiet = TRUE))
  expect_equal(
    create_taxonomic_update_lookup("Boronia oldname", resources, quiet = TRUE),
    suppressMessages(create_taxonomic_update_lookup("Boronia oldname", resources))
  )
})

test_that("align_taxa() and update_taxa() accept quiet, as APCalign's do, and print nothing either way", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  expect_no_message(aligned <- align_taxa("Boronia oldname", resources, quiet = FALSE))
  expect_equal(align_taxa("Boronia oldname", resources, quiet = TRUE), aligned)
  expect_no_message(updated <- update_taxa(aligned, resources, quiet = FALSE))
  expect_equal(update_taxa(aligned, resources, quiet = TRUE), updated)
})

test_that("aligned_reason names the data version matched against, where it's known", {
  reason <- function(reference) align_taxa("Boronia serrulata", reference)$aligned_reason

  # a dataset from a taxonAlign data release (load_taxonomic_resources() sets "data_release")
  released <- sample_taxonomic_resources()
  attr(released, "data_release") <- "2026-11-14"
  expect_match(reason(released), " in TEST (taxonAlign data release 2026-11-14)", fixed = TRUE)
  # ...also in a list of tables, as load_taxonomic_resources() returns
  expect_match(reason(list(TEST = released)), " in TEST (taxonAlign data release 2026-11-14)", fixed = TRUE)
  # ...and through prepare_taxonomic_resources()
  expect_match(reason(prepare_taxonomic_resources(released)), " in TEST (taxonAlign data release 2026-11-14)", fixed = TRUE)

  # a loader's own "version" attribute (taxonAlign.dataprep's load_WCVP(), load_CatalogueOfLife(), ...)
  versioned <- sample_taxonomic_resources()
  attr(versioned, "version") <- "16"
  expect_match(reason(versioned), " in TEST (TEST version 16)", fixed = TRUE)

  # no version known: the dataset alone, no brackets
  expect_match(reason(sample_taxonomic_resources()), " in TEST$")
})

test_that("each dataset in a combined reference gets its own version", {
  first <- sample_taxonomic_resources() |> dplyr::filter(.data$canonical_name == "Boronia serrulata")
  attr(first, "data_release") <- "2026-11-14"
  second <- sample_taxonomic_resources() |>
    dplyr::filter(.data$canonical_name == "Boronia oldname") |>
    dplyr::mutate(taxonomic_dataset = "OTHER", accepted_name_usage_ID = .data$taxon_ID, taxonomic_status = "accepted")
  attr(second, "version") <- "2"

  out <- align_taxa(c("Boronia serrulata", "Boronia oldname"), list(first, second))
  expect_match(out$aligned_reason[1], " in TEST (taxonAlign data release 2026-11-14)", fixed = TRUE)
  expect_match(out$aligned_reason[2], " in OTHER (OTHER version 2)", fixed = TRUE)
})
