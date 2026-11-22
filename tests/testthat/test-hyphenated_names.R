# Hyphenated genera (ICN Art. 20.3: "Neo-uvaria") and epithets ("Polygonia c-album", "Capsella
# bursa-pastoris"). APCalign::strip_names() turns the hyphen into a space, splitting one word into two
# and shifting every word after it -- found aligning a Malaysian plant list against the WCVP
# (traitecoevo/taxonAlign.dataprep#1), where a bare "Neo-uvaria" crashed the whole align_taxa() call.

hyphen_reference <- function() {
  tibble::tribble(
    ~canonical_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Neo-uvaria", "genus", "accepted", "Neo-uvaria", "g1", "g1",
    "Neo-uvaria acuminatissima", "species", "accepted", "Neo-uvaria", "s1", "s1",
    "Neo-uvaria foveolata", "species", "accepted", "Neo-uvaria", "s2", "s2",
    "Uvaria", "genus", "accepted", "Uvaria", "g2", "g2",
    "Uvaria grandiflora", "species", "accepted", "Uvaria", "s3", "s3",
    "Polygonia", "genus", "accepted", "Polygonia", "g3", "g3",
    "Polygonia c-album", "species", "accepted", "Polygonia", "s4", "s4",
    "Polygonia c-aureum", "species", "accepted", "Polygonia", "s5", "s5"
  ) |>
    dplyr::mutate(scientific_name = canonical_name, taxonomic_dataset = "TEST")
}

test_that("strip_names_keep_hyphens() keeps a hyphen between letters, and strips everything else", {
  expect_equal(
    strip_names_keep_hyphens(c("Neo-uvaria sp.", "Polygonia c-album", "Acacia sp. (R.J. Smith 12-3)", NA)),
    c("neo-uvaria sp", "polygonia c-album", "acacia sp rj smith 12 3", NA)
  )
})

test_that("a bare hyphenated genus aligns to the genus, rather than crashing", {
  res <- prepare_taxonomic_resources(hyphen_reference())
  out <- align_taxa(c("Neo-uvaria", "Uvaria grandiflora"), res)

  expect_equal(out$aligned_name, c("Neo-uvaria", "Uvaria grandiflora"))
  expect_equal(out$taxon_rank, c("genus", "species"))
  expect_equal(out$taxon_ID, c("g1", "s3"))
})

test_that("'Genus sp.' and an unknown epithet under a hyphenated genus stay at genus rank", {
  # both used to "match" the first Neo-uvaria species, via a "binomial" of "neo uvaria"
  res <- prepare_taxonomic_resources(hyphen_reference())
  out <- align_taxa(c("Neo-uvaria sp.", "Neo-uvaria fooensis"), res)

  expect_equal(out$taxon_rank, c("genus", "genus"))
  expect_equal(out$taxon_ID, c("g1", "g1"))
  expect_equal(out$aligned_name[1], "Neo-uvaria sp.")
})

test_that("species under a hyphenated genus, and hyphenated epithets, match exactly and fuzzily", {
  res <- prepare_taxonomic_resources(hyphen_reference())
  out <- align_taxa(
    c("Neo-uvaria acuminatissima", "Neo-uvaria foveolatta", "Polygonia c-aureum", "Polygonia c-aureum var. x"),
    res
  )

  expect_equal(
    out$aligned_name,
    c("Neo-uvaria acuminatissima", "Neo-uvaria foveolata", "Polygonia c-aureum", "Polygonia c-aureum")
  )
  expect_equal(out$taxon_ID, c("s1", "s2", "s5", "s5"))
})
