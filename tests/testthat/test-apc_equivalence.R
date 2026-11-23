# Every taxonAlign call here passes include_bracketed_info = TRUE, and APCalign's output goes through
# apcalign_bare_form() (helper-apc.R) first: APCalign gives a bare name as "<name> sp. [<name>;
# <identifier>]", taxonAlign gives it plain by default, or with include_bracketed_info = TRUE as
# "<name> sp. [<identifier>]" (both approved differences, user's decisions 2026-11-22).
#
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
#
# Also confirmed, while adding hybrids/intergrades_affinis matching (issue #9), that real APC data can
# still have the same lookup key repeat under different taxonomic_status labels ("Genoplesium insigne"
# above is one such case) -- match_taxa()'s first-hit match() semantics need the row order within each
# resources$<rank>$<status> table to prefer the most reliable status when that happens, which is what
# taxonAlign_taxonomic_status_priority (prepare_taxonomic_resources.R) now sorts by, ported and
# extended from APCalign's own relevel_taxonomic_status_preferred_order().

# Loads a real, live APC snapshot -- shared by both tests below so each only has to build it once.
# `resources` flattens APCalign's own nested list into one taxonAlign-format table, the same way
# taxonAlign.dataprep's load_APC() does (repeated here so this package's tests don't depend on that
# one); `APC` itself is kept too, since the comparison calls below need APCalign::align_taxa()'s own
# `resources` shape directly.

test_that("taxonAlign aligns/updates a curated set of real names the same way APCalign does", {
  testthat::skip_if_not_installed("APCalign")
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  loaded <- load_apc_resources_for_test()
  APC <- loaded$APC
  resources <- loaded$resources

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
  aligned_taxonAlign <- align_taxa(taxa, resources, include_bracketed_info = TRUE) |> dplyr::arrange(original_name)
  aligned_APCalign <- suppressMessages(APCalign::align_taxa(taxa, resources = APC, quiet = TRUE)) |>
    dplyr::arrange(original_name)

  expect_equal(aligned_taxonAlign$original_name, aligned_APCalign$original_name)
  expect_equal(aligned_taxonAlign$aligned_name,
               apcalign_bare_form(aligned_APCalign$aligned_name, aligned_APCalign$original_name))
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
  updated_taxonAlign <- create_taxonomic_update_lookup(taxa, resources, include_bracketed_info = TRUE) |> dplyr::arrange(original_name)
  updated_APCalign <- suppressMessages(
    APCalign::create_taxonomic_update_lookup(taxa, resources = APC, quiet = TRUE)
  ) |>
    dplyr::arrange(original_name)

  comparable_rank <- !updated_APCalign$taxon_rank %in% c("genus", "family")
  expect_equal(
    updated_taxonAlign$accepted_name[comparable_rank], updated_APCalign$accepted_name[comparable_rank]
  )

  # the APCalign columns taxonAlign added (traitecoevo/taxonAlign.dataprep#1) mean the same thing:
  # the accepted taxon's IDs, authorship and distribution, where APCalign gives one
  full_taxonAlign <- create_taxonomic_update_lookup(taxa, resources, full = TRUE, include_bracketed_info = TRUE) |> dplyr::arrange(original_name)
  full_APCalign <- suppressMessages(
    APCalign::create_taxonomic_update_lookup(taxa, resources = APC, quiet = TRUE, full = TRUE)
  ) |>
    dplyr::arrange(original_name)
  for (col in c("taxon_ID", "taxon_ID_genus", "scientific_name_ID", "scientific_name", "taxon_distribution", "subclass")) {
    given <- comparable_rank & !is.na(full_APCalign[[col]])
    expect_equal(full_taxonAlign[[col]][given], full_APCalign[[col]][given], label = col)
  }
})

test_that("taxonAlign matches oddball/edge-case real names the same way APCalign does", {
  testthat::skip_if_not_installed("APCalign")
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  loaded <- load_apc_resources_for_test()
  APC <- loaded$APC
  resources <- loaded$resources

  # A deliberately awkward set, exercising every opt-in match family issue #9 added plus a few
  # messy-real-world-data shapes -- APCalign's align_taxa() has no hybrids/intergrades_affinis toggle
  # (it always attempts these match families), so taxonAlign is called with both turned on to compare
  # fairly. Fabricated genus/epithet combinations (rather than real misapplied/uncertain APC names) are
  # used for the hybrid/intergrade/indecision/affinis cases specifically so neither package can
  # coincidentally species-level-fuzzy-match them to an unrelated real species -- that would make the
  # comparison a coin flip on both packages' fuzzy tie-breaking, not a real test of whether the same
  # *pattern* (hybrid marker, "--", "/", "aff."/"cf.") is detected the same way.
  taxa <- c(
    "Eucalyptus camaldulensus",              # genuine misspelling -> species-level fuzzy match
    "Eucalyptus sp.",                         # genus-only fallback
    "Acacia x fakehybridus",                  # fabricated hybrid name
    "Banksia cf. serrata",                    # graded/"cf." id of a real, unambiguous species
    "Acacia aff. completelyfakeepithet",      # fabricated graded/"affinis" id
    "Acacia -- Acacia aneura",                # intergrade between two named taxa
    "Acacia aneura/paraneura",                # collector's indecision between two taxa
    "  Eucalyptus   camaldulensis  ",         # messy extra whitespace
    "Acacia aneura var. aneura (widespread)"  # valid trinomial plus trailing free-text notes
  )

  out_taxonAlign <- align_taxa(taxa, resources, hybrids = TRUE, intergrades_affinis = TRUE, include_bracketed_info = TRUE)
  out_APCalign <- suppressMessages(APCalign::align_taxa(taxa, resources = APC, quiet = TRUE))

  expect_equal(out_taxonAlign$original_name, out_APCalign$original_name)
  expect_equal(out_taxonAlign$aligned_name, apcalign_bare_form(out_APCalign$aligned_name, out_APCalign$original_name))
  expect_equal(out_taxonAlign$taxon_rank, out_APCalign$taxon_rank)
})

