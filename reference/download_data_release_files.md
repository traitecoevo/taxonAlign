# Download files from a taxonAlign data release

Downloads (or finds already cached) any files from a data release – the
ready datasets
[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md)
reads, or the verbatim source exports stored alongside them (e.g.
`"nsl_fungi_taxon.parquet"`), which `taxonAlign.dataprep` rebuilds
references from. Most users never need this directly.
[`data_release_versions()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_versions.md)
lists the releases; each release's `manifest.csv` lists its files.

## Usage

``` r
download_data_release_files(
  files,
  version = NULL,
  refresh_cache = FALSE,
  cache_dir = tools::R_user_dir("taxonAlign", "cache"),
  quiet = FALSE
)
```

## Arguments

- files:

  Character vector of file names in the release.

- version:

  Data release to load, a date (`"YYYY-MM-DD"`); see
  [`data_release_versions()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_versions.md).
  Defaults to the latest release, or, with no internet connection, the
  newest release already downloaded.

- refresh_cache:

  Logical; if `TRUE`, re-downloads the files even if they're cached.
  Defaults to `FALSE`.

- cache_dir:

  Directory downloaded release files are cached in. Defaults to
  `tools::R_user_dir("taxonAlign", "cache")`.

- quiet:

  Logical; suppress progress messages. Defaults to `FALSE`.

## Value

A named character vector of local file paths, one per file. Downloaded
files are cached under `<cache_dir>/data_release/<version>/`; if the
latest release can't be downloaded, the newest release already cached
that has every file is used instead (never when `version` is given).

## Examples

``` r
# \donttest{
# needs the internet: the release's manifest, into a temporary cache
if (curl::has_internet()) {
  download_data_release_files("manifest.csv", version = "2026-11-14", cache_dir = tempfile())
}
#> Downloading manifest.csv (data release 2026-11-14)...
#>                                                           manifest.csv 
#> "/tmp/RtmprT685d/file1c15744de30/data_release/2026-11-14/manifest.csv" 
# }
```
