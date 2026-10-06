# A small, hand-built pair of tibbles shaped like a raw National Species List (NSL) "taxon"/"names"
# CSV export pair (same column names/conventions as the real inst/extdata/Australian_*/ files), used
# to test load_Australian_NSL() end to end, entirely offline. Only the columns the loader actually
# reads are included (the real files carry 37/47 columns each; most are unused).
#
# Deliberately spans: a family (to test genus = NA above genus rank), a genus, a subgenus written in
# NSL's own "Genus subg. Subgenusname" marker convention ("Testusgenus subg. Testussub" -- to test
# strip_NSL_subgenus_marker()'s stripping and extract_genus()'s pairing), an accepted species and a
# synonym of it under a *different* genus ("Oldgenus alphus"), and one row present *only* in the names
# file (never promoted to a taxon concept, taxonomicStatus = "unplaced") -- to test that taxa always
# take priority over names (every other names-file row here duplicates a taxon-file scientificNameID
# and must be dropped, not double-counted).
sample_nsl_taxon_raw <- function() {
  tibble::tribble(
    ~taxonID, ~scientificNameID, ~acceptedNameUsageID, ~taxonomicStatus, ~scientificName, ~canonicalName, ~taxonRank, ~datasetName,

    "t-fam1", "n-fam1", "t-fam1", "accepted", "Testidae", "Testidae", "Family", "TFX",
    "t-gen1", "n-gen1", "t-gen1", "accepted", "Testusgenus Sm.", "Testusgenus", "Genus", "TFX",
    "t-subg1", "n-subg1", "t-subg1", "accepted", "Testusgenus subg. Testussub Sm.", "Testusgenus subg. Testussub", "Subgenus", "TFX",
    "t-sp1", "n-sp1", "t-sp1", "accepted", "Testusgenus alphus Sm.", "Testusgenus alphus", "Species", "TFX",
    "t-sp1-syn", "n-sp1-syn", "t-sp1", "taxonomic synonym", "Oldgenus alphus Jones", "Oldgenus alphus", "Species", "TFX"
  )
}

sample_nsl_names_raw <- function() {
  tibble::tribble(
    ~scientificNameID, ~canonicalName, ~scientificName, ~taxonRank, ~taxonomicStatus, ~genericName, ~datasetName,

    # duplicates every scientificNameID already in the taxon file -- must all be dropped, not doubled
    "n-fam1", "Testidae", "Testidae", "Family", "included", NA_character_, "NFX",
    "n-gen1", "Testusgenus", "Testusgenus Sm.", "Genus", "accepted", "Testusgenus", "NFX",
    "n-subg1", "Testusgenus subg. Testussub", "Testusgenus subg. Testussub Sm.", "Subgenus", "accepted", "Testusgenus", "NFX",
    "n-sp1", "Testusgenus alphus", "Testusgenus alphus Sm.", "Species", "accepted", "Testusgenus", "NFX",
    "n-sp1-syn", "Oldgenus alphus", "Oldgenus alphus Jones", "Species", "included", "Oldgenus", "NFX",

    # names-file-only row -- no taxon concept of its own, only widens coverage
    "n-extra1", "Testusgenus informalis", "Testusgenus informalis ms.", "Species", "unplaced", "Testusgenus", "NFX"
  )
}

# Writes both fixtures into a fresh "Australian_<group>"-shaped temp directory (the "-taxon-"/"-names-"
# filename markers load_Australian_NSL()'s find_NSL_file() looks for), and returns that directory's
# path -- the shape its `path` argument expects.
write_sample_nsl_dir <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  readr::write_csv(sample_nsl_taxon_raw(), file.path(dir, "TFX-taxon-2026-01-01-1.csv"))
  readr::write_csv(sample_nsl_names_raw(), file.path(dir, "NFX-names-2026-01-01-1.csv"))
  dir
}