# APCalign's own benchmark (benchmarks/apcalign_test_matches_alignments_updates.csv: 239 names APCalign
# checks its alignments and updates against), through both packages on the same live APC data, column
# by column. Added 2026-11-14 after a tester found differences the narrower tests above never compared
# (taxonAlign.dataprep#1): misspellings falling to genus (no imprecise/trinomial/binomial fuzzy
# blocks), synonym genera chosen over accepted ones, and "Genus sp. [original]" suggested names
# collapsing to a bare genus. The user's rule: taxonAlign gives what APCalign gives, possibly more,
# never less. Approved differences, so not compared:
# - names APCalign resolves via APNI (searched late, in APNI-only blocks; taxonAlign has no
#   names-only dataset concept, and this test's reference is APC alone);
# - accepted_name/taxon_ID/scientific_name_ID for a name aligned above species, which taxonAlign
#   fills in and APCalign leaves NA (user, 2026-11-14: "for some animal groups id-ing to genus is as
#   good as it gets") -- compared only where APCalign gives one.
# - alternatives for a match to an *accepted* name that is also another record's synonym (APCalign
#   lists them -- "Acaena x ovina [alternative possible names: ...]"; taxonAlign doesn't: user's
#   decision 2026-11-14, as on the AFD it added them to plain accepted names);
# - APCalign's split rules (its splits benchmark): taxonAlign keeps the ordering rules developed
#   with the user against the AFD; and taxonomic_splits = "return_all", not ported (user, 2026-11-14).
test_that("APCalign's benchmark names align and update the same way in both packages", {
  testthat::skip_if_not_installed("APCalign")
  testthat::skip_if_offline()
  testthat::skip_on_cran()

  loaded <- load_apc_resources_for_test()
  bench <- utils::read.csv(testthat::test_path("benchmarks", "apcalign_test_matches_alignments_updates.csv"))
  names <- bench$original_name
  idf <- "test_all_matches_TRUE"

  a_al <- suppressMessages(APCalign::align_taxa(
    names, resources = loaded$APC, full = TRUE, fuzzy_abs_dist = 3, fuzzy_rel_dist = 0.2,
    imprecise_fuzzy_matches = TRUE, APNI_matches = TRUE, fuzzy_matches = TRUE, identifier = idf, quiet = TRUE
  ))
  a_up <- suppressMessages(APCalign::update_taxonomy(a_al, resources = loaded$APC, taxonomic_splits = "most_likely_species", quiet = TRUE))
  t_al <- align_taxa(names, loaded$resources, imprecise_fuzzy_matches = TRUE, hybrids = TRUE,
                     intergrades_affinis = TRUE, identifier = idf, full = TRUE,
                     include_bracketed_info = TRUE)
  t_up <- update_taxa(t_al, loaded$resources)

  a_al <- a_al[match(names, a_al$original_name), ]
  a_up <- a_up[match(names, a_up$original_name), ]
  apc <- !a_al$taxonomic_dataset %in% "APNI"
  expect_gt(sum(apc), 200)

  expect_equal(t_al$aligned_name[apc], apcalign_bare_form(a_al$aligned_name, names)[apc])
  expect_equal(t_al$taxon_rank[apc], a_al$taxon_rank[apc])
  # approved difference (see above): no alternatives for a match to an accepted name
  a_sugg <- ifelse(t_up$taxonomic_status_aligned %in% "accepted",
                   sub(" \\[alternative possible names: .*\\]$", "", a_up$suggested_name), a_up$suggested_name)
  expect_equal(t_up$suggested_name[apc], apcalign_bare_form(a_sugg, names)[apc])
  for (col in c("accepted_name", "taxon_ID", "scientific_name_ID", "scientific_name")) {
    given <- apc & !is.na(a_up[[col]])
    expect_equal(t_up[[col]][given], a_up[[col]][given], label = col)
  }
})
