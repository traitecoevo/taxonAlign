# Column names APCalign::load_taxonomic_resources() renames APC/APNI's raw Darwin Core columns to --
# copied verbatim so a user's raw Darwin Core-cased data (or APC/APNI itself) lines up with
# taxonAlign's naming without any manual renaming. Columns already correctly named, or not in this map
# at all, pass through untouched.
taxonAlign_column_rename <- c(
  taxon_ID = "taxonID",
  taxon_rank = "taxonRank",
  name_type = "nameType",
  taxonomic_status = "taxonomicStatus",
  pro_parte = "proParte",
  scientific_name = "scientificName",
  scientific_name_ID = "scientificNameID",
  accepted_name_usage_ID = "acceptedNameUsageID",
  accepted_name_usage = "acceptedNameUsage",
  canonical_name = "canonicalName",
  scientific_name_authorship = "scientificNameAuthorship",
  taxon_rank_sort_order = "taxonRankSortOrder",
  taxon_remarks = "taxonRemarks",
  taxon_distribution = "taxonDistribution",
  higher_classification = "higherClassification",
  nomenclatural_code = "nomenclaturalCode",
  dataset_name = "datasetName",
  name_element = "nameElement"
)

# `taxonomic_dataset` has no APCalign equivalent to rename from -- APCalign hardcodes it ("APC"/"APNI")
# rather than reading it from the data, since it only ever combines those two fixed datasets.
# taxonAlign combines arbitrary user-supplied datasets instead, so it has to be a real required column.
taxonAlign_required_cols <- c(
  "canonical_name", "scientific_name", "taxon_rank", "taxonomic_status", "taxonomic_dataset",
  "genus", "taxon_ID", "accepted_name_usage_ID"
)

# Priority order used to disambiguate when the same lookup key (canonical_name, scientific_name,
# binomial, trinomial, ...) appears more than once with a different taxonomic_status -- match_taxa()'s
# exact-match blocks use `match()` (first-hit semantics), so taxonomic_resources is sorted by this priority
# before any rank/status splitting happens (see prepare_taxonomic_resources() below), ensuring the
# highest-priority (most reliable) row wins regardless of the order the data happened to arrive in.
#
# Ported and extended from APCalign's own `relevel_taxonomic_status_preferred_order()`
# (`R/update_taxonomy.R`) -- the same disambiguation APCalign applies internally when resolving a
# genus/family-level match, generalised here to every rank/status lookup taxonAlign performs (not just
# genus/family). Extended with two terms GBIF's vocabulary uses that APC/APNI's doesn't: "homotypic
# synonym" (shares the accepted name's type specimen -- as reliable as a nomenclatural/basionym
# relationship, so placed right after the generic "taxonomic synonym") and "heterotypic synonym" (a
# different type judged to represent the same taxon -- placed right after "basionym", before the
# narrower "nomenclatural synonym"/"isonym" terms). A status not in this vector sorts after every known
# term (via `factor()`'s NA-for-unmatched-level behaviour, which `dplyr::arrange()` places last by
# default) rather than being dropped or erroring -- extend this vector as further status vocabularies
# turn up, rather than guessing at their rank.
taxonAlign_taxonomic_status_priority <- c(
  "accepted",
  "taxonomic synonym",
  "homotypic synonym",
  "basionym",
  "heterotypic synonym",
  "nomenclatural synonym",
  "isonym",
  "orthographic variant",
  "common name",
  "doubtful taxonomic synonym",
  "replaced synonym",
  "doubtful pro parte taxonomic synonym",
  "pro parte nomenclatural synonym",
  "pro parte taxonomic synonym",
  "pro parte misapplied",
  "misapplied",
  "unplaced",
  "excluded",
  "doubtful misapplied",
  "doubtful pro parte misapplied",
  "included"
)

