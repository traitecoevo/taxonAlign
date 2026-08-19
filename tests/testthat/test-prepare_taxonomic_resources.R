test_that("prepare_taxonomic_resources errors clearly when required columns are missing", {
  expect_error(
    prepare_taxonomic_resources(dplyr::tibble(canonical_name = "Boronia serrulata")),
    "missing required column"
  )
})

test_that("prepare_taxonomic_resources renames raw Darwin Core columns, exactly like APCalign::load_taxonomic_resources()", {
  raw <- dplyr::tibble(
    canonicalName = "Boronia serrulata", scientificName = "Boronia serrulata Sm.",
    taxonRank = "species", taxonomicStatus = "accepted", taxonomic_dataset = "TEST",
    genus = "Boronia", taxonID = "sp1", acceptedNameUsageID = "sp1"
  )
  resources <- prepare_taxonomic_resources(raw)

  expect_equal(resources$species$accepted$canonical_name, "Boronia serrulata")
  expect_equal(resources$species$accepted$taxon_ID, "sp1")
})

test_that("prepare_taxonomic_resources errors when there are no species-level rows", {
  no_species <- sample_taxon_resources() |> dplyr::filter(taxon_rank != "species", taxon_rank != "variety")
  expect_error(prepare_taxonomic_resources(no_species), "no rows at species/infraspecific rank")
})

test_that("prepare_taxonomic_resources splits by rank and status, deriving all ranks present", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())

  expect_setequal(names(resources), c("species", "genus", "family", "order", "tribe", "subgenus", "subgenus_v2"))
  expect_setequal(names(resources$species), c("accepted", "synonym"))
  expect_equal(nrow(resources$species$accepted), 2) # species + variety
  expect_equal(nrow(resources$species$synonym), 2) # "oldname" + "missingaccepted"
  # genus/order each have an accepted row and a synonym row, unlike species -- prepare_taxonomic_resources()
  # only splits `species` further by taxonomic_status, so these stay as one combined table per rank
  expect_setequal(resources$genus$canonical_name, c("Boronia", "Boronella"))
  expect_setequal(resources$order$canonical_name, c("Sapindales", "Oldorderia"))
  expect_equal(resources$family$canonical_name, "Rutaceae")
  expect_equal(resources$tribe$canonical_name, "Zanthoxyleae")
})

test_that("prepare_taxonomic_resources builds both subgenus conventions", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())

  expect_equal(resources$subgenus$canonical_name, "Valvatae")
  expect_equal(resources$subgenus_v2$genus_and_subgenus, "Boronia (Valvatae)")
})

test_that("a row with a missing (NA) canonical_name is dropped, with a warning", {
  # regression test: leaving such a row in is an active hazard, not just untidy data -- `NA %in% x` is
  # TRUE whenever `x` contains an NA, so a legitimately-failed fuzzy_match() (which returns NA) would
  # otherwise spuriously "match" this row instead of correctly matching nothing at all.
  broken <- sample_taxon_resources()
  broken$canonical_name[broken$taxon_ID == "sp2"] <- NA_character_

  expect_warning(
    resources <- prepare_taxonomic_resources(broken),
    "missing \\(NA\\) `canonical_name`"
  )
  # the variety row ("sp2") should be gone, while everything else survives
  expect_false("sp2" %in% resources$species$accepted$taxon_ID)
  expect_true("sp1" %in% resources$species$accepted$taxon_ID)
})

test_that("taxon_ranks_to_check filters out unwanted higher ranks (and subgenus_v2 with subgenus)", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources(), taxon_ranks_to_check = c("genus", "family"))

  expect_setequal(names(resources), c("species", "genus", "family"))
  expect_null(resources$tribe)
  expect_null(resources$subgenus)
  expect_null(resources$subgenus_v2)
})

test_that("taxon_ranks_to_check warns about ranks not present in the data", {
  expect_warning(
    prepare_taxonomic_resources(sample_taxon_resources(), taxon_ranks_to_check = c("genus", "class")),
    "not present"
  )
})
