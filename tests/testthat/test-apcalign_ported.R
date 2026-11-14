# APCalign's own tests of match outputs and robustness (traitecoevo/APCalign tests/testthat:
# test-match_branches.R, test-functions-fuzzy_match.R, test-operation_executes.R,
# test-lookup_summary.R), ported 2026-11-14 at the user's request so "same as APCalign" is checked
# against APCalign's tests, not a subset. Where an expectation depends on APC data, both packages are
# run on the same live snapshot and compared; behavioural expectations (no errors, row order, NA
# handling) are ported as written. Not ported: APCalign's APC-specific tests (state diversity, APC
# table structure, its caching/connection), its string-helper tests (taxonAlign uses stringr), its
# full-output snapshot (the benchmark comparison in test-apc_equivalence.R covers it), and its
# taxonomic_splits = "return_all" assertions (not ported: user's decision). The approved differences
# are listed in test-apc_equivalence.R.

skip_without_apc <- function() {
  testthat::skip_if_not_installed("APCalign")
  testthat::skip_if_offline()
  testthat::skip_on_cran()
}

# ---- test-match_branches.R ---------------------------------------------------------------------------

test_that("APCalign's previously-untested match branches resolve the same way", {
  skip_without_apc()
  loaded <- load_apc_resources_for_test()
  dark <- c(
    intergrade_unknown_genus = "Xqzztia aaa -- bbb",
    indecision_unknown_genus = "Xqzztia aaa / bbb",
    affinis_unknown_genus = "Xqzztia aff. bbb",
    hybrid_unknown = "Xqzztia x bbb",
    genus_fuzzy_synonym = "Enceephalartos xqzztii",
    family_fuzzy_accepted = "Zamiaceaa",
    family_fuzzy_synonym = "Boweniaceaa"
  )
  t <- align_taxa(unname(dark), loaded$resources, imprecise_fuzzy_matches = TRUE,
                  identifier = "test_all_matches_TRUE", full = TRUE)
  a <- suppressMessages(APCalign::align_taxa(unname(dark), resources = loaded$APC, full = TRUE,
                                             imprecise_fuzzy_matches = TRUE, APNI_matches = TRUE,
                                             identifier = "test_all_matches_TRUE", quiet = TRUE))
  expect_equal(t$aligned_name, a$aligned_name)
  expect_equal(t$taxon_rank, a$taxon_rank)
  # the four "unknown genus" fall-throughs can't be aligned; the three fuzzy genus/family ones can
  expect_true(all(is.na(t$aligned_name[1:4])))
  expect_false(any(is.na(t$aligned_name[5:7])))
})

test_that("`affinis` as a species epithet is not read as an affinity qualifier", {
  skip_without_apc()
  loaded <- load_apc_resources_for_test()
  accepted <- unique(loaded$APC$APC_accepted$canonical_name)
  epithet_affinis <- sort(accepted[grepl("\\baffinis\\b", accepted, perl = TRUE)])
  expect_gt(length(epithet_affinis), 0)

  # every accepted name containing `affinis` aligns to itself, at its own rank
  out <- align_taxa(epithet_affinis, loaded$resources)
  expect_equal(out$aligned_name, epithet_affinis)
  expect_false(any(out$taxon_rank == "genus"))

  # genuine affinity usage resolves to genus rank, as in APCalign
  affinity <- c("Acacia affinis dealbata", "Banksia affinis serrata", "Banksia aff. serrata")
  t <- align_taxa(affinity, loaded$resources)
  a <- suppressMessages(APCalign::align_taxa(affinity, resources = loaded$APC, quiet = TRUE))
  expect_equal(t$taxon_rank, rep("genus", 3))
  expect_equal(t$aligned_name, a$aligned_name)
})

test_that("aligned_reason records the data version, never the run date (APCalign #281)", {
  ref <- sample_taxonomic_resources()
  attr(ref, "data_release") <- "2026-11-14"
  out <- align_taxa(c("Boronia serrulata", "Boronia serulata", "Boronia sp."), ref)
  expect_true(all(endsWith(out$aligned_reason, " (taxonAlign data release 2026-11-14)")))
  expect_false(any(grepl(as.character(Sys.Date()), out$aligned_reason, fixed = TRUE)))

  # a reference with no version gets no stamp rather than a guessed one
  out2 <- align_taxa("Boronia serrulata", sample_taxonomic_resources())
  expect_equal(out2$aligned_reason, sub(" (taxonAlign data release 2026-11-14)", "", out$aligned_reason[1], fixed = TRUE))
  expect_false(grepl("\\(", out2$aligned_reason))
})

# ---- test-functions-fuzzy_match.R --------------------------------------------------------------------

