test_that("prepare_taxonomic_resources errors clearly when required columns are missing", {
  expect_error(
    prepare_taxonomic_resources(dplyr::tibble(canonical_name = "Boronia serrulata")),
    "missing required column"
  )
})

test_that("prepare_taxonomic_resources gives a clear, actionable error when taxonomic_resources is missing", {
  expect_error(prepare_taxonomic_resources(), "generate_GBIF_taxonomic_reference_list")
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
  no_species <- sample_taxonomic_resources() |> dplyr::filter(taxon_rank != "species", taxon_rank != "variety")
  expect_error(prepare_taxonomic_resources(no_species), "no rows at species/infraspecific rank")
})

test_that("prepare_taxonomic_resources splits by rank and status, deriving all ranks present", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  expect_setequal(names(resources), c("species", "genus", "family", "order", "tribe", "subgenus", "subgenus_v2"))
  expect_setequal(names(resources$species), c("accepted", "synonym"))
  expect_equal(nrow(resources$species$accepted), 2) # species + variety
  expect_equal(nrow(resources$species$synonym), 2) # "oldname" + "missingaccepted"
  # genus/order each have an accepted row and a synonym row, unlike species -- prepare_taxonomic_resources()
  # only splits `species` further by taxonomic_status, so these stay as one combined table per rank
  # "Zieria" is synthesised: the "Boronia oldname" synonym row's `genus` column names it, but the
  # fixture never gives it an explicit genus-rank row of its own -- prepare_taxonomic_resources() now
  # adds one automatically for any such implied-but-missing higher rank (see the synthesised_rows step)
  expect_setequal(resources$genus$canonical_name, c("Boronia", "Boronella", "Zieria"))
  expect_setequal(resources$order$canonical_name, c("Sapindales", "Oldorderia"))
  expect_equal(resources$family$canonical_name, "Rutaceae")
  expect_equal(resources$tribe$canonical_name, "Zanthoxyleae")
})

test_that("prepare_taxonomic_resources synthesises missing higher-rank rows from implied hierarchy columns", {
  # a species row can name its family via an extra `family` column without ever getting an explicit
  # family-rank row of its own -- a real, easy gap to leave (found via this package's own get-started.qmd
  # vignette example, where a genus named only via the `genus` column silently failed to align at all)
  raw <- dplyr::tibble(
    canonical_name = c("Testus alphus", "Testus betus"),
    scientific_name = c("Testus alphus Sm.", "Testus betus Sm."),
    taxon_rank = "species", taxonomic_status = "accepted", taxonomic_dataset = "MY_DATA",
    genus = "Testus", family = "Testaceae",
    taxon_ID = c("sp1", "sp2"), accepted_name_usage_ID = c("sp1", "sp2")
  )

  resources <- prepare_taxonomic_resources(raw)

  expect_equal(resources$genus$canonical_name, "Testus")
  expect_equal(resources$family$canonical_name, "Testaceae")
  # placeholder ID format: "<taxonomic_dataset>_<taxon_rank>_<canonical_name>" -- unique across both
  # rank (a nominotypical genus/subgenus sharing a name) and dataset (two sources both having, say, a
  # "Testaceae" family row)
  expect_equal(resources$genus$taxon_ID, "MY_DATA_genus_Testus")
  expect_equal(resources$genus$accepted_name_usage_ID, "MY_DATA_genus_Testus")
  expect_equal(resources$family$taxon_ID, "MY_DATA_family_Testaceae")
  expect_equal(resources$genus$taxonomic_status, "accepted")
  expect_equal(resources$genus$taxonomic_dataset, "MY_DATA")
})

test_that("prepare_taxonomic_resources doesn't duplicate a higher rank that already has an explicit row", {
  raw <- dplyr::bind_rows(
    dplyr::tibble(
      canonical_name = "Testaceae", scientific_name = "Testaceae Sm.", taxon_rank = "family",
      taxonomic_status = "accepted", taxonomic_dataset = "MY_DATA", genus = NA_character_,
      family = NA_character_, taxon_ID = "fam1", accepted_name_usage_ID = "fam1"
    ),
    dplyr::tibble(
      canonical_name = "Testus alphus", scientific_name = "Testus alphus Sm.", taxon_rank = "species",
      taxonomic_status = "accepted", taxonomic_dataset = "MY_DATA", genus = "Testus",
      family = "Testaceae", taxon_ID = "sp1", accepted_name_usage_ID = "sp1"
    )
  )

  resources <- prepare_taxonomic_resources(raw)

  # the explicit "fam1" row survives untouched -- no second, synthesised "Testaceae" row is added
  expect_equal(nrow(resources$family), 1)
  expect_equal(resources$family$taxon_ID, "fam1")
})

test_that("prepare_taxonomic_resources ignores a non-character extra column when synthesising rows", {
  # an extra column that isn't a hierarchy column at all (e.g. a collection year) shouldn't be treated
  # as one -- it can't hold a taxon name, and previously crashed outright (`values != ""` on a POSIXct/
  # numeric column errors rather than returning FALSE)
  raw <- dplyr::tibble(
    canonical_name = "Testus alphus", scientific_name = "Testus alphus Sm.", taxon_rank = "species",
    taxonomic_status = "accepted", taxonomic_dataset = "MY_DATA", genus = "Testus",
    collection_year = 1999L, taxon_ID = "sp1", accepted_name_usage_ID = "sp1"
  )

  resources <- prepare_taxonomic_resources(raw)

  expect_false("collection_year" %in% names(resources))
  expect_equal(resources$genus$canonical_name, "Testus")
})