# Specificity order (most specific first) used to decide, when a name could in principle match more
# than one taxonomic rank, which rank wins -- both when `resources`' rank sublists are flattened back
# into one table (`update_taxa()`'s `taxon_ID`-keyed lookup, `match()`, first-hit semantics) and when
# `match_taxa()`'s generic higher-rank loops (`match_02b`/`match_02c`/`match_12b`/`match_12c`) walk
# `taxon_ranks_to_check` one rank at a time, stopping at the first rank a row matches. Previously,
# `prepare_taxonomic_resources()` derived rank order from a plain `split()` on the raw rank string,
# which orders alphabetically -- arbitrary, and actively wrong whenever two ranks' rows can carry the
# same taxon_ID or name: real AFD data guarantees this for genus/subgenus (every genus split into
# subgenera has a *nominotypical* subgenus sharing the genus's own name), which is what surfaced this in
# the first place (see the AFD `taxon_ID` namespacing fix in `load_taxonomic_resources.R`) -- but even
# with that fixed, *any* other coincidental cross-rank name collision (a handful turn up in real AFD
# data at family/order/subfamily/suborder/subtribe/superfamily/superorder/class too) would otherwise
# still resolve to whichever rank happened to sort first alphabetically, rather than a deliberately
# chosen one -- the more specific rank in general, except genus-vs-subgenus specifically (see below).
#
# Species/infraspecific ranks aren't listed here -- `taxon_rank2` (below) buckets them into their own
# `"species"` entry before this ordering is ever applied, and that bucket is always the most specific of
# all, so it's still ranked first via `union()` at the call site.
#
# `genus` is deliberately placed *before* `subgenus`, even though subgenus is the taxonomically more
# specific rank -- the one deliberate exception to "most specific first" in this whole vector. A bare
# name shared by a genus and its own nominotypical subgenus (e.g. "Xylotoles") is ambiguous on its own,
# and the safer default when a user writes just that name is to assume they mean the broader, genus-rank
# grouping, not the narrower subgenus one -- genus names are what people actually write and expect to
# resolve to; the bracketed `Genus (Subgenus)` convention (`resources$subgenus_v2`) and the plain
# subgenus-alone convention (`resources$subgenus`) both exist for when a subgenus is genuinely intended.
# No other pair of ranks in this vector shares this same-name ambiguity (subgenus/genus is the one
# taxonomic level where an identical, nominotypical name is guaranteed to occur), so this is the only
# swap needed.
#
# Extends (and is ordered by reversing the sense of) `gbif_rank_order`
# (`generate_GBIF_taxonomic_reference_list.R`, broadest-to-narrowest, driving GBIF `rank`-filtering) --
# not reused directly, since that vector's own trailing "cultivar"/"other"/"unranked" placeholders exist
# for GBIF-filtering purposes specific to that file and aren't meaningful specificity-order entries here.
# Adds a few rank names real AFD/iNat/APCalign-standardised data actually uses that GBIF's own enum
# doesn't: "supertribe", "epifamily", "subterclass" (AFD/iNat), and "complex"/"hybrid" (informal,
# species-adjacent identification concepts, ranked just below subgenus). Also includes the doubled-`n`
# spellings ("sectionn", "subsectionn", "zoosectionn", "zoosubsectionn") that
# `APCalign::standardise_taxon_rank()` actually produces for "section"/"subsection"/"zoosection"/
# "zoosubsection" input (its Latin-to-English substring replacement, `gsub("sectio", "section", ...,
# fixed = TRUE)`, matches "sectio" as a *substring* of the already-English "section", appending a
# spurious extra "n" -- an upstream APCalign quirk, not a taxonAlign bug, but real values this vector
# needs to rank correctly since they're what actually reaches `prepare_taxonomic_resources()`).
#
# A rank not in this vector isn't dropped or misplaced -- the call site builds the actual `factor()`
# levels as `union(taxonAlign_taxon_rank_specificity, unique(taxon_rank2))`, so an unrecognised rank
# simply keeps its own bucket, appended after every known rank (i.e. treated as least-specific/lowest
# tie-break priority, the conservative default when specificity is genuinely unknown) -- extend this
# vector as further rank vocabularies turn up, the same "extend, don't guess" philosophy as
# `taxonAlign_taxonomic_status_priority` above.
taxonAlign_taxon_rank_specificity <- c(
  "genus", "subgenus",
  "complex", "hybrid",
  "section", "sectionn", "subsection", "subsectionn", "zoosection", "zoosectionn",
  "zoosubsection", "zoosubsectionn", "series", "subseries",
  "subtribe", "tribe", "supertribe",
  "subfamily", "family", "epifamily", "superfamily",
  "infraorder", "parvorder", "suborder", "order", "grandorder", "superorder", "magnorder",
  "infracohort", "subcohort", "cohort", "supercohort",
  "infralegion", "sublegion", "legion", "superlegion",
  "parvclass", "infraclass", "subterclass", "subclass", "class", "superclass",
  "infraphylum", "subphylum", "phylum", "superphylum",
  "infrakingdom", "subkingdom", "kingdom", "domain"
)

