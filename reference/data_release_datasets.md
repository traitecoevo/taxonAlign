# List the datasets in a taxonAlign data release

Reads a data release's manifest: the datasets
[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md)
can load from it, and where each came from. Cite the sources of the
datasets you use.

## Usage

``` r
data_release_datasets(
  version = NULL,
  path = NULL,
  refresh_cache = FALSE,
  cache_dir = tools::R_user_dir("taxonAlign", "cache"),
  quiet = FALSE
)
```

## Arguments

- version:

  Data release to load, a date (`"YYYY-MM-DD"`); see
  [`data_release_versions()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_versions.md).
  Defaults to the latest release, or, with no internet connection, the
  newest release already downloaded.

- path:

  Optional directory holding your own copy of a release's files
  (`manifest.csv` and the `<dataset>.parquet` files). `version` is then
  ignored.

- refresh_cache:

  Logical; if `TRUE`, re-downloads the files even if they're cached.
  Defaults to `FALSE`.

- cache_dir:

  Directory downloaded release files are cached in. Defaults to
  `tools::R_user_dir("taxonAlign", "cache")`.

- quiet:

  Logical; suppress progress messages. Defaults to `FALSE`.

## Value

A tibble with one row per dataset: `dataset`, `asset` (the release
file), `rows`, `source`, `retrieved`, `licence` and `citation`. The
release is recorded in its `"data_release"` attribute.
