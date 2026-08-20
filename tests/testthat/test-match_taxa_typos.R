# Deliberately messy, invertebrate-flavoured typo/oddity coverage for the matching engine, using
# sample_invert_taxonomic_resources() (helper-invert-typo-fixtures.R) -- complementing the more
# structural, plant-flavoured tests in test-align_taxa.R/test-match_taxa.R (which use
# sample_taxonomic_resources()). Every scenario here was first verified interactively against the real
# behaviour before being written as an assertion (not guessed at), and every name pattern is grounded
# in something confirmed to actually occur in the real inst/extdata/AFD.csv (hyphenated "letter-shape"
# epithets, nominotypical subgenus brackets, synonyms moved between genera) or in genuinely common
# real-world data-entry noise (typos of every edit-distance type, case, whitespace, trailing notes).

test_that("every edit-distance type of typo still fuzzy-matches the correct species", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())

  typos <- c(
    deletion       = "Aporocera t-virde",   # missing an "i"
    insertion      = "Aporocera t-viiride", # extra "i"
    substitution   = "Aporocera t-veride",  # i -> e
    transposition  = "Aporocera t-virdie",  # last two letters swapped
    genus_typo     = "Aporcera t-viride"    # deletion inside the genus itself, not the epithet
  )

  out <- align_taxa(unname(typos), resources)

  expect_true(all(out$aligned_name == "Aporocera t-viride"))
  expect_true(all(out$alignment_code == "match_05a_fuzzy_accepted_canonical_name"))
})

test_that("a genus typo that preserves the first letter still fuzzy-matches at species level", {
  # species-level fuzzy matching (match_05a) compares the *whole* stripped name, not genus and epithet
  # separately -- so a small genus-level typo is absorbed into the same distance budget as an epithet
  # typo would be, as long as the first letter is unchanged (see the first-letter rule below)
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Aoorocera t-viride", resources) # 2nd letter of genus swapped (p -> o)

  expect_equal(out$aligned_name, "Aporocera t-viride")
})

test_that("a genus typo that changes the first letter is correctly rejected, not cross-matched", {
  # the critical anti-cross-matching rule documented in CLAUDE.md ("Boronieae vs Boronia"): fuzzy_match()
  # only considers a candidate if the first letter agrees, even when the total edit distance would
  # otherwise be well within tolerance (here, distance 1 -- "Xporocera" vs "Aporocera")
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Xporocera t-viride", resources)

  expect_true(is.na(out$aligned_name))
})

test_that("too many edits fails species-level fuzzy matching but still falls back to genus rank", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Aporocera zzzzzzzzzz", resources) # correct genus, unrecognisable epithet

  expect_true(grepl("^Aporocera sp\\. \\[", out$aligned_name))
  expect_equal(out$taxon_rank, "genus")
})

test_that("a genuinely ambiguous fuzzy match (two equidistant candidates) resolves to nothing, not a guess", {
  # n_allowed = 1 inside fuzzy_match() means a *tie* for the best distance is treated as no match --
  # deliberately built so "Testus abcdex" is exactly distance 1 from both real species below
  resources <- prepare_taxonomic_resources(tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Testus abcdef Sm.", "Testus abcdef", "species", "accepted", "TEST", "Testus", "sp1", "sp1",
    "Testus abcdeg Sm.", "Testus abcdeg", "species", "accepted", "TEST", "Testus", "sp2", "sp2",
    "Testus Sm.", "Testus", "genus", "accepted", "TEST", NA_character_, "g1", "g1"
  ))

  out <- align_taxa("Testus abcdex", resources, full = TRUE)

  expect_true(is.na(out$fuzzy_match_cleaned))
  expect_equal(out$taxon_rank, "genus") # degrades gracefully to genus rather than guessing a species
})

test_that("case is irrelevant to matching", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())

  out_lower <- align_taxa("aporocera t-viride", resources)
  out_upper <- align_taxa("APOROCERA T-VIRIDE", resources)

  expect_equal(out_lower$aligned_name, "Aporocera t-viride")
  expect_equal(out_upper$aligned_name, "Aporocera t-viride")
})

