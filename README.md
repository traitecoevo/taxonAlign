# taxonAlign


<!-- README.md is generated from README.qmd. Please edit that file -->

<!-- badges: start -->

<!-- badges: end -->

`taxonAlign` helps you:

1.  **Build a personalised taxonomic reference** by combining one or
    more taxonomic reference tables – your own, one built from the
    GBIF backbone taxonomy with
    `generate_GBIF_taxonomic_reference_list()`, or a mix of both.
2.  **Fuzzy-match a list of raw taxon names** against that reference,
    resolving misspellings, synonyms, and names only identifiable to a
    higher rank (`genus sp.`), to maximise how many of your names
    align successfully.

It’s inspired by [APCalign](https://traitecoevo.github.io/APCalign/)’s
approach to aligning taxon names to the Australian Plant Census,
generalised so the reference doesn’t have to be APC/APNI and the taxa
don’t have to be plants – any taxonomic rank present in your reference
(species, genus, family, or anything else) can be matched against, not
just genus/species/family.

## Installation

`taxonAlign` isn’t on CRAN. Install the development version from
GitHub:

``` r
# install.packages("pak")
pak::pak("traitecoevo/taxonAlign")
```

## Workflow

| Function | What it does |
|----|----|
| `generate_GBIF_taxonomic_reference_list()` | Build a reference table from the GBIF backbone taxonomy for a taxon (optionally filtered by country and/or minimum rank). |
| `prepare_taxonomic_resources()` | Combine one or more reference tables (yours, GBIF’s, or both) into the structure the matching functions need. |
| `align_taxa()` | Match a list of raw taxon names against a prepared reference, via exact and fuzzy matching. |
| `update_taxa()` | Resolve a matched (possibly synonymous) name forward to its current accepted name. |
| `create_taxonomic_update_lookup()` | Run `align_taxa()` and `update_taxa()` together in one call – the easiest way to go from raw names to a lookup table of accepted names. |

## Example

Given a small taxonomic reference (built here by hand for the example
– in practice, this would usually come from your own data, or from
`generate_GBIF_taxonomic_reference_list()`):

``` r
library(taxonAlign)

reference <- tibble::tribble(
  ~scientific_name,        ~canonical_name,     ~taxon_rank, ~taxonomic_status, ~taxonomic_dataset, ~genus,    ~taxon_ID, ~accepted_name_usage_ID,
  "Boronia serrulata Sm.", "Boronia serrulata", "species",   "accepted",        "EXAMPLE",          "Boronia", "sp1",     "sp1",
  "Zieria serrulata Sm.",  "Zieria serrulata",  "species",   "synonym",         "EXAMPLE",          "Zieria",  "sp2",     "sp1"
)

resources <- prepare_taxonomic_resources(reference)
```

`create_taxonomic_update_lookup()` matches a list of raw names –
including a misspelling and an outdated synonym – and resolves each to
its current accepted name in one call:

``` r
create_taxonomic_update_lookup(
  c("Boronia serrulata", "Boronia serulata", "Zieria serrulata"),
  resources
) |>
  dplyr::select(original_name, aligned_name, accepted_name, taxonomic_status)
#> # A tibble: 3 × 4
#>   original_name     aligned_name      accepted_name     taxonomic_status
#>   <chr>             <chr>             <chr>             <chr>           
#> 1 Boronia serrulata Boronia serrulata Boronia serrulata accepted        
#> 2 Boronia serulata  Boronia serrulata Boronia serrulata accepted        
#> 3 Zieria serrulata  Zieria serrulata  Boronia serrulata accepted
```

<!-- You'll still need to render `README.qmd` regularly, to keep `README.md` up-to-date.  -->
