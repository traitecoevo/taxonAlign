# Load released taxonomic reference data

Downloads one or more taxonomic reference datasets from a dated
taxonAlign data release, ready to pass to
[`create_taxonomic_update_lookup()`](https://traitecoevo.github.io/taxonAlign/reference/create_taxonomic_update_lookup.md),
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
or
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md).
Naming the release (`version`) makes an alignment reproducible.
Downloaded files are cached, so each is only downloaded once.

## Usage

``` r
load_taxonomic_resources(
  datasets,
  version = NULL,
  include_extinct = FALSE,
  path = NULL,
  refresh_cache = FALSE,
  cache_dir = tools::R_user_dir("taxonAlign", "cache"),
  quiet = FALSE
)
```

## Arguments

- datasets:

  Character vector of datasets to load, e.g.
  `c("NSL_animals", "GBIF_AU")`.

- version:

  Data release to load, a date (`"YYYY-MM-DD"`); see
  [`data_release_versions()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_versions.md).
  Defaults to the latest release, or, with no internet connection, the
  newest release already downloaded.

- include_extinct:

  Logical; if `TRUE`, also keep taxa flagged as extinct, and their
  synonyms. Defaults to `FALSE`.

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

A named list of tibbles, one per dataset, each in taxonAlign's reference
format (see
[`taxonomic_reference_schema()`](https://traitecoevo.github.io/taxonAlign/reference/taxonomic_reference_schema.md)).
The release it came from is recorded in each tibble's `"data_release"`
attribute. If the release can't be had (offline with nothing cached,
GitHub not answering, or no such release), `NULL`, invisibly, with a
message saying why, as APCalign's `load_taxonomic_resources()` does.

## Details

The datasets in the first release are the Australian National Species
List exports – `"NSL_animals"` (the Australian Faunal Directory),
`"NSL_algae"`, `"NSL_bryophytes"`, `"NSL_fungi"` and `"NSL_lichens"` –
and `"GBIF_AU"`, every animal taxon in the GBIF Backbone with occurrence
records in Australia, plus its synonyms. GBIF has since replaced its
Backbone with the Catalogue of Life Extended Release, so later releases
have `"CatalogueOfLife_AU"` instead: that release's animal names GBIF
has Australian records of, plus their synonyms.
[`data_release_datasets()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_datasets.md)
lists what a release holds, with each dataset's source, retrieval date,
licence and citation.

When several datasets are loaded, they're returned in the order given,
which is the order they're preferred in when the same match attempt
finds a name in more than one (see
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)'s
Details).

Some datasets flag extinct taxa (an `extinct` column; `"GBIF_AU"`).
(`"CatalogueOfLife_AU"` has no flag; it leaves out names GBIF knows only
from fossil specimens instead.) GBIF's occurrence records include fossil
specimens, so these are left out by default, as they only produce
spurious matches against modern names. GBIF's flag doesn't distinguish
fossils from recent extinctions, though – the thylacine (*Thylacinus
cynocephalus*) is flagged extinct too – so `include_extinct = TRUE`
keeps everything, with the `extinct` column showing which are which.

The releases are built by the `taxonAlign.dataprep` package, which also
has the functions for building a reference from other sources (a live
GBIF fetch, taxadb, the AFD's own export, APC).

## Examples

``` r
# \donttest{
# needs the internet: the lichen list from the National Species List (a few MB), into a
# temporary cache; a misspelling ("inermsi") is corrected
if (curl::has_internet()) {
  lichens <- load_taxonomic_resources("NSL_lichens", version = "2026-11-14", cache_dir = tempfile())
  create_taxonomic_update_lookup(c("Cladia aggregata", "Usnea inermsi"), lichens)
}
#> Downloading manifest.csv (data release 2026-11-14)...
#> Downloading NSL_lichens.parquet (data release 2026-11-14)...
#> Summary of 2 names:
#>   -> 2 aligned to a species or infraspecific taxon (2 in ALC)
#>   -> 0 aligned only to a genus and 0 only to a family
#>   -> 0 could not be aligned
#>   -> 0 aligned names were updated to a different name (e.g. a synonym to its accepted name, or an outdated genus to the current one)
#> # A tibble: 2 × 20
#>   original_name    aligned_name    accepted_name suggested_name genus taxon_rank
#>   <chr>            <chr>           <chr>         <chr>          <chr> <chr>     
#> 1 Cladia aggregata Cladia aggrega… Cladia aggre… Cladia aggreg… Clad… species   
#> 2 Usnea inermsi    Usnea inermis   Usnea inermis Usnea inermis  Usnea species   
#> # ℹ 14 more variables: taxonomic_dataset <chr>, taxonomic_status <chr>,
#> #   scientific_name <chr>, aligned_reason <chr>, update_reason <chr>,
#> #   number_of_collapsed_taxa <int>, chars_changed <int>, taxon_ID <chr>,
#> #   taxon_ID_genus <chr>, scientific_name_ID <chr>, family <chr>,
#> #   taxonomic_status_aligned <chr>, alternative_possible_names <chr>,
#> #   identifier <chr>
# }
```