test_that("fuzzy_match() rejects an affinis/hybrid qualifier masquerading as an ordinary word", {
  skip_without_apc()
  res <- load_apc_resources_for_test()$resources
  accepted <- res$species$accepted$stripped_canonical
  synonyms <- res$species$synonym$stripped_canonical
  # "aff" must not slot into the epithet's place ("acacia aptaneura"), nor "x" into "banksia integrifolia"
  expect_true(is.na(fuzzy_match("acacia aff aneura", accepted, 3, 0.2, n_allowed = 1)))
  expect_true(is.na(fuzzy_match("banksia x integrifolia", accepted, 3, 0.2, n_allowed = 1)))
  # ...but a candidate carrying the same token still matches
  expect_equal(fuzzy_match("isoetes sp aff muellerii", synonyms, 3, 0.2, n_allowed = 1), "isoetes sp aff muelleri")
  expect_equal(fuzzy_match("persoonia x luciida", accepted, 3, 0.2, n_allowed = 1), "persoonia x lucida")
})

test_that("an affinis-qualified name is capped at genus rank instead of a wrong species match", {
  skip_without_apc()
  out <- align_taxa("Acacia aff. aneura", load_apc_resources_for_test()$resources, full = TRUE)
  expect_equal(out$aligned_name, "Acacia sp. [Acacia aff. aneura]")
  expect_equal(out$taxon_rank, "genus")
})

test_that("a name with no letter, or a word with none after the genus, doesn't stop the lookup", {
  skip_without_apc()
  res <- load_apc_resources_for_test()$resources
  expect_true(is.na(fuzzy_match("12 34", res$genus$canonical_name, 2, 0.35)))
  expect_true(is.na(fuzzy_match("acacia --", "acacia ab", 5, 1)))
  expect_true(is.na(fuzzy_match("acacia b", "acacia", 2, 0.35)))
  odd <- c("12 34", "1 1/2", "½", "± Acacia", "Acacia + aneura", "Eucalyptus |", "Eucalyptus ~", "Acacia ⊗ aneura")
  out <- expect_no_error(create_taxonomic_update_lookup(c(odd, "Acacia aneura"), res, quiet = TRUE))
  expect_equal(out$original_name, c(odd, "Acacia aneura"))
  expect_equal(out$aligned_name[length(odd) + 1], "Acacia aneura")
})

# ---- test-operation_executes.R -----------------------------------------------------------------------

test_that("align_taxa() executes with and without fuzzy matching", {
  skip_without_apc()
  res <- load_apc_resources_for_test()$resources
  original_name <- c("Dryandra preissii", "Banksia acuminata", "Bannksia accuminata")
  expect_equal(align_taxa(original_name, res, fuzzy_matches = TRUE)$aligned_name,
               c("Dryandra preissii", "Banksia acuminata", "Banksia acuminata"))
  expect_equal(align_taxa(original_name, res, fuzzy_matches = FALSE)$aligned_name,
               c("Dryandra preissii", "Banksia acuminata", NA))
})

test_that("a longer list aligns the same way as APCalign, in input order", {
  skip_without_apc()
  loaded <- load_apc_resources_for_test()
  species <- utils::read.csv(system.file("extdata", "species.csv", package = "APCalign"))$name[1:50]
  t <- align_taxa(species, loaded$resources)
  a <- suppressMessages(APCalign::align_taxa(species, resources = loaded$APC, quiet = TRUE))
  expect_equal(t$original_name, species)
  apc <- !a$taxonomic_dataset %in% "APNI"
  expect_equal(t$aligned_name[apc], a$aligned_name[apc])
})

test_that("update_taxa() and the lookup give the same, suitable structure", {
  skip_without_apc()
  res <- load_apc_resources_for_test()$resources
  aligned <- align_taxa(c("Dryandra preissii", "Banksia acuminata"), res)
  out1 <- update_taxa(aligned, res)
  out2 <- create_taxonomic_update_lookup(aligned$original_name, res, quiet = TRUE)
  expect_equal(out1[, c("original_name", "aligned_name")], aligned[, c("original_name", "aligned_name")])
  v <- setdiff(intersect(names(out1), names(out2)), "row_number")
  expect_equal(out1[, v], out2[, v])
  expect_equal(out1$suggested_name, rep("Banksia acuminata", 2))
  expect_equal(out2$accepted_name, rep("Banksia acuminata", 2))
})

