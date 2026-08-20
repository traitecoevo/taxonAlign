test_that("fuzzy_match tolerates NA entries in accepted_list rather than erroring", {
  # regression test: real reference tables (e.g. GBIF data with doubtful/unranked records) can
  # contain NA canonical names; these used to make `min(distance_c)` NA, which then crashed
  # `if (!(min_dist_abs_c <= ...))` with "missing value where TRUE/FALSE needed"
  expect_no_error(
    result <- fuzzy_match("Chen", c("Chen", NA, "Anser"), max_distance_abs = 2, max_distance_rel = 0.35)
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
