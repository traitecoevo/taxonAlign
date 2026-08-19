# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`taxonAlign` is an R package (currently pre-release, version 0.0.0.9000) with two goals per its
DESCRIPTION: 1) let a user build a personalised taxonomic reference resource by combining multiple
taxonomic references, and 2) fuzzy-match a user's raw taxon name lists against that resource to
maximise alignment coverage. The two goals map to two parts of the codebase (see Architecture below).

The long-term shape mirrors [APCalign](https://traitecoevo.github.io/APCalign/)'s four core
functions: `match_taxa` (internal matching engine) → `align_taxa` (exported orchestrator) →
`update_taxa` → `create_taxonomic_update_lookup` (exported, full pipeline) — with three deliberate
differences: (1) taxonomic resources are supplied by the user (their own table, or one built with
`generate_GBIF_taxonomic_reference_list()`), not a fixed APC/APNI download; (2) the APC-specific "splits"
disambiguation logic in APCalign's `update_taxonomy` won't carry over to taxonAlign's `update_taxa`;
(3) matching/aligning supports *all* taxonomic ranks present in the user's resources, not just
genus/species/family. All four core functions now exist and are tested (see Architecture #2):
`prepare_taxonomic_resources()`, `align_taxa()`, `update_taxa()` and `create_taxonomic_update_lookup()`
are exported; `match_taxa()` stays `@noRd`, matching how APCalign itself keeps its own internal
`match_taxa()` unexported. `prepare_taxonomic_resources()` also has an interactive on-ramp
(`interactive = TRUE`) for a user's own, differently-shaped reference table(s) — see Architecture #2.
Hybrid/graded-name matching is not yet started (tracked as issue #9).

## Commands

This is a standard R package (DESCRIPTION/NAMESPACE, `Roxygen: list(markdown = TRUE)`). A `tests/`
directory now exists (testthat 3rd edition, see Testing below), covering
`generate_GBIF_taxonomic_reference_list.R` and the whole matching/alignment engine (`prepare_taxonomic_resources()`,
`align_taxa()`, `match_taxa()`, `update_taxa()`, `create_taxonomic_update_lookup()`, and the vendored
helpers in `match_taxa_helpers.R`).

```r
devtools::load_all()       # load the package for interactive development
devtools::document()       # regenerate NAMESPACE/man/*.Rd from roxygen comments
devtools::test()           # run the testthat suite
devtools::check()          # full R CMD check
```

Gotcha (resolved): `devtools::load_all()`/`devtools::test()`/`devtools::check()` used to fail outright
because `R/match_taxa_for_inverts_202500304-use this.R` had top-level executable script code (it read
`taxon_resources` from a path outside this repo) rather than only function definitions, so sourcing the
`R/` directory errored with `object 'taxon_resources' not found` before anything got a chance to run.
Its logic has since been ported into real functions (see Architecture #2 below: `align_taxa()`,
`match_taxa()`, `prepare_taxonomic_resources()`), and the original file has now been moved to
`ignore/match_taxa_for_inverts_202500304-use this.R` (excluded from the build via `.Rbuildignore`,
since its non-portable filename otherwise trips a `checking for portable file names` `R CMD check`
WARNING) — the "temporarily move the file out and back" workaround this used to require is no longer
needed.

`DESCRIPTION` Imports now cover `APCalign`, `dplyr`, `purrr`, `readr`, `rgbif`, `rlang`, `stringdist`,
`stringr`, `tools`, `utils` (with `Remotes: traitecoevo/APCalign` since APCalign isn't on CRAN). The
vignette (only) additionally needs packages that are **not** declared as dependencies anywhere
(`tidyverse`, `here`, `arrow`) — install these manually if you need to run it:

```r
install.packages(c("here", "arrow", "tidyverse"))
```

### Testing

`tests/testthat/test-generate_GBIF_taxonomic_reference_list.R` covers `generate_GBIF_taxonomic_reference_list()`
and its internal helpers (`resolve_gbif_taxon()`, `fetch_gbif_taxon_tree()`, `fetch_gbif_country_keys()`,
`recycle_against_taxon_name()`, `cache_is_fresh()`) end to end, entirely offline: every `rgbif::` call
(`name_backbone`, `name_lookup`, `name_usage`, `occ_search`) is replaced with
`testthat::local_mocked_bindings(..., .package = "rgbif")`, with fixture builders in
`tests/testthat/helper-gbif-fixtures.R`.

`tests/testthat/test-prepare_taxonomic_resources.R`, `test-prepare_taxonomic_resources_interactive.R`,
`test-align_taxa.R`, `test-update_taxa.R`, `test-create_taxonomic_update_lookup.R` and
`test-match_taxa_helpers.R` cover the matching/alignment engine end to end against a small hand-built
combined reference table (`sample_taxon_resources()` in `tests/testthat/helper-align-taxa-fixtures.R`)
spanning species (accepted/synonym), genus (accepted/synonym), family, order (accepted/synonym — a
*second* higher rank with an outdated name, proving `update_taxa()`'s lookup isn't secretly
species/genus-specific), an extra non-hardcoded rank ("tribe"), and a subgenus — no network, no
`APCalign`-package-data download (only its pure string helpers,
`standardise_names()`/`strip_names()`/`strip_names_extra()`/`standardise_taxon_rank()`, are called,
which are safe to call directly offline). `test-prepare_taxonomic_resources_interactive.R` covers
`prepare_taxonomic_resources(interactive = TRUE)` by supplying `user_responses` throughout, exactly
the way `traits.build` tests its own `metadata_add_traits()`/etc. — never a real interactive session
(see Architecture #2 below). 178 expectations across all test files, all passing as of the last run.
(See Architecture #2 below for a fuzzy-matching gotcha this fixture data has to dodge.)

Gotcha if you add more end-to-end tests: don't wrap a block of `local_mocked_bindings()` calls in a
plain helper function and call that helper from inside `test_that()` without forwarding `.env` — the
mock's lifetime is tied to `local_mocked_bindings()`'s *own calling frame*, so it gets undone the moment
that helper function returns, before the test body runs (this silently falls through to real network
calls rather than erroring). Give the helper a `.env = parent.frame()` argument and pass it through, as
`local_mock_gbif_end_to_end()` in the test file does.

README.md is generated from README.qmd — re-render with Quarto after editing it:
```
quarto render README.qmd
```

## Architecture

### 1. GBIF-backed reference list builder — `R/generate_GBIF_taxonomic_reference_list.R` (active, exported)

This is the one fully-built, documented, exported piece of the package.
`generate_GBIF_taxonomic_reference_list(taxon_name, ...)` builds a tibble of taxa sourced from the GBIF
backbone taxonomy (`gbif_backbone_dataset_key`), optionally filtered to a country's occurrence records
and/or a minimum taxonomic rank (`gbif_rank_order` defines the "this rank and below" ordering).

Key design points worth knowing before touching this file:
- **Name resolution**: `resolve_gbif_taxon()` calls `rgbif::name_backbone()` once per input name,
  follows synonym links to the accepted usage key, and deliberately errors (rather than silently
  fetching a huge clade) when GBIF returns a `"HIGHERRANK"` match — this happens when `taxon_name` is
  an unresolved homonym (e.g. a genus name shared by a plant and an unrelated animal) and GBIF backs
  off to their common ancestor.
- **Bulk fetch + disk cache**: `fetch_gbif_taxon_tree()` pages through `rgbif::name_lookup()` (1000
  rows/page) instead of one API call per taxon, and caches the combined result per root GBIF key under
  `cache_dir` (default: `tools::R_user_dir("taxonAlign", "cache")`). Cache freshness is time-based
  (`cache_is_fresh()`, `max_cache_age_days`); `refresh_cache = TRUE` forces a re-download. A second,
  independent size guard (`max_taxa`, default 50000; override with `force_large_fetch = TRUE`) protects
  against a homonym resolving broader than intended and triggering a very large/slow first fetch.
- **Country filtering**: `fetch_gbif_country_keys()` does one `rgbif::occ_search()` facet query per
  requested root taxon (not per descendant) to keep this cheap, and is cached the same way. `country`
  is validated as a 2-letter ISO 3166-1 alpha-2 code (regex `^[A-Za-z]{2}$`) up front -- a country
  *name* like `"Australia"` used to pass straight through to `rgbif::occ_search()`, which doesn't
  recognise it, silently returning a 0×0 facet result rather than erroring; accessing that result's
  `$name` then triggered an "Unknown or uninitialised column" warning and a silently-empty reference
  list rather than a clear error. `occ$facets$taxonKey$name` is also now guarded with
  `"name" %in% names(...)` rather than just `!is.null(...)`, since an empty facet result is *not*
  `NULL` (it's a valid 0-row/0-column tibble).
- Final output columns are a fixed, renamed subset of the raw GBIF fields (see the function's
  `@return` doc), named to match [APCalign](https://traitecoevo.github.io/APCalign/)'s taxonomic
  resource tables wherever an equivalent concept exists there (`taxon_ID`, `accepted_name_usage_ID`,
  `scientific_name`, `scientific_name_authorship`, `canonical_name`, `taxon_rank`, `taxonomic_status`,
  `taxonomic_dataset`) so a GBIF-derived reference list can eventually sit alongside an APC/APNI one —
  with `taxonomic_dataset` hardcoded to `"GBIF"`. `accepted_name_usage_ID` is filled in even for
  already-accepted rows (self-referential, pointing at their own `taxon_ID`), matching the convention
  used in real APC downloads, rather than left `NA` the way GBIF's own `acceptedKey` field is. This
  file only knows about GBIF; combining *multiple* taxonomic references (the package's stated goal #1)
  is not yet implemented here.
- `gbif_rank_order` (broadest-to-narrowest rank list used for `rank`-filtering) doesn't cover every
  value in GBIF's real `Rank` enum — e.g. `infraspecific_name`, `supragenericname`, `infragenus` are
  missing. A taxon actually carrying one of those ranks would silently drop out of `rank`-filtered
  output rather than being included. Flagged but not fixed (deliberately) — pin down GBIF's exact
  ordinal placement for the missing ranks before adding them, rather than guessing.

### 2. Fuzzy-matching/alignment engine — `R/prepare_taxonomic_resources.R`, `R/prepare_taxonomic_resources_interactive.R`, `R/align_taxa.R`, `R/match_taxa.R`, `R/update_taxa.R`, `R/create_taxonomic_update_lookup.R`, `R/match_taxa_helpers.R` (active; everything but `match_taxa()` and the helpers is exported)

This is a cleaned-up port of an existing workflow (`AusInvertAlign`, from the sibling
`ausinvertraits.addons` project) for aligning raw taxon-name lists to an accepted taxonomic resource,
structured the way `traitecoevo/APCalign`'s exported `align_taxa()` wraps its own internal
`match_taxa()`. The original, still-unwrapped ported script this was extracted from now lives at
`ignore/match_taxa_for_inverts_202500304-use this.R` (see the "Gotcha (resolved)" note above) — kept
for reference, not a redundant duplicate to reconcile. Note its literal filename contains a space and
`-use this` suffix (multiple draft versions existed); quote it in shell commands.

Call graph, mirroring APCalign's `align_taxa()` → `update_taxonomy()` → `create_taxonomic_update_lookup()`:

```
create_taxonomic_update_lookup(original_name, resources, ...)   # exported, one-call convenience
  -> align_taxa(original_name, resources, ..., full = TRUE)        # exported
       -> match_taxa(taxa, resources, ...)                          # @noRd, the 20+-block engine
       -> flattens taxa$checked + taxa$tocheck into one tibble, left-joined back onto the input vector
  -> update_taxa(aligned_data, resources)                          # exported
       -> resolves a matched (possibly synonym) name forward to its current accepted name
```

`align_taxa()`/`update_taxa()` are also both usable standalone (you don't have to go through
`create_taxonomic_update_lookup()`). `resources` is built ahead of time by
`prepare_taxonomic_resources(taxon_resources, ...)` (exported), which itself now has an interactive
on-ramp for a user's own raw reference table(s) — see the `interactive`/`user_responses` bullet below.

Architecture of the matching engine itself:
- `match_taxa(taxa, resources, ...)` (`R/match_taxa.R`) is the core function. `taxa` is a list with two
  tibbles: `tocheck` (rows still needing a match) and `checked` (rows already resolved). The function
  runs through 20+ sequentially-numbered match blocks (`match_01a`, `match_01b`, ...), each testing one
  specific string pattern — exact scientific-name match, exact canonical-name match, fuzzy binomial,
  fuzzy trinomial, genus-only fallback, etc. — against `resources`, matching exact patterns before
  fuzzy ones, and consulting datasets in priority order when a name appears in more than one.
  After each block, `redistribute()` moves newly-resolved rows from `tocheck` into `checked`; the
  function returns early once `tocheck` is empty.
- `resources` is not a single table but a nested list, produced by `prepare_taxonomic_resources()`,
  split from a combined taxonomic reference table by `taxon_rank`/`taxonomic_status`. Unlike APCalign
  (which only ever splits into genus/species/family), **every** taxonomic rank present in the input
  table gets its own sublist — `match_taxa()`'s `taxon_ranks_to_check` argument defaults to `NULL`,
  which derives the set of higher ranks to check from `names(resources)` itself (minus
  `"species"`/`"subgenus_v2"`), so this generalizes to whatever ranks the user's combined reference
  happens to contain, not a hardcoded invertebrate-specific list.
- **Subgenus gets two parallel matching conventions**, both preserved deliberately:
  `resources$subgenus` (plain subgenus name alone, e.g. `"Podosemum"`, matched via the generic
  `taxon_ranks_to_check` loop like any other higher rank) and `resources$subgenus_v2` (a
  `genus_and_subgenus` column, e.g. `"Boronia (Podosemum)"`, matched via its own dedicated
  match_02a/match_12a blocks) — because different input name lists write subgenus either way. Don't
  collapse these into a single representation.
- `fuzzy_match(txt, accepted_list, max_distance_abs, max_distance_rel, ...)` in
  `match_taxa_helpers.R` does the actual fuzzy comparison, using
  `stringdist::stringdist(..., method = "dl")` (Damerau-Levenshtein), but only considers a candidate a
  match if the first letter (or, for genus/species epithets, first 1–2 letters) of each word already
  agrees — this is what keeps fuzzy matching from cross-matching unrelated taxa (see the "Boronieae"
  vs. "Boronia" note below). `extract_genus()` handles the `x Genus` hybrid-naming convention.
- `match_taxa()`/`prepare_taxonomic_resources()` call `APCalign::standardise_names()`,
  `APCalign::strip_names()`, `APCalign::strip_names_extra()`, `APCalign::standardise_taxon_rank()` —
  all exported by APCalign, now a formal `Imports`/`Remotes` dependency (previously unresolved).
  `fuzzy_match()`, `redistribute()` and `extract_genus()` in `match_taxa_helpers.R` are, by contrast,
  **intentionally vendored** local copies (with a comment explaining why) rather than imported, because
  APCalign keeps its own equivalents (`APCalign:::fuzzy_match` etc.) internal/unexported.
- Watch out when picking rank/taxon names for test fixtures: fuzzy genus/higher-rank matching
  (`max_distance_abs = 2`, `max_distance_rel = 0.35`) is lenient enough that unrelated-looking names
  can still collide (e.g. `"Boronieae"` fuzzy-matches `"Boronia"` at distance 2) — pick fixture ranks
  whose names don't share a first letter with anything else in the same fixture, or the fuzzy pass can
  resolve a row before the intended, more specific block gets a chance to.
- Every match block also captures the matched resource row's `taxon_ID`/`accepted_name_usage_ID` (not
  just `aligned_name`/`taxon_rank`/`taxonomic_status`/`taxonomic_dataset`) -- this is what
  `update_taxa()` needs to look a match back up in `resources`, and is threaded all the way from
  `match_taxa()` through `align_taxa()`'s default output (not just its `full = TRUE` one).
  `prepare_taxonomic_resources()` normalises both to character regardless of the source column's type
  (`generate_GBIF_taxonomic_reference_list()` gives integer IDs; real APC/AFD data gives URI/UUID strings).
- `update_taxa(aligned_data, resources)` (`R/update_taxa.R`) is a **single, rank-agnostic lookup** --
  not five rank/dataset-specific functions like APCalign's `update_taxonomy_APC_genus()` /
  `update_taxonomy_APC_family()` / `update_taxonomy_APC_species_and_infraspecific_taxa()` / etc. It
  flattens every rank/status sublist in `resources` into one combined table keyed by `taxon_ID`, then
  resolves each row by looking up its `accepted_name_usage_ID` against that table -- the exact same
  code path for a species-rank synonym, a genus-rank synonym, or any other rank. Deliberately doesn't
  carry over APCalign's `taxonomic_splits` disambiguation (APC-specific split history an arbitrary
  reference can't be expected to document) or its genus-substring-splicing trick for reconstructing a
  suggested name when only the genus changed (doesn't obviously generalize across ranks).
- **Two real bugs found by testing against real, messy data** (not just the hand-built fixture) that
  are worth knowing about if you touch this code again:
  - `fuzzy_match()` (`match_taxa_helpers.R`) used to crash with "missing value where TRUE/FALSE
    needed" whenever a reference list's `accepted_list` argument contained an `NA` (real GBIF data with
    doubtful/unranked records can have this) -- `min()` over a distance vector containing `NA` returns
    `NA`, which then blew up the tolerance check. Fixed by stripping `NA`s from `accepted_list` (and
    short-circuiting on an `NA` query string) at the top of the function.
  - A subtler one, in `match_taxa.R`'s `i <- some_value %in% resources$...$column` pattern (used
    throughout, especially the fuzzy blocks): **`NA %in% x` is `TRUE` in R whenever `x` itself contains
    an `NA`** -- so a `fuzzy_match()` call that correctly found no match (returning `NA`) would
    spuriously "match" whichever resource row happened to have an `NA` `canonical_name`, rather than
    correctly matching nothing. Real GBIF data occasionally has an `NA` `canonicalName`. Fixed at the
    source rather than at each call site: `prepare_taxonomic_resources()` now drops (with a warning)
    any row whose `canonical_name` is `NA` -- such a row could never be usefully matched against
    anyway, and leaving it in is a landmine for this exact `%in%` gotcha in every match block, not just
    the fuzzy ones.
- `resources` has no default on `align_taxa()`/`update_taxa()`/`create_taxonomic_update_lookup()`,
  and a common real mistake is passing the *raw* output of `generate_GBIF_taxonomic_reference_list()`
  (a flat tibble) straight in, instead of first running it through `prepare_taxonomic_resources()`
  (which builds the nested-by-rank list these functions actually expect). Left unchecked, that surfaced
  as confusing internal errors deep inside `match_taxa()` (`Can't recycle input of size N to size M`,
  "unknown or uninitialised column" warnings) rather than a clear message. All three now default
  `resources = NULL` and error with a pointer to `prepare_taxonomic_resources()` if it's missing
  entirely, then call `ensure_prepared_resources()` (`match_taxa_helpers.R`): if `resources` is a plain
  data frame, it's run through `prepare_taxonomic_resources()` automatically (non-interactively) rather
  than erroring -- a single reference table that's already fully formatted (e.g.
  `generate_GBIF_taxonomic_reference_list()`'s own output) shouldn't require the extra call; a table
  that still needs interactive column mapping surfaces the same `prepare_taxonomic_resources()`
  "missing required column(s)... pass `interactive = TRUE`" error, just one call deep. If `resources`
  is already a list, `ensure_prepared_resources()` only validates its shape (`validate_resources_shape()`,
  checking for a `resources$species$accepted` element) rather than re-preparing it -- re-splitting an
  already-split structure would be wrong. `create_taxonomic_update_lookup()` calls
  `ensure_prepared_resources()` itself, once, before calling `align_taxa()`/`update_taxa()` in turn, so
  a flat `resources` table it's given isn't prepared twice.
- `prepare_taxonomic_resources()` renames raw column names on the way in using APCalign's own
  `column_rename` vector verbatim (`APCalign::load_taxonomic_resources()`'s, copied as-is) --
  `canonicalName`/`taxonRank`/`taxonomicStatus`/`scientificName`/etc. get renamed to
  `canonical_name`/`taxon_rank`/`taxonomic_status`/`scientific_name`/etc. automatically. There's
  deliberately **no `taxon_name` column or fallback concept at all** -- an earlier version of this
  function had `canonical_name` optionally fall back to a separate `taxon_name` column (inherited from
  the ported `AusInvertAlign` prototype, whose AFD-derived CSV happens to have both), but that
  introduced exactly the column-naming ambiguity APCalign avoids by only ever using `canonical_name`.
  `canonical_name` is now a straightforwardly required column; a row where it's `NA` is dropped (see
  the bug note above), not silently patched from a second name field.
- `prepare_taxonomic_resources()`'s `interactive`/`user_responses` arguments (`R/prepare_taxonomic_resources_interactive.R`)
  are the "let a user bring their own reference table" on-ramp sketched in comments in
  `R/match_taxa_for_inverts_202500304-use this.R` — modelled directly on `traits.build`'s
  `metadata_add_traits()`/`metadata_add_locations()`/`metadata_add_contexts()`/`metadata_create_template()`
  (`traits.build`'s `R/setup.R`): `utils::menu()` for single-choice picks, a `readline()`-driven
  validated loop for ordered selections, and — critically for testing — every prompt has a
  `user_response`/`user_responses` escape hatch that substitutes a supplied value, so tests never open
  a real interactive session (see `test-prepare_taxonomic_resources_interactive.R`, all of which pass
  `user_responses` rather than prompting). `taxon_resources` now also accepts a file path or a
  (optionally named) list of tibbles/paths, one per source dataset to combine; when more than one is
  supplied, priority is expressed purely by row order in the bind_rows()'d result (since
  `match_taxa()`'s exact blocks use first-hit `match()` semantics) — `interactive = TRUE` prompts once
  for that order (or consults `user_responses$priority_order`), `interactive = FALSE` just uses
  supply-order with no prompt. A table missing no required columns is never interrupted, even in
  `interactive = TRUE` mode — only genuinely-missing fields get prompted for, so
  `generate_GBIF_taxonomic_reference_list()`'s output (already complete) sails through untouched. When a
  table *is* missing something, it's first asked (once, `prompt_already_aligned()`) whether it's
  already fully aligned regardless (e.g. from an earlier `prepare_taxonomic_resources()`/
  `generate_GBIF_taxonomic_reference_list()` call, just under column names `column_rename` didn't
  recognise) — note this can only ever end in either a clear, specific error naming what's still
  missing (since reaching this prompt at all means something genuinely is absent by name) or "No",
  proceeding into the normal per-field prompts; there's no silent-success branch, by construction, and
  that's intentional — it exists to catch a wrong assumption early with a precise message, not as a
  bypass.
- Once every initially-supplied table is resolved, `interactive = TRUE` also loops asking "Do you have
  any additional taxonomic reference(s) to include?" (`prompt_yes_no()`) — repeating for as many as the
  user has — before the priority-order prompt. This is asked *unconditionally* (regardless of whether
  the initial table(s) needed any column mapping at all), unlike `prompt_already_aligned()` above,
  because its purpose is different: letting someone start with a single file (`taxon_resources`) and
  grow it into a combined set interactively, rather than requiring the whole set assembled up front.
  `user_responses$additional_tables` (an optionally-named list of further tables/paths) bypasses the
  real loop for tests/scripting — each entry still goes through the exact same `resolve_taxon_resources_table()`
  path as any other table, consulting `user_responses[[its own label]]` for its own missing fields.

Not yet implemented (deliberately deferred, tracked as GitHub issues):
- Hybrid names, graded/"affinis" names (`aff.`/`cf.`), and indecision/intergrade names — real
  APCalign's internal `match_taxa()` has dedicated match blocks for all of these
  (`match_03*`/`match_04*`/`match_06*`/`match_08*`); taxonAlign's `match_taxa()` has none of them yet.
- A test suite asserting that, given the *same* APC data source, taxonAlign's `align_taxa()` produces
  the same output as APCalign's — meaningful only once the edge cases directly above are implemented
  (otherwise a mismatch would just restate "hybrids aren't handled yet", not surface a real bug).

### Vignette and data tying the two together

`vignettes/reproduce-EH-workflow.Rmd` reproduces the original AusInvertAlign workflow end-to-end:
loads a taxon reference CSV and an "answer key" (`aligned_names.csv`) from the sibling
`../ausinvertraits.addons` checkout, calls `prepare_taxonomic_resources()`/`align_taxa()`, and diffs
the result against the known-correct AusInvertTraits alignment to check the port is faithful. It is
**not self-contained** — it reads paths outside this repo and will not knit standalone.
`data/aligned_names_b.rds` is a saved output of that vignette run, kept for comparison.
`data-raw/data-raw.R` is a similar external-path stub for generating package data, not a working
reproducible data-raw script.
