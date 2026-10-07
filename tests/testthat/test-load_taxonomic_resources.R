# Covers load_taxonomic_resources(taxonomic_dataset = "AFD") end to end against a small AFD-shaped
# fixture (helper-afd-fixtures.R), entirely offline -- no need for the real ~89MB inst/extdata/AFD.csv.
# The "APC" path is inherently network-dependent (APCalign::load_taxonomic_resources() downloads/
# caches a live snapshot), so its test lives in test-apc_equivalence.R instead, gated the same way.

test_that("load_taxonomic_resources errors clearly on an unknown dataset", {
  expect_error(
    load_taxonomic_resources("NOT_A_REAL_DATASET"),
    "Unknown .taxonomic_dataset.: NOT_A_REAL_DATASET"
  )
})

test_that("load_taxonomic_resources(\"AFD\") returns a named list with a flat AFD tibble inside", {
  path <- write_sample_afd_csv()
  out <- load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE)

  expect_named(out, "AFD")
  expect_true(all(c(
    "canonical_name", "scientific_name", "taxon_rank", "taxonomic_status", "taxonomic_dataset",
    "genus", "taxon_ID", "accepted_name_usage_ID"
  ) %in% names(out$AFD)))
  expect_true(all(out$AFD$taxonomic_dataset == "AFD"))
})

test_that("load_taxonomic_resources(\"AFD\") derives taxon_rank from SUB_SPECIES correctly", {
  path <- write_sample_afd_csv()
  afd <- load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE)$AFD

  accepted_species <- afd |> dplyr::filter(taxonomic_status == "accepted", canonical_name == "Testus alphus")
  accepted_subspecies <- afd |> dplyr::filter(taxonomic_status == "accepted", canonical_name == "Testus alphus betus")

  expect_equal(accepted_species$taxon_rank, "species")
  expect_equal(accepted_species$taxon_ID, "guid-1")
  expect_equal(accepted_species$accepted_name_usage_ID, "guid-1")

  expect_equal(accepted_subspecies$taxon_rank, "subspecies")
  expect_equal(accepted_subspecies$genus, "Testus")
})

test_that("load_taxonomic_resources(\"AFD\") builds distinct higher-rank rows, case-normalised", {
  path <- write_sample_afd_csv()
  afd <- load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE)$AFD

  # FAMILY/ORDER are ALL CAPS in the raw fixture (matching real AFD's own export convention for
  # family-and-above ranks) -- confirms they're normalised to sentence case, not left as-is
  family_rows <- afd |> dplyr::filter(taxon_rank == "family")
  expect_setequal(family_rows$canonical_name, c("Testidae", "Anotherfam", "Thirdfam"))

  order_rows <- afd |> dplyr::filter(taxon_rank == "order")
  expect_setequal(order_rows$canonical_name, c("Testoptera", "Anotherorder", "Thirdorder"))

  # SUBFAMILY is already properly cased in the raw fixture -- confirms normalisation is a no-op there
  subfamily_rows <- afd |> dplyr::filter(taxon_rank == "subfamily")
  expect_setequal(subfamily_rows$canonical_name, c("Testinae", "Anothersubfam", "Thirdsubfam"))

  # two rows share GENUS/FAMILY/ORDER/CLASS/PHYLUM -- confirms distinct() dedup, not one row per input row
  expect_equal(nrow(afd |> dplyr::filter(taxon_rank == "genus", canonical_name == "Testus")), 1)
  expect_equal(nrow(family_rows |> dplyr::filter(canonical_name == "Testidae")), 1)
})

test_that("load_taxonomic_resources(\"AFD\") builds subgenus rows paired with their owning genus", {
  path <- write_sample_afd_csv()
  afd <- load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE)$AFD

  # filter to this fixture's non-nominotypical subgenus specifically -- "Thirdgenus" also has a
  # (nominotypical) subgenus row, covered by its own dedicated test below
  subgenus_row <- afd |> dplyr::filter(taxon_rank == "subgenus", canonical_name == "Subgenusy")
  expect_equal(subgenus_row$canonical_name, "Subgenusy")
  expect_equal(subgenus_row$genus, "Anothergenus")

  # prepare_taxonomic_resources() should be able to build the bracketed convention from this
  resources <- prepare_taxonomic_resources(afd)
  expect_true("Anothergenus (Subgenusy)" %in% resources$subgenus_v2$genus_and_subgenus)
})

