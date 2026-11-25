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
  include_bracketed_info = FALSE,
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

  Logical. `FALSE` (the default) leaves a name that is nothing more than
  a genus, family or other higher-rank name (a bare `"Banksia"`, or a
  bare `"Genus (Subgenus)"`) as that name: `"Banksia"`, with no `" sp."`
  added, since the input didn't say `"sp."`. `TRUE` treats it as though
  it had ended in `"sp."`: `"Banksia sp. [<identifier>]"`, the same as
  `"Banksia sp."` gives either way (APCalign gives
  `"Banksia sp. [Banksia; <identifier>]"`). A name with more than the
  higher-rank name (`"Banksia sp. 1"`, `"Banksia aff. ericifolia"`)
  keeps it in brackets either way
  (`"Banksia sp. [Banksia sp. 1; <identifier>]"`).

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

## Several references combined

When `resources` combines several references, each match attempt
searches all of them at once, and the references' order only decides
between them when the same attempt finds the name in more than one: the
first-listed reference's record wins. So a later reference can align a
name an earlier one also has, if it matches the name at an earlier
attempt: an exact match in the second reference beats a fuzzy match in
the first, and an accepted name in the second beats a synonym in the
first.

## Examples

``` r
reference <- data.frame(
  canonical_name = c("Boronia", "Boronia serrulata", "Boronia oldname"),
  scientific_name = c("Boronia Sm.", "Boronia serrulata Sm.", "Boronia oldname Sm."),
  taxon_rank = c("genus", "species", "species"),
  taxonomic_status = c("accepted", "accepted", "synonym"),
  taxonomic_dataset = "MY_LIST", genus = "Boronia",
  taxon_ID = c("1", "2", "3"), accepted_name_usage_ID = c("1", "2", "2")
)
# a misspelling and a synonym
aligned <- align_taxa(c("Boronia serulata", "Boronia oldname"), reference)
aligned[, c("original_name", "aligned_name", "taxonomic_status", "aligned_reason")]
#> # A tibble: 2 × 4
#>   original_name    aligned_name      taxonomic_status aligned_reason            
#>   <chr>            <chr>             <chr>            <chr>                     
#> 1 Boronia serulata Boronia serrulata accepted         Fuzzy match of taxon name…
#> 2 Boronia oldname  Boronia oldname   synonym          Exact match of taxon name…
```
