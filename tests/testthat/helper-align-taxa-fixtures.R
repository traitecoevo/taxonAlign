# A small, hand-built combined taxonomic reference table used to test
# `prepare_taxonomic_resources()`/`align_taxa()`/`match_taxa()` end to end, entirely offline (no
# GBIF/APCalign network calls -- `APCalign::standardise_names()`/`strip_names()`/
# `strip_names_extra()`/`standardise_taxon_rank()` are pure string functions, safe to call directly).
#
# Deliberately spans: species (accepted + synonym), genus, family, an extra higher rank not in any
# hardcoded rank list ("tribe"), and a subgenus (to exercise both the bracketed `Genus (Subgenus)`
# and plain `Subgenus` matching conventions).
sample_taxon_resources <- function() {
  tibble::tribble(
    ~taxon_name, ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus,
    "Boronia serrulata", "Boronia serrulata Sm.", "Boronia serrulata", "species", "accepted", "TEST", "Boronia",
    "Boronia pinnata var. pinnata", "Boronia pinnata var. pinnata Sm.", NA_character_, "variety", "accepted", "TEST", "Boronia",
    "Boronia oldname", "Boronia oldname Sm.", "Boronia oldname", "species", "synonym", "TEST", "Boronia",
    "Boronia", "Boronia Sm.", "Boronia", "genus", "accepted", "TEST", NA_character_,
    "Rutaceae", "Rutaceae Juss.", "Rutaceae", "family", "accepted", "TEST", NA_character_,
    "Zanthoxyleae", "Zanthoxyleae Nees.", "Zanthoxyleae", "tribe", "accepted", "TEST", NA_character_,
    "Valvatae", "Valvatae Endl.", "Valvatae", "subgenus", "accepted", "TEST", "Boronia"
  )
}