test_that("load_taxonomic_resources(\"AFD\") namespaces taxon_ID by rank so a nominotypical subgenus doesn't collide with its genus", {
  # "Thirdgenus" the genus and "Thirdgenus" the (nominotypical) subgenus share a canonical_name -- a
  # real, common taxonomic convention (every genus split into subgenera has one sharing the genus's own
  # name), not an edge case. Before taxon_ID was namespaced by rank, both rows fell back to the same
  # bare-name taxon_ID ("Thirdgenus"), so update_taxa()'s taxon_ID-keyed match() (first-hit semantics)
  # would silently resolve a subgenus-rank match to the colliding genus-rank row instead, discarding the
  # subgenus and downgrading taxon_rank from "subgenus" to "genus".
  path <- write_sample_afd_csv()
  afd <- load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE)$AFD

  genus_row <- afd |> dplyr::filter(taxon_rank == "genus", canonical_name == "Thirdgenus")
  subgenus_row <- afd |> dplyr::filter(taxon_rank == "subgenus", canonical_name == "Thirdgenus")

  expect_equal(nrow(genus_row), 1)
  expect_equal(nrow(subgenus_row), 1)
  expect_false(genus_row$taxon_ID == subgenus_row$taxon_ID)

  # end to end: a name using the bracketed Genus (Subgenus) convention, for a species AFD doesn't itself
  # list (forcing the subgenus fallback block, not an exact species match), should resolve at subgenus
  # rank all the way through update_taxa() -- not silently collapse to genus rank.
  resources <- prepare_taxonomic_resources(afd)
  out <- create_taxonomic_update_lookup("Thirdgenus (Thirdgenus) unlistedus", resources)
  expect_equal(out$taxon_rank, "subgenus")
})

test_that("load_taxonomic_resources(\"AFD\") splits SYNONYMS and strips authorship", {
  path <- write_sample_afd_csv()
  afd <- load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE)$AFD

  synonyms <- afd |> dplyr::filter(taxonomic_status == "synonym") |> dplyr::arrange(canonical_name)

  expect_equal(nrow(synonyms), 2)
  expect_setequal(synonyms$canonical_name, c("Oldgenus alphus", "Weirdgenus alphus"))
  expect_true(all(synonyms$accepted_name_usage_ID == "guid-1"))
  # genus is re-derived from each synonym's own name (different from the accepted row's genus, "Testus")
  expect_setequal(synonyms$genus, c("Oldgenus", "Weirdgenus"))
  # taxon_ID is synthesised, unique per synonym row
  expect_equal(length(unique(synonyms$taxon_ID)), 2)
})

test_that("load_taxonomic_resources(\"AFD\") caches the reshaped result, keyed by source file mtime/size", {
  path <- write_sample_afd_csv()
  cache_dir <- withr::local_tempdir()

  expect_message(
    load_taxonomic_resources("AFD", path = path, cache_dir = cache_dir),
    "Reading and reshaping"
  )
  expect_message(
    load_taxonomic_resources("AFD", path = path, cache_dir = cache_dir),
    "Using cached"
  )
  expect_message(
    load_taxonomic_resources("AFD", path = path, cache_dir = cache_dir, refresh_cache = TRUE),
    "Reading and reshaping"
  )
})

test_that("load_taxonomic_resources(\"AFD\") gives a clear error when the file is missing", {
  expect_error(
    load_taxonomic_resources("AFD", path = "/no/such/file.csv"),
    "Couldn't find the AFD reference file"
  )
})

test_that("prepare_taxonomic_resources(load_taxonomic_resources(\"AFD\")) runs end to end into align_taxa()", {
  path <- write_sample_afd_csv()
  resources <- prepare_taxonomic_resources(load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir())$AFD)

  out <- create_taxonomic_update_lookup(
    c("Testus alphus", "Oldgenus alphus", "Testus alphus betus"), resources
  )

  expect_equal(out$accepted_name, c("Testus alphus", "Testus alphus", "Testus alphus betus"))
  expect_equal(out$taxonomic_status_aligned, c("accepted", "synonym", "accepted"))
})

