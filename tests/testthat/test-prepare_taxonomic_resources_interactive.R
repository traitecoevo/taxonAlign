# All tests here supply `user_responses` throughout, exactly the way `traits.build` tests its own
# `metadata_add_traits()`/`metadata_add_locations()`/etc. -- never a real interactive session.

test_that("interactive = TRUE maps a raw table missing every optional/typed field", {
  raw <- tibble::tribble(
    ~name, ~authorship, ~rank, ~status_col, ~id,
    "Boronia serrulata", "Boronia serrulata Sm.", "species", "accepted", "1",
    "Boronia oldname", "Boronia oldname Sm.", "species", "synonym", "2"
  )

  resources <- prepare_taxonomic_resources(
    raw,
    interactive = TRUE,
    user_responses = list(
      `table 1` = list(
        already_aligned = FALSE,
        taxonomic_dataset = "TEST",
        canonical_name = "name",
        scientific_name = "authorship",
        taxon_rank = list(column = "rank", fixed_value = NULL),
        taxonomic_status = list(column = "status_col", fixed_value = NULL),
        genus = .taxonAlign_not_available,
        taxon_ID = "id",
        accepted_name_usage_ID = .taxonAlign_already_accepted
      ),
      additional_tables = list()
    )
  )

  expect_equal(resources$species$accepted$canonical_name, "Boronia serrulata")
  expect_equal(resources$species$accepted$taxonomic_dataset, "TEST")
  expect_equal(resources$species$accepted$accepted_name_usage_ID, "1") # self-referenced from taxon_ID
  expect_true(is.na(resources$species$accepted$genus))
})

test_that("interactive = TRUE with a fixed-value taxon_rank/taxonomic_status applies it to every row", {
  raw <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~genus, ~taxonomic_dataset,
    "Boronia serrulata", "Boronia serrulata Sm.", "Boronia", "TEST"
  )

  resources <- prepare_taxonomic_resources(
    raw,
    interactive = TRUE,
    user_responses = list(
      `table 1` = list(
        already_aligned = FALSE,
        taxon_rank = list(column = NULL, fixed_value = "species"),
        taxonomic_status = list(column = NULL, fixed_value = "accepted"),
        taxon_ID = .taxonAlign_generate_automatically,
        accepted_name_usage_ID = .taxonAlign_already_accepted
      ),
      additional_tables = list()
    )
  )

  expect_equal(resources$species$accepted$taxon_rank, "species")
  expect_equal(resources$species$accepted$taxonomic_status, "accepted")
  expect_equal(resources$species$accepted$taxon_ID, "table 1_1")
  expect_equal(resources$species$accepted$accepted_name_usage_ID, "table 1_1")
})

test_that("asserting already_aligned = TRUE errors clearly when columns are still genuinely missing", {
  raw <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Boronia serrulata", "Boronia serrulata Sm.", "species", "accepted", "Boronia", "1", "1"
  ) # missing `taxonomic_dataset`

  expect_error(
    prepare_taxonomic_resources(
      raw,
      interactive = TRUE,
      user_responses = list(`table 1` = list(already_aligned = TRUE))
    ),
    "already fully aligned.*taxonomic_dataset"
  )
})

test_that("a fully-correct table needs no per-field prompts, even with interactive = TRUE", {
  # `additional_tables = list()` bypasses the (always-asked, regardless of whether the table needed
  # column mapping) "any additional reference(s)?" loop -- without it, this would fall through to a
  # real (test-breaking) utils::menu() call. No other responses are supplied: if any per-field prompt
  # were actually attempted for this already-complete table, there'd be nothing to consult and it would
  # likewise fall through to a real prompt.
  resources <- prepare_taxonomic_resources(
    sample_taxon_resources(), interactive = TRUE, user_responses = list(additional_tables = list())
  )
  expect_equal(resources$species$accepted$canonical_name |> sort(), c("Boronia pinnata var. pinnata", "Boronia serrulata"))
})

test_that("multiple tables combine with a user-supplied priority order", {
  high_priority <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Boronia serrulata", "Boronia serrulata Sm.", "species", "accepted", "HIGH", "Boronia", "h1", "h1"
  )
  low_priority <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Boronia serrulata", "Boronia serrulata Ferdinandi.", "species", "accepted", "LOW", "Boronia", "l1", "l1"
  )

  resources <- prepare_taxonomic_resources(
    list(low = low_priority, high = high_priority),
    interactive = TRUE,
    user_responses = list(priority_order = c("high", "low"), additional_tables = list())
  )

  # "high" was bound first, so match()'s first-hit semantics prefer it for the duplicated name
  expect_equal(resources$species$accepted$taxonomic_dataset[1], "HIGH")
})

test_that("the 'any additional reference(s)?' loop adds more tables via user_responses$additional_tables", {
  first <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Boronia serrulata", "Boronia serrulata Sm.", "species", "accepted", "FIRST", "Boronia", "f1", "f1"
  )
  second <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Rutaceae", "Rutaceae Juss.", "family", "accepted", "SECOND", NA_character_, "s1", "s1"
  )

  resources <- prepare_taxonomic_resources(
    first,
    interactive = TRUE,
    user_responses = list(
      additional_tables = list(second),
      priority_order = c("table 1", "table 2")
    )
  )

  expect_setequal(names(resources), c("species", "family"))
  expect_equal(resources$species$accepted$taxonomic_dataset, "FIRST")
  expect_equal(resources$family$taxonomic_dataset, "SECOND")
})

test_that("interactive = FALSE (the default) still errors immediately, naming the table", {
  expect_error(
    prepare_taxonomic_resources(dplyr::tibble(canonical_name = "Boronia serrulata")),
    "table 1.*missing required column"
  )
})

test_that("a file path is read and processed", {
  path <- withr::local_tempfile(fileext = ".csv")
  readr::write_csv(sample_taxon_resources(), path)

  resources <- prepare_taxonomic_resources(path)
  expect_true("Boronia serrulata" %in% resources$species$accepted$canonical_name)
})
