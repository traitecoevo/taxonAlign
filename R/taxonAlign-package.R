#' @keywords internal
"_PACKAGE"

# Column names in dplyr's data-masking verbs are written `.data$col`, and in tidyselect verbs
# (`select()`, `pull()`) as strings, so R CMD check finds no undefined globals (the austraits-family
# convention; `.data$` is deprecated only in tidyselect).
#' @importFrom rlang .data
NULL
