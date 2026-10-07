# Names that lead to more than one accepted name: APCalign's `taxonomic_splits` convention -- one
# suggested, the others listed -- with candidates ordered by status, then a shared epithet, then an
# accepted name no younger than the name itself, then oldest, then alphabetical.

split_reference <- function() {
  tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    # tie on status: Oldgenus alba is a synonym of two taxa; Newgenus alba shares its epithet
    "Newgenus alba", "Newgenus alba (Smith, 1900)", "species", "accepted", "Newgenus", "a1", "a1",
    "Newgenus beta", "Newgenus beta Jones, 1850", "species", "accepted", "Newgenus", "a2", "a2",
    "Oldgenus alba", "Oldgenus alba Smith, 1900", "species", "synonym", "Oldgenus", "s1", "a1",
    "Oldgenus alba", "Oldgenus alba Smith, 1900", "species", "synonym", "Oldgenus", "s2", "a2",
    # no shared epithet: only Newgenus delta (1880) is older than Oldgenus gamma (1890)
    "Newgenus delta", "Newgenus delta Brown, 1880", "species", "accepted", "Newgenus", "a3", "a3",
    "Newgenus epsilon", "Newgenus epsilon Brown, 1950", "species", "accepted", "Newgenus", "a4", "a4",
    "Oldgenus gamma", "Oldgenus gamma Grey, 1890", "species", "synonym", "Oldgenus", "s3", "a4",
    "Oldgenus gamma", "Oldgenus gamma Grey, 1890", "species", "synonym", "Oldgenus", "s4", "a3",
    # status decides: a misapplication loses to a synonym
    "Oldgenus zeta", "Oldgenus zeta Grey, 1890", "species", "misapplied", "Oldgenus", "s5", "a1",
    "Oldgenus zeta", "Oldgenus zeta Grey, 1890", "species", "synonym", "Oldgenus", "s6", "a3",
    # a species also listed under its own nominotypical subspecies: not a split
    "Newgenus beta beta", "Newgenus beta beta Jones, 1850", "subspecies", "accepted", "Newgenus", "a5", "a5",
    "Newgenus beta", "Newgenus beta Jones, 1850", "species", "synonym", "Newgenus", "s7", "a5"
  )
}

test_that("a name leading to more than one accepted name gets one suggestion plus the alternatives", {
  resources <- prepare_taxonomic_resources(dplyr::mutate(split_reference(), taxonomic_dataset = "T"))
  out <- create_taxonomic_update_lookup(c("Oldgenus alba", "Oldgenus gamma", "Oldgenus zeta", "Newgenus beta"), resources)

  expect_equal(out$accepted_name, c("Newgenus alba", "Newgenus delta", "Newgenus delta", "Newgenus beta"))
  expect_equal(out$alternative_possible_names[1:3], c("Newgenus beta (synonym)", "Newgenus epsilon (synonym)", "Newgenus alba (misapplied)"))
  expect_equal(out$suggested_name[1], "Newgenus alba [alternative possible names: Newgenus beta (synonym)]")
  # a species also listed under its own nominotypical subspecies isn't ambiguous
  expect_true(is.na(out$alternative_possible_names[4]))
  expect_equal(out$suggested_name[4], "Newgenus beta")
})

test_that("taxonomic_splits = 'collapse_to_higher_taxon' collapses a split within one genus", {
  resources <- prepare_taxonomic_resources(dplyr::mutate(split_reference(), taxonomic_dataset = "T"))
  out <- create_taxonomic_update_lookup("Oldgenus alba", resources, taxonomic_splits = "collapse_to_higher_taxon")
  expect_equal(out$suggested_name, "Newgenus sp. [collapsed names: Newgenus alba (synonym) | Newgenus beta (synonym)]")
  expect_equal(out$taxon_rank, "genus")
  expect_true(is.na(out$accepted_name))
})

test_that("a name matched with its authorship isn't treated as a split", {
  ref <- tibble::tribble(
    ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Camponotus reticulatus", "Camponotus reticulatus Roger, 1863", "species", "accepted", "Camponotus", "a1", "a1",
    "Camponotus spenceri", "Camponotus spenceri Clark, 1930", "species", "accepted", "Camponotus", "a2", "a2",
    "Camponotus reticulatus", "Camponotus reticulatus Kirby, 1896", "species", "synonym", "Camponotus", "s1", "a2"
  ) |> dplyr::mutate(taxonomic_dataset = "T")
  out <- create_taxonomic_update_lookup(c("Camponotus reticulatus", "Camponotus reticulatus Kirby, 1896"), prepare_taxonomic_resources(ref))
  expect_equal(out$accepted_name, c("Camponotus reticulatus", "Camponotus spenceri"))
  # an accepted name is just that name, never treated as ambiguous
  expect_equal(out$alternative_possible_names, c(NA_character_, NA_character_))
})

test_that("a genus listed as a synonym of its own nominotypical subgenus isn't treated as a split", {
  ref <- tibble::tribble(
    ~canonical_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Acritus", "genus", "accepted", "Acritus", "g1", "g1",
    "Acritus", "subgenus", "accepted", "Acritus", "sg1", "sg1",
    "Acritus", "genus", "primary synonym", "Acritus", "g2", "sg1",
    "Acritus alba", "species", "accepted", "Acritus", "a1", "a1"
  ) |> dplyr::mutate(scientific_name = canonical_name, taxonomic_dataset = "T")
  out <- create_taxonomic_update_lookup("Acritus BF01", prepare_taxonomic_resources(ref))
  expect_true(is.na(out$alternative_possible_names))
  expect_equal(out$suggested_name, "Acritus")
})
