test_that("prepare_taxonomic_resources errors clearly when required columns are missing", {
  expect_error(
    prepare_taxonomic_resources(dplyr::tibble(taxon_name = "Boronia serrulata")),
    "missing required column"
  )
})

test_that("prepare_taxonomic_resources errors when there are no species-level rows", {
  no_species <- sample_taxon_resources() |> dplyr::filter(taxon_rank != "species", taxon_rank != "variety")
  expect_error(prepare_taxonomic_resources(no_species), "no rows at species/infraspecific rank")
})

test_that("prepare_taxonomic_resources splits by rank and status, deriving all ranks present", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())

  expect_setequal(names(resources), c("species", "genus", "family", "tribe", "subgenus", "subgenus_v2"))
  expect_setequal(names(resources$species), c("accepted", "synonym"))
  expect_equal(nrow(resources$species$accepted), 2) # species + variety
  expect_equal(nrow(resources$species$synonym), 1)
  expect_equal(resources$genus$canonical_name, "Boronia")
  expect_equal(resources$family$canonical_name, "Rutaceae")
  expect_equal(resources$tribe$canonical_name, "Zanthoxyleae")
})

test_that("prepare_taxonomic_resources builds both subgenus conventions", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())

  expect_equal(resources$subgenus$canonical_name, "Valvatae")
  expect_equal(resources$subgenus_v2$genus_and_subgenus, "Boronia (Valvatae)")
})

test_that("canonical_name falls back to taxon_name when NA", {
  resources <- prepare_taxonomic_resources(sample_taxon_resources())
  # the variety row had canonical_name = NA in the input
  expect_true("Boronia pinnata var. pinnata" %in% resources$species$accepted$canonical_name)
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
    prepare_taxonomic_resources(sample_taxon_resources(), taxon_ranks_to_check = c("genus", "order")),
    "not present"
  )
})
