# Shared fixture builders for mocking rgbif responses. Sourced automatically
# by testthat before the test files run.

# one row of a GBIF backbone usage, with sane defaults for the columns
# `generate_taxonomic_reference_list()` reads out of `name_lookup()`/`name_usage()`
gbif_taxon_row <- function(key,
                            parentKey = NA_integer_,
                            acceptedKey = NA_integer_,
                            scientificName,
                            canonicalName = scientificName,
                            rank,
                            taxonomicStatus = "ACCEPTED",
                            kingdom = "Plantae",
                            phylum = "Tracheophyta",
                            class = "Magnoliopsida",
                            order = "Sapindales",
                            family = "Rutaceae",
                            genus = NA_character_) {
  tibble::tibble(
    key = as.integer(key),
    parentKey = as.integer(parentKey),
    acceptedKey = as.integer(acceptedKey),
    scientificName = scientificName,
    canonicalName = canonicalName,
    rank = rank,
    taxonomicStatus = taxonomicStatus,
    kingdom = kingdom,
    phylum = phylum,
    class = class,
    order = order,
    family = family,
    genus = genus
  )
}

# a `name_backbone()`-shaped single-row match
gbif_backbone_match <- function(usageKey,
                                  scientificName,
                                  canonicalName = scientificName,
                                  rank,
                                  status = "ACCEPTED",
                                  matchType = "EXACT",
                                  kingdom = "Plantae",
                                  acceptedUsageKey = NA_integer_,
                                  note = NA_character_) {
  tibble::tibble(
    usageKey = as.integer(usageKey),
    scientificName = scientificName,
    canonicalName = canonicalName,
    rank = rank,
    status = status,
    matchType = matchType,
    kingdom = kingdom,
    acceptedUsageKey = as.integer(acceptedUsageKey),
    note = note
  )
}

# a `name_lookup()`-shaped page: list(meta = list(count = ...), data = tibble)
gbif_lookup_page <- function(data, count = nrow(data)) {
  list(meta = list(count = count), data = data)
}

# an `occ_search()`-shaped result with a `taxonKey` facet
gbif_occ_facet <- function(keys, counts = rep(1L, length(keys))) {
  if (length(keys) == 0) {
    return(list(facets = list()))
  }
  list(facets = list(taxonKey = data.frame(
    name = as.character(keys), count = counts, stringsAsFactors = FALSE
  )))
}
