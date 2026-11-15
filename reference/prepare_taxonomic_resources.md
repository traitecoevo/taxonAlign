# Prepare a combined taxonomic reference table for name matching

Takes one or more taxonomic reference tables – loaded with
[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md),
built yourself, or any mix of these – and turns them into the single
nested `resources` list that
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)/`match_taxa()`
expect: tables are combined if more than one was supplied, and the
result is split by rank (and, for species-level rows, by taxonomic
status).
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md),
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
and
[`create_taxonomic_update_lookup()`](https://traitecoevo.github.io/taxonAlign/reference/create_taxonomic_update_lookup.md)
call this themselves when given a table (or a list of tables) rather
than prepared `resources`; call it yourself to prepare once and reuse.

## Usage

``` r
prepare_taxonomic_resources(
  taxonomic_resources = NULL,
  taxon_ranks_to_check = NULL
)
```

## Arguments

- taxonomic_resources:

  A tibble, a path to a CSV file, or a (optionally named) list of either
  – one element per taxonomic reference table to combine. Each table
  must be in taxonAlign's taxonomic reference format (see
  [`taxonomic_reference_schema()`](https://traitecoevo.github.io/taxonAlign/reference/taxonomic_reference_schema.md)):
  at least the columns `canonical_name`, `scientific_name`,
  `taxon_rank`, `taxonomic_status`, `taxonomic_dataset`, `genus`,
  `taxon_ID` and `accepted_name_usage_ID`, matching
  [APCalign](https://traitecoevo.github.io/APCalign/)'s own naming
  convention (see Details). A row whose `canonical_name` is `NA` has no
  usable name and is dropped, with a warning. `accepted_name_usage_ID`
  must be self-referential (equal to `taxon_ID`) for already-accepted
  rows, not `NA` – this is what lets
  [`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
  resolve a matched name forward to its current accepted name regardless
  of whether it matched an accepted name or a synonym. To map a table
  with other column names onto this format interactively, see
  `taxonAlign.dataprep::build_taxonomic_reference()`.

- taxon_ranks_to_check:

  Optional character vector restricting which taxonomic ranks (besides
  species/infraspecific ranks) are retained in the returned `resources`
  for higher-rank matching (e.g. `c("genus", "family")`). Defaults to
  `NULL`, which keeps every rank present in `taxonomic_resources`.

## Value

A named list of tibbles (and, for `species`, a further named list split
by `taxonomic_status`): one element per taxonomic rank present in
`taxonomic_resources` (after applying `taxon_ranks_to_check`, if
supplied), plus `subgenus_v2` when subgenus-rank rows are present (see
Details).

## Details

Unlike [APCalign](https://traitecoevo.github.io/APCalign/)'s
[`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md),
which only ever assembles the fixed APC/APNI combination, this function
works on whatever combined reference data the user supplies – at
whatever set of taxonomic ranks it happens to contain, not just
genus/species/family.

Column names are normalised on the way in, exactly the way
[`APCalign::load_taxonomic_resources()`](https://traitecoevo.github.io/APCalign/reference/load_taxonomic_resources.html)
normalises APC/APNI's raw Darwin Core column names to its own convention
– e.g. a raw
`canonicalName`/`taxonRank`/`taxonomicStatus`/`scientificName` column is
renamed to
`canonical_name`/`taxon_rank`/`taxonomic_status`/`scientific_name`. This
keeps `canonical_name` the *only* name field taxonAlign ever refers to.

When multiple tables are supplied, whichever is supplied first is
preferred when a name exists in more than one, whatever taxonomic status
each gives it. Within one table, a name listed more than once is matched
to its most reliable status first (accepted, then the various kinds of
synonym, then misapplications, ...).

Two matching conventions for subgenus names are supported side by side:
some input name lists write the subgenus alone (e.g. `"Podosemum"`),
others write the `Genus (Subgenus)` bracketed convention (e.g.
`"Boronia (Podosemum)"`). To support both, when `taxonomic_resources`
contains subgenus-rank rows, `resources$subgenus` holds the plain
subgenus names (used for the first convention) and
`resources$subgenus_v2` additionally holds a `genus_and_subgenus` column
(used for the second).
