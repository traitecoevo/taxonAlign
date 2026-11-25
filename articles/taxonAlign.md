# Getting started with taxonAlign

`taxonAlign` aligns a list of raw taxon names against a taxonomic
reference – matching misspellings, synonyms, and names only identifiable
to a higher rank (`genus sp.`) – and then updates each match to its
current accepted name. The reference can be one of the dated reference
lists taxonAlign publishes (the Australian National Species List lists,
and GBIF’s Australian animals), your own table, or any mix of these.

It’s inspired by [APCalign](https://traitecoevo.github.io/APCalign/)’s
approach to aligning taxon names to the Australian Plant Census,
generalised so the reference doesn’t have to be APC/APNI and the taxa
don’t have to be plants – every function here works for any taxonomic
rank present in your reference, not just species. A real list of raw
names is rarely all species anyway – some identifications only ever make
it to genus, family, or a “morphospecies” code – so every example below
deliberately mixes ranks, not just species names.

Building a reference from other sources – the World Checklist of
Vascular Plants, the Catalogue of Life, a live GBIF fetch, a
[taxadb](https://docs.ropensci.org/taxadb/) snapshot, the Australian
Plant Census, or your own table with different column names – is the job
of the companion package
[taxonAlign.dataprep](https://github.com/traitecoevo/taxonAlign.dataprep),
which also builds the released lists. You only need it if you’re
building a reference yourself.

This vignette walks through every exported function, in the order you’d
typically use them, then puts them together into the workflow you’d
actually run on a real list of names.

``` r

library(taxonAlign)
library(dplyr)
#> 
#> Attaching package: 'dplyr'
#> The following objects are masked from 'package:stats':
#> 
#>     filter, lag
#> The following objects are masked from 'package:base':
#> 
#>     intersect, setdiff, setequal, union
```

## Choosing a taxonomic reference

Every matching/aligning function needs a taxonomic reference to match
against: a released list, a global taxonomic resource, your own table,
or several combined.

### A released reference list

The simplest starting point is one of the reference lists published as
taxonAlign **data releases**: dated, fixed copies of each list, so that
an alignment can be repeated exactly later by naming the release it
used. The releases contain:

| Dataset | Reference | Source |
|----|----|----|
| `"NSL_animals"` | Animals (Australian Faunal Directory) | The AFD’s National Species List (NSL) export |
| `"NSL_algae"` | Algae | NSL export (AAL taxa, AANI names) |
| `"NSL_bryophytes"` | Bryophytes | NSL export (CAB taxa, ABNI names) |
| `"NSL_fungi"` | Fungi | NSL export (AFL taxa, AFNI names) |
| `"NSL_lichens"` | Lichens | NSL export (ALC taxa, ALNI names) |
| `"GBIF_AU"` | Animals recorded in Australia (GBIF) | GBIF Backbone taxonomy: taxa with Australian occurrence records, plus their synonyms. In the `2026-10-07` release; replaced by `"CatalogueOfLife_AU"` from the next one, as GBIF has replaced its Backbone with the Catalogue of Life Extended Release |
| `"CatalogueOfLife_AU"` | Animals recorded in Australia (Catalogue of Life) | Catalogue of Life Extended Release (COL26.10 XR): animal names with Australian records. From the `2026-11-14` release. |

[`data_release_versions()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_versions.md)
lists the releases available, most recent first, and
[`data_release_datasets()`](https://traitecoevo.github.io/taxonAlign/reference/data_release_datasets.md)
lists what’s in one, with each dataset’s source, retrieval date, licence
and citation:

``` r

data_release_versions()
#> [1] "2026-11-14" "2026-10-07"
data_release_datasets("2026-11-14")
```

[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md)
loads one or more datasets. Each is downloaded the first time you use it
and stored on your computer (in
`tools::R_user_dir("taxonAlign", "cache")`), so after that it loads
without downloading again, and works offline. The result can go straight
into any of the matching functions:

``` r

animals <- load_taxonomic_resources(c("NSL_animals", "CatalogueOfLife_AU"))
create_taxonomic_update_lookup(c("Pardalotus striatus", "Cynthia cardui"), animals)
```

When you load more than one dataset, the order you name them in is their
priority. Each match attempt (exact matches before fuzzy ones, accepted
names before synonyms, species before genus) searches both, and where it
finds the name in both, `"NSL_animals"`’s record wins. A name the AFD
has only as a misspelling or a synonym can still go to an exact,
accepted name in `"CatalogueOfLife_AU"`.

GBIF’s occurrence records include fossil specimens, so taxa GBIF flags
as extinct are left out by default, as they would otherwise produce
spurious matches. GBIF’s flag doesn’t distinguish fossils from recent
extinctions, though (the thylacine is flagged extinct too), so
`include_extinct = TRUE` keeps everything, with an `extinct` column
showing which are which.

Each NSL list combines the group’s two NSL exports: the *taxon* file
(accepted names and their synonyms, with links between them) and the
*names* file (every name recorded for the group). The taxon file always
takes priority; names found only in the names file are added so they can
still be recognised, but they’re never “updated” to anything, since the
names file doesn’t link them to an accepted name. Each release also
holds the NSL exports themselves, unchanged, so every list can be traced
back to exactly what was supplied.

**Naming the release.** Without `version`, the latest release is used.
To make an analysis reproducible, name the release instead – the same
release always gives the same result:

``` r

animals <- load_taxonomic_resources("NSL_animals", version = "2026-10-07")
```

**Working offline.** A named release that has already been downloaded is
loaded straight from your computer, without going online at all. Without
`version`, taxonAlign checks GitHub once per session (with a short time
limit) for the latest release; if it can’t (no internet, a slow
connection), it uses the most recent release already on your computer.
Releases are only published when a source actually changes, so an older
release isn’t necessarily out of date.

### Download global taxonomic resources

For taxa the released lists don’t cover, or a reference that covers the
whole world, the companion package
[taxonAlign.dataprep](https://github.com/traitecoevo/taxonAlign.dataprep)
downloads the major global taxonomic resources and reshapes them into
taxonAlign’s format. Install it with
`pak::pak("traitecoevo/taxonAlign.dataprep")`.

| Function | Reference | Best for |
|----|----|----|
| `load_CatalogueOfLife()` | Catalogue of Life, from [ChecklistBank](https://www.checklistbank.org) | A reference to every taxon in every kingdom (~5.5 million names); `extended = TRUE` for its Extended Release (~8.5 million), GBIF’s own taxonomy |
| `load_WCVP()` | World Checklist of Vascular Plants (Royal Botanic Gardens, Kew) | Every vascular plant name worldwide (~1.45 million) |
| `filter_to_country()` | Any of the above | Keeping only the taxa GBIF has occurrence records of in one or more countries |

Each returns one table in taxonAlign’s format, which goes straight into
the matching functions:

``` r

library(taxonAlign.dataprep)

# every vascular plant name worldwide, then only those GBIF has Australian records of
wcvp_au <- load_WCVP() |> filter_to_country("AU")
create_taxonomic_update_lookup(my_plant_names, wcvp_au)

# the Catalogue of Life, pinned to one release (COL26.10) so the alignment can be repeated
col <- load_CatalogueOfLife(316595)

# GBIF's own taxonomy (the Catalogue of Life Extended Release), only the animals GBIF has
# Australian records of
col_xr_au <- load_CatalogueOfLife(extended = TRUE) |> filter_to_country("AU", gbif_taxon = "Animalia")
```

A few things worth knowing:

- **The WCVP and Catalogue of Life are large downloads** (~90MB and
  ~170MB). Each is downloaded once and cached, so later calls load from
  your computer, offline. Name a version (`load_WCVP(16)`,
  `load_CatalogueOfLife(316595)`) to make an alignment repeatable.
- **A worldwide list matches more names than you may want**: a misspelt
  Australian plant name can fuzzy-match a species that only grows in
  South America. `filter_to_country()` avoids this. It keeps each
  taxon’s accepted name and all its synonyms, even where GBIF and the
  reference disagree on which name is accepted, so old names in your
  list still update.
- **taxadb’s own GBIF snapshot can be several years old.** Pass
  `gbif_snapshot_url` to query a current GBIF snapshot instead. taxadb
  is only needed for this one function: install it with
  `install.packages("taxadb")`.
- **For Australian vascular plants**, `load_APC()` loads the Australian
  Plant Census, the National Species List for vascular plants.

taxonAlign.dataprep’s own [getting-started
vignette](https://github.com/traitecoevo/taxonAlign.dataprep/blob/main/vignettes/get-started.qmd)
covers each of these in detail.

### Your own reference table

If you already have a taxonomic reference table – your own species list,
an export from a museum database, whatever – taxonAlign will take it as
long as it’s in taxonAlign’s reference format: eight required columns,
`canonical_name`, `scientific_name`, `taxon_rank`, `taxonomic_status`,
`taxonomic_dataset`, `genus`, `taxon_ID` and `accepted_name_usage_ID`.
[`taxonomic_reference_schema()`](https://traitecoevo.github.io/taxonAlign/reference/taxonomic_reference_schema.md)
describes each:

``` r

taxonomic_reference_schema() |> filter(required) |> select(column, description)
#> # A tibble: 8 × 2
#>   column                 description                                            
#>   <chr>                  <chr>                                                  
#> 1 canonical_name         "The name without authorship, e.g. \"Boronia serrulata…
#> 2 scientific_name        "The name with authorship, e.g. \"Boronia serrulata Sm…
#> 3 taxon_rank             "The record's rank, e.g. \"species\", \"genus\", \"fam…
#> 4 taxonomic_status       "\"accepted\" for a currently accepted name; anything …
#> 5 taxonomic_dataset      "The reference the record comes from, e.g. \"APC\", \"…
#> 6 genus                  "The genus of a genus-rank or narrower record (for a s…
#> 7 taxon_ID               "An identifier for the record, unique within the table…
#> 8 accepted_name_usage_ID "The taxon_ID of the accepted name the record leads to…
```

Here’s a small, hand-built example spanning several ranks: two genera, a
family, a subgenus, a species with two synonyms (one under a different
genus entirely – a real, common pattern when a species is reclassified
over its taxonomic history), and a subspecies.

``` r

my_reference <- tibble::tribble(
  ~scientific_name,                          ~canonical_name,             ~taxon_rank,  ~taxonomic_status, ~taxonomic_dataset, ~genus,      ~taxon_ID, ~accepted_name_usage_ID,
  "Aporocera t-viride Blackburn, 1899",       "Aporocera t-viride",       "species",    "accepted",         "MY_DATA",          "Aporocera",  "sp1",    "sp1",
  "Aporocera viridipennis Lea, 1915",         "Aporocera viridipennis",   "species",    "synonym",          "MY_DATA",          "Aporocera",  "sp2",    "sp1",
  "Chalcolampra viridis Blackburn, 1897",     "Chalcolampra viridis",     "species",    "synonym",          "MY_DATA",          "Chalcolampra", "sp3",  "sp1",
  "Aporocera Blackburn",                      "Aporocera",                "genus",      "accepted",         "MY_DATA",          NA,           "g1",     "g1",
  "Aporocera (Aporocera) Blackburn",          "Aporocera",                "subgenus",   "accepted",         "MY_DATA",          "Aporocera",  "sg1",    "sg1",
  "Chrysomelidae Latreille",                  "Chrysomelidae",           "family",     "accepted",         "MY_DATA",          NA,           "f1",     "f1",
  "Xylotoles Pascoe",                          "Xylotoles",                "genus",      "accepted",         "MY_DATA",          NA,           "g2",     "g2",
  "Xylotoles costatus Pascoe, 1859",          "Xylotoles costatus",      "species",    "accepted",         "MY_DATA",          "Xylotoles",  "sp4",    "sp4",
  "Xylotoles costatus mixtus Someone, 1920",  "Xylotoles costatus mixtus", "subspecies", "accepted",       "MY_DATA",          "Xylotoles",  "sp5",    "sp5"
)

check_taxonomic_reference(my_reference)
```

[`check_taxonomic_reference()`](https://traitecoevo.github.io/taxonAlign/reference/check_taxonomic_reference.md)
confirms the table is in the format (it errors, listing every problem,
if it isn’t) – worth running on any reference you’re going to share.

You can pass a table like this straight to the matching functions, but
for repeated use it’s worth preparing it once with
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md),
which the matching functions otherwise do themselves on every call:

``` r

resources <- prepare_taxonomic_resources(my_reference)
names(resources)
#> [1] "species"     "genus"       "subgenus"    "subgenus_v2" "family"
```

[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
splits the combined table into a nested list – one element per taxonomic
rank present (here: `species`, `genus`, `subgenus`, `family`), with
`species` further split into `accepted`/`synonym` sub-tables. This is
the shape every other function in the package works on.

Note that `my_reference` above gives an explicit `"genus"`-rank row for
both `"Aporocera"` and `"Xylotoles"` – but you don’t actually have to.
Naming a genus in the `genus` column of a species row is enough on its
own:
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
automatically adds a genus-rank row for any genus (or any other rank you
record in its own column, e.g. `family`) that’s implied this way but
doesn’t yet have an explicit row of its own, so `"Xylotoles sp. 1"`
would still align to genus rank even if the `"Xylotoles"` row above were
deleted. Synthesised rows get a placeholder ID
(`taxonomic_dataset_taxon_rank_canonical_name`,
e.g. `"MY_DATA_genus_Xylotoles"`) since there’s no natural ID to reuse.

If your table’s columns have other names,
`taxonAlign.dataprep::build_taxonomic_reference()` walks you through
mapping them onto the format (in the style of `traits.build`’s
`metadata_add_traits()`).

### Combining several references

[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
(and the matching functions) also accept a list of tables, combining
them with a priority order. Each match attempt searches all the tables,
and when the same attempt finds the name in more than one, whichever
table is listed *first* wins (within one table, the most reliable status
wins). An earlier attempt in any table still beats a later one: an exact
match in the second table beats a fuzzy match in the first. This is how
you’d combine released lists with your own data:

``` r

# your own list first, then the AFD, then GBIF for anything neither of those has
resources <- prepare_taxonomic_resources(c(
  list(mine = my_reference),
  load_taxonomic_resources(c("NSL_animals", "CatalogueOfLife_AU"))
))
```

## Matching raw names: `align_taxa()`

[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
takes one or more raw taxon names and matches each against `resources`,
trying (in order) exact matches, then progressively more lenient fuzzy
matches, at species level first and then at each higher rank present in
`resources`.

``` r

align_taxa("Aporocera viridipennis", resources)  # exact match, a synonym
#> # A tibble: 1 × 12
#>   original_name          identifier cleaned_name  aligned_name taxonomic_dataset
#>   <chr>                  <chr>      <chr>         <chr>        <chr>            
#> 1 Aporocera viridipennis NA         Aporocera vi… Aporocera v… MY_DATA          
#> # ℹ 7 more variables: taxon_rank <chr>, taxonomic_status <chr>, taxon_ID <chr>,
#> #   accepted_name_usage_ID <chr>, aligned_reason <chr>, alignment_code <chr>,
#> #   chars_changed <int>
align_taxa("Aporocera viridipenis", resources)   # one letter missing -- fuzzy match
#> # A tibble: 1 × 12
#>   original_name         identifier cleaned_name   aligned_name taxonomic_dataset
#>   <chr>                 <chr>      <chr>          <chr>        <chr>            
#> 1 Aporocera viridipenis NA         Aporocera vir… Aporocera v… MY_DATA          
#> # ℹ 7 more variables: taxon_rank <chr>, taxonomic_status <chr>, taxon_ID <chr>,
#> #   accepted_name_usage_ID <chr>, aligned_reason <chr>, alignment_code <chr>,
#> #   chars_changed <int>
align_taxa("Xylotoles costatus mixtus", resources) # a subspecies
#> # A tibble: 1 × 12
#>   original_name           identifier cleaned_name aligned_name taxonomic_dataset
#>   <chr>                   <chr>      <chr>        <chr>        <chr>            
#> 1 Xylotoles costatus mix… NA         Xylotoles c… Xylotoles c… MY_DATA          
#> # ℹ 7 more variables: taxon_rank <chr>, taxonomic_status <chr>, taxon_ID <chr>,
#> #   accepted_name_usage_ID <chr>, aligned_reason <chr>, alignment_code <chr>,
#> #   chars_changed <int>
align_taxa("Chrysomelidae", resources)            # family only
#> # A tibble: 1 × 12
#>   original_name identifier cleaned_name  aligned_name  taxonomic_dataset
#>   <chr>         <chr>      <chr>         <chr>         <chr>            
#> 1 Chrysomelidae NA         Chrysomelidae Chrysomelidae MY_DATA          
#> # ℹ 7 more variables: taxon_rank <chr>, taxonomic_status <chr>, taxon_ID <chr>,
#> #   accepted_name_usage_ID <chr>, aligned_reason <chr>, alignment_code <chr>,
#> #   chars_changed <int>
```

A subgenus can be written into a name or left out; either way matches,
whichever way your reference writes it:

``` r

align_taxa(c("Aporocera t-viride", "Aporocera (Aporocera) t-viride"), resources) |>
  select(original_name, aligned_name, taxon_rank)
#> # A tibble: 2 × 3
#>   original_name                  aligned_name       taxon_rank
#>   <chr>                          <chr>              <chr>     
#> 1 Aporocera t-viride             Aporocera t-viride species   
#> 2 Aporocera (Aporocera) t-viride Aporocera t-viride species
```

A name that can’t be resolved to anything is left `NA`, not an error:

``` r

align_taxa("Completely unrelated nonsense", resources)
#> # A tibble: 1 × 12
#>   original_name           identifier cleaned_name aligned_name taxonomic_dataset
#>   <chr>                   <chr>      <chr>        <chr>        <chr>            
#> 1 Completely unrelated n… NA         Completely … NA           NA               
#> # ℹ 7 more variables: taxon_rank <chr>, taxonomic_status <chr>, taxon_ID <chr>,
#> #   accepted_name_usage_ID <chr>, aligned_reason <chr>, alignment_code <chr>,
#> #   chars_changed <int>
```

### Matching more than one name at once

[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
is vectorised – pass as many names as you like in one call, spanning as
many different ranks as your raw data actually has:

``` r

align_taxa(
  c("Aporocera t-viride", "Aporocera viridipenis", "Xylotoles costatus mixtus", "Chrysomelidae", "Xylotoles sp. 1"),
  resources
) |>
  select(original_name, aligned_name, taxon_rank)
#> # A tibble: 5 × 3
#>   original_name             aligned_name                    taxon_rank
#>   <chr>                     <chr>                           <chr>     
#> 1 Aporocera t-viride        Aporocera t-viride              species   
#> 2 Aporocera viridipenis     Aporocera viridipennis          species   
#> 3 Xylotoles costatus mixtus Xylotoles costatus mixtus       subspecies
#> 4 Chrysomelidae             Chrysomelidae                   family    
#> 5 Xylotoles sp. 1           Xylotoles sp. [Xylotoles sp. 1] genus
```

In practice your names usually live in a column of a data frame, not a
bare vector – just pass that column straight in:

``` r

field_data <- tibble(
  name = c("Aporocera t-viride", "Chalcolampra viridis", "Xylotoles sp. 1", "Totally unknown beetle"),
  site = c("Site A", "Site B", "Site C", "Site B")
)

align_taxa(field_data$name, resources) |>
  select(original_name, aligned_name, taxon_rank, taxonomic_status)
#> # A tibble: 4 × 4
#>   original_name          aligned_name                taxon_rank taxonomic_status
#>   <chr>                  <chr>                       <chr>      <chr>           
#> 1 Aporocera t-viride     Aporocera t-viride          species    accepted        
#> 2 Chalcolampra viridis   Chalcolampra viridis        species    synonym         
#> 3 Xylotoles sp. 1        Xylotoles sp. [Xylotoles s… genus      accepted        
#> 4 Totally unknown beetle NA                          NA         NA
```

Two opt-in parameters handle names that structurally can’t specify a
species at all, resolving them to genus rank instead of leaving them to
(possibly mis-)match a species-level pattern:

``` r

align_taxa("Aporocera x hybridname", resources, hybrids = TRUE)
#> # A tibble: 1 × 12
#>   original_name          identifier cleaned_name  aligned_name taxonomic_dataset
#>   <chr>                  <chr>      <chr>         <chr>        <chr>            
#> 1 Aporocera x hybridname NA         Aporocera x … Aporocera x… MY_DATA          
#> # ℹ 7 more variables: taxon_rank <chr>, taxonomic_status <chr>, taxon_ID <chr>,
#> #   accepted_name_usage_ID <chr>, aligned_reason <chr>, alignment_code <chr>,
#> #   chars_changed <int>
align_taxa("Aporocera aff. viridipennis", resources, intergrades_affinis = TRUE)
#> # A tibble: 1 × 12
#>   original_name           identifier cleaned_name aligned_name taxonomic_dataset
#>   <chr>                   <chr>      <chr>        <chr>        <chr>            
#> 1 Aporocera aff. viridip… NA         Aporocera a… Aporocera s… MY_DATA          
#> # ℹ 7 more variables: taxon_rank <chr>, taxonomic_status <chr>, taxon_ID <chr>,
#> #   accepted_name_usage_ID <chr>, aligned_reason <chr>, alignment_code <chr>,
#> #   chars_changed <int>
```

`hybrids` catches `Genus x species`-style hybrid names;
`intergrades_affinis` catches intergrades (`--`), a collector’s
indecision between two taxa (`/`), and graded/uncertain identifications
(`aff.`/`cf.`). Both default to `FALSE`.

A third opt-in parameter, `consider_english_name_endings`, recognises an
informal vernacular ending (e.g. `"Coccinellid"` for family
Coccinellidae, `"Curculionoid"` for superfamily Curculionoidea) and
tries an exact match on the formal Latin equivalent before falling back
to fuzzy matching – useful for the kind of morphospecies/voucher code
that names a broader group this way rather than a genus:

``` r

align_taxa("Chrysomelid sp. 1", resources, consider_english_name_endings = TRUE) |>
  select(original_name, aligned_name, taxon_rank)
#> # A tibble: 1 × 3
#>   original_name     aligned_name                          taxon_rank
#>   <chr>             <chr>                                 <chr>     
#> 1 Chrysomelid sp. 1 Chrysomelidae sp. [Chrysomelid sp. 1] family
```

For a large list, `progress = TRUE` prints a text progress bar tracking
how many names have been resolved so far.

Every result also includes `chars_changed` – how many characters
differed between the name and whatever it matched: `0` for an exact
match, the actual edit distance for a fuzzy one, `NA` if nothing
matched:

``` r

align_taxa("Aporocera viridipenis", resources) |> # one letter missing
  select(original_name, aligned_name, chars_changed)
#> # A tibble: 1 × 3
#>   original_name         aligned_name           chars_changed
#>   <chr>                 <chr>                          <int>
#> 1 Aporocera viridipenis Aporocera viridipennis             1
```

## Resolving to current names: `update_taxa()`

[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
tells you *what a name matched* –
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
takes that result and resolves it forward to whatever the *current*
accepted name is, following synonym links via `accepted_name_usage_ID`.
This works the same way regardless of rank – a species-level synonym and
a higher-rank one both resolve via the same lookup:

``` r

aligned <- align_taxa(c("Chalcolampra viridis", "Xylotoles sp. 1"), resources)
update_taxa(aligned, resources) |>
  select(original_name, aligned_name, accepted_name, taxonomic_status)
#> # A tibble: 2 × 4
#>   original_name        aligned_name               accepted_name taxonomic_status
#>   <chr>                <chr>                      <chr>         <chr>           
#> 1 Chalcolampra viridis Chalcolampra viridis       Aporocera t-… accepted        
#> 2 Xylotoles sp. 1      Xylotoles sp. [Xylotoles … Xylotoles     accepted
```

`accepted_name` is the current accepted name (`NA` if it couldn’t be
resolved); `suggested_name` falls back to `aligned_name` when there’s no
`accepted_name`, so it’s never `NA` for anything that matched at all.

### A synonym of more than one taxon

Sometimes a name is listed as a synonym of two or more accepted taxa –
for example, when a species has since been split into several. The name
alone can’t say which is meant. Following APCalign’s convention,
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
suggests the most likely one (by the synonyms’ taxonomic status, then a
few tie-breaking rules) and lists the others in brackets, and in
`alternative_possible_names`:

``` r

split_reference <- tibble::tribble(
  ~canonical_name,        ~scientific_name,                   ~taxon_rank, ~taxonomic_status,     ~genus,       ~taxon_ID, ~accepted_name_usage_ID,
  "Newgenus alba",        "Newgenus alba (Smith, 1900)",      "species",   "accepted",            "Newgenus",   "a1",      "a1",
  "Newgenus pallida",     "Newgenus pallida Jones, 1950",     "species",   "accepted",            "Newgenus",   "a2",      "a2",
  "Oldgenus alba",        "Oldgenus alba Smith, 1900",        "species",   "nomenclatural synonym", "Oldgenus", "s1",      "a1",
  "Oldgenus alba",        "Oldgenus alba Smith, 1900",        "species",   "misapplied",          "Oldgenus",   "s2",      "a2"
) |>
  mutate(taxonomic_dataset = "EXAMPLE")

create_taxonomic_update_lookup("Oldgenus alba", prepare_taxonomic_resources(split_reference)) |>
  select(original_name, suggested_name, alternative_possible_names)
#> Summary of 1 names:
#>   -> 1 aligned to a species or infraspecific taxon (1 in EXAMPLE)
#>   -> 0 aligned only to a genus and 0 only to a family
#>   -> 0 could not be aligned
#>   -> 0 aligned names were updated to a different name (e.g. a synonym to its accepted name, or an outdated genus to the current one)
#>   -> 1 names could refer to more than one currently accepted taxon. With `taxonomic_splits = "most_likely_species"`, `suggested_name` gives the most likely species and lists the alternatives in square brackets.
#> # A tibble: 1 × 3
#>   original_name suggested_name                            alternative_possible…¹
#>   <chr>         <chr>                                     <chr>                 
#> 1 Oldgenus alba Newgenus alba [alternative possible name… Newgenus pallida (mis…
#> # ℹ abbreviated name: ¹​alternative_possible_names
```

With `taxonomic_splits = "collapse_to_higher_taxon"`, a name whose
candidates all share a genus is reported at genus rank instead
(`"Newgenus sp. [collapsed names: ...]"`).

## The one-call pipeline: `create_taxonomic_update_lookup()`

Most of the time you want both steps together.
[`create_taxonomic_update_lookup()`](https://traitecoevo.github.io/taxonAlign/reference/create_taxonomic_update_lookup.md)
runs
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
then
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
in one call:

``` r

create_taxonomic_update_lookup(
  c("Aporocera viridipennis", "Aporocera viridipenis", "Chalcolampra viridis", "Xylotoles costatus mixtus", "Chrysomelidae"),
  resources
) |>
  select(original_name, aligned_name, accepted_name, taxonomic_status, update_reason)
#> Summary of 5 names:
#>   -> 4 aligned to a species or infraspecific taxon (4 in MY_DATA)
#>   -> 0 aligned only to a genus and 1 only to a family
#>   -> 0 could not be aligned
#>   -> 3 aligned names were updated to a different name (e.g. a synonym to its accepted name, or an outdated genus to the current one)
#> # A tibble: 5 × 5
#>   original_name        aligned_name accepted_name taxonomic_status update_reason
#>   <chr>                <chr>        <chr>         <chr>            <chr>        
#> 1 Aporocera viridipen… Aporocera v… Aporocera t-… accepted         Updated to t…
#> 2 Aporocera viridipen… Aporocera v… Aporocera t-… accepted         Updated to t…
#> 3 Chalcolampra viridis Chalcolampr… Aporocera t-… accepted         Updated to t…
#> 4 Xylotoles costatus … Xylotoles c… Xylotoles co… accepted         Aligned name…
#> 5 Chrysomelidae        Chrysomelid… Chrysomelidae accepted         Aligned name…
```

## Putting it together: updating a list of names

Here’s the workflow you’d actually run on a real list of raw names –
say, taxon names recorded in a field dataset that need reconciling
against a reference before analysis, spanning several ranks and
including a couple of names nothing will match.

``` r

field_data <- tibble(
  original_name = c(
    "Aporocera viridipennis",   # a synonym
    "Aporocera viridipenis",    # typo
    "Xylotoles costatus mixtus", # a subspecies
    "Chrysomelidae",             # family only
    "Aporocera sp. 1",          # morphospecies code -- genus known, species not
    "Totally unknown beetle"    # won't resolve to anything
  ),
  site = c("Site A", "Site B", "Site A", "Site C", "Site B", "Site B")
)

lookup <- create_taxonomic_update_lookup(field_data$original_name, resources, identifier = field_data$site)
#> Summary of 6 names:
#>   -> 3 aligned to a species or infraspecific taxon (3 in MY_DATA)
#>   -> 1 aligned only to a genus and 1 only to a family
#>   -> 1 could not be aligned
#>   -> 2 aligned names were updated to a different name (e.g. a synonym to its accepted name, or an outdated genus to the current one)
lookup |> select(original_name, identifier, suggested_name, taxonomic_status, update_reason)
#> # A tibble: 6 × 5
#>   original_name         identifier suggested_name taxonomic_status update_reason
#>   <chr>                 <chr>      <chr>          <chr>            <chr>        
#> 1 Aporocera viridipenn… Site A     Aporocera t-v… accepted         Updated to t…
#> 2 Aporocera viridipenis Site B     Aporocera t-v… accepted         Updated to t…
#> 3 Xylotoles costatus m… Site A     Xylotoles cos… accepted         Aligned name…
#> 4 Chrysomelidae         Site C     Chrysomelidae  accepted         Aligned name…
#> 5 Aporocera sp. 1       Site B     Aporocera sp.… accepted         Updated to t…
#> 6 Totally unknown beet… Site B     NA             unknown          NA
```

`identifier` (here, `site`) is threaded through so that a name only ever
resolvable to genus rank (like the morphospecies code above) is
disambiguated per dataset/location in its aligned name, rather than
collapsing two genuinely different unidentified morphospecies from
different sites into one.

Join the lookup back onto your original data by `original_name` to get
an updated name for every row:

``` r

field_data |> left_join(lookup, by = "original_name")
#> # A tibble: 6 × 21
#>   original_name site  aligned_name accepted_name suggested_name genus taxon_rank
#>   <chr>         <chr> <chr>        <chr>         <chr>          <chr> <chr>     
#> 1 Aporocera vi… Site… Aporocera v… Aporocera t-… Aporocera t-v… Apor… species   
#> 2 Aporocera vi… Site… Aporocera v… Aporocera t-… Aporocera t-v… Apor… species   
#> 3 Xylotoles co… Site… Xylotoles c… Xylotoles co… Xylotoles cos… Xylo… subspecies
#> 4 Chrysomelidae Site… Chrysomelid… Chrysomelidae Chrysomelidae  NA    family    
#> 5 Aporocera sp… Site… Aporocera s… Aporocera     Aporocera sp.… NA    genus     
#> 6 Totally unkn… Site… NA           NA            NA             NA    NA        
#> # ℹ 14 more variables: taxonomic_dataset <chr>, taxonomic_status <chr>,
#> #   scientific_name <chr>, aligned_reason <chr>, update_reason <chr>,
#> #   number_of_collapsed_taxa <int>, chars_changed <int>, taxon_ID <chr>,
#> #   taxon_ID_genus <chr>, scientific_name_ID <chr>, family <chr>,
#> #   taxonomic_status_aligned <chr>, alternative_possible_names <chr>,
#> #   identifier <chr>
```

From here, the rows worth a closer look are the ones where
`taxonomic_status` is `"unknown"` (nothing matched at all) or
`suggested_name` is `NA` – everything else resolved to *something*, even
if only at a higher rank. Reviewing exactly those rows (rather than the
whole list) is usually the fastest way to find the handful of names that
need a manual look – a real typo not caught by fuzzy matching, a name
missing from your reference entirely, or a genuinely new/undescribed
taxon.

``` r

lookup |> filter(is.na(suggested_name) | taxonomic_status == "unknown")
#> # A tibble: 1 × 20
#>   original_name       aligned_name accepted_name suggested_name genus taxon_rank
#>   <chr>               <chr>        <chr>         <chr>          <chr> <chr>     
#> 1 Totally unknown be… NA           NA            NA             NA    NA        
#> # ℹ 14 more variables: taxonomic_dataset <chr>, taxonomic_status <chr>,
#> #   scientific_name <chr>, aligned_reason <chr>, update_reason <chr>,
#> #   number_of_collapsed_taxa <int>, chars_changed <int>, taxon_ID <chr>,
#> #   taxon_ID_genus <chr>, scientific_name_ID <chr>, family <chr>,
#> #   taxonomic_status_aligned <chr>, alternative_possible_names <chr>,
#> #   identifier <chr>
```