#' Prepare a combined taxonomic reference table for name matching
#'
#' Takes one or more taxonomic reference tables (the user's own, one produced by
#' [generate_GBIF_taxonomic_reference_list()], or any mix of these) and turns them into the single nested
#' `resources` list that [align_taxa()]/`match_taxa()` expect: columns are normalised and any missing
#' ones resolved (see `interactive`, below), tables are combined if more than one was supplied, and the
#' result is split by rank (and, for species-level rows, by taxonomic status).
#'
#' Unlike [APCalign](https://traitecoevo.github.io/APCalign/)'s `load_taxonomic_resources()`, which
#' only ever assembles the fixed APC/APNI combination, this function works on whatever combined
#' reference data the user supplies -- at whatever set of taxonomic ranks it happens to contain, not
#' just genus/species/family.
#'
#' @param taxonomic_resources A tibble, a path to a CSV file, or a (optionally named) list of either --
#'  one element per taxonomic reference table to combine. Optional (`NULL`) when `interactive = TRUE`
#'  -- you'll be prompted for a path to the first table, the same way you're prompted for every
#'  additional one (see `interactive`, below). Each table needs (at least) the columns
#'  `canonical_name`, `scientific_name`, `taxon_rank`, `taxonomic_status`, `taxonomic_dataset`,
#'  `genus`, `taxon_ID` and `accepted_name_usage_ID` -- the column names produced by
#'  [generate_GBIF_taxonomic_reference_list()], and matching
#'  [APCalign](https://traitecoevo.github.io/APCalign/)'s own naming convention exactly (see Details)
#'  so there's one canonical name field, not two. A row whose `canonical_name` is `NA` has no usable
#'  name and is dropped, with a warning (real data occasionally has this -- e.g. some GBIF records
#'  genuinely lack a canonical name). `accepted_name_usage_ID` must be self-referential (equal to
#'  `taxon_ID`) for already-accepted rows, not `NA` -- this is what lets `update_taxa()` resolve a
#'  matched name forward to its current accepted name regardless of whether it matched an accepted
#'  name or a synonym.
#' @param taxon_ranks_to_check Optional character vector restricting which taxonomic ranks (besides
#'  species/infraspecific ranks) are retained in the returned `resources` for higher-rank matching
#'  (e.g. `c("genus", "family")`). Defaults to `NULL`, which keeps every rank present in
#'  `taxonomic_resources`.
#' @param interactive Logical; if `TRUE`, prompts (in the style of `traits.build`'s
#'  `metadata_add_traits()`/`metadata_add_locations()`) for any of the required columns a table is
#'  missing -- letting a column be picked from that table, or (for some fields) a fixed value typed in
#'  or auto-generated -- rather than erroring. A table that's already complete is never interrupted;
#'  one that isn't is first asked, once, whether it's already fully aligned regardless (e.g. it came
#'  from an earlier `prepare_taxonomic_resources()`/`generate_GBIF_taxonomic_reference_list()` call, just
#'  under column names `interactive` didn't recognise) before being walked through the per-field
#'  prompts. Once every initially-supplied table is resolved, also asks whether there are any
#'  additional taxonomic reference(s) to include -- repeating for as many as the user has -- so a
#'  single file passed in via `taxonomic_resources` can grow into a combined set interactively, rather
#'  than requiring the whole set to be assembled up front. When more than one table ends up in the
#'  final set, also prompts once for a priority order across them. Defaults to `FALSE`, which errors
#'  immediately (as before) if any required column is missing, and skips both of the prompts above.
#' @param user_responses Optional named list bypassing the real prompts `interactive = TRUE` would
#'  otherwise show -- for scripting or testing. Keyed by table name (matching `taxonomic_resources`'s
#'  names, or `"table 1"`/`"table 2"`/... if unnamed), each holding the responses for that table's
#'  missing fields (`already_aligned` (logical), `taxonomic_dataset`, `canonical_name`,
#'  `scientific_name`, `taxon_rank`, `taxonomic_status`, `genus`, `taxon_ID`,
#'  `accepted_name_usage_ID` -- see `?map_missing_taxonomic_resources_columns` for exact shapes), plus two
#'  top-level elements: `initial_table` (a table/path bypassing the prompt for the first table, when
#'  `taxonomic_resources` itself is `NULL`), `additional_tables` (an optionally-named list of further
#'  tables/paths to add, bypassing the "any additional reference(s)?" prompt loop -- each is still
#'  resolved via its own entry in `user_responses`, keyed the same way) and `priority_order`, when the
#'  final set has more than one table. Ignored unless `interactive = TRUE`.
#'
#' @return A named list of tibbles (and, for `species`, a further named list split by
#'  `taxonomic_status`): one element per taxonomic rank present in `taxonomic_resources` (after applying
#'  `taxon_ranks_to_check`, if supplied), plus `subgenus_v2` when subgenus-rank rows are present (see
#'  Details).
#'
#' @details
#' Column names are normalised on the way in, exactly the way
#' [APCalign::load_taxonomic_resources()] normalises APC/APNI's raw Darwin Core column names to its
#' own convention -- e.g. a raw `canonicalName`/`taxonRank`/`taxonomicStatus`/`scientificName` column
#' is renamed to `canonical_name`/`taxon_rank`/`taxonomic_status`/`scientific_name`. This keeps
#' `canonical_name` the *only* name field taxonAlign ever refers to -- unlike the ported
#' `AusInvertAlign` prototype this package originated from, which had a separate `taxon_name` fallback
#' column, there's no second, ambiguous name field to keep in sync.
#'
#' When multiple tables are supplied, priority is expressed purely through row order in the combined
#' table: `match_taxa()`'s exact-match blocks use `match()` (first-hit semantics), so whichever table
#' is row-bound first is preferred when a name exists in more than one.
#'
#' Two matching conventions for subgenus names are supported side by side: some input name lists
#' write the subgenus alone (e.g. `"Podosemum"`), others write the `Genus (Subgenus)` bracketed
#' convention (e.g. `"Boronia (Podosemum)"`). To support both, when `taxonomic_resources` contains
#' subgenus-rank rows, `resources$subgenus` holds the plain subgenus names (used for the first
#' convention) and `resources$subgenus_v2` additionally holds a `genus_and_subgenus` column (used for
#' the second).
#'
#' @export
prepare_taxonomic_resources <- function(taxonomic_resources = NULL,
                                         taxon_ranks_to_check = NULL,
                                         interactive = FALSE,
                                         user_responses = NULL) {

  if (is.null(taxonomic_resources)) {
    if (!interactive) {
      stop(
        "`taxonomic_resources` is required. Supply your own combined taxonomic reference table (or a path ",
        "to one), or build one with `generate_GBIF_taxonomic_reference_list()`. Or pass ",
        "`interactive = TRUE` to be prompted for one.",
        call. = FALSE
      )
    }
    # interactive = TRUE with nothing supplied yet -- prompt for the first table exactly the way
    # additional tables are already asked for below (see the `repeat` loop), rather than requiring the
    # caller to already have a table in hand before they can even start. Someone who *does* already
    # have a table (a path, or a tibble they've loaded themselves) still just passes it as
    # `taxonomic_resources` directly, as before -- this only fills the gap where they don't.
    taxonomic_resources <- prompt_for_table_path(
      "Enter the file path for your taxonomic reference: ", user_responses$initial_table
    )
  }

  tables <- normalise_taxonomic_resources_input(taxonomic_resources)

  resolved <- purrr::imap(
    tables,
    function(data, label) resolve_taxonomic_resources_table(data, label, interactive, user_responses[[label]])
  )

  # Interactively, keep asking for one more taxonomic reference until the user says there isn't one --
  # rather than requiring every table to be assembled into `taxonomic_resources` up front, this lets
  # someone start with just the one file they have open and add others as they think of them.
  # `user_responses$additional_tables` (a list of extra tables/paths, optionally named) bypasses the
  # real loop for scripting/testing -- each entry is resolved exactly like any other table, using
  # `user_responses[[its label]]` for its own missing-column prompts.
  if (interactive) {
    extra_tables <- user_responses$additional_tables
    extra_index <- 0

    repeat {
      if (!is.null(extra_tables)) {
        extra_index <- extra_index + 1
        if (extra_index > length(extra_tables)) break
        new_raw <- extra_tables[[extra_index]]
        new_label <- names(extra_tables)[extra_index]
      } else {
        if (!prompt_yes_no("\nDo you have any additional taxonomic reference(s) to include?")) break
        new_raw <- prompt_for_table_path("Enter the file path for the additional taxonomic reference: ")
        new_label <- NULL
      }

      if (is.null(new_label) || new_label == "") new_label <- paste("table", length(resolved) + 1)
      if (is.character(new_raw) && length(new_raw) == 1) new_raw <- read_taxonomic_resources_file(new_raw)

      resolved[[new_label]] <- resolve_taxonomic_resources_table(
        new_raw, new_label, interactive, user_responses[[new_label]]
      )
    }
  }

  if (length(resolved) > 1) {
    order <- if (interactive) {
      prompt_priority_order(names(resolved), user_responses$priority_order)
    } else {
      # no prompt: the order tables were supplied in already *is* the priority
      names(resolved)
    }
    taxonomic_resources <- dplyr::bind_rows(resolved[order])
  } else {
    taxonomic_resources <- resolved[[1]]
  }

  # dummy placeholder for blank cells -- fuzzy matching doesn't cope with blank/duplicate cells
  zzz <- "zzzz zzzz"

  taxonomic_resources <- taxonomic_resources |>
    dplyr::mutate(
      # normalise to character regardless of the source column's type (our own
      # generate_GBIF_taxonomic_reference_list() gives integer taxon_IDs; real APC/AFD data gives URI/UUID
      # strings) so downstream code never has to worry about integer-vs-character mismatches
      taxon_ID = as.character(taxon_ID),
      accepted_name_usage_ID = as.character(accepted_name_usage_ID)
    )

  # A row with no usable name (canonical_name is NA -- real data occasionally has this, e.g. some GBIF
  # records genuinely lack a canonicalName) can never be matched *against* anyway, so it's dropped
  # here rather than kept around as a resource-table row. This isn't just tidying: leaving it in is an
  # active hazard downstream, because `NA %in% x` is TRUE whenever `x` itself contains an NA -- so a
  # fuzzy_match() call that legitimately finds no match (returning NA) would otherwise spuriously
  # "match" this row's NA canonical_name instead of correctly matching nothing, in every match block
  # that does `i <- some_value %in% resources$...$canonical_name`-style lookups.
  n_before <- nrow(taxonomic_resources)
  taxonomic_resources <- taxonomic_resources |> dplyr::filter(!is.na(canonical_name))
  n_dropped <- n_before - nrow(taxonomic_resources)
  if (n_dropped > 0) {
    warning(
      n_dropped, " row(s) in `taxonomic_resources` have a missing (NA) `canonical_name` and were dropped ",
      "-- they could never be matched against anyway.",
      call. = FALSE
    )
  }

  # Synthesise a row for every implied higher rank present as its own column on the combined table
  # (e.g. a `genus`/`family`/`order` column recorded on species rows), for whichever such value doesn't
  # already have an explicit row of its own -- generalising what load_AFD() already does for AFD's own
  # raw export (see afd_higher_rank_rows()) to *any* input table that happens to carry this kind of
  # column, so someone assembling their own reference doesn't have to remember to add an explicit row
  # for every genus/family/etc. their species rows already imply (a real, easy mistake to make -- found
  # by making it in this package's own get-started.qmd vignette example). Any column beyond the
  # required 8 is scanned this way, not just the standard Linnaean kingdom/phylum/class/order/family
  # set, since real taxonomic data often has ranks beyond those (tribe, subfamily, superfamily, ...);
  # the tradeoff is that a genuinely non-taxonomic extra column (e.g. "locality", "collector") would
  # also be treated as an implied rank and generate rows from it -- if that's not wanted, simply don't
  # include such a column in `taxonomic_resources` in the first place. `genus` is part of the required
  # 8, but is *also* itself a hierarchy column implying its own rank's rows, so it's included here too.
  # Only character columns can plausibly hold a taxon name -- an extra numeric/logical/date column
  # (e.g. a collection year, a record count) isn't a hierarchy column at all, and treating it as one
  # doesn't just produce silly rows, it can crash outright (e.g. `values != ""` on a POSIXct column).
  extra_cols <- setdiff(names(taxonomic_resources), taxonAlign_required_cols)
  extra_cols <- extra_cols[purrr::map_lgl(taxonomic_resources[extra_cols], is.character)]
  implied_rank_cols <- union("genus", extra_cols)

  synthesised_rows <- purrr::map(implied_rank_cols, function(col) {
    values <- taxonomic_resources[[col]]
    already_present <- taxonomic_resources$canonical_name[taxonomic_resources$taxon_rank == col]
    to_add <- setdiff(unique(values[!is.na(values) & values != ""]), already_present)
    if (length(to_add) == 0) return(NULL)

    # attribute each synthesised row to whichever dataset first mentions that value -- consistent with
    # the rest of the package's "first-hit wins" priority convention when the same name could otherwise
    # be attributed to more than one source
    dataset <- taxonomic_resources$taxonomic_dataset[match(to_add, values)]

    dplyr::tibble(
      canonical_name = to_add,
      scientific_name = to_add,
      taxon_rank = col,
      taxonomic_status = "accepted",
      taxonomic_dataset = dataset,
      genus = NA_character_,
      # no natural taxon_ID exists for a rank synthesised this way -- a placeholder combining the
      # dataset, rank and name keeps it unique across both ranks (a nominotypical genus/subgenus
      # sharing a name) and datasets (two sources both having, say, a "Formicidae" family row)
      taxon_ID = paste(dataset, col, to_add, sep = "_"),
      accepted_name_usage_ID = paste(dataset, col, to_add, sep = "_")
    )
  })

  taxonomic_resources <- dplyr::bind_rows(taxonomic_resources, synthesised_rows)

  # Sort by taxonomic_status priority (see taxonAlign_taxonomic_status_priority above) so that, wherever
  # the same lookup key repeats under different statuses, the most reliable row is the one every
  # first-hit `match()`-based exact-match block finds, and the one the binomial/trinomial dedup below
  # keeps (it discards later duplicates, so ordering matters there too). This is a stable sort, so it
  # composes correctly with priority *between* multiple combined taxonomic_resources tables (row-bind
  # order, established above): rows tie on taxonomic_status keep the relative order they already had,
  # so a higher-priority *dataset*'s "accepted" row still comes before a lower-priority dataset's.
  taxonomic_resources <- taxonomic_resources |>
    dplyr::arrange(factor(taxonomic_status, levels = taxonAlign_taxonomic_status_priority))

  taxonomic_resources <- taxonomic_resources |>
    dplyr::mutate(
      word_one = extract_genus(canonical_name),
      taxon_rank = APCalign::standardise_taxon_rank(taxon_rank),
      taxon_rank2 = ifelse(taxon_rank %in% c("subspecies", "species", "form", "variety"), "species", taxon_rank),
      ## strip_names removes punctuation and filler words associated with infraspecific taxa (subsp,
      ## var, f, ser)
      stripped_canonical = APCalign::strip_names(canonical_name),
      ## strip_names_extra removes extra filler words associated with species name cases (x, sp) --
      ## essential for the 2/3-word matches, since those words shouldn't count as one of the words
      stripped_canonical2 = APCalign::strip_names_extra(stripped_canonical),
      stripped_scientific = APCalign::strip_names(scientific_name),
      binomial = ifelse(taxon_rank == "species", stringr::word(stripped_canonical2, start = 1, end = 2), zzz),
      binomial = ifelse(is.na(binomial), zzz, binomial),
      binomial = base::replace(binomial, duplicated(binomial), zzz),
      word_one_stripped = extract_genus(stripped_canonical),
      trinomial = stringr::word(stripped_canonical2, start = 1, end = 3),
      trinomial = ifelse(is.na(trinomial), zzz, trinomial),
      trinomial = base::replace(trinomial, duplicated(trinomial), zzz)
    )

  # split by taxon rank -- unlike APCalign, higher ranks beyond genus/family are expected and kept.
  # Ordered most-specific-first (see taxonAlign_taxon_rank_specificity above), not alphabetically, so
  # `names(resources)` -- and everything derived from it (`match_taxa()`'s default
  # `taxon_ranks_to_check`, `update_taxa()`'s flattened lookup table) -- checks/resolves the more
  # specific rank first whenever a name could in principle match at more than one rank. `"species"`
  # (the most specific bucket of all) is prepended explicitly via `union()`'s ordering rather than
  # listed inside taxonAlign_taxon_rank_specificity itself, since it's handled as its own case just
  # below. `union()` keeps every rank actually present, even ones not in the specificity vector at all
  # -- those simply keep their own bucket, appended after every known rank (drop = TRUE below then
  # discards whichever of the *specificity vector's* ranks aren't actually present, rather than creating
  # empty placeholder tibbles for them).
  rank_levels <- union(c("species", taxonAlign_taxon_rank_specificity), unique(taxonomic_resources$taxon_rank2))
  resources <- split(
    taxonomic_resources, factor(taxonomic_resources$taxon_rank2, levels = rank_levels), drop = TRUE
  )

  if (is.null(resources[["species"]])) {
    stop("`taxonomic_resources` contains no rows at species/infraspecific rank -- nothing to align names against.")
  }

  # for species, split further into "accepted" vs everything else -- not a literal split() by the raw
  # taxonomic_status string. Real-world data uses many distinct non-accepted status labels (real APC
  # data alone has ~18: "basionym", "nomenclatural synonym", "taxonomic synonym", "orthographic
  # variant", "misapplied", "excluded", ...), so a literal split() only ever created a
  # resources$species$synonym bucket for rows whose status was the exact string "synonym" -- every
  # other non-accepted row (the vast majority of real APC synonym-like rows) ended up in its own
  # orphaned resources$species$<status> list element that match_taxa() never references, silently
  # invisible to every synonym-matching block. Each row's *own* taxonomic_status is preserved in the
  # `synonym` bucket regardless (match_taxa() pulls it from the row, not from the bucket name), so
  # output still correctly reports e.g. "basionym" rather than a lossy relabel to generic "synonym" --
  # this only changes which bucket a row is a match *candidate* in.
  species_table <- resources$species
  species_status <- ifelse(species_table$taxonomic_status == "accepted", "accepted", "synonym")
  resources$species <- split(species_table, species_status)

  # A status entirely absent from the input (e.g. a reference built from accepted names only, with no
  # synonyms at all -- a real, valid shape, not just a fixture gap) would otherwise leave
  # resources$species$synonym (or $accepted) missing (NULL) rather than an empty tibble.
  # match_taxa()'s match_01a/01b/01c/01d/05a/05b/09a/09b/10a/10b/11a/11b blocks reference
  # resources$species$accepted/synonym$<column> unconditionally (unlike higher ranks, which are only
  # ever looped over if actually present in `names(resources)`); `NULL$<column>` is NULL, and
  # `dplyr::mutate(x = NULL)` *drops* that column rather than leaving it NA. Since every input name
  # then legitimately selects zero rows for that block, the mutated result ends up with fewer columns
  # than the slice it's replacing, and `taxa$tocheck[i, ] <- ...` errors ("Can't recycle input of size N
  # to size M") even though `i` selects nothing. Backfilling with a 0-row tibble (same columns) instead
  # keeps every match block's `resources$species$<status>$<column>` reference a real, if empty, vector.
  for (status in c("accepted", "synonym")) {
    if (is.null(resources$species[[status]])) {
      resources$species[[status]] <- species_table[0, ]
    }
  }

  # keep both subgenus conventions available: the plain split-by-rank table (`subgenus`, for input
  # names that write the subgenus alone) and a `genus_and_subgenus` variant (`subgenus_v2`, for input
  # names that write the bracketed `Genus (Subgenus)` convention) -- see @details.
  if (!is.null(resources[["subgenus"]])) {
    resources$subgenus_v2 <- resources$subgenus |>
      dplyr::mutate(genus_and_subgenus = paste0(genus, " (", canonical_name, ")"))

    # `$<-` above appends subgenus_v2 at the very end of the list regardless of where "subgenus" itself
    # sits -- reorder so it's positioned immediately after "subgenus" instead, keeping the two parallel
    # subgenus conventions adjacent in `names(resources)` rather than one of them always trailing last
    subgenus_pos <- which(names(resources) == "subgenus")
    new_order <- append(
      setdiff(names(resources), "subgenus_v2"), "subgenus_v2", after = subgenus_pos
    )
    resources <- resources[new_order]
  }

  if (!is.null(taxon_ranks_to_check)) {
    higher_ranks_present <- setdiff(names(resources), c("species", "subgenus_v2"))
    unknown_ranks <- setdiff(taxon_ranks_to_check, higher_ranks_present)
    if (length(unknown_ranks) > 0) {
      warning(
        "`taxon_ranks_to_check` includes rank(s) not present in `taxonomic_resources`: ",
        paste(unknown_ranks, collapse = ", "), ". They will have no effect.",
        call. = FALSE
      )
    }
    ranks_to_drop <- setdiff(higher_ranks_present, taxon_ranks_to_check)
    ranks_to_drop <- setdiff(ranks_to_drop, "subgenus_v2")
    if ("subgenus" %in% ranks_to_drop && !"subgenus" %in% taxon_ranks_to_check) {
      # dropping `subgenus` should also drop its bracketed-name counterpart
      resources$subgenus_v2 <- NULL
    }
    resources[ranks_to_drop] <- NULL
  }

  resources
}