test_that("prepare_taxonomic_resources orders resources most-specific-rank-first, not alphabetically", {
  # regression test: split() on the raw rank string alone orders alphabetically (family, genus, order,
  # subgenus, tribe here) -- arbitrary, and the wrong tie-break whenever a name could match more than
  # one rank (see taxonAlign_taxon_rank_specificity's own comment, and the AFD taxon_ID-collision bug
  # this generalises the fix for). Expected order here: species first (most specific of all), then
  # genus before subgenus specifically (the one deliberate exception -- a bare name shared by a genus
  # and its own nominotypical subgenus defaults to the broader genus grouping), subgenus_v2 (kept
  # immediately alongside its own "subgenus"), then tribe, family, order most-specific-first as usual.
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  expect_equal(
    names(resources),
    c("species", "genus", "subgenus", "subgenus_v2", "tribe", "family", "order")
  )
})

test_that("prepare_taxonomic_resources keeps an unrecognised rank's own bucket, appended after every known rank", {
  # a rank name absent from taxonAlign_taxon_rank_specificity entirely (not a typo of a known one) must
  # not be dropped -- it should get its own bucket, just placed last (least-specific/lowest tie-break
  # priority is the safe default when specificity is genuinely unknown)
  with_weird_rank <- sample_taxonomic_resources() |>
    dplyr::bind_rows(dplyr::tibble(
      canonical_name = "Madeupia", scientific_name = "Madeupia", taxon_rank = "totallymaderank",
      taxonomic_status = "accepted", taxonomic_dataset = "TEST", genus = NA_character_,
      taxon_ID = "weird1", accepted_name_usage_ID = "weird1"
    ))

  resources <- prepare_taxonomic_resources(with_weird_rank)

  expect_true("totallymaderank" %in% names(resources))
  expect_equal(resources$totallymaderank$canonical_name, "Madeupia")
  # every recognised rank still sorts before the unrecognised one (subgenus_v2 aside -- it's always
  # kept immediately after its own "subgenus", never reordered relative to it)
  expect_equal(tail(setdiff(names(resources), "subgenus_v2"), 1), "totallymaderank")
})

test_that("prepare_taxonomic_resources builds both subgenus conventions", {
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources())

  expect_equal(resources$subgenus$canonical_name, "Valvatae")
  expect_equal(resources$subgenus_v2$genus_and_subgenus, "Boronia (Valvatae)")
})

test_that("a row with a missing (NA) canonical_name is dropped, with a warning", {
  # regression test: leaving such a row in is an active hazard, not just untidy data -- `NA %in% x` is
  # TRUE whenever `x` contains an NA, so a legitimately-failed fuzzy_match() (which returns NA) would
  # otherwise spuriously "match" this row instead of correctly matching nothing at all.
  broken <- sample_taxonomic_resources()
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
  resources <- prepare_taxonomic_resources(sample_taxonomic_resources(), taxon_ranks_to_check = c("genus", "family"))

  expect_setequal(names(resources), c("species", "genus", "family"))
  expect_null(resources$tribe)
  expect_null(resources$subgenus)
  expect_null(resources$subgenus_v2)
})

test_that("taxon_ranks_to_check warns about ranks not present in the data", {
  expect_warning(
    prepare_taxonomic_resources(sample_taxonomic_resources(), taxon_ranks_to_check = c("genus", "class")),
    "not present"
  )
})

test_that("a reference table with only one taxonomic_status still gets a 0-row sublist for the other", {
  # regression test: a real, valid input shape (e.g. an accepted-names-only download) used to leave
  # resources$species$synonym missing (NULL) entirely rather than an empty tibble, since
  # split(species_table, species_table$taxonomic_status) only ever creates elements for statuses
  # actually present. match_taxa()'s match_01b/01d/05b/09b/10b/11b blocks reference
  # resources$species$synonym$<column> unconditionally regardless of whether any input name matches --
  # NULL$<column> is NULL, and dplyr::mutate(x = NULL) *drops* the column rather than leaving it NA, so
  # every alignment (matching nothing in that block, as always happens when there's nothing to match
  # against) hit a "Can't recycle input of size N to size M" error rather than aligning normally.
  accepted_only <- sample_taxonomic_resources() |> dplyr::filter(taxonomic_status == "accepted")
  resources <- prepare_taxonomic_resources(accepted_only)

  expect_setequal(names(resources$species), c("accepted", "synonym"))
  expect_equal(nrow(resources$species$synonym), 0)
  expect_true(all(c("scientific_name", "canonical_name", "taxon_ID") %in% names(resources$species$synonym)))

  # the real symptom: align_taxa() used to error outright on *any* name, not just unmatched ones
  out <- align_taxa("Boronia serrulata Sm.", resources)
  expect_equal(out$aligned_name, "Boronia serrulata")
})
