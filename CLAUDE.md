# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`taxonAlign` is an R package (currently pre-release, version 0.0.0.9000) with two goals per its
DESCRIPTION: 1) let a user build a personalised taxonomic reference resource by combining multiple
taxonomic references, and 2) fuzzy-match a user's raw taxon name lists against that resource to
maximise alignment coverage. The two goals map to two very differently-matured parts of the codebase
(see Architecture below) — most of the fuzzy-matching engine is ported prototype code, not yet wired
into an exported package API.

## Commands

This is a standard R package (DESCRIPTION/NAMESPACE, `Roxygen: list(markdown = TRUE)`). A `tests/`
directory now exists (testthat 3rd edition, see Testing below), covering
`generate_taxonomic_reference_list.R` only.

```r
devtools::load_all()       # load the package for interactive development
devtools::document()       # regenerate NAMESPACE/man/*.Rd from roxygen comments
devtools::test()           # run the testthat suite
devtools::check()          # full R CMD check
```

Important gotcha: `NAMESPACE` currently contains no exports at all (just the roxygen2 header comment),
even though `generate_taxonomic_reference_list()` is tagged `@export`. Run `devtools::document()`
after editing any roxygen tags to bring `NAMESPACE`/`man/` back in sync before relying on exports.

**Bigger gotcha — `devtools::load_all()`/`devtools::test()`/`devtools::check()` currently fail outright**,
because `R/match_taxa_for_inverts_202500304-use this.R` has top-level executable script code (it reads
`taxon_resources` from a path outside this repo) rather than only function definitions, so sourcing the
`R/` directory errors with `object 'taxon_resources' not found` before anything — including the test
suite below — gets a chance to run. Until that file is wrapped in functions or moved out of `R/`
(e.g. `.Rbuildignore`'d, or relocated under `data-raw/` alongside the vignette it supports), work around
it by temporarily moving the file out of `R/`, running the command, then moving it back — don't leave it
moved without asking, since it's an intentional (if messy) part of the ported prototype.

`DESCRIPTION` Imports (`dplyr`, `purrr`, `rgbif`, `tools`, `utils`) only cover
`generate_taxonomic_reference_list.R`. The other R files call packages that are **not** declared as
dependencies anywhere (`stringr`, `stringdist`, `tidyverse`, `here`, `readr`, `arrow`, and the GitHub
package `APCalign`) — install these manually if you need to run that code:

```r
install.packages(c("stringr", "stringdist", "here", "readr", "arrow", "tidyverse"))
remotes::install_github("traitecoevo/APCalign")
```

### Testing

`tests/testthat/test-generate_taxonomic_reference_list.R` covers `generate_taxonomic_reference_list()`
and its internal helpers (`resolve_gbif_taxon()`, `fetch_gbif_taxon_tree()`, `fetch_gbif_country_keys()`,
`recycle_against_taxon_name()`, `cache_is_fresh()`) end to end, entirely offline: every `rgbif::` call
(`name_backbone`, `name_lookup`, `name_usage`, `occ_search`) is replaced with
`testthat::local_mocked_bindings(..., .package = "rgbif")`, with fixture builders in
`tests/testthat/helper-gbif-fixtures.R`. 42 expectations, all passing as of the last run.

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

### 1. GBIF-backed reference list builder — `R/generate_taxonomic_reference_list.R` (active, exported)

This is the one fully-built, documented, exported piece of the package.
`generate_taxonomic_reference_list(taxon_name, ...)` builds a tibble of taxa sourced from the GBIF
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
  requested root taxon (not per descendant) to keep this cheap, and is cached the same way.
- Final output columns are a fixed, renamed subset of the raw GBIF fields (see the function's
  `@return` doc) with `taxonomic_reference` hardcoded to `"GBIF"` — this file only knows about GBIF;
  combining *multiple* taxonomic references (the package's stated goal #1) is not yet implemented here.
- `gbif_rank_order` (broadest-to-narrowest rank list used for `rank`-filtering) doesn't cover every
  value in GBIF's real `Rank` enum — e.g. `infraspecific_name`, `supragenericname`, `infragenus` are
  missing. A taxon actually carrying one of those ranks would silently drop out of `rank`-filtered
  output rather than being included. Flagged but not fixed (deliberately) — pin down GBIF's exact
  ordinal placement for the missing ranks before adding them, rather than guessing.

### 2. Fuzzy-matching/alignment engine — `R/AusInvertAlign_required_functions.R` and `R/match_taxa_for_inverts_202500304-use this.R` (ported prototype, not exported)

These two files are a wholesale port of an existing workflow (`AusInvertAlign`, from the sibling
`ausinvertraits.addons` project) for aligning raw invertebrate taxon-name lists to an accepted
taxonomic resource, in the style of the `traitecoevo/APCalign` package's `align_taxa()`. Every function
here is tagged `@noRd` (intentionally unexported) and the larger file is full of `XXX-TODO` comments —
treat this as in-progress porting work, not a finished feature. Note the literal filename contains a
space and `-use this` suffix (multiple draft versions existed); quote it in shell commands.

Architecture of the matching engine itself:
- `match_taxa(taxa, resources, ...)` is the core function. `taxa` is a list with two tibbles:
  `tocheck` (rows still needing a match) and `checked` (rows already resolved). The function runs
  through 20+ sequentially-numbered match blocks (`match_01a`, `match_01b`, ...), each testing one
  specific string pattern — exact scientific-name match, exact canonical-name match, fuzzy binomial,
  fuzzy trinomial, genus-only fallback, etc. — against `resources`, matching exact patterns before
  fuzzy ones, and consulting datasets in priority order when a name appears in more than one.
  After each block, `redistribute()` moves newly-resolved rows from `tocheck` into `checked`; the
  function returns early once `tocheck` is empty.
- `resources` is not a single table but a nested list produced by splitting a combined taxonomic
  reference table by `taxon_rank`/`taxonomic_status` (see the vignette's "Split taxonomic resources
  into sublists" step) — `match_taxa()` expects that shape, not a flat data frame.
- `fuzzy_match(txt, accepted_list, max_distance_abs, max_distance_rel, ...)` in
  `AusInvertAlign_required_functions.R` does the actual fuzzy comparison, using
  `stringdist::stringdist(..., method = "dl")` (Damerau-Levenshtein), but only considers a candidate a
  match if the first letter (or, for genus/species epithets, first 1–2 letters) of each word already
  agrees — this is what keeps fuzzy matching from cross-matching unrelated taxa. `extract_genus()`
  handles the `x Genus` hybrid-naming convention.
- `match_taxa()` calls several helpers (`standardise_names()`, `strip_names()`, `strip_names_extra()`,
  `standardise_taxon_rank()`) that are **not defined in this package** — they come from `APCalign`
  (loaded via `library(APCalign)` in the vignette/prototype file). Anything that touches `match_taxa()`
  needs `APCalign` installed and loaded; reconciling this dependency (vendoring, importing, or
  reimplementing) is unresolved work.

### Vignette and data tying the two together

`vignettes/reproduce-EH-workflow.Rmd` reproduces the original AusInvertAlign workflow end-to-end:
loads a taxon reference CSV and an "answer key" (`aligned_names.csv`) from the sibling
`../ausinvertraits.addons` checkout, builds the `resources` list, runs `match_taxa()`, and diffs the
result against the known-correct AusInvertTraits alignment to check the port is faithful. It is **not
self-contained** — it reads paths outside this repo and will not knit standalone. `data/aligned_names_b.rds`
is a saved output of that vignette run, kept for comparison. `data-raw/data-raw.R` is a similar
external-path stub for generating package data, not a working reproducible data-raw script.
