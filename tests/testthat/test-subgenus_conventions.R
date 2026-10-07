# Two reference conventions for species-level names exist: with the subgenus written into the name
# (AFD's CSV export: "Pardalotus (Pardalotinus) striatus") and without it (most other sources). Matching
# runs on the subgenus-free form, so raw names written either way must match a reference written either
# way; output names are then reported as the reference writes them, and subgenus-rank output is always
# "Genus (Subgenus)".

subgenus_reference <- function(with_subgenus) {
  sp <- function(x) if (with_subgenus) x else strip_subgenus_from_name(x)
  tibble::tribble(
    ~canonical_name, ~taxon_rank, ~taxonomic_status, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Pardalotus", "genus", "accepted", "Pardalotus", "g1", "g1",
    "Pardalotinus", "subgenus", "accepted", "Pardalotus", "sg1", "sg1",
    "Pardalotus (Pardalotinus) striatus", "species", "accepted", "Pardalotus", "sp1", "sp1",
    "Pardalotus (Pardalotinus) striatus striatus", "subspecies", "accepted", "Pardalotus", "ssp1", "ssp1",
    "Pardalotus (Pardalotinus) striatus kingi", "subspecies", "synonym", "Pardalotus", "syn1", "ssp1",
    "Pardalotus (Pardalotinus) ornatus", "species", "synonym", "Pardalotus", "syn2", "sp1"
  ) |>
    dplyr::mutate(
      canonical_name = ifelse(taxon_rank %in% c("species", "subspecies"), sp(canonical_name), canonical_name),
      scientific_name = canonical_name, taxonomic_dataset = "TEST"
    )
}

queries <- c(
  "Pardalotus striatus", "Pardalotus (Pardalotinus) striatus", "Pardalotus striatus striatus",
  "Pardalotus ornatus", "Pardalotus (Pardalotinus) ornatus", "Pardalotinus", "Pardalotus (Pardalotinus)"
)

test_that("strip_subgenus_from_name only touches the 'Genus (Subgenus) epithet' shape", {
  expect_equal(
    strip_subgenus_from_name(c(
      "Pardalotus (Pardalotinus) striatus", "Pardalotus (Pardalotinus) striatus kingi",
      "Pardalotus striatus", "Agaricia papillosa (pars)", "Calodema (regale species group)",
      "Acanthiza (Geobasileus)"
    )),
    c(
      "Pardalotus striatus", "Pardalotus striatus kingi", "Pardalotus striatus",
      "Agaricia papillosa (pars)", "Calodema (regale species group)", "Acanthiza (Geobasileus)"
    )
  )
})

for (with_subgenus in c(TRUE, FALSE)) {
  test_that(paste0("queries written either way resolve correctly (reference written ",
                   if (with_subgenus) "with" else "without", " subgenus)"), {
    resources <- prepare_taxonomic_resources(subgenus_reference(with_subgenus))
    out <- create_taxonomic_update_lookup(queries, resources)
    display <- function(x) if (with_subgenus) x else strip_subgenus_from_name(x)

    # a plain binomial must resolve to the accepted species itself -- not to a subspecies synonym
    # sharing its first two words (the failure seen against AFD's CSV export before this fix)
    expect_equal(out$taxon_rank[1:2], c("species", "species"))
    expect_equal(out$taxonomic_status_aligned[1:2], c("accepted", "accepted"))
    expect_equal(out$accepted_name[1:2], rep(display("Pardalotus (Pardalotinus) striatus"), 2))
    expect_equal(out$aligned_name[1:2], rep(display("Pardalotus (Pardalotinus) striatus"), 2))

    expect_equal(out$accepted_name[3], display("Pardalotus (Pardalotinus) striatus striatus"))
    # a synonym written either way resolves to its accepted name
    expect_equal(out$accepted_name[4:5], rep(display("Pardalotus (Pardalotinus) striatus"), 2))

    # subgenus-rank output is always "Genus (Subgenus)"
    expect_equal(out$taxon_rank[6:7], c("subgenus", "subgenus"))
    expect_equal(out$aligned_name[6:7], rep("Pardalotus (Pardalotinus)", 2))
    expect_equal(out$accepted_name[6:7], rep("Pardalotus (Pardalotinus)", 2))
  })
}
