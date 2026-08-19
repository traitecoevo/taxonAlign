# A small, hand-built combined taxonomic reference table used to test
# `prepare_taxonomic_resources()`/`align_taxa()`/`match_taxa()`/`update_taxa()`/
# `create_taxonomic_update_lookup()` end to end, entirely offline (no GBIF/APCalign network calls --
# `APCalign::standardise_names()`/`strip_names()`/`strip_names_extra()`/`standardise_taxon_rank()` are
# pure string functions, safe to call directly).
#
# Deliberately spans: species (accepted + synonym), genus (accepted + synonym), family (accepted
# only), order (accepted + synonym -- a *second*, distinct higher rank with an outdated name, to prove
# `update_taxa()`'s single lookup isn't secretly species/genus-specific), an extra higher rank not in
# any hardcoded rank list ("tribe", accepted only), and a subgenus (to exercise both the bracketed
# `Genus (Subgenus)` and plain `Subgenus` matching conventions). `taxon_ID`/`accepted_name_usage_ID`
# are self-referential for every accepted row and point at the accepted counterpart for every synonym
# row, matching the convention `prepare_taxonomic_resources()` requires.
sample_taxon_resources <- function() {
  tibble::tribble(
    ~taxon_name, ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Boronia serrulata", "Boronia serrulata Sm.", "Boronia serrulata", "species", "accepted", "TEST", "Boronia", "sp1", "sp1",
    "Boronia pinnata var. pinnata", "Boronia pinnata var. pinnata Sm.", NA_character_, "variety", "accepted", "TEST", "Boronia", "sp2", "sp2",
    # historically classified under a different (fictional) genus -- genus = "Zieria" here is
    # deliberately outdated, so update_taxa() resolving it forward to "Boronia" (the accepted
    # counterpart's genus) is a meaningful check, not a same-value passthrough
    "Boronia oldname", "Boronia oldname Sm.", "Boronia oldname", "species", "synonym", "TEST", "Zieria", "sp3", "sp1",
    # a synonym whose accepted_name_usage_ID is dangling (points at nothing in this table) -- tests
    # that update_taxa() degrades gracefully rather than erroring when a match can't be resolved
    "Boronia missingaccepted", "Boronia missingaccepted Sm.", "Boronia missingaccepted", "species", "synonym", "TEST", "Boronia", "sp4", "sp99",
    "Boronia", "Boronia Sm.", "Boronia", "genus", "accepted", "TEST", NA_character_, "g1", "g1",
    "Boronella", "Boronella F.Muell.", "Boronella", "genus", "synonym", "TEST", NA_character_, "g2", "g1",
    "Rutaceae", "Rutaceae Juss.", "Rutaceae", "family", "accepted", "TEST", NA_character_, "f1", "f1",
    "Sapindales", "Sapindales Juss.", "Sapindales", "order", "accepted", "TEST", NA_character_, "o1", "o1",
    "Oldorderia", "Oldorderia Endl.", "Oldorderia", "order", "synonym", "TEST", NA_character_, "o2", "o1",
    "Zanthoxyleae", "Zanthoxyleae Nees.", "Zanthoxyleae", "tribe", "accepted", "TEST", NA_character_, "t1", "t1",
    "Valvatae", "Valvatae Endl.", "Valvatae", "subgenus", "accepted", "TEST", "Boronia", "sg1", "sg1"
  )
}
