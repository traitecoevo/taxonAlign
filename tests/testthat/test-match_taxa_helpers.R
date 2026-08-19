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