test_that("unusual hybrid symbols, NAs and weird strings run, keeping every input row", {
  skip_without_apc()
  res <- load_apc_resources_for_test()$resources

  hybrid <- c("Platanus × acerifolia", "Platanus × hispanica")
  out <- align_taxa(hybrid, res)
  expect_equal(out$aligned_name, APCalign::standardise_names(hybrid))

  out_na <- create_taxonomic_update_lookup(c("Acacia aneura", NA), res, quiet = TRUE)
  expect_equal(out_na$original_name, c("Acacia aneura", NA))
  expect_equal(out_na$aligned_name, c("Acacia aneura", NA))
  expect_equal(out_na$accepted_name, c("Acacia aneura", NA))

  weird <- c("", "''", "'", "          ", "\t", "\n", "stuff with      ", "test'string'withquotes",
             "!@#$%^&*()_+", rep("abc", 10), "print('whoops no cleaning')", "Doesthislook likeaspeciesi",
             "Doesn'tlook likeaspeciesi", "Banksia  serrata")
  out1 <- align_taxa(weird, res)
  out2 <- create_taxonomic_update_lookup(weird, res, quiet = TRUE)
  expect_equal(out1$original_name, weird)
  expect_equal(out2$original_name, weird)
  expect_equal(out2$aligned_name, c(rep(NA_character_, length(weird) - 1), "Banksia serrata"))
})

test_that("genus-only names and names with nothing to match behave as in APCalign", {
  skip_without_apc()
  loaded <- load_apc_resources_for_test()
  for (names in list(c("Acacia sp.", "Eucalyptus sp."), c("Eucalyptus", "Banksia asdasd", "Ryandra sp"),
                     c("Aucalyptus", "Danksia asdasd", "Ryandra sp"))) {
    t <- create_taxonomic_update_lookup(names, loaded$resources, quiet = TRUE)
    a <- suppressMessages(APCalign::create_taxonomic_update_lookup(names, resources = loaded$APC, quiet = TRUE))
    expect_equal(t$original_name, names)
    expect_equal(t$aligned_name, a$aligned_name)
    expect_equal(t$suggested_name, a$suggested_name)
    expect_equal(t$taxon_rank, a$taxon_rank)
  }
})

test_that("every input row is returned, in order, even with duplicates", {
  skip_without_apc()
  res <- load_apc_resources_for_test()$resources
  original_name <- c("Dryandra preissii", "Banksia acuminata", "Doesthislook likeaspeciesi",
                     "Doesthislook likeaspeciesi", "Banksia acuminata", "Banksia acuminata", "Hibbertia sericea")
  out1 <- align_taxa(original_name, res)
  out2 <- update_taxa(out1, res)
  out3 <- create_taxonomic_update_lookup(original_name, res, quiet = TRUE)
  out4 <- align_taxa(original_name, res, full = TRUE)
  for (o in list(out1, out2, out3, out4)) expect_equal(o$original_name, original_name)
  expect_equal(out2$aligned_name, out1$aligned_name)
  expect_equal(out3$aligned_name, out1$aligned_name)
  expect_equal(out4$aligned_name, out1$aligned_name)
})

# ---- test-lookup_summary.R ---------------------------------------------------------------------------

summary_names <- c(
  "Banksia serrata",                # species, accepted
  "Banksia serrata",                # repeat: counted once
  "Acalypha indica var. australis", # variety, synonym of Acalypha lanceolata
  "Dryandra sp.",                   # genus only, Dryandra -> Banksia
  "Asteraceae sp.",                 # family only
  "Acaena x ovina",                 # accepted; APCalign also lists alternatives (an approved difference)
  "Abcde fgh x ijk",                # cannot be aligned
  NA
)

test_that("the closing summary counts each distinct name once", {
  skip_without_apc()
  res <- load_apc_resources_for_test()$resources
  aligned <- align_taxa(summary_names, res)
  for (splits in c("most_likely_species", "collapse_to_higher_taxon")) {
    lines <- summarise_update_lookup(aligned, update_taxa(aligned, res, taxonomic_splits = splits), splits)
    expect_equal(lines[1], "Summary of 6 names:", info = splits)
    expect_match(lines[2], "-> 3 aligned to a species or infraspecific taxon \\(3 in APC\\)", info = splits)
    expect_match(lines[3], "-> 1 aligned only to a genus and 1 only to a family", info = splits)
    expect_match(lines[4], "-> 1 could not be aligned", info = splits)
    expect_match(lines[5], "-> 2 aligned names were updated", info = splits)
    # APCalign also reports Acaena x ovina as a split; taxonAlign doesn't (approved difference)
    expect_length(lines, 5)
  }
})

test_that("create_taxonomic_update_lookup() prints the summary unless quiet", {
  res <- prepare_taxonomic_resources(sample_taxonomic_resources())
  expect_message(create_taxonomic_update_lookup("Boronia serrulata", res), "Summary of 1 names")
  expect_no_message(create_taxonomic_update_lookup("Boronia serrulata", res, quiet = TRUE))
  # a split is reported with how it was handled
  lines <- summarise_update_lookup(
    align_taxa("Boronia serrulata", res), update_taxa(align_taxa("Boronia serrulata", res), res), "most_likely_species"
  )
  expect_false(any(grepl("more than one", lines)))
})