# Normalises `taxonomic_resources` (a data frame, a file path, or a list of either, optionally named) into
# a *named* list of data frames -- reading any file-path elements via readr::read_csv(). Unnamed (or
# partially named) lists get positional labels ("table 1", "table 2", ...) for prompts/error messages.
normalise_taxonomic_resources_input <- function(taxonomic_resources) {

  if (is.data.frame(taxonomic_resources)) {
    tables <- list(taxonomic_resources)
  } else if (is.character(taxonomic_resources) && length(taxonomic_resources) == 1) {
    tables <- list(read_taxonomic_resources_file(taxonomic_resources))
  } else if (is.list(taxonomic_resources) && length(taxonomic_resources) > 0) {
    tables <- purrr::map(
      taxonomic_resources,
      function(x) if (is.character(x) && length(x) == 1) read_taxonomic_resources_file(x) else x
    )
  } else {
    stop(
      "`taxonomic_resources` must be a tibble/data frame, a path to a CSV file, or a (optionally named) ",
      "list of either.", call. = FALSE
    )
  }

  labels <- names(tables)
  if (is.null(labels)) labels <- rep("", length(tables))
  unnamed <- which(labels == "")
  labels[unnamed] <- paste("table", unnamed)
  names(tables) <- labels

  tables
}

