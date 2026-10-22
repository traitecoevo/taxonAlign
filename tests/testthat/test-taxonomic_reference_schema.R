# The taxonomic reference format -- the hand-off to taxonAlign.dataprep and to users' own tables
# (issue #26).

test_that("taxonomic_reference_schema lists the eight required columns first, with their Darwin Core names", {
  schema <- taxonomic_reference_schema()
  expect_equal(schema$column[schema$required], taxonAlign_required_cols)
  expect_equal(schema$darwin_core[schema$column == "canonical_name"], "canonicalName")
  expect_false(anyNA(schema$description))
  expect_true(all(c("extinct", "scientific_name_authorship") %in% schema$column[!schema$required]))
})

test_that("check_taxonomic_reference passes a well-formed table, returning it invisibly", {
  # (the fixture's one synonym leading nowhere, "sp4", left out)
  reference <- dplyr::filter(sample_taxonomic_resources(), taxon_ID != "sp4")
  expect_invisible(out <- check_taxonomic_reference(reference))
  expect_equal(out, reference)
})

test_that("check_taxonomic_reference names missing columns", {
  expect_error(
    check_taxonomic_reference(dplyr::select(sample_taxonomic_resources(), -genus, -taxon_ID)),
    "missing required column\\(s\\): genus, taxon_ID"
  )
})

test_that("check_taxonomic_reference lists every problem at once", {
  # (the fixture already has one synonym, "sp4", leading to an ID that isn't in the table)
  bad <- sample_taxonomic_resources()
  bad$canonical_name[1] <- NA
  bad$taxon_ID[3] <- bad$taxon_ID[2]
  accepted <- which(bad$taxonomic_status == "accepted")
  bad$accepted_name_usage_ID[accepted[length(accepted)]] <- "elsewhere"
  err <- expect_error(check_taxonomic_reference(bad), "isn't in taxonAlign's taxonomic reference format")
  expect_match(conditionMessage(err), "1 record\\(s\\) have no `canonical_name`")
  expect_match(conditionMessage(err), "share a `taxon_ID`")
  expect_match(conditionMessage(err), "accepted record\\(s\\) have an `accepted_name_usage_ID` other than")
  expect_match(conditionMessage(err), "isn't any record's `taxon_ID`")
})
