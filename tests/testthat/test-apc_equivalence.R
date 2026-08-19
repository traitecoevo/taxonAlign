# Issue #10: confirm that, given the *same* real APC data, taxonAlign's align_taxa()/
# create_taxonomic_update_lookup() align/update a curated set of real names the same way APCalign's
# own align_taxa()/create_taxonomic_update_lookup() do -- not just plausible-looking output on a
# hand-built fixture. Needs real network access (APCalign::load_taxonomic_resources() downloads/
# refreshes a cached APC snapshot) and a reasonably current APCalign install, so this is skipped
# rather than run unconditionally.
#
# Discovered a real bug while first writing this test (not a fixture gap):
# prepare_taxonomic_resources() used to split species purely by the *literal* taxonomic_status string
# (`split(x, x$taxonomic_status)`), so only rows whose status was the exact string "synonym" ended up
# in resources$species$synonym. Real APC data uses ~18 distinct non-accepted status labels ("basionym",
# "nomenclatural synonym", "taxonomic synonym", "orthographic variant", "misapplied", "excluded", ...)
# -- never literally "synonym" -- so essentially all real APC synonym matching was silently inert
# (every one of those rows sat in its own orphaned resources$species$<status> list element that
# match_taxa() never references). Fixed by bucketing on "accepted" vs "not accepted" rather than the
# literal status string -- see the fix and its comment in prepare_taxonomic_resources.R.

test_that("taxonAlign aligns/updates a curated set of real names the same way APCalign does", {
  testthat::skip_if_not_installed("APCalign")
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  suppressMessages(APC <- APCalign::load_taxonomic_resources())

  # Combine APC's accepted + synonym tables at species, genus and family rank into one flat table --
  # family_accepted is missing a taxonomic_dataset column (unlike every other APC table here), so it's
  # backfilled with "APC" (the value every other APC table already uses) to match, rather than being
  # left NA by dplyr::bind_rows().
  combined <- dplyr::bind_rows(
    APC$APC_accepted, APC$APC_synonyms,
    APC$genera_accepted, APC$genera_synonym,
    APC$family_accepted |> dplyr::mutate(taxonomic_dataset = "APC"),
    APC$family_synonym
  )
  resources <- prepare_taxonomic_resources(combined)

  # The same names APCalign's own test suite uses to check "consistency with previous runs"
  # (traitecoevo/APCalign tests/testthat/test-operation_outputs.R) -- deliberately spans exact
  # accepted-name matches, an exact match to a non-"accepted"/non-"synonym"-labelled synonym
  # ("Commersonia rosea", status "basionym"), a taxonomic split ("Justicia procumbens"), a genuine
  # misspelling requiring species-level fuzzy matching ("Athrotaxis laxiflolia"), and two names that
  # only resolve to genus rank ("Hibbertia sp.", "Galactia striata").
  taxa <- c(
    "Banksia integrifolia", "Acacia longifolia", "Commersonia rosea", "Thelymitra pauciflora",
    "Justicia procumbens", "Hibbertia stricta", "Rostellularia adscendens", "Hibbertia sericea",
    "Hibbertia sp.", "Athrotaxis laxiflolia", "Genoplesium insigne", "Polypogon viridis",
    "Acacia aneura", "Acacia paraneura", "Galactia striata"
  )

  # align_taxa() is the apples-to-apples comparison: both packages share the same design lineage for
  # the matching engine itself, and should agree on aligned_name/taxon_rank for every name regardless
  # of rank -- this is checked *before* either package's update step, which is where their designs
  # deliberately diverge (see below).
  aligned_taxonAlign <- align_taxa(taxa, resources) |> dplyr::arrange(original_name)
  aligned_APCalign <- suppressMessages(APCalign::align_taxa(taxa, resources = APC, quiet = TRUE)) |>
    dplyr::arrange(original_name)

  expect_equal(aligned_taxonAlign$original_name, aligned_APCalign$original_name)
  expect_equal(aligned_taxonAlign$aligned_name, aligned_APCalign$aligned_name)
  expect_equal(aligned_taxonAlign$taxon_rank, aligned_APCalign$taxon_rank)

  # accepted_name (post-update) only needs to agree outside genus/family rank. taxonAlign's
  # update_taxa() is deliberately rank-agnostic (it resolves a matched genus/family/etc. name forward
  # too, not just species, and refreshes taxon_rank to the *resolved* name's rank), so it legitimately
  # returns a real accepted_name (e.g. "Hibbertia") for a genus-rank match where APCalign's rank-specific
  # update functions leave it NA, and a refreshed taxon_rank (e.g. "subspecies", after a taxonomic
  # split resolves "Justicia procumbens" to "Rostellularia adscendens subsp. dallachyi") where APCalign
  # keeps the aligned name's original rank ("species"). Both are documented design generalisations (see
  # CLAUDE.md), not discrepancies to chase -- so only accepted_name is compared here, and only for
  # species-complex ranks where the two conventions can't diverge.
  updated_taxonAlign <- create_taxonomic_update_lookup(taxa, resources) |> dplyr::arrange(original_name)
  updated_APCalign <- suppressMessages(
    APCalign::create_taxonomic_update_lookup(taxa, resources = APC, quiet = TRUE)
  ) |>
    dplyr::arrange(original_name)

  comparable_rank <- !updated_APCalign$taxon_rank %in% c("genus", "family")
  expect_equal(
    updated_taxonAlign$accepted_name[comparable_rank], updated_APCalign$accepted_name[comparable_rank]
  )
})
