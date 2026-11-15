# List the available taxonAlign data releases

The reference data
[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md)
loads is published as dated releases, so that an alignment can be
reproduced exactly by naming the release it used. This lists the
releases available online, most recent first;
[`data_release_datasets()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_datasets.md)
lists what's in one.

## Usage

``` r
data_release_versions(refresh = FALSE)
```

## Arguments

- refresh:

  Logical; if `TRUE`, query GitHub again rather than reusing the list
  already fetched in this session. Defaults to `FALSE`.

## Value

A character vector of release versions (dates, `"YYYY-MM-DD"`), most
recent first; empty if GitHub can't be reached.

## Examples

``` r
# \donttest{
data_release_versions()
#> [1] "2026-11-14" "2026-10-07"
# }
```
