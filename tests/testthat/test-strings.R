# The base-R string helpers in R/strings.R replace stringr/stringi (issue #27). They are vendored from
# APCalign (traitecoevo/APCalign#302), and these tests are ported from APCalign's
# tests/testthat/test-functions-strings.R: each pins a behaviour where base R and stringr differ, with
# expected values from stringr 1.6.0 / stringi 1.8.7 (ICU 74). The last test compares with stringr
# directly when it is installed.

test_that("re_detect() keeps missing values missing", {
  expect_equal(re_detect(c("a", NA, "b"), "a"), c(TRUE, NA, FALSE))
})

test_that("U+0085 (next line) counts as white space, as in ICU", {
  expect_equal(trim("\u0085Acacia dealbata\u0085"), "Acacia dealbata")
  expect_equal(extract_genus("Acacia\u0085dealbata"), "Acacia")
})

test_that("a byte-order mark at the start is dropped where stringi dropped it", {
  expect_equal(trim("\uFEFFAcacia dealbata "), "Acacia dealbata")
  expect_equal(to_lower("\uFEFFABC"), "abc")
  expect_equal(split_i("\uFEFFAb c", " ", 1), "Ab")
  expect_equal(to_lower("A\uFEFFB"), "a\uFEFFb")
})

test_that("split_i(), split_all() and word() keep the empty pieces stringr keeps", {
  expect_equal(split_i("a ", " ", 2), "")      # separator at the end
  expect_equal(split_i(" a", " ", 1), "")      # separator at the start
  expect_equal(split_i("", " ", 1), "")        # empty string: one piece
  expect_equal(split_i("", " ", 2), NA_character_)
  expect_equal(split_i(NA, " ", 1), NA_character_)
  expect_equal(split_all("NSW,Qld,", ","), list(c("NSW", "Qld", "")))
  # a final newline is not a separator at the end (\z, not $)
  expect_equal(split_i("a \n", " ", 3), NA_character_)
  expect_equal(word(c("Acacia aneura", "Acacia", NA), 1, 2), c("Acacia aneura", NA, NA))
  expect_equal(word("a b c d e", 2, 5), "b c d e")
})

test_that("re_count() counts matches, NA for NA", {
  expect_equal(re_count(c("a b  c", "", NA, " a "), "[^\\s\\p{Z}\\x85]+"), c(3L, 0L, NA, 1L))
  expect_equal(count_fixed(c("a b  c", "", NA), " "), c(3L, 0L, NA))
})

test_that("to_sentence() follows ICU's sentence case", {
  x <- c("acacia?-dealbata", "1.Acacia", "(acacia", "5acacia", "ab!cd",
         "\u01C6a", "\u1E9Ea", "a.B", "ab.cd", "a. B", "\u00A4wx", "ACACIA", "x", NA)
  expected <- c("Acacia?-dealbata", "1.Acacia", "(Acacia", "5acacia", "Ab!Cd",
                "\u01C5a", "\u1E9Ea", "A.b", "Ab.cd", "A. B", "\u00A4wx", "Acacia", "X", NA)
  expect_equal(to_sentence(x), expected)
})

test_that("to_lower() follows ICU where base R differs", {
  expect_equal(to_lower("\u0130"), "i\u0307")
  expect_equal(to_lower("\u00C9COLE"), "\u00E9cole")
})

test_that("patterns with characters above U+00FF work on all-ASCII input", {
  expect_no_error(to_sentence(c("acacia!xyz", "Acacia aneura")))
  expect_no_error(strip_names_keep_hyphens(c("Acacia aneura", "Neo-uvaria sp.")))
})

test_that("fuzzy_match()'s first-letter cache follows the reference list", {
  expect_equal(fuzzy_match("acacia anera", c("acacia aneura", "banksia serrata"), 2, 0.35),
               "acacia aneura")
  # a different list straight after must not reuse the previous first letters
  expect_true(is.na(fuzzy_match("acacia anera", c("banksia serrata"), 2, 0.35)))
  expect_equal(fuzzy_match("banksia serata", c("banksia serrata", "acacia aneura"), 2, 0.35),
               "banksia serrata")
})

test_that("fuzzy_match() returns NA, without a warning, for text with no letter (APCalign #303)", {
  expect_no_warning(out <- fuzzy_match("12 34", c("acacia aneura", "banksia serrata"), 2, 0.35))
  expect_true(is.na(out))
})

test_that("a name with a word of no letter doesn't stop the lookup (APCalign #303)", {
  names <- c("12 34", "\u00B1 Boronia", "Boronia + serrulata", "Boronia |", "Boronia serrulata")
  out <- suppressMessages(create_taxonomic_update_lookup(names, sample_taxonomic_resources()))
  expect_equal(nrow(out), 5)
  expect_equal(out$original_name, names)
  expect_equal(out$aligned_name[5], "Boronia serrulata")
  expect_true(is.na(out$aligned_name[1]))
})

test_that("helpers agree with stringr on awkward strings", {
  skip_if_not_installed("stringr")
  z <- c("", " ", "a ", " a", "a  b", "a/", "/a", NA, "a /b", "x", "a \n",
         "Acacia\u0085dealbata", "\uFEFFAcacia dealbata", "A\uFEFFb", "Ac\u00E1cia",
         "e\u0301x", "\u00A0Banksia\u3000serrata ", "(acacia", "acacia?-dealbata",
         "\u0130stanbul", "\u00DFa", "a+b<c|d~e", "Acacia\u2215B", "\u201CAcacia\u201D",
         "Genus sp.", "Genus (Sub) sp.", "a b c d", "1.Acacia", "ab!cd")
  expect_equal(trim(z), stringr::str_trim(z))
  expect_equal(to_lower(z), stringr::str_to_lower(z))
  for (i in 1:3) {
    first <- stringr::str_split_i(z, " |\\/", i)
    expect_equal(split_i(z, " |\\/", i), first)
    expect_equal(to_sentence(first), stringr::str_to_sentence(first))
  }
  expect_equal(word(z, 2), stringr::word(z, 2, 2))
  expect_equal(word(z, 1, 2), stringr::word(z, 1, 2))
  expect_equal(word(z, 1, 3), stringr::word(z, 1, 3))
  expect_equal(re_extract(z, "\\p{L}|\\p{Nd}"), stringr::str_extract(z, "[:alpha:]|[:digit:]"))
  expect_equal(re_extract(z, "\\p{L}\\p{L}|\\p{Nd}"), stringr::str_extract(z, "[:alpha:][:alpha:]|[:digit:]"))
  expect_equal(re_detect(z, "[\\s\\p{Z}\\x85]sp\\.$"), stringr::str_detect(z, "[:space:]sp\\.$"))
  expect_equal(re_detect(z, "[\\s\\p{Z}\\x85]\\/"), stringr::str_detect(z, "\\s\\/"))
  expect_equal(re_count(z, "[^\\s\\p{Z}\\x85]+"), stringr::str_count(z, "\\S+"))
  expect_equal(count_fixed(z, " "), stringr::str_count(z, " "))
  expect_equal(re_replace(z, " \\(.*\\)", ""), stringr::str_remove(z, " \\(.*\\)"))
})