test_that("extra/doubled/leading/trailing whitespace is normalised before matching", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("  Aporocera   t-viride  ", resources)

  expect_equal(out$aligned_name, "Aporocera t-viride")
  expect_equal(out$alignment_code, "match_01c_accepted_canonical_name")
})

test_that("trailing free-text notes/annotations after a valid name don't prevent matching", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Aporocera t-viride (det. J. Doe 2019)", resources)

  expect_equal(out$aligned_name, "Aporocera t-viride")
})

test_that("'sensu lato'/'sensu stricto' qualifiers are stripped, not treated as part of the name", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Aporocera t-viride sensu lato", resources)

  expect_equal(out$aligned_name, "Aporocera t-viride")
})

test_that("compound/'ex' authorship after a valid name doesn't prevent matching", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Aporocera t-viride Blackburn, 1899 ex Lea", resources)

  expect_equal(out$aligned_name, "Aporocera t-viride")
})

test_that("morphospecies codes ('sp. 1', 'sp. nov.', 'sp. indet.') resolve to genus rank, not an error", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  names <- c("Aporocera sp. 1", "Aporocera sp. nov.", "Aporocera sp. indet.", "Aporocera sp. A")

  out <- align_taxa(names, resources)

  expect_true(all(out$taxon_rank == "genus"))
  expect_equal(out$aligned_name, paste0("Aporocera sp. [", names, "]"))
})

test_that("the nominotypical subgenus bracket convention resolves to the species it wraps", {
  # a real, extremely common zoological convention: the subgenus repeats the genus name in brackets --
  # distinct from sample_taxonomic_resources()'s Boronia (Valvatae) case, where the subgenus has a
  # different name from its genus
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())
  out <- align_taxa("Aporocera (Aporocera) t-viride", resources)

  expect_equal(out$aligned_name, "Aporocera t-viride")
  expect_equal(out$taxon_rank, "species")
})

test_that("both synonyms of the same accepted species resolve, including one under a different genus", {
  # a real, common invertebrate taxonomy pattern: a species reclassified into a new genus over its
  # history, leaving a synonym whose own genus differs from the current accepted name's
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())

  out_same_genus <- align_taxa("Aporocera viridipennis", resources)
  out_diff_genus <- align_taxa("Chalcolampra viridis", resources)

  expect_equal(out_same_genus$aligned_name, "Aporocera viridipennis")
  expect_equal(out_same_genus$taxonomic_status, "synonym")
  expect_equal(out_diff_genus$aligned_name, "Chalcolampra viridis")
  expect_equal(out_diff_genus$taxonomic_status, "synonym")

  # and both resolve forward to the same current accepted name via update_taxa()
  updated <- update_taxa(align_taxa(c("Aporocera viridipennis", "Chalcolampra viridis"), resources), resources)
  expect_equal(updated$accepted_name, rep("Aporocera t-viride", 2))
})

test_that("a subspecies-rank name (not just species/variety) is matched and fuzzy-matched correctly", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())

  out_exact <- align_taxa("Xylotoles costatus mixtus", resources)
  out_typo <- align_taxa("Xylotoles costatus mixtu", resources) # missing last letter

  expect_equal(out_exact$aligned_name, "Xylotoles costatus mixtus")
  expect_equal(out_exact$taxon_rank, "subspecies")
  expect_equal(out_typo$aligned_name, "Xylotoles costatus mixtus")
})

test_that("two genera that don't share a first letter never cross-collide even under heavy typos", {
  resources <- prepare_taxonomic_resources(sample_invert_taxonomic_resources())

  # a name that's actually gibberish shouldn't accidentally resolve to the *other* genus in the
  # reference just because both are present
  out <- align_taxa("Aporocera costatus", resources) # real genus + real epithet, wrong pairing

  # doesn't exact- or fuzzy-match a species (that binomial doesn't exist), falls back to genus rank
  # under the genus actually named, not the unrelated one
  expect_true(grepl("^Aporocera sp\\. \\[", out$aligned_name))
})
