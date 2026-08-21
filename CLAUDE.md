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
Hybrid/graded-name matching is now implemented, opt-in via `hybrids`/`intergrades_affinis` (issue #9,
see Architecture #2). `load_taxonomic_resources(taxonomic_dataset = ...)` (issue #6, see Architecture
#3) fetches/reshapes known reference sources -- the Australian Faunal Directory (`"AFD"`) and a thin
`APCalign::load_taxonomic_resources()` wrapper (`"APC"`) so far -- into the flat schema
`prepare_taxonomic_resources()` expects, complementing it the same way
`generate_GBIF_taxonomic_reference_list()` does for GBIF.

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
`taxonomic_resources` from a path outside this repo) rather than only function definitions, so sourcing the
`R/` directory errored with `object 'taxonomic_resources' not found` before anything got a chance to run.
Its logic has since been ported into real functions (see Architecture #2 below: `align_taxa()`,
`match_taxa()`, `prepare_taxonomic_resources()`), and the original file has now been moved to
`ignore/match_taxa_for_inverts_202500304-use this.R` (excluded from the build via `.Rbuildignore`,
since its non-portable filename otherwise trips a `checking for portable file names` `R CMD check`
WARNING) — the "temporarily move the file out and back" workaround this used to require is no longer
needed.

`DESCRIPTION` Imports now cover `APCalign`, `dplyr`, `parallel`, `purrr`, `readr`, `rgbif`, `rlang`,
`stringdist`, `stringr`, `tools`, `utils` (with `Remotes: traitecoevo/APCalign` since APCalign isn't on
CRAN; `parallel` ships with base R but is still declared since it's called via `::`, per the concurrent
GBIF-page-fetch note in Architecture #1). The
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
`test-align_taxa.R`, `test-match_taxa.R`, `test-update_taxa.R`, `test-create_taxonomic_update_lookup.R`
and `test-match_taxa_helpers.R` cover the matching/alignment engine end to end against a small
hand-built combined reference table (`sample_taxonomic_resources()` in
`tests/testthat/helper-align-taxa-fixtures.R`) spanning species (accepted/synonym), genus
(accepted/synonym), family, order (accepted/synonym — a *second* higher rank with an outdated name,
proving `update_taxa()`'s lookup isn't secretly species/genus-specific), an extra non-hardcoded rank
("tribe"), and a subgenus — no network, no `APCalign`-package-data download (only its pure string
helpers, `standardise_names()`/`strip_names()`/`strip_names_extra()`/`standardise_taxon_rank()`, are
called, which are safe to call directly offline). `test-prepare_taxonomic_resources_interactive.R`
covers `prepare_taxonomic_resources(interactive = TRUE)` by supplying `user_responses` throughout,
exactly the way `traits.build` tests its own `metadata_add_traits()`/etc. — never a real interactive
session (see Architecture #2 below). `test-match_taxa.R` covers the opt-in `hybrids`/
`intergrades_affinis` matching (issue #9), plus `progress = TRUE` (issue #5, also covered in
`test-align_taxa.R`). `test-load_taxonomic_resources.R` covers `load_taxonomic_resources("AFD")`
(issue #6) against a small AFD-shaped fixture (`helper-afd-fixtures.R`, see Architecture #3 below) --
also offline-safe, no need for the real 89MB `inst/extdata/AFD.csv`.

`test-match_taxa_typos.R` covers messy, invertebrate-flavoured name oddities specifically -- every
edit-distance type of typo (deletion/insertion/substitution/transposition), the first-letter
anti-cross-matching rule (a 1-edit-distance genus typo that changes the first letter must still fail),
a genuinely ambiguous fuzzy tie (must resolve to nothing, not a guess), case/whitespace/trailing-notes/
`sensu lato` normalisation, morphospecies codes (`sp. 1`/`sp. nov.`/`sp. indet.`), the nominotypical
subgenus bracket convention (`Genus (Genus) species`), and two synonyms of the same accepted species
where one sits under a *different* genus entirely (a real, common invertebrate-taxonomy pattern) --
using a second fixture, `sample_invert_taxonomic_resources()` (`helper-invert-typo-fixtures.R`), grounded in
naming conventions confirmed against the real `inst/extdata/AFD.csv` (e.g. the hyphenated
"letter-shape" epithet convention, `"t-viride"`) rather than invented from scratch.
`test-match_taxa_helpers.R` also gained direct `fuzzy_match()` unit tests for the same distance-type/
first-letter/tie-breaking behaviour, one level below the full `align_taxa()` pipeline.

321 expectations across all offline-safe test files, all passing as of the last run. (See Architecture
#2 below for a fuzzy-matching gotcha this fixture data has to dodge.)

`test-apc_equivalence.R` (issue #10) is the one exception to "no network, no APCalign-package-data
download" above -- it needs a real, live `APCalign::load_taxonomic_resources()` snapshot to compare
against, so it's skipped (not counted in the 321) unless `APCalign` is installed, network access is
available, and it isn't running under `R CMD check --as-cran`; when it does run, it adds a few more
passing expectations on top (328 total, as of the last online run that succeeded). This has also failed
intermittently across several local runs (`load_APC()` → `dplyr::mutate()` on a `NULL`
`APC$family_accepted`, i.e. a live `APCalign::load_taxonomic_resources()` call sometimes not returning
that element) -- looks like a real, if intermittent, upstream issue (rate limiting or a partial
response on the live APC download) rather than anything introduced by taxonAlign, but not yet root-caused;
retry if you hit it.

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
- **`country` can't narrow the fetch itself, only filter it afterwards** — found worth documenting
  explicitly after being asked directly whether the AU-occurrence filter could run *before* the
  (often much larger) full-tree download, to skip fetching taxa that don't even occur in the target
  country. It can't: GBIF's taxonomy-browsing endpoint (`name_lookup()`, what the tree fetch uses) has
  no country concept at all — only the *occurrence-record* endpoint (`occ_search()`, what
  `fetch_gbif_country_keys()` already uses) does, and occurrence records are normally tagged with a
  taxon's *accepted* usage, essentially never a synonym's own key. Filtering to occurrence-derived keys
  before fetching the tree would silently drop every synonym of an in-country taxon (a synonym itself
  has no occurrence records of its own to be found by). A tempting-looking alternative — use the
  (cheap) occurrence facet to get just the in-country *accepted* keys first, then fetch full detail
  (including synonyms) only for those via `rgbif::name_usage()` — was checked against real numbers
  before being ruled out too: AU-occurring Insecta alone has 105,178 distinct occurrence taxonKeys, and
  `name_usage()` doesn't accept more than one `key` at a time (confirmed: errors if you try) — that's
  105,178+ individual API calls, dramatically *more* than the ~1,800 calls (at 1000 rows/page) needed to
  page the whole global Insecta tree once. Fetching the whole tree first, then filtering, remains the
  right design; the genuine speedup opportunity is in how that full-tree fetch itself is paged (next
  bullet).
- **The full-tree fetch is paged concurrently, not one page at a time** — `parallel_requests` (default
  4) controls how many of `fetch_gbif_taxon_tree()`'s paginated `rgbif::name_lookup()` calls run at
  once, via `parallel::mclapply()` (fork-based, so Unix-alike only -- silently falls back to sequential
  on Windows, never incorrect, just not faster there). Chosen over adding a new async-HTTP dependency,
  since `rgbif::name_lookup()` itself has no batching/async option to hook into, and over the
  country-first alternative above. For a large clade (a GBIF-scale invertebrate phylum can mean
  thousands of 1000-row pages) this is where nearly all the wall-clock time goes, so this is a
  meaningful, not cosmetic, speedup — confirmed in practice fetching AU-occurring Arthropoda (2.17M
  global descendants, ~3,100 pages). Each page is retried up to 3 times with a short backoff
  (`fetch_page_with_retry()`) before being treated as a real failure — found necessary in the same
  real fetch: a single page occasionally fails with a transient network/TLS error (e.g. "LibreSSL
  SSL_read... bad decrypt") unrelated to the request itself, and without a retry this would fail the
  *entire* multi-thousand-page tree fetch (see the no-silent-partial-data check below) even after every
  other page already succeeded — wasteful to have to redo a very large, slow fetch from scratch over
  one flaky page. `parallel::mclapply()`'s own child-error handling is deliberately not relied on
  directly: each page is wrapped in its own `try()` inside `fetch_page_with_retry()` rather than letting
  a raw error propagate out of the forked worker, since `mclapply()` additionally emits its own
  "scheduled core N encountered error" warning for an uncaught child error, which would otherwise
  surface confusingly alongside (and before) this function's own clearer error message. If any page
  still fails after retries, the whole tree fetch errors clearly, naming how many of how many pages
  were lost — matching this package's existing "clear error over silent partial data" convention (e.g.
  the `country`-code / `canonical_name`-NA checks elsewhere in the package) — rather than silently
  returning an incomplete tree with no indication anything went wrong.
- **Every rgbif call gets an explicit timeout, and (outside the paginated-page path) a shared retry
  wrapper** (`gbif_curlopts`, `with_gbif_retry()`) -- found necessary after `fetch_page_with_retry()`
  alone still wasn't enough: a request occasionally *hangs* rather than erroring (observed directly on
  the real Arthropoda fetch -- worker processes sitting at ~0% CPU for 30+ minutes, no error, no
  further log output), and a hang can never trigger a retry, since a retry only runs after a request
  actually *fails*. `gbif_curlopts` (`timeout = 60`, passed to every `rgbif::name_backbone()`/
  `name_lookup()`/`name_usage()`/`occ_search()` call in the file via `curlopts`) turns a hang into an
  ordinary, retry-able error after the timeout (120s -- raised from an initial 60s after direct
  measurement showed GBIF's own deep-pagination legitimately taking up to 78s at high offsets under
  concurrent load; see `gbif_curlopts`'s own comment). `with_gbif_retry()` is the non-paginated sibling
  of `fetch_page_with_retry()` -- same retry-with-backoff policy, but raises on exhaustion instead of
  returning a try-error, since name resolution/root-usage/children-page/occurrence-facet calls have no
  cross-call aggregation to report into. Takes a zero-argument thunk (`function() ...`), not a bare
  expression -- an R promise argument is only ever evaluated once and its value cached, so a bare
  expression would silently *not* re-run the real network call on a second attempt. The very first
  `name_lookup()` call in `fetch_gbif_taxon_tree()` (the one that fetches `total`, deciding whether the
  clade needs splitting at all) was initially missed and left completely unwrapped -- found the hard
  way when it alone took down an entire ~5,400-children-deep recursive Insecta fetch on one transient
  failure, with no chance to retry. Now wrapped in `with_gbif_retry()` like everything else.
- **A clade bigger than 100,000 descendants can't be paged at all** — confirmed directly against the
  raw GBIF REST API (not just `rgbif`'s wrapper): `name_lookup()`'s underlying endpoint hard-refuses any
  page whose offset exceeds 100,000 (`"Max offset of 100000 exceeded."`), a fixed server-side limit, not
  a rate-limit or something retries fix. Found in practice fetching Arthropoda (~3.1M descendants,
  ~3,100 pages) and Mollusca (~484k, ~485 pages) — both fail once paging passes page 100, regardless of
  `parallel_requests` or `fetch_page_with_retry()`. `gbif_max_lookup_offset` (100000) is the threshold
  `fetch_gbif_taxon_tree()` checks `total` against; above it, the direct-paging path is skipped entirely
  in favour of `fetch_gbif_taxon_tree_by_children()`.
  - **Recursive split-into-children**: `fetch_gbif_taxon_tree_by_children()` fetches `root_key`'s
    immediate children (`fetch_gbif_taxon_children()`, paginated the same way via
    `rgbif::name_usage(key, data = "children")` — its `meta` has no `count` field, only `endOfRecords`,
    so it pages until that flag is set rather than computing a page count up front) and recurses into
    `fetch_gbif_taxon_tree()` for each one. A child can itself still be too large and need splitting
    again — every taxon's children are smaller than the taxon itself, so this always terminates, but a
    `.depth` guard (6 levels) errors clearly rather than trusting that invariant blindly forever, in case
    some corner of the backbone violates it. Children are fetched **sequentially, not in parallel**:
    each child's own fetch already parallelises across *its* pages internally (`parallel_requests`), and
    nesting `mclapply()` inside `mclapply()` would oversubscribe cores (e.g. 4 children × 4 pages each =
    16-way contention on what might be a 4-8 core machine) for no real benefit.
  - **This makes a huge fetch resumable for free, which matters a lot in practice for a fetch that can
    run for a long time unattended** (Arthropoda's full breakdown took multiple long-running sessions,
    including surviving a machine reboot partway through) — every recursive call caches its own result
    under its own GBIF key exactly like a directly-fetched tree, so there's no separate checkpointing
    mechanism to build or that can get out of sync: the disk cache *is* the checkpoint. Interrupted
    partway through fetching, say, 30 orders under a class, re-running the exact same top-level call
    later only re-fetches whichever orders aren't already cached — already-completed ones return
    instantly from `cache_is_fresh()`.
  - **A full-backbone bulk download exists as an alternative and was deliberately not used**
    (`https://hosted-datasets.gbif.org/datasets/backbone/current/backbone.zip`, confirmed via a direct
    HTTP HEAD request: ~971MB compressed, last modified over a year before this was investigated) — it
    would sidestep the offset limit entirely, but using it only for the huge clades would leave the
    combined reference with silently inconsistent currency (small phyla live/current via the API, huge
    ones years stale from a bulk snapshot) — a worse problem for a taxonomic alignment tool than being
    slower but uniformly live. Also a materially bigger architectural change (a new file-based ingestion
    path covering every kingdom, not a fetch scoped to one taxon) rather than a fix to the existing
    fetch. Worth reconsidering only if GBIF's API limits become more restrictive still.

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
`prepare_taxonomic_resources(taxonomic_resources, ...)` (exported), which itself now has an interactive
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
- **`names(resources)` (and hence `taxon_ranks_to_check`'s default, and `update_taxa()`'s flattened
  lookup table) is ordered most-specific-rank-first, not alphabetically.** `prepare_taxonomic_resources()`
  used to just `split()` on the raw rank string, which orders alphabetically -- arbitrary, and actively
  wrong wherever a name could in principle match at more than one rank (two ranks whose rows carry the
  same `taxon_ID`, as the AFD nominotypical-subgenus case above did before its fix, but also two ranks
  whose rows just happen to have the same *name* — real AFD data has a handful of these at
  family/order/subfamily/suborder/subtribe/superfamily/superorder/class too, and
  `sample_invert_taxonomic_resources()`'s own `"Aporocera"` genus/nominotypical-subgenus fixture is a
  deliberately-built example): `match_taxa()`'s generic higher-rank loops (`match_02b`/`match_02c`/
  `match_12b`/`match_12c`) stop at the first rank in `taxon_ranks_to_check` a row matches, and
  `update_taxa()`'s `taxon_ID`-keyed lookup is first-hit `match()` too, so whichever rank happened to
  sort first alphabetically silently won every such tie. Fixed by `taxonAlign_taxon_rank_specificity`
  (`prepare_taxonomic_resources.R`) -- a fixed, most-specific-first rank vocabulary (extending, in the
  opposite direction, `gbif_rank_order`'s broadest-to-narrowest one) that `taxonomic_resources$taxon_rank2`
  is turned into a `factor()` against (via `union()` with whatever ranks are actually present, so an
  unrecognised rank still gets its own bucket -- just appended after every known rank, sorting last/
  least-specific, the same "extend as new vocabulary turns up, don't guess" convention
  `taxonAlign_taxonomic_status_priority` already uses) before `split()`, and `"species"` (always the
  single most specific bucket) is prepended explicitly at both this split and again in `update_taxa()`'s
  own bind order. A practical consequence, not just a tie-break for pathological input: this is what
  makes a subgenus-rank match survive `update_taxa()` as `"subgenus"` rather than being silently
  downgraded to `"genus"` whenever the underlying loader (e.g. AFD, see below) ever produces a
  cross-rank `taxon_ID` collision again in the future -- most-specific-first ordering is a second,
  independent line of defense on top of namespacing the IDs themselves.
- **Subgenus gets two parallel matching conventions**, both preserved deliberately:
  `resources$subgenus` (plain subgenus name alone, e.g. `"Podosemum"`, matched via the generic
  `taxon_ranks_to_check` loop like any other higher rank) and `resources$subgenus_v2` (a
  `genus_and_subgenus` column, e.g. `"Boronia (Podosemum)"`, matched via its own dedicated
  match_02a/match_12a blocks) — because different input name lists write subgenus either way. Don't
  collapse these into a single representation.
- `fuzzy_match(txt, accepted_list, max_distance_abs, max_distance_rel, ...)` in
  `match_taxa_helpers.R` does the actual fuzzy comparison for a single string, using
  `stringdist::stringdist(..., method = "dl")` (Damerau-Levenshtein), but only considers a candidate a
  match if the first letter (or, for genus/species epithets, first 1–2 letters) of each word already
  agrees — this is what keeps fuzzy matching from cross-matching unrelated taxa (see the "Boronieae"
  vs. "Boronia" note below). `fuzzy_match_column(x, accepted_list, ...)` vectorizes it over a whole
  column via `purrr::map_chr()` — every fuzzy-matching call site in `match_taxa()` (species-level
  `match_05a`/`match_05b`, and the genus-level `fuzzy_match_genera()` closure) goes through this shared
  helper now, rather than some looping `for (i in seq_len(nrow(taxa$tocheck)))` and calling
  `fuzzy_match()` one row at a time, matching the equivalent efficiency fix upstream APCalign made in
  [commit fc16cd3](https://github.com/traitecoevo/APCalign/commit/fc16cd3f12cd0bb6fec8b5c8b402e8a339bdc84c)
  (a pure refactor there too, not a behaviour change — `fuzzy_match()` was already only ever called on
  one string at a time either way). `extract_genus()` handles the `x Genus` hybrid-naming convention.
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
- **Six real bugs found by testing against real, messy data** (not just the hand-built fixture) that
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
  - Discovered via real APC data (`APCalign::load_taxonomic_resources()$APC_accepted`, which is
    accepted-names-only -- no synonyms at all): `prepare_taxonomic_resources()`'s
    `split(species_table, species_table$taxonomic_status)` only creates a list element for statuses
    actually present, so an accepted-only (or synonym-only) input left `resources$species$synonym` (or
    `$accepted`) missing (`NULL`) entirely rather than an empty tibble. `match_taxa()`'s
    `match_01a`/`01b`/`01c`/`01d`/`05a`/`05b`/`09a`/`09b`/`10a`/`10b`/`11a`/`11b` blocks reference
    `resources$species$accepted`/`synonym$<column>` unconditionally (unlike higher ranks, which are
    only ever looped over if actually present in `names(resources)`) -- `NULL$<column>` is `NULL`, and
    `dplyr::mutate(x = NULL)` *drops* that column rather than leaving it `NA`. Since every input name
    then legitimately matches nothing in that block (there's nothing to match against), the mutated
    result ends up with fewer columns than the slice it's replacing, and `taxa$tocheck[i, ] <- ...`
    errored ("Can't recycle input of size N to size M") on *every* alignment, not just a specific name --
    regardless of whether `resources` was prepared explicitly or auto-prepared via
    `ensure_prepared_resources()`. Fixed by backfilling any status entirely absent after the split with
    a 0-row tibble sharing the same columns, so `resources$species$accepted`/`synonym` are always
    structurally complete.
  - Discovered writing the issue #10 APCalign-equivalence test, against the *full* real APC data (not
    just the accepted-only slice above): `split(species_table, species_table$taxonomic_status)` splits
    into a separate list element for every *literal* status string, but real APC synonym-like rows use
    ~18 distinct non-"accepted" labels ("basionym", "nomenclatural synonym", "taxonomic synonym",
    "orthographic variant", "misapplied", "excluded", ...) -- essentially never the literal word
    "synonym". So `resources$species$synonym` (the only non-accepted bucket `match_taxa()` ever
    references) ended up either empty or covering only a tiny sliver of real synonym rows, and the vast
    majority of real APC synonyms were silently invisible to every synonym-matching block -- not an
    error, just silently wrong output (e.g. `align_taxa("Genoplesium insigne", ...)` fuzzy-matched a
    coincidentally-similar but wrong genus instead of finding the exact, if non-"accepted"-labelled,
    synonym match APCalign itself found). Fixed by bucketing species into exactly `"accepted"` vs
    everything else (not a literal `split()` by the status string), while still preserving each row's
    real `taxonomic_status` value inside the `synonym` bucket (`match_taxa()` already pulls
    `taxonomic_status` from the row itself, not the bucket name, so output fidelity is unaffected).
  - Discovered against the real, combined AFD+iNaturalist reference (not a fixture): museum "voucher
    code" morphospecies names (e.g. `"Aderid BF05"`) that should fuzzy-match a real, present tribe/family
    name (`"Aderini"`/`"Aderidae"`, well within fuzzy tolerance) silently failed to, in `match_taxa()`'s
    final generic higher-rank fuzzy fallback (`match_12c`). Two compounding bugs in the same loop: (1)
    `fuzzy_match_genus` was never recomputed against *this* rank's `word_one_stripped` on each iteration
    of `for (ranks in taxon_ranks_to_check)` -- it was reused as a stale leftover from `match_02c`'s own
    loop, against whichever rank that loop had last tested (not necessarily the rank `match_12c` was
    currently on), so a fuzzy match only ever succeeded by coincidence; (2) even when a fuzzy candidate
    genuinely existed, the `ii <- match(...)` lookup used the original query's own `word_one_stripped`
    (which, being the fuzzy fallback, is by definition *not* present in `resources[[ranks]]`) instead of
    the fuzzy match result itself, so `ii` was always `NA`, corrupting the matched row's
    `taxonomic_dataset`/`taxon_ID`/etc. with blanks even on the rare case (1) let through. Fixed both:
    recompute `fuzzy_match_genus` fresh inside the loop against `resources[[ranks]]$word_one_stripped`,
    and look `ii` up via the fuzzy match result, not the original word. This changed some morphospecies
    codes that historically resolved to tribe rank (alphabetically checked before family in
    `taxon_ranks_to_check`'s default order) to resolve to family rank instead where both are valid
    fuzzy-match targets -- confirmed as acceptable, not a regression to chase further.
  - Discovered against a real, ~867k-row *worldwide* (all invertebrate phyla, no country filter)
    GBIF reference: `fuzzy_match()`'s first-letter-matching filter (`match_taxa_helpers.R`) used to
    compare every `accepted_list` entry's extracted first letter against the query's via `==`, with no
    guard for the extraction itself returning `NA`. Real, messy worldwide backbone data has malformed
    higher-rank rows whose `canonical_name` is an author-citation string (e.g. `"Chandler, 1935"`) --
    and some of *those* have no alphabetic character at all once malformed further (a bare punctuation/
    number fragment), so `stringr::str_extract(..., "[:alpha:]")` returns `NA` for them. Subsetting a
    vector with a logical index that itself contains `NA` doesn't drop that entry -- it inserts a
    literal `NA` *value* into the filtered result instead, which then silently poisons every
    `stringdist()`/`min()` computation downstream with `NA`, eventually surfacing as "missing value
    where TRUE/FALSE needed" deep inside the unrelated-looking `check_match()` helper -- a confusing
    error far from its actual cause. Fixed by excluding `!is.na(...)` explicitly in the first-letter
    filter itself (such an entry correctly has "no first letter to compare", so it's excluded rather
    than injected as `NA`), plus a defensive `na.rm = TRUE` on the `min()` calls as a backstop against
    any other not-yet-seen data-quality issue taking a similar path.
- **`taxonomic_status`-based disambiguation when the same lookup key repeats** -- real reference data
  (e.g. real APC data's "Genoplesium insigne", which recurs under more than one non-"accepted" status)
  can list the same `canonical_name`/`scientific_name`/binomial/trinomial more than once with different
  statuses attached. Since `match_taxa()`'s exact-match blocks use `match()` (first-hit semantics), the
  row order within each `resources$<rank>$<status>` table decides which one wins -- so
  `prepare_taxonomic_resources()` now sorts the whole combined table by
  `taxonAlign_taxonomic_status_priority` (a fixed priority vector, in `prepare_taxonomic_resources.R`)
  before any rank/status splitting happens, ensuring the most reliable status wins any tie. Ported and
  extended from APCalign's own `relevel_taxonomic_status_preferred_order()` (`update_taxonomy.R`),
  generalised here to every rank/status lookup (APCalign only applies it during genus/family-level
  update disambiguation) -- extended with two terms GBIF's vocabulary uses that APC/APNI's doesn't:
  `"homotypic synonym"` (shares the accepted name's type specimen -- as reliable as a
  nomenclatural/basionym relationship, placed right after `"taxonomic synonym"`) and
  `"heterotypic synonym"` (a different type judged to represent the same taxon -- placed right after
  `"basionym"`). A status not in the vector sorts after every known one (rather than being dropped or
  erroring) via `factor()`'s NA-for-unmatched-level behaviour, which `dplyr::arrange()` places last by
  default -- extend the vector as further status vocabularies turn up, rather than guessing at their
  rank. The sort is stable, so it composes correctly with the existing between-*dataset* priority
  (row-bind order, from combining multiple `taxonomic_resources` tables): rows tying on `taxonomic_status`
  keep whatever relative order they already had.
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
  `user_responses` rather than prompting). `taxonomic_resources` now also accepts a file path or a
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
  because its purpose is different: letting someone start with a single file (`taxonomic_resources`) and
  grow it into a combined set interactively, rather than requiring the whole set assembled up front.
  `user_responses$additional_tables` (an optionally-named list of further tables/paths) bypasses the
  real loop for tests/scripting — each entry still goes through the exact same `resolve_taxonomic_resources_table()`
  path as any other table, consulting `user_responses[[its own label]]` for its own missing fields.
- **`taxonomic_resources` is optional when `interactive = TRUE`**: if it's `NULL`, the *first* table is now
  obtained via the same prompt used for every *additional* one (`prompt_for_table_path()`, shared by
  both call sites) — asking for a file path via `readline()` — rather than requiring the caller to
  already have assembled a table before they can even start. `user_responses$initial_table` bypasses
  this for scripting/testing, the same way `additional_tables` already does for later ones. Before this,
  someone starting from scratch had to hand-assemble their own `list(...)` of tables in R code before
  ever calling the function at all, which is real friction for exactly the users this on-ramp is meant
  to help — found by re-reading the `get-started.qmd` vignette's own "combining multiple references"
  example.
- **`taxon_rank`/`taxonomic_status`/`taxonomic_dataset` share one prompt shape**
  (`prompt_column_or_fixed_value()`): "does the data have a column for this, or is every row the same
  value?" -- picking a column reads a per-row value, a fixed value applies the same one to every row.
  `taxonomic_dataset` used to be a plain free-text prompt (always one label for the whole table, no
  column option) until a real case surfaced it: a spreadsheet someone assembles by hand can just as
  easily mix rows sourced from several references (e.g. some rows from AFD, some from iNaturalist,
  with a column recording which) as have one uniform source. Moved onto the same
  `prompt_column_or_fixed_value()` path as the other two rather than keeping a separate, more limited
  mechanism — this also retired `prompt_free_text()` entirely (it had no other caller).
- **Missing higher-rank rows are synthesised automatically** from whatever implied hierarchy
  information a table already carries, rather than requiring the caller to add an explicit row for
  every genus/family/etc. themselves. Found via this package's own `get-started.qmd` vignette example:
  a species row named its genus via the `genus` column (`genus = "Xylotoles"`), but with no explicit
  `taxon_rank = "genus"` row for "Xylotoles" anywhere in the table, `align_taxa("Xylotoles sp. 1", ...)`
  correctly returned no match at all -- a `genus` column *value* is descriptive metadata, not the same
  thing as a genus-rank *row* to match against, and it's an easy gap to leave (the vignette's own
  example data had exactly this gap, for exactly this reason). `prepare_taxonomic_resources()` now scans
  every column beyond the required 8 (plus `genus` itself, which is required but is *also* a hierarchy
  column) for values without a corresponding explicit row at that rank, and adds one automatically --
  right after the `taxonomic_status`-priority sort and before the big derived-columns `mutate()`, so
  synthesised rows get `word_one`/`stripped_canonical`/etc. computed the same as every other row.
  Deliberately scans *any* extra column, not just the fixed Linnaean kingdom/phylum/class/order/family
  set, since real data carries ranks beyond those (tribe, subfamily, ...) -- the tradeoff, accepted
  deliberately, is that a genuinely non-taxonomic extra column (e.g. "locality", "collection_year")
  would also be scanned; a non-character column is skipped (it can't hold a taxon name, and previously
  crashed outright -- `values != ""` on a POSIXct/numeric column errors rather than returning `FALSE`),
  but a stray *character* column not meant as a hierarchy column has no such guard and will generate
  bogus rows if included. This generalises, inside `prepare_taxonomic_resources()` itself, the same idea
  `load_AFD()`'s `afd_higher_rank_rows()` already applies specifically to AFD's own raw export (see
  Architecture #3) -- to *any* input table, not just AFD's. A synthesised row has no natural ID, so
  `taxon_ID`/`accepted_name_usage_ID` fall back to a placeholder combining the dataset, rank and name
  (`paste(taxonomic_dataset, taxon_rank, canonical_name, sep = "_")`, e.g. `"MY_DATA_genus_Xylotoles"`)
  -- unique across both rank (a nominotypical genus/subgenus sharing a name) and dataset (two sources
  both having, say, a "Formicidae" family row). A value that already has an explicit row at that rank
  is left alone (no duplicate synthesised row is added).
- **`genus` now ranks before `subgenus`** in `taxonAlign_taxon_rank_specificity` -- the one deliberate
  exception to that vector's otherwise most-specific-first ordering. Unlike every other rank pair, a
  bare name shared by a genus and its own nominotypical subgenus (e.g. `"Xylotoles"`) is genuinely
  ambiguous on its own, and the safer default is to assume the user means the broader genus-rank
  grouping -- genus names are what people actually write, the bracketed `Genus (Subgenus)` convention
  and the plain subgenus-alone convention both still exist for when a subgenus really is intended. This
  is *unrelated* to the separate `taxon_ID`-collision bug fixed in `load_taxonomic_resources.R`'s
  `afd_higher_rank_rows()` (Architecture #3) -- that bug was about two different rows accidentally
  sharing the same *ID string* and is fixed by rank-namespacing IDs regardless of ordering; this is
  purely about which rank's *name* table a plain, unqualified query name should check first.
  `subgenus_v2` is ordered immediately after `subgenus` (not before, and not always trailing last as it
  used to) -- cosmetic only, since every functional reference to `taxon_ranks_to_check`/`update_taxa()`'s
  flattening already excludes `subgenus_v2` by name, unaffected by list position -- but keeps the two
  parallel subgenus conventions adjacent when a user inspects `names(resources)` themselves.
- **Hybrid/graded/indecision/intergrade names** (issue #9) are handled by one shared, generic helper,
  `match_special_case_to_genus()` (top of `R/match_taxa.R`), rather than APCalign's ~20 separate,
  near-duplicate blocks (5 sub-blocks each for 4 pattern families, because APC/APNI's `resources` keeps
  accepted/synonym/APNI genera in three separate tables). taxonAlign's `resources$genus` is already one
  combined table (only `species` gets split by `taxonomic_status`), so that split doesn't apply here --
  one function suffices for both callers. Both are opt-in (`hybrids = FALSE`, `intergrades_affinis =
  FALSE` on `match_taxa()`/`align_taxa()`/`create_taxonomic_update_lookup()`), and both only ever
  resolve to genus rank (never a specific species), since none of these naming conventions can specify
  a genuine species:
  - `hybrids = TRUE` detects `" x "`/`" X "` (a literal, space-delimited hybrid marker) -- `match_03a`
    (exact genus)/`match_03b` (fuzzy genus)/`match_03c` (unresolved)/`match_03d` (no genus-rank
    reference available at all).
  - `intergrades_affinis = TRUE` consolidates what APCalign implements as three separate pattern
    families -- an intergrade (`--`), a collector's indecision between two taxa (`/`, excluding names
    with digits/parens/apostrophes to avoid false positives), and a graded/"affinis"/"cf." identification
    (`aff.`/`affinis`/`cf.`) -- since they're rarer than hybrids and share the same shape: `match_04a`
    (exact genus)/`match_04b` (fuzzy genus)/`match_04c` (unresolved)/`match_04d` (no genus-rank
    reference). The `affinis` detection specifically needs `APCalign::standardise_names()` from a
    version including [upstream commit a2c43d1](https://github.com/traitecoevo/APCalign/commit/a2c43d1fbec29c68aec7bfd4fd46b831effccec3)
    or later (`remotes::install_github("traitecoevo/APCalign")` to pull latest `main`) -- older versions
    unconditionally abbreviate `" affinis "` to `" aff. "` regardless of what follows, which defeats the
    rank-marker-aware check needed to tell a genuine specific epithet (`"Gomphrena affinis subsp.
    pilbarensis"`) apart from an affinity qualifier (`"Acacia affinis dealbata"`) -- the same
    negative-lookahead regex (`not_before_rank_marker`) is also ported into `match_taxa()`'s own
    detection, but it's only reachable if `standardise_names()` hasn't already collapsed the distinction
    upstream.
  - `detect_fn` (the pattern-detection argument `match_special_case_to_genus()` takes) is a *function* of
    `cleaned_name`, not a pre-computed logical vector -- `taxa$tocheck` shrinks after each internal
    `redistribute()` call, so recomputing detection fresh each time keeps it aligned with whatever rows
    are still actually in `tocheck` rather than relying on stale positions from before rows were removed.
- **Also fixed two pre-existing `alignment_code` numbering bugs while adding the above**: the per-rank
  `sp.`-suffix exact-match loop (comment `match_02b`) and its fuzzy-fallback loop (comment `match_02c`)
  had been stamping `alignment_code` values of `"match_02a_..."`/`"match_02b_..."` respectively -- off
  by one letter from their own comments. Fixed so every match block's `alignment_code` now sorts in the
  same order names are actually matched in, letting a user sort output by `alignment_code` to see
  matches in execution order and spot mismatches by rank/pattern.

- **Equivalence with APCalign, given the same real APC data source, is now covered** (issue #10) by
  `tests/testthat/test-apc_equivalence.R` -- skipped unless `APCalign` is installed and network access
  is available (`testthat::skip_if_not_installed()`/`skip_if_offline()`/`skip_on_cran()`), since it
  loads a real, live `APCalign::load_taxonomic_resources()` snapshot rather than a fixture. Two tests:
  - Compares `align_taxa()`'s `aligned_name`/`taxon_rank` directly against `APCalign::align_taxa()`'s
    (these agree on every name regardless of rank, since both share the same matching-engine design
    lineage), and `create_taxonomic_update_lookup()`'s `accepted_name` against `APCalign`'s own
    (agreeing everywhere except genus/family rank, where taxonAlign's rank-agnostic `update_taxa()`
    legitimately resolves further than APCalign's rank-specific update functions do -- a documented
    design difference, not a discrepancy). Uses the same curated name list APCalign's own test suite
    checks "consistency with previous runs" against.
  - A second test focuses on the *matching* step specifically, with a deliberately awkward set of real
    and fabricated names: a genuine misspelling, a bare `genus sp.`, a fabricated hybrid name, a
    graded/"cf."/"affinis" identification (one real, one fabricated), an intergrade (`--`), an
    indecision (`/`), messy extra whitespace, and a valid trinomial with trailing free-text notes.
    Fabricated (rather than real, ambiguous) epithets are used for the hybrid/intergrade/indecision/
    affinis cases specifically so neither package can coincidentally species-level-fuzzy-match them to
    an unrelated real species -- that would turn the comparison into a coin flip on both packages' fuzzy
    tie-breaking, not a real test of whether the same *pattern* is detected the same way. Since
    APCalign's `align_taxa()` has no `hybrids`/`intergrades_affinis` toggle (it always attempts these
    match families), taxonAlign is called with both turned on to compare fairly.

- **Progress bar** (issue #5): `match_taxa()`/`align_taxa()`/`create_taxonomic_update_lookup()` all gain
  a `progress = FALSE` parameter; `TRUE` prints a `utils::txtProgressBar()` (no new dependency). Tracks
  *rows resolved so far* (`nrow(taxa$checked)` against the total `match_taxa()` started with), not which
  match block is currently running -- match blocks aren't equal-cost (the fuzzy blocks typically do most
  of the real work on large inputs), so a block-count-based bar would jump to "nearly done" almost
  instantly and then stall, which is more misleading than informative. Implemented via
  `redistribute_progress()` (`match_taxa_helpers.R`), a drop-in replacement for `redistribute()` that
  also advances the bar if one is open -- every one of `match_taxa()`'s ~18 `taxa <- redistribute(taxa)`
  checkpoints (including the ones inside `match_special_case_to_genus()`, the shared hybrid/
  intergrade_affinis helper) now calls this instead. `pb` (the progress-bar object, `NULL` unless
  `progress = TRUE`) is threaded through as an ordinary argument; `on.exit(close(pb), add = TRUE)` at the
  top of `match_taxa()` guarantees it's closed on every exit path, not just the final return at the
  bottom -- there are ~18 early returns scattered through the function (one after each match block, so
  it can stop as soon as everything is resolved), and the bar needs to close on all of them, not only
  the one at the end.
- **`include_bracketed_info` (opt-out of APCalign's always-bracketed higher-rank format)**:
  `match_taxa()`/`align_taxa()`/`create_taxonomic_update_lookup()` all gain an `include_bracketed_info
  = FALSE` parameter. APCalign's convention for a higher-rank-only match is always
  `"<rank name> sp. [<original name>; <identifier>]"`, even when the name being matched *is* nothing
  more than the matched rank's own name (a bare `"Boronia"` alone, or a bare `"Boronia (Valvatae)"`) --
  in that case the bracketed suffix is pure redundancy, since `original_name` already preserves the raw
  input as its own column on every row regardless of how `aligned_name` is formatted. When `FALSE` (the
  new default) *and* the name being matched reduces to nothing beyond the matched rank's own name,
  `aligned_name` is just that bare name -- no `" sp."`, no brackets, no `identifier` either (dropped
  entirely, not just de-emphasised). Whenever there's anything more in the name being matched (an
  unresolved epithet, a morphospecies code, a hybrid/intergrade/indecision/affinis marker, ...), the
  bracketed format is used regardless of this argument, since dropping it there would genuinely lose
  information the bracket was the only place recording. `include_bracketed_info = TRUE` restores
  APCalign's convention unconditionally, for anyone who wants it.
  - Only affects the three *generic, last-resort* higher-rank match blocks -- `match_12a` (bracketed
    subgenus fallback), `match_12b`/`match_12c` (exact/fuzzy fallback against any rank in
    `taxon_ranks_to_check`) -- via a `bare_rank_name` check (`stringr::str_count()` on `cleaned_name`:
    exactly 1 whitespace-delimited token for `match_12b`/`match_12c`, exactly 2 for `match_12a`'s
    `"Genus (Subgenus)"` shape). Deliberately does **not** touch:
    - `match_02a`/`match_02b`/`match_02c` (the explicit `"...sp."`-suffixed blocks) -- these only ever
      fire when the *original* input already explicitly wrote `"sp."` itself, so there's always
      something (the "sp.") beyond the bare rank name; their existing, simpler format (`"<rank name>
      sp."` plus an optional `identifier`, no repeated original-name bracket at all) is untouched.
    - `match_special_case_to_genus()` (the shared hybrid/intergrade/indecision/affinis helper) -- every
      one of its `detect_fn` patterns (`" x "`, `--`, `/`, `aff.`/`affinis`/`cf.`) requires content
      beyond a bare rank name by construction, so `cleaned_name` is never just the matched genus's own
      name there; the marker and (for an indecision `/`) the second candidate name are real information
      a bracket-less format would silently discard, not redundancy.
  - Real behavioural consequence for the `sample_invert_taxonomic_resources()` fixture's own
    `"Aporocera"`/nominotypical-subgenus-`"Aporocera"` ambiguity (see the rank-specificity-ordering
    note above): a bare `"Aporocera"` alone now returns `aligned_name == "Aporocera"` (no bracket) by
    default, regardless of whether the tie resolved to genus or subgenus rank underneath -- the
    ambiguity between the two is still resolved via `taxon_rank`/`taxon_ID` as before, just no longer
    rendered as a redundant `"Aporocera sp. [Aporocera]"` string.

### 3. Known-source reference loader — `R/load_taxonomic_resources.R` (active, exported; internal helpers `@noRd`)

`load_taxonomic_resources(taxonomic_dataset = ...)` (issue #6) fetches/reshapes a fixed set of *known*
taxonomic datasets into taxonAlign's flat, `prepare_taxonomic_resources()`-ready column schema
(`canonical_name`, `scientific_name`, `taxon_rank`, `taxonomic_status`, `taxonomic_dataset`, `genus`,
`taxon_ID`, `accepted_name_usage_ID`) — complementing (not replacing) `prepare_taxonomic_resources()`
the same way `generate_GBIF_taxonomic_reference_list()` does for GBIF, except `"AFD"`'s "fetch" is
reading+reshaping a local file rather than an API call, and `"APC"` is a thin wrapper around
`APCalign::load_taxonomic_resources()`. Always returns a *named list* of flat tibbles (one per
requested dataset, even for a single one), so a user combines any mix of known and their own
reference tables identically: `prepare_taxonomic_resources(load_taxonomic_resources(c("AFD", "APC")))`.
Errors immediately, naming the known datasets, on an unrecognised `taxonomic_dataset` value —
`taxonAlign_known_datasets` (top of the file) is the registry to extend as further sources are added.

- **`"AFD"` (Australian Faunal Directory)**: AFD only exists as a one-off raw CSV export (no public
  API, unlike GBIF) — `inst/extdata/AFD.csv` (~89MB, ~117k rows, one row per species/subspecies).
  `load_AFD()` ports the *approach* of the sibling `ausinvertraits.addons` repo's
  `scripts/02_AFD_checklist_clean.R` (confirmed the current, canonical version of that script —
  reimplemented directly against taxonAlign's schema, not translated line-by-line; deliberately
  excludes that repo's AusInvertTraits-specific GRIIS/WoRMS invasive-and-marine-species filtering and
  "improper name" removal, which are curation decisions about *which* taxa to include, not part of
  reshaping the data into taxonAlign's format):
  - **Accepted rows**: one per raw row, `canonical_name = FULL_NAME`, `scientific_name =
    COMPLETE_NAME`, `taxon_rank` derived from whether `SUB_SPECIES` is filled (`"species"` vs.
    `"subspecies"`), `taxon_ID = accepted_name_usage_ID = CONCEPT_GUID` (AFD's own stable UUID,
    self-referential -- the one rank level with a natural ID).
  - **Higher-rank rows**: one per distinct, non-blank value of every higher-rank column AFD provides
    (subgenus through phylum) -- mirroring the ported script's "one rank at a time, `distinct()` the
    column" approach. None of these have a natural stable ID (`CONCEPT_GUID` only exists at
    species/subspecies level), so `taxon_ID`/`accepted_name_usage_ID` fall back to the rank's own name,
    **namespaced by rank** (`"<rank>:<name>"`, e.g. `"genus:Agrilus"` vs. `"subgenus:Agrilus"`).
    `genus` is populated only for genus/subgenus rows (subgenus rows need their owning genus so
    `prepare_taxonomic_resources()` can build the bracketed `Genus (Subgenus)` convention
    automatically) -- every other higher rank leaves it `NA`, same as elsewhere in taxonAlign.
    **A real AFD-specific quirk found and fixed here**: family-and-above ranks (family, superfamily,
    order, ..., phylum) are exported ALL CAPS (`"BUPRESTIDAE"`), but subfamily-and-below (subfamily,
    tribe, subtribe) are normal title case (`"Agrilinae"`) -- inconsistent within the same file.
    `afd_higher_rank_rows()` normalises every rank to sentence case regardless (a no-op on the
    already-correctly-cased ones), since an ALL-CAPS reference value would otherwise never
    exact-match a normally-cased input name.
    **A second, more serious real bug found the same way (via a real end-to-end run against
    AusInvertTraits' full name list, not the hand-built fixture)**: `taxon_ID` used to fall back to the
    *bare* rank name with no rank qualifier at all. This collides across ranks whenever the same string
    is used at two different ranks -- and for genus/subgenus this isn't a rare coincidence but the norm:
    by nomenclatural convention, every genus that's been split into subgenera has one *nominotypical*
    subgenus sharing the genus's own name (e.g. genus `"Agrilus"` / its nominotypical subgenus
    `"Agrilus"`). In the real, full AFD.csv this affects 572 of 1725 distinct genus/subgenus pairs
    (~1180 higher-rank rows total, plus a handful more at family/order/subfamily/suborder/subtribe/
    superfamily/superorder/class). Since `update_taxa()`'s lookup is keyed on `taxon_ID` via `match()`
    (first-hit semantics, see the "single, rank-agnostic lookup" bullet in Architecture #2), a
    subgenus-rank match's `accepted_name_usage_ID` (self-referential, so also the bare rank name) would
    silently resolve to whichever colliding row bound first when `resources`' rank sublists were
    flattened -- the genus-rank row, since `genus` sorts before `subgenus` in `names(resources)` --
    discarding the subgenus and downgrading `taxon_rank`/`accepted_name`/`suggested_name` from subgenus
    to genus. `align_taxa()`'s own output was never affected (it builds `aligned_name` from
    `resources$subgenus_v2` directly, not via this ID lookup) -- only `update_taxa()`'s
    (and hence `create_taxonomic_update_lookup()`'s) forward-resolved columns were. Fixed by
    namespacing every higher-rank `taxon_ID` with its own rank, exactly as described above; regression
    test: `test-load_taxonomic_resources.R`'s `"namespaces taxon_ID by rank..."` test, using a fixture
    genus/subgenus pair that deliberately shares a name (`"Thirdgenus"`).
  - **Synonym rows**: AFD embeds every synonym of a taxon as one semicolon-joined free-text field
    (`SYNONYMS`), each entry mixing name + author + year with no separator between the name and its
    authorship (e.g. `"Cisseis fossicollis Kerremans, 1903"`). `afd_synonym_rows()` splits on `"; "`,
    drops entries identical to the row's own name (self-referential noise in the raw data), then
    strips authorship via `strip_afd_authorship()` -- ported from the same script's technique: build a
    regex from every distinct `AUTHOR` value present in the *whole* AFD file (a real, closed
    vocabulary of the taxonomists appearing in it) and strip a matching trailing `"<author>, <year>"`.
    A generic fallback (any capitalised author-like token(s) before a trailing year) catches entries
    whose author isn't in that dictionary for some reason; if neither matches, the entry is returned
    unchanged (including its authorship) rather than guessed at further -- verified against the real,
    full file this only affects ~3 of ~156k synonym rows (parenthetical multi-author combinations,
    lowercase author typos in the source data, and one very long `"in X, Y & Z"` author chain). `genus`
    is re-derived from each synonym's own (post-strip) name via the existing `extract_genus()` helper
    (`match_taxa_helpers.R`), not copied from the accepted row's `genus` -- a synonym can sit under a
    *different* genus than the name it's now a synonym of (e.g. `"Cisseis fossicollis"` as a synonym of
    accepted `"Aaaaba fossicollis"`). `taxon_ID` is synthesised per synonym row (`<CONCEPT_GUID>_syn<n>`);
    `accepted_name_usage_ID` is the accepted row's own `CONCEPT_GUID`, resolving the synonym forward.
  - **Caching**: the reshaped result (raw ~117k rows expand into ~310k output rows once every higher
    rank and every synonym gets its own row -- real work, ~14s uncached, ~0.5s cached) is cached as a
    single `.rds` in `cache_dir` (default `tools::R_user_dir("taxonAlign", "cache")`, the same
    convention `generate_GBIF_taxonomic_reference_list()` uses), keyed by the *source file's own
    size/mtime* rather than a time-based freshness window like the GBIF loader's -- deliberately
    different, since a local file (unlike a remote API) lets us detect a content change directly:
    swapping in an updated `AFD.csv` invalidates the cache automatically, without the user needing to
    remember `refresh_cache = TRUE`.
  - Every column is forced to character on read (`readr::cols(.default = readr::col_character())`) --
    several raw columns (`SUB_GENUS`, `SUB_SPECIES`, and others this function doesn't use) are sparsely
    populated enough that `readr`'s sample-based type-guessing can mis-infer them as logical, which
    would break every string operation the moment a real (non-blank) value showed up.
- **`"APC"`**: `load_APC()` is a thin wrapper flattening `APCalign::load_taxonomic_resources()`'s
  several accepted/synonym/genus/family pieces into one combined table -- the exact combining logic
  originally prototyped inline in `test-apc_equivalence.R` (issue #10), now shared from here instead
  (that test calls `load_taxonomic_resources("APC")` too, rather than duplicating it). `family_accepted`
  is APC's one piece missing a `taxonomic_dataset` column, backfilled with `"APC"` to match every other
  piece. No caching needed -- `APCalign::load_taxonomic_resources()` already caches internally.
- Test coverage: `tests/testthat/test-load_taxonomic_resources.R` covers the `"AFD"` path end to end
  (accepted/subspecies rows, higher-rank dedup and case normalisation, subgenus pairing, synonym
  splitting/authorship-stripping, caching, and a full `prepare_taxonomic_resources()`→
  `create_taxonomic_update_lookup()` run) against a small, hand-built AFD-*shaped* fixture
  (`helper-afd-fixtures.R`) -- entirely offline, no need for the real 89MB file. The `"APC"` path is
  inherently network-dependent (like the rest of `test-apc_equivalence.R`), so its coverage lives there
  instead, gated the same way.

### Vignette and data tying the two together

`vignettes/reproduce-EH-workflow.Rmd` reproduces the original AusInvertAlign workflow end-to-end:
loads a taxon reference CSV and an "answer key" (`aligned_names.csv`) from the sibling
`../ausinvertraits.addons` checkout, calls `prepare_taxonomic_resources()`/`align_taxa()`, and diffs
the result against the known-correct AusInvertTraits alignment to check the port is faithful. It is
**not self-contained** — it reads paths outside this repo and will not knit standalone.
`data/aligned_names_b.rds` is a saved output of that vignette run, kept for comparison.
`data-raw/data-raw.R` is a similar external-path stub for generating package data, not a working
reproducible data-raw script.

`vignettes/get-started.qmd`, by contrast, **is** self-contained and does actually build -- a
user-facing "getting started" walkthrough covering every exported function (`prepare_taxonomic_resources()`,
`generate_GBIF_taxonomic_reference_list()`, `load_taxonomic_resources()`, `align_taxa()`, `update_taxa()`,
`create_taxonomic_update_lookup()`) in the order you'd actually use them, ending in a realistic
"update a list of raw field names" workflow. Deliberately **not** registered as a formal R/knitr
vignette (no `%\VignetteIndexEntry`/`%\VignetteEngine` comments) -- it's meant to be rendered directly
via `quarto render vignettes/get-started.qmd` and published as a static page (e.g. GitHub Pages), not
built via `R CMD build`/`devtools::build_vignettes()`; `DESCRIPTION`'s `VignetteBuilder: knitr` is
unrelated to it. Verified to `quarto render` cleanly end to end (using real, small, fast examples --
a tiny hand-built reference table, plus a real live GBIF call for a small genus with only a handful of
descendants) -- confirm this keeps working after any change to `align_taxa()`/`update_taxa()`/
`create_taxonomic_update_lookup()`'s output shape. Quarto's own build leaves a `get-started_files/`
support directory and a `.knit.md` alongside the rendered `.html` -- both are `.gitignore`'d in
`vignettes/.gitignore`, matching the existing `*.html`/`*.R` entries there; clean them up manually if
testing a render locally (an `R CMD check` NOTE about "non-portable file paths" pointed at
`get-started_files/libs/...` is this leftover directory, not a real problem, if you forget to).

**A real bug found while building this vignette's live GBIF example**: `generate_GBIF_taxonomic_reference_list()`
crashed ("Column `acceptedKey` not found") on a real, small, no-synonym GBIF genus (`"Aporocera"`).
`rgbif::name_lookup()`/`name_usage()` responses omit a column entirely (rather than including it as
all-NA) whenever *every* row in the fetched batch lacks a value for it -- a jsonlite-flattening
artifact of the underlying GBIF API response. A small clade where every row is already accepted (so
every row's `acceptedKey` is genuinely NA) is a real, easy-to-hit case of this, and it broke the
function's own `dplyr::coalesce(.data$acceptedKey, .data$key)` step (and would equally have broken the
`country` filter's `.data$acceptedKey %in% occ_keys` check). Fixed by backfilling every column the
function goes on to reference (`acceptedKey`/`parentKey` as integer, the rest as character) if entirely
missing, right after the tree is fetched -- the same "ensure a possibly-absent column exists before
anything downstream assumes it's there" defensive pattern used elsewhere in the package (e.g.
`update_taxa()`'s `if ("genus" %in% names(all_taxa))` check).