test_that("load_taxonomic_resources(\"AFD\") reads the 2026 export shape (VALID_NAME, parenthesised authorship, split citations)", {
  # the 2026 AFD CSV export renamed FULL_NAME to VALID_NAME, writes changed-combination authorship in
  # parentheses, and occasionally separates a subsequent usage from its citation with "; "
  raw <- sample_afd_raw() |> dplyr::rename(VALID_NAME = FULL_NAME)
  raw$SYNONYMS[1] <- paste(
    "Oldgenus alphus (Smith, 1900)", "Testus alfus", "Smith, 1902", "Testus alphus Smith, 1900",
    sep = "; "
  )
  path <- tempfile(fileext = ".csv")
  readr::write_csv(raw, path)

  afd <- load_taxonomic_resources(
    "AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE
  )$AFD
  syn <- afd |> dplyr::filter(taxonomic_status == "synonym")

  expect_true("Testus alphus" %in% afd$canonical_name[afd$taxonomic_status == "accepted"])
  expect_setequal(syn$canonical_name, c("Oldgenus alphus", "Testus alfus"))
  # the orphaned "Smith, 1902" citation is re-attached to the name before it, not a synonym of its own
  expect_true("Testus alfus Smith, 1902" %in% syn$scientific_name)
})

test_that("load_taxonomic_resources(\"AFD\") errors clearly when expected columns are missing", {
  path <- tempfile(fileext = ".csv")
  readr::write_csv(dplyr::select(sample_afd_raw(), -SYNONYMS), path)
  expect_error(
    load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE),
    "missing expected column\\(s\\): SYNONYMS"
  )
})

test_that("load_taxonomic_resources(\"AFD\") keeps an \"Unplaced Synonym(s)\" pseudo-row's names as unresolved, never as an accepted taxon", {
  raw <- sample_afd_raw() |> dplyr::rename(VALID_NAME = FULL_NAME)
  unplaced <- raw[1, ]
  unplaced$VALID_NAME <- "Unplaced Synonym(s)"
  unplaced$COMPLETE_NAME <- "Unplaced Synonym(s) ,"
  unplaced$SPECIES <- "Unplaced"
  unplaced$SYNONYMS <- "Testus lostus Smith, 1901; Testus gonus Jones & Smith, 1902"
  unplaced$CONCEPT_GUID <- "guid-unplaced"
  path <- tempfile(fileext = ".csv")
  readr::write_csv(dplyr::bind_rows(raw, unplaced), path)

  afd <- load_taxonomic_resources(
    "AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE
  )$AFD

  expect_false(any(grepl("Unplaced", afd$canonical_name)))
  lost <- afd |> dplyr::filter(canonical_name %in% c("Testus lostus", "Testus gonus"))
  expect_equal(nrow(lost), 2)
  expect_true(all(lost$taxonomic_status == "unplaced"))
  expect_equal(lost$accepted_name_usage_ID, lost$taxon_ID)
})

test_that("load_taxonomic_resources(\"AFD\") treats an unplaced genus/family as a placeholder, not a taxon", {
  raw <- sample_afd_raw() |> dplyr::rename(VALID_NAME = FULL_NAME)
  sp <- raw[1, ]
  sp$VALID_NAME <- "Unplaced vetula"
  sp$COMPLETE_NAME <- "Unplaced vetula (Meyrick, 1893)"
  sp$GENUS <- "Unplaced"
  sp$FAMILY <- "Unplaced to Family"
  sp$SPECIES <- "vetula"
  sp$SYNONYMS <- "Tinea vetula Meyrick, 1893"
  sp$CONCEPT_GUID <- "guid-unplaced-genus"
  path <- tempfile(fileext = ".csv")
  readr::write_csv(dplyr::bind_rows(raw, sp), path)

  afd <- load_taxonomic_resources(
    "AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE
  )$AFD

  expect_false(any(grepl("Unplaced", afd$canonical_name, ignore.case = TRUE)))
  tinea <- afd |> dplyr::filter(canonical_name == "Tinea vetula")
  expect_equal(tinea$taxonomic_status, "unplaced")
  expect_equal(tinea$accepted_name_usage_ID, tinea$taxon_ID)
})

