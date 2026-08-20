# A second hand-built combined taxonomic reference table, complementing sample_taxon_resources()
# (helper-align-taxa-fixtures.R) -- that one is deliberately plant-flavoured (Boronia/Rutaceae) and
# covers the *structural* rank/status-splitting machinery; this one is deliberately invertebrate-
# flavoured and covers *messy real-world name* oddities specifically, grounded in genuine AFD naming
# conventions confirmed against the real inst/extdata/AFD.csv (not invented from scratch):
# - a hyphenated "letter-shape" epithet (a real, recurring AFD convention for species named after a
#   marking resembling a letter, e.g. "t-viride", "v-album", "c-purpureus")
# - a nominotypical subgenus that repeats its genus name in brackets (Aporocera (Aporocera) ...) --
#   extremely common in real zoological nomenclature, distinct from sample_taxon_resources()'s
#   Boronia (Valvatae) case where the subgenus has its own, different name
# - *two* synonyms for the same accepted species (sample_taxon_resources() only ever has one per
#   accepted name), one of them under a *different* genus entirely -- a genuinely common real pattern
#   when a species is moved between genera over its taxonomic history
# - a subspecies-rank row distinct from sample_taxon_resources()'s "variety" example
#
# A second, unrelated genus ("Xylotoles") is included specifically to test that fuzzy matching
# doesn't cross-collide between unrelated taxa -- picked to share no first-letter/first-2-letter
# prefix with "Aporocera", per the "Boronieae vs Boronia" gotcha documented in CLAUDE.md.
sample_invert_taxon_resources <- function() {
  tibble::tribble(
    ~scientific_name, ~canonical_name, ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus, ~taxon_ID, ~accepted_name_usage_ID,
    "Aporocera t-viride Blackburn, 1899", "Aporocera t-viride", "species", "accepted", "TEST", "Aporocera", "sp1", "sp1",
    # two synonyms for the one accepted species above -- the second under a different genus entirely,
    # reflecting a real, common invertebrate taxonomy pattern (a species moved between genera over time)
    "Aporocera viridipennis Lea, 1915", "Aporocera viridipennis", "species", "synonym", "TEST", "Aporocera", "sp2", "sp1",
    "Chalcolampra viridis Blackburn, 1897", "Chalcolampra viridis", "species", "synonym", "TEST", "Chalcolampra", "sp3", "sp1",
    "Aporocera Blackburn", "Aporocera", "genus", "accepted", "TEST", NA_character_, "g1", "g1",
    "Aporocera (Aporocera) Blackburn", "Aporocera", "subgenus", "accepted", "TEST", "Aporocera", "sg1", "sg1",
    "Chrysomelidae Latreille", "Chrysomelidae", "family", "accepted", "TEST", NA_character_, "f1", "f1",
    "Xylotoles costatus Pascoe, 1859", "Xylotoles costatus", "species", "accepted", "TEST", "Xylotoles", "sp4", "sp4",
    "Xylotoles costatus mixtus Someone, 1920", "Xylotoles costatus mixtus", "subspecies", "accepted", "TEST", "Xylotoles", "sp5", "sp5",
    "Xylotoles Pascoe", "Xylotoles", "genus", "accepted", "TEST", NA_character_, "g2", "g2"
  )
}
