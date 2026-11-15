# The taxonomic reference format taxonAlign matches against

Describes the columns a taxonomic reference table needs before it can be
passed to
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md),
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md),
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
or
[`create_taxonomic_update_lookup()`](https://traitecoevo.github.io/taxonAlign/reference/create_taxonomic_update_lookup.md).
Every reference taxonAlign loads
([`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md))
is in this format, and any table you build yourself – by hand, with your
own scripts, or with the `taxonAlign.dataprep` package – just needs to
be in it too.

## Usage

``` r
taxonomic_reference_schema()
```

## Value

A tibble with one row per column: `column`, `required` (logical),
`darwin_core` (the Darwin Core name it's renamed from, or `NA`) and
`description`.

## Details

Eight columns are required: `canonical_name`, `scientific_name`,
`taxon_rank`, `taxonomic_status`, `taxonomic_dataset`, `genus`,
`taxon_ID` and `accepted_name_usage_ID`. The names follow
[APCalign](https://traitecoevo.github.io/APCalign/)'s own; where a
Darwin Core name exists (`canonicalName`, `taxonRank`, ...),
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
renames it automatically.

Any other column is kept. A character column named after a rank
(`family`, `order`, `tribe`, ...) is read as that rank's value for each
row:
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
adds a row for every family/order/... named this way that has no row of
its own. Such an added row's `taxon_ID` is
`<taxonomic_dataset>_<rank>_<name>`, e.g. `"WCVP_family_Annonaceae"`
(the dataset of the first row naming it) – built from the name alone, so
it's the same every time the same reference is prepared. The optional
columns listed by `taxonomic_reference_schema()` (`scientific_name_ID`,
`scientific_name_authorship`, `taxon_distribution`, `extinct`, ...) are
never read as ranks. `extinct` (logical) is described in
[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md).

One record per row. A synonym (any `taxonomic_status` other than
`"accepted"`) has its own row, whose `accepted_name_usage_ID` is the
`taxon_ID` of the accepted record it leads to. If a table has several
references in it, it's ordered from most to least preferred: when the
same name appears twice with the same status, taxonAlign uses the first.

## See also

[`check_taxonomic_reference()`](https://traitecoevo.github.io/taxonAlign/reference/check_taxonomic_reference.md)
to check a table is in this format.

## Examples

``` r
taxonomic_reference_schema()
#> # A tibble: 21 × 4
#>    column                 required darwin_core         description              
#>    <chr>                  <lgl>    <chr>               <chr>                    
#>  1 canonical_name         TRUE     canonicalName       "The name without author…
#>  2 scientific_name        TRUE     scientificName      "The name with authorshi…
#>  3 taxon_rank             TRUE     taxonRank           "The record's rank, e.g.…
#>  4 taxonomic_status       TRUE     taxonomicStatus     "\"accepted\" for a curr…
#>  5 taxonomic_dataset      TRUE     NA                  "The reference the recor…
#>  6 genus                  TRUE     NA                  "The genus of a genus-ra…
#>  7 taxon_ID               TRUE     taxonID             "An identifier for the r…
#>  8 accepted_name_usage_ID TRUE     acceptedNameUsageID "The taxon_ID of the acc…
#>  9 name_type              FALSE    nameType            "Optional; kept as-is."  
#> 10 pro_parte              FALSE    proParte            "Optional; kept as-is."  
#> # ℹ 11 more rows
```