test_that("load_taxonomic_resources(\"AFD\") reads CHANGED_COMBINATION_NAMES as generic combinations, and ranks synonyms by word count", {
  raw <- sample_afd_raw() |> dplyr::rename(VALID_NAME = FULL_NAME)
  raw$CHANGED_COMBINATION_NAMES <- NA_character_
  raw$CHANGED_COMBINATION_NAMES[1] <- "Newgenus alphus (Smith, 1900); Oldgenus alphus Smith, 1900"
  raw$SYNONYMS[2] <- "Testus alphus gammus Jones, 1940"
  path <- tempfile(fileext = ".csv")
  readr::write_csv(raw, path)

  afd <- load_taxonomic_resources("AFD", path = path, cache_dir = withr::local_tempdir(), quiet = TRUE)$AFD

  comb <- afd |> dplyr::filter(canonical_name == "Newgenus alphus")
  expect_equal(comb$taxonomic_status, "Generic combination")
  expect_equal(comb$accepted_name_usage_ID, "guid-1")
  # listed in both SYNONYMS and CHANGED_COMBINATION_NAMES -> kept once, as a synonym
  old <- afd |> dplyr::filter(canonical_name == "Oldgenus alphus")
  expect_equal(nrow(old), 1)
  expect_equal(old$taxonomic_status, "synonym")
  # a trinomial synonym is a subspecies, not a species
  expect_equal(afd$taxon_rank[afd$canonical_name == "Testus alphus gammus"], "subspecies")
})

test_that("AFD-format synonym annotations are cleaned, and misapplied/part markers become statuses", {
  entries <- c(
    "Acanthoglossa? setigera Smith, 1900", "Megascolides(?) pygmaeus Smith, 1900",
    "H[yla] jacksonii Smith, 1900", "Paraponyx <i></i> pudica Smith, 1900",
    "'Ochlerotatus' notoscriptus (Skuse, 1889)", "Allotria d'arci Smith, 1900",
    "Myllita deshayesi d'Orbigny, 1846", "Trichobilharzia parocellata (Johnston & Simpson), 1939",
    "Mangilia (Glyphostoma)) jousseaumei Smith, 1900",
    "Pyramidella (Chrysallida (section Styloptygma)) typica Smith, 1900"
  )
  expect_equal(
    strip_afd_authorship(entries, c("Smith", "Skuse")),
    c(
      "Acanthoglossa setigera", "Megascolides pygmaeus", "Hyla jacksonii", "Paraponyx pudica",
      "Ochlerotatus notoscriptus", "Allotria d'arci", "Myllita deshayesi",
      "Trichobilharzia parocellata", "Mangilia (Glyphostoma) jousseaumei",
      "Pyramidella (Chrysallida (section Styloptygma)) typica"
    )
  )

  marked <- c(
    "Dendrodoris fumata auctt. non Rüppell & Leuckart, 0", "Aulicus episcopalis sensu Smith",
    "Chelonia depressa (part.)", "Mopsea elegans [pars]", "Hammaticherus indutus auct., ",
    "Testus alphus Smith, 1900"
  )
  expect_equal(
    afd_usage_status(marked, "synonym"),
    c("misapplied", "misapplied", "pro parte synonym", "pro parte synonym", "misapplied", "synonym")
  )
  expect_equal(
    strip_afd_authorship(marked, "Smith"),
    c("Dendrodoris fumata", "Aulicus episcopalis", "Chelonia depressa", "Mopsea elegans",
      "Hammaticherus indutus", "Testus alphus")
  )
  # a marker or a connector-joined citation split off by "; " is re-attached to the name before it
  expect_equal(
    rejoin_afd_synonym_fragments(c("Paracharactis vestianella", "auctt., ", "Theretra cinerea", "Haines in Dowling & Haines, 1963")),
    c("Paracharactis vestianella auctt., ", "Theretra cinerea Haines in Dowling & Haines, 1963")
  )
})
