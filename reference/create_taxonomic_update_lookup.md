# Align and update a list of taxon names in one call

The one-call convenience pipeline:
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
followed by
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md).
Matches each name in `original_name` against `resources`, then resolves
that match forward to its current accepted name.

## Usage

``` r
create_taxonomic_update_lookup(
  original_name,
  resources = NULL,
  identifier = NA_character_,
  fuzzy_abs_dist = 3,
  fuzzy_rel_dist = 0.2,
  fuzzy_matches = TRUE,
  imprecise_fuzzy_matches = FALSE,
  taxon_ranks_to_check = NULL,
  hybrids = TRUE,
  intergrades_affinis = TRUE,
  consider_english_name_endings = FALSE,
  include_bracketed_info = TRUE,
  progress = FALSE,
  taxonomic_splits = c("most_likely_species", "collapse_to_higher_taxon"),
  full = FALSE,
  quiet = FALSE
)
```

## Arguments

- original_name:

  Character vector of raw taxon names to align and update.

- resources:

  The nested list of reference tibbles produced by
  [`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md),
  or a reference table (or list of them) – see
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md).

- identifier, fuzzy_abs_dist, fuzzy_rel_dist, fuzzy_matches,
  imprecise_fuzzy_matches, taxon_ranks_to_check, hybrids,
  intergrades_affinis, consider_english_name_endings,
  include_bracketed_info, progress:

  Forwarded to
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md);
  see its documentation.

- taxonomic_splits:

  Passed to
  [`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md):
  how to report a name that leads to more than one accepted name
  (`"most_likely_species"`, the default, or
  `"collapse_to_higher_taxon"`).

- full:

  Logical; if `TRUE`, return every intermediate column
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)/[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
  compute. If `FALSE` (the default), return just the key output columns:
  `original_name`, `aligned_name`, `accepted_name`, `suggested_name`,
  `genus`, `family`, `taxon_rank`, `taxonomic_dataset`,
  `taxonomic_status`, `taxonomic_status_aligned`, `aligned_reason`,
  `update_reason` and `chars_changed` (the number of characters that
  differed between the name being matched and the reference name it
  matched – `0` for an exact match, the edit distance for a fuzzy match,
  `NA` when nothing matched).

- quiet:

  Logical; if `FALSE` (the default), ends by printing a summary, as
  APCalign's does: how many distinct names aligned to a species or
  infraspecific taxon (by dataset), only to a genus or a family, or to
  another rank; how many couldn't be aligned; how many were updated to a
  different name; and how many could refer to more than one accepted
  taxon. `TRUE` prints nothing.

## Value

A tibble with one row per element of `original_name`; see
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
for column details.
