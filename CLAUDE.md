# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package is

`taxonAlign` is an R package (currently pre-release, version 0.0.0.9000) that fuzzy-matches a user's
raw taxon name lists against a taxonomic reference (`align_taxa()`) and updates each match to its
currently accepted name (`update_taxa()`, both together in `create_taxonomic_update_lookup()`). The
reference is either a released dataset (`load_taxonomic_resources()`, downloaded from a dated data
release) or the user's own table, in the format documented by `taxonomic_reference_schema()`.

The shape mirrors [APCalign](https://traitecoevo.github.io/APCalign/)'s four core functions:
`match_taxa` (internal matching engine) → `align_taxa` (exported orchestrator) → `update_taxa` →
`create_taxonomic_update_lookup` (exported, full pipeline) — with three deliberate differences: (1)
taxonomic resources are supplied by the user or a data release, not a fixed APC/APNI download; (2) the
APC-specific "splits" disambiguation logic in APCalign's `update_taxonomy` is replaced by a narrower,
generic version (see Architecture #2); (3) matching/aligning supports *all* taxonomic ranks present in
the reference, not just genus/species/family. `match_taxa()` stays `@noRd`, matching how APCalign
itself keeps its own internal `match_taxa()` unexported. Hybrid/graded-name matching is opt-in via
`hybrids`/`intergrades_affinis` (issue #9). The NSL's `"Genus subg. Subgenusname"` infrageneric-name
syntax is recognised by `match_taxa()` (`match_02x`, issue #25), alongside the zoological/AFD-style
`"Genus (Subgenus)"` bracket convention (issue #14).

## The package split (issue #26)

Until 2026-10-22 this repo also held every function that *builds* a reference. Following Will
Cornwell's suggestion on [issue #26](https://github.com/traitecoevo/taxonAlign/issues/26) ("a new user
who's just got a species list ... just needs `align_taxa()`, `update_taxa()`,
`create_taxonomic_update_lookup()` with the right option to pull the right release"), it was split in
two; the other half is the sibling checkout `../taxonalign-dataprep`
([traitecoevo/taxonAlign.dataprep](https://github.com/traitecoevo/taxonAlign.dataprep)), R package
**`taxonAlign.dataprep`** (dotted, in the traits.build/austraits.build style; R names can't have a
hyphen). The GitHub repo was created as `taxonalign-dataprep` and renamed `taxonAlign.dataprep` to
match the package on 2026-10-22 (GitHub redirects the old name; the local folder keeps the old name).

| Here (taxonAlign) | taxonAlign.dataprep |
|---|---|
| `align_taxa()`, `update_taxa()`, `create_taxonomic_update_lookup()`, `match_taxa()` | `generate_GBIF_taxonomic_reference_list()`, `generate_taxadb_taxonomic_reference_list()` |
| `prepare_taxonomic_resources()` (non-interactive) | `build_taxonomic_reference()` (was `prepare_taxonomic_resources(interactive = TRUE)`) |
| `load_taxonomic_resources(datasets, version)` -- *released* data only | `load_APC()` (was `load_taxonomic_resources("APC")`) |
| `data_release_versions()`, `data_release_datasets()`, `download_data_release_files()` | `load_NSL(taxon_group, version)` (was `load_NSL_resources()`; reads the release's verbatim exports by default, `path` optional) |
| `taxonomic_reference_schema()`, `check_taxonomic_reference()` | `data-raw/build_data_release.R`; the GitHub Releases themselves |

Decisions made with the user while splitting (don't re-litigate):
- **The released data is the hand-off.** A release holds, per dataset, the verbatim source export(s)
  ("raw", for traceability -- the store-raw-data philosophy) *and* a ready file in taxonAlign's format
  (`<dataset>.parquet`, "ready"), built by dataprep and checked with `check_taxonomic_reference()`.
  taxonAlign only ever downloads ready files, so it needs no source-specific reshaping code at all.
  `manifest.csv` has `dataset`/`type` (raw/ready) columns; `load_taxonomic_resources()` reads it to learn
  which datasets a release offers, so adding a dataset needs a new data release, not a taxonAlign
  release. Dataset names: `NSL_animals`, `NSL_algae`, `NSL_bryophytes`, `NSL_fungi`, `NSL_lichens`,
  `GBIF_AU`.
- **Releases live on the dataprep repo** (`taxonAlign_data_release_repo` in `R/data_release_helpers.R`
  is `"traitecoevo/taxonAlign.dataprep"`). The old `2026-10-07` draft on this repo's own Releases has the
  old asset layout (no ready files, `gbif_au_animals.parquet`, a manifest without `dataset`/`type`) and is
  superseded; `data_release_datasets()` errors clearly on a manifest that old.
- **`load_AFD()` was removed** (user, 2026-10-22: "as long as we can load the NSL version through
  `load_NSL` ... remove load_AFD"): the AFD-format CSV isn't released, so a loader for it couldn't build
  off a release, and the AFD is now loaded via `load_NSL("animals")` / `"NSL_animals"`. Its code is kept,
  for continuing AFD-format vs NSL-format comparisons for the curators, as the appendix of dataprep's
  `vignettes/AFD-data-processing.qmd` (user: "it will just live in a vignette").
- **Data-side loaders build off the releases, no path needed** (user: "these should build off the
  releases just like load_taxonomic_resources would ... and does in APCalign"): dataprep's `load_NSL()`
  downloads the release's verbatim `nsl_<group>_{taxon,names}.parquet` by default (`version =`), via
  taxonAlign's exported `download_data_release_files()` (exported for exactly this, rather than
  duplicating the download/offline-fallback logic in dataprep).
- **Dataset-specific names** for the data-side functions (Will's suggestion), and
  `load_taxonomic_resources()` reused here for released data, as an homage to APCalign's own.
- **The format contract** is `taxonomic_reference_schema()` (required columns, Darwin Core names,
  descriptions) + `check_taxonomic_reference()` (required columns present; no missing name/rank/status/
  dataset/ID; unique `taxon_ID`; accepted rows self-referential; every `accepted_name_usage_ID` is some
  row's `taxon_ID`). dataprep's `build_taxonomic_reference()` reads the schema rather than restating it.
  `prepare_taxonomic_resources()` stays more forgiving than the check (renames Darwin Core columns, drops
  NA-`canonical_name` rows with a warning).
- The matching functions also accept a *list* of flat tables (`ensure_prepared_resources()`), so
  `create_taxonomic_update_lookup(names, load_taxonomic_resources(c("NSL_animals", "GBIF_AU")))` works
  directly; a prepared list is never mistaken for one, since its `species` element is itself a list.
- Both packages default to the same cache dir, `tools::R_user_dir("taxonAlign", "cache")` -- kept so the
  large, resumable GBIF fetch cache built up there isn't orphaned.
- dataprep vendors `extract_genus()` (`R/utils.R`) -- keep it identical to this repo's
  `R/match_taxa_helpers.R` version.
- `inst/extdata/AFD.csv` was untracked (`git rm --cached`; still on disk, `inst/extdata/` now gitignored
  and build-ignored) -- nothing here reads it any more. The raw exports under `data/AFD_*` and
  `inst/extdata/Australian_*` also stay on disk, untracked; they're dataprep's inputs.
- Git history for the moved files stays in this repo (they were copied, not history-migrated); the
  dataprep repo's first commit names the taxonAlign commit they came from.

## Commands

This is a standard R package (DESCRIPTION/NAMESPACE, `Roxygen: list(markdown = TRUE)`), testthat 3rd
edition.

```r
devtools::load_all()       # load the package for interactive development
devtools::document()       # regenerate NAMESPACE/man/*.Rd from roxygen comments
devtools::test()           # run the testthat suite
devtools::check()          # full R CMD check
```

taxonAlign.dataprep Imports taxonAlign, so after changing anything here that dataprep relies on (the
schema, `prepare_taxonomic_resources()`, the matching output), `devtools::install()` this package before
running dataprep's tests.

Gotcha (resolved): `devtools::load_all()`/`devtools::test()`/`devtools::check()` used to fail outright
because `R/match_taxa_for_inverts_202500304-use this.R` had top-level executable script code. Its logic
has since been ported into real functions, and the original file now lives at
`ignore/match_taxa_for_inverts_202500304-use this.R` (excluded from the build via `.Rbuildignore`, since
its non-portable filename otherwise trips a `checking for portable file names` `R CMD check` WARNING).

`DESCRIPTION` Imports: `APCalign`, `arrow`, `curl`, `dplyr`, `jsonlite`, `purrr`, `readr`, `stats`,
`stringdist`, `stringr`, `tools`, `utils` (with `Remotes: traitecoevo/APCalign` since APCalign isn't on
CRAN). `rgbif`, `parallel`, `rlang` and the `taxadb`/`duckdb`/`DBI` Suggests went to dataprep with the
code that used them. The `reproduce-EH-workflow.Rmd` vignette (only) additionally needs packages that
are **not** declared as dependencies anywhere (`tidyverse`, `here`) — install these manually if you
need to run it.

### Testing

`tests/testthat/test-prepare_taxonomic_resources.R`, `test-align_taxa.R`, `test-match_taxa.R`,
`test-update_taxa.R`, `test-create_taxonomic_update_lookup.R`, `test-subgenus_conventions.R`,
`test-taxonomic_splits.R` and `test-match_taxa_helpers.R` cover the matching/alignment engine end to
end against a small hand-built combined reference table (`sample_taxonomic_resources()` in
`tests/testthat/helper-align-taxa-fixtures.R`) spanning species (accepted/synonym), genus
(accepted/synonym), family, order (accepted/synonym — a *second* higher rank with an outdated name,
proving `update_taxa()`'s lookup isn't secretly species/genus-specific), an extra non-hardcoded rank
("tribe"), and a subgenus — no network, no `APCalign`-package-data download (only its pure string
helpers, `standardise_names()`/`strip_names()`/`strip_names_extra()`/`standardise_taxon_rank()`, are
called, which are safe to call directly offline). The fixture deliberately includes one synonym
(`"sp4"`) whose `accepted_name_usage_ID` leads nowhere, so it does *not* pass
`check_taxonomic_reference()` as-is. `test-match_taxa.R` covers the opt-in `hybrids`/
`intergrades_affinis` matching (issue #9), plus `progress = TRUE` (issue #5, also covered in
`test-align_taxa.R`).

`test-match_taxa_typos.R` covers messy, invertebrate-flavoured name oddities specifically -- every
edit-distance type of typo (deletion/insertion/substitution/transposition), the first-letter
anti-cross-matching rule (a 1-edit-distance genus typo that changes the first letter must still fail),
a genuinely ambiguous fuzzy tie (must resolve to nothing, not a guess), case/whitespace/trailing-notes/
`sensu lato` normalisation, morphospecies codes (`sp. 1`/`sp. nov.`/`sp. indet.`), the nominotypical
subgenus bracket convention (`Genus (Genus) species`), and two synonyms of the same accepted species
where one sits under a *different* genus entirely (a real, common invertebrate-taxonomy pattern) --
using a second fixture, `sample_invert_taxonomic_resources()` (`helper-invert-typo-fixtures.R`), grounded in
naming conventions confirmed against the real AFD export (e.g. the hyphenated "letter-shape" epithet
convention, `"t-viride"`) rather than invented from scratch. `test-match_taxa_helpers.R` also has
direct `fuzzy_match()` unit tests for the same distance-type/first-letter/tie-breaking behaviour, one
level below the full `align_taxa()` pipeline.

`test-data_release.R` covers release-version resolution, caching and offline fallback (GitHub API and
downloads mocked), and `load_taxonomic_resources()`/`data_release_datasets()` against a small
release-shaped directory (`write_sample_release()`: a manifest with ready and raw rows, two ready
parquet files) -- including a full `create_taxonomic_update_lookup()` run on the loaded list.
`test-taxonomic_reference_schema.R` covers the schema and every `check_taxonomic_reference()` problem.

391 expectations, all passing as of the last `devtools::test()` run (2026-10-22), with `APCalign` installed and network access available, so `test-apc_equivalence.R`'s live tests ran too (`devtools::test()` sets `NOT_CRAN` itself). taxonAlign.dataprep's own suite (233 expectations) holds the tests that moved with the builders.

`test-apc_equivalence.R` (issue #10) is the one exception to "no network, no APCalign-package-data
download" above -- it needs a real, live `APCalign::load_taxonomic_resources()` snapshot to compare
against, so it's skipped unless `APCalign` is installed, network access is available, and it isn't
running under `R CMD check --as-cran`. It flattens APCalign's tables itself (the same `bind_rows()` as
dataprep's `load_APC()`, repeated so this package's tests don't depend on dataprep). This has also
failed intermittently across several local runs (`dplyr::mutate()` on a `NULL` `APC$family_accepted`,
i.e. a live `APCalign::load_taxonomic_resources()` call sometimes not returning that element) -- looks
like a real, if intermittent, upstream issue (rate limiting or a partial response on the live APC
download) rather than anything introduced by taxonAlign, but not yet root-caused; retry if you hit it.

README.md is generated from README.qmd — re-render with Quarto after editing it:
```
quarto render README.qmd
```

## Architecture

Sections are numbered as they were before the split, so the many cross-references below still line
up: #2 (matching engine) and #5 (released data) are here; #1 (live GBIF builder), #1b (taxadb
builder), #3 (AFD-format/APC loaders) and #4 (NSL loader) are in taxonAlign.dataprep's CLAUDE.md,
with the old function names mapped as in the table above (`load_taxonomic_resources("AFD")` ->
`load_AFD()` (since removed; its code is in dataprep's AFD-data-processing vignette),
`load_NSL_resources()` -> `load_NSL()`, `load_GBIF_AU_resources()` -> `load_taxonomic_resources("GBIF_AU")`).

### 2. Fuzzy-matching/alignment engine — `R/prepare_taxonomic_resources.R`, `R/align_taxa.R`, `R/match_taxa.R`, `R/update_taxa.R`, `R/create_taxonomic_update_lookup.R`, `R/match_taxa_helpers.R` (active; everything but `match_taxa()` and the helpers is exported)

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
- **The interactive on-ramp moved to taxonAlign.dataprep** (issue #26):
  `prepare_taxonomic_resources(interactive = TRUE, user_responses = ...)` is now
  `taxonAlign.dataprep::build_taxonomic_reference(taxonomic_resources, user_responses)`, which returns one
  combined flat table (in the chosen priority order) rather than prepared `resources`. Its design notes
  (traits.build-style prompts, `already_aligned`, the "additional references?" loop, the
  column-or-fixed-value prompt) moved to that repo's CLAUDE.md. `prepare_taxonomic_resources()` here is
  non-interactive only: renames Darwin Core columns, errors naming any still-missing required column
  (pointing at `taxonomic_reference_schema()` and `build_taxonomic_reference()`), and combines a list of
  tables in supply order.
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
- **Synonym splits (`R/resolve_synonym_splits.R`, `build_split_table()`)**: a species/infraspecific
  *synonym* leading to two or more accepted taxa gets one suggested name plus
  `alternative_possible_names` (APCalign's `taxonomic_splits` convention; ordering rules and their
  history are in dataprep's CLAUDE.md, Architecture #3, where they were developed against the AFD).
  Narrowed at the user's insistence to species-level synonyms only -- a *genus* synonym leading to
  several accepted genera (e.g. COL's six homonymous *Cynthia* genus records) still silently takes the
  first; user, 2026-10-22: "let's leave for now". **Fixed 2026-10-22, found rendering the Prendergast
  demo against AFD + GBIF_AU**: candidates used to be distinct accepted *records* (`target_ID`), so
  with references combined, a name leading to the same accepted name in both (AFD and GBIF each
  listing *Lichenostomus leucotis* -> *Nesoptilotis leucotis*) was a "split" listing its own accepted
  name as its alternative. Now distinct accepted *taxa*: the same name in different references is one
  taxon; within one reference the name as written (`display_name`) decides, so *Ogma (Seriespinula)
  australis* and *Ogma (Pateracephalanema) australis* stay distinct. Measured: NSL animals + GBIF_AU
  57,818 -> 7,514 splits; a single AFD format loses only 6, each the same valid name listed twice (a
  data error the curator report lists). The old-vs-new split comparison (dataprep's CLAUDE.md) was run
  before this fix, so combined-reference lookups now differ from it by design.
- **Across combined references, list order outranks status** (user's decision, 2026-10-22: "List
  order first"). `prepare_taxonomic_resources()` sorts by `.table_order` (the order tables were
  supplied in; carried onto synthesised higher-rank rows via the table of the row that first names
  the value, dropped after the sort), then by `taxonAlign_taxonomic_status_priority` within each table.
  It used to sort by status alone (stable, so list order only broke ties), so where two references
  listed the same *old* name under different statuses, the higher-priority status won whichever
  reference it was in -- GBIF's "synonym" for *Lichenostomus leucotis* beat the AFD's "Generic
  combination" with the AFD listed first, contradicting the documented "first listed wins". A single
  table is unaffected. Test: `test-prepare_taxonomic_resources.R`, "the first-listed table wins".
  Measured with the split fix above, on the 5,154-name list against NSL_animals + GBIF_AU: no
  `aligned_name` changes; 20 `suggested_name`s change -- 9 lose a self-listed alternative, 11 now
  follow the AFD's taxonomy where GBIF's "accepted" record used to win (*Conoderus* -> *Monocrepidus*
  for 7 names, *Goniocolletes* -> *Leioproctus (Goniocolletes)*, *Pachycoelia* -> *Lepispilus*).
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

### 5. Released reference data and the reference format (issues #24, #26) — `R/load_taxonomic_resources.R`, `R/data_release_helpers.R`, `R/taxonomic_reference_schema.R`

Reference data is published as files on dated GitHub Releases of the **taxonAlign.dataprep** repo
(bare `YYYY-MM-DD` tags, exactly as APCalign does), so an alignment is reproducible by naming the
release. Building and publishing releases is dataprep's job (its CLAUDE.md has the release-building
history: scope, GBIF extinct flags, the BOLD-BIN records left out of `GBIF_AU`); this package only
downloads and reads them. A new release only when a source actually changes -- **no "outdated data"
warning** (user: it implies laziness, and the GBIF backbone often doesn't change for long periods).
- `load_taxonomic_resources(datasets, version = NULL, include_extinct = FALSE, path = NULL, ...)` reads
  the release's `manifest.csv` (via `data_release_datasets()`), checks every requested dataset is a
  `type == "ready"` row, downloads those `<dataset>.parquet` files from *the same* release the manifest
  came from, drops `extinct %in% TRUE` rows unless `include_extinct`, and returns a named list in the
  order asked for (= priority order), each tibble carrying a `"data_release"` attribute. `path` reads a
  local copy of a release directory instead.
- **Offline behaviour** (user requirement, from APCalign's failure mode of searching for new versions
  when offline): a named release already downloaded never touches the network; without `version`,
  `data_release_versions()` asks GitHub once per session via `curl` with a 5s connect / 10s total
  timeout, any failure -> newest local release; `get_data_release_assets()` falls back to the newest
  complete local release if the latest can't be downloaded (never for an explicitly named version).
  Release tags are dates, never numbers. Files cache under `<cache_dir>/data_release/<version>/`.
  A download goes to `<file>.part` first and is renamed only on success, so a failed re-download
  (`refresh_cache = TRUE` offline) never deletes or truncates a cached copy -- found when a failed
  re-download wrote *through* a symlinked cache entry and emptied the file it pointed at.
- `data_release_versions()` lists published date-tagged releases (drafts excluded, pre-releases
  included) -- so a *draft* release is only usable by naming `version` after downloading its files into
  the cache by hand (`gh release download <tag> --repo traitecoevo/taxonAlign.dataprep -D
  <cache_dir>/data_release/<tag>`).
- `arrow`, `curl`, `jsonlite` are full Imports (user decision for arrow, as APCalign).
- **GBIF's `extinct` flag doesn't distinguish fossils from recent extinctions** -- the thylacine,
  pig-footed bandicoot and paradise parrot are flagged exactly like *Diprotodon*. Hence releases keep
  everything with the column and the loader filters, rather than the release dropping them.
- `taxonomic_reference_schema()`/`check_taxonomic_reference()`: the format contract with dataprep and
  with users' own tables -- see "The package split" above.

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
user-facing "getting started" walkthrough covering every exported function (`load_taxonomic_resources()`
and the release helpers, `taxonomic_reference_schema()`/`check_taxonomic_reference()`,
`prepare_taxonomic_resources()`, `align_taxa()`, `update_taxa()`, `create_taxonomic_update_lookup()`) in
the order you'd actually use them, pointing at taxonAlign.dataprep for building references from other
sources (its own `vignettes/get-started.qmd` took over the GBIF/taxadb/APC/AFD/interactive sections), ending in a realistic "update a list of raw field names" workflow
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
package. **Reworked 2026-10-22**: it now aligns the real `Prendergast_2026_3` plant-pollinator dataset
(sibling `austraits.build` repo, `../../austraits.build/data/Prendergast_2026_3/data.csv` relative to
`vignettes/` -- **not self-contained**) -- user's choice, because it has the vertebrate visitors (birds,
bats, a possum, a skink; "I definitely want the version with vertebrates!!"). The pollination data was
split in austraits.build after the demo was first written: `Prendergast_2026_2` is now insects only,
and the old text's hardcoded "2,896 rows" and vertebrate claims described neither. References: the
released `NSL_animals` and `GBIF_AU` (version `2026-10-07`), then both combined. The old "AFD has no
vertebrates" story no longer applies -- the AFD's NSL export covers vertebrates, so every order matches
exactly (incl. fuzzy `"Psittaformes"`), and the demo now shows *Lichenostomus* honeyeaters updating to
*Gavicalis*/*Caligavis*/*Ptilotula*/*Nesoptilotis*, and three old combinations the AFD lacks at species
rank (*Phylidonyris albifrons*, *Anthochaera rufogularis*, misspelt *Climacteris leucophaca*), the
first two filled by GBIF in the combination. Until the release is published, render it against the
local release files with `R_USER_CACHE_DIR` pointing at a folder holding
`R/taxonAlign/data_release/2026-10-07/` (the ready files + manifest), so the real cache isn't touched.
This vignette also surfaced the real `match_02a` bug fixed above (`"Hylaeus (Rhodhylaeus) sp."`), and
the combined-references split bug (see "Synonym splits").
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
