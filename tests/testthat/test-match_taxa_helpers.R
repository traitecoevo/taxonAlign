test_that("fuzzy_match tolerates NA entries in accepted_list rather than erroring", {
  # regression test: real reference tables (e.g. GBIF data with doubtful/unranked records) can
  # contain NA canonical names; these used to make `min(distance_c)` NA, which then crashed
  # `if (!(min_dist_abs_c <= ...))` with "missing value where TRUE/FALSE needed"
  expect_no_error(
    result <- fuzzy_match("Chen", c("Chen", NA, "Anser"), max_distance_abs = 2, max_distance_rel = 0.35)
  )
  expect_equal(result, "Chen")
})

test_that("fuzzy_match tolerates an accepted_list entry with no alphabetic character", {
  # regression test, found via a real, messy worldwide GBIF reference (~867k rows spanning every
  # invertebrate phylum): some malformed higher-rank backbone rows have a `canonicalName` that's an
  # author-citation string, not a taxon name -- and *some* of those (or other data-quality oddities)
  # have no alphabetic character at all (e.g. a bare punctuation/number fragment). The first-letter
  # filter used to compare every accepted_list entry's extracted first letter against the query's via
  # `==`, with no NA guard -- str_extract() returns NA for an entry with no letter, and subsetting a
  # vector with a logical index that itself contains NA doesn't drop that entry, it inserts a literal
  # NA *value* into the filtered result instead. That NA then propagated into stringdist()/min(),
  # crashing deep inside check_match() with "missing value where TRUE/FALSE needed" -- confusingly far
  # from its actual cause. Such an entry should instead just be correctly excluded (it has no first
  # letter to compare, so it can never be a valid first-letter match).
  expect_no_error(
    result <- fuzzy_match("Chen", c("Chen", "1935", "Anser"), max_distance_abs = 2, max_distance_rel = 0.35)
  )
  expect_equal(result, "Chen")
})

test_that("fuzzy_match returns NA (rather than erroring) for an NA query string", {
  expect_no_error(result <- fuzzy_match(NA_character_, c("Chen", "Anser"), max_distance_abs = 2, max_distance_rel = 0.35))
  expect_true(is.na(result))
})

test_that("fuzzy_match tolerates a deletion typo within the allowed distance", {
  result <- fuzzy_match("Aporcera", c("Aporocera", "Xylotoles"), max_distance_abs = 3, max_distance_rel = 0.35)
  expect_equal(result, "Aporocera")
})

test_that("fuzzy_match rejects a candidate whose first letter differs, even at distance 1", {
  # the core anti-cross-matching rule -- "Xporocera" is only 1 edit from "Aporocera", well within
  # tolerance, but a differing first letter means it must not match
  result <- fuzzy_match("Xporocera", c("Aporocera", "Xylotoles"), max_distance_abs = 3, max_distance_rel = 0.35)
  expect_true(is.na(result))
})

test_that("fuzzy_match returns NA for a genuine tie (n_allowed = 1), but both candidates for n_allowed = 2", {
  expect_true(is.na(fuzzy_match("abcdex", c("abcdef", "abcdeg"), max_distance_abs = 3, max_distance_rel = 0.5, n_allowed = 1)))
  expect_setequal(
    fuzzy_match("abcdex", c("abcdef", "abcdeg"), max_distance_abs = 3, max_distance_rel = 0.5, n_allowed = 2),
    c("abcdef", "abcdeg")
  )
})

test_that("fuzzy_match returns NA when every candidate exceeds the allowed distance", {
  result <- fuzzy_match("Aporocera", "Xyzzyzzy", max_distance_abs = 3, max_distance_rel = 0.99)
  expect_true(is.na(result))
})
