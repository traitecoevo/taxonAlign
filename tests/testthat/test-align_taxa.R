test_that("align_taxa exact-matches a scientific name (with authorship)", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia serrulata Sm.", resources)

  expect_equal(out$aligned_name, "Boronia serrulata")
  expect_equal(out$taxonomic_status, "accepted")
  expect_equal(out$alignment_code, "match_01a_accepted_scientific_name_with_authorship")
})

test_that("align_taxa exact-matches a canonical name (no authorship)", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia serrulata", resources)

  expect_equal(out$aligned_name, "Boronia serrulata")
  expect_equal(out$alignment_code, "match_01c_accepted_canonical_name")
})

test_that("align_taxa matches a synonymous scientific name and reports its status", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia oldname Sm.", resources)

  expect_equal(out$aligned_name, "Boronia oldname")
  expect_equal(out$taxonomic_status, "synonym")
  expect_equal(out$alignment_code, "match_01b_synonym_scientific_name_with_authorship")
})

test_that("align_taxa matches a synonymous canonical name (no authorship)", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia oldname", resources)

  expect_equal(out$aligned_name, "Boronia oldname")
  expect_equal(out$taxonomic_status, "synonym")
  expect_equal(out$alignment_code, "match_01d_synonym_canonical_name")
})

test_that("align_taxa falls back to genus level for a bare 'genus sp.' name", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia sp.", resources)

  expect_equal(out$taxon_rank, "genus")
  expect_true(grepl("^Boronia sp\\.", out$aligned_name))
})

test_that("align_taxa falls back to a non-hardcoded higher rank ('tribe')", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Zanthoxyleae sp.", resources)

  expect_equal(out$taxon_rank, "tribe")
  expect_true(grepl("^Zanthoxyleae sp\\.", out$aligned_name))
})

test_that("align_taxa matches the bracketed 'Genus (Subgenus) sp.' convention", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia (Valvatae) sp.", resources)

  expect_equal(out$taxon_rank, "subgenus")
  expect_true(grepl("^Boronia \\(Valvatae\\) sp\\.", out$aligned_name))
})

test_that("align_taxa matches the plain 'Subgenus sp.' convention", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Valvatae sp.", resources)

  expect_equal(out$taxon_rank, "subgenus")
  expect_true(grepl("^Valvatae sp\\.", out$aligned_name))
})

test_that("align_taxa fuzzy-matches a slightly misspelled canonical name", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia serulata", resources) # missing one 'r'

  expect_equal(out$aligned_name, "Boronia serrulata")
  expect_equal(out$alignment_code, "match_05a_fuzzy_accepted_canonical_name")
})

test_that("align_taxa leaves an unmatchable name unresolved rather than erroring", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Completely unrelated nonsense taxon", resources)

  expect_true(is.na(out$aligned_name))
})

test_that("taxon_ranks_to_check restricts which higher ranks align_taxa will use", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Zanthoxyleae sp.", resources, taxon_ranks_to_check = c("genus", "family"))

  expect_true(is.na(out$aligned_name))
})

test_that("align_taxa preserves length, order and duplicates of the input vector", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  names <- c("Boronia serrulata Sm.", NA, "Boronia serrulata Sm.", "Completely unrelated nonsense taxon")
  out <- align_taxa(names, resources)

  expect_equal(nrow(out), length(names))
  expect_equal(out$original_name, names)
  expect_equal(out$aligned_name[c(1, 3)], c("Boronia serrulata", "Boronia serrulata"))
  expect_true(is.na(out$aligned_name[2]))
})

test_that("identifier is recycled or validated against original_name length", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  expect_error(
    align_taxa(c("a", "b"), resources, identifier = c("x", "y", "z")),
    "`identifier` must have length 1"
  )

  out <- align_taxa("Boronia sp.", resources, identifier = "site1")
  expect_true(grepl("\\[site1\\]$", out$aligned_name))
})

test_that("full = TRUE returns the intermediate matching columns", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  out <- align_taxa("Boronia serrulata Sm.", resources, full = TRUE)

  expect_true(all(c("stripped_name", "trinomial", "binomial", "word_one", "checked", "known") %in% names(out)))
})

test_that("align_taxa requires a non-empty original_name", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  expect_error(align_taxa(character(0), resources), "must have length > 0")
})

test_that("align_taxa gives a clear, actionable error when resources is missing", {
  expect_error(align_taxa("Boronia serrulata"), "prepare_taxonomic_resources")
})

test_that("align_taxa accepts a flat, already-formatted resources tibble directly", {
  # a common real mistake was passing a flat data frame (e.g.
  # generate_GBIF_taxonomic_reference_list()'s own output) directly, instead of running it through
  # prepare_taxonomic_resources() first -- rather than erroring, this is now auto-detected and
  # prepared automatically, since the table itself needs no interactive column mapping
  out_direct <- align_taxa("Boronia serrulata", resources = sample_taxonomic_resources())
  out_prepared <- align_taxa("Boronia serrulata", resources = prepare_taxonomic_resources(sample_taxonomic_resources()))

  expect_equal(out_direct, out_prepared)
  expect_equal(out_direct$aligned_name, "Boronia serrulata")
})

test_that("align_taxa gives a clear, actionable error when resources is a malformed list", {
  # genuinely the wrong shape (not a data frame, and not a prepare_taxonomic_resources()-style nested
  # list either) -- unlike a flat data frame, this can't be auto-prepared, so it should still error
  expect_error(
    align_taxa("Boronia serrulata", resources = list(foo = "bar")),
    "prepare_taxonomic_resources"
  )
})

test_that("progress = TRUE prints a progress bar and doesn't change the result (issue #5)", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())
  names <- c("Boronia serrulata Sm.", "Boronia oldname Sm.", "Completely unrelated nonsense taxon")

  expect_silent(out_quiet <- align_taxa(names, resources))
  expect_output(out_progress <- align_taxa(names, resources, progress = TRUE), "%")

  expect_equal(out_quiet, out_progress)
})
