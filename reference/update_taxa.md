# Resolve aligned names forward to their current accepted name

Takes the output of
[`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
and, for every row that matched something in `resources` (whether an
accepted name or a synonym), looks up the *current* record for that
match via `accepted_name_usage_ID` and reports its accepted name (when
it resolves to one).

## Usage

``` r
update_taxa(
  aligned_data,
  resources = NULL,
  taxonomic_splits = c("most_likely_species", "collapse_to_higher_taxon"),
  quiet = FALSE
)
```

## Arguments

- aligned_data:

  A tibble in the shape
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
  returns – in particular, it must have `aligned_name`,
  `taxonomic_status`, `taxon_rank`, `taxonomic_dataset`, `taxon_ID` and
  `accepted_name_usage_ID` columns (both
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)'s
  default, `full = FALSE`, output and its `full = TRUE` output include
  these).

- resources:

  The nested list of reference tibbles produced by
  [`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
  (the same one passed to
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)),
  or a reference table (or list of them) – see
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md).

- taxonomic_splits:

  How to report a name that leads to more than one accepted name:
  `"most_likely_species"` (the default) suggests one and lists the
  others in brackets; `"collapse_to_higher_taxon"` collapses it to genus
  when all candidates share one. See Details.

- quiet:

  Accepted for compatibility with APCalign's function of the same name;
  this function prints nothing either way.

## Value

`aligned_data` with `taxon_rank`/`genus`/`family`/`taxonomic_dataset`
refreshed to whatever the current record has (a synonym's may be
outdated), the pre-update `taxonomic_status` renamed to
`taxonomic_status_aligned`, and new columns `accepted_name` (the current
accepted name, when the match resolves to one, otherwise `NA`),
`suggested_name` (`accepted_name` if available, otherwise falls back to
`aligned_name`), `taxonomic_status` (the *current* record's status) and
`update_reason` (a short explanation, mirroring `aligned_reason`'s
style), and `alternative_possible_names` (the other candidates for a
name that leads to more than one accepted name, otherwise `NA`).

It also has every column APCalign's `update_taxonomy()` returns, meaning
the same thing, all describing the taxon `suggested_name` names (its
accepted record, or for a split collapsed to genus, that genus's):

- `taxon_ID`: that accepted record's ID (`NA` when the name doesn't
  resolve to an accepted name). The ID of the record the name *matched*
  (a synonym's own ID, say), which
  [`align_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/align_taxa.md)
  returns as `taxon_ID`, is kept as `aligned_taxon_ID`.

- `taxon_ID_genus`: the ID of its genus's accepted record.

- `scientific_name` and `scientific_name_ID`: its name with authorship,
  and the reference's `scientific_name_ID` for it (e.g. an IPNI LSID for
  the WCVP; `NA` if the reference has none). For a name that matched but
  doesn't resolve to an accepted name (an unplaced name, say), those of
  the matched record.

- `subclass`, `taxon_distribution`: the reference's own columns of those
  names, `NA` if it has none.

- `canonical_name`: the same as `suggested_name`, as in APCalign.

- `row_number`: the row's position in `aligned_data`.

- `number_of_collapsed_taxa`: for a name leading to more than one
  accepted name, 1 when one is suggested, or the number of candidates
  when they're collapsed to genus; `NA` otherwise.

## Details

Unlike [APCalign](https://traitecoevo.github.io/APCalign/)'s
`update_taxonomy()` – five separate functions, each hand-written for one
specific rank/dataset combination (`update_taxonomy_APC_genus`,
`update_taxonomy_APC_family`, ...) – this is a **single, rank-agnostic**
lookup: every rank present in `resources` is resolved the same way, by
matching each row's `accepted_name_usage_ID` against a `taxon_ID` in a
table combining every rank/status sublist in `resources`. A row that's
already accepted resolves to itself (its own `accepted_name_usage_ID` is
self-referential, per
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)'s
requirements); a synonym resolves to whatever its
`accepted_name_usage_ID` points to.

**A synonym that leads to more than one accepted taxon** (a species or
infraspecific name listed as a synonym of two or more different accepted
taxa – a split, or a pro parte synonym) follows APCalign's
`taxonomic_splits` convention. One accepted name is chosen – by
taxonomic status precedence, then (for a tie) an accepted name sharing
the name's epithet, then one of the same rank, then one published no
later than the name itself, then the oldest, then the order `resources`
lists them in – and the others are listed with their status, both in
`suggested_name`
(`"X [alternative possible names: Y (synonym) | Z (misapplied)]"`) and
in a separate `alternative_possible_names` column. With
`taxonomic_splits = "collapse_to_higher_taxon"`, a name whose candidates
all share one genus is collapsed to that genus instead
(`"Genus sp. [collapsed names: ...]"`, `taxon_rank = "genus"`,
`accepted_name = NA`). Only a match to a synonym record is treated this
way: a match to an accepted name, or to a name given with its authorship
(which identifies one record, e.g. one of two homonyms), is not.

One thing this deliberately does **not** do, relative to APCalign's
`update_taxonomy()`:

- **No genus-substring surgery.** APCalign's
  `update_taxonomy_APC_genus()` reconstructs a species' suggested name
  by splicing just the updated genus portion into the aligned name, when
  only the genus (not the species) has changed. That's a nice refinement
  but doesn't obviously generalize across arbitrary ranks the way the
  rest of this does, so it's omitted here.
