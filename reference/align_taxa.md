# Align raw taxon names to a prepared taxonomic reference

Attempts to match each name in `original_name` to a name in `resources`
(produced by
[`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)),
trying, in order, exact matches (scientific name with authorship, then
canonical name), then progressively more lenient fuzzy matches, at
species level first and then at each higher taxonomic rank present in
`resources`. See `match_taxa()` for the full sequence of match attempts.

## Usage

``` r
align_taxa(
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
  full = FALSE,
  quiet = FALSE
)
```

## Arguments

- original_name:

  Character vector of raw taxon names to align.

- resources:

  The taxonomic reference to align against: the nested list produced by
  [`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md),
  or a reference table (or a list of them, such as
  [`load_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/load_taxonomic_resources.md)'s
  output), which is run through
  [`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)
  automatically. Preparing it yourself first saves repeating that work
  when aligning several name lists against the same reference.

- identifier:

  A dataset, location or other identifier associated with each name in
  `original_name` – used only to disambiguate `genus sp.`-style aligned
  names (see
  [`prepare_taxonomic_resources()`](https://traitecoevo.github.io/taxonAlign/reference/prepare_taxonomic_resources.md)/`match_taxa()`)
  as belonging to a specific dataset/location. Recycled if length 1;
  otherwise must be the same length as `original_name`. Defaults to
  `NA`.

- fuzzy_abs_dist:

  The number of characters allowed to differ for a fuzzy match.

- fuzzy_rel_dist:

  The proportion of characters allowed to differ for a fuzzy match.

- fuzzy_matches:

  Logical; whether fuzzy matching is attempted at all. Defaults to
  `TRUE`.

- imprecise_fuzzy_matches:

  Logical; reserved for a more lenient fuzzy-matching pass (not yet
  implemented – see `match_taxa()`). Defaults to `FALSE`.

- taxon_ranks_to_check:

  Optional character vector of taxonomic ranks (besides species) to
  attempt higher-rank matches against. Defaults to `NULL`, which uses
  every higher rank present in `resources`.

- hybrids:

  Logical; if `TRUE` (the default, as APCalign always does), a hybrid
  name (`Genus x species`) that isn't itself a listed name is resolved
  to genus rank (`"Genus x [original name]"`) rather than left for later
  match attempts – with `FALSE`, `"Banksia serrata x ericifolia"` aligns
  to *Banksia serrata*. See `?match_taxa`.

- intergrades_affinis:

  Logical; if `TRUE` (the default, as APCalign always does), names
  suggesting an intergrade (`--`), an indecision between taxa (`/`), or
  a graded/"affinis"/"cf." identification are resolved to genus rank the
  same way, unless the whole name is a listed name. See `?match_taxa`.

- consider_english_name_endings:

  Logical; if `TRUE`, before any fuzzy matching, try substituting a
  recognised informal English vernacular name ending (e.g. `"-id"`,
  `"-ine"`, `"-oid"`) for its formal Latin equivalent and attempt an
  exact match on the corrected name. Defaults to `FALSE`. See
  `?match_taxa`.

- include_bracketed_info:

  Logical; `TRUE` (the default) gives every higher-rank-only match
  APCalign's `"<rank name> sp. [<original name>; <identifier>]"` form,
  e.g. `"Banksia sp. [Banksia]"` for a bare `"Banksia"`. `FALSE` drops
  the brackets when the name is nothing more than the matched rank's own
  name (a bare single word, or a bare `"Genus (Subgenus)"`), giving just
  `"Banksia"`; `original_name` keeps the raw input either way, and a
  name with anything more keeps the brackets regardless. See
  `?match_taxa`.

- progress:

  Logical; if `TRUE`, prints a text progress bar tracking what fraction
  of `original_name` has been resolved so far. Useful for large inputs,
  where matching can take a while. Defaults to `FALSE`. See
  `?match_taxa`.

- full:

  Logical; if `TRUE`, return every intermediate column `match_taxa()`
  computes (useful for inspecting *why* a name matched the way it did).
  If `FALSE` (the default), return just the key output columns.

- quiet:

  Accepted for compatibility with APCalign's function of the same name;
  this function prints nothing either way.

## Value

A tibble with one row per element of `original_name` (preserving its
length, order and any duplicates/`NA`s), with columns `original_name`,
`cleaned_name`, `aligned_name`, `taxonomic_dataset`, `taxon_rank`,
`taxonomic_status`, `taxon_ID`, `accepted_name_usage_ID`,
`aligned_reason`, `alignment_code`, `chars_changed` and `identifier`
(or, if `full = TRUE`, every column `match_taxa()` computes along the
way). `taxon_ID`/`accepted_name_usage_ID` identify which row of
`resources` a name matched to, and are what
[`update_taxa()`](https://traitecoevo.github.io/taxonAlign/reference/update_taxa.md)
uses to resolve a matched synonym forward to its current accepted name.
`chars_changed` is the number of characters that differed between the
name being matched and the reference name it matched – `0` for every
exact match, the actual edit distance (Damerau-Levenshtein) for a fuzzy
match, and `NA` when nothing matched at all.