read_taxonomic_resources_file <- function(path) {
  if (!file.exists(path)) {
    stop("`taxonomic_resources` names a file that doesn't exist: ", path, call. = FALSE)
  }
  readr::read_csv(path, show_col_types = FALSE, progress = FALSE)
}

# Applies the column_rename step to one table, then either returns it as-is (already complete),
# errors (interactive = FALSE), or interactively fills in whatever's missing (interactive = TRUE).
resolve_taxonomic_resources_table <- function(data, table_label, interactive, user_responses) {

  data <- data |> dplyr::rename(dplyr::any_of(taxonAlign_column_rename))
  missing_cols <- setdiff(taxonAlign_required_cols, names(data))

  if (length(missing_cols) == 0) {
    return(data)
  }

  if (!interactive) {
    stop(
      "`taxonomic_resources` (`", table_label, "`) is missing required column(s): ",
      paste(missing_cols, collapse = ", "), ". See `?prepare_taxonomic_resources` for the expected ",
      "input columns, or pass `interactive = TRUE` to be prompted for them.",
      call. = FALSE
    )
  }

  # Give the user a chance to assert the table is already fully aligned before launching into the
  # full per-field prompt sequence below -- e.g. it may already be in taxonAlign's target shape (from
  # an earlier prepare_taxonomic_resources()/generate_GBIF_taxonomic_reference_list() call) just under
  # column names the automatic column_rename step above doesn't recognise. Only asked here, once
  # column_rename has already run and something is still missing -- a table that's already fully
  # resolved (the common case for generate_GBIF_taxonomic_reference_list()'s own output) is never
  # interrupted with this question at all.
  if (prompt_already_aligned(table_label, user_responses$already_aligned)) {
    stop(
      "`", table_label, "` was indicated as already fully aligned, but is still missing required ",
      "column(s): ", paste(missing_cols, collapse = ", "), ". Answer \"No\" (or omit ",
      "`user_responses$already_aligned`) if it still needs column mapping.",
      call. = FALSE
    )
  }

  map_missing_taxonomic_resources_columns(data, missing_cols, table_label, user_responses)
}
