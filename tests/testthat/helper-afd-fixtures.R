# A small, hand-built tibble shaped exactly like a raw AFD CSV export (same column names/conventions
# as the real `inst/extdata/AFD.csv`), used to test `load_taxonomic_resources(taxonomic_dataset =
# "AFD")` end to end, entirely offline -- no need for the real ~89MB file. Written to a temp CSV and
# read back via `load_taxonomic_resources()`'s real `path` argument, so the test exercises the actual
# CSV round-trip, not just the internal reshaping helpers directly.
#
# Deliberately spans: an accepted species and a subspecies under it (to test taxon_rank derivation from
# SUB_SPECIES); two distinct families, written ALL CAPS as AFD's own export does for family-and-above
# ranks (to test the sentence-case normalisation); a subgenus (to test genus/subgenus pairing); a
# synonym whose authorship is in the AUTHOR-column dictionary ("Smith") and one whose authorship isn't
# ("Someunlistedauthor" -- capitalised, so the generic fallback pattern still strips it) -- see
# `strip_afd_authorship()`.
sample_afd_raw <- function() {
  tibble::tribble(
    ~FULL_NAME, ~COMPLETE_NAME, ~AUTHOR, ~YEAR, ~SUB_SPECIES, ~SPECIES, ~GENUS, ~SUB_GENUS,
    ~FAMILY, ~SUBFAMILY, ~ORDER, ~CLASS, ~PHYLUM, ~SYNONYMS, ~CONCEPT_GUID,

    "Testus alphus", "Testus alphus, Smith 1900", "Smith", "1900", NA_character_, "alphus", "Testus", NA_character_,
    "TESTIDAE", "Testinae", "TESTOPTERA", "INSECTA", "ARTHROPODA",
    "Oldgenus alphus Smith, 1900; Weirdgenus alphus Someunlistedauthor, 1888", "guid-1",

    "Testus alphus betus", "Testus alphus betus, Jones 1950", "Jones", "1950", "betus", "alphus", "Testus", NA_character_,
    "TESTIDAE", "Testinae", "TESTOPTERA", "INSECTA", "ARTHROPODA",
    NA_character_, "guid-2",

    "Anothergenus (Subgenusy) gammus", "Anothergenus gammus, Brown 1999", "Brown", "1999", NA_character_, "gammus", "Anothergenus", "Subgenusy",
    "ANOTHERFAM", "Anothersubfam", "ANOTHERORDER", "INSECTA", "ARTHROPODA",
    NA_character_, "guid-3"
  )
}

# Writes sample_afd_raw() to a temp CSV and returns its path -- the shape load_taxonomic_resources()'s
# `path` argument expects.
write_sample_afd_csv <- function() {
  path <- tempfile(fileext = ".csv")
  readr::write_csv(sample_afd_raw(), path)
  path
}
