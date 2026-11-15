## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new release.

## Test environments

<!-- fill in before submitting: GitHub Actions (macOS, Windows, Ubuntu: R devel, release, oldrel-1),
win-builder (devel, release), mac builder, R-hub -->

## Notes for CRAN

* Examples and tests that download data are wrapped in `\donttest{}` or skipped on CRAN; downloads
  go to a temporary directory in examples, and to `tools::R_user_dir("taxonAlign", "cache")` only when
  a user calls the functions.
