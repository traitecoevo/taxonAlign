# A small, hand-built pair of tibbles shaped like a raw National Species List (NSL) "taxon"/"names"
# CSV export pair (same column names/conventions as the real inst/extdata/Australian_*/ files), used
# to test load_NSL_resources() end to end, entirely offline. Only the columns the loader actually
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
# filename markers load_NSL_resources()'s find_NSL_file() looks for), and returns that directory's
# path -- the shape its `path` argument expects.
write_sample_nsl_dir <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  readr::write_csv(sample_nsl_taxon_raw(), file.path(dir, "TFX-taxon-2026-01-01-1.csv"))
  readr::write_csv(sample_nsl_names_raw(), file.path(dir, "NFX-names-2026-01-01-1.csv"))
  dir
}

# An animals-shaped NSL export pair -- the Australian Faunal Directory's own NSL export, which carries
# the same concepts as the plant-side groups above but as pipe-delimited `.txt` files with snake_case
# column names and "_taxon_"/"_name_" filename markers. Deliberately spans: a zoological
# "Genus (Subgenus)" subgenus (incl. a nominotypical one); a "vagrant species" whose
# accepted_name_usage_id points at its *family* (AFD's real convention for excluded/vagrant taxa,
# which must be made self-referential); a "Generic combination" synonym; a single-word zoological
# "Section" row and a "Generic Aggregate" row written "Subtribe Testina" (both must get genus = NA);
# and one names-file-only row. `generic_name` in the taxon file is deliberately the *accepted* genus
# (as in the real export), to prove it's not used for a synonym's own genus.
sample_nsl_animals_taxon_raw <- function() {
  tibble::tribble(
    ~taxon_id, ~scientific_name_id, ~accepted_name_usage_id, ~taxonomic_status, ~scientific_name, ~canonical_name, ~taxon_rank, ~dataset_name, ~generic_name,

    "t-fam", "n-fam", "t-fam", "accepted", "Avidae Smith, 1900", "Avidae", "Family", "AFD", NA,
    "t-sect", "n-sect", "t-sect", "accepted", "Eusectio", "Eusectio", "Section", "AFD", NA,
    "t-agg", "n-agg", "t-agg", "accepted", "Subtribe Testina", "Subtribe Testina", "Generic Aggregate", "AFD", NA,
    "t-gen", "n-gen", "t-gen", "accepted", "Avigenus Smith, 1900", "Avigenus", "Genus", "AFD", "Avigenus",
    "t-sg1", "n-sg1", "t-sg1", "accepted", "Avigenus (Avigenus) Smith, 1900", "Avigenus (Avigenus)", "Subgenus", "AFD", "Avigenus",
    "t-sg2", "n-sg2", "t-sg2", "accepted", "Avigenus (Montavis) Jones, 1950", "Avigenus (Montavis)", "Subgenus", "AFD", "Avigenus",
    "t-sp", "n-sp", "t-sp", "accepted", "Avigenus alba (Smith, 1900)", "Avigenus alba", "Species", "AFD", "Avigenus",
    "t-gc", "n-gc", "t-sp", "Generic combination", "Oldavis alba Smith, 1900", "Oldavis alba", "Species", "AFD", "Avigenus",
    "t-vag", "n-vag", "t-fam", "vagrant species", "Vagrantia errans Brown, 1880", "Vagrantia errans", "Species", "AFD", NA
  )
}

sample_nsl_animals_names_raw <- function() {
  tibble::tribble(
    ~name_id, ~scientific_name_id, ~canonical_name, ~scientific_name, ~taxon_rank, ~taxonomic_status, ~generic_name, ~dataset_name,

    "1", "n-sp", "Avigenus alba", "Avigenus alba (Smith, 1900)", "Species", "accepted", "Avigenus", "AFDNI",
    "2", "n-gc", "Oldavis alba", "Oldavis alba Smith, 1900", "Species", "included", "Oldavis", "AFDNI",
    "3", "n-sg2", "Avigenus (Montavis)", "Avigenus (Montavis) Jones, 1950", "Subgenus", "accepted", "Avigenus", "AFDNI",
    # names-file-only rows -- widen coverage only
    "4", "n-extra", "Avigenus alba minor", "Avigenus alba minor Green, 1920", "Subspecies", "unplaced", "Avigenus", "AFDNI",
    "5", "n-extra-sg", "Avigenus (Lowavis)", "Avigenus (Lowavis) Green, 1920", "Subgenus", "unplaced", "Avigenus", "AFDNI"
  )
}

# Writes the animals fixture pair the way the real AFD NSL export ships: pipe-delimited, every value
# quoted, "_taxon_"/"_name_" filename markers, `.txt` extension.
write_sample_nsl_animals_dir <- function() {
  dir <- withr::local_tempdir(.local_envir = parent.frame())
  readr::write_delim(sample_nsl_animals_taxon_raw(), file.path(dir, "AFD_export_taxon_20260101.txt"), delim = "|", quote = "all", na = "")
  readr::write_delim(sample_nsl_animals_names_raw(), file.path(dir, "AFD_export_name_20260101.txt"), delim = "|", quote = "all", na = "")
  dir
}
