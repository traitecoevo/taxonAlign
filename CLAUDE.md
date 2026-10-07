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
`generate_taxadb_taxonomic_reference_list()` (issue #19, see Architecture #1b) is a third way to build
a reference table -- sourced from [taxadb](https://docs.ropensci.org/taxadb/)'s own pre-cached,
versioned snapshots of GBIF/ITIS/COL/etc., a better fit than `generate_GBIF_taxonomic_reference_list()`
for a genuinely large taxon group (no live pagination, no 100,000-row offset ceiling), with `country`
filtering (still GBIF-only) reusing that function's own internal helpers rather than duplicating them.
`load_NSL_resources(taxon_group = ...)` (see Architecture #4) is a fourth: a standalone loader for the
Australian National Species List's own per-group export pairs (`"animals"` -- the AFD's own NSL
export -- plus `"algae"`, `"bryophytes"`, `"fungi"`, `"lichens"`), combining each group's "taxon" and "names" files with taxa always
taking priority over names. Writing a query in that source's own `"Genus subg. Subgenusname"`
infrageneric-name syntax is now recognised by `match_taxa()` too (`match_02x`, issue #25), alongside the
zoological/AFD-style `"Genus (Subgenus)"` bracket convention issue #14 already added.

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

`tests/testthat/test-generate_taxadb_taxonomic_reference_list.R` covers
`generate_taxadb_taxonomic_reference_list()`, also entirely offline -- the core reshape/filter tests
run against real data via `taxadb`'s own tiny bundled `"itis_test"` fixture (no mocking needed, since
it's a small subset of ITIS shipped inside the `taxadb` package itself purely for testing purposes),
and the one `country`-filtering test (`provider = "gbif"`) mocks `taxadb::td_create()`/
`taxadb::taxa_tbl()` alongside `rgbif::name_backbone()`/`rgbif::occ_search()` (reusing
`helper-gbif-fixtures.R`'s existing builders for the latter two). Skipped (not counted below) if
`taxadb` isn't installed, since it's a `Suggests`, not an `Imports`, dependency. `gbif_snapshot_url`
(issue #23, see Architecture #1b) is covered both offline -- mocking the internal `gbif_snapshot_tbl()`
directly to prove `taxadb::td_create()`/`taxa_tbl()` are never called, plus a small local parquet file
(written via `duckdb`'s own `COPY ... TO ... (FORMAT PARQUET)`) for the missing-column schema-check
error -- and with one real, live test against the actual source.coop URL, gated the same way
`test-apc_equivalence.R` gates its own live external dependency (`skip_if_offline()`/`skip_on_cran()`).

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

`test-load_NSL_resources.R` covers `load_NSL_resources()` (issue #25's underlying feature -- see
Architecture #4 below) against two small, hand-built National Species List (NSL) taxon/names fixture
pairs (`helper-nsl-fixtures.R`) -- one in the plant-side camelCase-CSV shape, one in the animals
export's pipe-delimited snake_case shape -- entirely offline, no need for the real, much larger
`inst/extdata/Australian_*/` files. Covers the taxa-take-priority-over-names combining rule, genus
derivation by rank, the subgenus marker-stripping fix, caching, and a full
`prepare_taxonomic_resources()` → `create_taxonomic_update_lookup()` run including a marker-form
subgenus query (`match_02x`, see Architecture #2 below).

559 expectations, all passing as of the last `devtools::test()` run in an environment with `taxadb`/
`duckdb`/`APCalign` installed and network access available (this now includes both
`test-apc_equivalence.R`'s live tests and `gbif_snapshot_url`'s one live test against the real
source.coop file below -- neither skips under a plain `devtools::test()` run when those conditions
hold, `skip_on_cran()` included, since `devtools::test()` sets `NOT_CRAN` itself). The offline-only
subset (skip anything needing `taxadb`/`APCalign`/network) is smaller; re-run without those to get an
exact count if you need one. (See Architecture #2 below for a fuzzy-matching gotcha this fixture data
has to dodge.)

`test-apc_equivalence.R` (issue #10) is one exception to "no network, no APCalign-package-data
download" above -- it needs a real, live `APCalign::load_taxonomic_resources()` snapshot to compare
against, so it's skipped unless `APCalign` is installed, network access is available, and it isn't
running under `R CMD check --as-cran` (both true in the environment the 559 figure above came from,
so it's already folded into that count there, not a separate add-on). This has also failed
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

### 1b. taxadb-backed reference list builder — `R/generate_taxadb_taxonomic_reference_list.R` (active, exported)

Companion to the function above, for the case that function's own docs now explicitly say it's *not*
suited to: a genuinely large clade (a phylum, a large class). Sources from
[taxadb](https://docs.ropensci.org/taxadb/) (rOpenSci) — a package that already downloads and locally
caches versioned, pre-built snapshots of several major taxonomic authorities (`gbif`, `itis`, `col`,
`ncbi`, `ott`, `iucn`, and some less-actively-maintained ones — see `taxadb::td_create()`'s own docs
for the current list), backed by DuckDB + parquet. Filtering to a taxon group (`generate_taxadb_taxonomic_reference_list(taxon_name, rank, provider)`)
is then an ordinary local database query regardless of how large the group is — no pagination limit,
no recursive splitting, no retry/timeout engineering needed, at the cost of the snapshot being up to a
few months stale rather than live (taxadb's own docs: snapshots are semi-annual). Investigated and
implemented per [issue #19](https://github.com/traitecoevo/taxonAlign/issues/19).

- **Measured, not just theorised, how close taxadb's GBIF snapshot actually is to a live fetch --
  and the first-pass explanation for the gap found was wrong.** Ran both
  `generate_GBIF_taxonomic_reference_list()` (this session's own, independently-fetched AU
  invertebrate reference, 358,496 rows across 28 phyla) and `generate_taxadb_taxonomic_reference_list()`
  (the same 28 phyla, `provider = "gbif"`, `country = "AU"`) and compared exact GBIF usageKeys (both
  sources use the same raw key -- ours bare, taxadb's `"GBIF:<key>"`-prefixed, so this is a precise
  key-set comparison, not just a name comparison). Result: **85.2% agreement overall (Jaccard),
  93.0% restricted to accepted names only** -- emphatically not "near perfect", and rightly challenged
  as such rather than accepted at face value.
  - **First hypothesis (wrong, but checked rather than assumed): duplicate/reassigned GBIF backbone
    keys for the same name.** A real, known GBIF quirk -- confirmed a handful of real cases (e.g.
    `"Nephthyidae"`/`"Ambo"` appearing on *both* "only in one side" lists under different keys) -- but
    only ~2-6% of the mismatches, not the main driver.
  - **Second hypothesis (also wrong): taxadb's GBIF provider has inherently thinner synonym
    coverage than the live API.** This is what got written up and reported *before* the actual root
    cause was found -- a real mistake, caught only because the resulting numbers were challenged
    directly rather than accepted as "a reasonable-sounding trade-off". Investigating *why* named
    records were missing (not just counting them) led to the real answer:
  - **Actual root cause: taxadb's cached "gbif" snapshot is stuck at version `"22.12"`
    (December 2022)** -- confirmed directly via `taxadb:::latest_version()` (returns `"22.12"`) and
    `taxadb:::available_versions()` (returns `"22.12"` for *every* provider it lists, not just
    `"gbif"` -- the whole package's underlying data pipeline appears to have stopped publishing new
    snapshots around that date, not something scoped to one provider). At the time this was measured
    (2026), that's roughly **four years stale**, not the "semi-annual" cadence taxadb's own
    `data-sources` vignette claims. Four years of new species descriptions, added synonyms, and
    backbone reclassifications for an actively-studied group like invertebrates plausibly explains a
    gap this size on its own, without needing "taxadb's methodology is less complete" as an
    explanation at all.
  - One phylum, `"Entoprocta"`, has zero rows under that exact name in taxadb's snapshot at all --
    plausibly a downstream symptom of the same staleness (a classification change since Dec 2022) or a
    genuine flattening difference; not separately resolved. Negligible in scale (78 rows in the live
    fetch either way).
  - **Practical implication, corrected**: don't recommend `generate_taxadb_taxonomic_reference_list()`
    as a reliably-current alternative to a live fetch right now -- its usefulness depends entirely on
    whether taxadb's maintainers resume publishing snapshots, which is outside this package's control.
    It may still be the right tool when a somewhat-stale worldwide slice is an acceptable trade for
    speed/reliability on a huge clade, but that trade-off is now known to be "up to ~4 years stale",
    not "up to a few months" -- say so plainly wherever this function is recommended, and don't soften
    it into a smaller-sounding caveat next time real numbers look wrong. Worth periodically re-checking
    `taxadb:::available_versions()` in case this changes.
  - **The raw ~15% dataset-level gap and the *practical* impact on a real alignment are two different
    numbers, and both are worth reporting together.** Ran the real, full AusInvertTraits name list
    (5,154 names) through `create_taxonomic_update_lookup()` twice -- `AFD + our own live-fetched
    GBIF` vs. `AFD + the taxadb-sourced equivalent`, same 28 phyla -- and compared `aligned_name`
    directly, not just raw usageKeys. Result: **5,143/5,154 (99.79%) identical; only 11 names
    differ**, and all 11 are cleanly explained by the same staleness cause, never the reverse (taxadb
    never resolved something the live fetch didn't): two species (`"Onthophagus bulga"`,
    `"Trioza melaleucae"`) and two genera (`"Austrocardiophorus"`, `"Trachytetra"`, the latter across
    6 rows) that the live fetch has and taxadb's snapshot doesn't. This isn't a contradiction of the
    85.2%/93.0% figures above -- it reconciles cleanly: AFD is checked first and resolves the large
    majority of names on its own, so only a small residual set of names ever reaches GBIF at all, and
    only a fraction of *that* residual happens to fall inside taxadb's specific staleness gap. Don't
    report the raw dataset-level comparison alone as "how bad is taxadb" without also checking what it
    actually costs on a real alignment task -- they can (and here do) tell very different stories.

- **`country` filtering is still GBIF-API-only**, not something `taxadb` can supply for *any*
  provider — `taxadb` has no occurrence data at all, only taxonomic backbone data. So `country` is
  only accepted when `provider = "gbif"`, and even then it's answered by reusing
  `resolve_gbif_taxon()`/`fetch_gbif_country_keys()` (the exact same internal helpers
  `generate_GBIF_taxonomic_reference_list()` already uses for its own `country` argument) rather than
  duplicating that logic — one small, live GBIF API call to resolve `taxon_name`'s key and one
  occurrence-facet query, on top of the otherwise-fully-local taxadb query.
- **A real bug found in `taxadb::filter_rank()` while investigating this (confirmed directly, not
  assumed from docs)**: `rank = "order"` throws a genuine DuckDB parser error
  (`"Parser Error: syntax error at or near \"order\""`) — `order` is a reserved SQL keyword, and
  `filter_rank()`'s internals build a raw `WHERE` clause without quoting the column name. Every other
  rank (`kingdom`/`phylum`/`class`/`family`/`genus`) works fine; only `order` collides. Not reported
  upstream yet. Worked around here by not depending on `filter_rank()` at all — this function queries
  `taxadb::taxa_tbl(provider)` directly via an ordinary `dplyr::filter()`, which goes through
  `dbplyr`'s own identifier-quoting and doesn't hit the bug, confirmed working for `"order"` too.
- **taxadb's schema has no separate authorship field** — confirmed against its own `taxonID`/
  `scientificName`/`acceptedNameUsageID`/... Darwin Core schema (identical across every provider,
  the whole point of `taxadb`'s normalisation) and directly against real data (`taxadb`'s own tiny
  bundled `itis_test` fixture, used for this package's own offline tests). `scientific_name` and
  `canonical_name` are therefore identical in this function's output, unlike
  `generate_GBIF_taxonomic_reference_list()`'s, where `scientific_name` includes authorship.
- **`taxonID`/`acceptedNameUsageID` are `"<PROVIDER>:<integer>"`-prefixed strings** (e.g.
  `"GBIF:2440935"`), confirmed against `taxadb`'s `data-sources` vignette and real `itis_test` data --
  `strip_taxadb_gbif_prefix()` strips this specifically for the `country`-filtering step, which needs
  the bare GBIF usageKey to compare against `fetch_gbif_country_keys()`'s result and to pass to
  `resolve_gbif_taxon()`'s underlying `rgbif` calls. The final output keeps the prefixed string form
  as `taxon_ID` (consistent with `taxadb`'s own convention, and harmless for combining with other
  sources since `prepare_taxonomic_resources()` already normalises `taxon_ID` to character regardless
  of the source column's type).
- **Investigated, and deliberately not (yet) used, as a way to shrink or replace this package's own
  bespoke GBIF pagination engineering**: `taxadb`'s own `gbif` snapshot could in principle make much of
  `fetch_gbif_taxon_tree_by_children()`'s recursive-splitting logic unnecessary for large clades, since
  the whole point is that `taxadb` already did that heavy lifting once, centrally, rather than every
  user re-paginating GBIF's live API themselves. This is *why* `generate_taxadb_taxonomic_reference_list()`
  exists as a genuine alternative, not a niche extra option — but `generate_GBIF_taxonomic_reference_list()`
  itself is deliberately left as-is (not rewritten to use `taxadb` internally) since it's still the
  right tool for a small clade needing a live, up-to-the-moment fetch, and this session's own real,
  independently-fetched worldwide GBIF invertebrate reference (Architecture #1's own numbers) remains
  useful precisely *because* it was fetched independently — a live cross-check against `taxadb`'s
  snapshot, not a redundant duplicate of it.
- **`taxadb` is a `Suggests`, not an `Imports`, dependency** — this function is the only thing in the
  package that needs it, guarded by an explicit `requireNamespace()` check with an install hint, so a
  user who never calls this function never needs to install `taxadb` (and its own heavier dependency,
  DuckDB) at all.
- **`gbif_snapshot_url` (issue #23, implemented): bypasses `taxadb`'s own frozen registry entirely for
  `provider = "gbif"`.** Following up directly with the maintainer (`cboettig`) on
  [ropensci/taxadb#123](https://github.com/ropensci/taxadb/issues/123) turned up something actionable:
  current-year GBIF snapshots are uploaded as raw Darwin-Core parquet files to `source.coop` well
  before they're wired into `taxadb`'s own `td_create()`/`taxa_tbl()` registry (which stays frozen at
  `"22.12"`, confirmed again directly via that registry's own GitHub commit history — one commit,
  2022-12-20, unchanged — even after the maintainer reported updating "his underlying files"; that
  update is real, but it's the source.coop parquet, not the R package's registry). `gbif_snapshot_url`,
  when supplied, queries that parquet URL directly instead — confirmed against real names known
  missing from the frozen `"22.12"` snapshot (`"Trachytetra"` + 5 species, `"Onthophagus bulga"`,
  `"Trioza melaleucae"`, `"Austrocardiophorus"`): all four now resolve via this path.
  - `gbif_snapshot_tbl()` (`@noRd`) does the actual work: opens/reuses `taxadb::td_connect()`'s own
    cached `duckdb` connection (an *exported* function -- deliberately not `taxadb:::duckdb_view()`,
    to avoid depending on an internal implementation detail that could change without notice and the
    `R CMD check` NOTE a `:::` call to another package triggers), creates a `CREATE VIEW IF NOT
    EXISTS` over the URL via `read_parquet()` (httpfs auto-installs/loads for an http(s) path in
    current DuckDB, but installed explicitly here too rather than relying on that default), and
    returns an ordinary lazy `dplyr::tbl()` -- so every downstream step in
    `generate_taxadb_taxonomic_reference_list()` (rank filtering, `include_synonyms`, `country`
    filtering, the final `transmute()`) works completely unchanged regardless of which source fed it.
    View names are keyed by a short hash of the URL so two different snapshot URLs used in the same
    session don't collide.
  - **Schema stability here isn't a guarantee `taxadb` itself is making** -- the maintainer's own
    caveat when confirming the upload ("I haven't had a chance to update the taxadb bindings
    themselves or verify we don't have breaking changes") -- so `gbif_snapshot_tbl()` explicitly checks
    the expected columns (`taxonAlign_gbif_snapshot_required_cols`) are present and errors clearly,
    naming what's missing, rather than failing confusingly deep inside the final `transmute()` if a
    future snapshot's schema drifts. A column being *renamed* rather than dropped could still slip
    through undetected -- not fully guarded against.
  - Deliberately **opt-in, not the default** -- passing nothing still uses `taxadb`'s own (stale)
    registry, unchanged from before this was added. `country` filtering, rank filtering (including the
    `order`-reserved-keyword case, confirmed unaffected -- `rank = "order"` against the real 2026
    snapshot returns 767,547 rows via ordinary `dplyr::filter()`), and `include_synonyms` all work
    identically whether the source is `taxadb`'s registry or a direct snapshot URL.
  - `duckdb`/`DBI` added to `DESCRIPTION`'s `Suggests` (both already transitive dependencies of
    `taxadb` itself, so no new install burden for anyone who already uses this function).
  - Test coverage: mocks `gbif_snapshot_tbl()` directly (a same-package internal function, so no
    `.package =` needed) to prove the bypass-taxadb assertion and exercise the full reshape pipeline
    offline; a small local parquet file written via `duckdb`'s own `COPY ... TO ... (FORMAT PARQUET)`
    covers the missing-column schema-check error, also offline; one real, live test against the actual
    source.coop URL (skipped unless online/not on CRAN, same gating `test-apc_equivalence.R` uses for
    its own live external dependency) confirms `"Trachytetra"` resolves for real, not just against a
    mock.

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
- **Seven real bugs found by testing against real, messy data** (not just the hand-built fixture) that
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
  - Discovered combining AFD with a real, 358k-row GBIF-derived AU-invertebrate reference: `taxon_ID`
    columns from different sources can have different underlying types (AFD's own UUID strings vs.
    `generate_GBIF_taxonomic_reference_list()`'s raw integer GBIF `usageKey`), and `prepare_taxonomic_resources()`'s
    multi-table `dplyr::bind_rows()` step ran *before* the existing `as.character()` normalisation, not
    after -- `bind_rows()` errors outright on a cross-table type mismatch ("Can't combine
    `..1$taxon_ID` <character> and `..2$taxon_ID` <integer>") rather than coercing it, so combining any
    two tables with different `taxon_ID` types failed immediately, regardless of what the later
    single-table normalisation would have fixed. Fixed by normalising each table's `taxon_ID`/
    `accepted_name_usage_ID` to character individually, before they're combined.
  - Also discovered combining AFD with the same real GBIF-derived reference: two further real,
    large-scale versions of "a genuinely non-taxonomic extra column gets scanned by the higher-rank
    row-synthesis feature", not just theoretical risks that feature's own design comment already flags.
    (1) `generate_GBIF_taxonomic_reference_list()`'s own `scientific_name_authorship` column (an extra
    column beyond the required 8) was being scanned like any other character column, turning every
    distinct author-citation string in it (e.g. `"Plisko, 1965"`) into its own bogus "taxon" at a
    fictional rank literally named `"scientific_name_authorship"` -- 66,564 such rows (~10% of the
    combined resource) in that real case. Fixed via `taxonAlign_non_hierarchy_cols`, a short, explicit
    list of column names known with certainty to never be hierarchy columns because they're metadata
    *taxonAlign's own loaders* always produce (not a user's own arbitrary data) -- excluded from the
    scan regardless of the "scan any extra column" default; extend as further such columns turn up, the
    same "extend, don't guess" convention `taxonAlign_taxon_rank_specificity`/
    `taxonAlign_taxonomic_status_priority` already use. (2) Separately, GBIF's own backbone has a real
    (if unusual) taxonomic convention for an undescribed genus/family/etc. -- a placeholder scientific
    name like `"Genus B JS"` or `"Genus ANIC A"` (ANIC = Australian National Insect Collection) -- and
    GBIF's own `canonicalName` parsing strips the placeholder code, leaving just the bare rank word
    (`"Genus"`, `"Family"`, `"Order"`, `"Tribe"`, `"Subfamily"` were all confirmed present in the real
    data). This collides with a *completely unrelated* convention on the query side: morphospecies
    voucher codes like `"Genus 1 sp.01 Corinnidae"` also use the literal word `"Genus"` as a
    placeholder for "unidentified genus", so the generic higher-rank matcher would confidently but
    wrongly resolve such a query to whichever unrelated placeholder taxon happened to be named just
    `"Genus"`, instead of correctly failing to match at all. Fixed the same way as the NA-`canonical_name`
    case above (dropped, with a warning, generically for any rank via
    `tolower(canonical_name) != tolower(taxon_rank)`) since such a row is equally unmatchable-in-any-
    useful-sense and equally hazardous.
- **Two further real bugs found by directly diffing the same AusInvertTraits name list against two
  different resource combinations (AFD+iNat vs AFD+GBIF) rather than just eyeballing one run**:
  - (Issue #13) `fuzzy_match()` had no concept that a literal rank-category word ("genus", "species",
    "family", "tribe", ...) is never itself a real taxon name -- so a query like
    `"species of Salticidae"` (whose `word_one_stripped` is just the bare word `"species"`) could
    genuinely fuzzy-match a real, unrelated genus (`"Sphecius"`) that happened to be a similarly short,
    same-first-letter string. This is the query-side mirror of the already-existing resource-side guard
    (a GBIF placeholder row named just `"Genus"` is dropped by `prepare_taxonomic_resources()`) --
    fixed by adding the same check at the top of `fuzzy_match()` itself (`match_taxa_helpers.R`), reusing
    `taxonAlign_taxon_rank_specificity` (plus `"species"`, which that vector excludes) as one shared
    rank-word vocabulary for both sides. Scoped to only fire when the *whole* string being matched
    equals a rank word, so ordinary two-word species-binomial fuzzy matching can never be affected.
  - (Issue #14) A **bare** `"Genus (Subgenus)"` query (no species epithet at all) could be
    mis-resolved to an unrelated real species -- e.g. `"Lasioglossum (Parasphecodes)"` resolved
    correctly to subgenus rank against one resource combination, but silently mis-resolved to the real
    species `"Lasioglossum parasphecodum"` against the other. Root cause: `cleaned_name` (from
    `APCalign::standardise_names()` alone) correctly keeps the `"(Subgenus)"` bracket intact, and the
    dedicated bracket-aware blocks use it correctly -- but `stripped_name`/`stripped_name2` (and hence
    `binomial`/`trinomial`/`word_one_stripped`, which every species-level block works off) only strip
    the *parenthesis characters* via `APCalign::strip_names()`, not the bracketed word itself
    (`strip_names("Lasioglossum (Parasphecodes)")` returns `"lasioglossum parasphecodes"`, not
    `"lasioglossum"`). For a bare bracketed name, the subgenus word then sits exactly where a species
    epithet would, and species-level matching -- which used to run well before the old, sole
    bracket-aware fallback (`match_12a`, all the way down at block 12) -- could genuinely find a real,
    unrelated species close enough to it. Not inherited from APCalign "for no reason": `strip_names()`
    exists to scrub *botanical* voucher/manuscript parenthetical annotations, a domain that never
    collides with a real species epithet this way, since botany doesn't write subgenus using the
    zoological `"Genus (Subgenus)"` bracket convention. Fixed by adding a new, early block
    (`match_02y`, right after `match_02a`, well before any species-level block) that quarantines
    *only* the bare, exactly-two-token `"Genus (Subgenus)"` shape -- detected by string shape, not
    resource membership, so a pair absent from `resources$subgenus_v2` (or a resource with no
    `subgenus_v2` table at all) is still safely caught. Tries an exact match against
    `resources$subgenus_v2`, then a fuzzy match (new -- the old fallback had none at all), then falls
    back to the genus part alone via the same shared helper the hybrid/intergrade matching uses
    (`match_special_case_to_genus()`), so an unresolved bracket never reaches species-level matching as
    a fake epithet. Deliberately scoped to *only* the bare two-token case: a genuine
    `"Genus (Subgenus) species"` trinomial (e.g. the nominotypical-subgenus convention
    `"Aporocera (Aporocera) t-viride"`, `test-match_taxa_typos.R`) is already resolved correctly by a
    different, existing mechanism -- `match_11a`/`match_11b`'s `ignore_bracketed_words`, computed
    directly from `original_name` via `stringr::str_remove(original_name, " \\(.*\\)")`, which drops
    the entire `"(...)"` (parens and contents) rather than just the characters -- and the original,
    unconditional-on-trailing-content `match_12a` fallback is kept (now purely as the late safety net
    for a `"Genus (Subgenus) unmatched_epithet"` query, once every species-level block has already had,
    and failed, first refusal), so subgenus-level specificity for that case isn't lost to a genus-only
    fallback either. A related but fragile-not-fixed observation: even for the trinomial case,
    `binomial`/`trinomial` reconstruction is already subtly wrong today (inflated to e.g.
    `"lasioglossum parasphecodes turneri"` instead of the real `"lasioglossum turneri"`) -- it happens
    to still work only because `ignore_bracketed_words` bypasses that reconstruction and goes straight
    to `original_name`.
  - (Issue #15, proposed, not yet implemented) A further, more ambitious idea from the same
    investigation -- an opt-in parameter to strip recognised rank words *and* filler words ("of", "in")
    from a query before matching (turning `"species of Salticidae"` into a match attempt on
    `"Salticidae"` alone, with the full original string still preserved in the aligned name's `"[...]"`
    suffix) -- deliberately deferred pending design discussion (filler-word vocabulary, where in the
    match sequence it runs, interaction with `include_bracketed_info`'s bare-match logic once words are
    dropped rather than bracketed).
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
  supply-order with no prompt. **Each table's `taxon_ID`/`accepted_name_usage_ID` is normalised to
  character *before* that `bind_rows()`, not after** -- found necessary combining AFD (character UUID
  strings) with a `generate_GBIF_taxonomic_reference_list()`-derived table (integer `taxon_ID`, its own
  raw GBIF usageKey): `dplyr::bind_rows()` errors outright on a type mismatch across the tables being
  combined ("Can't combine `..1$taxon_ID` <character> and `..2$taxon_ID` <integer>") rather than
  coercing, and the existing single-table `as.character()` normalisation (kept for the interactive-input
  path) ran only *after* this combine step -- too late to prevent the crash. A table missing no required columns is never interrupted, even in
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
  bogus rows if included -- confirmed in practice, not just theoretically: combining AFD with a real,
  358k-row GBIF-derived reference produced 66,564 bogus rows (~10% of the combined resource) from
  `generate_GBIF_taxonomic_reference_list()`'s own `scientific_name_authorship` column, each turning an
  author-citation string (e.g. `"Plisko, 1965"`) into its own fictional "taxon" at a rank literally
  named `"scientific_name_authorship"`. Fixed for this specific, known case via
  `taxonAlign_non_hierarchy_cols` -- a short, explicit list of column names known with certainty to
  never be hierarchy columns because they're metadata *taxonAlign's own loaders* always produce (not a
  user's own arbitrary data), excluded from the scan regardless of the "scan any extra column" default.
  Extend this vector as further such columns turn up, the same "extend, don't guess" convention
  `taxonAlign_taxon_rank_specificity`/`taxonAlign_taxonomic_status_priority` already use -- a user's own
  arbitrary extra column is still scanned exactly as before; this only ever grows with columns taxonAlign
  itself is responsible for producing. This generalises, inside `prepare_taxonomic_resources()` itself, the same idea
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
    (`aff.`/`affinis`/`cf.`) -- since they're rarer than hybrids and share the same shape. Intergrade and
    indecision are `match_04a` (exact genus)/`match_04b` (fuzzy genus)/`match_04c` (unresolved)/`match_04d`
    (no genus-rank reference); the affinis/cf. family is `match_04e`-`match_04j` (see the next bullet --
    it isn't quite the same shape). The `affinis` detection specifically needs `APCalign::standardise_names()`
    from a version including [upstream commit a2c43d1](https://github.com/traitecoevo/APCalign/commit/a2c43d1fbec29c68aec7bfd4fd46b831effccec3)
    or later (`remotes::install_github("traitecoevo/APCalign")` to pull latest `main`) -- older versions
    unconditionally abbreviate `" affinis "` to `" aff. "` regardless of what follows, which defeats the
    rank-marker-aware check needed to tell a genuine specific epithet (`"Gomphrena affinis subsp.
    pilbarensis"`) apart from an affinity qualifier (`"Acacia affinis dealbata"`) -- the same
    negative-lookahead regex (`not_before_rank_marker`) is also ported into `match_taxa()`'s own
    detection, but it's only reachable if `standardise_names()` hasn't already collapsed the distinction
    upstream.
  - **(Issue #16) The affinis/cf. family checks for a real, exact species-level match *first*, before
    ever falling back to genus** -- unlike intergrade/indecision, which have no equivalent step, because
    "affinis" has a problem "--"/"/" don't: it's also a common, real specific epithet in its own right,
    so a *repeated* bare epithet (`"Themognatha affinis affinis"`, the zoological tautonym convention
    for a nominotypical subspecies) is genuinely indistinguishable from the qualifier reading by text
    shape alone -- `APCalign::standardise_names()` abbreviates the first `"affinis"` to `"aff."`
    regardless, since there's no explicit rank-marker word for the `not_before_rank_marker` lookahead to
    catch. Found via a real validation run comparing two resource combinations on the same name list:
    a genuinely accepted tautonymous subspecies was being discarded to genus rank purely on the
    affinis/cf. text pattern, before exact species matching (`match_05`/`match_09`/`match_10`/`match_11`,
    all later in the file) ever got a chance to prove the name was real. Deliberately **not** fixed by
    guessing "a repeated word means a tautonym" -- that would be wrong in the opposite direction, silently
    upgrading a genuine, deliberately uncertain hedge into a false, over-confident subspecies match --
    and deliberately **not** fixed by simply moving the affinis/cf. detection to run after those later
    exact blocks either, which was the first fix attempted and broke a real APC-equivalence-test case
    (`test-apc_equivalence.R`): `match_09`/`match_10`'s trinomial/binomial exact matching is truncated to
    the first 2-3 words of the *already-abbreviated* `stripped_name2`, and real reference data can have
    its own informally-named placeholder entries using the same "sp. aff. X" convention -- a real APC
    entry, `"Acacia sp. aff. rigens (Gerang Gerung)"`, reduces to the same truncated `"acacia aff"`
    binomial as *any* fabricated `"Acacia aff. <anything>"` query once stripped, so a truncated exact
    "match" there is coincidence, not evidence the query is a real, listed name. Fixed instead by adding
    `match_04e`/`match_04f` -- an exact check the affinis/cf. block performs *itself*, at its own early
    position, using the same *untruncated* field `match_11a`/`match_11b` use (`ignore_bracketed_words`,
    built straight from `original_name`, never touched by the "aff." abbreviation) -- so it doesn't
    depend on running after any other block at all. `match_04g`-`match_04j` (exact genus/fuzzy genus/
    unresolved/no genus resource) is the unchanged genus-only fallback for whatever's left once that
    exact check has failed -- i.e. a genuine hedge that isn't also a real, listed name, the overwhelming
    majority case, resolves exactly as before.
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

- **Fuzzy higher-rank matching defaults to broadest-first, unlike exact matching (issue #12)** --
  found via a real, large validation (AFD + a real GBIF-derived AU-invertebrate reference, against the
  full real AusInvertTraits name list): 52% of names resolved via a fuzzy higher-rank match
  (`match_02c`/`match_12c`) *also* fuzzy-matched a real candidate at a *different* rank than the one
  actually resolved to. The large majority of these weren't coincidence: real invertebrate
  morphospecies/voucher codes commonly use an informal English vernacular adjective form derived from a
  family/subfamily/superfamily root (e.g. `"Melolonthine BF01 Heteronyx"`, `"Coccinellid BF01"`,
  `"Dynastine BF01"`), which by convention signals that broader group, not any specific genus --
  but most-specific-first ordering (the same order used for *exact* matching, where cross-rank
  collisions are rare) was resolving nearly all of them to a coincidentally-similar but unrelated
  **genus** instead. `taxon_ranks_to_check_fuzzy` (`match_taxa.R`) is the broadest-first reverse of
  `taxon_ranks_to_check`, used only by `match_02c`/`match_12c` -- `match_02b`/`match_12b` (exact
  matching) keep the original most-specific-first order, since there's no evidence exact matching has
  the same problem. Genus-before-subgenus is preserved even under this reversal (swapped back into
  place after the `rev()`) -- that exception is a guaranteed nomenclatural convention (a nominotypical
  subgenus sharing its genus's own name), not a coincidental fuzzy collision, so it stays put
  regardless of which direction the rest of the order runs.
- **`consider_english_name_endings` (issue #12, opt-in, default `FALSE`)** -- a further refinement on
  top of the broadest-first fuzzy reordering above. Broadest-first alone isn't always the *most
  precise* fix: for a name like `"Melolonthine BF01 Heteronyx"`, broadest-first fuzzy matching finds
  *some* real candidate within tolerance, but that might land on family when the "-ine" ending
  specifically signals subfamily, if both happen to exist and family is checked first for being
  broader. `match_02z` (new block, placed after `match_02b` so an already-exact-matching name never
  reaches it, and before `match_02c`/`match_12c` so it gets first refusal on both the "ends in `sp.`"
  and generic fuzzy-fallback cases in one place) tries substituting a recognised informal ending for
  its formal Latin equivalent -- `"-id"` -> `"-idae"` (family), `"-ine"` -> `"-inae"` (subfamily),
  `"-oid"` -> `"-oidea"` (superfamily); tribe (`-ini`) and subtribe (`-ina`) endings are already the
  formal Latin form, so no vernacular variant is needed there -- and attempts an **exact** match on the
  corrected name. This is safer than fuzzy matching or reordering alone: it only ever succeeds when the
  corrected name is a real, present taxon (not just textually close to one), and costs nothing when no
  substitution produces a real match -- falls through to ordinary fuzzy matching unchanged. Off by
  default since it's a deliberate, opinionated transformation of the input rather than a pure matching
  refinement.
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
- **`chars_changed` (issue #20, user-requested)**: every one of `match_taxa()`'s ~27 match
  blocks/sub-cases (the 23 numbered blocks plus the four sub-cases inside the shared
  `match_special_case_to_genus()` helper) now also sets `chars_changed` -- `0L` for every exact-match
  block, the real edit distance for every fuzzy-match block, and `NA_integer_` for the
  unresolved/no-resource fallbacks and for a row nothing ever matched. Threaded through
  `align_taxa()`'s initial tibble and both its and `create_taxonomic_update_lookup()`'s `full = FALSE`
  (slim) output column lists, matching the issue's explicit ask that it be retained by both, not just
  present in `full = TRUE`. `update_taxa()` needed no change at all -- it operates via
  `aligned_data |> dplyr::mutate(...)`, which preserves whatever columns `aligned_data` already has,
  so `chars_changed` flows through it automatically as long as `align_taxa()` supplied it (which it
  now unconditionally does).
  - For a fuzzy block, the distance is recomputed via `stringdist::stringdist(query, matched, method =
    "dl")` on the *exact same two strings* that block's own `fuzzy_match()`/`fuzzy_match_column()` call
    already computed a distance for internally (e.g. `stripped_name` vs. `fuzzy_match_cleaned` for
    match_05a, `word_one_stripped` vs. `fuzzy_match_genus` for the genus-level fuzzy blocks) -- not
    reconstructed from some other pair of fields, since `fuzzy_match()` itself only returns the
    matched *string*, not the distance value it internally computed to find it.
  - `match_02z` (the opt-in English-vernacular-ending substitution, e.g. `"Coccinellid"` ->
    `"Coccinellidae"`) reports `0`, not the substitution's own character difference -- it's
    implemented as a deterministic rule-based substitution followed by an *exact* lookup, not a
    `stringdist`-based fuzzy comparison, so `0` is the correct answer under the same "exact vs. fuzzy"
    dichotomy every other block uses, even though the substituted and original strings visibly differ.
- **`match_02a` gained a fuzzy fallback (and a genus-only fallback), matching `match_02y`'s design --
  found via the real `demo-align-Prendergast.qmd` vignette, not a fixture.** `match_02a` (the
  `"Genus (Subgenus) sp."` shape, trailing `"sp."` retained) was, before this fix, exact-only and
  *membership-gated* -- it only ever fired when the bracketed pair was already, verbatim, in
  `resources$subgenus_v2$genus_and_subgenus`. Unlike `match_02y` (the bare, no-`"sp."` sibling, fixed
  under issue #14), it had no shape-based quarantine and no fuzzy fallback, so a genuinely present but
  *misspelled* subgenus fell straight through every remaining block down to the generic higher-rank
  loop (`match_02b`), which strips to `word_one` and matches genus alone -- silently discarding both
  the subgenus and the `"sp."` itself, with no trace anything unusual happened. Real case:
  `"Hylaeus (Rhodhylaeus) sp."` (a 1-letter-missing typo for the real AFD subgenus
  `"Rhodohylaeus"`) resolved only to `"Hylaeus sp."` via `match_02b` -- `alignment_code` gave no hint a
  subgenus had even been attempted. Fixed by adding, right after the existing exact block (same
  `"02a"` letter, new trailing alignment-code suffixes rather than a new letter -- matching how
  `match_02y` itself already uses several suffixes under one letter): a shape-based quarantine (exactly
  three tokens, ending `" sp."`, middle token a complete `"(...)"` bracket -- not membership-gated, so
  it still catches a pair `resources$subgenus_v2` doesn't have at all) that tries an exact match (the
  original block, unchanged), then a **fuzzy** match against the same `genus_and_subgenus` table
  (`match_02a_fuzzy_higher_level_accepted_or_synonym`), then falls back to genus rank via the same
  shared `match_special_case_to_genus()` helper match_02y already uses
  (`match_02a_genus_fallback_exact`/`_fuzzy`/`_unresolved`/`_no_resource`), preserving the original
  bracket+`"sp."` text in the aligned name rather than silently dropping it. A genuine classification
  mismatch (not a typo) is handled correctly by the same genus-fallback path -- e.g.
  `"Lasioglossum (Homalictus) sp."`, where AFD itself treats `"Homalictus"` as its own genus rather
  than a `Lasioglossum` subgenus, resolves to `"Lasioglossum sp. [Lasioglossum (Homalictus) sp.]"`:
  genus rank, with the disputed subgenus visibly preserved for a human to judge, not silently erased.
- **Subgenus written into species-level names: either reference convention, either query
  convention.** AFD's CSV export writes `"Pardalotus (Pardalotinus) striatus"`; NSL/most sources write
  `"Pardalotus striatus"`. Before this fix, a *reference* in the bracketed convention broke plain-binomial
  queries badly (`stripped_canonical`/`binomial` were built from the bracketed form, so
  `"Leioproctus (Leioproctus) lanceolatus"`'s binomial was "leioproctus leioproctus"): `"Leioproctus
  lanceolatus"` fell to genus, `"Pardalotus striatus"` hit a subspecies synonym's binomial. Bracketed
  *queries* were already fine (`match_11a`/`11b` strip `"(...)"` from `original_name`). Fix, user-chosen
  design ("option 2", generic rather than AFD-loader-only): `prepare_taxonomic_resources()` sets
  `display_name` = the name as the reference writes it, then rewrites `canonical_name` for
  species-level rows to the subgenus-free form (`strip_subgenus_from_name()`, `match_taxa_helpers.R`)
  *before* every derived matching key is computed -- so all of `match_taxa()` runs on subgenus-free
  names and needed no changes. Afterwards `align_taxa()` puts `display_name` back into `aligned_name`
  (`restore_display_names()`, keyed on `taxon_ID`, prefix replacement so `"Geobasileus sp."` ->
  `"Acanthiza (Geobasileus) sp."`), and `update_taxa()` reports `accepted_name` from `display_name`.
  Subgenus-rank `display_name` is always `"Genus (Subgenus)"` (user requirement: every subgenus-rank
  output in that form), while `canonical_name` stays the bare subgenus name the plain subgenus-name
  matching and `subgenus_v2` need. `load_NSL_resources()` rebuilds the bracketed form for ICZN
  species-level names from the parent chain (`add_NSL_subgenus()`) so both AFD exports give identical
  output -- verified on 22 real queries, both conventions, both exports. Known behaviour, not changed:
  a query with a *wrong* subgenus (`"Leioproctus (Wrongsub) lanceolatus"`) silently resolves to the
  species under its real subgenus; a matched *synonym* keeps whatever form its reference wrote (NSL
  synonym records have no parent link). Tests: `test-subgenus_conventions.R`.
- **Higher-rank synthesis used to duplicate every explicit row whose rank was capitalised** (found
  while doing the above): `already_present` compared the raw `taxon_rank` (`"Genus"` in NSL exports)
  to the lowercase column name, so 19,347 NSL synonym genera (e.g. *Geobasileus*, a primary synonym of
  subgenus *Acanthiza (Geobasileus)*) got a synthesised *accepted* genus row that outranked the real
  synonym row. Now compared via `APCalign::standardise_taxon_rank()`. Still open (not changed, a design
  question): genus values with *no* explicit row anywhere (NSL 7,443; CSV 12,283, almost all from
  synonym names only, since the CSV export has no genus-synonym records at all) are still synthesised
  as `"accepted"` genera.
- **`match_02x` (issue #25): a second, marker-abbreviation input syntax for the bracketed-subgenus
  concept.** Found loading the new National Species List (NSL) reference data (`load_NSL_resources()`,
  see Architecture #4 below): NSL writes an infrageneric name as `"Genus subg. Subgenusname"` (e.g.
  `"Hygrocybe subg. Cuphophyllus"`), never as the zoological/AFD-style `"Genus (Subgenus)"` bracket
  `match_02a`/`match_02y`/`match_12a` (issue #14) already handle. Without this block, such a query fell
  through to the generic higher-rank loop (`match_12b`), which only ever compares `word_one_stripped`
  (just `"Hygrocybe"`) against `resources$genus$canonical_name` -- silently discarding `"subg.
  Cuphophyllus"` and returning a plain genus-rank match instead of the correct subgenus-rank one.
  `match_02x` is placed right after `match_02a`, before `match_02y` -- same "quarantine early, before
  species-level matching can mis-parse it" position, mirroring `match_02y`'s shape-based (not
  membership-based) detection: exactly three whitespace-delimited tokens, the middle one `"subg."`/
  `"subg"` (case-insensitive). It builds a `"Genus (Subgenusname)"`-equivalent key from the query and
  looks that up against the *same* `resources$subgenus_v2$genus_and_subgenus` table `match_02y` already
  uses -- exact match, then fuzzy match, then the same genus-only `match_special_case_to_genus()`
  fallback -- rather than duplicating that lookup table under a second name. This only works because
  `load_NSL_resources()`'s own loader fix (see Architecture #4) stores the *bare* subgenus name in
  `canonical_name` (e.g. `"Cuphophyllus"`, not the full marker-prefixed string) -- `subgenus_v2`'s own
  construction (`genus_and_subgenus = paste0(genus, " (", canonical_name, ")")`) assumes exactly that,
  the same way it already does for AFD's bare subgenus names.
  - **Scoped to subgenus only.** NSL's own infrageneric rank vocabulary uses this same
    `"Genus <abbrev>. Name"` shape for three further ranks -- section (`sect.`), series (`ser.`, fungi
    only), special form (`f.sp.`, fungi only) -- but none of them have an equivalent `_v2`/bracket-style
    structure in `prepare_taxonomic_resources()` at all (they're just plain higher-rank buckets).
    Extending this treatment to them is a materially bigger, separate change, not attempted here.
  - **Also not attempted**: a genuine trinomial in this syntax (`"Genus subg. Subgenusname species"`,
    an unresolved epithet actually following the marker) has no equivalent to `match_11a`/`match_11b`'s
    `ignore_bracketed_words` mechanism (which strips a real `"(...)"` bracket, contents and all, from
    `original_name` for exactly this purpose on the bracket convention) -- unlikely enough in practice
    (not demonstrated against real data) that it's flagged, not fixed, here.

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
- **AFD's 2026 CSV export (`data/AFD_2026-10-07/Anamalia_all_ranks.csv`) is read by the same
  `load_AFD()`, not a second function** -- checked column-by-column against the old `AFD.csv` first:
  `FULL_NAME` renamed to `VALID_NAME` (renamed back on read), `SUBSPECIES_COUNT_IN_SPECIES`/
  `LAST_MODIFIED`/the distribution columns dropped (none used), still one row per species/subspecies
  despite the "all ranks" filename (no higher-rank rows), Animalia only (now incl. Chordata; no
  protists). Only ~20% of `CONCEPT_GUID`s carry over from the old file, so IDs aren't stable across
  AFD exports. Four new data quirks handled, all also harmless on the old file:
  - `COMPLETE_NAME`/`SYNONYMS` now write changed-combination authorship in parentheses
    (`"Otobothrium curtum (Linton, 1909)"`) -- `strip_afd_authorship()`'s patterns accept an optional
    `(...)`.
  - Multi-author/particle-prefixed citations where only the *last* author is in the `AUTHOR`
    dictionary left debris (`"Gymnothorax griffini Whitley &"`, `"Platydemus manokwari de"`) in ~2k
    synonyms -- `tidy_afd_authorship_debris()` cleans up afterwards (truncate at a capitalised token
    after a lowercase epithet; strip a residual year; strip trailing particles/`&`/commas).
  - Subsequent usages written with `"; "` between name and citation (`"Phalaena inquinalis; Swinhoe,
    1892"`) used to orphan `"Swinhoe, 1892"` as a bogus synonym -- `rejoin_afd_synonym_fragments()`
    re-attaches it (~176 cases new, 6 old). Also dropped: synonyms whose stripped name equals the
    accepted name (a self-reference with different authorship formatting).
  - Two kinds of "Unplaced" row (382 total): `"Unplaced Synonym(s)"` holders (`SPECIES`/`SUB_SPECIES =
    "Unplaced"`, 79) and species awaiting generic placement (`GENUS = "Unplaced"`, `VALID_NAME` e.g.
    `"Unplaced vetula"`, 303). Neither becomes an accepted row; their synonyms (510, for the latter
    usually the original combination, e.g. `"Tinea vetula"`) are kept as self-referential
    `taxonomic_status = "unplaced"` names (mirroring NSL's own "unplaced"). `"Unplaced"`/`"Unplaced to
    Family"` values in hierarchy columns are never turned into higher-rank rows. Stray control
    characters/tabs in names are squished out.
  - `VALID_NAME` keeps the subgenus in brackets (`"Pardalotus (Pardalotinus) striatus"`, 11,183
    accepted sp/ssp), kept as-is in `canonical_name` -- see the "Subgenus written into species-level
    names" bullet in Architecture #2 for how matching/output handle it. 3,305 SYNONYMS entries are just
    the accepted name minus its subgenus (`"Clivina tenuis"` under `"Clivina (Clivina) tenuis"`) and are
    dropped as self-listings (`strip_subgenus_from_name()` comparison).
- **Further CSV-loader fixes from the full name-level reconciliation against the NSL export**
  (`ignore/AFD_export_comparison.R`; goal: every name agrees, or each genuine discrepancy is listed in
  `vignettes/AFD-data-processing.qmd`):
  - `CHANGED_COMBINATION_NAMES` (~15k entries, never read before, in either export version) is now
    read as `taxonomic_status = "Generic combination"` (NSL's label for the same records) via the
    generalised `afd_synonym_rows(afd, column, status, id_suffix)`; a name in both columns is kept
    once, as a synonym.
  - Synonym `taxon_rank` was always `"species"`, so trinomial synonyms claimed a two-word `binomial`
    key in `prepare_taxonomic_resources()` (the real cause of `"Pardalotus striatus"` resolving via
    the synonym *P. s. kingi*). Now `"subspecies"` for 3+ words, ignoring a subgenus.
  - `clean_afd_name_annotations()` strips `[sic]`, leading `?`/`(?)`, whole-name `[...]`, quoted
    manuscript authors and stray quotes; `tidy_afd_authorship_debris()` also strips malformed trailing
    parenthesised authorship (`"(, )"`, `"(Milne Edwards, )"`, `"(1876, Bergh)"`, `"(Turner, 1908))"`,
    unclosed `"(Adams"`); `rejoin_afd_synonym_fragments()` allows a lowercase particle
    (`"; van Eecke, 1925"`).
  - `taxonAlign_taxonomic_status_priority` gained AFD's statuses (objective/primary synonym,
    "synonym", "Generic combination", replacement name, excluded variants) -- unknown statuses sorted
    after `"included"`, so an NSL names-file record could beat a real taxon-file record.
  - Latest full result: 237,885 of 242,163 species-level names identical (incl. 1,792 synonyms of
    more than one taxon, listed identically -- how to report that ambiguity is still open); 40 differ
    (listed in the qmd); 1,453 CSV-only, 2,785 NSL-only (mostly protists/vagrants/missing
    Tortricidae+Temnocephalidae). Not yet clean: ~193 CSV-only and 165 NSL-only still unexplained,
    some still formatting variants (`"Enicospilus? flavivenae"`, `"Carenum cyaneum non"`,
    `"Tinea lactella [Denis"`). `LITERATURE_NAMES` (misspellings/misidentifications as free text,
    CSV-only information) deliberately not read yet.
- **Rounds 2-4 of the AFD format vs NSL format reconciliation** (terminology: the user calls them
  the "AFD format" and the "NSL format" -- both are CSV-style files, so never "CSV export"):
  - `clean_afd_name_annotations()` now also handles uncertainty marks anywhere (`"Genus? sp"`,
    `"(Ceratia ?)"`), square brackets around part of a name (content kept, as NSL does), HTML tags,
    year outside the bracket, unbalanced doubled `"))"` (only when brackets don't balance -- a blanket
    collapse broke genuinely nested ones), and quote marks only at word edges (`strip_name_quotes()`,
    shared with the NSL loader; an apostrophe inside a word, `"d'arci"`, is kept). Accepted names
    (`VALID_NAME`) get the same quote stripping plus trailing `,`/`;` removal (not `.` -- that broke
    every `"Genus sp."` name; caught only because the comparison numbers got *worse*).
  - **Misapplication/part markers become statuses**: `strip_afd_usage_markers()`/`afd_usage_status()`
    read `sensu`, `auct.`/`auctt.`/`auctorum`, `non`/`nec`, `(part)`/`[pars]` -> "misapplied",
    "pro parte synonym", "pro parte misapplied" (added to the priority vector). The NSL format drops
    these markers and labels the same usages plain "synonym" (50 of 58) -- a curator item. The NSL
    loader (`clean_NSL_canonical_names()`) reads the few markers left in NSL canonical names too, but
    only to sharpen a plain "synonym".
  - `strip_subgenus_from_name()` now accepts any bracket content (`"Nassa (Alectryon, Aciculina) x"`).
  - Result (round 4): 238,009 of 241,998 names agree; 23 differ; 1,308 AFD-format-only (all
    explained: Temnocephalidae/Tortricidae, NSL names-file-only, 59 listed); 2,658 NSL-only (Protista,
    vagrants, 38 listed). Remaining one-sided names are mostly NSL `canonical_name` values with
    authorship left in (`"Conus complanatus Sowerby"`), reported, deliberately not "fixed" in the
    loader (user: only discrepancies in *their* lists should remain, so data errors are reported, not
    hidden).
  - **Names leading to more than one accepted name** (1,893): the comparison script now ranks each
    name's records by `taxonAlign_taxonomic_status_priority`. 997 resolve to themselves (accepted and
    also a synonym elsewhere), 54 resolve identically, 295 only via NSL's "primary synonym" vs
    "synonym" (AFD format has only "synonym"), 461 tie in both formats. User's position: without finer
    statuses there's no resolution -- flag ties with the curators (done, full lists in the qmd).
    taxonAlign's matching still silently picks the first record on a tie -- needs a flag in output
    (not yet designed). The placement of "primary synonym"/"synonym"/"Generic combination" in the
    priority vector is our assumption, awaiting curator confirmation (50 outcomes depend only on
    synonym > Generic combination).
- **Names leading to more than one accepted name ("splits") are now handled in `update_taxa()`**
  (`R/resolve_synonym_splits.R`, `build_split_table()`), following APCalign's `taxonomic_splits`
  convention at the user's request: `taxonomic_splits = "most_likely_species"` (default) suggests one
  name as `"X [alternative possible names: Y (status) | Z (status)]"` plus a new
  `alternative_possible_names` column (also in `create_taxonomic_update_lookup()`'s slim output);
  `"collapse_to_higher_taxon"` gives `"Genus sp. [collapsed names: ...]"` when all candidates share a
  genus. Order: status precedence, then (ties) shared epithet, same rank (word count), accepted name
  published no later than the synonym, oldest, then source order -- the last is APCalign's own final
  tie-break and is what keeps `test-apc_equivalence.R`'s "Justicia procumbens" ->
  "Rostellularia adscendens subsp. dallachyi" passing (alphabetical broke it). Epithet/older-than rules
  were chosen by testing against NSL's own resolutions (99%/93% agreement; "oldest" 57%, "newest"
  40%). Skipped when matched with authorship (`alignment_code` contains "with_authorship", e.g.
  homonyms), and for a species listed under its own nominotypical subspecies. **User's position:**
  remaining ties are curator data problems (467 are ties within the NSL format itself; the 295
  AFD-format-only ties vanish once the AFD publishes only the NSL format) -- the tie-break rules are a
  stopgap, don't keep refining them. 1,709 of 1,893 such names now get the same suggestion from both
  formats.
- **Real-name-list test done** (2026-10-07): the full AusInvertTraits name list
  (`ignore/AusInvertTraits_taxonomic_updates.csv`, 5,154 names) aligned against each format separately
  -- 5,116 (99.3%) get the same `suggested_name`; the 36 distinct names that differ are all explained
  and listed in `vignettes/AFD-data-processing.qmd`'s "Test against a real name list" (genus-level
  synonymy the AFD format lacks, subgenus placement disagreements, NSL-only names, fuzzy matches to
  names in neither). Scratch scripts for it are not in the repo; the run takes ~10 min. Fixes it
  forced: (1) `match_02b` required exactly two spaces, so every plain `"Genus sp."` skipped exact
  matching (APCalign's own rule is one space) -- now one or two; (2) splits (`build_split_table()`)
  narrowed, at the user's insistence, to species/infraspecific *synonyms* leading to 2+ accepted taxa
  only -- accepted names, genera and authorship matches never go through it ("don't go down rabbit
  holes with splits"); (3) `prepare_taxonomic_resources()`'s higher-rank synthesis: a value seen on an
  accepted row is accepted; a value seen only on synonym rows becomes a *synonym* of the accepted
  value(s) its rows lead to (e.g. genus "Conoderus" -> "Monocrepidus"; one synonym row per target);
  only an orphan with no links is "unplaced" (user: "synonyms should not be called unplaced... an
  unplaced name is a dead end"); bare rank words ("Genus") are never synthesised, and "Genus A"-style
  rank-word + placeholder-code names are dropped (narrowly -- APC phrase names like "Genus sp. Yalgoo
  (...)" are real); (4) the AFD loader treats "Incertae sedis" as a placeholder like "Unplaced".
  NSL's 675 genus records pointing to their own nominotypical subgenus (*Acritus* -> *Acritus
  (Acritus)*) are a curator question, not something to interpret.
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

### 4. Australian National Species List (NSL) reference loader — `R/load_NSL_resources.R` (active, exported; internal helpers `@noRd`)

`load_NSL_resources(taxon_group, ...)` reads/reshapes the [National Species
List](https://www.anbg.gov.au/chah/nsl/)'s per-group export pairs -- `"animals"`, `"algae"`,
`"bryophytes"`, `"fungi"`, `"lichens"` -- into taxonAlign's
flat, `prepare_taxonomic_resources()`-ready schema. Complements `load_taxonomic_resources()`/
`generate_GBIF_taxonomic_reference_list()` the same way, for this source, but is a **standalone
exported function**, not wired into `load_taxonomic_resources()`'s `"AFD"`/`"APC"` switch -- it takes
one group at a time and returns a flat tibble directly (mirroring
`generate_GBIF_taxonomic_reference_list()`'s own contract), so combining several groups is just
`prepare_taxonomic_resources(list(load_NSL_resources("fungi"), load_NSL_resources("lichens")))`, the
same pattern as combining any other two sources. Revisit folding it into `load_taxonomic_resources()`'s
registry if that starts to feel like the wrong split in practice.

- **Two files per group, taxa always taking priority over names.** Each group ships as a *pair* of
  CSVs under `inst/extdata/Australian_<group>/`: a "taxon" file (one row per taxon concept, with real
  synonym-to-accepted resolution via `acceptedNameUsageID`) and a "names" file (a broader name-level
  index, including names never promoted to a full taxon concept, but carrying no
  `acceptedNameUsageID` of its own at all). Confirmed empirically, not assumed: every taxon-file row's
  `scientificNameID` is also present in the names file (100% overlap across all four groups checked),
  i.e. the names file is a strict superset at the name level. `load_NSL_resources()` combines them by
  dropping, from the names file's contribution, every row whose `scientificNameID` already appears in
  the taxon file, then binding taxon rows first -- so a name never enters the combined result twice,
  and the taxon file's real synonymy always wins over the names file's self-referential (no-forward-
  link) version of the same name. This mirrors how iNat's hardcoded `"accepted"` status is described
  elsewhere in `development-history.qmd`: the names file can only *widen* coverage, never resolve a
  synonym.
  - Files are located by filename *substring*, not a fixed prefix-to-group map (`find_NSL_file()`
    matches `"-taxon-"`/`"-names-"` in the basename) -- the raw export's own prefix varies per group
    (`AAL`/`AFL`/`ALC`/`CAB` for taxon; `AANI`/`AFNI`/`ALNI`/`ABNI` for names) but this substring
    doesn't, so this generalises automatically to a group not yet seen, including `"animals"`.
- **`genus` comes from two different places depending on the file**, since only the names file has a
  dedicated column for it: the names file's own `genericName` (blank whenever not applicable, `NA`'d
  via `dplyr::na_if()`); the taxon file has no equivalent column at all, so `genus` is derived via the
  existing `extract_genus()` helper (`match_taxa_helpers.R`) on the *raw* `canonicalName` -- NSL's own
  convention always prefixes an infrageneric/infraspecific name with its governing genus (e.g. the
  subgenus `"Agaricus subg. Homophron"`, the species `"Scutellinia badioberbis"`), so taking the first
  word recovers it correctly for genus rank and everything narrower. `genus` is forced to `NA` for
  family rank and broader (`taxonAlign_NSL_above_genus_ranks`, a small explicit list covering the
  botanical `"division"`/`"subdivision"` terminology this data uses that
  `taxonAlign_taxon_rank_specificity` doesn't, plus a real spelling quirk seen in the raw algae export,
  `"Subphyllum"`) -- a bespoke list rather than reusing `taxonAlign_taxon_rank_specificity`, since that
  vector is tuned to AFD/GBIF/APC's own rank vocabulary, not NSL's.
- **Subgenus rank needs one further correction, on top of `genus`**: NSL's `canonical_name` for a
  subgenus is the *full* `"Genus subg. Subgenusname"` string, not the bare subgenus name AFD's own
  convention uses (bare `"Podosemum"` alongside `genus = "Boronia"`) --
  `prepare_taxonomic_resources()`'s `subgenus_v2` construction
  (`genus_and_subgenus = paste0(genus, " (", canonical_name, ")")`) assumes the latter, so left
  unstripped it produces a doubled, unmatchable key (`"Hygrocybe (Hygrocybe subg. Cuphophyllus)"`).
  `strip_NSL_subgenus_marker()` strips the `"Genus subg. "` prefix down to the bare name for
  subgenus-rank rows specifically, in *both* files, applied after `genus` is already derived from the
  unstripped name (order matters -- `extract_genus()` needs the genus to still be the name's own first
  word). Recognising `"Genus subg. Subgenusname"` itself as an alternate *input* syntax when matching a
  query (rather than just fixing the resource side) is the other half of this, `match_02x` in
  `match_taxa.R` -- see Architecture #2 above and issue #25.
- **`taxonomic_dataset` is read straight off each row's own `datasetName` column** (e.g. `"AFL"` for
  fungi's taxon-file rows, `"AFNI"` for its names-file rows) rather than one hardcoded label for the
  whole group -- lets the two files within one group still be told apart in output (e.g.
  `align_taxa()`'s `taxonomic_dataset` column), consistent with how they're genuinely two different
  underlying datasets even though loaded together.
- **Caching**: keyed by *both* files' combined size/mtime (not a time-based window), the same
  size/mtime-keying convention `load_taxonomic_resources("AFD")` uses and for the same reason -- a
  local file lets a content change be detected directly, without the user needing to remember
  `refresh_cache = TRUE`.
- **Testing now vs. the planned release scheme (issue #24)**: `path` defaults to the bundled
  `system.file("extdata", paste0("Australian_", taxon_group), package = "taxonAlign")`, which resolves
  correctly under `devtools::load_all()` even though these folders are currently untracked in git (not
  yet part of the release scheme issue #24 is still planning) -- override `path` once these files are
  served from elsewhere (e.g. a downloaded, versioned GitHub release) instead of being bundled
  in-package. No download mechanism is implemented yet; that's issue #24's own scope, not this
  function's.
- **The `"animals"` export (AFD's own NSL export, `data/AFD_NSL_export_20260929/`) differs in shape,
  not concept, from the plant-side groups**: pipe-delimited `.txt`, snake_case columns, `_taxon_`/
  `_name_` filename markers. `read_NSL_file()` sniffs the delimiter from the header and
  `standardise_NSL_column_names()` converts camelCase to snake_case, so every reshaping step sees one
  schema; `find_NSL_file()` matches `[-_]taxon[-_]`/`[-_]names?[-_]`, `.csv` or `.txt`. Three further
  animals-specific differences:
  - Subgenus canonical names use the zoological `"Acanthiza (Geobasileus)"` form, not `"subg."` --
    `strip_NSL_subgenus_marker()` handles both.
  - The taxon file's `generic_name` is the *accepted* name's genus (a synonym under a different genus
    gets the wrong one), so genus is still derived from the name itself; `derive_NSL_genus()` also
    masks any single-word non-genus-rank name (zoological "Section" is above genus, botanical
    "sect." below) and the zoological ranks added to `taxonAlign_NSL_above_genus_ranks` (cohort,
    infra-/parv-/subter- ranks, "Higher Taxon", "Generic Aggregate" -- written `"Subtribe Clerina"`).
  - Excluded/vagrant/intercepted taxa (`taxonAlign_NSL_non_synonymy_statuses`) point
    `accepted_name_usage_id` at their *parent* genus/family (e.g. vagrant `"Pernis ptilorhynchus"` ->
    `"Accipitridae"`), so `update_taxa()` would "update" a valid species to a family -- made
    self-referential instead. The plant-side groups' "excluded" rows were already self-referential.
- **Independent cross-check of the two AFD formats** (the reason both loaders exist -- the user's
  stated goal is an independent check that the AFD team transferred data between formats correctly).
  Comparing `load_taxonomic_resources("AFD", path = <2026 CSV>)` against
  `load_NSL_resources("animals", ...)`, subgenus brackets removed from both sides' names first:
  accepted species/subspecies 129,749 shared, 345-350 CSV-only, 1,821 NSL-only (1,820 of those are
  Protista, which the CSV export doesn't include). Synonymy: 96,539 synonym names in both, 96,538
  resolving to the same accepted name (the one exception, `"Bathypallenopsis oscitans"`, is two
  different usages of the same name that NSL only partly carries). **Real transfer gaps found in the
  NSL export**: Temnocephalidae entirely missing (90 spp., 13 genera), and 32 Tortricidae genera
  (244 spp., e.g. *Epiphyas*, *Homona*, *Adoxophyes*) missing -- worth reporting to the AFD team.
  All of this (every transformation, with exact counts, plus a numbered list of data issues to raise)
  is written up for the AFD curators in `vignettes/AFD-data-processing.qmd` (same not-a-formal-vignette,
  `eval: false`, render-directly treatment as `development-history.qmd`) -- keep it in sync if either
  loader's rules change, since it's the record of "exactly what work is being done" that the user
  reports back to the curators. The curators already acknowledge that `CONCEPT_GUID` isn't stable
  across exports. Both raw exports currently live under `data/`, which isn't where R expects raw files (`data/` is for
  `.rda` datasets; `R CMD check` will complain) -- pass `path` explicitly until issue #24's release
  scheme settles where they go.
- Test coverage: `tests/testthat/test-load_NSL_resources.R` covers the combining rule, genus
  derivation, the subgenus-marker fix, caching, and a full `prepare_taxonomic_resources()` →
  `create_taxonomic_update_lookup()` run, against a small, hand-built NSL-*shaped* fixture pair
  (`helper-nsl-fixtures.R`) -- entirely offline, no need for the real, much larger
  `inst/extdata/Australian_*/` files.

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
`generate_GBIF_taxonomic_reference_list()`, `generate_taxadb_taxonomic_reference_list()`,
`load_taxonomic_resources()`, `align_taxa()`, `update_taxa()`, `create_taxonomic_update_lookup()`) in
the order you'd actually use them, ending in a realistic "update a list of raw field names" workflow
(issue #22 -- keep this list, and the vignette's own worked examples, current as further functions/
parameters are exported; `library(taxonAlign)` in a real render uses the *installed* package, not
`devtools::load_all()`'s in-session version, so re-run `devtools::install()` before re-rendering if
you've made source changes this session and the render doesn't reflect them). Deliberately **not**
registered as a formal R/knitr
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

`vignettes/development-history.qmd` revisits [issue #2](https://github.com/traitecoevo/taxonAlign/issues/2)
(originally "reproduce current workflow as a vignette", filed as a benchmark-before-refactoring ask) --
reimplementing `reproduce-EH-workflow.Rmd`'s underlying idea (align the real AusInvertTraits name list
against AFD+iNat and check the result against a real historical answer key) against the *finished*
package's exported functions, rather than fixing the original prototype vignette's broken external
paths. Framed explicitly as a historical record, not a tutorial (`get-started.qmd` is that) --
narrates why the package exists (real, messy invertebrate names, generically attributed to "an
Australian invertebrates trait database" throughout rather than naming AusInvertTraits or its sibling
`ausinvertraits`/`ausinvertraits.addons` repos directly -- **those are private repos**, so this
published-facing vignette (unlike CLAUDE.md, which is internal and keeps the specific names) never
names or links them), walks through building the AFD+iNat reference (noting AFD's own real limitation
-- incomplete coverage across invertebrate phyla, comprehensive for some groups like insects but not
others -- and iNat's: `taxonomic_status` hardcoded to `"accepted"`, so it carries no synonym
information and can only widen coverage, never resolve a synonym) and aligning the real 5,154-name
list, quantifies agreement against the historical answer key at **both** species level (`taxon_name`:
2,861/2,873, 99.6%) **and** higher-rank level (the historical `aligned_name` column, matched against
`include_bracketed_info = TRUE`'s identical bracketed format: 1,911/2,281, 87.1% -- a stricter,
format-sensitive comparison, with the same two resource combinations still agreeing with *each other*
on 98.5% of that higher-rank subset), individually characterises all 12 species-level disagreements (6
real coverage gaps, 2 fuzzy-matching imprecision within *Euastacus* -- a large genus of very
similarly-epithet-ed crayfish species, newly filed as
[issue #17](https://github.com/traitecoevo/taxonAlign/issues/17) -- 2 that are the *historical* file's
own inconsistency rather than a disagreement this package introduced, 1 a human-context-vs-string-match
limitation, and 1 the real tautonym bug issue #16 fixed), demonstrates swapping AFD+iNat for AFD+GBIF
(99.1% agreement against the *other* pipeline overall, per the earlier AFD+iNat/AFD+GBIF diff analysis
in this file), and closes with the GBIF-scale-fetch engineering story (Architecture #1 above) and some
retrospective lessons. Trimmed materially after user review for length and general-audience readability
(the opening and "why this package exists" section especially -- fewer example names, a shorter
disclaimer). Every code chunk is `#| eval: false` (set once, document-wide, via the YAML frontmatter's
`execute: eval: false`) -- most of it (the AFD/iNat/GBIF loading calls) is now genuinely runnable once
those three exports land in `inst/extdata/` as planned, but the database's own raw name list still
isn't this package's data to ship, and the whole multi-minute alignment plus live GBIF fetch still
isn't something to run on every render regardless. Confirmed this still renders cleanly end to end
(`quarto render vignettes/development-history.qmd`, cleaning up the same `*_files/`/`.knit.md`/`.html`
leftovers as `get-started.qmd` afterward) despite none of its code actually executing, the same "not a
formal knitr vignette, rendered directly" treatment as `get-started.qmd` -- for the same reason: it
isn't (yet, pending those three files landing in `inst/extdata/`) self-contained enough for
`R CMD build` to knit it, same as `reproduce-EH-workflow.Rmd`, so it's kept out of the formal
vignette-build path entirely rather
than left to fail it.

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

`vignettes/demo-align-Prendergast.qmd` is a worked demo against real, messy data rather than a
hand-built example or a historical record -- requested as "something to show people as a test" of the
package, not a tutorial or a benchmark. Aligns the real `Prendergast_2026_2` plant-pollinator dataset
(from the sibling `austraits.build` repo, `../../austraits.build/data/Prendergast_2026_2/data.csv` --
**not self-contained**, same caveat as `reproduce-EH-workflow.Rmd`) at both species level (`Animal
species binomial name`) and order level (`Animal order`), first against AFD, then against a
live-GBIF-fetched Australia-wide animal reference (both invertebrates and vertebrates, combined from
two already-built `generate_GBIF_taxonomic_reference_list(..., country = "AU")` tables kept outside
the repo under `ignore/`) -- summarising match-type counts, showing examples sorted by internal match
code, listing every non-matched name with its observation count (to drive a "what needs fixing"
review), and directly comparing both references on the vertebrate orders AFD structurally can't cover
(`Passeriformes`, `Chiroptera`, `Squamata`, ...). This is also the vignette that surfaced the real
`match_02a` bug fixed above (`"Hylaeus (Rhodhylaeus) sp."` collapsing to bare genus rank) -- found by
running real data through the package, not by constructing a fixture to probe for it.
- The `generate_taxadb_taxonomic_reference_list(..., gbif_snapshot_url = ...)` route (see Architecture
  #1b) can build the same kind of Australia-wide animal reference directly, combining `country = "AU"`
  with the current 2026 snapshot in one call, without needing the pre-built `ignore/` files -- confirmed
  working, but watch `facet_limit`: the default (100,000) is genuinely too small for a broad root like
  `"Animalia"` (confirmed AU-occurring-taxon count under kingdom Animalia is 220,340, triggering
  `fetch_gbif_country_keys()`'s own truncation warning) -- pass an explicit, generous `facet_limit`
  (e.g. `2e5` or more) for any query this broad, rather than trusting the default.
- Rendering this (or any) vignette while *also* running concurrent `devtools::install()`/background
  test processes against the same package library is worth avoiding -- it's the suspected (not fully
  confirmed) cause of a real, intermittently-recurring `APCalign.rdb is corrupt` /
  `R_decompress1 ... libdeflate` error hit multiple times while this vignette was being built, including
  once from inside `APCalign`'s own internal `apply_match()` (confirmed via `apply_match` existing only
  in `APCalign`'s namespace, not `taxonAlign`'s) -- i.e. triggered by a call that resolved to
  `APCalign::align_taxa()`, not `taxonAlign::align_taxa()`, a live instance of the already-known
  shared-function-name risk. Not yet root-caused with certainty (a force-load sweep of every object in
  `APCalign`'s namespace found no corruption moments after one such failure, suggesting something
  transient/environmental rather than a permanently bad file on disk) -- if this recurs in a clean,
  freshly-restarted R session with no concurrent installs running, treat it as a real, separate issue
  worth properly diagnosing rather than assuming it's this same cause again.
